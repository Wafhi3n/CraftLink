-- Data/SoD/Cooking.lua — couche saisonnière « Saison de la Découverte » (seasonId 2).
-- GÉNÉRÉ par tools/gen_season.lua — NE PAS ÉDITER À LA MAIN.
-- Source : Wowhead (domaine « classic », lignes taguées seasonId:2).
--
-- ADDITIF : ces recettes sont AJOUTÉES EN FIN du set Vanilla, dont les positions de bits (donc les
-- bitfields du registre déjà diffusés) restent intactes. Le fichier s'auto-désactive hors saison.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end
if CraftLink:ActiveSeason() ~= 2 then return end   -- couche inerte hors de sa saison

CraftLink:ExtendProfession("Cooking", {
    -- recettes saisonnières (appondues à la suite du set de base, jamais insérées)
    recipes = {
        470359, 470370, 1225758, 1225759, 1225760, 1225762, 1225763,
    },
    itemToSpell = {
        [232436] = 470359,
        [232438] = 470370,
        [238637] = 1225758,
        [238638] = 1225759,
        [238639] = 1225760,
        [238641] = 1225762,
        [238642] = 1225763,
    },
    produces = {
        [470359] = 232436,
        [470370] = 232438,
        [1225758] = 238637,
        [1225759] = 238638,
        [1225760] = 238639,
        [1225762] = 238641,
        [1225763] = 238642,
    },
    reagents = {
        [470359] = { {13888,1}, {227813,1} },
        [470370] = { {13758,1} },
        [1225758] = { {12202,2}, {239016,1} },
        [1225759] = { {12203,2}, {239016,1} },
        [1225760] = { {12207,2}, {239016,1} },
        [1225762] = { {4603,12}, {12184,4}, {6362,3}, {239017,1} },
        [1225763] = { {13888,12}, {3712,4}, {3404,3}, {239017,1} },
    },
    learnedAt = {
        [470359] = 325,
        [470370] = 325,
        [1225758] = 260,
        [1225759] = 260,
        [1225760] = 260,
        [1225762] = 290,
        [1225763] = 290,
    },
    taughtBy = {
        [232437] = 470359,
        [232443] = 470370,
        [238645] = 1225758,
        [238646] = 1225759,
        [238647] = 1225760,
        [238649] = 1225762,
        [238650] = 1225763,
    },

    -- >>> gen_skill_colors.lua (généré — Wowhead classic ; ne pas éditer à la main)
    -- seuils de difficulté : [spellID] = { orange, jaune, vert, gris }
    -- (gris = rang où la recette ne rapporte plus de point)
    skillColors = {
        [470359] = { 0, 325, 345, 365 },
        [470370] = { 0, 325, 345, 365 },
        [1225758] = { 0, 260, 270, 280 },
        [1225759] = { 0, 260, 270, 280 },
        [1225760] = { 0, 260, 270, 280 },
        [1225762] = { 0, 290, 300, 310 },
        [1225763] = { 0, 290, 300, 310 },
    },
    -- <<< gen_skill_colors.lua
})
