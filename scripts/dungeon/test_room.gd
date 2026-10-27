class_name TestRoom
extends Node2D
## Salle de test jouable (scène principale de la phase 1).
## Tout est construit en code : sol, murs, piliers, joueur, cibles, UI, debug.
## Les scènes du joueur et du joystick sont chargées de façon tolérante :
## si elles n'existent pas encore, on avertit et la salle tourne quand même.

const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const JOYSTICK_SCENE_PATH := "res://scenes/ui/virtual_joystick.tscn"
const DUMMY_SCENE_PATH := "res://scenes/enemies/target_dummy.tscn"
const DEBUG_OVERLAY_SCENE_PATH := "res://scenes/ui/debug_overlay.tscn"
const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")
const DEBUG_WORLD_DRAW_SCRIPT := preload("res://scripts/debug/debug_world_draw.gd")

const LAYER_WORLD := 1

# Disposition (level design, pas de l'équilibrage) en fractions de la salle,
# pour rester valable si la taille change dans balance.cfg.
## Piliers : centre (fraction) et taille (px).
const PILLARS: Array[Dictionary] = [
	{"at": Vector2(0.5, 0.52), "size": Vector2(170, 170)},
	{"at": Vector2(0.24, 0.70), "size": Vector2(130, 130)},
	{"at": Vector2(0.76, 0.30), "size": Vector2(130, 130)},
]
## Cibles : position (fraction) et apparence (0 = mannequin de pierre, 1 = golem).
## La première est cachée derrière le pilier central vu depuis le point d'apparition.
const DUMMIES: Array[Dictionary] = [
	{"at": Vector2(0.5, 0.40), "variant": 1},
	{"at": Vector2(0.25, 0.42), "variant": 0},
	# Visible et à portée dès l'apparition : valide le tir auto sans bouger.
	{"at": Vector2(0.70, 0.68), "variant": 0},
]
const PLAYER_SPAWN := Vector2(0.5, 0.85)

var room_size: Vector2 = Vector2(1400, 2000)
var wall_thickness: float = 64.0
var tile_size: float = 80.0

var player: Node2D = null
var dummies: Array[Node2D] = []
var ui_layer: CanvasLayer = null
var debug_world_draw: Node2D = null
var hud: Control = null

var _pillar_rects: Array[Rect2] = []


func _ready() -> void:
	room_size = Vector2(
		Balance.get_float("test_room", "width", 1400.0),
		Balance.get_float("test_room", "height", 2000.0))
	wall_thickness = Balance.get_float("test_room", "wall_thickness", 64.0)
	tile_size = Balance.get_float("test_room", "tile_size", 80.0)

	_build_floor()
	_build_walls()
	_build_pillars()
	_spawn_dummies()
	_spawn_player()
	_build_debug_world_draw()
	_build_ui()


# --- Construction du monde ---------------------------------------------------

func _build_floor() -> void:
	var floor_node := RoomFloor.new()
	floor_node.name = "Floor"
	floor_node.room_size = room_size
	floor_node.tile_size = tile_size
	floor_node.wall_thickness = wall_thickness
	floor_node.z_index = -10
	add_child(floor_node)


func _build_walls() -> void:
	var t := wall_thickness
	var w := room_size.x
	var h := room_size.y
	var walls := Node2D.new()
	walls.name = "Walls"
	add_child(walls)
	# Murs extérieurs : haut, bas, gauche, droite (débordent dans les coins).
	var rects: Array[Rect2] = [
		Rect2(-t, -t, w + 2.0 * t, t),
		Rect2(-t, h, w + 2.0 * t, t),
		Rect2(-t, 0, t, h),
		Rect2(w, 0, t, h),
	]
	for r: Rect2 in rects:
		walls.add_child(_make_wall_body(r, false))


func _build_pillars() -> void:
	var pillars := Node2D.new()
	pillars.name = "Pillars"
	add_child(pillars)
	for data: Dictionary in PILLARS:
		var size: Vector2 = data["size"]
		var center: Vector2 = (data["at"] as Vector2) * room_size
		var r := Rect2(center - size / 2.0, size)
		_pillar_rects.append(r)
		pillars.add_child(_make_wall_body(r, true))


