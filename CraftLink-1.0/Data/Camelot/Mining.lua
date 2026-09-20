-- Data/Camelot/Mining.lua — set COMPLET de la saveur « WoW: Forever (Camelot) ».
-- GÉNÉRÉ par tools/gen_flavor.lua depuis Wowhead (domaine « forever/ »). NE PAS ÉDITER À LA MAIN.
-- Noms résolus au runtime (GetItemInfo/GetSpellInfo) — multilingue.
--
-- REMPLACE le set de base (RegisterProfession), il ne l'étend pas : cette saveur RETIRE des
-- recettes en plus d'en ajouter, ce qu'une couche additive ne sait pas faire. Sélectionné par le
-- .toc de l'hôte via Data/Camelot.xml — aucune garde runtime, le .toc est le seul aiguillage.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

CraftLink:RegisterProfession("Mining", {
    aliases = { "Mining", "Minage", "Bergbau", "Minería" },

    recipes = {
        2657, 2658, 2659, 3304, 3307, 3308, 3569, 10097, 10098, 14891, 16153, 22967,
        1213638, 1230161, 1249637, 1262975, 1263071, 1306126,
    },
    itemToSpell = {
        [2840] = 2657,
        [2841] = 2659,
        [2842] = 2658,
        [3575] = 3307,
        [3576] = 3304,
        [3577] = 3308,
        [3859] = 3569,
        [3860] = 10097,
        [6037] = 10098,
        [11371] = 14891,
        [12359] = 16153,
        [17771] = 22967,
        [249726] = 1249637,
        [251291] = 1306126,
        [279948] = 1262975,
        [279952] = 1263071,
        [279960] = 1230161,
    },
    produces = {
        [2657] = 2840,
        [2658] = 2842,
        [2659] = 2841,
        [3304] = 3576,
        [3307] = 3575,
        [3308] = 3577,
        [3569] = 3859,
        [10097] = 3860,
        [10098] = 6037,
        [14891] = 11371,
        [16153] = 12359,
        [22967] = 17771,
        [1230161] = 279960,
        [1249637] = 249726,
        [1262975] = 279948,
        [1263071] = 279952,
        [1306126] = 251291,
    },
    reagents = {
        [2657] = { {2770,1} },
        [2658] = { {2775,1} },
        [2659] = { {2840,1}, {3576,1} },
        [3304] = { {2771,1} },
        [3307] = { {2772,1} },
        [3308] = { {2776,1} },
        [3569] = { {3575,1}, {3857,1} },
        [10097] = { {3858,1} },
        [10098] = { {7911,1} },
        [14891] = { {11370,8} },
        [16153] = { {10620,1} },
        [22967] = { {18562,1}, {12360,10}, {17010,1}, {18567,3} },
        [1213638] = { {12655,2}, {22203,2} },
        [1230161] = { {2835,1}, {2840,1} },
        [1249637] = { {249426,2}, {3857,1} },
        [1262975] = { {2838,2}, {2772,1}, {2842,1} },
        [1263071] = { {12359,5}, {12365,2}, {6037,1} },
        [1306126] = { {248815,1} },
    },
    learnedAt = {
        [2657] = 25,
        [2658] = 75,
        [2659] = 65,
        [3304] = 65,
        [3307] = 125,
        [3308] = 155,
        [3569] = 165,
        [10097] = 175,
        [10098] = 230,
        [14891] = 230,
        [16153] = 250,
        [22967] = 310,
        [1213638] = 315,
        [1230161] = 20,
        [1249637] = 275,
        [1262975] = 140,
        [1263071] = 300,
        [1306126] = 300,
    },

    -- >>> gen_skill_colors.lua (généré — Wowhead forever ; ne pas éditer à la main)
    -- seuils de difficulté : [spellID] = { orange, jaune, vert, gris }
    -- (gris = rang où la recette ne rapporte plus de point)
    skillColors = {
        [2657] = { 0, 25, 47, 70 },
        [2658] = { 75, 100, 112, 125 },
        [2659] = { 65, 65, 90, 115 },
        [3304] = { 0, 0, 65, 75 },
        [3307] = { 125, 130, 135, 140 },
        [3308] = { 155, 170, 177, 185 },
        [3569] = { 165, 165, 165, 165 },
        [10097] = { 175, 175, 175, 175 },
        [10098] = { 0, 230, 230, 230 },
        [14891] = { 0, 230, 230, 230 },
        [16153] = { 250, 250, 250, 250 },
        [22967] = { 0, 310, 315, 320 },
        [1213638] = { 0, 315, 322, 330 },
        [1230161] = { 0, 20, 22, 25 },
        [1249637] = { 0, 275, 275, 275 },
        [1262975] = { 0, 140, 142, 145 },
        [1263071] = { 0, 300, 300, 300 },
        [1306126] = { 0, 300, 307, 315 },
    },
    -- <<< gen_skill_colors.lua

    -- >>> gen_sources.lua (généré — Wowhead forever ; ne pas éditer à la main)
    -- où s'obtient le PLAN : [spellID] = "vendor" | "drop" | "quest"
    -- (le formateur ne s'écrit pas : il se DÉDUIT de l'absence d'objet-recette)
    recipeSource = {
    },
    -- <<< gen_sources.lua

    -- >>> gen_origins.lua (généré — Wowhead forever, pages d'objet ; ne pas éditer à la main)
    -- QUI est derrière le plan : [spellID] = { { id, areaID, "nom", faction }, ... }
    -- faction "A"/"H" = ce camp SEULEMENT ; nil = les deux, ou inconnue.
    -- Le SENS des entrées vient de `recipeSource` : marchand, créature, ou quête.
    recipeOrigin = {
    },
    -- PRIX du plan chez son marchand, en cuivre. Absent = inconnu, JAMAIS zéro.
    recipePrice = {
    },
    -- <<< gen_origins.lua
})
