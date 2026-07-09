-- Data/Cooldowns.lua — recettes À COOLDOWN (curaté à la main, source Wowhead, toutes saveurs).
-- Chargé APRÈS les fichiers générés : RegisterProfession MERGE les champs cooldowns/cdGroup dans
-- les defs existantes sans toucher recipes → dataVersion intacte. Un spellID absent du catalogue
-- d'une saveur est inerte. cdGroup : catégorie PARTAGÉE — caster un sort du groupe déclenche le
-- cooldown de tout le groupe, avec la durée du sort casté (ex. Arcanite 48 h verrouille tout).

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

CraftLink:RegisterProfession("Alchemy", {
    -- Transmutations Vanilla : 24 h sauf Arcanite (48 h) et Feu élémentaire (10 min).
    cooldowns = {
        [11479] = 86400,   -- Transmute: Iron to Gold
        [11480] = 86400,   -- Transmute: Mithril to Truesilver
        [17559] = 86400,   -- Transmute: Air to Fire
        [17560] = 86400,   -- Transmute: Fire to Earth
        [17561] = 86400,   -- Transmute: Earth to Water
        [17562] = 86400,   -- Transmute: Water to Air
        [17563] = 86400,   -- Transmute: Undeath to Water
        [17564] = 86400,   -- Transmute: Water to Undeath
        [17565] = 86400,   -- Transmute: Life to Earth
        [17566] = 86400,   -- Transmute: Earth to Life
        [17187] = 172800,  -- Transmute: Arcanite (2 j)
        [25146] = 600,     -- Transmute: Elemental Fire (10 min)
    },
    cdGroup = {
        [11479] = "transmute", [11480] = "transmute", [17559] = "transmute",
        [17560] = "transmute", [17561] = "transmute", [17562] = "transmute",
        [17563] = "transmute", [17564] = "transmute", [17565] = "transmute",
        [17566] = "transmute", [17187] = "transmute", [25146] = "transmute",
    },
})

CraftLink:RegisterProfession("Tailoring", {
    cooldowns = {
        [18560] = 345600,  -- Mooncloth / Étoffe lunaire (4 j, CD propre)
    },
})
