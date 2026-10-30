# RaidersGo

« Tire. Pille. Tire-toi. » Extraction shooter rogue-lite en vue de dessus (style Archero), Godot 4.7.2, GDScript typé, PC + mobile.
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
- Git : on travaille à deux sur le projet. **Ne jamais pousser directement sur `main`.**
  - Chaque nouvelle fonctionnalité ou correction se fait dans sa propre branche, créée depuis `main` à jour : `feature/<sujet>`, `fix/<sujet>` ou `chore/<sujet>` (noms courts en minuscules, mots séparés par des tirets).
  - Commits courts et explicites sur la branche, puis push de la branche et ouverture d'une pull request vers `main`.
  - Description de la PR OBLIGATOIRE et précise : liste exacte de ce qui a changé (fonctionnalités, fichiers principaux, valeurs d'équilibrage modifiées avant → après), comment tester, résultat des tests.
  - Captures d'écran OBLIGATOIRES de chaque modification visible (avant/après quand c'est pertinent), affichées dans la description. Les images sont poussées sur la branche `pr-assets` (branche orpheline jamais fusionnée), dans `<numéro ou nom de la branche>/`, et insérées par leur lien `https://raw.githubusercontent.com/MrCranito/maskit/pr-assets/<dossier>/<image>.png`. Pour un changement sans effet visible, l'écrire explicitement.
  - La pull request doit être validée par l'utilisateur avant d'être fusionnée : ne jamais la fusionner soi-même.
  - Avant d'ouvrir la PR : projet qui compile et suite GUT verte (sinon le signaler dans la description).

## Direction artistique (référence unique : la planche « Les royaumes des masques »)
Image : `docs/reference/royaumes_des_masques.jpg`. Seule la partie « Les royaumes des masques » de l'image de référence fait foi. La partie « Les royaumes assemblés » (matériaux, royaumes de bois/métal, etc.) n'est PAS utilisée.
- Style : fantasy stylisée, rendu peint semi-réaliste, personnages aux proportions héroïques légèrement exagérées, contours nets, très lisible sur mobile.
- Décor : cours et remparts de château en pierre ocre, tours, grandes bannières rouges à emblème blanc, ciel de coucher de soleil (orange, rose, violet), lumière chaude rasante, ombres bleu nuit.
- Héros : personnage simple de shooter d'extraction, sans masque (visage visible, gilet tactique, sac à dos), qui tient une arme à feu. Son apparence ne change que par les skins cosmétiques.
- Effets de combat : éclairs de bouche, douilles, traçantes, explosions, impacts ; ennemis massifs type golem de pierre.
- Interface (direction « D », maquette validée : https://claude.ai/artifact/FTXHPHfN5wZRxSQDW8oaDq) : fond encre (#06070D) translucide, angles vifs et coins biseautés (`CutBox`), accent violet électrique (#7C4DFF, clair #B79BFF) pour l'action principale et les grands bandeaux translucides en biais, titres et gros chiffres en Anton capitales, texte en Space Grotesk, texte secondaire blanc à 60-70 %. Pas de « // » ni de libellés façon terminal. Tout passe par `MenuKit` / `InventoryStyle`.
- Placeholders au début (formes dessinées en code dans cette palette), organisés pour être remplacés facilement.
- Codes couleur de rareté partout : Commun gris, Peu commun vert, Rare bleu, Épique violet, Légendaire orange (lueur pour Épique et Légendaire).

## Arsenal (remplace les anciens masques — supprimés)
- Armes à feu par catégorie : pistolet, revolver, mitraillette, fusil à pompe, fusil d'assaut, sniper, mitrailleuse, bazooka, lance-grenades. Chaque modèle a une rareté fixe (Commun → Légendaire).
- Réserve permanente d'armes (autoload Profile). Avant chaque raid : validation de l'arsenal de départ (1 à 3 armes).
- Mort : l'arsenal emporté et le butin sont perdus, retour au menu. Si la réserve est vide, un petit pistolet est offert.
- Extraction réussie : armes tenues + armes et objets du sac rejoignent la réserve, + quelques gemmes.

## Monétisation
- Gemmes : packs (paiement simulé tant que les comptes stores ne sont pas configurés) + quelques gemmes par extraction.
- Avec les gemmes : skins de personnage et d'armes (cosmétique), et packs d'or (décision de Victor du 30/10) pour s'équiper à l'armurerie avant les parties. Pas d'autre avantage en jeu vendu (pas de butin, de PV ou d'armes Légendaires contre gemmes).
- Tout achat de la boutique passe par une fenêtre de confirmation.

## Mondes et biomes
Chaque monde a son propre biome (décor, palette, ennemis, boss, tables de loot, armes propres). Les personnages gardent la direction artistique du projet ; le biome change le décor.
- **Monde 1 — Far West** : ville fantôme au coucher du soleil (bois délavé, adobe, sable ocre, ciel orange-rose-violet, ombres bleu nuit). Bâtiments : saloon (étage), banque (coffre-fort = salle de super-loot), bureau du shérif (cellules), magasin général, hôtel (étage), écurie, église, entrée de mine (sous-sol). Ennemis : hors-la-loi masqués (bandit au couteau, pistolero, brute au fusil, colosse de grès). Conteneurs : caisses, tonneaux, chariots, diligences, coffres, placards, armoires, cadavres.
- Mondes suivants : biomes à définir.