func _make_wall_body(r: Rect2, is_pillar: bool) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = r.get_center()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.add_child(cs)
	var visual := WallVisual.new()
	visual.size = r.size
	visual.is_pillar = is_pillar
	body.add_child(visual)
	return body


func _spawn_dummies() -> void:
	if not ResourceLoader.exists(DUMMY_SCENE_PATH):
		push_warning("TestRoom: %s introuvable, pas de cibles." % DUMMY_SCENE_PATH)
		return
	var scene := load(DUMMY_SCENE_PATH) as PackedScene
	var container := Node2D.new()
	container.name = "Enemies"
	container.y_sort_enabled = true
	add_child(container)
	for i: int in DUMMIES.size():
		var data: Dictionary = DUMMIES[i]
		var dummy := scene.instantiate() as Node2D
		dummy.name = "TargetDummy%d" % (i + 1)
		dummy.position = (data["at"] as Vector2) * room_size
		if "variant" in dummy:
			dummy.set("variant", int(data["variant"]))
		container.add_child(dummy)
		dummies.append(dummy)


func _spawn_player() -> void:
	var spawn_pos := PLAYER_SPAWN * room_size
	if ResourceLoader.exists(PLAYER_SCENE_PATH):
		var scene := load(PLAYER_SCENE_PATH) as PackedScene
		if scene != null:
			player = scene.instantiate() as Node2D
	if player == null:
		push_warning("TestRoom: joueur introuvable (%s), caméra fixe de secours." % PLAYER_SCENE_PATH)
		var cam := Camera2D.new()
		cam.name = "FallbackCamera"
		cam.position = spawn_pos
		add_child(cam)
		cam.make_current()
		return
	player.name = "Player"
	player.position = spawn_pos
	add_child(player)


func _build_debug_world_draw() -> void:
	debug_world_draw = DEBUG_WORLD_DRAW_SCRIPT.new() as Node2D
	debug_world_draw.name = "DebugWorldDraw"
	add_child(debug_world_draw)
	# Exemple d'extension : contour des obstacles bloquant la ligne de vue.
	debug_world_draw.call("register_drawer", _draw_debug_obstacles)


func _draw_debug_obstacles(canvas: Node2D) -> void:
	for r: Rect2 in _pillar_rects:
		canvas.draw_rect(r, Color(0.4, 0.7, 1.0, 0.9), false, 2.0)


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	ui_layer.layer = 10
	add_child(ui_layer)

	hud = HUD_SCRIPT.new() as Control
	ui_layer.add_child(hud)

	if ResourceLoader.exists(JOYSTICK_SCENE_PATH):
		var js_scene := load(JOYSTICK_SCENE_PATH) as PackedScene
		if js_scene != null:
			var joystick := js_scene.instantiate()
			joystick.name = "VirtualJoystick"
			ui_layer.add_child(joystick)
	else:
		push_warning("TestRoom: joystick virtuel introuvable (%s)." % JOYSTICK_SCENE_PATH)

	if ResourceLoader.exists(DEBUG_OVERLAY_SCENE_PATH):
		var overlay := (load(DEBUG_OVERLAY_SCENE_PATH) as PackedScene).instantiate()
		ui_layer.add_child(overlay)
	else:
		push_warning("TestRoom: overlay debug introuvable (%s)." % DEBUG_OVERLAY_SCENE_PATH)


# --- Visuels placeholder -----------------------------------------------------
# Palette : cour de château en pierre ocre, lumière chaude de coucher de soleil,
# ombres bleu nuit, bannières rouges à emblème blanc.

const SHADOW_NIGHT := Color(0.07, 0.10, 0.22)
const STONE_OUTLINE := Color(0.11, 0.09, 0.14)
const BANNER_RED := Color(0.76, 0.10, 0.11)
const EMBLEM_WHITE := Color(0.97, 0.95, 0.92)


