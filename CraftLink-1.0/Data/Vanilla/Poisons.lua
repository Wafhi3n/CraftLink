-- Data/Professions/Poisons.lua
-- GÉNÉRÉ par tools/gen_professions.lua — NE PAS ÉDITER À LA MAIN.
-- Source : MissingTradeSkillsList (faits de jeu : itemID -> nom).
-- Les noms sont indicatifs ; l'addon résout le vrai nom localisé via GetItemInfo.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

CraftLink:RegisterProfession("Poisons", {
    aliases = { "Poisons", "Gifte", "Venenos" },

    sellable = {
        [2892] = "Deadly Poison",
        [2893] = "Deadly Poison II",
        [3775] = "Crippling Poison",
        [3776] = "Crippling Poison II",
        [5237] = "Mind-numbing Poison",
        [5530] = "Blinding Powder",
        [6947] = "Instant Poison",
        [6949] = "Instant Poison II",
        [6950] = "Instant Poison III",
        [6951] = "Mind-numbing Poison II",
        [8926] = "Instant Poison IV",
        [8927] = "Instant Poison V",
        [8928] = "Instant Poison VI",
        [8984] = "Deadly Poison III",
        [8985] = "Deadly Poison IV",
        [9186] = "Mind-numbing Poison III",
        [10918] = "Wound Poison",
        [10920] = "Wound Poison II",
        [10921] = "Wound Poison III",
        [10922] = "Wound Poison IV",
        [21302] = "Deadly Poison V",
    },

    recipes = {
        2835, 2837, 3420, 3421, 5763, 6510, 8681, 8687, 8691, 8694, 11341, 11342,
        11343, 11357, 11358, 11400, 13220, 13228, 13229, 13230, 25347,
    },

    itemToSpell = {
        [2892] = 2835,
        [2893] = 2837,
        [3775] = 3420,
        [3776] = 3421,
        [5237] = 5763,
        [5530] = 6510,
        [6947] = 8681,
        [6949] = 8687,
        [6950] = 8691,
        [6951] = 8694,
        [8926] = 11341,
        [8927] = 11342,
        [8928] = 11343,
        [8984] = 11357,
        [8985] = 11358,
        [9186] = 11400,
        [10918] = 13220,
        [10920] = 13228,
        [10921] = 13229,
        [10922] = 13230,
        [21302] = 25347,
    },
})
