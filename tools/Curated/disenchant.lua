-- tools/Curated/disenchant.lua
-- Données curées à la main, lues par DEUX générateurs — c'est la seule liste, ne pas la recopier :
--   * tools/gen_professions.lua  -> CraftLink-1.0/Data/Vanilla/Enchanting.lua
--   * tools/gen_flavor.lua       -> CraftLink-1.0/Data/<Saveur complète>/Enchanting.lua (Camelot)
--
-- Les mats de désenchantement ne sont PAS des recettes : ils n'existent ni dans la base MTSL ni sur
-- les pages Wowhead de métier (qui ne listent que des sorts). On les maintient ici pour que la
-- régénération des fichiers ci-dessus reste idempotente (ne perde pas ce bloc).
--
-- Tous vanilla, donc présents sur Forever — les 24 y sont consommés par des enchants (vérifié le
-- 2026-09-19 sur le cache forever_Enchanting.html). Forever a peut-être ses propres produits, mais
-- quatre réactifs neufs très utilisés (234003, 234008, 234010, 234011) y ont encore un nom VIDE :
-- la bêta ne les a pas observés. Ne rien ajouter sur une supposition — trancher en jeu d'abord.
--
-- Retourne : { [profCanonical] = { disenchant = { [itemID] = "Nom" } } }

return {
    Enchanting = {
        disenchant = {
            -- Poussières
            [10940] = "Strange Dust",
            [11083] = "Soul Dust",
            [11137] = "Vision Dust",
            [11176] = "Dream Dust",
            [16204] = "Illusion Dust",
            -- Essences
            [10938] = "Lesser Magic Essence",
            [10939] = "Greater Magic Essence",
            [10998] = "Lesser Astral Essence",
            [11082] = "Greater Astral Essence",
            [11134] = "Lesser Mystic Essence",
            [11135] = "Greater Mystic Essence",
            [11174] = "Lesser Nether Essence",
            [11175] = "Greater Nether Essence",
            [16202] = "Lesser Eternal Essence",
            [16203] = "Greater Eternal Essence",
            -- Éclats
            [10978] = "Small Glimmering Shard",
            [11084] = "Large Glimmering Shard",
            [11138] = "Small Glowing Shard",
            [11139] = "Large Glowing Shard",
            [11177] = "Small Radiant Shard",
            [11178] = "Large Radiant Shard",
            [14343] = "Small Brilliant Shard",
            [14344] = "Large Brilliant Shard",
            -- Cristal
            [20725] = "Nexus Crystal",
        },
    },
}
