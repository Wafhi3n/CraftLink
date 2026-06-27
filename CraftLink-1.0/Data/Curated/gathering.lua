-- Data/Curated/gathering.lua — métiers de RÉCOLTE (items récoltables, commandables).
-- Pas de recettes/réactifs : juste une liste `gathers` d'itemID (noms résolus runtime GetItemInfo).
-- Permet de commander des matières premières (plantes, minerais, peaux, poissons).
--
-- Herboristerie = herbes (dérivé de milling.lua), Mining = minerais (dérivé de prospecting.lua).
-- Skinning / Fishing : À COMPLÉTER (recherche utilisateur — peaux/cuirs et poissons par version).
-- Réinjecté par le générateur comme professions de récolte dans chaque saveur.

return {
    Herbalism = {
        aliases = { "Herbalism", "Herboristerie", "Kräuterkunde", "Herboristería" },
        gathers = {
            765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369,
            3818, 3819, 3820, 3821, 4625, 8831, 8836, 8838, 8839, 8845, 8846, 13463,
            13464, 13465, 13466, 13467, 22785, 22786, 22787, 22789, 22790, 22791, 22792, 22793,
            36901, 36903, 36905, 36906, 36907, 37921, 39970,
        },
    },
    Mining = {  -- minerais bruts (le métier Mining a aussi le smelting = recettes, à part)
        aliases = { "Mining", "Minage", "Bergbau", "Minería" },
        gathers = {
            2770, 2771, 2772, 3858, 10620, 23424, 23425, 36909, 36910, 36912,
        },
    },
    Skinning = {
        aliases = { "Skinning", "Dépeçage", "Kürschnerei", "Desuello" },
        gathers = {
            -- À COMPLÉTER : peaux/cuirs (Light/Medium/Heavy Leather, Knothide, Borean, etc.)
        },
    },
    Fishing = {
        aliases = { "Fishing", "Pêche", "Angeln", "Pesca" },
        gathers = {
            -- À COMPLÉTER : poissons bruts par version.
        },
    },
}
