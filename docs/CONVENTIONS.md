# Conventions techniques (contrat entre modules)

## Moteur
- Godot 4.4.1, GDScript **typé** (annoter variables, paramètres, retours).
- Binaire : `godot` (dans le PATH). Projet : `/home/claude/royaumes-des-masques`.
- Vérif compilation : `godot --headless --path . --import` puis `godot --headless --path . --quit`.
- Vérif exécution de la scène principale : `godot --headless --path . --quit-after 300` (aucune erreur SCRIPT ERROR ne doit sortir).
- Résolution de référence : 720 x 1280 (portrait, style Archero).

## Autoloads (déjà écrits, ne pas modifier sans raison)
- `EventBus` : signaux globaux (player_spawned, player_damaged, player_died, enemy_spawned, enemy_died, projectile_fired, debug_toggled).
- `Balance` : `Balance.get_float("section", "cle", defaut)` / `Balance.get_value(...)`. Fichier : `data/balance.cfg`. Toute valeur d'équilibrage y va.
- `InputSetup` : actions `move_up/down/left/right` (ZQSD + WASD + flèches), `toggle_debug` (F3), `interact` (E), `fire_manual` (clic gauche).
- `GameState` : `player`, `debug_enabled`, `run_seed`. Bascule le debug sur F3 et émet `EventBus.debug_toggled`.
- `SaveManager`, `LootManager` : stubs.

## Couches de collision (numéro de couche → valeur bitmask)
| Couche | Nom | Bit |
|---|---|---|
| 1 | world (murs) | 1 |
| 2 | player | 2 |
| 3 | enemies | 4 |
| 4 | player_projectiles | 8 |
| 5 | enemy_projectiles | 16 |
| 6 | interactables | 32 |

## Groupes
- `player` : le joueur.
- `enemies` : toute cible ennemie (le tir auto cible ce groupe).
- `damageable` : tout ce qui encaisse des dégâts.
- `enemy_units` : tous les ennemis, morts ou vivants (pour les compteurs). `enemies` ne contient que les ennemis ciblables.

## Interface de dégâts
Tout nœud du groupe `damageable` implémente :
```gdscript
func take_damage(amount: float, source: Node) -> void
func is_alive() -> bool
```

## Chemins partagés (phase 1)
- Joueur : `res://scenes/player/player.tscn` (racine CharacterBody2D, script `res://scripts/player/player.gd`, classe `Player`).
  - Propriétés publiques : `hp: float`, `max_hp: float`, `weapon: WeaponData`, `current_target: Node2D` (peut être null).
  - Contient sa propre Camera2D.
  - Émet `EventBus.player_spawned.emit(self)` dans `_ready`.
- Joystick virtuel : `res://scenes/ui/virtual_joystick.tscn` (Control, script `res://scripts/ui/virtual_joystick.gd`, classe `VirtualJoystick`), propriété `output: Vector2` (longueur 0..1). Le joueur le trouve via le groupe `virtual_joystick`.
- Ressource arme : `res://scripts/combat/weapon_data.gd` (classe `WeaponData`, Resource).
- Projectile : `res://scenes/combat/projectile.tscn`, pooling via `res://scripts/combat/projectile_pool.gd` (classe `ProjectilePool`).
- Cible d'entraînement : `res://scenes/enemies/target_dummy.tscn`.
- Overlay debug : `res://scenes/ui/debug_overlay.tscn`.
- Scène principale : `res://scenes/rooms/test_room.tscn`.

## Phase 2 : sprites et ennemis
### Référence visuelle
`docs/reference/royaumes_des_masques.jpg` (seule partie qui fait foi). Les personnages sont vus en **3/4 de face, légèrement en plongée** (style Archero), pas en vue strictement de dessus. Orientation gauche/droite par `flip_h`.

### Sprites (SVG importés par Godot, dans `assets/sprites/`)
- Héros : `res://assets/sprites/hero/hero_kitsune.svg` (+ éventuelles frames `hero_kitsune_walk_1.svg`, `_2.svg`). Pieds (point d'ancrage au sol) en bas au centre.
- Ennemis : `res://assets/sprites/enemies/<kind>.svg` pour `kind` ∈ `golem`, `masked_grunt`, `masked_archer`, `masked_brute`. Pieds en bas au centre.
- Taille à l'écran (zoom caméra 1.3 inclus) : héros ≈ 70 px de haut ; grunt/archer ≈ 75 px ; brute ≈ 95 px ; golem ≈ 120 px.

### Composant visuel ennemi (agent art monstres)
`res://scripts/enemies/enemy_visual.gd`, `class_name EnemyVisual extends Node2D`, enfant de l'ennemi, sans logique de jeu :
- `setup(kind: StringName) -> void` : charge le sprite, règle échelle et ombre au sol.
- `set_facing(dir: Vector2) -> void`, `set_moving(moving: bool) -> void` (petit balancement de marche).
- `flash_hit() -> void`, `play_alert() -> void` (icône « ! » au-dessus de la tête), `play_attack_windup(duration: float) -> void` (lueur/télégraphe rouge), `play_death() -> void` (dissolution, puis signal `death_finished`).
- `set_aura(color: Color)` (teinte de masque par royaume).
- `get_head_offset() -> Vector2` (où placer barre de vie et « ! »).

### Ennemis (agent IA)
- `res://scripts/enemies/enemy_data.gd` : `class_name EnemyData extends Resource` (kind, display_name, max_hp, move_speed, detection_radius, detection_angle_deg (360 = cercle), lose_sight_time, alert_duration, attack_range, attack_damage, attack_cooldown, attack_windup, attack_type (melee/ranged), projectile_speed, alert_neighbors_radius, patrol_radius).
- `data/enemies/<kind>.tres`.
- `res://scripts/enemies/enemy.gd` : `class_name Enemy extends CharacterBody2D` ; `res://scenes/enemies/enemy.tscn` ; `Enemy.spawn(data: EnemyData)` ou `@export var data`.
- Machine à états générique : `res://scripts/ai/state_machine.gd` (`StateMachine`) et `res://scripts/ai/state.gd` (`State`). États : Patrol/Idle → Alert → Chase → Attack → Return.
- Groupes : `enemies`, `damageable`, `enemy_units`. Couche 3 (bit 4). Les ennemis doivent être des CharacterBody2D (les projectiles Area2D les détectent).

## Style
- Personnages et monstres : sprites SVG (voir phase 2). Décors et effets : dessin en code (`_draw()`) acceptable.
- Couleurs chaudes, contours nets.
- Construire les structures complexes en code ; garder les .tscn minimaux.
- Commentaires et textes de jeu en français.
