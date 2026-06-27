-- Data/Curated/milling.lua  (Inscription — WotLK+)
-- Conversion « broyage » : DÉTRUIRE une plante (herbe) → obtenir des PIGMENTS.
-- (L'encre N'EST PAS ici : c'est une recette normale réactif=pigment, déjà dans `reagents`.)
--
-- Généré depuis milling_inverted.csv (recherche utilisateur, pigment→herbes ré-inversé en
-- herbe→pigments). Clés = itemID (noms résolus au runtime via GetItemInfo). Couvre toutes les
-- herbes (millables en WotLK). Réinjecté comme `conversions` dans Data/Wrath/Inscription.lua.

return {
    Inscription = {
        conversions = {
            { kind = "mill", from = 765, to = { 39151 } },
            { kind = "mill", from = 785, to = { 39334, 43103 } },
            { kind = "mill", from = 2447, to = { 39151 } },
            { kind = "mill", from = 2449, to = { 39151 } },
            { kind = "mill", from = 2450, to = { 39334, 43103 } },
            { kind = "mill", from = 2452, to = { 39334, 43103 } },
            { kind = "mill", from = 2453, to = { 39334, 43103 } },
            { kind = "mill", from = 3355, to = { 39338, 43104 } },
            { kind = "mill", from = 3356, to = { 39338, 43104 } },
            { kind = "mill", from = 3357, to = { 39338, 43104 } },
            { kind = "mill", from = 3358, to = { 39339, 43105 } },
            { kind = "mill", from = 3369, to = { 39338, 43104 } },
            { kind = "mill", from = 3818, to = { 39339, 43105 } },
            { kind = "mill", from = 3819, to = { 39339, 43105 } },
            { kind = "mill", from = 3820, to = { 39334, 43103 } },
            { kind = "mill", from = 3821, to = { 39339, 43105 } },
            { kind = "mill", from = 4625, to = { 39340, 43106 } },
            { kind = "mill", from = 8831, to = { 39340, 43106 } },
            { kind = "mill", from = 8836, to = { 39340, 43106 } },
            { kind = "mill", from = 8838, to = { 39340, 43106 } },
            { kind = "mill", from = 8839, to = { 39340, 43106 } },
            { kind = "mill", from = 8845, to = { 39340, 43106 } },
            { kind = "mill", from = 8846, to = { 39340, 43106 } },
            { kind = "mill", from = 13463, to = { 39341, 43107 } },
            { kind = "mill", from = 13464, to = { 39341, 43107 } },
            { kind = "mill", from = 13465, to = { 39341, 43107 } },
            { kind = "mill", from = 13466, to = { 39341, 43107 } },
            { kind = "mill", from = 13467, to = { 39341, 43107 } },
            { kind = "mill", from = 22785, to = { 39342, 43108 } },
            { kind = "mill", from = 22786, to = { 39342, 43108 } },
            { kind = "mill", from = 22787, to = { 39342, 43108 } },
            { kind = "mill", from = 22789, to = { 39342, 43108 } },
            { kind = "mill", from = 22790, to = { 39342, 43108 } },
            { kind = "mill", from = 22791, to = { 39342, 43108 } },
            { kind = "mill", from = 22792, to = { 39342, 43108 } },
            { kind = "mill", from = 22793, to = { 39342, 43108 } },
            { kind = "mill", from = 36901, to = { 39343, 43109 } },
            { kind = "mill", from = 36903, to = { 39343, 43109 } },
            { kind = "mill", from = 36905, to = { 39343, 43109 } },
            { kind = "mill", from = 36906, to = { 39343, 43109 } },
            { kind = "mill", from = 36907, to = { 39343, 43109 } },
            { kind = "mill", from = 37921, to = { 39343, 43109 } },
            { kind = "mill", from = 39970, to = { 39343, 43109 } },
        },
    },
}
