-- Data/SoD/Mining.lua — couche saisonnière « Saison de la Découverte » (seasonId 2).
-- GÉNÉRÉ par tools/gen_season.lua — NE PAS ÉDITER À LA MAIN.
-- Source : Wowhead (domaine « classic », lignes taguées seasonId:2).
--
-- ADDITIF : ces recettes sont AJOUTÉES EN FIN du set Vanilla, dont les positions de bits (donc les
-- bitfields du registre déjà diffusés) restent intactes. Le fichier s'auto-désactive hors saison.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end
if CraftLink:ActiveSeason() ~= 2 then return end   -- couche inerte hors de sa saison

CraftLink:ExtendProfession("Mining", {
    -- recettes saisonnières (appondues à la suite du set de base, jamais insérées)
    recipes = {
        1213638,
    },
    itemToSpell = {
        [234003] = 1213638,
    },
    produces = {
        [1213638] = 234003,
    },
    reagents = {
        [1213638] = { {12655,2}, {22203,2} },
    },
    learnedAt = {
        [1213638] = 315,
    },
})
