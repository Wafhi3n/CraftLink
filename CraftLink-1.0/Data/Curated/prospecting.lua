-- Data/Curated/prospecting.lua  (Joaillerie/Jewelcrafting — TBC+)
-- Conversion « prospection » : DÉTRUIRE 5 minerais → obtenir des GEMMES.
-- Généré depuis wow-professions.com/tbc/prospecting (recherche utilisateur). Couvre Copper→Adamantite.
-- Clés = itemID (noms résolus au runtime via GetItemInfo). Réinjecté comme `conversions` dans
-- Data/TBC/Jewelcrafting.lua (et Wrath).

return {
    Jewelcrafting = {
        conversions = {
            { kind = "prospect", from = 2770, to = { 774, 818, 1210 } },  -- Copper Ore -> Malachite, Tigerseye, Shadowgem
            { kind = "prospect", from = 2771, to = { 1705, 1206, 1210, 7909, 3864, 1529 } },  -- Tin Ore -> Lesser Moonstone, Moss Agate, Shadowgem, Aquamarine, Citrine, Jade
            { kind = "prospect", from = 2772, to = { 1705, 3864, 1529, 7910, 7909 } },  -- Iron Ore -> Lesser Moonstone, Citrine, Jade, Star Ruby, Aquamarine
            { kind = "prospect", from = 3858, to = { 7910, 7909, 3864, 12361, 12799, 12800, 12364 } },  -- Mithril Ore -> Star Ruby, Aquamarine, Citrine, Blue Sapphire, Large Opal, Azerothian Diamond, Huge Emerald
            { kind = "prospect", from = 10620, to = { 7910, 12364, 12800, 12361, 12799, 23077, 23079, 21929, 23112, 23107, 23117 } },  -- Thorium Ore -> Star Ruby, Huge Emerald, Azerothian Diamond, Blue Sapphire, Large Opal, Blood Garnet, Deep Peridot, Flame Spessarite, Golden Draenite, Shadow Draenite, Azure Moonstone
            { kind = "prospect", from = 23424, to = { 23077, 23079, 21929, 23112, 23107, 23117, 23439, 23440, 23436, 23441, 23438, 23437 } },  -- Fel Iron Ore -> Blood Garnet, Deep Peridot, Flame Spessarite, Golden Draenite, Shadow Draenite, Azure Moonstone, Noble Topaz, Dawnstone, Living Ruby, Nightseye, Star of Elune, Talasite
            { kind = "prospect", from = 23425, to = { 23077, 23079, 21929, 23112, 23107, 23117, 23439, 23440, 23436, 23441, 23438, 23437 } },  -- Adamantite Ore -> Blood Garnet, Deep Peridot, Flame Spessarite, Golden Draenite, Shadow Draenite, Azure Moonstone, Noble Topaz, Dawnstone, Living Ruby, Nightseye, Star of Elune, Talasite
        },
    },
}
