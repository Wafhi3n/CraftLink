# CraftLink devient l'addon qui partage les recettes connues

> État : **approuvée** · Décisions A1-A11 du user le 2026-11-23 · Protocole figé (test), rien de codé dans l'addon
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
- Par défaut, CraftLink ne cherche ses pairs que dans la **guilde** et la **liste d'amis**. Le canal global (la
  salle de découverte) ne se rejoint que sur une commande du joueur (A11).
- **CraftLink-Discord**, plus tard, s'appuie sur CraftLink pour envoyer les métiers au bot (contrat `CM1` de la spec
  du bot).

## Ce qu'on NE fait PAS

- **Changer le protocole.** Mêmes verbes, mêmes messages, au caractère près : les COC déjà installés (v1.53.0 et
  avant) doivent voir un joueur CraftLink seul, et inversement.
- **Sortir les commandes, la recherche de travail (LFW), les rerolls, la confiance, les temps de recharge** : ils
  restent dans COC (A3). Ce n'est que la première découpe.
- **Toucher TradeScanner** (Era, gelé) : il garde sa copie embarquée de la bibliothèque.
- **Écrire CraftLink-Discord ici** : sa propre spec, une fois cette découpe faite.
- **Repenser le canal global ici.** Le user (2026-11-23) : il faudra le réingénierer, parce que l'identifiant du
  royaume sous-jacent (le « layer », que lit `GetRealmID`) ne sera bientôt plus lisible (source et date pas
  données). La 0.1.0 reprend la salle telle que COC la fait aujourd'hui, derrière `/craftlink global` (A11) ; la
  refonte aura sa propre spec. Sans cet identifiant, le code actuel envoie déjà un `SK` et un `HI` sans `rm=`, que
  tous les COC lisent (test du protocole, « sans métier ni royaume »).

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

Ajusté à la copie (étape 3, 2026-11-23) : de `Directory_Community.lua`, seule la **glue réseau** part
(`OnlinePeers`, `MarkOffline`, `_WireNoChannel`). La communauté officielle (coupée depuis le 2026-09-29), le lien
« Rejoindre », `COC:NetworkLabel` restent chez COC : ils s'appuient sur ses cercles (`Directory_Club`). De
`Directory_Room.lua`, `RoomCmd` et `RoomStatusLine` (la commande et la ligne de `/co`) restent aussi chez COC.

## Cas particuliers

- **Un ancien COC (qui embarque encore CraftLink) avec le nouvel addon CraftLink installé** : LibStub ne garde
  qu'une instance, et les deux annuaires y brancheraient leurs gestionnaires (la bibliothèque accepte plusieurs
  gestionnaires par verbe) : deux PONG, deux annonces. CraftLink détecte un COC qui tient encore son propre
  annuaire et se tait, en le disant une fois au joueur. Ce sera le cas de **tous** les premiers joueurs de
  CraftLink 0.1.0 qui ont COC (A8) : la garde est dans la 0.1.0. Sans dépendance, l'ordre de chargement des deux
  addons n'est pas garanti : la garde regarde une fois les deux chargés, jamais au chargement de CraftLink seul.
- **La même bibliothèque, deux copies** (relevé le 2026-11-23) : COC v1.53.0 embarque `CraftLink-1.0` au même
  numéro LibStub que la source (16), mais avec des données plus anciennes (`Data/Camelot`, build 70938 pas encore
  sorti dans COC). À numéro égal, LibStub garde la première copie chargée. Ce que l'ancien COC ne doit pas recevoir
  va dans les fichiers propres de l'addon CraftLink, pas dans la bibliothèque partagée sous un numéro plus haut ; et
  COC v1.53.0 doit marcher pareil quelle que soit la copie gardée. Le CODE des deux copies est identique ; les
  fichiers de DONNÉES, eux, s'inscrivent sans garde dans la même bibliothèque (`RegisterProfession` fusionne) :
  les deux jeux tournent, le dernier chargé l'emporte. Ils ne diffèrent que des corrections du build 70938. Sur
  Forever, le registre part en identifiants (RI), lisibles quelle que soit la donnée ; seule la découpe par palier
  peut changer, et le receveur la lit telle qu'elle arrive.
