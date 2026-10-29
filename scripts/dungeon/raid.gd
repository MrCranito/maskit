class_name Raid
extends Node2D
## Scène de raid jouable (scène principale, phase 3) : assemble les modules du donjon.
##   Monde (WorldData)  → data/worlds/world_01_far_west.tres
##   Générateur         → DungeonGenerator.generate_run(seed, world, difficulty)
##   Décor              → WorldBuilder.build(layout, world)  (portes DoorNode, escaliers)
##   Brouillard         → FogOfWar
## Chaque module est chargé dynamiquement (ResourceLoader.exists + load) : s'il manque,
## un repli prend le relais pour que la scène tourne toujours :
##   pas de générateur  → FloorLayout.make_sample() (étage 0 seulement) ;
##   pas de WorldBuilder → FallbackBuilder (rectangles colorés, murs, portes simples) ;
##   pas de FogOfWar    → pas de brouillard.
## Étages : l'état de l'étage quitté (ennemis vivants, portes, tourelles détruites,
## exploration) est gardé dans un FloorState et restauré au retour.
## Fin du raid (boucle Exfil Rush) :
##   extraction = rester [extraction] channel_time s sur une case d'extraction (anneau de
##   progression, interrompue si on sort, ennemis proches alertés au début)
##   → Profile.finish_extraction(armes tenues, sac) → écran de fin → menu ;
##   mort (ou abandon depuis la pause) → Profile.finish_death() → écran de fin → menu.
## Tourelles : TurretPlacer (scripts/dungeon/turret_placer.gd), chargé par chemin.

const WORLD_PATH := "res://data/worlds/world_01_far_west.tres"
const GENERATOR_PATH := "res://scripts/dungeon/dungeon_generator.gd"
const WORLD_BUILDER_PATH := "res://scripts/dungeon/world_builder.gd"
const FOG_PATH := "res://scripts/dungeon/fog_of_war.gd"
const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const ENEMY_SCENE_PATH := "res://scenes/enemies/enemy.tscn"
const ENEMY_DATA_DIR := "res://data/enemies/"
const FALLBACK_ENEMY_KIND := &"masked_grunt"
const JOYSTICK_SCENE_PATH := "res://scenes/ui/virtual_joystick.tscn"
const DEBUG_OVERLAY_SCENE_PATH := "res://scenes/ui/debug_overlay.tscn"
const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")
const DEBUG_WORLD_DRAW_SCRIPT := preload("res://scripts/debug/debug_world_draw.gd")
const TURRET_PLACER_PATH := "res://scripts/dungeon/turret_placer.gd"

const GROUP_FOG_HIDEABLE := &"fog_hideable"
## Nom affiché si aucun WorldData n'est disponible (ville de la carte d'exemple).
const DEFAULT_WORLD_NAME := "Dust Creek"

const NIGHT_BLUE := Color(0.071, 0.102, 0.18, 0.92)  # ~#121a2e
const BORDER_LIGHT := Color(0.85, 0.88, 0.95, 0.85)
const TEXT_SECONDARY := Color(0.78, 0.80, 0.86)

## Couleurs debug des salles par type, et des portes par état.
const DEBUG_ROOM_COLORS := {
	&"spawn": Color(0.3, 0.9, 1.0),
	&"combat": Color(1.0, 0.35, 0.3),
	&"loot": Color(1.0, 0.85, 0.3),
	&"trap": Color(1.0, 0.5, 0.1),
	&"rest": Color(0.4, 1.0, 0.5),
	&"super_loot": Color(0.75, 0.4, 1.0),
	&"boss": Color(0.9, 0.1, 0.3),
	&"extraction": Color(0.3, 1.0, 0.6),
	&"corridor": Color(0.7, 0.7, 0.75),
}
const DEBUG_DOOR_OPEN := Color(0.3, 1.0, 0.4)
const DEBUG_DOOR_CLOSED := Color(1.0, 0.8, 0.2)
const DEBUG_DOOR_LOCKED := Color(1.0, 0.2, 0.2)

## Seed et difficulté du raid.
var run_seed: int = 0
## (Test B) Seed de la STRUCTURE de carte : une des cartes pré-rendues (Blender) tirée au
## sort, 0 = pas de pré-rendu (structure = run_seed). Ennemis et butin restent sur run_seed.
var map_seed: int = 0
var prerender: PrerenderBackdrop = null
var difficulty: int = 1
## WorldData chargé (null si le module Monde n'existe pas encore).
var world: Resource = null
## Index d'étage → FloorLayout.
var floors: Dictionary = {}
## Index d'étage → FloorState (étages déjà visités puis quittés).
var floor_states: Dictionary = {}
var current_floor: int = 0
var layout: FloorLayout = null

## Modules effectivement utilisés (debug / rapport).
var uses_generator: bool = false
var uses_world_builder: bool = false
var uses_fog: bool = false

var player: Node2D = null
var level: Node2D = null          ## Racine triée en Y (étage courant + joueur)
var floor_root: Node2D = null     ## Tout ce qui appartient à l'étage courant
var world_root: Node2D = null     ## Nœud renvoyé par WorldBuilder / FallbackBuilder
var nav_region: NavigationRegion2D = null
var enemies_container: Node2D = null
var fog: Node2D = null
var ui_layer: CanvasLayer = null
var hud: Control = null
var minimap: MiniMap = null
var debug_world_draw: Node2D = null

var _doors: Array[Node2D] = []
var _door_by_cell: Dictionary = {}
var _builder_script: Script = null
var _fog_script: Script = null
var _transitioning: bool = false
var _stairs_cooldown: float = 0.0
var _last_player_cell: Vector2i = Vector2i(-9999, -9999)
## Canalisation d'extraction en cours (s) ; -1 = pas de canalisation.
var _extraction_time: float = -1.0
## Raid terminé (extraction ou mort) : plus aucune fin ne peut se déclencher.
var _raid_over: bool = false
var _extraction_marker: Node2D = null
## Zones d'extraction de l'étage (ExtractionZone) et zone en cours de canalisation.
var extraction_zones: Array[ExtractionZone] = []
var _active_zone: ExtractionZone = null
var end_screen: RaidEndScreen = null
## Tourelles de l'étage courant (nœud → case) et cases des tourelles détruites.
var turrets_container: Node2D = null
var _turret_cells: Dictionary = {}
var _destroyed_turrets: Array[Vector2i] = []
var _turret_script: Script = null

var _banner_title: Label = null
var _banner_room: Label = null
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _fade_rect: ColorRect = null


func _ready() -> void:
	# Leurres d'un raid précédent : effacés (scripts/economy/noise_sources.gd).
	NoiseSources.clear()
	run_seed = GameState.run_seed
	difficulty = GameState.difficulty
	_load_world()
	_generate_floors()
	_apply_map_modifiers()
	_load_module_scripts()

	level = Node2D.new()
	level.name = "Level"
	level.y_sort_enabled = true
	add_child(level)

	_build_debug_world_draw()
	_build_floor(current_floor)
	_spawn_player(layout.player_spawn)
	_build_ui()
	_apply_map_player_modifiers()
	_update_banner(true)
	EventBus.player_died.connect(_on_player_died)
	EventBus.debug_toggled.connect(_on_debug_toggled)
	EventBus.raid_started.emit(run_seed)
	EventBus.floor_changed.emit(current_floor)
	NetHooks.attach_raid(self)  # Coop en ligne (scripts/net) : sans effet en solo.


