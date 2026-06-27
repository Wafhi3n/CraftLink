-- Data/Curated/milling.lua  (Inscription — WotLK+)
-- Conversion « broyage » : DÉTRUIRE une plante (herbe) → obtenir des PIGMENTS.
-- (L'encre N'EST PAS ici : c'est une recette normale réactif=pigment, déjà dans `reagents`.)
--
-- Donnée curée à la main (Wowhead ne l'expose pas proprement par sort) — réinjectée comme
-- `conversions` dans Data/Wrath/Inscription.lua par le générateur. À COMPLÉTER par l'utilisateur.
-- Clés = itemID (multilingue : noms résolus au runtime via GetItemInfo).
--
-- Format : { [prof] = { conversions = { { kind="mill", from=<herbItemID>, to={ <pigmentItemID>,... } }, ... } } }
-- Réf pigment exemple : Azure Pigment = item 39343 (https://www.wowhead.com/wotlk/item=39343).

return {
    Inscription = {
        conversions = {
            -- EXEMPLES À VÉRIFIER / COMPLÉTER (from = herbe broyée, to = pigments obtenus) :
            -- { kind = "mill", from = 36901, to = { 39151 } },  -- Goldclover -> Alabaster Pigment
            -- { kind = "mill", from = 36904, to = { 39334 } },  -- Tiger Lily  -> ... Pigment
            -- { kind = "mill", from = 36907, to = { 39339, 39343 } }, -- ... -> Azure Pigment (39343)
        },
    },
}