- **Un joueur de COC v1.53 ne distingue pas un artisan CraftLink seul d'un artisan COC** (voulu : A2, A7). Une
  commande qu'il lui pousse ou lui adresse reste sans réponse : limite connue de la 0.1.0. Le signe existe déjà sur
  le réseau : le `SK` d'un CraftLink seul n'a pas de `cv=` (ni `rep=`, ni `rl=1`) ; un COC à venir pourra s'en
  servir pour ne pas lui proposer de commande. Relecture réseau du 2026-11-23 : le signe est ambigu (un build de
  dev de COC omet aussi `cv=`, un vieux COC n'a pas `rl=1`) ; une preuve positive vaudra mieux, par exemple un
  premier `ORD` ou un accusé reçu de lui. Les chemins concernés chez COC : le transfert d'une commande captée
  (`CraftingOrderClassic_Handoff.lua`, `CanCraft`) et les `ORD NEW` poussés à l'arrivée d'un artisan
  (`Orders.lua`, `OnArtisanOnline`).
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
- 2026-11-23, agent, **confirmé par le user** le même jour (A3) : la ligne de découpe du tableau ci-dessus.
  Partent la découverte, l'échange des recettes et des niveaux, le roster et la présence ; le reste ne bouge pas.
- 2026-11-23, agent, **confirmé par le user** (A4) : pont entre royaumes et relais restent dans COC pour la première
  découpe.
- 2026-11-23, agent, **confirmé par le user** (A5) : chaque addon garde ses propres champs ; l'annuaire de COC est
  recopié une seule fois dans CraftLink (personne ne perd ses artisans connus).
- 2026-11-23, agent, **confirmé par le user** (A6) : sur CurseForge, CraftLink est une **dépendance obligatoire** de
  COC (relation « Required Dependency » : l'appli CurseForge l'installe toute seule). Onglet Source réglé avant le
  premier tag du nouveau projet.
- 2026-11-23, **user** (A8) : **CraftLink sort seul d'abord.** CraftLink 0.1.0 partage les recettes et vit à côté
  du COC actuel, qui ne change pas ; le user crée le projet, CurseForge le valide ; **ensuite seulement** sort une
  version de COC sans sa copie, avec la dépendance (A6). Raison : la modération ne valide un projet neuf qu'avec un
  vrai fichier, et la dépendance obligatoire suppose un projet en ligne. Remplace « une seule release pour les
  deux » de l'ancien plan.
- 2026-11-23, **user** (A9, définitif dès la première publication) : dossier et `.toc` **`CraftLink`**, sauvegarde
  **`CraftLinkDB`**, adresse CurseForge **`craftlink`** (variante seulement si elle est prise).
- 2026-11-23, **user** (A10) : une commande d'état **`/craftlink`**, tapée par le joueur seulement, qui répond en une
  ligne (« partage actif, N artisans connus dans la guilde »). Rien ne s'affiche jamais tout seul, hors du message
  unique de la garde. Pour le joueur, et pour qu'un modérateur voie que l'addon marche.
- 2026-11-23, **user** (A11) : de base, CraftLink n'utilise que la **liste d'amis et la guilde** ; le joueur tape une
  commande `/craftlink` pour **rejoindre le global** (la salle de découverte). L'avis de COC « l'addon rejoint le
  canal… » n'est donc pas écrit par CraftLink : `/craftlink` dit si le global est rejoint et comment le rejoindre.
  Forme proposée par l'agent, **confirmée par le user** le même jour : `/craftlink` = l'état ; `/craftlink global`
  rejoint le global, `/craftlink global off` le quitte ; retenu d'une session à l'autre dans `CraftLinkDB`.
  **À trancher à l'étape 6** : COC fait rejoindre la salle par défaut
  (aujourd'hui) ; une fois qu'il dépend de CraftLink, garde-t-il le global allumé pour ses joueurs ?
- 2026-11-23, **user** (A7, réponse à Q1) : un joueur qui n'a **que** CraftLink ne voit rien. Il **partage ses
  infos**, et donc aussi avec le GM et les officiers. Ceux-ci, avec **CraftLink-Discord**, mettent à jour la base
  du bot Discord avec tout ce que leur CraftLink sait (M6 de la spec du bot). CraftLink seul s'installe donc parce
  que la guilde le demande, pas pour ce qu'il montre.

## Critères d'acceptation

1. [test] Les messages construits par CraftLink (`HI`, `SK`, `RK`, `RI`, `PING`, `PONG`) sont identiques, octet pour
   octet, à ceux de COC v1.53.0 pour le même perso. Fixtures tirées de la v1.53.0. → suite headless de l'outillage.
2. [test] Un COC qui charge l'annuaire de CraftLink voit les mêmes artisans, avec les mêmes recettes, qu'avant la
   découpe (même roster de départ, mêmes messages reçus).
3. [test] La migration recopie le roster une fois, garde les champs de COC chez COC, et ne refait rien au second
   lancement.
4. [check] Les quatre portes passent pour CraftLink (déclaré `addon` dans `addons.json`) et pour COC.
5. [agent] `craftlink-protocol-reviewer` ne trouve aucun changement de protocole ; `api-gotcha-reviewer` rien de neuf.
6. [humain] Le perso du user avec **CraftLink seul** : les vrais guildiens qui ont COC (v1.53.0, publié) le voient
   comme artisan avec ses recettes. Le user n'a qu'un perso sur le live (dit le 2026-11-23) : la moitié qu'il
   observe seul est la réponse des guildiens à son bonjour (compte de `/craftlink`, roster de `CraftLinkDB` lu
   après la séance) ; l'annuaire vu de l'autre côté demande un guildien qui accepte de regarder. Témoin : le perso
   avec COC, avant la découpe. Observateur : le user (et ce guildien).
7. [humain] Le perso du user avec le nouvel ensemble, un vrai joueur avec COC v1.53.0 (ancien) : chacun voit
   l'autre, et une commande fait son cycle complet. Témoin : la validation à deux comptes du cycle de commande.
   Observateur : le user et ce joueur (un seul perso sur le live : pas de second compte à soi).
8. [humain] Un ancien COC avec le nouvel addon CraftLink : un seul PONG par PING (trace `/co trace`), un message
   unique au joueur, et COC marche comme avant (annuaire, commandes). Un seul perso suffit, en cochant les addons
   tour à tour. Témoin : les gestionnaires réseau de la bibliothèque avec COC seul (`_handlers`, mêmes nombres).
   Observateur : le user.
9. [humain] `/craftlink` répond en une ligne : partage actif, nombre d'artisans connus, global rejoint ou non.
   Sans la commande, CraftLink n'écrit rien dans le chat. Témoin : le nombre d'artisans de l'annuaire de COC sur le
   même compte. Observateur : le user.
10. [humain] Sans la commande du global, CraftLink ne rejoint aucun canal (liste des canaux du chat) et voit quand
    même un membre de la guilde ou un ami qui l'a. Après la commande, il est dans le global, et y revient après un
    `/reload`. Témoin : la liste des canaux avant et après. Observateur : le user.

## Contrat (CraftLink 0.1.0 ↔ COC de l'étape 6)

Ce que COC lira et étendra une fois qu'il dépendra de CraftLink. Figé dès la 0.1.0 publiée : le changer casse le COC
qui s'y branche.

- **L'annuaire** : `_G.CraftLink.Directory` (`Dir`), avec `Dir.roster` (dans `CraftLinkDB.roster`), `Dir.online`,
  `Dir.onlineGame`, `Dir.mySkills`. COC y pose ses propres méthodes, comme aujourd'hui sur `COC.Directory` (relais,
  pont, temps de recharge, rerolls, LFW, version : `StartX`, `AnnounceCooldowns`, `AnnounceAlts`, `OnTrustEnvelope`,
  `_MyVersion`, `_IsDevBuild`, `NotePeerVersion`, `LFWRiposte`, `RelayPartnersTo`, `BridgeOnRoomHello`, `Bridge*`,
  `Prune*`, `ForEachCircleMemberOnline`, `_WireGreenWall`, `_WireClubs`).
- **Les points d'accroche** (méthodes optionnelles de `Dir`, absentes quand CraftLink est seul ; ce que COC faisait
  lui-même) : `OnArtisanOnline(nom)`, `OnAddedOnline(nom)`, `OnLinked(nom)`, `OnChanged()`, `OnSkillGain()`,
  `RebroadcastMine()`, `Beacon()`, `Trace(catégorie, texte)`, `Delivered()` → nombre (le `rep=` du SK),
  `OnMySkills(niveaux)`, `OnMarkOffline(nom)`. Appelées en méthode, `self` = `Dir` : COC écrit
  `Dir.OnArtisanOnline = function(_, nom) COC.Orders:OnArtisanOnline(nom) end`. Un nom mal écrit échoue en silence.
  `OnMarkOffline` doit refaire ce que faisait l'ancien `MarkOffline` : éteindre `Dir.lfw[nom]` et rafraîchir la
  plaque (`Nameplate:Refresh`). `RebroadcastMine` doit être posée avant `Dir:Start`.
