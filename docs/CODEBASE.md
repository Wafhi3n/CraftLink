# CraftLink — carte du code

> **GÉNÉRÉ** le 2026-11-24 (v0.1.0) par `scripts\gen_docs.ps1` — ne pas éditer à la main :
> relancer le script (deploy.ps1 le fait) après un changement de structure. Source de chaque
> rubrique : le `.toc` (ordre de chargement) et les commentaires d'en-tête des fichiers eux-mêmes.

14 modules + 0 entrée(s) Libs (CraftLink embarquée, documentée dans son repo).

## Modules (ordre de chargement)

| Fichier | Rôle | Lignes |
|---|---|---|
| `LibStub\LibStub.lua` | LibStub is a simple versioning stub meant for use in Libraries. | 32 |
| `CraftLink_Locale.lua` | socle de localisation du CHROME. | 14 |
| `CraftLink_Locale_enUS.lua` | overlay ANGLAIS (enUS/enGB). | 25 |
| `CraftLink_Locale_deDE.lua` | overlay ALLEMAND (deDE). | 24 |
| `CraftLink_Locale_esES.lua` | overlay ESPAGNOL (esES/esMX). | 25 |
| `CraftLink_Api.lua` | les quelques adaptations d'API dont l'annuaire a besoin, reprises de CraftingOrderClassic_Compat.lua (COC v1.53.0) avec leur signature : NS.Api.X remplace COC.Api.X dans les modules copiés (spec docs/specs/addon-partage.md, étape 3). | 68 |
| `CraftLink.lua` | socle de l'addon : table d'addon, réglages, SavedVariables, garde contre un ancien Crafting Order, commande /craftlink (spec docs/specs/addon-partage.md, A8 à A11). | 144 |
| `CraftLink_Directory.lua` | l'annuaire des GENS (présence + qui peut crafter quoi), copié de Directory.lua de Crafting Order v1.53.0 (spec docs/specs/addon-partage.md, étape 3). | 494 |
| `CraftLink_Directory_Skills.lua` | niveaux de compétence (couche « profil » de l'annuaire), copié de Directory_Skills.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3). | 199 |
| `CraftLink_Directory_Recipes.lua` | COUTURE de lecture du registre « qui sait crafter quoi » d'un artisan. | 212 |
| `CraftLink_Directory_Presence.lua` | présence : la vérité JEU (amis/guilde) et sa fusion avec la vérité ADDON. | 150 |
| `CraftLink_Directory_Community.lua` | le réseau SANS canal : la glue entre la bibliothèque et l'annuaire. | 41 |
| `CraftLink_Directory_Room.lua` | la salle de découverte : le canal global rejoint pour SE PRÉSENTER, pas pour transporter. | 57 |
| `CraftLink_Mine.lua` | MES recettes et mes niveaux : ce que CraftingOrderClassic.lua (v1.53.0) faisait pour l'annuaire, repris pour CraftLink seul (spec docs/specs/addon-partage.md, étape 3). | 74 |

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

### `CraftLink_Api.lua`
> CraftLink_Api.lua — les quelques adaptations d'API dont l'annuaire a besoin, reprises de
> CraftingOrderClassic_Compat.lua (COC v1.53.0) avec leur signature : NS.Api.X remplace COC.Api.X dans
> les modules copiés (spec docs/specs/addon-partage.md, étape 3). Les raisons de chacune sont écrites
> chez COC ; elles tiennent ici telles quelles.

**API** : `A.GetBNetFriend(index)` · `A.AddChatFilter(event, fn)` · `A.IsSecret(v)` · `A.PlayerName()` · `A.IsFullPlayerName(name)`

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

**API** : `NS:Print(msg)` · `NS:Printf(fmt, ...)` · `NS:OldCraftingOrder()` · `NS:CheckGuard()` · `NS:CountArtisans()` · `NS:NoRecipeYet()` · `NS:Status()` · `NS:Start()` · `NS:ApplyGlobal(on)` · `NS:SetGlobal(on)` · `NS:Slash(msg)`

### `CraftLink_Directory.lua`
> CraftLink_Directory.lua — l'annuaire des GENS (présence + qui peut crafter quoi), copié de
> Directory.lua de Crafting Order v1.53.0 (spec docs/specs/addon-partage.md, étape 3). Présence
> (Dir.online) = qui répond ; « global » part en whisper vers ces pairs (CraftLink_Directory_Community).
> Recettes → Dir.roster (persistant, CraftLinkDB). Discipline : réseau → roster → (interface de l'hôte).
> 
> Le protocole est celui de COC v1.53.0, au caractère près (tests/test_craftlink_protocole*.lua). Ce que
> COC faisait lui-même (commandes, toasts, traces, fenêtre métier, interface) devient un POINT
> D'ACCROCHE : une méthode optionnelle de Dir, absente quand CraftLink est seul, que COC pose à l'étape 6
> (OnArtisanOnline, OnAddedOnline, OnLinked, OnChanged, OnSkillGain, RebroadcastMine, Beacon, Trace,
> Delivered, OnMySkills, OnMarkOffline). Ses modules qui étendaient déjà Dir (relais, pont, recharges,
> rerolls, LFW, version) gardent leurs accroches telles quelles : `self.X` existe s'ils sont chargés.

**API** : `Dir:OnPresence(kind, who)` · `Dir:ScanRelations()` · `Dir:ClassifySource(name)` · `Dir:ReclassifyAll()` · `Dir:PruneRoster(maxAgeDays, maxRecent)` · `Dir:OnRK(sender, message)` · `Dir:OnHello(sender, message, distribution)` · `Dir:OnPing(sender, _, distribution)` · `Dir:OnPong(sender)` · `Dir:Announce(onlyChanged)` · `Dir:AnnounceTo(target)` · `Dir:DiscoverPlayer(name)` · `Dir:OnBeacon(who)` · `Dir:Refresh()` · `Dir:RediscoverKnown(includeRecent)` · `Dir:CountOnline()` · `Dir:CountKnownCrafters()` · `Dir:WhoCanCraft(prof, spellID)` · `Dir:Start()`

### `CraftLink_Directory_Skills.lua`
> CraftLink_Directory_Skills.lua — niveaux de compétence (couche « profil » de l'annuaire), copié de
> Directory_Skills.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3).
> 
> Capture MES niveaux de métier (API skill, lisibles sans ouvrir la fenêtre), les diffuse (verbe SK), et
> reçoit ceux des autres → Dir.roster[name].skill/.level/.rep. Trois morceaux du SK appartiennent à
> l'hôte et n'en partent que s'il les fournit : `rep=` (commandes livrées, Dir.Delivered), `cv=` (sa
> version, Dir._MyVersion) et `rl=1` (relais de confiance, Dir.OnTrustEnvelope). Le miroir par perso de
> l'onglet « Mes artisans » de COC passe par Dir.OnMySkills.

**API** : `Dir:CaptureSkills()` · `Dir:AnnounceSkills()` · `Dir:OnSkill(sender, message)` · `Dir:AnnounceThrottled()`

### `CraftLink_Directory_Recipes.lua`
> CraftLink_Directory_Recipes.lua — COUTURE de lecture du registre « qui sait crafter quoi » d'un artisan.
> Copié de Directory_Recipes.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3).
> 
> Pourquoi. Le registre reçu peut prendre DEUX formes selon la saveur de l'émetteur :
>   * BITFIELD (verbe RK) — positions de bits dans le catalogue partagé. N'a de sens que si les
>     deux bouts ont EXACTEMENT le même catalogue, d'où le `dataVersion` sur le fil.
>   * IDENTIFIANTS (verbe RI, Camelot / WoW: Forever) — les recipeID eux-mêmes. Auto-descriptif,
>     aucune version à faire concorder (cf. CraftLink_RegistryIDs.lua).
> 
> Avant cette couture, la garde `r.recipeDV == lib:DataVersion()` était RECOPIÉE dans quatre
> modules (Handoff, LazyGold, UI_Artisans_Needs, UI_Post_Artisans), chacun appelant `HasBit`
> directement. Ajouter une seconde forme y aurait ajouté quatre branchements — et la prochaine
> forme, quatre de plus. Ici les appelants posent une QUESTION (« connaît-il cette recette ? ») et
> ignorent la réponse à « sous quelle forme est-ce stocké ».
> 
> Même philosophie que la table d'API du socle métier (`*_Craft.lua`) : un seul endroit sait que
> les saveurs divergent.
> 
> NB : les deux jeux étant séparés (un client Camelot ne parle qu'à des clients Camelot), un même
> roster ne mélange pas les formes en pratique. La couture reste écrite pour les deux — c'est ce
> qui la rend indépendante de cette hypothèse.

**API** : `Dir:RecipeForm(r, prof)` · `Dir:RecipeTester(r, prof)` · `Dir:RecipeKnownSet(r, prof)` · `Dir:HasRecipeData(r, prof)` · `Dir:RecipeFingerprint(r, prof)` · `Dir:RecipeMessages(prof, onlyChanged, record)` · `Dir:OnRI(sender, message)` · `Dir:HasAnyRecipeRecord(r, prof)`

### `CraftLink_Directory_Presence.lua`
> CraftLink_Directory_Presence.lua — présence : la vérité JEU (amis/guilde) et sa fusion avec la vérité
> ADDON. Copié de Directory_Presence.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3).
> 
> Deux sources, à ne JAMAIS confondre :
>   * Dir.online     — il RÉPOND en CraftLink (JOIN/LEAVE du canal, ou tout message reçu → _Touch).
>                      C'est la seule qui autorise une commande : ses données sont fraîches.
>   * Dir.onlineGame — le JEU le dit connecté (roster de guilde / liste d'amis / BNet), addon ou pas.
>                      Ne vaut que pour mes RELATIONS : le jeu ne dit rien d'un simple croisé.
> Sans la seconde, un guildmate connecté SANS l'addon s'affichait « Hors ligne » — faux, et ça
> ressemblait à une panne réseau. Dir:PresenceOf les fusionne en 3 états pour l'UI.
> 
> Satellite de Directory.lua (anti-monolithe) : y vivent le sweep des relations en ligne
> (DiscoverFriendsAndGuild), la requête d'affichage, et le filtre des erreurs « No player named »,
> seule présence qu'on ait d'un simple croisé. Chargé APRÈS Directory.lua (.toc).

**API** : `Dir:ForEachBNetWoWFriend(fn)` · `Dir:DiscoverFriendsAndGuild()` · `Dir:PresenceOf(name)`

### `CraftLink_Directory_Community.lua`
> CraftLink_Directory_Community.lua — le réseau SANS canal : la glue entre la bibliothèque et l'annuaire.
> Copié de la 1re partie de Directory_Community.lua de COC v1.53.0 (spec docs/specs/addon-partage.md,
> étape 3). La suite de ce fichier chez COC (communauté officielle, coupée depuis le 2026-09-29, lien
> « Rejoindre », libellé de /co status) reste chez COC : elle s'appuie sur ses cercles (Directory_Club).
> 
> Sur Forever, un canal custom est MORCELÉ en salles (prouvé le 2026-09-27) : « à tous » part donc en
> whisper vers les pairs que DÉSIGNE l'annuaire (Dir.online), et la bibliothèque prévient quand l'un d'eux
> ne répond plus — la présence que donnait le canal.

**API** : `Dir:OnlinePeers()` · `Dir:MarkOffline(who)`

### `CraftLink_Directory_Room.lua`
> CraftLink_Directory_Room.lua — la salle de découverte : le canal global rejoint pour SE PRÉSENTER, pas
> pour transporter. Copié de Directory_Room.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3).
> 
> Pourquoi (2026-09-29) : sans canal général, on chuchote aux joueurs qu'on connaît (amis, guilde) ; un
> porteur de l'addon qui n'est dans aucun de ces cercles n'est jamais atteint. Le banc des constats a
> prouvé qu'un message d'addon passe DANS une salle de canal custom. Sur Forever, CraftLinkNet est
> découpé en salles (2026-09-27) : on n'y fait plus passer de données, mais on peut y dire bonjour.
> 
> Mécanique (CraftLink, FANOUT_REV 3) : le canal est rejoint (garde anti-/1, caché des fenêtres) ; à
> chaque arrivée, un HI avec mes métiers part sur la salle (portée « room ») ; les présents me répondent
> en whisper (Dir:OnHello, branche canal : à moi seul), et je les connais. « À tous » reste en whisper.
> 
> Différences avec COC (A11) : la salle est FERMÉE par défaut, ouverte seulement par /craftlink global
> (CraftLinkDB.global) ; aucun avis au chat en y entrant, /craftlink le dit ; le rappel d'arrivée n'est
> posé auprès de la bibliothèque qu'au démarrage (Dir:_WireRoom), jamais au chargement du fichier : en
> pause, il remplacerait celui d'un ancien COC (la bibliothèque n'en garde qu'un).

**API** : `Dir:RoomEnabled()` · `Dir:OnRoomJoined()` · `Dir:RoomHello()` · `Dir:SetRoom(on)`

### `CraftLink_Mine.lua`
> CraftLink_Mine.lua — MES recettes et mes niveaux : ce que CraftingOrderClassic.lua (v1.53.0) faisait
> pour l'annuaire, repris pour CraftLink seul (spec docs/specs/addon-partage.md, étape 3).
> 
> La fenêtre de métier ouverte est relue (débouncé 0,3 s, les événements de liste spamment pendant un
> craft en série), l'union va dans la bibliothèque et dans la partition du perso courant de CraftLinkDB,
> puis l'annuaire rediffuse. Un point de métier gagné rediffuse mes niveaux (throttlé 2 s). Les temps de
> recharge, eux, restent à COC. Démarré par NS:Start, donc jamais quand la garde a mis CraftLink en pause.

**API** : `Mine:Store()` · `Mine:Load()` · `Mine:Scan()` · `Mine:ScanSoon()` · `Mine:OnSkillLines()` · `Mine:Start()`
