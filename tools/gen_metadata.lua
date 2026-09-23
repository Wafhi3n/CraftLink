---@diagnostic disable: undefined-global
-- tools/gen_metadata.lua — Complète les MÉTADONNÉES manquantes des Data/<flavor>/*.lua :
--   * learnedAt : spellID -> niveau de métier où la recette s'apprend
--   * taughtBy  : itemID de l'objet-plan (recette/formule/schéma/patron) -> spellID enseigné
--     (le chaînon manquant de l'alerte « plan looté » et du flux « proposer un don »)
--
-- Source UNIQUE : cache HTML Wowhead tools/wh/<domaine>_<Métier>.html (une page skill par
-- métier — cf. tools/README.md pour la boucle curl). La même page fournit :
--   * le Listview `spells`       -> "learnedat" (+ nom du sort)
--   * le Listview `recipe-items` -> objets-plans (classs:9) « Recipe: X » / « Formula: X » ...
-- taughtBy = jointure par NOM (préfixe « Xxx: » retiré) entre les deux listviews : Wowhead
-- n'expose pas le lien plan->sort en direct sur ces pages. Les non-appariés sont listés.
--
-- IDEMPOTENT : le bloc généré est délimité par des sentinelles `-- >>> gen_metadata.lua` /
-- `-- <<< gen_metadata.lua` ; une relance REMPLACE le bloc au lieu d'empiler des doublons.
-- NE TOUCHE JAMAIS `recipes` : la dataVersion (empreinte des spellID triés, Vanilla figée
-- 1792301894) reste intacte — computeDataVersion ne lit que `recipes`. Les métadonnées sont
-- de plus RESTREINTES au set `recipes` du fichier (une page Wowhead peut lister plus large :
-- recettes SoD, contenus retirés...).
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_metadata.lua            # Vanilla (cache tools\wh\classic_*.html)
--   lua tools\gen_metadata.lua TBC        # TBC    (cache tools\wh\tbc_*.html)
--   lua tools\gen_metadata.lua Wrath      # Wrath  (cache tools\wh\wotlk_*.html)
--   lua tools\gen_metadata.lua Camelot    # Camelot (cache tools\wh\forever_*.html)

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local WH_DIR    = [[tools\wh\]]

-- Le DOMAINE Wowhead se declare (il ne se devine pas) ; les METIERS, eux, se DECOUVRENT dans
-- Data/<Saveur>/. Ils etaient ecrits a la main ici, et Camelot n'y figurait simplement pas : c'est
-- la seule raison pour laquelle cette passe n'avait jamais tourne sur la saveur qu'on developpe.
-- Verifie avant bascule le 2026-09-23 : la decouverte rend EXACTEMENT les listes declarees pour
-- Vanilla, TBC et Wrath. Meme lecon que la decouverte des .toc et celle des tests.
local FLAVORS = {
    Vanilla = { domain = "classic" },
    TBC     = { domain = "tbc" },
    Wrath   = { domain = "wotlk" },
    Camelot = { domain = "forever" },
}

-- Antislash fabrique par code : ecrit en dur, il arrive parfois simple ou double selon l'outil
-- d'edition qui a transite le fichier.
local BS = string.char(92)

local function professionsOf(flavor)
    local out = {}
    local pipe = io.popen('dir /b "' .. DATA_ROOT .. flavor .. BS .. '*.lua"')
    if not pipe then return out end
    for line in pipe:lines() do
        local name = line:gsub("%s+$", ""):match("^(.+)%.lua$")
        if name then out[#out + 1] = name end
    end
    pipe:close()
    table.sort(out)
    return out
end

local MARK_OPEN  = "    -- >>> gen_metadata.lua"
local MARK_CLOSE = "    -- <<< gen_metadata.lua"

-- ------------------------------------------------------------------
-- E/S et parsing des fichiers Data existants
-- ------------------------------------------------------------------
local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local function writeFile(p, c)
    local f = assert(io.open(p, "wb")); f:write(c); f:close()
end

-- Set des spellID du bloc `recipes` figé du fichier (garde : on n'annote QUE le catalogue).
local function recipesSet(content)
    local block = content:match("recipes%s*=%s*(%b{})")
    if not block then return nil end
    local set, n = {}, 0
    for id in block:gmatch("%d+") do set[tonumber(id)] = true; n = n + 1 end
    return set, n
end

-- Paires [k] = v d'un bloc nommé existant (itemToSpell / produces), pour l'audit.
local function pairsOfBlock(content, key)
    local block = content:match(key .. "%s*=%s*(%b{})")
    local out = {}
    if block then
        for k, v in block:gmatch("%[(%d+)%]%s*=%s*(%d+)") do out[tonumber(k)] = tonumber(v) end
    end
    return out
end

-- ------------------------------------------------------------------
-- Parsing du HTML Wowhead (les clés JSON des lignes Listview sont triées alphabétiquement,
-- d'où la fiabilité des adjacences ci-dessous ; [^{}]- reste dans l'objet courant)
-- ------------------------------------------------------------------
-- Listview `spells` : learnedAt[spellID] + index nom(minuscule) -> spellID pour la jointure.
local function parseSpells(html)
    local learnedAt, byName, dupes = {}, {}, {}
    for id, at, name in html:gmatch('"id":(%d+),"learnedat":(%d+)[^{}]-"name":"([^"]*)"') do
        id = tonumber(id)
        learnedAt[id] = tonumber(at)
        local key = name:lower()
        if byName[key] and byName[key] ~= id then dupes[key] = true else byName[key] = id end
    end
    for key in pairs(dupes) do byName[key] = nil end  -- nom ambigu : on ne joint pas dessus
    return learnedAt, byName
end

-- Listview `recipe-items` (classs:9) : liste { itemID, nom sans préfixe « Xxx: » }.
local function parseRecipeItems(html)
    local out = {}
    for id, name in html:gmatch('"classs":9[^{}]-"id":(%d+)[^{}]-"name":"([^"]*)"') do
        local taught = name:match("^[^:]+:%s*(.+)$")
        if taught then out[#out + 1] = { item = tonumber(id), name = taught } end
    end
    return out
end

-- Page -> { learnedAt = {sid=N}, taughtBy = {item=sid}, unmatched = {noms...} }.
local function parseWowhead(html, recipes)
    local learnedAt, byName = parseSpells(html)
    local taughtBy, unmatched = {}, {}
    for _, ri in ipairs(parseRecipeItems(html)) do
        local sid = byName[ri.name:lower()]
        if sid and recipes[sid] then taughtBy[ri.item] = sid
        elseif not sid then unmatched[#unmatched + 1] = ri.name end
    end
    return { learnedAt = learnedAt, taughtBy = taughtBy, unmatched = unmatched }
end

-- ------------------------------------------------------------------
-- Écriture du bloc sentinellisé (remplacement ou insertion avant le "})" final)
-- ------------------------------------------------------------------
-- Le fichier declare-t-il DEJA learnedAt hors de notre bloc ? (On retire le notre avant de
-- regarder, sinon une relance se repondrait a elle-meme.)
local function stripUnit(content)
    local i = content:find(MARK_OPEN, 1, true); if not i then return content end
    local j = content:find(MARK_CLOSE, i, true); if not j then return content end
    return content:sub(1, i - 1) .. content:sub(j + #MARK_CLOSE)
end

-- UNE table, UN proprietaire. Sur les saveurs recentes (Camelot), c'est gen_flavor.lua qui ecrit
-- DEJA learnedAt ET taughtBy dans le corps du fichier. Les reecrire ici poserait une SECONDE cle
-- du meme nom dans la meme table Lua, ou seul le dernier gagne selon l'ordre du TEXTE — un
-- ecrasement que rien n'annonce.
--
-- Mesure du 2026-09-23 sur les 9 metiers Camelot, table par table :
--   learnedAt : identiques (0 perdu, 0 ajoute, 0 valeur differente) — les deux outils lisent la
--               meme page Wowhead, le doublon n'apportait rien ;
--   taughtBy  : gen_metadata n'apporte RIEN et PERD 8 entrees (1 Alchimie, 1 Travail du cuir,
--               6 Couture). Ces 8 sont exactement ce dont l'alerte « plan loote » a besoin.
-- Conclusion : sur une saveur ou gen_flavor ecrit deja ces tables, cette passe n'a plus d'objet.
-- On cede la main table par table plutot que de refuser la saveur en bloc : le jour ou un
-- generateur cesse d'ecrire l'une d'elles, celle-ci redevient la notre sans qu'on y pense.
local function renderUnit(meta, recipes, sourceNote, skipLearnedAt, skipTaughtBy)
    local la, tb = {}, {}
    for sid in pairs(meta.learnedAt) do
        if recipes[sid] then la[#la + 1] = sid end
    end
    table.sort(la)
    for itemID, sid in pairs(meta.taughtBy) do
        if recipes[sid] then tb[#tb + 1] = itemID end
    end
    table.sort(tb)

    if skipLearnedAt then la = {} end
    if skipTaughtBy  then tb = {} end
    -- Rien a dire = rien a ecrire. Un bloc sentinelle vide n'est pas une information, c'est du
    -- bruit dans un fichier genere : il ferait croire a un traitement la ou il n'y a rien.
    if #la == 0 and #tb == 0 then return nil, 0, 0 end

    local out = { MARK_OPEN .. " (généré — " .. sourceNote .. " ; ne pas éditer à la main)" }
    if skipLearnedAt or skipTaughtBy then
        out[#out + 1] = "    -- Tables cedees a gen_flavor.lua (ce fichier les declare deja) : "
            .. (skipLearnedAt and "learnedAt " or "") .. (skipTaughtBy and "taughtBy" or "")
    end
    if #la > 0 then
        out[#out + 1] = "    -- niveau de métier où la recette s'apprend : [spellID] = niveau"
        out[#out + 1] = "    learnedAt = {"
        for _, sid in ipairs(la) do out[#out + 1] = string.format("        [%d] = %d,", sid, meta.learnedAt[sid]) end
        out[#out + 1] = "    },"
    end
    if #tb > 0 then
        out[#out + 1] = "    -- objet-plan (recette/formule/schéma) -> spellID enseigné (alerte loot / dons)"
        out[#out + 1] = "    taughtBy = {"
        for _, itemID in ipairs(tb) do out[#out + 1] = string.format("        [%d] = %d,", itemID, meta.taughtBy[itemID]) end
        out[#out + 1] = "    },"
    end
    out[#out + 1] = MARK_CLOSE
    return table.concat(out, "\n"), #la, #tb
end

local function upsertUnit(content, unit)
    local s = content:find(MARK_OPEN, 1, true)
    if s then
        local e = content:find(MARK_CLOSE, s, true)
        assert(e, "sentinelle ouvrante sans fermante — fichier à réparer à la main")
        -- On normalise le saut de ligne après la sentinelle fermante au lieu de le consommer
        -- aveuglément : idempotent, et répare un éventuel état « })  collé » antérieur.
        local rest = content:sub(e + #MARK_CLOSE):gsub("^\n?", "")
        return content:sub(1, s - 1) .. unit .. "\n" .. rest
    end
    content = content:gsub("%s*$", "")
    assert(content:sub(-2) == "})", "le fichier ne se termine pas par '})'")
    return content:sub(1, -3) .. "\n" .. unit .. "\n})\n"
end

-- ------------------------------------------------------------------
-- Audit : entrées d'itemToSpell qui sont en réalité des objets-PLANS (retombée du fallback
-- MTSL `items` de gen_professions.lua — `items` y est l'objet qui ENSEIGNE, pas le produit).
-- ------------------------------------------------------------------
local function auditItemToSpell(content, meta)
    local i2s      = pairsOfBlock(content, "itemToSpell")
    local produces = pairsOfBlock(content, "produces")
    local bad = {}
    for itemID, sid in pairs(i2s) do
        if meta.taughtBy[itemID] == sid and produces[sid] ~= itemID then
            bad[#bad + 1] = string.format("%d->%d", itemID, sid)
        end
    end
    table.sort(bad)
    return bad
end

-- ------------------------------------------------------------------
-- Main
-- ------------------------------------------------------------------
local flavor = arg and arg[1] or "Vanilla"
local cfg = FLAVORS[flavor] or error("saveur inconnue : " .. tostring(flavor) .. " (Vanilla|TBC|Wrath|Camelot)")
cfg.profs = professionsOf(flavor)
if #cfg.profs == 0 then error("aucun fichier de metier dans " .. DATA_ROOT .. flavor) end

local totalLA, totalTB = 0, 0

for _, prof in ipairs(cfg.profs) do
    local path    = DATA_ROOT .. flavor .. [[\]] .. prof .. ".lua"
    local content = readFile(path)
    local htmlPath = WH_DIR .. cfg.domain .. "_" .. prof .. ".html"
    local html    = readFile(htmlPath)
    if not content then print("SKIP " .. prof .. " (fichier data absent : " .. path .. ")")
    elseif not html then print("SKIP " .. prof .. " (cache " .. htmlPath .. " manquant)")
    else
        local recipes, nRec = recipesSet(content)
        if not recipes then print("SKIP " .. prof .. " (bloc recipes introuvable)") else
            local meta = parseWowhead(html, recipes)
            local body   = stripUnit(content)
            local ownsLA = body:find("learnedAt = {", 1, true) ~= nil
            local ownsTB = body:find("taughtBy = {", 1, true) ~= nil
            local unit, nLA, nTB = renderUnit(meta, recipes, "Wowhead " .. cfg.domain, ownsLA, ownsTB)
            if unit then writeFile(path, upsertUnit(content, unit)) end
            totalLA = totalLA + nLA; totalTB = totalTB + nTB
            local audit = auditItemToSpell(content, meta)
            print(string.format("%-16s recettes=%-4d learnedAt=%-8s taughtBy=%-8s plans-non-appariés=%d%s",
                prof, nRec, ownsLA and "(flavor)" or tostring(nLA),
                ownsTB and "(flavor)" or tostring(nTB), #meta.unmatched,
                (#audit > 0) and ("  [AUDIT] itemToSpell pollué par " .. #audit .. " objet(s)-plan") or ""))
            if #meta.unmatched > 0 and #meta.unmatched <= 5 then
                print("                 non-appariés : " .. table.concat(meta.unmatched, " | "))
            end
        end
    end
end

print(string.format("Terminé (%s) : %d learnedAt, %d taughtBy au total.", flavor, totalLA, totalTB))