# --- Chargement des modules ----------------------------------------------------

func _load_world() -> void:
	# Monde de la carte choisie (GameState.world_path), repli Far West.
	var path: String = GameState.world_path if GameState.world_path != "" else WORLD_PATH
	if ResourceLoader.exists(path):
		world = load(path) as Resource
	elif ResourceLoader.exists(WORLD_PATH):
		push_warning("Raid: monde introuvable (%s), repli Far West." % path)
		world = load(WORLD_PATH) as Resource
	if world == null:
		push_warning("Raid: monde introuvable (%s), valeurs par défaut." % WORLD_PATH)
	BiomeAssets.set_world(world)


## Chemin d'un module du monde (generator_path / builder_path), repli Far West.
func _world_module_path(key: StringName, fallback: String) -> String:
	var v: Variant = world.get(key) if world != null else null
	var p: String = String(v) if v != null else ""
	return p if p != "" and ResourceLoader.exists(p) else fallback


## Génère tous les étages du run, ou la carte d'exemple si le générateur manque.
func _generate_floors() -> void:
	floors.clear()
	var gen: Script = _load_script(_world_module_path(&"generator_path", GENERATOR_PATH))
	map_seed = 0
	# Cartes pré-rendues (Blender) : tirage d'un paquet du biome (assets/prerender/<biome>/<seed>/).
	if world != null and Balance.get_value("prerender", "enabled", true) and PrerenderBackdrop.has_packs(StringName(world.get("biome"))):
		map_seed = PrerenderBackdrop.pick_seed(run_seed, StringName(world.get("biome")))
	if gen != null and world != null:
		var result: Variant = _call_module(gen, &"generate_run", [map_seed if map_seed != 0 else run_seed, world, difficulty])
		if result is Array:
			for l: Variant in result:
				if l is FloorLayout:
					floors[(l as FloorLayout).floor_index] = l
		if not floors.has(0) and not floors.is_empty():
			push_warning("Raid: le générateur n'a pas produit d'étage 0.")
		uses_generator = not floors.is_empty()
		if map_seed != 0 and floors.has(0):
			shuffle_enemy_spawns(floors[0], hash([run_seed, "prerender_enemies"]))
	if floors.is_empty():
		if gen != null and world == null:
			push_warning("Raid: générateur présent mais pas de monde, carte d'exemple.")
		floors[0] = FloorLayout.make_sample()
	current_floor = 0 if floors.has(0) else int(floors.keys()[0])


func _load_module_scripts() -> void:
	_builder_script = _load_script(_world_module_path(&"builder_path", WORLD_BUILDER_PATH))
	_fog_script = _load_script(FOG_PATH)


## Appelle `method` sur le script (méthode statique) ou, à défaut, sur une instance.
static func _call_module(script: Script, method: StringName, args: Array) -> Variant:
	for m: Dictionary in script.get_script_method_list():
		if StringName(m.get("name", "")) == method:
			if int(m.get("flags", 0)) & METHOD_FLAG_STATIC:
				return script.callv(method, args)
			var inst: Object = script.new()
			var res: Variant = inst.callv(method, args)
			var returned_self: bool = res is Object and (res as Object) == inst
			if inst is Node and not returned_self and not (inst as Node).is_inside_tree():
				(inst as Node).queue_free()
			return res
	push_warning("Raid: méthode %s absente de %s." % [method, script.resource_path])
	return null


static func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as Script
	if s == null or not s.can_instantiate():
		return null
	return s


# --- Construction d'un étage ----------------------------------------------------

## Construit (ou restaure, si déjà visité) l'étage `index`. Ne place pas le joueur.
func _build_floor(index: int) -> void:
	current_floor = index
	layout = floors[index]
	var state: FloorState = floor_states.get(index) as FloorState
	if state != null:
		_apply_door_states_to_layout(state)

	floor_root = Node2D.new()
	floor_root.name = "Floor_%d" % index
	floor_root.y_sort_enabled = true
	level.add_child(floor_root)

	_build_world_root()
	_attach_prerender(index)
	_collect_doors()
	if state != null:
		_restore_door_nodes(state)
	_build_navigation()

	enemies_container = Node2D.new()
	enemies_container.name = "Enemies"
	enemies_container.y_sort_enabled = true
	enemies_container.z_index = 10
	floor_root.add_child(enemies_container)
	if state != null:
		_restore_enemies(state)
	else:
		_spawn_enemies()

	_spawn_turrets(state)

	LootSpawner.spawn_for_floor(layout, world_root, run_seed, difficulty)
	_build_extraction_marker()
	_build_fog(state)
	_apply_map_floor_modifiers()
	_last_player_cell = Vector2i(-9999, -9999)
	_cancel_extraction(false)


func _build_world_root() -> void:
	world_root = null
	uses_world_builder = false
	if _builder_script != null:
		var built: Variant = _call_module(_builder_script, &"build", [layout, world])
		if built is Node2D:
			world_root = built
			uses_world_builder = true
		else:
			push_warning("Raid: WorldBuilder.build n'a pas renvoyé de Node2D, constructeur de secours.")
	if world_root == null:
		world_root = FallbackBuilder.build(layout, world)
	world_root.name = "World"
	floor_root.add_child(world_root)
	if world_root.has_signal("stairs_entered"):
		world_root.connect("stairs_entered", _on_stairs_entered)
	else:
		push_warning("Raid: le constructeur de monde n'expose pas stairs_entered.")


## (Test B) Fond pré-rendu de l'étage 0 : remplace les visuels du WorldBuilder.
func _attach_prerender(index: int) -> void:
	prerender = null
	if map_seed == 0 or index != 0 or not uses_world_builder:
		return
	prerender = PrerenderBackdrop.create(map_seed, floors.get(0), StringName(world.get("biome")) if world != null else &"far_west")
	if prerender == null:
		return
	floor_root.add_child(prerender)
	floor_root.move_child(prerender, 0)
	prerender.attach_to(world_root)


