---@diagnostic disable: undefined-global
-- tools/check_dataversion.lua — Garde de l'invariant « set de recettes figé ».
--
-- Recalcule HORS-JEU la dataVersion de chaque saveur avec l'ALGORITHME EXACT de la lib
-- (computeDataVersion, CraftLink-1.0.lua) : repli (v*31+id) % 2^31-1 sur les spellID des
-- métiers triés par nom. À lancer avant/après toute régénération de Data/ : si la valeur
-- Vanilla bouge, les bitfields de registre déjà diffusés chez les joueurs deviennent
-- ininterprétables (positions de bits décalées).
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\check_dataversion.lua          # toutes les saveurs
--   lua tools\check_dataversion.lua Vanilla  # une seule
--
-- Échoue (exit 1) si Vanilla ne vaut plus la valeur figée déployée.

local FROZEN_VANILLA = 1792301894

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local FLAVORS = {
    Vanilla = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
                "FirstAid", "Leatherworking", "Mining", "Poisons", "Tailoring" },
    TBC     = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
                "FirstAid", "Jewelcrafting", "Leatherworking", "Mining", "Tailoring" },
    Wrath   = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
                "FirstAid", "Inscription", "Jewelcrafting", "Leatherworking", "Mining", "Tailoring" },
}

-- Couches SAISONNIÈRES (Data/<Season>/, ExtendProfession) : appondues EN FIN du set de base.
-- Leur dataVersion diffère forcément de celle de la base — c'est VOULU (un client dans la saison
-- ne doit pas comparer ses bitfields avec un client hors saison). Ce qui est INTERDIT, c'est
-- qu'une recette saisonnière existe déjà dans la base : elle décalerait les positions.
local SEASONS = {
    SoD = { base = "Vanilla", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
            "Engineering", "FirstAid", "Leatherworking", "Mining", "Tailoring" } },
}

local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

-- Extrait (nom canonique enregistré, liste ordonnée des spellID) d'un fichier Data.
-- Reconnaît RegisterProfession (set de base) ET ExtendProfession (couche saisonnière).
local function parseDataFile(path)
    local content = readFile(path)
    if not content then return nil end
    local name  = content:match('RegisterProfession%("([^"]+)"')
                  or content:match('ExtendProfession%("([^"]+)"')
    local block = content:match("recipes%s*=%s*(%b{})")
    if not name or not block then return nil end
    local ids = {}
    for id in block:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
    return name, ids
end

-- Réplique de computeDataVersion : métiers triés par nom, spellID dans l'ordre du fichier.
local function computeDataVersion(catalog)
    local profs = {}
    for prof in pairs(catalog) do profs[#profs + 1] = prof end
    table.sort(profs)
    local v = 0
    for _, prof in ipairs(profs) do
        for _, id in ipairs(catalog[prof]) do
            v = (v * 31 + id) % 2147483647
        end
    end
    return v
end

local only = arg and arg[1]
local fail = false

local names = {}
for flavor in pairs(FLAVORS) do names[#names + 1] = flavor end
table.sort(names)

for _, flavor in ipairs(names) do
    if not only or only == flavor then
        local catalog, nRec, missing = {}, 0, {}
        for _, prof in ipairs(FLAVORS[flavor]) do
            local name, ids = parseDataFile(DATA_ROOT .. flavor .. [[\]] .. prof .. ".lua")
            if name then catalog[name] = ids; nRec = nRec + #ids
            else missing[#missing + 1] = prof end
        end
        local v = computeDataVersion(catalog)
        local note = ""
        if flavor == "Vanilla" then
            if v == FROZEN_VANILLA then note = "  [OK] = valeur figée déployée"
            else note = "  [FAIL] != " .. FROZEN_VANILLA .. " (bitfields déployés invalidés !)"; fail = true end
        end
        print(string.format("%-8s dataVersion=%-12d recettes=%d%s%s", flavor, v, nRec,
            (#missing > 0) and ("  (fichiers absents : " .. table.concat(missing, ", ") .. ")") or "", note))
    end
end

-- ------------------------------------------------------------------
-- Couches saisonnières : base + append. Garde = AUCUNE collision avec la base.
-- ------------------------------------------------------------------
local seasonNames = {}
for s in pairs(SEASONS) do seasonNames[#seasonNames + 1] = s end
table.sort(seasonNames)

for _, season in ipairs(seasonNames) do
    if not only or only == season then
        local cfg = SEASONS[season]
        local catalog, nBase, nAdd, collisions = {}, 0, 0, {}
        -- 1) le set de base, dans son ordre figé
        for _, prof in ipairs(FLAVORS[cfg.base]) do
            local name, ids = parseDataFile(DATA_ROOT .. cfg.base .. [[\]] .. prof .. ".lua")
            if name then catalog[name] = ids; nBase = nBase + #ids end
        end
        -- 2) la couche, APPONDUE en fin (exactement ce que fait lib:ExtendProfession)
        for _, prof in ipairs(cfg.profs) do
            local name, ids = parseDataFile(DATA_ROOT .. season .. [[\]] .. prof .. ".lua")
            if name and catalog[name] then
                local seen = {}
                for _, id in ipairs(catalog[name]) do seen[id] = true end
                for _, id in ipairs(ids) do
                    if seen[id] then collisions[#collisions + 1] = name .. ":" .. id
                    else catalog[name][#catalog[name] + 1] = id; nAdd = nAdd + 1 end
                end
            end
        end
        local v = computeDataVersion(catalog)
        local note
        if #collisions > 0 then
            note = "  [FAIL] " .. #collisions .. " recette(s) déjà dans la base : " ..
                   table.concat(collisions, ", "):sub(1, 90) .. " (positions décalées !)"
            fail = true
        else
            note = "  [OK] append-only, positions de " .. cfg.base .. " intactes"
        end
        print(string.format("%-8s dataVersion=%-12d recettes=%d (%s %d + saison %d)%s",
            season, v, nBase + nAdd, cfg.base, nBase, nAdd, note))
    end
end

os.exit(fail and 1 or 0)
