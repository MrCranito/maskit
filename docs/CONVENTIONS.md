# Conventions techniques (contrat entre modules)

## Moteur
- Godot 4.7.2 (depuis la phase 3 ; 4.4.1 avant), GDScript **typé** (annoter variables, paramètres, retours).
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
- Joystick virtuel : `res://scenes/ui/virtual_joystick.tscn` (Control, script `res://scripts/ui/virtual_joystick.gd`, classe `TouchJoystick` (renommée : Godot 4.7 a une classe native VirtualJoystick)), propriété `output: Vector2` (longueur 0..1). Le joueur le trouve via le groupe `virtual_joystick`.
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

## Phase 3 : monde Far West, bâtiments, étages, brouillard
Lire d'abord CLAUDE.md, sections « Mondes et biomes » et « Structure des cartes ».

### Données de carte (déjà écrites)
`res://scripts/dungeon/floor_layout.gd` (`FloorLayout`, RefCounted, pur données) : grille `tiles` (enum `Tile` : VOID, STREET, FLOOR, WALL, DOOR, STAIRS_UP, STAIRS_DOWN), `rooms` (Room : id, rect, outdoor, building_id, type, name), `buildings` (archetype, rect, room_ids, door_ids), `doors` (cell, vertical, state OPEN/CLOSED/LOCKED, key_id, room_a/b), `stairs` (cell, up, target_floor, target_cell), `player_spawn`, `extraction_cells`, `enemy_spawns` / `container_spawns` / `prop_spawns` (Spawn : cell, kind, room_id).
- `FloorLayout.TILE_SIZE = 64`, `cell_to_world(c)` (centre de case), `world_to_cell(p)`.
- `FloorLayout.make_sample()` : carte écrite à la main (rue, saloon + escalier, banque + coffre verrouillé `key_bank_vault`, shérif, ruelle d'extraction). Sert à développer en parallèle du générateur.
- VOID et WALL sont infranchissables et opaques. Une case DOOR est opaque et infranchissable tant que la porte est fermée.
- Scripts `extends SceneTree` lancés avec `--script` : faire `godot --headless --path . --import` avant, sinon les `class_name` récents ne sont pas connus.

### Modules et propriétaires
| Module | Fichiers | API |
|---|---|---|
| Monde | `scripts/dungeon/world_data.gd` (`WorldData`, Resource), `data/worlds/world_01_far_west.tres` | id, display_name, biome, palette (Dictionary de Color), enemy_roster (Dictionary type de salle → {kind: poids}), building_archetypes, container_kinds, prop_kinds, floors_min/max |
| Générateur | `scripts/dungeon/dungeon_generator.gd` (`DungeonGenerator`) | `static generate_run(seed: int, world: WorldData, difficulty: int) -> Array[FloorLayout]` (étages -1, 0, 1 selon le monde ; escaliers cohérents entre étages) ; `static generate_floor(seed, world, difficulty, floor_index) -> FloorLayout` |
| Décor | `scripts/dungeon/world_builder.gd` (`WorldBuilder`), `scripts/dungeon/door.gd` (`DoorNode`) + `scenes/dungeon/door.tscn`, `scripts/dungeon/roof.gd`, `scripts/dungeon/prop.gd`, `assets/sprites/far_west/` | `WorldBuilder.build(layout: FloorLayout, world: WorldData) -> Node2D` (sol, murs avec collisions couche world, toits, portes, escaliers, décors). Renvoie un nœud racine ayant `get_doors() -> Array[DoorNode]`, `get_stairs_areas() -> Array[Area2D]` (meta `stairs` = FloorLayout.Stairs), signal `stairs_entered(stairs)` |
| Portes | `DoorNode` (StaticBody2D, couche world quand fermée, groupe `doors`) | `cell: Vector2i`, `is_open()`, `is_locked()`, `open()`, `close()`, `try_unlock(key_id) -> bool`, signal `state_changed(door)`. S'ouvre automatiquement quand le joueur ou un ennemi en poursuite la touche (adapté au mobile) ; verrouillée = cadenas + message « Clef requise ». |
| Brouillard | `scripts/dungeon/fog_of_war.gd` (`FogOfWar`, Node2D) + `assets/shaders/fog_of_war.gdshader` | `setup(layout: FloorLayout)`, `set_door_query(callable: Callable)` (cell → bool ouverte), `update_from(world_pos: Vector2)`, `is_cell_visible(c)`, `is_cell_explored(c)`, `reveal_all(on: bool)`, `get_state() -> PackedByteArray` / `set_state(...)` (mémoire par étage). Cache les nœuds du groupe `fog_hideable` (ennemis, conteneurs) hors des cases visibles. |
| Ennemis Far West | `assets/sprites/enemies/` (nouveaux kinds), `scripts/enemies/enemy_visual.gd` (KINDS), `data/enemies/*.tres` | Nouveaux kinds : `outlaw_knife`, `gunslinger`, `shotgun_brute`, `sandstone_colossus`. Les anciens kinds restent (autres mondes). |
| Raid | `scripts/dungeon/raid.gd` (`Raid`) + `scenes/dungeon/raid.tscn` (nouvelle scène principale) | Charge le monde 1, génère (ou `make_sample()` si le générateur manque), construit l'étage, place joueur/ennemis, brouillard, UI ; change d'étage par les escaliers en conservant l'état de chaque étage ; marqueur d'extraction (logique en phase 6). |

### Couches de rendu (z_index)
Sol 0 · décors au sol 1 · personnages/ennemis/murs triés en Y (y_sort) 10 · toits 50 · brouillard 80 · UI dans CanvasLayer.

## Refonte « retour de test » (après la phase 3)
### Règles de performance (OBLIGATOIRES pour tout le monde — l'iPhone chauffait)
- Pas de `queue_redraw()` à chaque frame : seulement quand l'état visuel change. Les dessins statiques sont faits une fois (ou mis en cache dans une texture).
- Pas d'allocation par frame (tableaux, dictionnaires, `PackedVector2Array` recréés) dans `_process`/`_physics_process` ; réutiliser des buffers.
- Raycasts et requêtes physiques espacées (timers 0,1 s), jamais N×M par frame.
- `set_process(false)` / `set_physics_process(false)` pour ce qui est hors écran ou inactif (ennemis loin du joueur, décors).
- Aucun shader plein écran coûteux : une seule passe pour le brouillard, pas de boucles lourdes dans les fragment shaders.
- Cible : 60 fps stables, CPU faible. Le projet limite à 60 fps et active l'interpolation physique.

### Orientation et contrôles
- Jeu **uniquement en paysage** : viewport 1280×720, `window/handheld/orientation` = paysage (capteur).
- **Deux joysticks** (mobile) : gauche = déplacement, droit = viser et tirer (tir continu tant que le stick droit est poussé au-delà de la zone morte). PC : ZQSD/WASD + souris (viser), clic gauche (tirer). Plus de tir automatique.
- Les joysticks sont deux instances de `TouchJoystick` avec `side` = `&"left"` / `&"right"`, groupes `joystick_move` / `joystick_aim`.

### Joueur (API ajoutée)
- `aim_direction: Vector2` (normalisé), `is_moving() -> bool`, `is_hidden() -> bool`, `set_hidden(on: bool, spot: Node = null)`.
- `get_noise_level() -> float` (0..1) : 0 immobile, ~0,35 en marche, 1 juste après un tir (décroît en ~0,6 s). Signal `fired(direction: Vector2)`. Caché = bruit 0 et invisible pour les ennemis.
- Sprite du héros : `res://assets/sprites/hero3d/hero_frames.tres` (SpriteFrames) avec animations `idle_<dir>` et `run_<dir>`, `<dir>` ∈ `e, se, s, sw, w, nw, n, ne` ; métadonnées `res://assets/sprites/hero3d/hero_meta.json` (`frame_size`, `feet_offset` [x,y] en px depuis le coin haut-gauche du cadre, `display_height` en unités monde, `fps`). Repli : anciens SVG.
- Arme tenue : `res://assets/sprites/weapons/<id>.png` (pointe vers la droite) + `res://assets/sprites/weapons/<id>.json` (`grip` [x,y] en px = point de rotation dans la main, `muzzle` [x,y] = bout du canon, `scale`). Première arme : `revolver`. Le joueur la fait tourner vers `aim_direction` (flip vertical quand on vise à gauche).
- Portraits de masques pour les menus : `res://assets/ui/masks/<mask_id>.png` (`colosse`, `spectre`, `alchimiste`, `marionnettiste`, `kitsune`).

### Masques (choix au menu)
- `res://scripts/core/mask_data.gd` (`MaskData`, Resource) + `data/masks/<id>.tres` : id, display_name, description, aura_color, stats (max_hp_mult, speed_mult, damage_mult, fire_rate_mult). `GameState.selected_mask_id` (défaut `&"kitsune"`).

### Discrétion (ennemis)
- Chaque ennemi a une **jauge de reconnaissance** 0..1 affichée au-dessus de la tête quand > 0 : monte avec la vue (joueur dans le champ de vision, ligne de vue, plus vite de près) et le bruit (`get_noise_level()` × proximité), redescend lentement sinon. Pleine → attaque (état Alert puis Chase). Joueur caché → la jauge ne monte pas (sauf si l'ennemi l'a vu se cacher de très près).

### Butin, inventaire, cachettes
- `scripts/loot/item_data.gd` (`ItemData`), `data/items/*.tres`, tables `data/loot_tables/*.tres`, raretés 0..4 (Commun→Légendaire, couleurs de CLAUDE.md).
- Conteneurs (`scripts/loot/loot_container.gd`, groupe `containers`, `fog_hideable`) placés depuis `layout.container_spawns` ; fouille = maintenir l'interaction ~1,2 s (interrompue si on bouge ou si on est touché).
- Cachettes (`scripts/loot/hiding_spot.gd`, groupe `hiding_spots`) : tonneau, armoire, botte de foin… ; entrer/sortir par l'interaction.
- Interaction : bouton tactile « action » (à droite, au-dessus du stick de visée) + touche E. Signal `EventBus.interact_target_changed(target: Node)` ; les cibles ont `get_interact_label() -> String` et `interact(player)`.
- Inventaire de raid : `GameState.raid_inventory` (`Inventory`, RefCounted) ; écran d'inventaire (bouton sac en haut à droite / touche I / Tab).
