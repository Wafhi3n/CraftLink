-- Data/Gathering.lua — métiers de RÉCOLTE (chargé en plus des recettes, toutes saveurs).
-- GÉNÉRÉ depuis Data/Curated/gathering.lua. gathers = itemID commandables (pas de recettes →
-- n'affecte pas dataVersion). Mining : merge avec ses recettes de fonte (charger APRÈS).

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

CraftLink:RegisterProfession("Herbalism", {
    aliases = { "Herbalism", "Herboristerie", "Kräuterkunde", "Herboristería" },
    gathers = {
        765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369,
        3818, 3819, 3820, 3821, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13463,
        13464, 13465, 13466, 13467, 22785, 22786, 22787, 22789, 22790, 22791, 22792, 22793,
        36901, 36903, 36905, 36906, 36907, 37921, 39970,
    },
})

CraftLink:RegisterProfession("Mining", {
    aliases = { "Mining", "Minage", "Bergbau", "Minería" },
    gathers = {
        2770, 2771, 2772, 3858, 10620, 23424, 23425, 36909, 36910, 36912,
    },
})

CraftLink:RegisterProfession("Skinning", {
    aliases = { "Skinning", "Dépeçage", "Kürschnerei", "Desuello" },
    gathers = {
        783, 2318, 2319, 2934, 4232, 4234, 4235, 4304, 5784, 5785, 6470, 6471,
        7287, 8154, 8169, 8170, 8171, 12607, 12731, 15408, 15410, 15412, 15414, 15415,
        15416, 17012, 21887, 25699, 25700, 25708, 28547, 29539, 29548, 33567, 33568, 38557,
        38561, 38568, 44128,
    },
})

CraftLink:RegisterProfession("Fishing", {
    aliases = { "Fishing", "Pêche", "Angeln", "Pesca" },
    gathers = {
        4603, 6289, 6291, 6303, 6308, 6317, 6361, 6362, 7974, 8365, 13754, 13756,
        13758, 13759, 13760, 13888, 13889, 13890, 21071, 21153, 27422, 27425, 27429, 27435,
        27437, 27438, 27439, 33823, 33824, 35285, 41800, 41801, 41802, 41803, 41805, 41806,
        41807, 41808, 41809, 41810, 41812, 41813, 41814, 43571, 43572, 43646, 43647, 43652,
        45907,
    },
})

