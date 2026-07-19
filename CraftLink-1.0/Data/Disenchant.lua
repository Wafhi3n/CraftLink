-- Data/Disenchant.lua — table CURATÉE du DÉSENCHANTEMENT : composant (poussière/essence/éclat/
-- cristal) → la CLASSE d'objets qui le rend au désenchantement { q = qualité (2 vert / 3 bleu /
-- 4 épique), lo/hi = tranche de NIVEAU D'OBJET (ilvl — ≠ niveau requis pour équiper, toujours
-- l'afficher comme « niv. d'objet ») }.
--
-- Source : Wowpedia « Disenchanting tables » (la table historique d'Enchantrix). Les bornes
-- divergent d'une source à l'autre (l'extrapolation Wowhead « disenchanted from » donne ±5 aux
-- bornes) → ESTIMATION assumée, à afficher comme telle. Régénérable plus tard par un outil
-- gen_* (source Wowhead) si la précision aux bornes devient un enjeu.
--
-- Sert à la bourse d'artisan / au plan de route : « fournis-lui des objets verts niv. d'objet
-- X-Y à désenchanter » — un composant de désenchantement ne s'achète pas toujours, il se FABRIQUE
-- en détruisant des objets. IDs d'objets uniques par extension → UNE table pour toutes les
-- saveurs (chargée par Vanilla.xml / TBC.xml / Wrath.xml, comme Gathering.lua ; la couche SoD
-- hérite de Vanilla). Complémentaire de `conversions` (prospection/mouture : source = un OBJET
-- précis ; ici la source est une CLASSE d'objets).

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

CraftLink.deSources = {
    -- ----- Vanilla — poussières (verts, surtout armures)
    [10940] = { q = 2, lo = 5,  hi = 25 },   -- Strange Dust
    [11083] = { q = 2, lo = 26, hi = 35 },   -- Soul Dust
    [11137] = { q = 2, lo = 36, hi = 45 },   -- Vision Dust
    [11176] = { q = 2, lo = 46, hi = 55 },   -- Dream Dust
    [16204] = { q = 2, lo = 56, hi = 65 },   -- Illusion Dust
    -- ----- Vanilla — essences (verts, surtout armes)
    [10938] = { q = 2, lo = 5,  hi = 15 },   -- Lesser Magic Essence
    [10939] = { q = 2, lo = 16, hi = 25 },   -- Greater Magic Essence
    [10998] = { q = 2, lo = 26, hi = 30 },   -- Lesser Astral Essence
    [11082] = { q = 2, lo = 31, hi = 35 },   -- Greater Astral Essence
    [11134] = { q = 2, lo = 36, hi = 40 },   -- Lesser Mystic Essence
    [11135] = { q = 2, lo = 41, hi = 45 },   -- Greater Mystic Essence
    [11174] = { q = 2, lo = 46, hi = 50 },   -- Lesser Nether Essence
    [11175] = { q = 2, lo = 51, hi = 55 },   -- Greater Nether Essence
    [16202] = { q = 2, lo = 56, hi = 60 },   -- Lesser Eternal Essence
    [16203] = { q = 2, lo = 61, hi = 65 },   -- Greater Eternal Essence
    -- ----- Vanilla — éclats (bleus ; petite chance sur les verts de la tranche)
    [10978] = { q = 3, lo = 5,  hi = 20 },   -- Small Glimmering Shard
    [11084] = { q = 3, lo = 21, hi = 25 },   -- Large Glimmering Shard
    [11138] = { q = 3, lo = 26, hi = 30 },   -- Small Glowing Shard
    [11139] = { q = 3, lo = 31, hi = 35 },   -- Large Glowing Shard
    [11177] = { q = 3, lo = 36, hi = 40 },   -- Small Radiant Shard
    [11178] = { q = 3, lo = 41, hi = 45 },   -- Large Radiant Shard
    [14343] = { q = 3, lo = 46, hi = 50 },   -- Small Brilliant Shard
    [14344] = { q = 3, lo = 51, hi = 65 },   -- Large Brilliant Shard
    [20725] = { q = 4, lo = 51, hi = 80 },   -- Nexus Crystal (épiques)
    -- ----- TBC
    [22445] = { q = 2, lo = 79,  hi = 120 }, -- Arcane Dust
    [22447] = { q = 2, lo = 79,  hi = 99 },  -- Lesser Planar Essence
    [22446] = { q = 2, lo = 100, hi = 120 }, -- Greater Planar Essence
    [22448] = { q = 3, lo = 80,  hi = 99 },  -- Small Prismatic Shard
    [22449] = { q = 3, lo = 100, hi = 115 }, -- Large Prismatic Shard
    [22450] = { q = 4, lo = 95,  hi = 164 }, -- Void Crystal (épiques)
    -- ----- WotLK
    [34054] = { q = 2, lo = 130, hi = 200 }, -- Infinite Dust
    [34056] = { q = 2, lo = 130, hi = 165 }, -- Lesser Cosmic Essence
    [34055] = { q = 2, lo = 166, hi = 200 }, -- Greater Cosmic Essence
    [34053] = { q = 3, lo = 130, hi = 185 }, -- Small Dream Shard
    [34052] = { q = 3, lo = 186, hi = 200 }, -- Dream Shard
    [34057] = { q = 4, lo = 200, hi = 232 }, -- Abyss Crystal (épiques)
}
