# Conventions techniques (contrat entre modules)

## Moteur
- Godot 4.7.2 (depuis la phase 3 ; 4.4.1 avant), GDScript **typé** (annoter variables, paramètres, retours).
- Binaire : `godot` (dans le PATH). Projet : `/home/claude/maskit` (dépôt MrCranito/maskit).
- Vérif compilation : `godot --headless --path . --import` puis `godot --headless --path . --quit`.
- Vérif exécution de la scène principale : `godot --headless --path . --quit-after 300` (aucune erreur SCRIPT ERROR ne doit sortir).
- Résolution de référence : 1280 x 720 (paysage uniquement).
- Import des textures (taille de l'APK) : après l'ajout d'atlas, de textures de sol/murs ou d'un paquet pré-rendu, lancer `python tools/apply_texture_imports.py` puis réimporter. Pré-rendu : WebP avec perte (qualité 0,9), sauf `o_*.png` et `footprint.png` sans perte ; atlas d'ennemis, atlas de biome, sols et murs : Basis Universal (pas de VRAM brut, mode 2). Vérifié par `tests/test_texture_imports.gd`. `docs/`, `tools/`, `art/`, `server/`, `supabase/` ne sont jamais exportés (exclude_filter) : le jeu ne doit rien y charger.

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
| Brouillard | `scripts/dungeon/fog_of_war.gd` (`FogOfWar`, Node2D) + `assets/shaders/fog_darkened.gdshader` / `fog_mist.gdshader` (style `[fog] fog_style`, partie commune `fog_common.gdshaderinc`) | `setup(layout: FloorLayout)`, `set_door_query(callable: Callable)` (cell → bool ouverte), `update_from(world_pos: Vector2)`, `is_cell_visible(c)`, `is_cell_explored(c)`, `reveal_all(on: bool)`, `get_state() -> PackedByteArray` / `set_state(...)` (mémoire par étage). Cache les nœuds du groupe `fog_hideable` (ennemis, conteneurs) hors des cases visibles. |
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

### Masques — SUPPRIMÉS (refonte Exfil Rush)
Remplacés par l'arsenal (voir la dernière section). Plus de MaskData, data/masks, assets/ui/masks.

### Discrétion (ennemis)
- Chaque ennemi a une **jauge de reconnaissance** 0..1 affichée au-dessus de la tête quand > 0 : monte avec la vue (joueur dans le champ de vision, ligne de vue, plus vite de près) et le bruit (`get_noise_level()` × proximité), redescend lentement sinon. Pleine → attaque (état Alert puis Chase). Joueur caché → la jauge ne monte pas (sauf si l'ennemi l'a vu se cacher de très près).

### Butin, inventaire, cachettes
- `scripts/loot/item_data.gd` (`ItemData`), `data/items/*.tres`, tables `data/loot_tables/*.tres`, raretés 0..4 (Commun→Légendaire, couleurs de CLAUDE.md).
- Conteneurs (`scripts/loot/loot_container.gd`, groupe `containers`, `fog_hideable`) placés depuis `layout.container_spawns` ; fouille = maintenir l'interaction ~1,2 s (interrompue si on bouge ou si on est touché).
- Cachettes (`scripts/loot/hiding_spot.gd`, groupe `hiding_spots`) : tonneau, armoire, botte de foin… ; entrer/sortir par l'interaction.
- Interaction : bouton tactile « action » (à droite, au-dessus du stick de visée) + touche E. Signal `EventBus.interact_target_changed(target: Node)` ; les cibles ont `get_interact_label() -> String` et `interact(player)`.
- Inventaire de raid : `GameState.raid_inventory` (`Inventory`, RefCounted) ; écran d'inventaire (bouton sac en haut à droite / touche I / Tab).

## Cartes et biomes (après le retour de test)
### Cartes (sélection au clic sur « Jouer »)
- `scripts/maps/map_card.gd` (`MapCard`, Resource) + `data/maps/*.tres` : id, nom, monde (`world_path`), catégorie (`permanent`, `weekly`, `monthly`, `event`), difficulté (0..4, propre à la carte), modificateurs (propriétés différentes par carte).
- `scripts/maps/map_rotation.gd` (`MapRotation`) : cartes disponibles à un instant donné, calculées de façon déterministe depuis l'heure UTC (mêmes cartes pour tous les joueurs, sans serveur). Événements : 2 h.
- Au lancement d'un raid : `GameState.world_path`, `GameState.difficulty`, `GameState.current_map` (la MapCard) sont fixés par l'écran de sélection de carte. La difficulté n'est plus choisie avec le masque.

### Biomes (un monde = un biome)
| Biome | Monde | Dossiers |
|---|---|---|
| Far West | `data/worlds/world_01_far_west.tres` | `scripts/dungeon/` (générateur, WorldBuilder), `assets/sprites/far_west/` |
| Station spatiale | `data/worlds/world_02_space_station.tres` | `scripts/biomes/space_station/`, `assets/sprites/space_station/`, `art/blender/space_station/` |
| Centre commercial abandonné | `data/worlds/world_03_mall.tres` | `scripts/biomes/mall/`, `assets/sprites/mall/`, `art/blender/mall/` |
| ~~Station sous-marine~~ (retirée) | `data/worlds/world_04_underwater.tres` | `scripts/biomes/underwater/`, `assets/sprites/underwater/`, `art/blender/underwater/` |

> **29/10/2026 : le 4e monde « Station sous-marine » (Abysse Nérée, `world_04_underwater`) a été retiré** (refonte du bestiaire) : scripts, données (ennemis `uw_*`, objets, clefs, tables, cartes, tourelles), sprites, textures, modèles Blender, tests et section `[underwater]` de balance.cfg supprimés. Les chemins ci-dessous qui le mentionnent sont historiques.

Chaque biome fournit, à ces chemins :
- **Monde** (`WorldData`) avec `generator_path`, `builder_path`, `containers_dir`, `floor_names`, `enemy_roster`, `container_kinds`, `prop_kinds`, `palette`, `music_explore/combat`.
- **Générateur** : `static func generate_run(seed: int, world: WorldData, difficulty: int) -> Array[FloorLayout]` (format `FloorLayout`, avec `hiding_spot_spawns`, déterministe, connectivité garantie, salles super_loot verrouillées par clef). Mêmes règles que le générateur Far West (tests de connectivité, perf < 50 ms/étage).
- **Constructeur de décor** : `static func build(layout: FloorLayout, world: Resource) -> Node2D` ayant la même API que `WorldBuilder` : `get_doors() -> Array[DoorNode]`, `get_stairs_areas() -> Array[Area2D]` (meta `stairs`), `signal stairs_entered(stairs)`, `get_room_at_world(pos)`, `set_stairs_cooldown(sec)`. Murs sur la couche world (bit 1), z_index du contrat. Portes : instances de `DoorNode` (sous-classe autorisée dans le dossier du biome pour un autre dessin : surcharger `_draw`), groupe `doors`.
- **Ennemis** : `scripts/biomes/<biome>/enemy_kinds.gd` avec `const KINDS := {kind: {...}}` au format de `EnemyVisual.KINDS` (path vers PNG rendu sous Blender, svg_size = taille du PNG, feet, scale, head, shadow, eyes, eye_r, debris, aura) — chargé automatiquement par `BiomeRegistry`. `data/enemies/<kind>.tres` (EnemyData complet, discrétion comprise).
- **Conteneurs et cachettes** : sprites dans `containers_dir` (`<kind>.png`, `<kind>_open.png`, `hide_<kind>.png`), tables `data/loot_tables/<kind>.tres`, objets propres au biome `data/items/<id>.tres` (préfixe du biome dans l'id). Les cachettes doivent avoir un `kind` présent dans `containers_dir`.
- Le raid charge tout dynamiquement (`GameState.world_path`) ; `BiomeAssets.set_world(world)` est appelé avant la construction.
- Style : même pipeline Blender que le héros (`art/blender/rdm_common.py` : caméra orthographique 3/4 à 48°, matériaux toon, contour Freestyle), même échelle (héros ≈ 64 unités monde), règles de performance de la « Refonte » (atlas, peu de nœuds, pas de redessin par frame, aucune lumière dynamique).

## Refonte « Exfil Rush » (retour de test n°3) — CONTRAT ENTRE AGENTS
Le jeu s'appelle désormais **Exfil Rush**. Le projet est dans
`/home/claude/maskit` (dépôt GitHub MrCranito/maskit). **Les masques n'existent plus** : plus de
MaskData, de choix de masque, d'aura, de portraits. Le héros est un personnage simple sans masque.
Les ennemis « masqués » (outlaw, masked_grunt…) restent : ce sont des ennemis, pas le système.

### Fondations déjà écrites (ne pas changer les signatures sans l'orchestrateur)
- `scripts/combat/weapon_data.gd` (`WeaponData`) : category (CAT_*), rarity, tir, chargeur
  (magazine_size, reload_time, automatic), explosion (explosion_radius/damage), ressenti
  (recoil_px, shake_px, move_speed_mult, muzzle_flash_scale, eject_shells), projectile_style
  (bullet, pellet, tracer, rocket, grenade), sprite_id, icon, permanent, value.
- `scripts/combat/weapon_catalog.gd` (`WeaponCatalog`) : get_weapon(id), all(), get_starter(),
  icon_for(w) (icône `assets/ui/weapons/<sprite_id>.png`, sinon `<category>.png`). STARTER_ID = starter_pistol.
- `scripts/loot/item_data.gd` : `weapon_id` + `is_weapon()`. Un objet arme dans le sac = `data/items/wpn_<weapon_id>.tres`
  (type weapon, weapon_id, icon vide → l'UI utilise WeaponCatalog.icon_for).
- Autoload **`Profile`** (`scripts/core/profile.gd`) : réserve d'armes (uids), arsenal de départ (`loadout`, 3 emplacements,
  `[arsenal] loadout_slots`), objets extraits, gemmes, dollars, skins. API : get_stash_weapons(), set_loadout(uids),
  get_loadout_weapons(), can_start_raid(), start_raid(), finish_extraction(weapon_ids, bag) → résumé,
  finish_death() → résumé, ensure_starter(), add_gems(n), owns_skin(id), buy_skin(id), equip_character_skin(id),
  get_character_skin(), equip_weapon_skin(id, category), get_weapon_skin(category), signaux changed / gems_changed.
- `GameState.begin_raid()` : nouveau sac + `GameState.raid_weapons = Profile.start_raid()`. Les menus l'appellent juste
  avant de charger `res://scenes/dungeon/raid.tscn`. `GameState.raid_weapons` vide (raid lancé en debug) → pistolet de départ.
- `scripts/cosmetics/skin_data.gd` (`SkinData`, data/skins/*.tres), `weapon_skin.gd` (`WeaponSkin.apply(item, skin)`),
  `hero_skin.gd` (`HeroSkin.frames_for/meta_for/material_for/current`). Les deux derniers sont des stubs à compléter
  par leurs propriétaires (voir tableau).
- balance.cfg : sections `[arsenal]`, `[extraction]`, `[shop]`.

### Règles de la boucle
- Avant un raid : choix de la carte → **validation de l'arsenal de départ** (1 à 3 armes de la réserve) → raid.
- **Mort** (ou « Abandonner le raid » dans la pause, ou jeu quitté en plein raid) : écran de mort (armes et butin perdus),
  puis retour au menu principal. `Profile.finish_death()`. Si la réserve est vide, un pistolet de départ est offert.
- **Extraction** : rester `[extraction] channel_time` s sur une case d'extraction (barre circulaire, interrompue si on sort ;
  les ennemis proches sont alertés au début). Réussite → `Profile.finish_extraction(armes tenues, sac)` → écran de résumé
  (armes, objets, valeur, gemmes gagnées) → menu principal.
- En raid, le joueur tient jusqu'à 3 armes (emplacements) ; les armes trouvées vont dans le sac et peuvent être équipées
  depuis l'inventaire (échange avec l'arme de l'emplacement courant, qui retourne dans le sac).
- Monétisation : **uniquement cosmétique** (skins de personnage et d'armes) payés en gemmes. Gemmes : packs (paiement
  **simulé** pour l'instant, `scripts/cosmetics/store.gd`) + quelques gemmes à chaque extraction réussie. Aucun bonus de stats.

### API joueur (propriétaire : agent Joueur)
`Player` : `set_weapons(list: Array[WeaponData])`, `get_weapons() -> Array[WeaponData]` (taille ≤ 3, null = emplacement vide),
`current_slot: int`, `weapon` (arme courante, compatibilité), `switch_to(slot)`, `next_weapon()`,
`equip_into_current_slot(w: WeaponData) -> WeaponData` (renvoie l'arme remplacée, ou null), `get_carried_weapon_ids() -> Array[StringName]`,
`get_ammo() -> int`, `is_reloading()`, `get_reload_progress() -> float`, `reload()`,
signaux `weapons_changed`, `ammo_changed(ammo: int, magazine: int)`, `fired(direction)`. À sa création le joueur lit
`GameState.raid_weapons`. Actions d'entrée : `weapon_next` (Q, molette), `weapon_1..3` (1, 2, 3), `reload` (R).

### Sprites d'armes (propriétaire : agent Art) — liste FIGÉE des sprite_id
`starter_pistol, pistol, pistol_heavy, revolver, revolver_gold, smg, smg_compact, shotgun, shotgun_double, rifle,
rifle_tactical, sniper, sniper_heavy, lmg, rocket_launcher, grenade_launcher` (+ un fichier par catégorie : `pistol`,
`revolver`, `smg`, `shotgun`, `rifle`, `sniper`, `lmg`, `rocket_launcher`, `grenade_launcher` sont dans la liste).
Tenue : `assets/sprites/weapons/<sprite_id>.png` + `.json` (grip, muzzle, scale ; canon vers la droite).
Icône d'inventaire : `assets/ui/weapons/<sprite_id>.png` (vue de profil, fond transparent, ~192×96).

### Propriété des fichiers (un agent ne modifie QUE ses fichiers ; besoin ailleurs → le noter dans son rapport)
| Agent | Fichiers |
|---|---|
| Arsenal & raid | `data/weapons/*`, `data/items/*`, `data/loot_tables/*`, `scripts/dungeon/raid.gd`, `scripts/dungeon/floor_state.gd`, `scripts/loot/*` (sauf item_data.gd), `scripts/ui/hud.gd`, `scripts/ui/inventory_*.gd`, nouveaux `scripts/ui/weapon_hud.gd`, `scripts/ui/raid_end_screen.gd`, tests associés, `tests/test_masks.gd` (à supprimer) |
| Menus | `scripts/ui/menus/*`, `scenes/ui/menus/*`, `assets/ui/masks` (à supprimer), `scripts/cosmetics/weapon_skin.gd`, `scripts/cosmetics/store.gd`, `assets/shaders/weapon_skin.gdshader`, `data/skins/wsk_*.tres`, `scripts/maps/*` (affichage seulement), `tests/test_menus.gd`, `tests/test_maps.gd` |
| Art | `art/blender/*`, `assets/sprites/hero3d/**`, `assets/sprites/hero/**`, `assets/sprites/weapons/*`, `assets/ui/weapons/*`, `scripts/cosmetics/hero_skin.gd`, `data/skins/char_*.tres`, `tests/test_assets.gd` |
| Joueur | `scripts/player/*`, `scenes/player/*`, `scripts/combat/projectile*.gd`, `scenes/combat/projectile.tscn`, `scripts/combat/vfx/*` (nouveau), `scripts/core/input_setup.gd`, `tests/test_player_logic.gd`, `tests/test_controls.gd`, `tests/test_combat_fixes.gd` |
| Tourelles | `scripts/enemies/turret*.gd`, `scripts/dungeon/turret_placer.gd`, `scripts/enemies/turret_data.gd`, `data/turrets/*`, `assets/sprites/turrets/*`, `tests/test_turrets.gd` |
| Décor | `scripts/dungeon/gen/*`, `scripts/dungeon/dungeon_generator.gd`, `scripts/dungeon/world_builder.gd`, `scripts/dungeon/prop.gd`, `scripts/biomes/**`, `assets/sprites/{far_west,space_station,mall,underwater}/**`, `art/blender/{mall,space_station,underwater}/*`, `art/blender/build_props.py`, `tests/test_dungeon_generator.gd`, `tests/test_world_builder.gd`, tests de biome |
| Orchestrateur | `CLAUDE.md`, `docs/*`, `project.godot`, `data/balance.cfg` (les agents y AJOUTENT leur propre section/clés en fin de section, sans toucher aux autres), `scripts/core/*` (hors input_setup), suppression finale de `scripts/core/mask_data.gd` et `data/masks/` |

### État après intégration (refonte Exfil Rush)
- Flux : splash → menu principal (Jouer, Arsenal, Boutique, Options, Crédits) → choix de la carte (grille de vignettes + puces de catégorie + panneau bas) → arsenal de départ (`scenes/ui/menus/loadout.tscn`) → `GameState.begin_raid()` → raid → écran de fin (`scripts/ui/raid_end_screen.gd`) → menu principal.
- Héros : planches `assets/sprites/hero3d/` (idle, run, backpedal, strafe_l, strafe_r, hit × 8 directions), skins dans `assets/sprites/hero3d/skins/<id>/`, chargés via `HeroSkin`. Main : `hand_height` lu dans hero_meta.json (22.6).
- Armes : 38 dans data/weapons (tools/gen_weapons.py les régénère avec leurs objets `wpn_*` et les entrées des tables).
- Joueur : logique d'armes dans `scripts/player/weapon_loadout.gd`, rendu dans `player_visual.gd` / `weapon_view.gd`, effets poolés dans `scripts/combat/vfx/`. Entrées : R recharger, 1/2/3, molette, `weapon_next` (Q physique = A en AZERTY).
- Tourelles : `Turret`, `TurretData` (data/turrets, 3 familles × 4 biomes), `TurretPlacer` (évite portes, escaliers, extraction, spawn, murs décorés `FloorLayout.wall_decor_cells`).
- Décor : `scripts/dungeon/gen/furnisher.gd` (moteur commun) + gabarits par biome (`gen/fw_templates.gd`, `biomes/*/*_templates.gd`). FloorLayout : `Spawn.offset/size/flip/rot`, `decor_spawns`, `wall_decor_cells`, `partition_cells`.
- Debug (F3 activé) : F5 extraction instantanée, F6 mort instantanée.

## Refonte n°2 « planches de référence » (CONTRAT) — personnages, arsenal, cartes
Références (à regarder avec Read) : `docs/reference/personnages_skins.jpg`, `docs/reference/arsenal.jpg`, `docs/reference/cartes.png`.

### Arsenal = EXACTEMENT la planche arsenal.jpg (skins d'armes : plus tard, onglet masqué)
Catégories (`WeaponData.CATEGORIES`) : pistol, smg, rifle, sniper, rocket_launcher, gadget (« Autres »).
Les anciennes catégories revolver/shotgun/lmg/grenade_launcher et leurs armes disparaissent du catalogue.
| id | Nom affiché | Catégorie | Rareté |
|---|---|---|---|
| pistol_p9 | P9 | pistol | 0 Commun (= arme de départ, `WeaponCatalog.STARTER_ID`) |
| pistol_glock18 | Glock 18 | pistol | 2 Rare |
| pistol_deagle | Desert Eagle | pistol | 3 Épique |
| pistol_p320 | P320 | pistol | 4 Légendaire |
| smg_mp5 | MP5 | smg | 0 |
| smg_vector | Vector | smg | 2 |
| smg_p90 | P90 | smg | 3 |
| smg_uzi | Uzi | smg | 4 |
| rifle_ak47 | AK-47 | rifle | 0 |
| rifle_m4a1 | M4A1 | rifle | 2 |
| rifle_scarh | SCAR-H | rifle | 3 |
| rifle_aug | AUG | rifle | 4 |
| sniper_m24 | M24 | sniper | 0 |
| sniper_ax50 | AX-50 | sniper | 2 |
| sniper_m82 | Barrett M82 | sniper | 3 |
| rocket_rpg7 | RPG-7 | rocket_launcher | 2 |
| rocket_m202 | M202 | rocket_launcher | 3 |
| rocket_javelin | Javelin | rocket_launcher | 4 |
| gadget_frag | Grenade frag | gadget (kind frag) | 0 |
| gadget_smoke | Grenade fumigène | gadget (kind smoke) | 2 |
| gadget_mine | Mine | gadget (kind mine) | 3 |
| gadget_c4 | C4 | gadget (kind c4) | 3 (Épique : fabricable à l'atelier ; les Légendaires restent uniquement en butin) |
| gadget_drone | Drone | gadget (kind drone) | 4 |
- `sprite_id` = `id` (un sprite tenu + une icône par arme : `assets/sprites/weapons/<id>.png/.json`, `assets/ui/weapons/<id>.png`).
  Gadgets : sprite tenu = l'objet en main (grenade, mine, pain de C4, télécommande/drone), + sprite au sol/en vol `assets/sprites/weapons/<id>_world.png`.
- Équipement (`slot = gadget`) : 1 emplacement en plus des 3 armes (`[arsenal] gadget_slots`). Champs : gadget_kind, charges, throw_range, fuse_time, effect_radius, effect_duration (+ explosion_radius/damage).
  `Profile.get_loadout_gadget()`, `Profile.raid_gadget`, `GameState.raid_gadget`. Perdu à la mort ; à l'extraction il revient s'il reste des charges (le joueur l'inclut dans get_carried_weapon_ids()).
- Joueur : `get_gadget() -> WeaponData`, `get_gadget_charges() -> int`, `use_gadget(dir: Vector2)`, signal `gadget_changed`. Entrée `gadget` (G ; mobile : bouton dédié du HUD). Comportements :
  frag = lancer en arc, explose après fuse_time ; smoke = nuage qui bloque la vue des ennemis et tourelles (groupe `smoke_clouds`, API statique `SmokeField.blocks_line(a, b) -> bool`) pendant effect_duration ;
  mine = posée au sol, s'arme après fuse_time, explose au passage d'un ennemi (effect_radius) ; c4 = posé, 2e appui = détonation à distance ; drone = allié volant qui suit le joueur et tire sur l'ennemi le plus proche pendant effect_duration.
- Raretés de la planche : Commun / Rare / Épique / Légendaire (index 0, 2, 3, 4 ; « Peu commun » n'est plus utilisé dans le catalogue).

### Personnages = la planche personnages_skins.jpg
Personnage de base : « Soldat standard » (Commun) : casque tactique noir avec casque audio, lunettes de protection, cagoule/col, gilet porte-plaques, genouillères, rangers, fusil tenu à deux mains ; chibi (grosse tête casquée).
Skins (`data/skins/char_<id>.tres`, rareté = bandeau de la planche) :
| id | Nom | Rareté | Prix |
|---|---|---|---|
| char_default | Soldat standard | 0 Commun | 0 |
| char_gign | GIGN | 2 Rare | 250 |
| char_fantome | Fantôme (cagoule tête de mort) | 2 Rare | 250 |
| char_sas | SAS | 3 Épique | 500 |
| char_desert | Desert | 3 Épique | 500 |
| char_forest | Forest (tenue ghillie) | 3 Épique | 500 |
| char_spetsnaz | Spetsnaz (armure de samouraï rouge, casque à cornes dorées) | 4 Légendaire | 1000 |
| char_cyber | Cyber (néon violet/cyan) | 4 Légendaire | 1000 |
| char_scorpion | Scorpion (noir et or) | 4 Légendaire | 1000 |
Les anciens skins (recrue, désert, nuit, néon, légende dorée) sont supprimés.

### Cartes = la planche cartes.png (agent Décor)
Far West : ville dispersée dans le désert, rochers, train à l'arrêt (obstacle), éolienne, château d'eau. Station : croix de modules + centre de contrôle circulaire, planète en fond, zones de gravité faible (`FloorLayout.low_gravity_cells`, inertie gérée par le joueur). Mall : bâtiment rectangulaire, atrium à fontaine, escalators, parking à l'entrée.


## Nom du jeu
Le jeu s'appelle désormais **RaidersGo** (anciennement « Exfil Rush », avant « Les Royaumes des Masques »). Les mentions « Exfil Rush » dans les commentaires désignent la même refonte.

## Refonte n°3 « méta-jeu, coop, station » (CONTRAT, 29/10)
Quatre agents en parallèle. Propriété des fichiers :
| Agent | Fichiers |
|---|---|
| Économie | `scripts/core/profile.gd` (or, déblocages, matériaux), `data/weapons/*`, `tools/gen_weapons.py`, `data/items/*`, `data/loot_tables/*`, `data/recipes/*` (nouveau), `scripts/economy/*` (nouveau : marchand, armurerie, artisanat, déblocages), `scripts/ui/menus/arsenal_screen.gd`, `weapon_tile.gd`, nouveaux écrans `scenes/ui/menus/{merchant,crafting}.tscn` + scripts, `scripts/ui/inventory_*.gd`, `tests/test_arsenal.gd`, `tests/test_economy.gd` |
| Pass & skins | `scripts/progression/*` (nouveau autoload `BattlePass`), `data/battle_pass/*`, `data/skins/*`, `scripts/cosmetics/*`, `assets/shaders/weapon_skin.gdshader`, `assets/sprites/weapons/skins/**`, `assets/ui/weapons/skins/**`, `art/blender/build_weapon_skins.py`, `scripts/ui/menus/{main_menu,shop_screen,lobby_*,hero_preview,loadout_summary,play_card,info_banner,nav_button,menu_kit}.gd`, `scenes/ui/menus/{main_menu,shop,battle_pass}.tscn`, `tests/test_menus.gd`, `tests/test_battle_pass.gd` |
| Coop | `scripts/net/*` (nouveau), `server/` (nouveau, serveur relais), `scenes/ui/menus/coop_lobby.tscn` + script, `tests/test_net*.gd` ; modifications CIBLÉES (relire avant chaque édition) de `scripts/dungeon/raid.gd`, `scripts/player/player.gd`, `scripts/enemies/enemy.gd`, `scripts/combat/*`, `scripts/loot/*` |
| Station spatiale | `scripts/biomes/space_station/*`, `tools/prerender/ss_*`, `tools/prerender/export_layout.gd` (ajouts), `assets/prerender/space_station/**`, `assets/sprites/space_station/**`, `art/blender/space_station/*`, `data/worlds/world_02_space_station.tres`, `data/maps/perm_station_kagami.tres`, `scripts/dungeon/prerender_backdrop.gd` (ajouts génériques), tests de la station |
- `data/balance.cfg` : chacun AJOUTE ses propres sections (`[economy]`, `[crafting]`, `[battle_pass]`, `[net]`, `[space_prerender]`), jamais de modification des sections des autres.
- `project.godot` : seul l'orchestrateur l'édite (nouveaux autoloads : demander dans le rapport).
- Points de branchement entre agents :
  - Marchand / Atelier : scènes `res://scenes/ui/menus/merchant.tscn` et `res://scenes/ui/menus/crafting.tscn` (agent Économie) ; l'agent Pass & skins ajoute leurs boutons dans la barre de navigation du lobby (icônes « Marchand », « Atelier », « Pass »), et le bouton « Coop » vers `res://scenes/ui/menus/coop_lobby.tscn`.
  - Kill d'un ennemi : `EventBus.enemy_died(enemy)` existe ; l'agent Économie l'écoute pour les déblocages (`enemy.data.kind`), l'agent Pass & skins pour l'XP de pass (via les stats de fin de raid).
  - XP de pass : `BattlePass.add_raid_xp(summary: Dictionary)` appelée par raid.gd en fin de raid (l'agent Pass & skins ajoute cet appel, une ligne, en relisant raid.gd juste avant).


## Travail à deux : branches et pull requests (à partir du 29/10)
- Plus aucun push direct sur `main`. Une branche par fonctionnalité ou correction (`feature/…`, `fix/…`, `chore/…`), créée depuis `main` à jour.
- Une pull request par branche, vers `main`, avec : description exacte de tout ce qui a changé, comment tester (éditeur, iPhone, APK), captures d'écran de chaque modification visible (hébergées sur la branche orpheline `pr-assets`), résultat des tests GUT.
- Fusion uniquement après validation de la PR par l'utilisateur.
- L'APK Android (workflow `Android APK`) se reconstruit à chaque fusion dans `main`.
