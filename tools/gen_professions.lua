-- tools/gen_professions.lua
-- Convertisseur HORS-LIGNE (non packagé) : génère CraftLink-1.0/Data/Vanilla/*.lua à partir de la
-- base de MissingTradeSkillsList (MTSL), déjà installée dans le dossier AddOns de WoW.
--
-- MTSL (data/skills.lua) liste TOUTES les recettes des 13 métiers Classic (apprises ou non),
-- avec l'itemID produit + noms localisés. On bake ces données chez nous → zéro dépendance
-- runtime à MTSL. Source : MissingTradeSkillsList par Thumbkin (faits de jeu : itemID→nom).
--
-- Usage (depuis f:\AddonDevellopement\CraftLink\) :
--   "C:\Users\wafhi\AppData\Local\Programs\Lua\bin\lua.exe" tools\gen_professions.lua
--
-- Régénération idempotente : le bloc `disenchant` curé (tools/Curated/disenchant.lua) est
-- réinjecté, car il n'existe pas dans MTSL (les mats de DE ne sont pas des recettes).

-- ------------------------------------------------------------------
-- Configuration des chemins
-- ------------------------------------------------------------------
local MTSL_DATA_DIR = [[D:\Jeux\World of Warcraft\_classic_era_\Interface\AddOns\MissingTradeSkillsList\data\]]
local OUT_DIR       = [[CraftLink-1.0\Data\Vanilla\]]  -- données embarquées dans la lib
local CURATED_FILE  = [[tools\Curated\disenchant.lua]]
local WOWHEAD_MAP    = [[tools\wowhead_map.lua]]  -- spellID -> itemID produit (cf. tools/README)

-- Métier MTSL -> nom de fichier de sortie (sans espace)
local FILE_NAME = setmetatable({
    ["First Aid"] = "FirstAid",
}, { __index = function(_, k) return k end })

-- Alias localisés à exporter (clés du sous-objet name dans MTSL)
local ALIAS_LANGS = { "English", "French", "German", "Spanish" }

-- ------------------------------------------------------------------
-- Chargement des données MTSL (tables Lua pures, pas d'API WoW requise)
-- ------------------------------------------------------------------
MTSL_DATA = {}
local function loadMTSL(file)
    local path = MTSL_DATA_DIR .. file
    local chunk, err = loadfile(path)
    if not chunk then error("Impossible de charger " .. path .. " : " .. tostring(err)) end
    chunk()
end
loadMTSL("global_variables.lua")
loadMTSL("professions.lua")
loadMTSL("skills.lua")

local curated     = dofile(CURATED_FILE) or {}
local wowheadMap  = dofile(WOWHEAD_MAP)  or {}  -- [spellID] = itemID produit

local skills      = MTSL_DATA.skills      or error("MTSL_DATA.skills introuvable")
local professions = MTSL_DATA.professions or error("MTSL_DATA.professions introuvable")

-- ------------------------------------------------------------------
-- Helpers d'écriture
-- ------------------------------------------------------------------
local function luaQuote(s)
    return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

-- Construit la liste d'alias d'un métier (canonique + langues), dédupliquée
local function buildAliases(profKey)
    local seen, out = {}, {}
    local function add(v)
        if v and v ~= "" and not seen[v] then seen[v] = true; out[#out + 1] = v end
    end
    add(profKey)
    local def = professions[profKey]
    if def and def.name then
        for _, lang in ipairs(ALIAS_LANGS) do add(def.name[lang]) end
    end
    return out
end

-- ------------------------------------------------------------------
-- Génération
-- ------------------------------------------------------------------
local totalSell, totalEnch, totalRecipes, fileCount = 0, 0, 0, 0

for profKey, list in pairs(skills) do
    -- sellable : recettes produisant un objet (items={itemID})
    -- sellable : recette produisant un OBJET (itemID).  enchants : service sans objet
    -- (sort lancé sur un item — commandable par spellID).
    -- Produit = itemID Wowhead. Fallback MTSL `items` SAUF pour l'Enchantement : là, une
    -- recette sans produit Wowhead est un enchantement pur (MTSL y stocke le parchemin, qu'on
    -- ne veut PAS dans sellable). Pour les autres métiers, MTSL `items` = le produit (fiable).
    local isEnchanting = (profKey == "Enchanting")
    local sellable, enchants = {}, {}
    for _, sk in ipairs(list) do
        local name = sk.name and (sk.name.English or sk.name.French) or ("skill:" .. tostring(sk.id))
        local itemID = wowheadMap[sk.id]
        if not itemID and not isEnchanting then
            itemID = sk.items and sk.items[1]
        end
        if itemID and itemID > 0 then
            sellable[itemID] = name
        else
            enchants[#enchants + 1] = { id = sk.id, name = name }
        end
    end

    -- Tri déterministe (diffs stables)
    local sellIDs = {}
    for id in pairs(sellable) do sellIDs[#sellIDs + 1] = id end
    table.sort(sellIDs)
    table.sort(enchants, function(a, b) return a.name < b.name end)

    -- Index canonique de recettes : TOUTES les recettes du métier, triées par spellID.
    -- C'est la table de positions de bits du registre (cf. CraftLink-1.0/CraftLink_Registry).
    -- + itemToSpell (itemID produit -> spellID) : repli runtime pour le scan TradeSkill, qui
    -- ne capte que l'itemID produit alors que le bitfield est indexé par spellID.
    local recipeIDs, itemToSpell = {}, {}
    for _, sk in ipairs(list) do
        recipeIDs[#recipeIDs + 1] = sk.id
        local pid = wowheadMap[sk.id] or ((not isEnchanting) and sk.items and sk.items[1]) or nil
        if pid and pid > 0 then itemToSpell[pid] = sk.id end
    end
    table.sort(recipeIDs)

    local aliases = buildAliases(profKey)
    local cur     = curated[profKey]

    -- Écriture du fichier
    local fname = OUT_DIR .. FILE_NAME[profKey] .. ".lua"
    local f = assert(io.open(fname, "w"))
    f:write("-- " .. FILE_NAME[profKey] .. ".lua\n")
    f:write("-- GÉNÉRÉ par tools/gen_professions.lua — NE PAS ÉDITER À LA MAIN.\n")
    f:write("-- Source : MissingTradeSkillsList (faits de jeu : itemID -> nom).\n")
    f:write("-- Données embarquées dans CraftLink (lib self-contained) via RegisterProfession.\n\n")
    f:write("local CraftLink = LibStub and LibStub:GetLibrary(\"CraftLink-1.0\", true)\n")
    f:write("if not CraftLink then return end\n\n")
    f:write("CraftLink:RegisterProfession(" .. luaQuote(profKey) .. ", {\n")

    -- aliases
    local aq = {}
    for _, a in ipairs(aliases) do aq[#aq + 1] = luaQuote(a) end
    f:write("    aliases = { " .. table.concat(aq, ", ") .. " },\n\n")

    -- disenchant curé (si présent)
    if cur and cur.disenchant then
        local deIDs = {}
        for id in pairs(cur.disenchant) do deIDs[#deIDs + 1] = id end
        table.sort(deIDs)
        f:write("    disenchant = {\n")
        for _, id in ipairs(deIDs) do
            f:write(string.format("        [%d] = %s,\n", id, luaQuote(cur.disenchant[id])))
        end
        f:write("    },\n\n")
    end

    -- sellable
    f:write("    sellable = {\n")
    for _, id in ipairs(sellIDs) do
        f:write(string.format("        [%d] = %s,\n", id, luaQuote(sellable[id])))
        totalSell = totalSell + 1
    end
    f:write("    },\n")

    -- enchants (services sans objet) : { id = spellID, name = "..." }
    if #enchants > 0 then
        f:write("\n    enchants = {\n")
        for _, e in ipairs(enchants) do
            f:write(string.format("        { id = %d, name = %s },\n", e.id, luaQuote(e.name)))
            totalEnch = totalEnch + 1
        end
        f:write("    },\n")
    end

    -- recipes : index canonique (positions de bits du registre). NE PAS réordonner.
    if #recipeIDs > 0 then
        f:write("\n    recipes = {\n")
        for i = 1, #recipeIDs, 12 do
            local chunk = {}
            for j = i, math.min(i + 11, #recipeIDs) do chunk[#chunk + 1] = recipeIDs[j] end
            f:write("        " .. table.concat(chunk, ", ") .. ",\n")
        end
        f:write("    },\n")
        totalRecipes = totalRecipes + #recipeIDs
    end

    -- itemToSpell : repli itemID produit -> spellID (mapping runtime du scan TradeSkill)
    local i2sIDs = {}
    for id in pairs(itemToSpell) do i2sIDs[#i2sIDs + 1] = id end
    table.sort(i2sIDs)
    if #i2sIDs > 0 then
        f:write("\n    itemToSpell = {\n")
        for _, id in ipairs(i2sIDs) do
            f:write(string.format("        [%d] = %d,\n", id, itemToSpell[id]))
        end
        f:write("    },\n")
    end

    f:write("})\n")
    f:close()
    fileCount = fileCount + 1
    print(string.format("  [OK] %-16s  sellable=%-4d enchants=%-4d recipes=%-4d aliases=%d",
        FILE_NAME[profKey] .. ".lua", #sellIDs, #enchants, #recipeIDs, #aliases))
end

print(string.format("Terminé : %d fichiers, %d sellable, %d enchants, %d recettes (index) au total.",
    fileCount, totalSell, totalEnch, totalRecipes))
