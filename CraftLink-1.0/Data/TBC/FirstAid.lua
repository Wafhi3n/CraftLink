-- FirstAid.lua  (TBC)
-- GÉNÉRÉ par tools/gen_flavor.lua depuis Wowhead tbc/. NE PAS ÉDITER À LA MAIN.
-- Noms résolus au runtime (GetItemInfo/GetSpellInfo) — multilingue.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

-- Clé canonique = "First Aid" (avec espace), comme en Vanilla — l'ancienne génération
-- (gen_flavor) enregistrait "FirstAid", incohérent inter-saveurs (corrigé 2026-07-02).
CraftLink:RegisterProfession("First Aid", {
    aliases = { "First Aid", "Secourisme", "Erste Hilfe", "Primeros auxilios" },

    recipes = {
        3275, 3276, 3277, 3278, 7928, 7929, 7934, 7935, 10840, 10841, 18629, 18630, 
        23787, 27032, 27033, 30021, 
    },

    produces = {
        [3275] = 1251,
        [3276] = 2581,
        [3277] = 3530,
        [3278] = 3531,
        [7928] = 6450,
        [7929] = 6451,
        [7934] = 6452,
        [7935] = 6453,
        [10840] = 8544,
        [10841] = 8545,
        [18629] = 14529,
        [18630] = 14530,
        [23787] = 19440,
        [27032] = 21990,
        [27033] = 21991,
        [30021] = 23684,
    },

    itemToSpell = {
        [1251] = 3275,
        [2581] = 3276,
        [3530] = 3277,
        [3531] = 3278,
        [6450] = 7928,
        [6451] = 7929,
        [6452] = 7934,
        [6453] = 7935,
        [8544] = 10840,
        [8545] = 10841,
        [14529] = 18629,
        [14530] = 18630,
        [19440] = 23787,
        [21990] = 27032,
        [21991] = 27033,
        [23684] = 30021,
    },

    reagents = {
        [3275] = { {2589,1} },
        [3276] = { {2589,2} },
        [3277] = { {2592,1} },
        [3278] = { {2592,2} },
        [7928] = { {4306,1} },
        [7929] = { {4306,2} },
        [7934] = { {1475,1} },
        [7935] = { {1288,1} },
        [10840] = { {4338,1} },
        [10841] = { {4338,2} },
        [18629] = { {14047,1} },
        [18630] = { {14047,2} },
        [23787] = { {19441,1} },
        [27032] = { {21877,1} },
        [27033] = { {21877,2} },
        [30021] = { {23567,1}, {14047,10} },
    },

    -- >>> gen_metadata.lua (généré — Wowhead tbc ; ne pas éditer à la main)
    -- niveau de métier où la recette s'apprend : [spellID] = niveau
    learnedAt = {
        [3275] = 1,
        [3276] = 40,
        [3277] = 80,
        [3278] = 115,
        [7928] = 150,
        [7929] = 180,
        [7934] = 80,
        [7935] = 130,
        [10840] = 210,
        [10841] = 240,
        [18629] = 260,
        [18630] = 290,
        [23787] = 300,
        [27032] = 330,
        [27033] = 360,
    },
    -- objet-plan (recette/formule/schéma) -> spellID enseigné (alerte loot / dons)
    taughtBy = {
        [6454] = 7935,
        [16112] = 7929,
        [16113] = 10840,
        [19442] = 23787,
        [21992] = 27032,
        [21993] = 27033,
    },
    -- <<< gen_metadata.lua

    -- >>> gen_skill_colors.lua (généré — Wowhead tbc ; ne pas éditer à la main)
    -- seuils de difficulté : [spellID] = { orange, jaune, vert, gris }
    -- (gris = rang où la recette ne rapporte plus de point)
    skillColors = {
        [3275] = { 1, 30, 45, 60 },
        [3276] = { 40, 50, 75, 100 },
        [3277] = { 80, 80, 115, 150 },
        [3278] = { 115, 115, 150, 185 },
        [7928] = { 150, 150, 180, 210 },
        [7929] = { 180, 180, 210, 240 },
        [7934] = { 80, 80, 115, 150 },
        [7935] = { 130, 130, 165, 200 },
        [10840] = { 210, 210, 240, 270 },
        [10841] = { 240, 240, 270, 300 },
        [18629] = { 260, 260, 290, 320 },
        [18630] = { 290, 290, 320, 350 },
        [23787] = { 300, 300, 330, 360 },
        [27032] = { 330, 330, 360, 390 },
        [27033] = { 360, 360, 385, 410 },
    },
    -- <<< gen_skill_colors.lua
})
