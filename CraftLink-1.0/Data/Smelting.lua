-- Data/Smelting.lua — la FONTE (Smelting) n'est PAS un métier à part : c'est la facette « craft » du
-- Minage (l'autre facette étant la récolte de minerais). En jeu, ouvrir la Fonte affiche une fenêtre
-- de CRAFT (API CraftFrame, comme l'Enchantement) dont le nom de ligne de compétence
-- (« Fonte » / « Smelting ») DIFFÈRE du nom du métier (« Minage » / « Mining »). Sans alias,
-- ResolveProfession ne rattacherait pas cette fenêtre — ni les recettes qu'on y scanne — à Mining :
-- les lingots seraient mal classés (sous un pseudo-métier « Fonte ») et la vue métier custom ne
-- saurait pas quel médaillon/annuaire afficher.
--
-- On APPEND donc les noms localisés de la Fonte aux alias de Mining. Chargé APRÈS Gathering.lua (qui
-- pose l'alias de base du Minage). Purement additif : AUCUNE donnée de recette ici → n'affecte pas
-- dataVersion (calculé sur les noms de métiers + recettes, jamais sur les alias). Le nom localisé du
-- client courant est lu au runtime via GetSpellInfo(2656) (le sort « Fonte ») ; suivent des replis
-- statiques pour les locales usuelles au cas où l'API n'aurait pas encore le sort en cache.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

local def = CraftLink:GetProfession("Mining")
if not def then return end

def.aliases = def.aliases or {}
local have = {}
for _, a in ipairs(def.aliases) do have[a:lower()] = true end

local names = { "Smelting", "Fonte", "Schmelzkunst", "Fundición" }
local live = GetSpellInfo and GetSpellInfo(2656)   -- nom localisé de la Fonte pour CE client
if live then names[#names + 1] = live end

for _, a in ipairs(names) do
    if a and a ~= "" and not have[a:lower()] then
        have[a:lower()] = true
        def.aliases[#def.aliases + 1] = a
    end
end

CraftLink._aliasMap = nil   -- invalide le cache d'alias (ResolveProfession le reconstruira à la demande)
