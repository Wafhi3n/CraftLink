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

    -- recette -> objet produit (généré Wowhead)
    produces = {
        [2657] = 2840,
        [2658] = 2842,
        [2659] = 2841,
        [3304] = 3576,
        [3307] = 3575,
        [3308] = 3577,
        [3569] = 3859,
        [10097] = 3860,
        [10098] = 6037,
        [14891] = 11371,
        [16153] = 12359,
        [22967] = 17771,
    },

    -- recette -> réactifs {itemID, qté} (généré Wowhead). Noms via GetItemInfo.
    reagents = {
        [2657] = { {2770,1} },
        [2658] = { {2775,1} },
        [2659] = { {2840,1}, {3576,1} },
        [3304] = { {2771,1} },
        [3307] = { {2772,1} },
        [3308] = { {2776,1} },
        [3569] = { {3575,1}, {3857,1} },
        [10097] = { {3858,1} },
        [10098] = { {7911,1} },
        [14891] = { {11370,8} },
        [16153] = { {10620,1} },
        [22967] = { {18562,1}, {12360,10}, {17010,1}, {18567,3} },
    },

    -- >>> gen_metadata.lua (généré — Wowhead classic ; ne pas éditer à la main)
    -- niveau de métier où la recette s'apprend : [spellID] = niveau
    learnedAt = {
        [2657] = 25,
        [2658] = 75,
        [2659] = 65,
        [3304] = 65,
        [3307] = 125,
        [3308] = 155,
        [3569] = 165,
        [10097] = 175,
        [10098] = 230,
        [14891] = 230,
        [16153] = 250,
        [22967] = 310,
    },
    -- <<< gen_metadata.lua
})
