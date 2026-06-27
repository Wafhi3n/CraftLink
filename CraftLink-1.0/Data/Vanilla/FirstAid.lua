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
})
