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
- `check_dataversion.lua` — **garde de l'invariant** : recalcule hors-jeu la dataVersion de chaque
  saveur avec l'algorithme exact de la lib. Échoue (exit 1) si Vanilla ≠ `1792301894` (= bitfields
  de registre déjà diffusés chez les joueurs invalidés). À lancer avant/après TOUTE régénération.
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
| SoD | à faire (couche à part) | Wowhead `classic` + `seasonId:2` | — |

Clé canonique du Secourisme : `"First Aid"` (avec espace) sur TOUTES les saveurs (TBC/Wrath
enregistraient `"FirstAid"`, corrigé 2026-07-02). L'outil de génération complète des saveurs
(`gen_flavor.lua`) a été perdu — à réécrire depuis la structure ci-dessus si on ajoute SoD ou
qu'on régénère TBC/Wrath (garder `check_dataversion.lua` comme filet).

## Sources / attribution

Données = faits de jeu (recette → objet produit → composants). Merci à **MissingTradeSkillsList**
(Thumbkin) pour la liste exhaustive des recettes Vanilla (set figé), et à **Wowhead**
(Classic/TBC/WotLK) pour les métadonnées et les jeux de recettes par version.
