# CraftLink devient l'addon qui partage les recettes connues

> État : **brouillon** · Direction et décisions A1-A2 du user le 2026-11-23 · Rien de codé · Q1 ouverte
> Portée : CraftLink (dépôt `Wafhi3n/CraftLink`) et Crafting Order - Classic (COC) · Cible : WoW: Forever

## Le problème

Crafting Order est monolithique : 175 fichiers Lua, environ 39 700 lignes. Le partage des recettes connues
(qui a l'addon, qui sait crafter quoi, qui est en ligne) est enfoui dans son annuaire (`Directory*.lua`), mêlé
aux commandes, à la recherche de travail, aux rerolls et à la confiance. Conséquences :

- Un joueur qui veut seulement **montrer ses métiers** à la guilde doit installer tout COC.
- Le bot Discord a besoin d'un envoyeur de métiers (`CraftingOrderBot/docs/specs/metiers-guilde.md`, M12) ; le
  mettre dans COC ferait grossir encore le monolithe.
- CraftLink est une bibliothèque **embarquée** (`Libs/CraftLink-1.0`, recopiée par `sync-libs.ps1`), et la copie de
  COC a déjà pris du retard sur la source (constaté le 2026-09-29).

## Ce qu'on veut

- **CraftLink est un addon à part**, installé comme les autres. Il partage les recettes connues du joueur sur le
  réseau et tient l'annuaire de ceux qui l'ont aussi : leurs métiers, leurs niveaux, leurs recettes, leur présence.
- **COC n'embarque plus CraftLink** : il en dépend, et lit l'annuaire que CraftLink tient.
- Un joueur avec **CraftLink seul** est vu comme artisan par les joueurs de COC, exactement comme un joueur de COC.
- **CraftLink-Discord**, plus tard, s'appuie sur CraftLink pour envoyer les métiers au bot (contrat `CM1` de la spec
  du bot).

## Ce qu'on NE fait PAS

- **Changer le protocole.** Mêmes verbes, mêmes messages, au caractère près : les COC déjà installés (v1.53.0 et
  avant) doivent voir un joueur CraftLink seul, et inversement.
- **Sortir les commandes, la recherche de travail (LFW), les rerolls, la confiance, les temps de recharge** : ils
  restent dans COC (A3). Ce n'est que la première découpe.
- **Toucher TradeScanner** (Era, gelé) : il garde sa copie embarquée de la bibliothèque.
- **Écrire CraftLink-Discord ici** : sa propre spec, une fois cette découpe faite.

## Ce qui part de COC (relu le 2026-11-23)

| Part dans CraftLink (A3) | Reste dans COC |
|---|---|
| `Directory.lua` (verbes `RK`, `RI`, `SK`, `HI`, `PING`, `PONG`, roster, purge) | `Orders*` (`ORD` ; il écoute aussi `HI` et `PING`) |
| `Directory_Recipes.lua` (lecture du registre reçu) | `Directory_LFW.lua` (`LFW`, `LFO`, `LFR`) |
| `Directory_Skills.lua` (niveaux, fil `SK`) | `Directory_Alts.lua` + `AltCodec` (`ALT`) |
| `Directory_Presence.lua` (présence jeu + addon) | `Directory_Cooldowns.lua` (`CD`) |
| `Directory_Community.lua` (le réseau sans canal) | `Directory_Relay*` / `TrustRelay` (`RLY`, `RL`, `RLA`, `VRF`) |
| `Directory_Room.lua` (salle de découverte) | `Directory_Bridge.lua` (`INT`, `HL`, pont entre royaumes) |
| | `Directory_Club`, `Confed`, `Note`, `LootScan`, `MyArtisans`, `Version` |

Environ 1 400 lignes partent. Le pont entre royaumes et les relais touchent aussi au partage : ils restent dans COC
pour cette première découpe, et se décideront après (A4). `Directory_Version.lua` reste dans COC : c'est la version
**de COC** qu'il annonce, dans le fil `SK`, ce qui demande une couture (cas particuliers).

## Cas particuliers

- **Un ancien COC (qui embarque encore CraftLink) avec le nouvel addon CraftLink installé** : LibStub ne garde
  qu'une instance, et les deux annuaires y brancheraient leurs gestionnaires (la bibliothèque accepte plusieurs
  gestionnaires par verbe) : deux PONG, deux annonces. CraftLink détecte un COC qui tient encore son propre
  annuaire et se tait, en le disant une fois au joueur.
- **COC installé sans CraftLink** : COC ne se charge pas (dépendance obligatoire, A1). Le jeu affiche « dépendance
  manquante ». Le texte de la page CurseForge et du CHANGELOG le dit en premier.
- **Joueur CraftLink seul** : aucune commande COC, aucune recherche de travail. Il est listé comme artisan, et la
  carte du bot ne lui donne jamais d'étoile ★ (M7 de la spec du bot).
- **La version de COC dans le fil `SK`** (pseudo-morceau `cv=`) : c'est CraftLink qui construit `SK`. Il offre à COC
  une façon d'y ajouter ses morceaux, sans rien changer à ce qui part sur le réseau.
