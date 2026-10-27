class_name FallbackBuilder
extends Node2D
## Constructeur de monde de SECOURS, utilisé par le Raid tant que
## res://scripts/dungeon/world_builder.gd (WorldBuilder) n'existe pas.
## Même contrat minimal que WorldBuilder (cf. docs/CONVENTIONS.md, phase 3) :
##   FallbackBuilder.build(layout, world) -> Node2D racine avec
##   get_doors(), get_stairs_areas() (meta `stairs`), signal stairs_entered(stairs).
## Rendu : rectangles colorés (sol, rue, murs, escaliers, extraction), collisions
## de murs sur la couche world (rectangles fusionnés), portes simples.

signal stairs_entered(stairs: FloorLayout.Stairs)

const LAYER_WORLD := 1
const MASK_PLAYER := 2
const MASK_ENEMIES := 4

var layout: FloorLayout = null
var _doors: Array[Node2D] = []
var _stairs_areas: Array[Area2D] = []


## Construit l'étage complet. `world` (WorldData ou null) ne sert qu'à la palette.
static func build(p_layout: FloorLayout, world: Resource = null) -> FallbackBuilder:
	var root := FallbackBuilder.new()
	root.name = "FallbackWorld"
	root.layout = p_layout
	root._build(world)
	return root


func get_doors() -> Array[Node2D]:
	return _doors


func get_stairs_areas() -> Array[Area2D]:
	return _stairs_areas


# --- Utilitaire partagé ------------------------------------------------------

## Fusionne en rectangles (gloutonnement : segments par ligne, prolongés vers le bas)
## les cases de `layout` dont la tuile satisfait `predicate(tile) -> bool`.
static func merge_cells(p_layout: FloorLayout, predicate: Callable) -> Array[Rect2i]:
	var w := p_layout.size.x
	var h := p_layout.size.y
	var used := PackedByteArray()
	used.resize(w * h)
	var out: Array[Rect2i] = []
	for y: int in h:
		var x := 0
		while x < w:
			if used[y * w + x] != 0 or not bool(predicate.call(p_layout.tiles[y * w + x])):
				x += 1
				continue
			var x1 := x
			while x1 < w and used[y * w + x1] == 0 and bool(predicate.call(p_layout.tiles[y * w + x1])):
				x1 += 1
			# Prolonge vers le bas tant que la ligne entière [x, x1) convient.
			var y1 := y + 1
			while y1 < h:
				var ok := true
				for xx: int in range(x, x1):
					if used[y1 * w + xx] != 0 or not bool(predicate.call(p_layout.tiles[y1 * w + xx])):
						ok = false
						break
				if not ok:
					break
				y1 += 1
			for yy: int in range(y, y1):
				for xx: int in range(x, x1):
					used[yy * w + xx] = 1
			out.append(Rect2i(x, y, x1 - x, y1 - y))
			x = x1
	return out


static func is_solid_tile(t: int) -> bool:
	return t == FloorLayout.Tile.WALL or t == FloorLayout.Tile.VOID


static func cell_rect_world(r: Rect2i) -> Rect2:
	var ts := float(FloorLayout.TILE_SIZE)
	return Rect2(Vector2(r.position) * ts, Vector2(r.size) * ts)


# --- Construction ------------------------------------------------------------

func _build(world: Resource) -> void:
	var tiles := TileDrawer.new()
	tiles.name = "Tiles"
	tiles.layout = layout
	tiles.palette = _read_palette(world)
	tiles.z_index = 0
	add_child(tiles)
	_build_walls()
	_build_doors()
	_build_stairs()


func _read_palette(world: Resource) -> Dictionary:
	var pal := {
		"void": Color(0.07, 0.10, 0.18),
		"street": Color(0.80, 0.62, 0.40),
		"floor": Color(0.55, 0.38, 0.24),
		"wall": Color(0.38, 0.25, 0.19),
		"stairs": Color(0.72, 0.55, 0.36),
		"extraction": Color(0.30, 0.85, 0.45, 0.45),
	}
	if world != null and world.get("palette") is Dictionary:
		var wp: Dictionary = world.get("palette")
		for k: String in pal.keys():
			if wp.get(k) is Color:
				pal[k] = wp[k]
	return pal


func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	for r: Rect2i in merge_cells(layout, is_solid_tile):
		var wr := cell_rect_world(r)
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = wr.size
		cs.shape = shape
		cs.position = wr.get_center()
		body.add_child(cs)


