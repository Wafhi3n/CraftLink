# Tenir la base de données à jour pendant la vie de l'addon

> État : **brouillon** · Rédigée le 2026-09-22 · À arbitrer par le user
> Portée : `CraftLink-1.0/Data/` et sa chaîne `tools/` · Consommateurs : COC, TradeScanner

## Le problème

Ce que l'addon sait des métiers est **figé dans le paquet** : 2512 recettes Camelot, leurs réactifs,
leurs seuils de couleur, leurs sources, leurs origines. Or la cible est une **bêta vivante**. Wowhead
se remplit par observation — 48 % des objets `forever/` portent une source contre 93 % en `classic` —
et le cap de niveau reste à 30 jusqu'au 2026-11-04. Autrement dit : le jour où on publie, une partie
de ce qu'on livre est **inconnue**, et elle le restera chez le joueur jusqu'à la version suivante.

Trois manques constatés, tous de la même famille :

- **357 recettes sans objet produit** (Wowhead se tait encore) ;
- **29 recettes sans niveau d'apprentissage** — 8 rien qu'en Couture. Signalé en jeu le 2026-09-22 :
  la vue Manquantes les classait en tête et les déclarait à portée, parce que le code lisait
  l'absence comme un `0`. Le symptôme est corrigé côté COC ; **le trou de données, non** ;
- **le formateur ne s'écrit jamais depuis Wowhead** : aucune page ne l'affirme, on ne le déduirait
  que d'une absence, et une absence a deux causes indiscernables.

La question n'est donc pas « comment générer la base », qui est réglé, mais **comment elle se tient à
jour dans la durée, et par quel chemin ce qu'on apprend en jeu revient dedans**.

## Ce qui existe déjà (2026-09-22, ne pas re-spécifier)

- La génération hors-jeu, ordonnée et non commutative, décrite dans la skill `craftlink-data-pipeline`.
- La boucle de bêta `refresh_flavor.ps1` : contrôle d'abord, `-Apply` seulement sur une dérive saine ;
  une PERTE ne s'applique jamais seule.
- **La récolte en jeu entre dans le pipeline** (`observed.lua`, `import_observed.ps1`) : les
  SavedVariables de tous les comptes du poste sont fusionnées dans `Curated/observed_<Saveur>`,
  commité, qui **accumule et ne retire jamais**. `gen_origins` le relit à chaque passe.
  L'observation **comble** là où Wowhead se tait, elle ne remplace jamais, et seulement si la nature
  concorde avec `recipeSource` ; sinon conflit, rien n'est écrit.
- La reprise des pages **muettes** (`fetch_items.ps1 -Phase stale`) : une page en cache n'est pas une
  page à jour.

## Ce qu'on veut

1. **Une cadence tenue** : une passe par semaine pendant la bêta, une passe par patch une fois en
   live. On sait quand on le fait, ce qu'on regarde avant d'appliquer, et ce qui part chez les
   joueurs.
2. **Ce qu'on voit en jeu finit dans la base.** Le formateur, le niveau requis, le PNJ, le prix
   affiché : le client les connaît, le site non. Ce chemin existe pour les origines ; il doit couvrir
   **les niveaux d'apprentissage**, aujourd'hui absents pour Camelot (`gen_metadata` n'a jamais tourné
   sur cette saveur).
3. **Un trou se voit.** À tout moment on doit pouvoir dire combien de recettes n'ont ni objet produit,
   ni niveau, ni source, et sur quels métiers — sans ouvrir les fichiers à la main.
4. **Un trou se dit au joueur**, plutôt que d'être comblé par une valeur inventée. Règle déjà
   appliquée : un niveau inconnu s'affiche « ? », ne se classe pas en tête, et ne promet rien.
5. **Rien de faux ne part.** Une donnée qui vient d'un site tiers se relit avant d'être commitée.

## Ce qu'on NE fait PAS

- **Pas de téléchargement en jeu.** Un addon ne lit aucun fichier et ne fait aucune requête réseau
  vers l'extérieur. La base arrive par le paquet, point.
- **Pas de données venues des AUTRES joueurs** — en tout cas pas dans cette spec. Le transport
  CraftLink porte des recettes connues et des ordres, pas des faits de monde. Accepter qu'un
  inconnu écrive dans notre base de données ouvrirait une surface de confiance qu'on n'a pas
  étudiée. **À trancher (voir Décisions ouvertes).**
- **Pas de secours par les données d'une autre saveur** (SoD pour combler Camelot) : refusé par le
  user, on attend Wowhead.