- **Les fiches du roster mêlent les deux mondes** : métiers, niveaux, présence, source (CraftLink) et LFW, rerolls,
  temps de recharge, relais (COC). Chaque addon garde **ses** champs dans **sa** sauvegarde, par nom de perso (A5).
- **Migration** : le premier lancement du nouvel ensemble recopie une seule fois le roster de
  `CraftingOrderClassicDB` dans la sauvegarde de CraftLink, compte par compte, puis n'y touche plus (A5).
- **Combat, taint, valeurs secrètes** : rien ne change, c'est le même code qui change d'addon. La revue
  `api-gotcha-reviewer` le confirme quand même.

## Décisions

- 2026-11-23, **user** (A1) : COC **n'embarque plus** CraftLink. CraftLink est un addon à installer, dont COC
  dépend.
- 2026-11-23, **user** (A2) : ce que CraftLink sépare de COC, c'est **le partage des recettes connues par le canal
  de communication** (le réseau). Le reste de COC ne bouge pas pour l'instant.
- 2026-11-23, agent, **à reconfirmer** (A3) : la ligne de découpe du tableau ci-dessus. Partent la découverte,
  l'échange des recettes et des niveaux, le roster et la présence ; le reste ne bouge pas.
- 2026-11-23, agent, **à reconfirmer** (A4) : pont entre royaumes et relais restent dans COC pour la première
  découpe.
- 2026-11-23, agent, **à reconfirmer** (A5) : chaque addon garde ses propres champs ; migration une seule fois.
- 2026-11-23, agent, **à reconfirmer** (A6) : sur CurseForge, CraftLink est une **dépendance obligatoire** de COC
  (relation « Required Dependency » : l'appli CurseForge l'installe toute seule). Onglet Source réglé avant le
  premier tag du nouveau projet.

## Questions ouvertes

- **Q1 (user)** : que voit un joueur qui n'a **que** CraftLink ? Rien (il partage en silence), une ligne
  « fabricable par X, Y » dans l'infobulle des objets, ou une petite liste par commande. S'il ne voit rien, peu de
  gens l'installeront seul.

## Critères d'acceptation

1. [test] Les messages construits par CraftLink (`HI`, `SK`, `RK`, `RI`, `PING`, `PONG`) sont identiques, octet pour
   octet, à ceux de COC v1.53.0 pour le même perso. Fixtures tirées de la v1.53.0. → suite headless de l'outillage.
2. [test] Un COC qui charge l'annuaire de CraftLink voit les mêmes artisans, avec les mêmes recettes, qu'avant la
   découpe (même roster de départ, mêmes messages reçus).
3. [test] La migration recopie le roster une fois, garde les champs de COC chez COC, et ne refait rien au second
   lancement.
4. [check] Les quatre portes passent pour CraftLink (déclaré `addon` dans `addons.json`) et pour COC.
5. [agent] `craftlink-protocol-reviewer` ne trouve aucun changement de protocole ; `api-gotcha-reviewer` rien de neuf.
6. [humain] Au banc, compte A avec COC + CraftLink, compte B avec **CraftLink seul** : A voit B comme artisan avec
   ses recettes dans l'annuaire de COC. Témoin : B avec COC, avant la découpe. Observateur : le user.
7. [humain] Au banc, compte A avec le nouvel ensemble, compte B avec COC v1.53.0 (ancien) : chacun voit l'autre, et
   une commande fait son cycle complet. Témoin : la validation à deux comptes du cycle de commande. Observateur : le
   user.
8. [humain] Un ancien COC avec le nouvel addon CraftLink : un seul PONG par PING (trace `/co trace`), un message
   unique au joueur. Observateur : le user.

## Plan (2026-11-23, à jeter une fois fait)

1. Réponse du user à Q1, reconfirmation de A3-A6.
2. Fixtures de protocole tirées de COC v1.53.0 (critère 1), avant de déplacer quoi que ce soit.
3. CraftLink : déclaration `addon` (branche de l'outillage), `.toc` de l'addon, sauvegarde ; les modules du partage
   déplacés depuis COC sans changer leur sortie. Critères 1, 4, 5.
4. COC : retrait de `Libs/CraftLink-1.0` et de `sync-libs.ps1` côté COC, `## Dependencies: CraftLink`, lecture de
   l'annuaire de CraftLink, migration. Critères 2, 3.
5. Banc à deux comptes : critères 6 à 8. Une seule release qui sort les deux addons le même jour.
6. CraftLink-Discord : sa spec, puis son code (spec du bot, M12).

## Liens

- `CraftingOrderClassic/Directory*.lua` et `Orders.lua` (les gestionnaires de verbes), `CraftLink-1.0/CraftLink_Transport.lua`
  (`RegisterHandler`, plusieurs gestionnaires par verbe).
- `CraftingOrderBot/docs/specs/metiers-guilde.md` (M7, M12 : l'envoi au bot).
- `CraftingOrderClassic/docs/specs/pont-royaumes.md`, `relais-confiance.md` (ce qui reste dans COC pour l'instant).
- Skill `wow-classic-addon-dev` (architecture, portes, banc), agent `craftlink-protocol-reviewer`.
