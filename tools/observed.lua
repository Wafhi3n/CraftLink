---@diagnostic disable: undefined-global
-- tools/observed.lua — ce qu'on a VU en jeu, gardé entre deux régénérations.
--
-- POURQUOI UN FICHIER VERSIONNÉ, et pas l'export de COCScout recollé à la main. Pendant la bêta
-- Forever, Wowhead se tait sur ~940 recettes Camelot ; le joueur qui teste l'addon, lui, ouvre des
-- marchands et parle à des formateurs. Ces réponses vivaient dans une SavedVariable -- une par
-- COMPTE, qu'une réinstallation efface -- et le seul chemin vers les données passait par un
-- copier-coller qu'aucun outil ne relisait : collé dans Data/, il sautait au premier gen_flavor.
-- D'où ce module, et le fichier `tools/Curated/observed_<Saveur>.lua` qu'il tient :
--   · il ACCUMULE et ne retire JAMAIS rien tout seul (un PNJ qu'on n'a pas revu n'a pas disparu) ;
--   · `gen_origins.lua` le relit à CHAQUE passe, donc aucune régénération ne le perd ;
--   · il est commité : le diff git est la relecture humaine que COCScout exigeait avant qu'une
--     observation parte chez les joueurs.
--
-- LA FORME DES ENTRÉES EST CELLE DE `recipeOrigin` : { npcID, areaID, "nom", faction }. Pas un
-- format à nous -- deux formats pour une même donnée finissent toujours par diverger. L'areaID est
-- nil (le jeu donne un uiMapID, pas un AreaID) ; gen_origins le reprend sur la page du PNJ.
--
-- Module PUR : aucune lecture de fichier ici, sauf `load`. Testé par tests/test_observed.lua.

local M = {}

local function round1(v) return v and math.floor(v * 10 + 0.5) / 10 or nil end

-- Une entrée par PNJ dans une liste : trouve la sienne ou l'ajoute. Le nom et le camp ne se
-- remplacent que par une valeur CONNUE -- une observation sans camp n'efface pas un camp relevé.
local function upsert(list, npcID, name, side)
    for _, e in ipairs(list) do
        if e[1] == npcID then
            if name then e[3] = name end
            if side then e[4] = side end
            return e
        end
    end
    local e = { npcID, nil, name or "?", side }
    list[#list + 1] = e
    return e
end

-- Recopie un { map, x, y } relevé, arrondi comme `npcSpot` l'écrit. La dernière relève gagne : un
-- PNJ déplacé par un patch doit pouvoir se corriger au prochain import.
local function setSpot(obs, npcID, map, x, y, name)
    if not (npcID and map and x and y) then return end
    local prev = obs.spot[npcID]
    obs.spot[npcID] = { map, round1(x), round1(y), name or (prev and prev[4]) }
end

function M.empty() return { trainer = {}, vendor = {}, spot = {} } end

-- COCScoutDB -> obs. Les formateurs viennent de `trainers` (une visite PAR PNJ, depuis 0.2.0).
function M.mergeScout(obs, db)
    if type(db) ~= "table" then return 0 end
    local n = 0
    for npcID, t in pairs(db.trainers or {}) do
        for sid in pairs(t.teaches or {}) do
            obs.trainer[sid] = obs.trainer[sid] or {}
            upsert(obs.trainer[sid], npcID, t.name, t.npcSide); n = n + 1
        end
        setSpot(obs, npcID, t.mapID, t.x, t.y, t.name)
    end
    for npcID, v in pairs(db.vendors or {}) do
        -- `v.side` (0.1.0) était le camp du JOUEUR : ignoré. Seul `npcSide` dit celui du PNJ.
        for itemID, price in pairs(v.items or {}) do
            obs.vendor[itemID] = obs.vendor[itemID] or {}
            local e = upsert(obs.vendor[itemID], npcID, v.name, v.npcSide)
            -- Prix inconnu = nil, JAMAIS 0 : 0 ferait un plan gratuit dans le Plan de route.
            if type(price) == "number" and price > 0 then e[5] = price end
            n = n + 1
        end
        setSpot(obs, npcID, v.mapID, v.x, v.y, v.name)
    end
    for npcID, s in pairs(db.spots or {}) do setSpot(obs, npcID, s[1], s[2], s[3], s[4]) end
    return n
end

-- CraftingOrderClassicDB.trainers -> obs. ⚠️ Cette base-là ne garde qu'UN PNJ par métier (le
-- dernier vu) quand `teaches` s'accumule : après deux formateurs d'un métier, le second hérite de
-- ce que le premier enseigne. On ne la prend donc que pour les sorts qu'AUCUNE visite COCScout du
-- même compte n'attribue déjà -- c'est le filet des comptes où COCScout n'était pas chargé.
function M.mergeCoc(obs, db, scoutDB)
    if type(db) ~= "table" then return 0 end
    local precise = {}
    for _, t in pairs((type(scoutDB) == "table" and scoutDB.trainers) or {}) do
        for sid in pairs(t.teaches or {}) do precise[sid] = true end
    end
    local n = 0
    for _, st in pairs(db.trainers or {}) do
        local npc = st.npc
        if npc and npc.id then
            for sid in pairs(st.teaches or {}) do
                if not precise[sid] then
                    obs.trainer[sid] = obs.trainer[sid] or {}
                    upsert(obs.trainer[sid], npc.id, npc.name, nil); n = n + 1
                end
            end
            if not obs.spot[npc.id] then setSpot(obs, npc.id, npc.mapID, npc.x, npc.y, npc.name) end
        end
    end
    return n
end

-- ------------------------------------------------------------------ rendu

local function sortedKeys(t)
    local k = {}
    for id in pairs(t) do k[#k + 1] = id end
    table.sort(k)
    return k
end

local function opt(v, fmt) return v ~= nil and string.format(fmt, v) or "nil" end

local function entry(e, withPrice)
    local s = string.format("{ %d, %s, %q, %s", e[1], opt(e[2], "%d"), e[3] or "?", opt(e[4], "%q"))
    if withPrice then s = s .. ", " .. opt(e[5], "%d") end
    return s .. " }"
end

local function renderLists(out, t, withPrice)
    for _, id in ipairs(sortedKeys(t)) do
        local parts = {}
        for _, e in ipairs(t[id]) do parts[#parts + 1] = entry(e, withPrice) end
        out[#out + 1] = string.format("        [%d] = { %s },", id, table.concat(parts, ", "))
    end
end

function M.render(obs, header)
    local out = { header, "return {" }
    out[#out + 1] = "    -- [spellID] = { { npcID, areaID, \"nom\", faction }, ... } : formateurs VUS l'enseigner"
    out[#out + 1] = "    trainer = {"
    renderLists(out, obs.trainer, false)
    out[#out + 1] = "    },"
    out[#out + 1] = "    -- [itemID] = { { npcID, areaID, \"nom\", faction, cuivre|nil }, ... } : marchands VUS le vendre"
    out[#out + 1] = "    vendor = {"
    renderLists(out, obs.vendor, true)
    out[#out + 1] = "    },"
    out[#out + 1] = "    -- [npcID] = { uiMapID, x, y, \"nom\" } : positions RELEVEES (0-100)"
    out[#out + 1] = "    spot = {"
    for _, id in ipairs(sortedKeys(obs.spot)) do
        local s = obs.spot[id]
        out[#out + 1] = string.format("        [%d] = { %d, %.1f, %.1f, %s },", id, s[1], s[2], s[3], opt(s[4], "%q"))
    end
    out[#out + 1] = "    },"
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
end

-- Le fichier curé d'une saveur, ou une base vide s'il n'existe pas encore.
function M.load(path)
    local f = io.open(path, "rb")
    if not f then return M.empty() end
    f:close()
    local t = dofile(path)
    t.trainer, t.vendor, t.spot = t.trainer or {}, t.vendor or {}, t.spot or {}
    return t
end

return M