## (Test B) Carte pré-rendue = structure fixe : chaque ennemi est redéplacé sur une case
## libre de sa salle (tirage sur run_seed) pour que deux parties sur la même carte diffèrent.
static func shuffle_enemy_spawns(l: FloorLayout, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var busy := {}
	for list: Array in [l.prop_spawns, l.container_spawns, l.hiding_spot_spawns]:
		for sp: FloorLayout.Spawn in list:
			for c: Vector2i in FloorLayout.spawn_cells(sp):
				busy[c] = true
	for sp2: FloorLayout.Spawn in l.enemy_spawns:
		var room := l.get_room(sp2.room_id) if sp2.room_id >= 0 else l.room_at(sp2.cell)
		if room == null or room.type == &"boss":
			continue
		for _i: int in 12:
			var c2 := Vector2i(rng.randi_range(room.rect.position.x, room.rect.end.x - 1),
				rng.randi_range(room.rect.position.y, room.rect.end.y - 1))
			var t := l.get_tile(c2)
			if busy.has(c2) or c2.distance_to(l.player_spawn) < 8.0 \
					or not (t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET):
				continue
			busy.erase(sp2.cell)
			sp2.cell = c2
			busy[c2] = true
			break


func _collect_doors() -> void:
	_doors.clear()
	_door_by_cell.clear()
	var list: Array = []
	if world_root.has_method("get_doors"):
		list = world_root.call("get_doors")
	else:
		list = world_root.find_children("*", "", true, false).filter(
			func(n: Node) -> bool: return n.is_in_group(&"doors"))
	for d: Variant in list:
		if not (d is Node2D):
			continue
		var door := d as Node2D
		var cell: Variant = door.get("cell")
		if not (cell is Vector2i):
			cell = FloorLayout.world_to_cell(door.global_position)
		_doors.append(door)
		_door_by_cell[cell] = door
		if door.has_signal("state_changed"):
			door.connect("state_changed", _on_door_state_changed)
		# DoorNode affiche son propre message ; le toast ne sert qu'aux portes de secours.
		if door.has_signal("locked_bumped") and not door.has_method("is_locked_message_visible"):
			door.connect("locked_bumped", func(_d: Node2D) -> void: show_toast("Clef requise"))


func get_doors() -> Array[Node2D]:
	return _doors


func get_door_at(cell: Vector2i) -> Node2D:
	return _door_by_cell.get(cell) as Node2D


## Requête du brouillard : la case porte est-elle ouverte ? (pas de porte = ouverte)
func is_door_cell_open(cell: Vector2i) -> bool:
	var door: Node2D = _door_by_cell.get(cell) as Node2D
	if door == null or not is_instance_valid(door):
		return true
	return _door_is_open(door)


static func _door_is_open(door: Node2D) -> bool:
	return bool(door.call("is_open")) if door.has_method("is_open") else true


static func _door_is_locked(door: Node2D) -> bool:
	return bool(door.call("is_locked")) if door.has_method("is_locked") else false


func _on_door_state_changed(_door: Variant = null) -> void:
	if fog != null and fog.has_method("invalidate"):
		fog.call("invalidate")
	if NetHooks.active:
		NetHooks.on_door_changed(_door)


## Navigation cuite depuis le layout : toute la carte praticable, cases VOID/WALL
## creusées (rectangles fusionnés). Les portes fermées restent navigables
## (les ennemis les ouvrent au contact).
func _build_navigation() -> void:
	var ts := float(FloorLayout.TILE_SIZE)
	var poly := NavigationPolygon.new()
	poly.agent_radius = Balance.get_float("raid", "nav_agent_radius", 20.0)
	var source := NavigationMeshSourceGeometryData2D.new()
	var full := Rect2(Vector2.ZERO, Vector2(layout.size) * ts)
	source.add_traversable_outline(_rect_outline(full))
	for r: Rect2i in FallbackBuilder.merge_cells(layout, FallbackBuilder.is_solid_tile):
		source.add_obstruction_outline(_rect_outline(FallbackBuilder.cell_rect_world(r)))
	# Couche « emprise rendue » du fond pré-calculé (rochers, wagons, fouillis…).
	if prerender != null:
		for r2: Rect2 in prerender.collision_rects():
			source.add_obstruction_outline(_rect_outline(r2))
	NavigationServer2D.bake_from_source_geometry_data(poly, source)
	nav_region = NavigationRegion2D.new()
	nav_region.name = "NavigationRegion2D"
	nav_region.navigation_polygon = poly
	floor_root.add_child(nav_region)


static func _rect_outline(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


func _build_fog(state: FloorState) -> void:
	fog = null
	uses_fog = false
	if _fog_script == null:
		return
	fog = _fog_script.new() as Node2D
	if fog == null:
		return
	fog.name = "FogOfWar"
	floor_root.add_child(fog)
	if fog.has_method("setup"):
		fog.call("setup", layout)
	if fog.has_method("set_door_query"):
		fog.call("set_door_query", is_door_cell_open)
	if state != null and not state.fog.is_empty() and fog.has_method("set_state"):
		fog.call("set_state", state.fog)
	# La révélation F3 est pilotée par FogOfWar ([fog] debug_reveal_with_f3) ; on ne
	# fait que resynchroniser un brouillard créé alors que le debug est déjà actif.
	if GameState.debug_enabled and bool(Balance.get_value("fog", "debug_reveal_with_f3", false)) and fog.has_method("reveal_all"):
		fog.call("reveal_all", true)
	uses_fog = true
	if is_instance_valid(player):
		fog.call("update_from", player.global_position)


# --- Ennemis --------------------------------------------------------------------

## EnemyData du kind demandé ; kind inconnu → masked_grunt + avertissement.
static func load_enemy_data(kind: StringName) -> Resource:
	var path := ENEMY_DATA_DIR + String(kind) + ".tres"
	if not ResourceLoader.exists(path):
		push_warning("Raid: ennemi « %s » inconnu, remplacé par %s." % [kind, FALLBACK_ENEMY_KIND])
		path = ENEMY_DATA_DIR + String(FALLBACK_ENEMY_KIND) + ".tres"
	return load(path) as Resource


func _spawn_enemies() -> void:
	for i: int in layout.enemy_spawns.size():
		var sp: FloorLayout.Spawn = layout.enemy_spawns[i]
		var en := _add_enemy(load_enemy_data(sp.kind), FloorLayout.cell_to_world(sp.cell), "%s_%d" % [String(sp.kind).to_pascal_case(), i])
		if en != null:
			en.set_meta(&"net_id", i)  # Identité réseau (coop) : index d'apparition, identique chez les deux joueurs.


func _add_enemy(data: Resource, pos: Vector2, enemy_name: String) -> Node2D:
	if not ResourceLoader.exists(ENEMY_SCENE_PATH) or data == null:
		return null
	var enemy := (load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as Node2D
	enemy.set("data", data)
	enemy.name = enemy_name
	enemy.position = pos
	enemy.add_to_group(GROUP_FOG_HIDEABLE)
	enemies_container.add_child(enemy)
	return enemy


func _restore_enemies(state: FloorState) -> void:
	for i: int in state.enemies.size():
		var e: Dictionary = state.enemies[i]
		var data: Resource = e["data"]
		var enemy := _add_enemy(data, e["position"], "%s_%d" % [str(data.get("kind")).to_pascal_case(), i])
		if enemy == null:
			continue
		enemy.set("spawn_position", e["spawn_position"])
		enemy.set("hp", float(e["hp"]))
		enemy.set_meta(&"net_id", int(e.get("net_id", i)))


## Ennemis vivants de l'étage courant.
func get_alive_enemies() -> Array[Node2D]:
	var out: Array[Node2D] = []
	if enemies_container == null:
		return out
	for n: Node in enemies_container.get_children():
		if n is Node2D and not n.is_queued_for_deletion() \
				and (not n.has_method("is_alive") or bool(n.call("is_alive"))):
			out.append(n as Node2D)
	return out


# --- Étages ---------------------------------------------------------------------

## Capture l'état de l'étage courant (ennemis vivants, portes, brouillard).
func capture_floor_state() -> FloorState:
	var s := FloorState.new()
	for e: Node2D in get_alive_enemies():
		s.enemies.append({
			"data": e.get("data"),
			"position": e.global_position,
			"spawn_position": e.get("spawn_position") if e.get("spawn_position") is Vector2 else e.global_position,
			"hp": float(e.get("hp")) if e.get("hp") != null else 1.0,
			"net_id": int(e.get_meta(&"net_id", -1)),
		})
	for cell: Vector2i in _door_by_cell:
		var d: Node2D = _door_by_cell[cell]
		if not is_instance_valid(d):
			continue
		var st := FloorLayout.DoorState.CLOSED
		if _door_is_open(d):
			st = FloorLayout.DoorState.OPEN
		elif _door_is_locked(d):
			st = FloorLayout.DoorState.LOCKED
		s.doors[cell] = st
	if fog != null and fog.has_method("get_state"):
		var fs: Variant = fog.call("get_state")
		if fs is PackedByteArray:
			s.fog = fs
	s.destroyed_turrets = get_destroyed_turret_cells()
	return s


func _apply_door_states_to_layout(state: FloorState) -> void:
	for d: FloorLayout.Door in layout.doors:
		if state.doors.has(d.cell):
			d.state = int(state.doors[d.cell])


func _restore_door_nodes(state: FloorState) -> void:
	for cell: Vector2i in state.doors:
		var door: Node2D = _door_by_cell.get(cell) as Node2D
		if door == null:
			continue
		var want := int(state.doors[cell])
		if want == FloorLayout.DoorState.OPEN and not _door_is_open(door) and door.has_method("open"):
			door.call("open")


## L'étage `index` existe-t-il dans ce run ?
func has_floor(index: int) -> bool:
	return floors.has(index)


## Change d'étage immédiatement (sans fondu). Sauvegarde l'étage courant, construit
## ou restaure la cible, place le joueur sur `arrival_cell` (décalé hors de l'escalier).
func go_to_floor(index: int, arrival_cell: Vector2i) -> bool:
	if not floors.has(index) or index == current_floor:
		return false
	floor_states[current_floor] = capture_floor_state()
	_free_current_floor()
	_build_floor(index)
	place_player(_arrival_offset(arrival_cell))
	_stairs_cooldown = Balance.get_float("raid", "stairs_cooldown", 0.8)
	if world_root != null and world_root.has_method("set_stairs_cooldown"):
		world_root.call("set_stairs_cooldown", _stairs_cooldown)
	_update_banner(true)
	EventBus.floor_changed.emit(current_floor)
	return true


func _free_current_floor() -> void:
	if floor_root != null and is_instance_valid(floor_root):
		level.remove_child(floor_root)
		floor_root.queue_free()
	floor_root = null
	world_root = null
	enemies_container = null
	turrets_container = null
	_turret_cells.clear()
	_extraction_marker = null
	nav_region = null
	fog = null
	_doors.clear()
	_door_by_cell.clear()


## Case libre voisine de l'escalier d'arrivée (pour ne pas re-déclencher l'escalier).
func _arrival_offset(cell: Vector2i) -> Vector2i:
	for dir: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
		var t := layout.get_tile(cell + dir)
		if t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET:
			return cell + dir
	return cell


func _on_stairs_entered(stairs: Variant) -> void:
	if _transitioning or _stairs_cooldown > 0.0 or stairs == null:
		return
	if NetHooks.active and NetHooks.intercept_stairs(stairs):
		return  # Coop : changement d'étage commun (compte à rebours).
	var target_floor := int(stairs.get("target_floor"))
	var target_cell: Vector2i = stairs.get("target_cell")
	if not floors.has(target_floor):
		_stairs_cooldown = Balance.get_float("raid", "stairs_cooldown", 0.8)
		show_toast("Étage non disponible")
		return
	_transitioning = true
	var half := Balance.get_float("raid", "fade_duration", 0.3)
	if is_instance_valid(player):
		player.set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, half)
	tw.tween_callback(func() -> void: go_to_floor(target_floor, target_cell))
	tw.tween_property(_fade_rect, "color:a", 0.0, half)
	tw.tween_callback(_end_transition)


func _end_transition() -> void:
	_transitioning = false
	if is_instance_valid(player):
		player.set_physics_process(true)


func is_transitioning() -> bool:
	return _transitioning


# --- Joueur ---------------------------------------------------------------------

func _spawn_player(cell: Vector2i) -> void:
	if ResourceLoader.exists(PLAYER_SCENE_PATH):
		var scene := load(PLAYER_SCENE_PATH) as PackedScene
		if scene != null:
			player = scene.instantiate() as Node2D
	if player == null:
		push_warning("Raid: joueur introuvable (%s), caméra fixe de secours." % PLAYER_SCENE_PATH)
		var cam := Camera2D.new()
		cam.name = "FallbackCamera"
		cam.position = FloorLayout.cell_to_world(cell)
		add_child(cam)
		cam.make_current()
		return
	player.name = "Player"
	player.z_index = 10
	player.position = FloorLayout.cell_to_world(cell)
	level.add_child(player)


## Téléporte le joueur au centre de `cell` (caméra recalée sans lissage).
func place_player(cell: Vector2i) -> void:
	if not is_instance_valid(player):
		return
	player.global_position = FloorLayout.cell_to_world(cell)
	if player is CharacterBody2D:
		(player as CharacterBody2D).velocity = Vector2.ZERO
	# Téléportation : pas d'interpolation physique entre l'ancienne et la nouvelle position.
	player.reset_physics_interpolation()
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam != null:
		cam.reset_smoothing()
	if fog != null:
		fog.call("update_from", player.global_position)


func get_player_cell() -> Vector2i:
	if not is_instance_valid(player):
		return Vector2i(-1, -1)
	return FloorLayout.world_to_cell(player.global_position)


func _on_player_died() -> void:
	if _raid_over:
		return
	_cancel_extraction(false)
	var delay := Balance.get_float("raid", "death_screen_delay", Balance.get_float("raid", "reload_delay", 2.0))
	get_tree().create_timer(delay).timeout.connect(_finish_death)


## Abandon volontaire (menu pause, confirmation déjà faite) = mort immédiate.
func abandon_raid() -> void:
	if _raid_over:
		return
	if NetHooks.active:
		NetHooks.note_abandon()
	_cancel_extraction(false)
	_finish_death()


## Mort : l'arsenal emporté et le butin sont perdus (Profile.finish_death), écran de fin.
func _finish_death() -> void:
	if _raid_over or not is_inside_tree():
		return
	_raid_over = true
	var bag: Inventory = GameState.raid_inventory
	var lost_items := 0
	var lost_value := 0
	if bag != null:
		for i in bag.capacity():
			var sl := bag.get_slot(i)
			if not sl.is_empty():
				lost_items += int(sl.get("count", 1))
		lost_value = bag.total_value()
	var summary: Dictionary = Profile.finish_death()
	summary["lost_items"] = lost_items
	summary["lost_value"] = lost_value
	_end_raid_state()
	_show_end_screen(false, summary)


## Extraction réussie : armes tenues + sac rejoignent la réserve, écran de fin.
func _finish_extraction() -> void:
	if _raid_over or not is_inside_tree():
		return
	_raid_over = true
	_cancel_extraction(false)
	var summary: Dictionary = Profile.finish_extraction(get_carried_weapon_ids(), GameState.raid_inventory)
	_end_raid_state()
	_show_end_screen(true, summary)


## Ids des armes tenues (API joueur, repli : arme courante).
func get_carried_weapon_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if not is_instance_valid(player):
		return out
	if player.has_method(&"get_carried_weapon_ids"):
		var v: Variant = player.call(&"get_carried_weapon_ids")
		if v is Array:
			for id: Variant in v:
				out.append(StringName(str(id)))
			return out
	for w: WeaponData in WeaponHud.read_weapons(player):
		if w != null:
			out.append(w.id)
	# Équipement : revient s'il reste des charges.
	if player.has_method(&"get_gadget"):
		var g := player.call(&"get_gadget") as WeaponData
		var n := int(player.call(&"get_gadget_charges")) if player.has_method(&"get_gadget_charges") else 1
		if g != null and n > 0:
			out.append(g.id)
	return out


## Le raid est soldé côté profil : sac vidé, armes de raid oubliées (un raid relancé
## directement repartira avec le pistolet de départ).
func _end_raid_state() -> void:
	if GameState.raid_inventory != null:
		GameState.raid_inventory.clear()
	GameState.raid_weapons.clear()
	GameState.set("raid_gadget", null)
	if is_instance_valid(player):
		player.set_physics_process(false)


func _show_end_screen(success: bool, summary: Dictionary) -> void:
	summary["pass_xp"] = BattlePassSystem.get_instance().add_raid_xp(summary.merged({"success": success}))
	if NetHooks.active and NetHooks.defer_end_screen(success, summary):
		return  # Coop : spectateur du coéquipier, écran de fin plus tard.
	end_screen = RaidEndScreen.create(success, summary)
	add_child(end_screen)


func is_raid_over() -> bool:
	return _raid_over


# --- Boucle ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_stairs_cooldown = maxf(_stairs_cooldown - delta, 0.0)
	if not is_instance_valid(player) or layout == null:
		return
	if fog != null and not _transitioning:
		fog.call("update_from", NetHooks.view_position(player.global_position) if NetHooks.active else player.global_position)
	var cell := get_player_cell()
	if cell != _last_player_cell:
		_last_player_cell = cell
		_update_banner(false)
	_update_extraction(cell, delta)


# --- Extraction -----------------------------------------------------------------

static func extraction_channel_time() -> float:
	return maxf(Balance.get_float("extraction", "channel_time", 5.0), 0.05)


func is_extracting() -> bool:
	return _extraction_time >= 0.0


## Progression de la canalisation (0..1), 0 si aucune.
func get_extraction_progress() -> float:
	return clampf(_extraction_time / extraction_channel_time(), 0.0, 1.0) if is_extracting() else 0.0


func _update_extraction(cell: Vector2i, delta: float) -> void:
	if _raid_over or _transitioning:
		return
	var alive := (not player.has_method("is_alive") or bool(player.call("is_alive"))) \
		and not (NetHooks.active and NetHooks.is_downed(player))
	var on_zone := alive and layout.extraction_cells.has(cell)
	if not on_zone:
		if is_extracting():
			_cancel_extraction(alive)
		return
	if not is_extracting():
		_start_extraction()
	_extraction_time += delta
	if _active_zone != null and is_instance_valid(_active_zone):
		_active_zone.set_progress(get_extraction_progress(), extraction_channel_time() - _extraction_time)
	if _extraction_time >= extraction_channel_time():
		_finish_extraction()


## Début de canalisation : anneau de progression centré sur la zone, ennemis proches alertés.
func _start_extraction() -> void:
	_extraction_time = 0.0
	_active_zone = get_extraction_zone_at(get_player_cell())
	if _active_zone != null:
		_active_zone.show_progress(true)
	var n := alert_enemies_near(player.global_position, Balance.get_float("extraction", "alert_radius", 520.0))
	show_toast("Extraction… reste dans la zone !" if n == 0 else "Extraction… ils arrivent !")


## Alerte les ennemis vivants dans `radius` autour de `pos` ; renvoie le nombre alerté.
func alert_enemies_near(pos: Vector2, radius: float) -> int:
	var n := 0
	var r2 := radius * radius
	for e: Node2D in get_alive_enemies():
		if e.global_position.distance_squared_to(pos) > r2:
			continue
		if e.has_method("become_aware"):
			e.call("become_aware", pos, false)
			n += 1
	return n


func _cancel_extraction(notify: bool) -> void:
	var was := is_extracting()
	_extraction_time = -1.0
	if _active_zone != null and is_instance_valid(_active_zone):
		_active_zone.show_progress(false)
	_active_zone = null
	if notify and was and not _raid_over:
		show_toast("Extraction interrompue")


## Marqueurs d'extraction (ExtractionZone : un par groupe de cases contiguës), dessinés une
## fois et animés par Tween.
func _build_extraction_marker() -> void:
	_extraction_marker = null
	extraction_zones.clear()
	_active_zone = null
	if layout == null or layout.extraction_cells.is_empty():
		return
	_remove_builder_extraction_markers()
	var m := Node2D.new()
	m.name = "ExtractionZones"
	m.z_index = 1
	floor_root.add_child(m)
	for z: ExtractionZone in ExtractionZone.create_all(layout.extraction_cells):
		m.add_child(z)
		extraction_zones.append(z)
	_extraction_marker = m


## Les constructeurs de décor posent leur propre lueur (ExtractionGlow, animée par _process) et
## une fusée (groupe extraction_markers) : remplacées par ExtractionZone.
func _remove_builder_extraction_markers() -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	var old: Array[Node] = world_root.find_children("*ExtractionGlow*", "", true, false)
	for n: Node in world_root.find_children("*", "", true, false):
		if n.is_in_group(&"extraction_markers") and not old.has(n):
			old.append(n)
	for n: Node in old:
		n.queue_free()


## Zone d'extraction contenant la case (null si aucune).
func get_extraction_zone_at(cell: Vector2i) -> ExtractionZone:
	for z: ExtractionZone in extraction_zones:
		if is_instance_valid(z) and z.has_cell(cell):
			return z
	return null


# --- Tourelles -------------------------------------------------------------------

## Place les tourelles de l'étage (TurretPlacer, chargé par chemin) puis retire celles
## détruites lors d'une visite précédente (FloorState.destroyed_turrets).
func _spawn_turrets(state: FloorState) -> void:
	_turret_cells.clear()
	_destroyed_turrets.clear()
	if state != null:
		_destroyed_turrets.assign(state.destroyed_turrets)
	if _turret_script == null:
		_turret_script = _load_script(TURRET_PLACER_PATH) if ResourceLoader.exists(TURRET_PLACER_PATH) else null
	if _turret_script == null:
		return
	turrets_container = Node2D.new()
	turrets_container.name = "Turrets"
	turrets_container.y_sort_enabled = true
	turrets_container.z_index = 10
	floor_root.add_child(turrets_container)
	var res: Variant = _call_module(_turret_script, &"spawn_for_floor",
		[self, layout, turrets_container, hash([run_seed, current_floor, "turrets"]), difficulty, current_floor])
	if not (res is Array):
		return
	for t: Variant in res:
		if not (t is Node2D) or not is_instance_valid(t):
			continue
		var node := t as Node2D
		var cell: Vector2i = node.get_meta(&"turret_cell", FloorLayout.world_to_cell(node.global_position))
		if _destroyed_turrets.has(cell):
			node.queue_free()
			continue
		_turret_cells[node] = cell
		node.add_to_group(GROUP_FOG_HIDEABLE)
		if node.has_signal(&"destroyed"):
			# Arguments du signal ignorés (unbind), seule la case compte.
			var cb := _on_turret_destroyed.bind(cell).unbind(_signal_arg_count(node, &"destroyed"))
			node.connect(&"destroyed", cb, CONNECT_ONE_SHOT)


static func _signal_arg_count(obj: Object, sig: StringName) -> int:
	for d: Dictionary in obj.get_signal_list():
		if StringName(d.get("name", "")) == sig:
			return (d.get("args", []) as Array).size()
	return 0


func _on_turret_destroyed(cell: Vector2i) -> void:
	if not _destroyed_turrets.has(cell):
		_destroyed_turrets.append(cell)


## Cases des tourelles détruites de l'étage courant (signal `destroyed` ou is_alive).
func get_destroyed_turret_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = _destroyed_turrets.duplicate()
	for node: Variant in _turret_cells:
		var cell: Vector2i = _turret_cells[node]
		var dead := not is_instance_valid(node) or (node as Node).is_queued_for_deletion() \
			or ((node as Node).has_method("is_alive") and not bool((node as Node).call("is_alive")))
		if dead and not out.has(cell):
			out.append(cell)
	return out


## Tourelles vivantes de l'étage courant.
func get_alive_turrets() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node: Variant in _turret_cells:
		if is_instance_valid(node) and not (node as Node).is_queued_for_deletion() \
				and (not (node as Node).has_method("is_alive") or bool((node as Node).call("is_alive"))):
			out.append(node as Node2D)
	return out


func _on_debug_toggled(_enabled: bool) -> void:
	# Contours de salles/portes redessinés par DebugWorldDraw ; brouillard autonome.
	pass


## Raccourcis de debug (F3 actif) : F5 = extraction instantanée, F6 = mort instantanée.
func _unhandled_input(event: InputEvent) -> void:
	if not GameState.debug_enabled or _raid_over:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_F5:
				get_viewport().set_input_as_handled()
				_finish_extraction()
			KEY_F6:
				get_viewport().set_input_as_handled()
				_finish_death()


# --- UI -------------------------------------------------------------------------

## Nom d'étage propre au monde (WorldData.floor_names), sinon nom générique.
func world_floor_name(index: int) -> String:
	var names: Variant = world.get("floor_names") if world != null else null
	if names is Dictionary:
		var d: Dictionary = names
		if d.has(index):
			return String(d[index])
		if d.has(str(index)):
			return String(d[str(index)])
	return floor_display_name(index)


static func floor_display_name(index: int) -> String:
	match index:
		0:
			return "Rez-de-chaussée"
		1:
			return "Étage"
		-1:
			return "Sous-sol"
	return ("Étage %d" % index) if index > 0 else ("Sous-sol %d" % -index)


func get_world_display_name() -> String:
	if world != null:
		var n: Variant = world.get("display_name")
		if n is String and not (n as String).is_empty():
			return n
	return DEFAULT_WORLD_NAME


func get_banner_text() -> String:
	var title: String = map_card.display_name if map_card != null else get_world_display_name()
	return "%s — %s" % [title, world_floor_name(current_floor)]


func get_current_room_name() -> String:
	if layout == null:
		return ""
	var r := layout.room_at(get_player_cell())
	return r.name if r != null else ""


func _update_banner(full: bool) -> void:
	if _banner_title == null:
		return
	if full:
		_banner_title.text = get_banner_text()
	var room := get_current_room_name()
	_banner_room.text = room
	_banner_room.visible = not room.is_empty()


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 10
	add_child(ui_layer)

	hud = HUD_SCRIPT.new() as Control
	ui_layer.add_child(hud)
	_build_banner()
	_build_toast()

	# Double joystick (paysage) : gauche = déplacement, droit = visée + tir.
	# Ajoutés AVANT les autres contrôles : ceux-ci (bouton action, sac…) reçoivent
	# les touches en premier, les sticks ne prennent que les touches non gérées.
	var sticks: Array[TouchJoystick] = TouchJoystick.create_pair(ui_layer)
	for j: TouchJoystick in sticks:
		ui_layer.move_child(j, 0)
	if sticks.is_empty():
		push_warning("Raid: joystick virtuel introuvable (%s)." % JOYSTICK_SCENE_PATH)
	if is_instance_valid(player) and player.has_method("refresh_joysticks"):
		player.call("refresh_joysticks")

	if ResourceLoader.exists(DEBUG_OVERLAY_SCENE_PATH):
		var overlay := (load(DEBUG_OVERLAY_SCENE_PATH) as PackedScene).instantiate()
		ui_layer.add_child(overlay)
		_layout_debug_overlay(overlay)
	else:
		push_warning("Raid: overlay debug introuvable (%s)." % DEBUG_OVERLAY_SCENE_PATH)

	_setup_loot_ui()
	PauseMenu.attach(ui_layer)
	var lh := ui_layer.get_node_or_null(^"InventoryHud")
	if lh != null and lh.has_method("align_pause_button"):
		lh.call_deferred("align_pause_button")

	# Fondu au noir (changement d'étage), au-dessus de tout.
	var fade_layer := CanvasLayer.new()
	fade_layer.name = "Fade"
	fade_layer.layer = 30
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(_fade_rect)


## Butin (phase 4) : bouton action, sac + écran d'inventaire, fenêtre de butin.
## Ajouté après les joysticks pour recevoir les touches avant eux.
func _setup_loot_ui() -> void:
	var loot_hud := InventoryHud.new()
	ui_layer.add_child(loot_hud)
	# Mini-carte (haut droite, sous le sac) : extractions, zones explorées ; tap = plein écran.
	# Insérée SOUS la couche de butin : fenêtre de fouille, fil des ramassages et inventaire
	# passent au-dessus ; la mini-carte s'efface pendant la fouille / l'inventaire.
	minimap = MiniMap.create(self)
	ui_layer.add_child(minimap)
	ui_layer.move_child(minimap, loot_hud.get_index())
	loot_hud.loot_window.visibility_changed_for_action.connect(func(open: bool) -> void:
		minimap.set_obscured(&"loot", open))
	loot_hud.inventory_screen.opened_changed.connect(func(open: bool) -> void:
		minimap.set_obscured(&"inventory", open))


static func _make_panel_style(radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = NIGHT_BLUE
	style.border_color = BORDER_LIGHT
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	return style


static func _make_label(size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var settings := LabelSettings.new()
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.8 if bold else 0.0
	settings.font = font
	settings.font_size = size
	settings.font_color = color
	l.label_settings = settings
	return l


## Overlay F3 (paysage) : sous la barre de vie, à gauche, police compacte.
func _layout_debug_overlay(overlay: Node) -> void:
	var top := Balance.get_float("hud", "debug_overlay_top", 96.0)
	var left := maxf(Balance.get_float("hud", "margin", 16.0), HudSafeArea.margins(ui_layer).x)
	var font_size := int(Balance.get_value("hud", "debug_overlay_font_size", 15))
	for c: Node in overlay.get_children():
		if c is PanelContainer:
			(c as PanelContainer).position = Vector2(left, top)
			for l: Node in c.get_children():
				if l is Label and (l as Label).label_settings != null:
					(l as Label).label_settings.font_size = font_size


## Bandeau monde + étage + salle actuelle, en haut au centre (paysage).
func _build_banner() -> void:
	var center := CenterContainer.new()
	center.name = "Banner"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	var top := maxf(Balance.get_float("hud", "banner_top", 12.0), HudSafeArea.margins(ui_layer).y)
	center.offset_left = -260
	center.offset_right = 260
	center.offset_top = top
	center.offset_bottom = top + 60
	ui_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _make_panel_style(14))
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)
	_banner_title = _make_label(20, Color.WHITE, true)
	vbox.add_child(_banner_title)
	_banner_room = _make_label(16, TEXT_SECONDARY, false)
	vbox.add_child(_banner_room)


## Message temporaire (étage non disponible, extraction, clef requise).
func _build_toast() -> void:
	var center := CenterContainer.new()
	center.name = "Toast"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.62
	center.anchor_bottom = 0.62
	center.offset_bottom = 70
	ui_layer.add_child(center)
	_toast_panel = PanelContainer.new()
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", _make_panel_style(14))
	_toast_panel.visible = false
	center.add_child(_toast_panel)
	_toast_label = _make_label(24, Color.WHITE, true)
	_toast_panel.add_child(_toast_label)


func show_toast(text: String) -> void:
	if _toast_panel == null:
		return
	_toast_label.text = text
	_toast_panel.visible = true
	_toast_panel.modulate.a = 1.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(Balance.get_float("raid", "toast_duration", 2.0))
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func() -> void: _toast_panel.visible = false)


func get_toast_text() -> String:
	return _toast_label.text if _toast_panel != null and _toast_panel.visible else ""


# --- Carte (MapCard) : modificateurs ---------------------------------------------
# GameState.current_map (fixée par la sélection de carte). Sans carte (raid lancé
# directement, debug) : aucun modificateur, comportement d'origine.

## Carte jouée (null = aucune).
var map_card: MapCard = null


## Au lancement, après la génération : bonus de butin (LootRoller) et densité d'ennemis
## (points d'apparition retirés ou dupliqués, de façon déterministe depuis la seed).
func _apply_map_modifiers() -> void:
	map_card = GameState.current_map as MapCard
	LootRoller.reset_map_bonus()
	if map_card == null:
		return
	LootRoller.map_rarity_bonus = map_card.get_mod_f("loot_rarity_bonus")
	LootRoller.map_quantity_mult = maxf(map_card.get_mod_f("loot_quantity_mult"), 0.0)
	var density: float = maxf(map_card.get_mod_f("enemy_density_mult"), 0.0)
	if is_equal_approx(density, 1.0):
		return
	for idx: Variant in floors:
		var l: FloorLayout = floors[idx]
		l.enemy_spawns = scale_enemy_spawns(l, density, hash([run_seed, int(idx), "density"]))


## Densité d'ennemis : < 1 retire des points d'apparition (jamais les boss), > 1 en
## ajoute sur une case libre voisine d'un point existant (même salle). Déterministe.
static func scale_enemy_spawns(l: FloorLayout, mult: float, seed_value: int) -> Array[FloorLayout.Spawn]:
	var src: Array[FloorLayout.Spawn] = l.enemy_spawns
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[FloorLayout.Spawn] = []
	if mult < 1.0:
		for sp: FloorLayout.Spawn in src:
			var room := l.get_room(sp.room_id) if sp.room_id >= 0 else l.room_at(sp.cell)
			if (room != null and room.type == &"boss") or rng.randf() < mult:
				out.append(sp)
		return out
	out.append_array(src)
	var extra: int = roundi(src.size() * (mult - 1.0))
	var used: Dictionary = {}
	for sp: FloorLayout.Spawn in src:
		used[sp.cell] = true
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
	var tries: int = 0
	while extra > 0 and not src.is_empty() and tries < extra * 12 + 24:
		tries += 1
		var base: FloorLayout.Spawn = src[rng.randi_range(0, src.size() - 1)]
		var c: Vector2i = base.cell + dirs[rng.randi_range(0, dirs.size() - 1)] * rng.randi_range(1, 2)
		var t: int = l.get_tile(c)
		if used.has(c) or c == l.player_spawn or not (t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET):
			continue
		var r := l.room_at(c)
		if r != null and base.room_id >= 0 and r.id != base.room_id:
			continue
		var sp := FloorLayout.Spawn.new()
		sp.cell = c
		sp.kind = base.kind
		sp.room_id = base.room_id
		out.append(sp)
		used[c] = true
		extra -= 1
	return out


## À chaque construction d'étage : stats des ennemis, rayon de vue du brouillard, nuit.
func _apply_map_floor_modifiers() -> void:
	if map_card == null:
		return
	if map_card.is_night() and floor_root != null:
		# Un seul CanvasModulate est actif par canevas : on assombrit celui du décor
		# (teinte d'ambiance du WorldBuilder) ou on en crée un.
		var tint: Variant = Balance.get_value("maps", "night_tint", Color(0.5, 0.55, 0.8))
		var night: Color = tint if tint is Color else Color(0.5, 0.55, 0.8)
		var mods: Array[Node] = floor_root.find_children("*", "CanvasModulate", true, false)
		if mods.is_empty():
			var cm := CanvasModulate.new()
			cm.name = "MapNight"
			floor_root.add_child(cm)
			mods.append(cm)
		for cm: Node in mods:
			(cm as CanvasModulate).color *= night
	if enemies_container != null:
		for e: Node in enemies_container.get_children():
			if e.has_method("apply_modifiers"):
				e.call("apply_modifiers", map_card.get_mod_f("enemy_hp_mult"), map_card.get_mod_f("enemy_damage_mult"),
					map_card.get_mod_f("enemy_speed_mult"), map_card.get_mod_f("awareness_mult"))
	var vr_mult: float = map_card.get_mod_f("view_radius_mult")
	if fog != null and not is_equal_approx(vr_mult, 1.0) and fog.get("view_radius") != null:
		var base_r: int = int(Balance.get_value("fog", "view_radius", 10))
		var min_r: int = int(Balance.get_value("maps", "min_view_radius", 3))
		fog.set("view_radius", maxi(min_r, roundi(base_r * vr_mult)))
		if fog.has_method("_apply_shader_params"):
			fog.call("_apply_shader_params")
		if fog.has_method("invalidate"):
			fog.call("invalidate")


## Après l'apparition du joueur et de l'UI : stats du joueur, teinte nuit, badge de
## difficulté dans le bandeau.
func _apply_map_player_modifiers() -> void:
	if map_card == null:
		return
	if is_instance_valid(player):
		var hp_m: float = maxf(map_card.get_mod_f("player_hp_mult"), 0.05)
		if not is_equal_approx(hp_m, 1.0) and player.get("max_hp") != null:
			player.set("max_hp", float(player.get("max_hp")) * hp_m)
			player.set("hp", float(player.get("max_hp")))
			if hud != null and hud.has_method("set_health"):
				hud.call("set_health", float(player.get("hp")), float(player.get("max_hp")))
		var dmg_m: float = maxf(map_card.get_mod_f("player_damage_mult"), 0.0)
		if not is_equal_approx(dmg_m, 1.0):
			apply_weapon_damage_mult(player, dmg_m)
	if _banner_title != null:
		var vbox := _banner_title.get_parent()
		var row := HBoxContainer.new()
		row.name = "MapTitleRow"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row)
		vbox.move_child(row, 0)
		_banner_title.reparent(row)
		var badge := MapTile.difficulty_badge(map_card.difficulty, true)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
		var center := vbox.get_parent().get_parent() as Control
		if center != null:
			center.offset_left = -330
			center.offset_right = 330


