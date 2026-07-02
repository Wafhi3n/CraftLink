---@diagnostic disable: undefined-global
-- tools/gen_wowhead.lua — Enrichissement des données de recettes depuis Wowhead (hors-jeu).
--
-- Ajoute `produces` (spellID -> itemID produit) + `reagents` (spellID -> { {itemID, qty}, ... })
-- aux fichiers CraftLink-1.0/Data/<flavor>/*.lua, SANS toucher `recipes` (la dataVersion Vanilla
-- figée 1792301894 reste valide — computeDataVersion ne lit que `recipes`).
--
-- PRÉREQUIS : récupérer le HTML brut des pages skill (WebFetch ne marche pas — il jette la table JS).
-- Depuis tools/ :
--   for e in Alchemy:171/alchemy Blacksmithing:164/blacksmithing Cooking:185/cooking \
--            Enchanting:333/enchanting Engineering:202/engineering FirstAid:129/first-aid \
--            Leatherworking:165/leatherworking Mining:186/mining Tailoring:197/tailoring ; do
--     prof=${e%%:*}; path=${e#*:}
--     curl -s -A "Mozilla/5.0" "https://www.wowhead.com/classic/skill=${path}" -o "wh/classic_${prof}.html"
--   done
-- (TBC/WotLK : domaines tbc/ wotlk/ ; + Joaillerie skill=755, Inscription skill=773. Pour ces
--  saveurs c'est une génération COMPLÈTE — recipes inclus — pas une simple enrichissement.)
--
-- Les noms NE SONT PAS bakés : le client localise via GetItemInfo/GetSpellInfo (multilingue).

local DATA  = [[CraftLink-1.0\Data\Vanilla\]]   -- relatif à tools/.. (cwd = CraftLink)
local HTML  = [[tools\wh\classic_]]
local PROFS = { "Alchemy","Blacksmithing","Cooking","Enchanting","Engineering",
                "FirstAid","Leatherworking","Mining","Poisons","Tailoring" }

-- Parse les objets recette « feuille » ({...} sans {} interne) du HTML : id/creates/reagents.
local function extractRecipes(html)
    local byId = {}
    for obj in html:gmatch("{[^{}]*}") do
        if obj:find('"creates":', 1, true) or obj:find('"reagents":', 1, true) then
            local id = tonumber(obj:match('"id":(%d+)'))
            if id then
                local produces = tonumber(obj:match('"creates":%[(%d+)'))
                local reagents = {}
                local rb = obj:match('"reagents":(%b[])')
                if rb then for iid, q in rb:gmatch('%[(%d+),(%d+)%]') do reagents[#reagents+1] = { tonumber(iid), tonumber(q) } end end
                if produces or #reagents > 0 then byId[id] = { produces = produces, reagents = reagents } end
            end
        end
    end
    return byId
end

local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end local c = f:read("*a"); f:close(); return c end

for _, prof in ipairs(PROFS) do
    local content = readFile(DATA .. prof .. ".lua")
    local html    = readFile(HTML .. prof .. ".html")
    -- GARDE : cet outil APPEND les blocs (pas de remplacement) — le relancer sur un fichier
    -- déjà enrichi empilerait des doublons. Pour les métadonnées additionnelles, utiliser
    -- tools/gen_metadata.lua (idempotent).
    if content and content:find("\n    produces = {", 1, true) then
        print("SKIP " .. prof .. " (déjà enrichi — produces présent ; cf. gen_metadata.lua)")
    elseif content and html then
        local recBlock = content:match("recipes%s*=%s*(%b{})")
        local ids = {}
        if recBlock then for n in recBlock:gmatch("%d+") do ids[#ids+1] = tonumber(n) end end
        table.sort(ids)
        local byId = extractRecipes(html)

        local prod, reag, np, nr = {}, {}, 0, 0
        for _, id in ipairs(ids) do
            local w = byId[id]
            if w then
                if w.produces then prod[#prod+1] = string.format("        [%d] = %d,", id, w.produces); np = np + 1 end
                if #w.reagents > 0 then
                    local parts = {}; for _, rg in ipairs(w.reagents) do parts[#parts+1] = string.format("{%d,%d}", rg[1], rg[2]) end
                    reag[#reag+1] = string.format("        [%d] = { %s },", id, table.concat(parts, ", ")); nr = nr + 1
                end
            end
        end

        if np > 0 or nr > 0 then
            local blocks = ""
            if np > 0 then blocks = blocks .. "\n    -- recette -> objet produit (généré Wowhead)\n    produces = {\n" .. table.concat(prod, "\n") .. "\n    },\n" end
            if nr > 0 then blocks = blocks .. "\n    -- recette -> réactifs {itemID, qté} (généré Wowhead). Noms via GetItemInfo.\n    reagents = {\n" .. table.concat(reag, "\n") .. "\n    },\n" end
            content = content:gsub("%s*$", "")
            assert(content:sub(-2) == "})", prof .. ": le fichier ne se termine pas par '})'")
            content = content:sub(1, -3) .. blocks .. "})\n"
            local f = io.open(DATA .. prof .. ".lua", "wb"); f:write(content); f:close()
        end
        print(string.format("%-16s recettes=%d  produces=%d  reagents=%d", prof, #ids, np, nr))
    else
        print("SKIP " .. prof .. " (data ou html manquant)")
    end
end