## Bannière rouge à emblème blanc (masque stylisé), suspendue depuis `top`.
static func draw_banner(canvas: CanvasItem, top: Vector2, width: float, height: float) -> void:
	var hw := width / 2.0
	var pts := PackedVector2Array([
		top + Vector2(-hw, 0), top + Vector2(hw, 0), top + Vector2(hw, height),
		top + Vector2(0, height - width * 0.4), top + Vector2(-hw, height)])
	# Ombre portée bleu nuit, décalée vers le bas-droite (soleil couchant en haut-gauche).
	var shadow := PackedVector2Array()
	for p: Vector2 in pts:
		shadow.append(p + Vector2(6, 8))
	canvas.draw_colored_polygon(shadow, Color(SHADOW_NIGHT, 0.45))
	canvas.draw_colored_polygon(pts, BANNER_RED)
	canvas.draw_line(top + Vector2(-hw + 4, 4), top + Vector2(-hw + 4, height - 6), BANNER_RED.lightened(0.25), 3.0)
	var closed := pts.duplicate()
	closed.append(pts[0])
	canvas.draw_polyline(closed, STONE_OUTLINE, 2.5, true)
	# Emblème : masque blanc avec deux fentes.
	var c := top + Vector2(0, height * 0.42)
	var r := width * 0.24
	canvas.draw_set_transform(c, 0.0, Vector2(0.8, 1.0))
	canvas.draw_circle(Vector2.ZERO, r, EMBLEM_WHITE)
	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_line(c + Vector2(-r * 0.45, -r * 0.3), c + Vector2(-r * 0.2, r * 0.1), BANNER_RED, 2.5)
	canvas.draw_line(c + Vector2(r * 0.45, -r * 0.3), c + Vector2(r * 0.2, r * 0.1), BANNER_RED, 2.5)
	# Hampe.
	canvas.draw_line(top + Vector2(-hw - 6, 0), top + Vector2(hw + 6, 0), STONE_OUTLINE, 5.0)


## Sol de dalles de pierre ocre, dessiné une seule fois (variations déterministes).
class RoomFloor extends Node2D:
	var room_size: Vector2 = Vector2.ZERO
	var tile_size: float = 80.0
	var wall_thickness: float = 64.0

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1337  # Motif fixe : purement décoratif.
		var base := Color(0.80, 0.62, 0.40)
		var grout := Color(0.40, 0.29, 0.25)
		draw_rect(Rect2(Vector2.ZERO, room_size), grout)
		var cols := ceili(room_size.x / tile_size)
		var rows := ceili(room_size.y / tile_size)
		for y: int in rows:
			# Rangées décalées d'une demi-dalle, comme un appareil de pierres.
			var offset := (tile_size * 0.5) if y % 2 == 1 else 0.0
			for x: int in range(-1, cols + 1):
				var r := Rect2(x * tile_size + offset, y * tile_size, tile_size, tile_size)
				r = r.intersection(Rect2(Vector2.ZERO, room_size))
				if r.size.x <= 2.0 or r.size.y <= 2.0:
					continue
				var v := rng.randf_range(-0.06, 0.06)
				var c := Color(base.r + v + rng.randf_range(0.0, 0.04), base.g + v, base.b + v - rng.randf_range(0.0, 0.03))
				if rng.randf() < 0.07:
					c = c.lerp(Color(0.92, 0.70, 0.55), 0.35)  # Dalle rosée par le couchant.
				r = r.grow(-2.0)
				draw_rect(r, c)
				# Arête éclairée (haut-gauche), arête dans l'ombre bleutée (bas-droite).
				draw_line(r.position, Vector2(r.end.x, r.position.y), c.lightened(0.18), 2.0)
				draw_line(r.position, Vector2(r.position.x, r.end.y), c.lightened(0.10), 2.0)
				draw_line(Vector2(r.position.x, r.end.y), r.end, c.lerp(SHADOW_NIGHT, 0.35), 2.0)
				draw_line(Vector2(r.end.x, r.position.y), r.end, c.lerp(SHADOW_NIGHT, 0.25), 2.0)
				if rng.randf() < 0.08:
					var p := r.position + Vector2(rng.randf_range(10, r.size.x - 10), rng.randf_range(10, r.size.y - 10))
					draw_polyline(PackedVector2Array([p, p + Vector2(8, 6), p + Vector2(4, 16)]), c.lerp(SHADOW_NIGHT, 0.45), 1.5)
		# Allée centrale de grandes dalles claires.
		var path := Rect2(room_size.x * 0.5 - 80.0, room_size.y * 0.06, 160.0, room_size.y * 0.88)
		draw_rect(path, Color(0.95, 0.80, 0.58, 0.35))
		draw_rect(path, Color(0.55, 0.40, 0.33, 0.6), false, 3.0)
		# Ombres bleu nuit projetées par les murs (soleil couchant en haut-gauche).
		draw_rect(Rect2(0, 0, room_size.x, 70.0), Color(SHADOW_NIGHT, 0.35))
		draw_rect(Rect2(0, 0, 50.0, room_size.y), Color(SHADOW_NIGHT, 0.28))
		# Lumière chaude de coucher de soleil.
		draw_circle(room_size * Vector2(0.35, 0.4), minf(room_size.x, room_size.y) * 0.55, Color(1.0, 0.62, 0.38, 0.07))


