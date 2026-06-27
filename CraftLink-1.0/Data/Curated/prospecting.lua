-- Data/Curated/prospecting.lua  (Joaillerie/Jewelcrafting — TBC+)
-- Conversion « prospection » : DÉTRUIRE 5 minerais → obtenir des GEMMES.
--
-- Donnée curée à la main (sorties probabilistes, Wowhead ne l'expose pas proprement) — réinjectée
-- comme `conversions` dans Data/TBC/Jewelcrafting.lua (et Wrath) par le générateur.
-- À COMPLÉTER par l'utilisateur. Clés = itemID (noms résolus au runtime via GetItemInfo).
--
-- Format : { [prof] = { conversions = { { kind="prospect", from=<oreItemID>, to={ <gemItemID>,... } }, ... } } }

return {
    Jewelcrafting = {
        conversions = {
            -- EXEMPLES À VÉRIFIER / COMPLÉTER (from = minerai prospecté, to = gemmes possibles) :
            -- { kind = "prospect", from = 23424, to = { 23077, 23079, 23107, 23112, 21929 } }, -- Fel Iron Ore
            -- { kind = "prospect", from = 23425, to = { 23436, 23437, 23438, 23439, 23440 } }, -- Adamantite Ore
        },
    },
}