- **La garde** : un COC qui lit l'annuaire de CraftLink pose `CraftingOrderClassic.sharesViaCraftLink = true` ; sans
  lui, CraftLink se met en pause (A8).
- **La salle** : `Dir:SetRoom(on)` écrit `CraftLinkDB.global` (A11), plus `roomOff` de COC ; `Dir:RoomEnabled()` le lit.

## Plan (2026-11-23, revu après A8 ; à jeter une fois fait)

1. ~~Reconfirmation de A3-A6~~ (faite le 2026-11-23, plus A8-A10).
2. ~~Fixtures de protocole tirées de COC v1.53.0~~ (faites le 2026-11-23 : `tests/test_craftlink_protocole.lua`
   de l'outillage, dans `master`).
3. (Codée le 2026-11-23 sur `feat/craftlink-addon` des deux dépôts, quatre portes vertes ; reste le critère 5,
   la revue des agents, sur la demande du user. Fusion : CraftLink `main` d'abord, puis l'outillage le même jour.)
   CraftLink 0.1.0 : déclaration `addon` dans `addons.json` (`"banc": true`, branche de l'outillage, fusion sur
   l'accord du user), `CraftLink.toc`, `CraftLinkDB`, `.pkgmeta` ; les modules du partage **copiés** depuis COC sans
   changer leur sortie (COC garde les siens jusqu'à l'étape 6) ; la garde contre l'ancien COC ; `/craftlink`.
   Critères 1, 4, 5, 9, 10.
4. Banc sur le seul perso du live, trois connexions (COC seul, COC + CraftLink, CraftLink seul) : critères 8, 9,
   10, et la moitié de 6 qui se voit sans autre joueur (fiche `CraftLink--feat-craftlink-addon`, 2026-11-23).
5. Le user crée le projet CurseForge (`craftlink`), règle l'onglet Source, la page est écrite (skill
   `curseforge-copy`) ; tag `v0.1.0` sur son feu vert ; modération.
6. Après la validation : COC sans `Libs/CraftLink-1.0` ni `sync-libs.ps1` côté COC, `## Dependencies: CraftLink`,
   dépendance obligatoire sur CurseForge, lecture de l'annuaire de CraftLink, migration. Critères 2, 3, 7.
7. CraftLink-Discord : sa spec, puis son code (spec du bot, M12).

## Liens

- `CraftingOrderClassic/Directory*.lua` et `Orders.lua` (les gestionnaires de verbes), `CraftLink-1.0/CraftLink_Transport.lua`
  (`RegisterHandler`, plusieurs gestionnaires par verbe).
- `CraftingOrderBot/docs/specs/metiers-guilde.md` (M7, M12 : l'envoi au bot).
- `CraftingOrderClassic/docs/specs/pont-royaumes.md`, `relais-confiance.md` (ce qui reste dans COC pour l'instant).
- Skill `wow-classic-addon-dev` (architecture, portes, banc), agent `craftlink-protocol-reviewer`.