## Structure des cartes
PAS de monde ouvert. Une carte = des bâtiments dans lesquels le joueur entre, reliés par des rues et ruelles qui servent de couloirs. Salles ouvertes (rues, places) et fermées (intérieurs derrière des portes). Les portes bloquent mouvement et vision tant qu'elles sont fermées. Le toit d'un bâtiment masque son intérieur et s'efface quand le joueur entre. Étages : étage supérieur (saloon, hôtel) et sous-sol (mine), reliés par des escaliers.

## Boucle de jeu
1. Hub : choix de la carte (difficulté propre à la carte), puis validation de l'arsenal de départ. Difficulté = ennemis plus forts + loot plus rare.
2. Raid : exploration, combat, fouille, inventaire de raid limité (grille ou poids).
3. Extraction : points d'extraction par étage, canalisation de quelques secondes pendant laquelle les ennemis attaquent.
   - Réussite : butin transféré dans la réserve permanente.
   - Mort : arsenal emporté et butin du raid perdus.
4. Retour au hub : arsenal, boutique, nouveau raid.

## Vue et exploration
- Jeu uniquement en paysage. Caméra de dessus qui suit le joueur et anticipe la visée. Mobile : deux joysticks (gauche = déplacement, droit = viser et tirer). PC : ZQSD/WASD + souris pour viser, clic gauche pour tirer. Pas de tir automatique.
- Brouillard permanent : tout l'écran est sous une brume bleu nuit animée ; seul le champ de vision réel du joueur (polygone de visibilité, bloqué par murs et portes fermées) est net, avec bords doux et vignettage. Les zones visitées retombent dans le brouillard (souvenir très discret du décor) et les ennemis/conteneurs y sont cachés.
- Donjon procédural : graphe de salles reliées par des couloirs, seed rejouable.
  Types de salles : combat, fouille, piège, repos, super-loot verrouillée, boss, extraction.
- Plusieurs étages reliés par des escaliers, chacun plus dangereux et plus riche.

## Loot
- Conteneurs fouillables (animation de fouille interruptible) : coffre, placard, armoire, tonneau, carcasse de voiture, épave de vaisseau, cadavre, autel. Une table de loot par type.
- Tables pondérées influencées par conteneur, niveau de donjon, étage, zone.
- Clefs spéciales : drop uniquement sur ennemis, taux très bas (0,5 % à 2 %, configurable). Chaque clef ouvre une zone de super-loot précise (porte scellée visible). Taux Épique/Légendaire fortement augmentés, gardes d'élite. Les clefs peuvent être extraites et gardées.

## Armes
Chaque arme (WeaponData, data/weapons/*.tres) : catégorie, rareté, dégâts, cadence, chargeur, rechargement, portée, dispersion, perforation, explosion, ressenti (recul, secousse). Ajoutables sans toucher au code. Objectif : au moins 30 armes.

## Tourelles
Tourelles immobiles fixées à certains murs (cône de tir, télégraphe avant la rafale, destructibles), dans tous les biomes.

## Ennemis et IA
- Zone de détection (Area2D cercle ou cône) + raycast de ligne de vue (murs bloquants).
- États : Patrouille/Idle → Alerte (« ! », courte pause) → Poursuite → Attaque → Retour.
- Un ennemi alerté prévient ses voisins proches.
- Archétypes : mêlée, distance, tank, rapide, invocateur, kamikaze, élite, boss à phases.
- StateMachine générique réutilisable, navigation via NavigationAgent2D.

## Architecture
/scenes (player, enemies, rooms, ui, hub)
/scripts (core, combat, ai, loot, dungeon, inventory, save)
/data (weapons, enemies, turrets, loot_tables, skins, items, maps, worlds, balance.cfg)
/assets (sprites, sfx, music, shaders)
/tests
/addons (gut)
- Autoloads : GameState, SaveManager, Profile, LootManager, EventBus, CloudSync. Systèmes découplés par signaux.
- Sauvegarde locale JSON (réserve d'armes, objets, gemmes, skins, progression), synchronisée dans le cloud par CloudSync (Supabase, compte invité automatique ; voir docs/CLOUD_SAVE.md).
- Mobile : pooling projectiles/effets, cible 60 fps.

## GitHub
- .gitignore Godot, .gitattributes (fins de ligne LF, binaires directement dans git, pas de LFS), README, LICENSE, ROADMAP.md.
- GitHub Actions : `ci.yml` sur chaque PR (compilation, lint gdlint en avertissement, tests GUT, tests serveur, export debug Linux/Web), `android.yml` (APK de test publié à chaque push sur `main`), `export.yml` (exports Windows, Linux, Web, Android à chaque tag `v*`, image godot-ci). Godot est installé par l'action composite `.github/actions/setup-godot`.

## ROADMAP
1. Base : dépôt, structure, joueur (déplacement + tir auto), caméra, debug F3.
2. Ennemis : détection, ligne de vue, machine à états.
3. Donjon : salles + couloirs, étages, brouillard de guerre.
4. Loot : conteneurs, tables, raretés, inventaire de raid.
5. Clefs spéciales et zones de super-loot.
6. Extraction, mort, réserve, hub, difficultés.
7. Arsenal de départ, boutique cosmétique (fait, refonte Exfil Rush).
8. Catalogue d'armes, affixes, armes de boss.
9. Royaumes, boss, équilibrage.
10. UI mobile, polish, sons, CI d'export.
