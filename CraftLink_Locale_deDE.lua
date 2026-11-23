-- CraftLink_Locale_deDE.lua — overlay ALLEMAND (deDE). Clé FR → texte DE.
-- Chargé APRÈS CraftLink_Locale.lua (qui crée NS.L). Sur un client non allemand : early-return.
local _, NS = ...
NS = NS or _G.CraftLink
if not NS or not NS.L then return end

if (GetLocale and GetLocale() or "enUS") ~= "deDE" then return end

local T = {
    ["en pause : Crafting Order partage déjà tes recettes. CraftLink prendra le relais quand Crafting Order sera à jour."]
        = "pausiert: Crafting Order teilt deine Rezepte bereits. CraftLink übernimmt, sobald Crafting Order aktualisiert ist.",
    ["partage actif, %d artisan(s) connu(s) ; canal global : %s"] = "Teilen aktiv, %d Handwerker bekannt; globaler Kanal: %s",
    ["rejoint"] = "beigetreten",
    ["pas rejoint (/craftlink global pour le rejoindre)"] = "nicht beigetreten (/craftlink global zum Beitreten)",
    ["canal global rejoint."] = "dem globalen Kanal beigetreten.",
    ["canal global quitté."] = "globalen Kanal verlassen.",
    ["version %s. Commandes : /craftlink (état), /craftlink global, /craftlink global off"]
        = "Version %s. Befehle: /craftlink (Status), /craftlink global, /craftlink global off",
}
for k, v in pairs(T) do NS.L[k] = v end
