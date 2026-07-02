-- tools/Curated/disenchant.lua
-- Données curées à la main, fusionnées par tools/gen_professions.lua dans les fichiers générés.
--
-- Les mats de désenchantement ne sont PAS des recettes : ils n'existent pas dans la base
-- MTSL (qui ne liste que des skills/recettes). On les maintient ici pour que la
-- régénération de CraftLink-1.0/Data/Vanilla/Enchanting.lua reste idempotente (ne perde pas ce bloc).
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