func _build_doors() -> void:
	var margin := Balance.get_float("raid", "fallback_door_trigger_margin", 14.0)
	for d: FloorLayout.Door in layout.doors:
		var door := FallbackDoor.new()
		door.name = "Door%d" % d.id
		door.cell = d.cell
		door.vertical = d.vertical
		door.key_id = d.key_id
		door.trigger_margin = margin
		door.initial_state = d.state
		door.position = FloorLayout.cell_to_world(d.cell)
		add_child(door)
		_doors.append(door)


func _build_stairs() -> void:
	var ts := float(FloorLayout.TILE_SIZE)
	for st: FloorLayout.Stairs in layout.stairs:
		var area := Area2D.new()
		area.name = "Stairs_%d_%d" % [st.cell.x, st.cell.y]
		area.collision_layer = 0
		area.collision_mask = MASK_PLAYER
		area.monitorable = false
		area.position = FloorLayout.cell_to_world(st.cell)
		area.set_meta(&"stairs", st)
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(ts, ts) * 0.6
		cs.shape = shape
		area.add_child(cs)
		add_child(area)
		area.body_entered.connect(_on_stairs_body_entered.bind(st))
		_stairs_areas.append(area)


func _on_stairs_body_entered(body: Node2D, st: FloorLayout.Stairs) -> void:
	if body.is_in_group(&"player"):
		stairs_entered.emit(st)