## Multiplie les dégâts de toutes les armes tenues (copies dupliquées : les .tres du
## catalogue ne sont jamais modifiés). API joueur get/set_weapons, repli : player.weapon.
static func apply_weapon_damage_mult(p: Node, mult: float) -> void:
	if p.has_method(&"get_weapons") and p.has_method(&"set_weapons"):
		var list: Array[WeaponData] = []
		for w: WeaponData in WeaponHud.read_weapons(p):
			if w == null:
				list.append(null)
				continue
			var nw := w.duplicate() as WeaponData
			nw.damage *= mult
			nw.explosion_damage *= mult
			list.append(nw)
		p.call(&"set_weapons", list)
		return
	var cur: Variant = p.get("weapon")
	if cur is WeaponData:
		var nw2 := (cur as WeaponData).duplicate() as WeaponData
		nw2.damage *= mult
		nw2.explosion_damage *= mult
		p.set("weapon", nw2)


# --- Debug F3 -------------------------------------------------------------------

func _build_debug_world_draw() -> void:
	debug_world_draw = DEBUG_WORLD_DRAW_SCRIPT.new() as Node2D
	debug_world_draw.name = "DebugWorldDraw"
	add_child(debug_world_draw)
	debug_world_draw.call("register_drawer", _draw_debug_rooms)
	debug_world_draw.call("register_drawer", _draw_debug_doors)
	debug_world_draw.call("register_drawer", _draw_debug_footprint)
	debug_world_draw.call("register_drawer", _draw_debug_info)


