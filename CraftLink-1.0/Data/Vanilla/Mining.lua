-- Data/Professions/Mining.lua
-- GÉNÉRÉ par tools/gen_professions.lua — NE PAS ÉDITER À LA MAIN.
-- Source : MissingTradeSkillsList (faits de jeu : itemID -> nom).
-- Les noms sont indicatifs ; l'addon résout le vrai nom localisé via GetItemInfo.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

CraftLink:RegisterProfession("Mining", {
    aliases = { "Mining", "Minage", "Bergbau", "Minería" },

    sellable = {
        [2840] = "Smelt Copper",
        [2841] = "Smelt Bronze",
        [2842] = "Smelt Silver",
        [3575] = "Smelt Iron",
        [3576] = "Smelt Tin",
        [3577] = "Smelt Gold",
        [3859] = "Smelt Steel",
        [3860] = "Smelt Mithril",
        [6037] = "Smelt Truesilver",
        [11371] = "Smelt Dark Iron",
        [12359] = "Smelt Thorium",
        [17771] = "Smelt Elementium",
    },

    recipes = {
        2657, 2658, 2659, 3304, 3307, 3308, 3569, 10097, 10098, 14891, 16153, 22967,
    },

    itemToSpell = {
        [2840] = 2657,
        [2841] = 2659,
        [2842] = 2658,
        [3575] = 3307,
        [3576] = 3304,
        [3577] = 3308,
        [3859] = 3569,
        [3860] = 10097,
        [6037] = 10098,
        [11371] = 14891,
        [12359] = 16153,
        [17771] = 22967,
    },
})
