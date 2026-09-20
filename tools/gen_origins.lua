---@diagnostic disable: undefined-global
-- tools/gen_origins.lua — QUI est derrière un plan, lu sur la page de l'OBJET.
--
-- POURQUOI UN SECOND OUTIL. `gen_sources.lua` lit la page de MÉTIER : une ligne par objet-recette,
-- avec sa nature (`source`) et, quand la page veut bien, UN nom dans `sourcemore`. Sur Camelot ça
-- laisse 457 recettes avec une nature et personne en face -- « Vendeur », point. Or la page de
-- l'OBJET, elle, porte la liste complète : `sold-by`, `dropped-by`, `reward-from-q`, chacune avec
-- l'identifiant du PNJ, son AreaID, son nom et sa FACTION.
--
-- LA FACTION EST LA VRAIE RAISON, plus encore que la couverture. `sourcemore` rend le premier PNJ
-- venu, sans dire de quel camp il est : pour « Recipe: Gingerbread Cookie » c'est Wulmort
-- Jinglepocket, à Forgefer. Un joueur de la Horde était donc envoyé en territoire allié, avec
-- aplomb. C'est exactement le défaut qui avait déjà été corrigé du temps de MTSL ; la page de métier
-- seule ne permet pas de ne pas le refaire.
--
-- CE QU'ON PREND, ET RIEN DE PLUS :
--   · `sold-by`       -> npcID, AreaID, nom anglais, faction, et le PRIX (`cost`) ;
--   · `dropped-by`    -> npcID, AreaID, nom, et le taux (`count`/`outof`) pour trier les meilleurs ;
--   · `reward-from-q` -> questID, nom, côté. Pas de zone : Wowhead n'en attache pas à une quête.
--
-- ⚠️ `recipeOrigin` APPARTIENT À CET OUTIL, plus à gen_sources. Deux outils qui écrivent la même
-- table finissent par se contredire, et le perdant est toujours celui qui tourne en premier.
-- gen_sources ne garde que `recipeSource` (la NATURE) ; ici c'est QUI. Quand la page d'un objet
-- manque du cache, on retombe sur ce que la page de métier savait : un nom sans faction vaut mieux
-- que rien, et il est marqué comme tel (faction nil = on ne sait pas, pas « neutre »).
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_origins.lua Camelot -urls    # les pages à télécharger (cf. fetch_items.ps1)
--   lua tools\gen_origins.lua Camelot -check   # mesurer la couverture, ne rien écrire
--   lua tools\gen_origins.lua Camelot          # écrire recipeOrigin + recipePrice

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local ITEM_DIR  = [[tools\wh\items\]]