## Contour des salles + nom et type.
func _draw_debug_rooms(canvas: Node2D) -> void:
	if layout == null:
		return
	var font := ThemeDB.fallback_font
	for r: FloorLayout.Room in layout.rooms:
		var col: Color = DEBUG_ROOM_COLORS.get(r.type, Color.WHITE)
		var wr := FallbackBuilder.cell_rect_world(r.rect)
		canvas.draw_rect(wr.grow(-3.0), Color(col, 0.8), false, 3.0)
		var label := "%s [%s]" % [r.name, String(r.type)]
		var at := wr.position + Vector2(10, 26)
		canvas.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0.07, 0.1, 0.18))
		canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
	for st: FloorLayout.Stairs in layout.stairs:
		var p := FloorLayout.cell_to_world(st.cell)
		var txt := "→ %s%s" % [world_floor_name(st.target_floor), "" if floors.has(st.target_floor) else " (absent)"]
		canvas.draw_string_outline(font, p + Vector2(-40, -36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0.07, 0.1, 0.18))
		canvas.draw_string(font, p + Vector2(-40, -36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.9, 1.0))


## Couche « emprise rendue » du fond pré-calculé (orange).
func _draw_debug_footprint(canvas: Node2D) -> void:
	if prerender != null and is_instance_valid(prerender):
		for r2: Rect2 in prerender.collision_rects():
			canvas.draw_rect(r2, Color(1.0, 0.55, 0.0, 0.35))


