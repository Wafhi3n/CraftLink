-- CraftLink_Locale_esES.lua — overlay ESPAGNOL (esES/esMX). Clé FR → texte ES.
-- Chargé APRÈS CraftLink_Locale.lua (qui crée NS.L). Sur un client non espagnol : early-return.
local _, NS = ...
NS = NS or _G.CraftLink
if not NS or not NS.L then return end

local locale = GetLocale and GetLocale() or "enUS"
if locale ~= "esES" and locale ~= "esMX" then return end

local T = {
    ["en pause : Crafting Order partage déjà tes recettes. CraftLink prendra le relais quand Crafting Order sera à jour."]
        = "en pausa: Crafting Order ya comparte tus recetas. CraftLink tomará el relevo cuando Crafting Order esté actualizado.",
    ["partage actif, %d artisan(s) connu(s) ; canal global : %s"] = "compartir activo, %d artesano(s) conocido(s); canal global: %s",
    ["rejoint"] = "unido",
    ["pas rejoint (/craftlink global pour le rejoindre)"] = "no unido (/craftlink global para unirte)",
    ["canal global rejoint."] = "te has unido al canal global.",
    ["canal global quitté."] = "has salido del canal global.",
    ["version %s. Commandes : /craftlink (état), /craftlink global, /craftlink global off"]
        = "versión %s. Comandos: /craftlink (estado), /craftlink global, /craftlink global off",
}
for k, v in pairs(T) do NS.L[k] = v end
