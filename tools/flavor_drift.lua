-- tools/flavor_drift.lua — comparaison PURE (aucune E/S) entre une page Wowhead parsée et le fichier
-- de données commité, au niveau des CHAMPS d'une recette, pas seulement de sa présence.
--
-- POURQUOI : `gen_flavor.lua -check` ne comparait que les numéros de recettes. Or pendant la bêta,
-- Wowhead documente l'objet créé ou le niveau d'apprentissage d'une recette BIEN APRÈS l'avoir listée
-- (357 recettes sans objet relevées le 2026-09-19). Un champ qui apparaît sur une recette déjà commitée
-- donnait « identique » : -Apply ne régénérait jamais, et ces données n'arrivaient que par accident,
-- le jour où une recette nouvelle déclenchait une régénération complète.
--
-- Même règle de sûreté que pour les recettes : ce qui APPARAÎT est une dérive saine ; ce qui
-- DISPARAÎT ou CHANGE ne s'applique jamais sans un humain.
--
-- Séparé de gen_flavor.lua pour être testé : l'outil termine par os.exit et lit le cache HTML (non
-- versionné), il ne se charge donc pas dans un harnais. Cf. tests/test_flavor_drift.lua.

local M = {}

-- Champs scalaires [spellID] = nombre que parseAll rend ET que le fichier commité porte. `learnedAt`
-- vaut légitimement 0 (recettes de départ) : on compare la PRÉSENCE et l'ÉGALITÉ, jamais la vérité.
M.FIELDS = { "produces", "learnedAt" }

-- Table `[k] = v` numérique d'un bloc de PREMIER niveau du fichier commité. L'indentation de 4 espaces
-- est exigée : un motif sans ancrage attraperait un bloc imbriqué ou un bloc de seconde passe.
function M.committedMap(content, field)
    local out = {}
    local block = content and content:match("\n    " .. field .. "%s*=%s*(%b{})")
    if block then
        for k, v in block:gmatch("%[(%d+)%]%s*=%s*(%d+)") do out[tonumber(k)] = tonumber(v) end
    end
    return out
end

-- live = { [spellID] = { produces=, learnedAt=, ... } } (parseAll) ; have = set des recettes commitées.
-- Ne regarde que les recettes présentes DES DEUX CÔTÉS : une recette disparue est déjà une perte,
-- la compter une seconde fois ici brouillerait le bilan. Rend (champs complétés, champs perdus/changés).
function M.fieldDrift(live, have, content)
    local gained, changed = 0, 0
    for _, field in ipairs(M.FIELDS) do
        local committed = M.committedMap(content, field)
        for id in pairs(have) do
            if live[id] then
                local lv, cv = live[id][field], committed[id]
                if lv ~= nil and cv == nil then
                    gained = gained + 1
                elseif cv ~= nil and lv ~= cv then
                    changed = changed + 1
                end
            end
        end
    end
    return gained, changed
end

return M
