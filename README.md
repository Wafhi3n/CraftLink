# CraftLink-1.0

Librairie **embarquée** (LibStub) — infrastructure partagée des addons de craft WoW Classic Era.
Source canonique unique ; **pas un addon installé séparément**.

## Ce qu'elle fournit (infra générique seulement)

- **Catalogue de recettes** canonique (`CraftLink-1.0.lua`) — index des positions de bits par métier.
- **Codec hex du registre** (`CraftLink_Registry.lua`) — « quelles recettes je connais » en bitfield
  compact, diffusable en un addon message.
- **Versions** : `dataVersion` (compat des index de bits) + `protocolVersion` (compat du wire).
- *(à venir)* **Transports** : canal global caché / guilde (GUILD + GreenWall) / proximité (SAY/YELL).

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

- **Guild Economy** (TradeScanner) — scanner d'offres + « can craft ».
- **Crafting Order - Classic** — réseau global/social de commandes de craft.
