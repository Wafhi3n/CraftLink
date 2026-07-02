# CraftLink-1.0

Librairie **embarquée** (LibStub) — infrastructure partagée des addons de craft WoW Classic Era.
Source canonique unique ; **pas un addon installé séparément**.

## Ce qu'elle fournit (infra générique seulement)

- **Catalogue de recettes** canonique (`CraftLink-1.0.lua`) — index des positions de bits par métier.
- **Métadonnées de recettes** (`Data/<flavor>/`) : `produces` (objet produit), `reagents`
  (composants), `learnedAt` (niveau d'apprentissage), `taughtBy` (objet-plan → sort enseigné) —
  accesseurs `RecipeProduct` / `RecipeReagents` / `RecipeLearnedAt` / `RecipeFromPlanItem`.
- **Codec hex du registre** (`CraftLink_Registry.lua`) — « quelles recettes je connais » en bitfield
  compact, diffusable en un addon message.
- **Versions** : `dataVersion` (compat des index de bits) + `protocolVersion` (compat du wire).
- **Transports** (`CraftLink_Transport.lua`) : découverte par balise texte (hardware event) +
  données en WHISPER dirigé.

> Ce qui touche les **gens** (présence, profils, favoris, réputation) **n'est pas** ici — ça vit
> dans le produit *Crafting Order - Classic*. CraftLink ne connaît ni l'UI ni le skin de l'hôte.

## Distribution

Modèle Ace : **repo propre** (versionné, tags) **+ embarquée** dans chaque addon. Les utilisateurs
n'installent que les addons ; LibStub ne garde qu'une instance au runtime (version la plus haute).

- Source de vérité : ce repo (`CraftLink-1.0/`, `LibStub/`).
- Sync vers les addons hôtes : `sync-libs.ps1` (copie dans `Addon/Libs/`).
- Inclusion côté addon : une seule ligne `.toc` → `Libs\CraftLink-1.0\lib.xml`.
- Packaging CurseForge : `.pkgmeta` (projet « Library », embarqué dans les addons hôtes).

## Addons hôtes

- **Crafting Order - Classic** — réseau global/social de commandes de craft. Seul addon
  embarquant CraftLink aujourd'hui.

> **Guild Economy (TradeScanner) n'embarque plus CraftLink depuis sa v2.0.0** (2026-06-30,
> « Étape F ») : le craft-social (registre, roster, fenêtre métier) a été retiré de TS et vit
> désormais exclusivement dans Crafting Order - Classic. TS est un pur scanner d'offres de trade.

## Outillage de génération

`tools/` (déplacé depuis `TradeScanner/tools/` le 2026-07-02) contient la chaîne de génération
hors-ligne des données par métier (`CraftLink-1.0/Data/<flavor>/*.lua`) — source courante :
**Wowhead** (MTSL = provenance historique du set Vanilla figé). Outils clés :
`gen_metadata.lua` (complète learnedAt/taughtBy, idempotent) et `check_dataversion.lua`
(garde l'invariant Vanilla `1792301894`). Voir `tools/README.md`.
