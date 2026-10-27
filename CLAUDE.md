# Les Royaumes des Masques : Extraction

Rogue-lite d'extraction en vue de dessus (style Archero), Godot 4.x, GDScript typé, PC + mobile.
Ce fichier est la référence du projet : relis-le avant chaque phase.

## Règles de travail (Claude Code)
- Travaille une phase à la fois (voir ROADMAP). Avant de coder une phase, présente un plan court et attends validation.
- À la fin de chaque phase : résumé, fichiers modifiés, comment tester dans l'éditeur, puis commit.
- Vérifie que le projet compile après chaque changement :
  `godot --headless --path . --quit` (aucune erreur de parsing ne doit apparaître).
- Tests unitaires avec GUT (addon dans /addons/gut), lancés en headless :
  `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Tu ne vois pas le jeu tourner : ajoute des outils de debug (touche F3) qui affichent zones de détection, graphe de salles, seed, FPS, taux de drop. Demande-moi de tester visuellement quand c'est nécessaire.
- Fichiers .tscn : garde-les simples. Pour les structures complexes, construis les nœuds en code plutôt que d'écrire de longs .tscn à la main. Ne modifie jamais un .tscn ou .tres sans l'avoir relu entièrement.
- Aucune valeur d'équilibrage en dur : tout dans /data (ressources .tres) ou /data/balance.cfg.
- Si un choix de design est ambigu, propose deux options et demande.
- Git : commits courts et explicites, push directement sur `main`. Pas de branche ni de pull request, sauf si l'utilisateur en demande une explicitement.

## Direction artistique (référence unique : la planche « Les royaumes des masques »)
Image : `docs/reference/royaumes_des_masques.jpg`. Seule la partie « Les royaumes des masques » de l'image de référence fait foi. La partie « Les royaumes assemblés » (matériaux, royaumes de bois/métal, etc.) n'est PAS utilisée.
- Style : fantasy stylisée, rendu peint semi-réaliste, personnages aux proportions héroïques légèrement exagérées, contours nets, très lisible sur mobile.
- Décor : cours et remparts de château en pierre ocre, tours, grandes bannières rouges à emblème blanc, ciel de coucher de soleil (orange, rose, violet), lumière chaude rasante, ombres bleu nuit.
- Héros de référence : masque blanc type kitsune avec marques rouges et yeux rouges lumineux, cornes/plumes rouges, écharpe rouge, armure sombre aux liserés rouges et cuir, lame courbe.
- Chaque masque a une couleur d'aura qui teinte le personnage et ses effets :
  - Colosse : casque massif or et pierre, yeux bleu clair → palette or/bronze.
  - Spectre : masque argent anguleux, éclairs et lueur cyan → palette argent/cyan.
  - Alchimiste : masque de flammes orange et rouge → palette feu.
  - Marionnettiste : masque d'os blanc avec fils et cordes → palette violette (la variante violette de la planche).
- Effets de combat : traînées d'attaque lumineuses et arcs de lame (rouge pour le héros), ennemis massifs type golem de pierre.
- Interface : panneaux bleu nuit (#121a2e environ) aux coins arrondis, bordures fines claires, titres blancs en gras, texte secondaire gris clair.
- Placeholders au début (formes dessinées en code dans cette palette), organisés pour être remplacés facilement.
- Codes couleur de rareté partout : Commun gris, Peu commun vert, Rare bleu, Épique violet, Légendaire orange (lueur pour Épique et Légendaire).

## Masques (classes)
- Colosse : attaques lentes, gros dégâts, grande résistance.
- Spectre : déplacements rapides, esquives, attaques surprises.
- Alchimiste : explosions, zones de dégâts, effets élémentaires.
- Marionnettiste : invocations alliées.
Chaque masque = une ressource MaskData (stats, pouvoir actif, passif, armes autorisées).

## Royaumes
Un royaume par famille de masques, tous dans l'univers château fantasy de la planche :
- Forteresse du Colosse : remparts de pierre et d'or, golems, gardiens lourds.
- Ruines du Spectre : citadelle hantée, brumes et éclairs cyan, ennemis rapides.
- Forges de l'Alchimiste : bastion en flammes, ennemis élémentaires, explosions.
- Théâtre du Marionnettiste : cour violette, pantins et invocateurs.
Chacun : palette, ennemis, boss, tables de loot, armes propres.

## Boucle de jeu
1. Hub : choix du masque, de l'équipement, du niveau de donjon (Facile → Cauchemar). Difficulté = ennemis plus forts + loot plus rare.
2. Raid : exploration, combat, fouille, inventaire de raid limité (grille ou poids).
3. Extraction : points d'extraction par étage, canalisation de quelques secondes pendant laquelle les ennemis attaquent.
   - Réussite : butin transféré dans la réserve permanente.
   - Mort : butin du raid perdu, sauf emplacement sécurisé limité.
4. Retour au hub : vente, amélioration, nouveau raid.

## Vue et exploration
- Caméra de dessus qui suit le joueur. Joystick virtuel (mobile), WASD/ZQSD + souris (PC). Tir automatique sur l'ennemi le plus proche, visée manuelle optionnelle sur PC.
- Brouillard de guerre à 3 états : jamais vu (noir), exploré hors vue (grisé, ennemis cachés), visible. Vision bloquée par les murs. Implémentation : texture de masque mise à jour depuis la position du joueur + shader sur CanvasLayer.
- Donjon procédural : graphe de salles reliées par des couloirs, seed rejouable.
  Types de salles : combat, fouille, piège, repos, super-loot verrouillée, boss, extraction.
- Plusieurs étages reliés par des escaliers, chacun plus dangereux et plus riche.

## Loot
- Conteneurs fouillables (animation de fouille interruptible) : coffre, placard, armoire, tonneau, carcasse de voiture, épave de vaisseau, cadavre, autel. Une table de loot par type.
- Tables pondérées influencées par conteneur, niveau de donjon, étage, zone.
- Clefs spéciales : drop uniquement sur ennemis, taux très bas (0,5 % à 2 %, configurable). Chaque clef ouvre une zone de super-loot précise (porte scellée visible). Taux Épique/Légendaire fortement augmentés, gardes d'élite. Les clefs peuvent être extraites et gardées.

## Armes
Familles : épées, haches, marteaux, lances, dagues, arcs, arbalètes, armes à feu mécaniques, bâtons, grimoires, armes d'invocation, armes vivantes évolutives.
Chaque arme (WeaponData .tres) : rareté, dégâts, cadence, portée, pattern d'attaque/projectile, affixes aléatoires (brûlure, gel, ricochet, multi-tir, vol de vie, onde de choc…).
Armes de boss avec effets uniques. Objectif : au moins 30 armes au départ, ajoutables sans toucher au code.

## Ennemis et IA
- Zone de détection (Area2D cercle ou cône) + raycast de ligne de vue (murs bloquants).
- États : Patrouille/Idle → Alerte (« ! », courte pause) → Poursuite → Attaque → Retour.
- Un ennemi alerté prévient ses voisins proches.
- Archétypes : mêlée, distance, tank, rapide, invocateur, kamikaze, élite, boss à phases.
- StateMachine générique réutilisable, navigation via NavigationAgent2D.

## Architecture
/scenes (player, enemies, rooms, ui, hub)
/scripts (core, combat, ai, loot, dungeon, inventory, save)
/data (weapons, enemies, loot_tables, masks, containers, keys, balance.cfg)
/assets (sprites, sfx, music, shaders)
/tests
/addons (gut)
- Autoloads : GameState, SaveManager, LootManager, EventBus. Systèmes découplés par signaux.
- Sauvegarde locale JSON (réserve, masques, progression).
- Mobile : pooling projectiles/effets, cible 60 fps.

## GitHub
- .gitignore Godot, .gitattributes avec Git LFS pour les binaires, README, LICENSE, ROADMAP.md.
- GitHub Actions : export Windows, Linux, Web, Android à chaque tag `v*` (image godot-ci), + job qui lance les tests GUT sur chaque PR.

## ROADMAP
1. Base : dépôt, structure, joueur (déplacement + tir auto), caméra, debug F3.
2. Ennemis : détection, ligne de vue, machine à états.
3. Donjon : salles + couloirs, étages, brouillard de guerre.
4. Loot : conteneurs, tables, raretés, inventaire de raid.
5. Clefs spéciales et zones de super-loot.
6. Extraction, mort, réserve, hub, difficultés.
7. Masques et pouvoirs.
8. Catalogue d'armes, affixes, armes de boss.
9. Royaumes, boss, équilibrage.
10. UI mobile, polish, sons, CI d'export.