local FLAVORS = {
    Vanilla = { domain = "classic", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Leatherworking", "Mining", "Poisons", "Tailoring" } },
    TBC     = { domain = "tbc", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Jewelcrafting", "Leatherworking", "Mining", "Tailoring" } },
    Wrath   = { domain = "wotlk", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Inscription", "Jewelcrafting", "Leatherworking",
                "Mining", "Tailoring" } },
    SoD     = { domain = "classic", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Leatherworking", "Mining", "Tailoring" } },
    Camelot = { domain = "forever", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Leatherworking", "Mining", "Tailoring" } },
}

-- Combien de PNJ on garde PAR CAMP. Deux suffisent : le joueur en veut un, le second couvre le cas
-- où le premier a été déplacé ou tué par un patch. Au-delà on gonfle les fichiers de données pour
-- une infobulle qui n'affiche qu'une ligne.
local KEEP_PER_SIDE = 2
local KEEP_DROPS    = 3   -- triés par taux : les trois meilleurs, pas les trois premiers venus

local MARK_OPEN  = "    -- >>> gen_origins.lua"
local MARK_CLOSE = "    -- <<< gen_origins.lua"

local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local function writeFile(p, c)
    local f = assert(io.open(p, "wb")); f:write(c); f:close()
end

-- ------------------------------------------------------------------
-- Lecture des fichiers de données
-- ------------------------------------------------------------------

local function block(content, name)
    return content:match(name .. "%s*=%s*(%b{})") or ""
end

-- sort -> objet-recette (inverse de taughtBy, qui va de l'objet vers le sort).
local function itemOf(content)
    local out = {}
    for item, spell in block(content, "taughtBy"):gmatch("%[(%d+)%]%s*=%s*(%d+)") do
        out[tonumber(spell)] = tonumber(item)
    end
    return out
end

local function kinds(content)
    local out = {}
    for sid, k in block(content, "recipeSource"):gmatch("%[(%d+)%]%s*=%s*\"(%w+)\"") do
        out[tonumber(sid)] = k
    end
    return out
end

-- Le repli : ce que la page de MÉTIER savait déjà (un PNJ, sans faction). Lu dans le bloc que
-- gen_sources écrivait avant que cette table ne change de propriétaire -- il peut donc être absent.
local function legacyOrigin(content)
    local out = {}
    for sid, body in block(content, "recipeOrigin"):gmatch("%[(%d+)%]%s*=%s*(%b{})") do
        local id, area, name = body:match("{%s*(%d+)%s*,%s*([%d]*n?i?l?)%s*,%s*\"([^\"]*)\"")
        if id then out[tonumber(sid)] = { tonumber(id), tonumber(area), name } end
    end
    return out
end

-- ------------------------------------------------------------------
-- Lecture d'une page d'objet
-- ------------------------------------------------------------------

-- Les lignes d'une Listview nommée, à accolades ÉQUILIBRÉES : chaque ligne imbrique `modes` et
-- `itemSeasonPhaseData`, un découpage naïf les couperait en plein milieu.
local function listviewRows(html, lvid)
    local at = html:find("id: '" .. lvid .. "'", 1, true)
    if not at then return {} end
    local s = html:find("data: [", at, true)
    if not s then return {} end
    local out, i, depth, start = {}, s + 7, 0, nil
    while i <= #html do
        local c = html:sub(i, i)
        if c == "{" then
            if depth == 0 then start = i end
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 and start then out[#out + 1] = html:sub(start, i); start = nil end
        elseif c == "]" and depth == 0 then
            break
        end
        i = i + 1
    end
    return out
end

-- "A" (Alliance seule) | "H" (Horde seule) | nil (les deux, ou hostile aux deux : une créature).
local function sideOf(row)
    local r = row:match('"react":%[([^%]]*)%]')
    if not r then return nil end
    local a, h = r:match("([^,]+),([^,]+)")
    local na, nh = tonumber(a), tonumber(h)
    if na and na > 0 and not nh then return "A" end
    if nh and nh > 0 and not na then return "H" end
    return nil
end

-- `"name":"…"` et pas `"displayName":"…"` : la casse du D majuscule suffit à les distinguer, et
-- `"names":[]` ne matche pas non plus (le motif exige le guillemet fermant du champ).
local function nameOf(row) return row:match('"name":"([^"]*)"') end

-- Un PNJ vendeur : { npcID, areaID, nom, faction }, plus le prix en cuivre à part.
local function soldBy(html)
    local out, price = {}, nil
    for _, row in ipairs(listviewRows(html, "sold-by")) do
        local id   = tonumber(row:match('"id":(%d+)'))
        local area = tonumber(row:match('"location":%[(%d+)'))
        local name = nameOf(row)
        if id and name then out[#out + 1] = { id, area, name, sideOf(row) } end
        price = price or tonumber(row:match('"cost":%[%[(%d+)'))
    end
    return out, price
end

-- Les créatures qui lâchent le plan, TRIÉES PAR TAUX décroissant. Wowhead les rend dans l'ordre de
-- sa page ; envoyer le joueur sur la première venue plutôt que sur la plus généreuse serait un
-- conseil au hasard. `count`/`outof` sont le premier couple de la ligne (ceux de `modes` répètent).
local function droppedBy(html)
    local out = {}
    for _, row in ipairs(listviewRows(html, "dropped-by")) do
        local id   = tonumber(row:match('"id":(%d+)'))
        local name = nameOf(row)
        if id and name then
            local c, o = tonumber(row:match('"count":(%d+)')), tonumber(row:match('"outof":(%d+)'))
            out[#out + 1] = { id, tonumber(row:match('"location":%[(%d+)')), name, sideOf(row),
                              rate = (c and o and o > 0) and (c / o) or 0 }
        end
    end
    table.sort(out, function(a, b) return a.rate > b.rate end)
    return out
end

-- Les quêtes qui donnent le plan. `side` 1 = Alliance, 2 = Horde, absent = les deux. AUCUNE zone :
-- Wowhead n'attache pas d'AreaID à une quête, et `category` est un identifiant à lui, pas du jeu.
local function questsFor(html)
    local out = {}
    for _, row in ipairs(listviewRows(html, "reward-from-q")) do
        local id, name = tonumber(row:match('"id":(%d+)')), nameOf(row)
        if id and name then
            local side = tonumber(row:match('"side":(%d+)'))
            out[#out + 1] = { id, nil, name, (side == 1 and "A") or (side == 2 and "H") or nil }
        end
    end
    return out
end

-- ------------------------------------------------------------------
-- Choix des entrées gardées
-- ------------------------------------------------------------------

-- Au plus KEEP_PER_SIDE par CAMP, dans l'ordre de la page. Garder les N premiers tout court
-- renverrait les deux factions chez les mêmes PNJ alliés quand la page les liste d'abord.
local function keepBothSides(list)
    local seen, out = { A = 0, H = 0, N = 0 }, {}
    for _, e in ipairs(list) do
        local bucket = e[4] or "N"
        if seen[bucket] < KEEP_PER_SIDE then
            seen[bucket] = seen[bucket] + 1
            out[#out + 1] = e
        end
    end
    return out
end

-- Ce qu'on retient pour UNE recette, selon sa nature. nil = la page ne dit rien d'exploitable.
local function originsFor(kind, html)
    if kind == "vendor" then
        local list, price = soldBy(html)
        return keepBothSides(list), price
    elseif kind == "drop" then
        local list = droppedBy(html)
        local cut = {}
        for i = 1, math.min(#list, KEEP_DROPS) do cut[i] = list[i] end
        return cut, nil
    elseif kind == "quest" then
        return keepBothSides(questsFor(html)), nil
    end
    return {}, nil
end

-- ------------------------------------------------------------------
-- Rendu
-- ------------------------------------------------------------------

local function renderEntry(e)
    return string.format("{ %d, %s, %q, %s }", e[1],
        e[2] and tostring(e[2]) or "nil", e[3], e[4] and string.format("%q", e[4]) or "nil")
end

local function renderUnit(origins, prices, note)
    local sids = {}
    for sid in pairs(origins) do sids[#sids + 1] = sid end
    table.sort(sids)
    local out = { MARK_OPEN .. " (généré — " .. note .. " ; ne pas éditer à la main)" }
    out[#out + 1] = "    -- QUI est derrière le plan : [spellID] = { { id, areaID, \"nom\", faction }, ... }"
    out[#out + 1] = "    -- faction \"A\"/\"H\" = ce camp SEULEMENT ; nil = les deux, ou inconnue."
    out[#out + 1] = "    -- Le SENS des entrées vient de `recipeSource` : marchand, créature, ou quête."
    out[#out + 1] = "    recipeOrigin = {"
    for _, sid in ipairs(sids) do
        local parts = {}
        for _, e in ipairs(origins[sid]) do parts[#parts + 1] = renderEntry(e) end
        out[#out + 1] = string.format("        [%d] = { %s },", sid, table.concat(parts, ", "))
    end
    out[#out + 1] = "    },"
    local psids = {}
    for sid in pairs(prices) do psids[#psids + 1] = sid end
    table.sort(psids)
    out[#out + 1] = "    -- PRIX du plan chez son marchand, en cuivre. Absent = inconnu, JAMAIS zéro."
    out[#out + 1] = "    recipePrice = {"
    for _, sid in ipairs(psids) do
        out[#out + 1] = string.format("        [%d] = %d,", sid, prices[sid])
    end
    out[#out + 1] = "    },"
    out[#out + 1] = MARK_CLOSE
    return table.concat(out, "\n")
end

local function upsertUnit(content, unit)
    local s = content:find(MARK_OPEN, 1, true)
    if s then
        local e = content:find(MARK_CLOSE, s, true)
        assert(e, "sentinelle ouvrante sans fermante — fichier à réparer à la main")
        local rest = content:sub(e + #MARK_CLOSE):gsub("^\n?", "")
        return content:sub(1, s - 1) .. unit .. "\n" .. rest
    end
    content = content:gsub("%s*$", "")
    assert(content:sub(-2) == "})", "le fichier ne se termine pas par '})'")
    return content:sub(1, -3) .. "\n" .. unit .. "\n})\n"
end

-- ------------------------------------------------------------------
-- Main
-- ------------------------------------------------------------------

local flavor, mode = "Camelot", nil
for i = 1, #(arg or {}) do
    if arg[i] == "-urls" or arg[i] == "-check" then mode = arg[i]
    elseif arg[i] then flavor = arg[i] end
end
local cfg = FLAVORS[flavor] or error("saveur inconnue : " .. tostring(flavor))

local tot = { want = 0, have = 0, named = 0, legacy = 0, price = 0, empty = 0 }

for _, prof in ipairs(cfg.profs) do
    local path    = DATA_ROOT .. flavor .. [[\]] .. prof .. ".lua"
    local content = readFile(path)
    if not content then
        if mode ~= "-urls" then print("SKIP " .. prof .. " (fichier data absent)") end
    else
        local items, kind, legacy = itemOf(content), kinds(content), legacyOrigin(content)
        local origins, prices, have, named, fromLegacy, empty = {}, {}, 0, 0, 0, 0
        for sid, k in pairs(kind) do
            local itemID = items[sid]
            if itemID then
                tot.want = tot.want + 1
                local cache = ITEM_DIR .. cfg.domain .. "_" .. itemID .. ".html"
                if mode == "-urls" then
                    print(cache .. "\t" .. "https://www.wowhead.com/" .. cfg.domain .. "/item=" .. itemID)
                else
                    local html = readFile(cache)
                    if html then
                        have = have + 1
                        local list, price = originsFor(k, html)
                        if #list > 0 then origins[sid] = list; named = named + 1
                        else empty = empty + 1 end
                        if price then prices[sid] = price end
                    elseif legacy[sid] then
                        origins[sid] = { legacy[sid] }; fromLegacy = fromLegacy + 1
                    end
                end
            end
        end
        if mode ~= "-urls" then
            tot.have, tot.named = tot.have + have, tot.named + named
            tot.legacy, tot.empty = tot.legacy + fromLegacy, tot.empty + empty
            for _ in pairs(prices) do tot.price = tot.price + 1 end
            if mode ~= "-check" then writeFile(path, upsertUnit(content, renderUnit(origins, prices,
                "Wowhead " .. cfg.domain .. ", pages d'objet"))) end
            print(string.format("%-16s pages=%-4d nommees=%-4d (repli page-metier=%-3d, muettes=%-3d) prix=%d",
                prof, have, named, fromLegacy, empty, (function() local n = 0
                    for _ in pairs(prices) do n = n + 1 end; return n end)()))
        end
    end
end

if mode ~= "-urls" then
    print(string.format("%s (%s) : %d recettes sourcees, %d pages en cache -> %d nommees, %d par repli, %d muettes, %d prix%s",
        (mode == "-check") and "Mesure" or "Termine", flavor, tot.want, tot.have, tot.named,
        tot.legacy, tot.empty, tot.price, (mode == "-check") and " (rien ecrit)" or ""))
end
