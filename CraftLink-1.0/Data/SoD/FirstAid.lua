-- Data/SoD/FirstAid.lua — couche saisonnière « Saison de la Découverte » (seasonId 2).
-- GÉNÉRÉ par tools/gen_season.lua — NE PAS ÉDITER À LA MAIN.
-- Source : Wowhead (domaine « classic », lignes taguées seasonId:2).
--
-- ADDITIF : ces recettes sont AJOUTÉES EN FIN du set Vanilla, dont les positions de bits (donc les
-- bitfields du registre déjà diffusés) restent intactes. Le fichier s'auto-désactive hors saison.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end
if CraftLink:ActiveSeason() ~= 2 then return end   -- couche inerte hors de sa saison

CraftLink:ExtendProfession("First Aid", {
    -- recettes saisonnières (appondues à la suite du set de base, jamais insérées)
    recipes = {
        470349,
    },
    itemToSpell = {
        [232433] = 470349,
    },
    produces = {
        [470349] = 232433,
    },
    reagents = {
        [470349] = { {14530,2} },
    },
    learnedAt = {
        [470349] = 315,
    },
    taughtBy = {
        [232434] = 470349,
    },
})