- **Pas de déduction là où il n'y a qu'une absence.** Le formateur ne se déduit pas d'un objet-plan
  manquant ; la réputation ne se distingue pas d'un vendeur.

## Cas particuliers

- **Wowhead se remplit après coup** : une page muette en cache doit être re-téléchargée, pas crue.
- **Une perte** (recette disparue de la page) : une page incomplète et un retrait réel sont
  indiscernables depuis le cache. On regarde la page en cause avant d'entériner.
- **Observation et site se contredisent** : conflit, rien n'est écrit, et le conflit doit se voir.
- **Un identifiant de quête recoupe un identifiant de PNJ** (vécu : la quête 2763 a hérité de la zone
  du PNJ 2763). Les quêtes sont exclues des deux côtés du remplissage.
- **Un joueur ne verra jamais certaines données** : son personnage n'a pas le métier, pas le niveau,
  ou le formateur est chez l'autre faction. La base ne peut pas se remplir par la seule observation.

## Décisions

- 2026-09-22, user — le chantier « base de données » est un **fil rouge** du projet, pas un
  one-shot : il revient à chaque cycle de la bêta.
- 2026-09-22, agent (à confirmer) — un trou se **dit** plutôt que de se combler par défaut. Appliqué
  aux niveaux inconnus dans la vue Manquantes de COC le jour même.

- 2026-09-22, user — **cadence : une passe par SEMAINE pendant la bêta, une passe par PATCH une fois
  le jeu en live.** Le rafraîchissement suit le rythme auquel le monde change, pas celui de nos
  releases : une passe hebdomadaire qui ne produit rien est un résultat, pas un échec.
- 2026-09-22, user — **les niveaux d'apprentissage viennent des DEUX chemins** : la génération
  (`gen_metadata.lua`, qui n'a jamais tourné sur Camelot) ET la moisson en jeu chez le formateur.
  Ils se complètent au lieu de se choisir, comme les origines le font déjà avec `observed_<Saveur>`.

### Décisions ouvertes, à trancher par le user

1. **Lequel fait foi** quand la génération et la moisson donnent deux niveaux différents pour la même
   recette ? (Proposition de l'agent : la moisson, parce qu'elle vient du client lui-même — c'est
   déjà la règle pour la nature, où `recipeSource` fait foi.)
2. **Données venues des autres joueurs.** Jamais, ou un jour avec un modèle de confiance explicite ?
   Cette réponse décide de la forme de tout le reste, et elle vaut aussi pour les prix.
3. **Runtime contre paquet.** Quand le client sait quelque chose que la base ignore (niveau vu chez
   un formateur), COC s'en sert-il **tout de suite** pour l'affichage du joueur, ou attend-il que le
   fait soit passé par le pipeline et republié ?

## Critères d'acceptation

1. `[outil]` Un relevé de santé nomme, par saveur et par métier, le nombre de recettes sans objet
   produit, sans niveau, sans source, sans origine. Observateur : n'importe qui, en une commande.
2. `[outil]` Deux passes de rafraîchissement d'affilée, sans nouveau téléchargement, produisent un
   diff git **vide**. Une régénération ne doit jamais perdre ce qu'une autre passe a écrit.
3. `[test]` Les tests de forme (`test_camelot_data`, `test_flavor_drift`) restent verts après une
   régénération complète.
4. `[porte]` `check_dataversion.lua` passe avant ET après : la `dataVersion` Vanilla ne bouge pas.
5. `[humain]` Après une session de jeu sur un personnage qui visite des formateurs, l'import des
   observations ajoute des faits — et le relevé de santé du critère 1 baisse d'autant.
6. `[humain]` Un joueur ne voit jamais une valeur inventée à la place d'un trou : la vue Manquantes
   affiche « ? » et ne classe pas ces recettes en tête. Témoin connu-bon : la Couture avant le
   2026-09-22, où 8 recettes s'affichaient « niveau 0 » en haut de liste.

## Renvois

- Skill `craftlink-data-pipeline` (l'ordre des passes, les invariants, les pièges) — c'est elle qui
  porte le COMMENT ; cette spec porte le QUOI et la cadence.
- Skill `coc-item-classification` (ce qui se lit sur le client plutôt que dans les données).
- Mémoires `coc-camelot-recipe-data`, `coc-mtsl-removal-sources`,
  `coc-optional-deps-decommissioned`.
- Spec voisine : `CraftingOrderClassic/docs/specs/prix-maison.md` — même question, appliquée aux prix.
