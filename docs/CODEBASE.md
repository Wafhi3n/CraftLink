# CraftLink — carte du code

> **GÉNÉRÉ** le 2026-11-23 (v0.1.0) par `scripts\gen_docs.ps1` — ne pas éditer à la main :
> relancer le script (deploy.ps1 le fait) après un changement de structure. Source de chaque
> rubrique : le `.toc` (ordre de chargement) et les commentaires d'en-tête des fichiers eux-mêmes.

6 modules + 0 entrée(s) Libs (CraftLink embarquée, documentée dans son repo).

## Modules (ordre de chargement)

| Fichier | Rôle | Lignes |
|---|---|---|
| `LibStub\LibStub.lua` | LibStub is a simple versioning stub meant for use in Libraries. | 32 |
| `CraftLink_Locale.lua` | socle de localisation du CHROME. | 14 |
| `CraftLink_Locale_enUS.lua` | overlay ANGLAIS (enUS/enGB). | 21 |
| `CraftLink_Locale_deDE.lua` | overlay ALLEMAND (deDE). | 20 |
| `CraftLink_Locale_esES.lua` | overlay ESPAGNOL (esES/esMX). | 21 |
| `CraftLink.lua` | socle de l'addon : table d'addon, réglages, SavedVariables, garde contre un ancien Crafting Order, commande /craftlink (spec docs/specs/addon-partage.md, A8 à A11). | 114 |

## Kit UI — référence `Skin.*` (extraite des fichiers *Skin*)

## Détail par module (en-tête + API publique)

### `LibStub\LibStub.lua`
> LibStub is a simple versioning stub meant for use in Libraries.
> https://www.wowace.com/projects/libstub  (public domain)
> Vendored verbatim so CraftLink-1.0 can be embedded by several addons (Guild Economy /
> TradeScanner, Crafting Order - Classic, a future TBC build) without duplicating it.

### `CraftLink_Locale.lua`
> CraftLink_Locale.lua — socle de localisation du CHROME.
> Convention de l'écosystème : la CLÉ est le texte FRANÇAIS ; `NS.L[clé]` renvoie la clé par
> défaut, donc un client FR voit le texte tel quel — aucun overlay à écrire. Chaque AUTRE langue
> est un overlay chargé APRÈS ce fichier (_Locale_enUS...), avec early-return hors de sa locale.
> 
> Le repli passe par la métatable (invisible à pairs) : la porte scripts\check_locale.ps1 peut donc
> lire exactement les clés qu'un overlay pose. Elle charge ces fichiers par dofile SANS varargs,
> d'où la reprise par la globale _G.CraftLink ci-dessous.

### `CraftLink_Locale_enUS.lua`
> CraftLink_Locale_enUS.lua — overlay ANGLAIS (enUS/enGB). Clé FR → texte EN.
> Chargé APRÈS CraftLink_Locale.lua (qui crée NS.L). Sur un client non anglais : early-return.

### `CraftLink_Locale_deDE.lua`
> CraftLink_Locale_deDE.lua — overlay ALLEMAND (deDE). Clé FR → texte DE.
> Chargé APRÈS CraftLink_Locale.lua (qui crée NS.L). Sur un client non allemand : early-return.

### `CraftLink_Locale_esES.lua`
> CraftLink_Locale_esES.lua — overlay ESPAGNOL (esES/esMX). Clé FR → texte ES.
> Chargé APRÈS CraftLink_Locale.lua (qui crée NS.L). Sur un client non espagnol : early-return.

### `CraftLink.lua`
> CraftLink.lua — socle de l'addon : table d'addon, réglages, SavedVariables, garde contre un ancien
> Crafting Order, commande /craftlink (spec docs/specs/addon-partage.md, A8 à A11).
> 
> Chargé APRÈS la locale, AVANT les modules. Les SavedVariables sont prêtes sur l'ADDON_LOADED de CET
> addon ; tout le reste attend PLAYER_LOGIN, quand TOUS les addons sont chargés : sans dépendance
> déclarée, l'ordre de chargement de CraftLink et de Crafting Order n'est pas garanti, et la garde doit
> voir les deux.
> 
> Silence au chat (A10) : CraftLink n'écrit qu'en réponse à /craftlink, plus une seule ligne, une fois
> par compte, quand la garde le met en pause.

**API** : `NS:Print(msg)` · `NS:Printf(fmt, ...)` · `NS:OldCraftingOrder()` · `NS:CheckGuard()` · `NS:CountArtisans()` · `NS:Status()` · `NS:SetGlobal(on)` · `NS:Slash(msg)`
