-- Data/Professions/FirstAid.lua
-- GÉNÉRÉ par tools/gen_professions.lua — NE PAS ÉDITER À LA MAIN.
-- Source : MissingTradeSkillsList (faits de jeu : itemID -> nom).
-- Les noms sont indicatifs ; l'addon résout le vrai nom localisé via GetItemInfo.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

CraftLink:RegisterProfession("First Aid", {
    aliases = { "First Aid", "Secourisme", "Erste Hilfe", "Primeros auxilios" },

    sellable = {
        [1251] = "Linen Bandage",
        [2581] = "Heavy Linen Bandage",
        [3530] = "Wool Bandage",
        [3531] = "Heavy Wool Bandage",
        [6450] = "Silk Bandage",
        [6452] = "Anti-Venom",
        [6454] = "Strong Anti-Venom",
        [8545] = "Heavy Mageweave Bandage",
        [14529] = "Runecloth Bandage",
        [14530] = "Heavy Runecloth Bandage",
        [16112] = "Heavy Silk Bandage",
        [16113] = "Mageweave Bandage",
        [19442] = "Powerful Anti-Venom",
    },

    recipes = {
        3275, 3276, 3277, 3278, 7928, 7929, 7934, 7935, 10840, 10841, 18629, 18630,
        23787,
    },

    itemToSpell = {
        [1251] = 3275,
        [2581] = 3276,
        [3530] = 3277,
        [3531] = 3278,
        [6450] = 7928,
        [6452] = 7934,
        [6454] = 7935,
        [8545] = 10841,
        [14529] = 18629,
        [14530] = 18630,
        [16112] = 7929,
        [16113] = 10840,
        [19442] = 23787,
    },

    -- recette -> objet produit (généré Wowhead)
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
    },

    -- recette -> réactifs {itemID, qté} (généré Wowhead). Noms via GetItemInfo.
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
    },

    -- >>> gen_metadata.lua (généré — Wowhead classic ; ne pas éditer à la main)
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
    },
    -- objet-plan (recette/formule/schéma) -> spellID enseigné (alerte loot / dons)
    taughtBy = {
        [6454] = 7935,
        [16112] = 7929,
        [16113] = 10840,
        [19442] = 23787,
    },
    -- <<< gen_metadata.lua

    -- >>> gen_skill_colors.lua (généré — Wowhead classic ; ne pas éditer à la main)
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
    },
    -- <<< gen_skill_colors.lua
})
