# Registre de verification en jeu - CraftLink

Meme role que celui de Crafting Order - Classic : dire jusqu'ou l'addon a ete **vu fonctionner**
dans le client, puisque aucune porte automatique ne sait le dire. `scripts/untested.ps1 -Addon
CraftLink` fait l'union de tous les releves ci-dessous et liste ce qu'aucun n'avait dans le client.

Format d'un releve (le plus recent EN TETE) :

```
- AAAA-MM-JJ HH:MM - jusqu'a <sha> - <build> - <verdict> - <ce qui a ete observe>
```

Le `<sha>` est le dernier commit reellement present dans le client pendant la seance. On n'ecrit
un releve qu'APRES avoir observe, et on dit ce qui n'a PAS ete observe. Plusieurs sessions peuvent
ecrire ici en parallele : l'heure plutot qu'un numero du jour, et le fichier fusionne en
`merge=union` (`.gitattributes`) sans conflit.

**Un rebase perime le sha d'un releve** : apres le rebase d'une branche deja couverte, avancer son
sha (`git log --oneline` sur la nouvelle branche donne l'equivalent, le message est identique).

## Releves

- 2026-11-24 16:12 - jusqu'a 4e6a7ab - main-dev@3c102fd 2026-11-23 19:03 - GO - le but de CraftLink seul, envoyer les metiers de quelqu'un qui n'a pas COC, vu par le canal global (meme perso, COC decoche) : sonde des chuchotements de CraftLink, `/craftlink global`, des reponses chuchotees arrivent, `/craftlink` compte au moins 1 artisan. La sauvegarde ecrite au `/reload` garde 2 joueurs hors guilde (source `recent`, Alliance), chacun avec ses metiers, vus a 16:01 (le global reste ouvert apres le `/reload` de la seance precedente) et a 16:11 (ce geste) : chacun a recu le bonjour de salle, qui embarque le SK, et a repondu en chuchote. `global = false` retenu apres `global off`. Aucune erreur Lua. PAS observe : la voie de la guilde (aucun guildien avec COC en ligne) ; les recettes, que personne n'a demandees (aucun PING, aucune recette recue en retour ; meme comportement entre deux COC sur le global). Mesure : `GetRealmName()` = "", `GetNormalizedRealmName()` = "", `GetRealmID()` = 0, `UnitFullName("player")` rend un royaume non vide (client 1.60.1.71037) : le SK part sans `rm=` (`_MyRealmID` rend nil), et la partition des recettes s'appelle `<perso>-`.

- 2026-11-24 15:55 - jusqu'a 4e6a7ab - main-dev@3c102fd 2026-11-23 19:03 - GO partiel - un seul perso, trois connexions (fiche `CraftLink--feat-craftlink-addon`). COC seul : gestionnaires de la bibliotheque PING 2, HI 2, RI 1, SK 1. COC + CraftLink : la ligne de pause une fois, `/craftlink` redit la pause, memes nombres (CraftLink ne branche rien en double). CraftLink seul : rien au chat a la connexion, `/craftlink` en une ligne ; fenetres de metier ouvertes puis fermees : l'invitation disparait, la sauvegarde garde 144 recettes sur 4 metiers (Cooking, Blacksmithing, First Aid, Enchanting) dans la partition du perso ; pas de CraftLinkNet avant `/craftlink global`, rejoint apres, toujours la apres `/reload` (`global = true` dans la sauvegarde ecrite au `/reload`), « canal global quitte. » apres `global off`. Aucune erreur Lua pendant la seance (BugGrabber). PAS observe : la voie reseau. Aucun guildien avec COC en ligne (l'annuaire de COC n'a eu aucun contact de 15:55 a 15:59, dernier guildien vu a 12:54), donc 0 artisan connu et roster de CraftLinkDB vide ; personne n'a regarde l'annuaire de l'autre cote. Vu aussi : la partition des recettes s'appelle `<perso>-` sans royaume (`GetRealmName()` vide ?), la sauvegarde de COC porte la meme cle a cote de l'ancienne avec royaume : herite de COC, a mesurer.