## Sol, rues, murs, escaliers et cases d'extraction (dessinés une seule fois).
class TileDrawer extends Node2D:
	var layout: FloorLayout = null
	var palette: Dictionary = {}

	func _draw() -> void:
		if layout == null:
			return
		var ts := float(FloorLayout.TILE_SIZE)
		var night := Color(0.07, 0.10, 0.22)
		for y: int in layout.size.y:
			for x: int in layout.size.x:
				var c := Vector2i(x, y)
				var t := layout.get_tile(c)
				var r := Rect2(Vector2(c) * ts, Vector2(ts, ts))
				match t:
					FloorLayout.Tile.VOID:
						draw_rect(r, palette["void"])
					FloorLayout.Tile.STREET:
						var col: Color = palette["street"]
						col = col.darkened(0.04 if (x + y) % 2 == 0 else 0.0)
						draw_rect(r, col)
					FloorLayout.Tile.FLOOR, FloorLayout.Tile.DOOR:
						var col2: Color = palette["floor"]
						draw_rect(r, col2)
						# Lattes de plancher.
						for i: int in range(1, 4):
							var yy := r.position.y + ts * float(i) / 4.0
							draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), col2.darkened(0.25), 1.0)
					FloorLayout.Tile.WALL:
						var wc: Color = palette["wall"]
						draw_rect(r, wc)
						draw_line(r.position, Vector2(r.end.x, r.position.y), wc.lightened(0.25), 3.0)
						draw_line(Vector2(r.position.x, r.end.y), r.end, wc.lerp(night, 0.5), 3.0)
					FloorLayout.Tile.STAIRS_UP, FloorLayout.Tile.STAIRS_DOWN:
						var sc: Color = palette["stairs"]
						draw_rect(r, sc)
						for i: int in 5:
							var k := float(i) / 5.0
							var shade := sc.lightened(0.3 * (1.0 - k)) if t == FloorLayout.Tile.STAIRS_UP else sc.darkened(0.5 * k)
							draw_rect(Rect2(r.position + Vector2(4, 4 + k * (ts - 8)), Vector2(ts - 8, (ts - 8) / 5.0 - 2)), shade)
						var arrow := "▲" if t == FloorLayout.Tile.STAIRS_UP else "▼"
						draw_string(ThemeDB.fallback_font, r.position + Vector2(ts * 0.3, ts * 0.65), arrow, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		# Ombre bleu nuit sous les murs (soleil couchant en haut-gauche).
		for y: int in layout.size.y:
			for x: int in layout.size.x:
				var c := Vector2i(x, y)
				if layout.get_tile(c) == FloorLayout.Tile.WALL and FloorLayout.is_walkable_tile(layout.get_tile(c + Vector2i.DOWN)):
					draw_rect(Rect2(Vector2(c + Vector2i.DOWN) * ts, Vector2(ts, ts * 0.25)), Color(night, 0.3))
		for c: Vector2i in layout.extraction_cells:
			var r := Rect2(Vector2(c) * ts, Vector2(ts, ts))
			draw_rect(r, palette["extraction"])
			draw_rect(r.grow(-3), Color(0.5, 1.0, 0.6, 0.9), false, 3.0)


## Porte simple : bloque (couche world) tant qu'elle est fermée ; s'ouvre au contact
## du joueur ou d'un ennemi en combat ; verrouillée = cadenas, signal locked_bumped.
class FallbackDoor extends StaticBody2D:
	signal state_changed(door: Node2D)
	signal locked_bumped(door: Node2D)

	var cell: Vector2i = Vector2i.ZERO
	var vertical: bool = false
	var key_id: StringName = &""
	var trigger_margin: float = 14.0
	var initial_state: int = FloorLayout.DoorState.CLOSED
	var state: int = FloorLayout.DoorState.CLOSED
	var _shape: CollisionShape2D = null
	var _trigger: Area2D = null
	var _bump_cooldown: float = 0.0

	func _ready() -> void:
		add_to_group(&"doors")
		collision_mask = 0
		var ts := float(FloorLayout.TILE_SIZE)
		_shape = CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(ts, ts)
		_shape.shape = rect
		add_child(_shape)
		_trigger = Area2D.new()
		_trigger.collision_layer = 0
		_trigger.collision_mask = MASK_PLAYER | MASK_ENEMIES
		_trigger.monitorable = false
		var tcs := CollisionShape2D.new()
		var trect := RectangleShape2D.new()
		trect.size = Vector2(ts, ts) + Vector2.ONE * trigger_margin * 2.0
		tcs.shape = trect
		_trigger.add_child(tcs)
		add_child(_trigger)
		state = initial_state
		_apply()

	func is_open() -> bool:
		return state == FloorLayout.DoorState.OPEN

	func is_locked() -> bool:
		return state == FloorLayout.DoorState.LOCKED

	func open() -> void:
		if state == FloorLayout.DoorState.OPEN:
			return
		state = FloorLayout.DoorState.OPEN
		_apply()
		state_changed.emit(self)

	func close() -> void:
		if state == FloorLayout.DoorState.CLOSED:
			return
		state = FloorLayout.DoorState.CLOSED
		_apply()
		state_changed.emit(self)

	func try_unlock(p_key_id: StringName) -> bool:
		if state != FloorLayout.DoorState.LOCKED or p_key_id != key_id:
			return false
		state = FloorLayout.DoorState.CLOSED
		_apply()
		state_changed.emit(self)
		return true

	func _apply() -> void:
		collision_layer = 0 if is_open() else LAYER_WORLD
		if _shape != null:
			_shape.set_deferred("disabled", is_open())
		if _trigger != null:
			_trigger.set_deferred("monitoring", not is_open())
		queue_redraw()

	func _physics_process(delta: float) -> void:
		_bump_cooldown = maxf(_bump_cooldown - delta, 0.0)
		if is_open() or _trigger == null or not _trigger.monitoring:
			return
		for b: Node2D in _trigger.get_overlapping_bodies():
			var opener := b.is_in_group(&"player")
			if not opener and b.has_method("is_in_combat") and b.has_method("is_alive"):
				opener = bool(b.call("is_alive")) and bool(b.call("is_in_combat"))
			if not opener:
				continue
			if is_locked():
				if b.is_in_group(&"player") and _bump_cooldown <= 0.0:
					_bump_cooldown = 1.5
					locked_bumped.emit(self)
				continue
			open()
			return

	func _draw() -> void:
		var ts := float(FloorLayout.TILE_SIZE)
		var h := ts * 0.5
		var wood := Color(0.47, 0.30, 0.17)
		var outline := Color(0.11, 0.09, 0.14)
		if is_open():
			# Battant rabattu contre le chambranle.
			var leaf := Rect2(-h, -h, ts, 8) if vertical else Rect2(-h, -h, 8, ts)
			draw_rect(leaf, wood.lightened(0.1))
			draw_rect(leaf, outline, false, 2.0)
			return
		var r := Rect2(-h + 4, -h + 4, ts - 8, ts - 8)
		draw_rect(r, wood if not is_locked() else wood.lerp(Color(0.6, 0.12, 0.1), 0.45))
		for i: int in range(1, 4):
			var k := -h + 4 + (ts - 8) * float(i) / 4.0
			if vertical:
				draw_line(Vector2(r.position.x, k), Vector2(r.end.x, k), wood.darkened(0.35), 2.0)
			else:
				draw_line(Vector2(k, r.position.y), Vector2(k, r.end.y), wood.darkened(0.35), 2.0)
		draw_rect(r, outline, false, 3.0)
		if is_locked():
			# Cadenas.
			draw_arc(Vector2(0, -6), 8.0, PI, TAU, 12, Color(0.85, 0.8, 0.6), 3.0)
			draw_rect(Rect2(-11, -6, 22, 18), Color(0.85, 0.7, 0.25))
			draw_rect(Rect2(-11, -6, 22, 18), outline, false, 2.0)
