---@diagnostic disable: undefined-global
-- tools/gen_recipe_names.lua — Ajoute aux Data/<flavor>/<Métier>.lua la table `names`
-- (noms ANGLAIS canoniques des recettes QUI PRODUISENT UN OBJET).
--
-- POURQUOI : certains classements ne peuvent se faire que sur le nom, et le nom RUNTIME du client
-- est LOCALISÉ. Cas d'usage d'origine : la Joaillerie. Une gemme taillée s'appelle
-- « <Taille> <Gemme brute> » en anglais (« Stormy Azure Moonstone ») — la TAILLE, toujours le
-- premier mot, porte la stat. En français l'adjectif passe en FIN de nom *et il s'accorde*
-- (« Pierre de lune azur orageu**se** » vs « Œil-de-nuit orageu**x** ») : regrouper sur le nom
-- localisé éclaterait le groupe en deux. Le regroupement doit donc se faire sur l'anglais, exactement
-- comme pour les enchantements (cf. gen_enchant_names.lua, même raison, même remède).
--
-- Source UNIQUE : cache HTML Wowhead tools/wh/<domaine>_<Métier>.html (cf. tools/README.md).
-- On ne retient qu'une ligne du Listview `spells` AVEC un champ `"creates"` (= elle fabrique un
-- objet) et dont l'id est dans le set `recipes` du fichier Data — une page Wowhead liste plus large
-- (contenus retirés, autres saisons). C'est le critère MIROIR de gen_enchant_names.lua, qui ne garde
-- lui QUE les lignes SANS `"creates"` (services sans objet) : les deux tables ne se recouvrent
-- jamais, un métier peut porter les deux.
--
-- IDEMPOTENT : bloc délimité par des sentinelles dédiées (distinctes de gen_metadata.lua et de
-- gen_enchant_names.lua) ; une relance REMPLACE le bloc. NE TOUCHE JAMAIS `recipes` (dataVersion
-- intacte — elle ne dépend que de `recipes` ; vérifier avec `lua tools\check_dataversion.lua`).
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_recipe_names.lua TBC   Jewelcrafting
--   lua tools\gen_recipe_names.lua Wrath Jewelcrafting

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local WH_DIR    = [[tools\wh\]]

local FLAVORS = {
    TBC   = { domain = "tbc" },
    Wrath = { domain = "wotlk" },
    SoD   = { domain = "classic" },
}

local MARK_OPEN  = "    -- >>> gen_recipe_names.lua"
local MARK_CLOSE = "    -- <<< gen_recipe_names.lua"

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

-- Listview `spells` : recettes AVEC objet produit -> { {id, name} }. Les lignes n'ont pas d'accolade
-- imbriquée (creates/reagents sont des `[]`) : on découpe sur les accolades, comme gen_season.lua.
local function parseCrafts(html, recipes)
    local out = {}
    for chunk in html:gmatch("[^{}]+") do
        -- Ancrage sur `learnedat` (comme gen_enchant_names.lua) MAIS avec repli : quelques lignes du
        -- Listview `spells` n'ont pas ce champ (recettes hors arbre de progression — « Silver Rose
        -- Pendant », « Primal Stone Statue »), et l'ancrage seul les perdait EN SILENCE. Le repli
        -- exige `nskillup`, champ propre au Listview des recettes → aucune autre liste de la page
        -- (objets, PNJ) ne peut s'y glisser.
        local id = chunk:match('"id":(%d+),"learnedat":%d+')
                or (chunk:find('"nskillup":', 1, true) and chunk:match('"id":(%d+),'))
        id = id and tonumber(id)
        if id and recipes[id] and chunk:find('"creates":', 1, true) then
            local name = chunk:match('"name":"([^"]*)"')
            -- Un backslash dans le nom casserait la chaîne Lua émise : on écarte plutôt que d'inventer
            -- un échappement (aucun cas relevé — la garde est là pour ne pas produire un fichier mort).
            if name and name ~= "" and not name:find("\\", 1, true) then
                out[#out + 1] = { id = id, name = name }
            end
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
    out[#out + 1] = "    -- Noms ANGLAIS canoniques des recettes qui produisent un objet : source robuste"
    out[#out + 1] = "    -- d'un classement dérivé du NOM, indépendante de la langue du client."
    out[#out + 1] = "    names = {"
    for _, e in ipairs(list) do
        out[#out + 1] = string.format('        { id = %d, name = "%s" },', e.id, e.name)
    end
    out[#out + 1] = "    },"
    out[#out + 1] = MARK_CLOSE
    return table.concat(out, "\n")
end

-- Remplace le bloc sentinellisé existant, ou l'insère avant le "})" final (même mécanique que
-- gen_enchant_names.lua — les blocs coexistent sans se voir).
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
local prof   = arg and arg[2] or error("métier requis (nom de fichier Data, ex. Jewelcrafting)")
local cfg = FLAVORS[flavor] or error("saveur inconnue : " .. tostring(flavor) .. " (TBC|Wrath|SoD)")

local path    = DATA_ROOT .. flavor .. "\\" .. prof .. ".lua"
local content = assert(readFile(path), "fichier data absent : " .. path)
local whPath  = WH_DIR .. cfg.domain .. "_" .. prof .. ".html"
local html    = assert(readFile(whPath), "cache Wowhead manquant : " .. whPath)
local recipes = assert(recipesSet(content), "bloc recipes introuvable dans " .. path)

local list = parseCrafts(html, recipes)
assert(#list > 0, "aucune recette nommée — cache Wowhead vide ou format changé : " .. whPath)
writeFile(path, upsertUnit(content, renderUnit(list, "Wowhead " .. cfg.domain)))

print(string.format("[OK] %s/%s : %d recette(s) nommée(s) sur %d au catalogue.",
    flavor, prof, #list, (function() local n = 0; for _ in pairs(recipes) do n = n + 1 end; return n end)()))
