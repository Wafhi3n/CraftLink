---@diagnostic disable: undefined-global
-- tools/gen_enchant_names.lua — Ajoute aux Data/<flavor>/Enchanting.lua la table `enchants`
-- (noms ANGLAIS canoniques des services sans objet, « Enchant <Slot> - <Effet> »).
--
-- POURQUOI : seul Vanilla portait cette table (émise par gen_professions.lua). Les couches TBC/
-- Wrath/SoD ne listaient que des spellID → le classement par emplacement/stat de COC (_Enchant.lua)
-- retombait sur le nom RUNTIME, LOCALISÉ, du client : il ne marchait que sur un client anglais
-- (constaté en jeu 2026-07-16 : tous les enchants SoD en « Autres » sur client FR). Cette table
-- rend le classement indépendant de la langue du client, comme pour Vanilla.
--
-- Source UNIQUE : cache HTML Wowhead tools/wh/<domaine>_Enchanting.html (cf. tools/README.md).
-- Une ligne du Listview `spells` SANS champ `"creates"` = service sans objet (même critère que
-- gen_professions.lua). Restreint au set `recipes` du fichier Data (une page Wowhead liste plus
-- large : SoD sur le domaine classic, contenus retirés…).
--
-- IDEMPOTENT : bloc délimité par des sentinelles dédiées (distinctes de gen_metadata.lua) ; une
-- relance REMPLACE le bloc. NE TOUCHE JAMAIS `recipes` (dataVersion intacte — elle ne dépend que
-- de `recipes` ; vérifier avec `lua tools\check_dataversion.lua` avant/après).
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_enchant_names.lua TBC     # domaine tbc
--   lua tools\gen_enchant_names.lua Wrath   # domaine wotlk
--   lua tools\gen_enchant_names.lua SoD     # domaine classic (le set recipes du fichier SoD filtre)

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local WH_DIR    = [[tools\wh\]]

local FLAVORS = {
    TBC   = { domain = "tbc" },
    Wrath = { domain = "wotlk" },
    SoD   = { domain = "classic" },
}

local MARK_OPEN  = "    -- >>> gen_enchant_names.lua"
local MARK_CLOSE = "    -- <<< gen_enchant_names.lua"

local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local function writeFile(p, c)
    local f = assert(io.open(p, "wb")); f:write(c); f:close()
end

-- Set des spellID du bloc `recipes` du fichier (garde : on ne nomme QUE le catalogue du fichier).
local function recipesSet(content)
    local block = content:match("recipes%s*=%s*(%b{})")
    if not block then return nil end
    local set = {}
    for id in block:gmatch("%d+") do set[tonumber(id)] = true end
    return set
end

-- Listview `spells` : services sans objet (« Enchant … », pas de champ "creates") -> { {id, name} }.
-- Les lignes du Listview n'ont pas d'accolade imbriquée (creates/reagents sont des `[]`) : on
-- découpe sur les accolades, comme gen_season.lua.
local function parseEnchantServices(html, recipes)
    local out = {}
    for chunk in html:gmatch("[^{}]+") do
        local id = chunk:match('"id":(%d+),"learnedat":%d+')
        id = id and tonumber(id)
        if id and recipes[id] and not chunk:find('"creates":', 1, true) then
            local name = chunk:match('"name":"([^"]*)"')
            if name and name ~= "" then out[#out + 1] = { id = id, name = name } end
        end
    end
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return out
end

local function renderUnit(list, sourceNote)
    local out = { MARK_OPEN .. " (généré — " .. sourceNote .. " ; ne pas éditer à la main)" }
    out[#out + 1] = "    -- Noms ANGLAIS canoniques des services sans objet (« Enchant <Slot> - <Effet> ») :"
    out[#out + 1] = "    -- source robuste du classement par emplacement/stat, indépendante de la langue du client."
    out[#out + 1] = "    enchants = {"
    for _, e in ipairs(list) do
        out[#out + 1] = string.format('        { id = %d, name = "%s" },', e.id, e.name)
    end
    out[#out + 1] = "    },"
    out[#out + 1] = MARK_CLOSE
    return table.concat(out, "\n")
end

-- Remplace le bloc sentinellisé existant, ou l'insère avant le "})" final (même mécanique que
-- gen_metadata.lua — les deux blocs coexistent sans se voir).
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

local flavor = arg and arg[1] or error("saveur requise : TBC | Wrath | SoD")
local cfg = FLAVORS[flavor] or error("saveur inconnue : " .. tostring(flavor) .. " (TBC|Wrath|SoD)")

local path    = DATA_ROOT .. flavor .. [[\Enchanting.lua]]
local content = assert(readFile(path), "fichier data absent : " .. path)
local html    = assert(readFile(WH_DIR .. cfg.domain .. "_Enchanting.html"),
                       "cache Wowhead manquant : " .. WH_DIR .. cfg.domain .. "_Enchanting.html")
local recipes = assert(recipesSet(content), "bloc recipes introuvable dans " .. path)

local list = parseEnchantServices(html, recipes)
writeFile(path, upsertUnit(content, renderUnit(list, "Wowhead " .. cfg.domain)))

local named = 0
for _, e in ipairs(list) do if e.name:find("^Enchant%s") then named = named + 1 end end
print(string.format("[OK] %s : %d service(s) sans objet nommé(s), dont %d « Enchant … » (classables).",
    flavor, #list, named))