## Portes : vert ouverte, jaune fermée, rouge verrouillée.
func _draw_debug_doors(canvas: Node2D) -> void:
	var ts := float(FloorLayout.TILE_SIZE)
	for cell: Vector2i in _door_by_cell:
		var d: Node2D = _door_by_cell[cell]
		if not is_instance_valid(d):
			continue
		var col := DEBUG_DOOR_OPEN if _door_is_open(d) else (DEBUG_DOOR_LOCKED if _door_is_locked(d) else DEBUG_DOOR_CLOSED)
		var r := Rect2(Vector2(cell) * ts, Vector2(ts, ts))
		canvas.draw_rect(r, Color(col, 0.25))
		canvas.draw_rect(r.grow(-2.0), col, false, 3.0)


func _debug_weapons_text() -> String:
	var parts := PackedStringArray()
	var cur := int(player.get("current_slot")) if player.get("current_slot") is int else 0
	var ws := WeaponHud.read_weapons(player)
	for i in ws.size():
		var w: WeaponData = ws[i]
		if w == null:
			parts.append("[vide]")
			continue
		var ammo := ""
		if i == cur and player.has_method("get_ammo"):
			ammo = " %d/%d" % [int(player.call("get_ammo")), w.magazine_size]
		parts.append(("> " if i == cur else "") + String(w.id) + ammo)
	return ", ".join(parts) if not parts.is_empty() else "aucune"