## Visuel d'un mur ou d'un pilier (centré sur le corps physique).
class WallVisual extends Node2D:
	var size: Vector2 = Vector2.ZERO
	var is_pillar: bool = false

	func _draw() -> void:
		var r := Rect2(-size / 2.0, size)
		if is_pillar:
			# Ombre bleu nuit projetée vers le bas-droite.
			draw_rect(Rect2(r.position + Vector2(18, 22), r.size), Color(SHADOW_NIGHT, 0.4))
		var stone := Color(0.74, 0.55, 0.36) if is_pillar else Color(0.62, 0.45, 0.32)
		var mortar := stone.lerp(SHADOW_NIGHT, 0.4)
		draw_rect(r, stone)
		# Rangées de pierres de taille.
		var brick_h := 32.0
		var y := r.position.y
		var row := 0
		while y < r.end.y:
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), mortar, 2.0)
			var bx := r.position.x + (24.0 if row % 2 == 1 else 0.0)
			while bx < r.end.x:
				draw_line(Vector2(bx, y), Vector2(bx, minf(y + brick_h, r.end.y)), mortar, 2.0)
				bx += 48.0
			y += brick_h
			row += 1
		# Face éclairée (haut-gauche) et face à l'ombre (bas-droite).
		draw_line(r.position, Vector2(r.end.x, r.position.y), stone.lightened(0.3), 4.0)
		draw_line(r.position, Vector2(r.position.x, r.end.y), stone.lightened(0.2), 4.0)
		draw_line(Vector2(r.position.x, r.end.y), r.end, mortar, 4.0)
		if is_pillar:
			# Chapiteau de pierre claire + bannière rouge à emblème blanc.
			draw_rect(Rect2(r.position, Vector2(r.size.x, 14.0)), stone.lightened(0.25))
			TestRoom.draw_banner(self, Vector2(0, r.position.y + 14.0), r.size.x * 0.42, r.size.y - 30.0)
		else:
			# Créneaux et bannières le long des murs intérieurs.
			_draw_wall_banners(r)
		draw_rect(r, STONE_OUTLINE, false, 4.0)

	func _draw_wall_banners(r: Rect2) -> void:
		var horizontal := r.size.x > r.size.y
		var length := r.size.x if horizontal else r.size.y
		var spacing := 420.0
		var count := maxi(int(length / spacing), 1)
		for i: int in count:
			var t := (float(i) + 0.5) / float(count)
			if horizontal:
				var x := r.position.x + r.size.x * t
				TestRoom.draw_banner(self, Vector2(x, r.position.y + 6.0), 40.0, r.size.y + 30.0)
			else:
				var yy := r.position.y + r.size.y * t
				var bx := r.get_center().x
				TestRoom.draw_banner(self, Vector2(bx, yy - 40.0), r.size.x * 0.6, 80.0)
