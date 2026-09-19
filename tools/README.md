# tools/ — outils de build (NON packagés)

Ce dossier contient la chaîne de génération de la base de métiers statique
(`CraftLink-1.0/Data/<flavor>/*.lua`). **Rien ici n'est chargé en jeu** — c'est exclu du package
CurseForge via `.pkgmeta`. Déplacé depuis `TradeScanner/tools/` (2026-07-02).

**Source de données courante : Wowhead uniquement** (une page skill par métier contient tout :
recettes, produit, réactifs, `learnedat`, objets-plans, tag SoD). MTSL n'est plus qu'une source
*historique* : c'est d'elle que vient le set Vanilla FIGÉ (dataVersion `1792301894`), qui ne doit
plus jamais être régénéré.

## Fichiers

- `gen_metadata.lua` — **l'outil courant**. Complète les `Data/<flavor>/*.lua` existants avec les
  métadonnées manquantes, depuis le cache HTML Wowhead (`tools/wh/`) :
  - `learnedAt` (spellID → niveau de métier où la recette s'apprend) — champ `"learnedat"` ;
  - `taughtBy` (itemID de l'objet-plan → spellID enseigné) — jointure par NOM entre les
    listviews `spells` et `recipe-items` de la même page (Wowhead n'expose pas le lien direct).
  Idempotent (bloc sentinellisé `-- >>> gen_metadata.lua`, remplacé à chaque relance) ; ne touche
  JAMAIS `recipes` et restreint les métadonnées au set `recipes` du fichier.
  ```powershell
  cd f:\AddonDevellopement\CraftLink
  & "C:\Users\wafhi\AppData\Local\Programs\Lua\bin\lua.exe" tools\gen_metadata.lua           # Vanilla
  & "C:\Users\wafhi\AppData\Local\Programs\Lua\bin\lua.exe" tools\gen_metadata.lua TBC
  & "C:\Users\wafhi\AppData\Local\Programs\Lua\bin\lua.exe" tools\gen_metadata.lua Wrath
  ```
  Lacunes connues : Poisons Vanilla sans `learnedAt` (la page skill=40 n'expose pas le champ) ;
  les « plans non appariés » listés en sortie sont surtout du contenu hors-set (SoD, items `OLD`).
- `gen_skill_colors.lua` — ajoute `skillColors` (spellID → `{orange, jaune, vert, gris}`, le gris =
  rang où la recette ne rapporte plus de point) depuis le champ `"colors"` du Listview `spells`.
  Même patron que gen_metadata : sentinelles propres (`-- >>> gen_skill_colors.lua`), restreint au
  set `recipes`, ne touche jamais la dataVersion. Prend la saveur en argument (`Vanilla` par défaut,
  `TBC`, `Wrath`, `SoD` — la couche SoD lit les pages `classic`). ⚠️ à relancer (SoD) après
  `gen_season.lua`, qui régénère les fichiers de saison. Lacune connue : Poisons Vanilla (la page
  skill=40 n'expose pas `colors`) → l'heuristique runtime prend le relais. Consommé par
  `lib:RecipeColors(prof, spellID)` (lib v11).
- `check_dataversion.lua` — **garde de l'invariant** : recalcule hors-jeu la dataVersion de chaque
  saveur avec l'algorithme exact de la lib. Échoue (exit 1) si Vanilla ≠ `1792301894` (= bitfields
  de registre déjà diffusés chez les joueurs invalidés). À lancer avant/après TOUTE régénération.
- `gen_flavor.lua` — génère un set COMPLET de saveur (`RegisterProfession`) : `Data/<Saveur>/*.lua`
  + `Data/<Saveur>.xml`. À utiliser quand la saveur **retire** des recettes et pas seulement en
  ajoute — une couche (`gen_season.lua`) ne sait que appondre. Modes : `-check` (contrôle de dérive,
  n'écrit rien, échoue sur toute PERTE), `-urls` / `-fetch` (liste des pages à télécharger). Un
  sous-ensemble de métiers en arguments n'écrit délibérément PAS le XML (il listerait un set partiel).
- `flavor_drift.lua` — la comparaison **par champ** de `-check` (objet créé, niveau d'apprentissage),
  module pur testé à part (`tests/test_flavor_drift.lua`). Sans elle, un objet que Wowhead documente
  APRÈS avoir listé la recette donnait « identique », et la boucle ne le prenait jamais.
- `refresh_flavor.ps1` — enveloppe la boucle : fetch (curl.exe, avec refus d'un téléchargement
  invalide pour ne pas écraser un bon cache) → `-check` → application seulement sur `-Apply` et
  seulement si la dérive est saine. Ne redéclare PAS la liste des métiers : elle vient de `-urls`.
- `gen_wowhead.lua` — enrichissement historique `produces`/`reagents` (fait sur les 3 saveurs).
  APPEND sans remplacement → garde intégrée : SKIP si `produces` déjà présent. Pour de nouvelles
  métadonnées, passer par `gen_metadata.lua`.
- `gen_professions.lua` — générateur HISTORIQUE du set Vanilla depuis MTSL (installée dans le
  dossier AddOns). **NE PLUS LANCER** : le set/ordre des recettes est figé. Conservé comme
  documentation de la provenance. NB : son fallback `sk.items` confondait objet-plan et produit —
  d'où ~72 entrées `itemToSpell` polluées (68 Cooking, 4 FirstAid), détectées par l'audit de
  `gen_metadata.lua` (correctif futur : régénérer `itemToSpell` comme inverse de `produces`).
- `wowhead_map.lua` — table `[spellID] = itemID produit` (extraction Wowhead), utilisée par
  gen_professions à l'époque. Historique.
- `Curated/disenchant.lua` — données curées à la main (mats de désenchantement, absents des
  sources), fusionnées dans `Data/Vanilla/Enchanting.lua`.

## Cache HTML Wowhead (`tools/wh/`, gitignoré)

Une page par `(domaine, métier)`, nommée `<domaine>_<Métier>.html` (ex. `classic_Alchemy.html`,
`tbc_Jewelcrafting.html`, `wotlk_Inscription.html`). ⚠️ Depuis mi-2026, un `curl -A "UA"` nu se
fait refuser (CloudFront 403) : il faut un jeu d'en-têtes navigateur complet. PAS de WebFetch
(il convertit en markdown et jette la table JS). Boucle de récupération (bash, délai de
politesse) :

```bash
cd f:/AddonDevellopement/CraftLink/tools/wh
fetch() {
  curl -s --compressed \
    -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36" \
    -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
    -H "Accept-Language: fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7" \
    -H "Referer: https://www.wowhead.com/" -H "Upgrade-Insecure-Requests: 1" \
    -H "Sec-Fetch-Dest: document" -H "Sec-Fetch-Mode: navigate" -H "Sec-Fetch-Site: same-origin" \
    "$2" -o "$1"; sleep 2
}
# domaines : classic (Vanilla+SoD) / tbc / wotlk — IDs skill : Alchemy 171, Blacksmithing 164,
# Cooking 185, Enchanting 333, Engineering 202, First Aid 129, Leatherworking 165, Mining 186,
# Poisons 40, Tailoring 197, Jewelcrafting 755 (TBC+), Inscription 773 (WotLK+).
fetch classic_Alchemy.html "https://www.wowhead.com/classic/skill=171/alchemy"
# ... etc.
```

Structure exploitée : les lignes du Listview `spells` (`new Listview({...id:'spells'...})`) sont
des objets JSON à clés TRIÉES : `{"cat":11,"colors":[o,j,v,g],"creates":[itemID,min,max],
"id":spellID,"learnedat":N,"level":L,"name":"...","nskillup":1,"quality":Q,
"reagents":[[itemID,qty],...],"skill":[171],"seasonId":2?,"phaseId":N?}`. Les objets-plans sont
dans le Listview `recipe-items` (`"classs":9`, nom `"Recipe: X"` / `"Formula: X"` / ...).
`seasonId:2` = recette Saison de la Découverte (absente = vanilla de base).

## Multi-versions (état)

Les données vivent dans `CraftLink-1.0/Data/<flavor>/*.lua` + un `Data/<flavor>.xml` par saveur,
inclus par le `.toc` correspondant de chaque addon hôte.

| Saveur | État | Source recettes | dataVersion |
|---|---|---|---|
| Vanilla | **FIGÉ** — ne jamais régénérer `recipes` | MTSL (historique) | `1792301894` (déployée) |
| TBC | générée (gen_flavor, outil perdu) + enrichie | Wowhead `tbc` | `1073594610` |
| Wrath | générée (gen_flavor, outil perdu) + enrichie | Wowhead `wotlk` | `362977519` |
| SoD | **couche additive** sur Vanilla (`gen_season.lua`) | Wowhead `classic` + `seasonId:2` | `892995836` (Vanilla+304) |
| Camelot (Forever) | **saveur complète** (`gen_flavor.lua`) | Wowhead `forever` | `1908807446` (2512 rec.) |

Clé canonique du Secourisme : `"First Aid"` (avec espace) sur TOUTES les saveurs (TBC/Wrath
enregistraient `"FirstAid"`, corrigé 2026-07-02). L'outil de génération complète des saveurs (`gen_flavor.lua`) avait été
**perdu** ; il a été **réécrit le 2026-09-18** pour Camelot et sert de nouveau à régénérer n'importe
quelle saveur complète (garder `check_dataversion.lua` comme filet).

## SAVEUR complète (`gen_flavor.lua`) — Camelot / WoW: Forever

Une saveur **remplace** le set de base (`RegisterProfession`), là où une saison s'y ajoute. Camelot a
eu besoin de ça et pas d'une couche, pour une raison mesurée le 2026-09-18 : Forever ne fait pas
qu'ajouter, il **retire**. Les six potions de soin ont quitté l'Alchimie (sorts 2330, 2337, 3447,
7181, 11457, 17556) pour Premiers soins sous de nouveaux sorts, et six recettes ont quitté la Forge
pour le Travail du cuir. `ExtendProfession` est append-only par construction : il aurait laissé des
recettes fantômes, commandables, pointant sur des sorts disparus. `gen_season.lua` ne s'appliquait
de toute façon pas — il filtre sur un tag `"seasonId"` dont les pages `forever/` ne portent **aucune**
occurrence : sur une page de saveur, toute la page EST la saveur.

Pas de garde runtime : c'est le `.toc` `_Camelot` qui inclut `Data/Camelot.xml` à la place de
`Vanilla.xml`. `C_Seasons` n'existe d'ailleurs pas sur Forever. Poisons est absent du set : Forever
en a fait des sorts **sans réactif**, il n'y a aucune recette à modéliser.

```powershell
# Boucle complète (fetch -> contrôle -> application), cwd = CraftLink :
.\tools\refresh_flavor.ps1              # télécharge et SIGNALE la dérive, n'écrit aucune donnée
.\tools\refresh_flavor.ps1 -Apply       # applique, mais SEULEMENT si la dérive est saine
.\tools\refresh_flavor.ps1 -SkipFetch   # contrôle sur le cache déjà présent
```

⚠️ **À relancer souvent, et à ne jamais automatiser jusqu'à la fusion.** Forever est en bêta (niveau
plafonné à 30 jusqu'au 4 novembre 2026) et Blizzard **offusque les données client** : la base Wowhead
ne vient pas du datamining, elle se remplit par OBSERVATION des joueurs. Une recette qui disparaît
d'une page est donc presque toujours un trou de collecte, pas un vrai retrait — d'où le mode
`-check`, qui **échoue sur toute perte** (code 1), signale les ajouts (code 2) et se tait sinon
(code 0). Une perte, c'est une recette disparue OU un champ disparu/changé ; un ajout, une recette
nouvelle OU un champ complété sur une recette connue — le cas le plus fréquent pendant la bêta, où
Wowhead documente l'objet créé bien après la recette. Et rappel de fond : ces données ne sont pas
que des données, les positions dans `recipes`
sont les **bitfields du registre** échangés entre clients. Rien ne doit se fusionner sans relecture.

## Couches SAISONNIÈRES (`gen_season.lua`) — SoD

Une saison **ajoute** des recettes à un set de base au lieu de le remplacer. `gen_season.lua` écrit
`Data/<Season>/<Métier>.lua` (+ `Data/<Season>.xml`) ; chaque fichier appelle
`CraftLink:ExtendProfession` et s'auto-désactive hors saison (`CraftLink:ActiveSeason() ~= <id>`).
Le `.toc` **de base** l'inclut APRÈS `Vanilla.xml` — le même .toc sert donc Era classique et SoD.

```powershell
cd f:\AddonDevellopement\CraftLink
& "C:\Users\wafhi\AppData\Local\Programs\Lua\bin\lua.exe" tools\check_dataversion.lua   # AVANT
& "C:\Users\wafhi\AppData\Local\Programs\Lua\bin\lua.exe" tools\gen_season.lua SoD
& "C:\Users\wafhi\AppData\Local\Programs\Lua\bin\lua.exe" tools\check_dataversion.lua   # APRÈS
```

**Pourquoi c'est sûr** : `ExtendProfession` appond EN FIN de `recipes`. Les positions 1..N des
recettes de base — donc les bitfields du registre (`CraftLink_Registry`) déjà encodés chez les
joueurs — restent valides bit pour bit. Seule la `dataVersion` change, et **seulement pour les
clients dans la saison** : un joueur Era garde `1792301894` intact. Deux clients de dataVersion
différentes ne comparent pas leurs bitfields, ce qui est exactement le comportement voulu (ils sont
sur des royaumes différents, qui ne communiquent jamais). `check_dataversion.lua` refuse (exit 1)
toute recette saisonnière qui existerait DÉJÀ dans la base : elle décalerait les positions.

⚠️ Les objets-plans (`"classs":9`) portent EUX AUSSI `seasonId` : la jointure `taughtBy` doit s'y
restreindre, sinon un plan de base est rattaché à un sort saisonnier par collision de nom (mesuré :
18 faux appariements en Forge).

**Ajouter Camelot** : une entrée dans `SEASONS` de `gen_season.lua` (domaine Wowhead, `seasonId`,
set de base, liste des métiers) + une dans `SEASONS` de `check_dataversion.lua`, puis une ligne
`Data\<Season>.xml` dans le `.toc` de base. Aucune modification de la lib.

## Sources / attribution

Données = faits de jeu (recette → objet produit → composants). Merci à **MissingTradeSkillsList**
(Thumbkin) pour la liste exhaustive des recettes Vanilla (set figé), et à **Wowhead**
(Classic/TBC/WotLK) pour les métadonnées et les jeux de recettes par version.