## Encart près du joueur : seed, étage, modules branchés, armes, extraction.
func _draw_debug_info(canvas: Node2D) -> void:
	if not is_instance_valid(player):
		return
	var lines := PackedStringArray([
		"Seed %d · carte %s · difficulté %d · étage %d" % [run_seed, (str(map_seed) + " (pré-rendue)") if map_seed != 0 else "générée", difficulty, current_floor],
		"Générateur:%s Décor:%s Brouillard:%s" % [
			"oui" if uses_generator else "exemple",
			"WorldBuilder" if uses_world_builder else "secours",
			"oui" if uses_fog else "non"],
		"Ennemis vivants : %d · tourelles : %d (détruites %d)" % [get_alive_enemies().size(),
			get_alive_turrets().size(), get_destroyed_turret_cells().size()],
		"Armes : %s" % _debug_weapons_text(),
		"Extraction : %s (%.1f s) · F5 extraire · F6 mourir" % [
			("%.1f / %.1f s" % [_extraction_time, extraction_channel_time()]) if is_extracting() else "—",
			extraction_channel_time()],
	])
	var font := ThemeDB.fallback_font
	var origin := player.global_position + Vector2(-150, -150)
	for i: int in lines.size():
		var at := origin + Vector2(0, 20.0 * i)
		canvas.draw_string_outline(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0.07, 0.1, 0.18))
		canvas.draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
