-- CraftLink_Locale.lua — socle de localisation du CHROME.
-- Convention de l'écosystème : la CLÉ est le texte FRANÇAIS ; `NS.L[clé]` renvoie la clé par
-- défaut, donc un client FR voit le texte tel quel — aucun overlay à écrire. Chaque AUTRE langue
-- est un overlay chargé APRÈS ce fichier (_Locale_enUS...), avec early-return hors de sa locale.
--
-- Le repli passe par la métatable (invisible à pairs) : la porte scripts\check_locale.ps1 peut donc
-- lire exactement les clés qu'un overlay pose. Elle charge ces fichiers par dofile SANS varargs,
-- d'où la reprise par la globale _G.CraftLink ci-dessous.
local _, NS = ...
NS = NS or _G.CraftLink
if not NS then return end
_G.CraftLink = NS

NS.L = setmetatable({}, { __index = function(_, k) return k end })
