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
## Étages : l'état de l'étage quitté (ennemis vivants, portes, exploration) est gardé
## dans un FloorState et restauré au retour. Mort du joueur → rechargement, même seed.

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
var debug_world_draw: Node2D = null

var _doors: Array[Node2D] = []
var _door_by_cell: Dictionary = {}
var _builder_script: Script = null
var _fog_script: Script = null
var _transitioning: bool = false
var _stairs_cooldown: float = 0.0
var _last_player_cell: Vector2i = Vector2i(-9999, -9999)
var _extraction_time: float = 0.0
var _extraction_shown: bool = false

var _banner_title: Label = null
var _banner_room: Label = null
var _toast_panel: PanelContainer = null
var _toast_label: Label = null
var _toast_tween: Tween = null
var _fade_rect: ColorRect = null


func _ready() -> void:
	run_seed = GameState.run_seed
	difficulty = int(Balance.get_value("raid", "default_difficulty", 1))
	_load_world()
	_generate_floors()
	_load_module_scripts()

	level = Node2D.new()
	level.name = "Level"
	level.y_sort_enabled = true
	add_child(level)

	_build_debug_world_draw()
	_build_floor(current_floor)
	_spawn_player(layout.player_spawn)
	_build_ui()
	_update_banner(true)
	EventBus.player_died.connect(_on_player_died)
	EventBus.debug_toggled.connect(_on_debug_toggled)
	EventBus.raid_started.emit(run_seed)
	EventBus.floor_changed.emit(current_floor)


# --- Chargement des modules ----------------------------------------------------

func _load_world() -> void:
	if ResourceLoader.exists(WORLD_PATH):
		world = load(WORLD_PATH) as Resource
	if world == null:
		push_warning("Raid: monde introuvable (%s), valeurs par défaut." % WORLD_PATH)


## Génère tous les étages du run, ou la carte d'exemple si le générateur manque.
func _generate_floors() -> void:
	floors.clear()
	var gen: Script = _load_script(GENERATOR_PATH)
	if gen != null and world != null:
		var result: Variant = _call_module(gen, &"generate_run", [run_seed, world, difficulty])
		if result is Array:
			for l: Variant in result:
				if l is FloorLayout:
					floors[(l as FloorLayout).floor_index] = l
		if not floors.has(0) and not floors.is_empty():
			push_warning("Raid: le générateur n'a pas produit d'étage 0.")
		uses_generator = not floors.is_empty()
	if floors.is_empty():
		if gen != null and world == null:
			push_warning("Raid: générateur présent mais pas de monde, carte d'exemple.")
		floors[0] = FloorLayout.make_sample()
	current_floor = 0 if floors.has(0) else int(floors.keys()[0])


func _load_module_scripts() -> void:
	_builder_script = _load_script(WORLD_BUILDER_PATH)
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

	_build_fog(state)
	_last_player_cell = Vector2i(-9999, -9999)
	_extraction_time = 0.0
	_extraction_shown = false


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
		_add_enemy(load_enemy_data(sp.kind), FloorLayout.cell_to_world(sp.cell), "%s_%d" % [String(sp.kind).to_pascal_case(), i])


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
	var delay := Balance.get_float("raid", "reload_delay", 2.0)
	get_tree().create_timer(delay).timeout.connect(_reload_raid)


## Recharge le raid (même seed : GameState.run_seed n'est pas modifié).
func _reload_raid() -> void:
	if is_inside_tree() and get_tree().current_scene == self:
		get_tree().reload_current_scene()


# --- Boucle ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_stairs_cooldown = maxf(_stairs_cooldown - delta, 0.0)
	if not is_instance_valid(player) or layout == null:
		return
	if fog != null and not _transitioning:
		fog.call("update_from", player.global_position)
	var cell := get_player_cell()
	if cell != _last_player_cell:
		_last_player_cell = cell
		_update_banner(false)
	_update_extraction(cell, delta)


func _update_extraction(cell: Vector2i, delta: float) -> void:
	if layout.extraction_cells.has(cell):
		_extraction_time += delta
		if not _extraction_shown and _extraction_time >= Balance.get_float("raid", "extraction_hint_delay", 0.5):
			_extraction_shown = true
			show_toast("Point d'extraction — disponible en phase 6")
	else:
		_extraction_time = 0.0
		_extraction_shown = false


func _on_debug_toggled(_enabled: bool) -> void:
	# Contours de salles/portes redessinés par DebugWorldDraw ; brouillard autonome.
	pass


# --- UI -------------------------------------------------------------------------

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
	return "%s — %s" % [get_world_display_name(), floor_display_name(current_floor)]


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
	var left := Balance.get_float("hud", "margin", 16.0)
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
	var top := Balance.get_float("hud", "banner_top", 12.0)
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


# --- Debug F3 -------------------------------------------------------------------

func _build_debug_world_draw() -> void:
	debug_world_draw = DEBUG_WORLD_DRAW_SCRIPT.new() as Node2D
	debug_world_draw.name = "DebugWorldDraw"
	add_child(debug_world_draw)
	debug_world_draw.call("register_drawer", _draw_debug_rooms)
	debug_world_draw.call("register_drawer", _draw_debug_doors)
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
		var txt := "→ %s%s" % [floor_display_name(st.target_floor), "" if floors.has(st.target_floor) else " (absent)"]
		canvas.draw_string_outline(font, p + Vector2(-40, -36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0.07, 0.1, 0.18))
		canvas.draw_string(font, p + Vector2(-40, -36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.6, 0.9, 1.0))


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


## Encart près du joueur : seed, étage, modules branchés.
func _draw_debug_info(canvas: Node2D) -> void:
	if not is_instance_valid(player):
		return
	var lines := PackedStringArray([
		"Seed %d · difficulté %d · étage %d" % [run_seed, difficulty, current_floor],
		"Générateur:%s Décor:%s Brouillard:%s" % [
			"oui" if uses_generator else "exemple",
			"WorldBuilder" if uses_world_builder else "secours",
			"oui" if uses_fog else "non"],
		"Ennemis vivants : %d" % get_alive_enemies().size(),
	])
	var font := ThemeDB.fallback_font
	var origin := player.global_position + Vector2(-150, -110)
	for i: int in lines.size():
		var at := origin + Vector2(0, 20.0 * i)
		canvas.draw_string_outline(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0.07, 0.1, 0.18))
		canvas.draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
