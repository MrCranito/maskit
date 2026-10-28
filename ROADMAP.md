# Roadmap

Les phases se font une par une. Chacune se termine par un résumé, des tests et une PR vers `develop`.

## Phase 1 — Base *(terminée)*
- [x] Dépôt : .gitignore, .gitattributes (LFS), LICENSE, README, ROADMAP
- [x] GUT installé, tests headless et CI GitHub Actions (tests + exports)
- [x] Autoloads : EventBus, Balance (`data/balance.cfg`), InputSetup, GameState
- [x] Joueur : déplacement clavier (ZQSD/WASD/flèches) et joystick virtuel mobile
- [x] Tir automatique sur l'ennemi le plus proche avec pooling des projectiles, plus un tir manuel au clic gauche
- [x] Caméra qui suit le joueur, salle de test avec cible d'entraînement
- [x] Overlay de debug F3 : FPS, seed, zones de portée

## Phase 2 — Ennemis *(terminée)*
- [x] StateMachine générique réutilisable (Idle/Patrouille → Alerte → Poursuite → Attaque → Retour)
- [x] Zone de détection (cercle ou cône) et raycast de ligne de vue bloqué par les murs
- [x] Indicateur « ! » à l'alerte et propagation de l'alerte aux voisins proches
- [x] Navigation avec NavigationAgent2D
- [x] Premiers archétypes : mêlée, distance, kamikaze
- [x] Debug F3 : cônes de détection, état courant de chaque ennemi

## Phase 3 — Donjon (monde 1 Far West) *(terminée)*
- [x] Générateur de graphe de salles à partir d'une seed rejouable
- [x] Types de salles : combat, fouille, piège, repos, super-loot, boss, extraction
- [x] Couloirs entre les salles, collisions et navigation
- [x] Plusieurs étages reliés par des escaliers, avec une difficulté croissante
- [x] Brouillard de guerre à 3 états (texture de masque et shader sur un CanvasLayer)
- [x] Debug F3 : graphe des salles, seed

## Phase 4 — Loot *(terminée)*
- [x] Ressources ItemData / raretés (gris, vert, bleu, violet, orange avec lueur)
- [x] Tables de loot pondérées selon le conteneur, la difficulté, l'étage et la zone
- [x] Conteneurs fouillables avec une animation de fouille interruptible
- [x] Inventaire de raid limité (grille ou poids) et UI associée
- [x] Debug F3 : taux de drop observés

## Phase 5 — Clefs spéciales et super-loot *(en partie : clefs sur ennemis et portes verrouillées faites — prochaine)*
- [ ] Drop de clefs sur les ennemis uniquement (taux de 0,5 % à 2 %, réglé dans balance.cfg)
- [ ] Portes scellées visibles, chacune liée à une clef précise
- [ ] Salles de super-loot : taux Épique/Légendaire augmentés et gardes d'élite
- [ ] Clefs extractibles et conservées dans la réserve
- [ ] Tests statistiques des taux de drop (GUT)

## Phase 6 — Extraction, mort, hub
- [ ] Points d'extraction avec une canalisation interrompue par les attaques
- [ ] Réussite : butin transféré dans la réserve. Mort : butin perdu, sauf l'emplacement sécurisé
- [ ] Sauvegarde locale JSON (réserve, masques, progression) avec SaveManager
- [ ] Hub : choix du masque, de l'équipement et de la difficulté (Facile → Cauchemar)
- [ ] Vente et amélioration d'objets

## Phase 7 — Masques et pouvoirs *(en partie : choix du masque au menu et stats faits ; pouvoirs à faire)*
- [ ] Ressource MaskData (stats, pouvoir actif, passif, armes autorisées)
- [ ] Colosse : attaques lentes et lourdes, grande résistance
- [ ] Spectre : vitesse, esquive, attaques surprises
- [ ] Alchimiste : explosions, zones, effets élémentaires
- [ ] Marionnettiste : invocations alliées

## Phase 8 — Armes
- [ ] Ressource WeaponData complète (rareté, pattern d'attaque/projectile, affixes)
- [ ] Affixes aléatoires : brûlure, gel, ricochet, multi-tir, vol de vie, onde de choc…
- [ ] Au moins 30 armes en `.tres`, ajoutables sans toucher au code
- [ ] Armes de boss avec des effets uniques, armes vivantes évolutives
- [ ] Tests de génération d'affixes

## Phase 9 — Royaumes, boss, équilibrage
- [ ] Quatre royaumes : palettes, ennemis, tables de loot et armes propres
- [ ] Boss à phases (un par royaume)
- [ ] Archétypes restants : tank, rapide, invocateur, élite
- [ ] Passe d'équilibrage complète dans `data/balance.cfg`

## Phase 10 — UI mobile, polish, CI d'export *(en partie : paysage, double joystick, splash, menus, pause, inventaire, sons téléchargés)*
- [ ] UI mobile finale (zones tactiles, safe areas, lisibilité)
- [ ] Sons, musiques, effets visuels (avec pooling)
- [ ] Performances : 60 fps sur mobile milieu de gamme
- [ ] Exports Windows, Linux, Web et Android validés par CI sur tag `v*`
- [ ] Keystore Android de release dans les secrets GitHub

## Retour de test (octobre 2026) — fait
- [x] Brouillard permanent refait (polygone de visibilité, brume animée)
- [x] Héros modélisé sous Blender (8 directions, idle/course), revolver tenu
- [x] Paysage uniquement, double joystick, déplacement fluide, aide à la visée
- [x] Jauge de reconnaissance des ennemis (vue + bruit), enquête, cachettes
- [x] Coffres et conteneurs fouillables, inventaire
- [x] Décors refaits (Blender), splash, menu, choix du masque
- [x] Optimisations (60 i/s max, interpolation physique, ennemis endormis au loin, draw calls ÷20, option 30 i/s)
- [x] Correctif : les balles touchent (trajectoire au niveau des hitbox)
- [ ] Brancher les sons et musiques en jeu
- [ ] Ennemis re-rendus sous Blender (même style que le héros)
