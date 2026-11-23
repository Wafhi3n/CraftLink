-- CraftLink_Locale_enUS.lua — overlay ANGLAIS (enUS/enGB). Clé FR → texte EN.
-- Chargé APRÈS CraftLink_Locale.lua (qui crée NS.L). Sur un client non anglais : early-return.
local _, NS = ...
NS = NS or _G.CraftLink
if not NS or not NS.L then return end

local locale = GetLocale and GetLocale() or "enUS"
if locale ~= "enUS" and locale ~= "enGB" then return end

local T = {
    ["en pause : Crafting Order partage déjà tes recettes. CraftLink prendra le relais quand Crafting Order sera à jour."]
        = "paused: Crafting Order already shares your recipes. CraftLink will take over once Crafting Order is updated.",
    ["partage actif, %d artisan(s) connu(s) ; canal global : %s"] = "sharing on, %d crafter(s) known; global channel: %s",
    ["rejoint"] = "joined",
    ["pas rejoint (/craftlink global pour le rejoindre)"] = "not joined (/craftlink global to join it)",
    ["canal global rejoint."] = "global channel joined.",
    ["canal global quitté."] = "global channel left.",
    ["version %s. Commandes : /craftlink (état), /craftlink global, /craftlink global off"]
        = "version %s. Commands: /craftlink (status), /craftlink global, /craftlink global off",
    ["à l'arrêt : la bibliothèque CraftLink-1.0 ne s'est pas chargée (essaie /reload)."]
        = "stopped: the CraftLink-1.0 library did not load (try /reload).",
    ["ouvre chacun de tes métiers une fois pour partager tes recettes."] = "open each of your professions once to share your recipes.",
    ["dernière erreur de lecture du métier : %s"] = "last profession read error: %s",
}
for k, v in pairs(T) do NS.L[k] = v end
