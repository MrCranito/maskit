class_name EgyptBuilder
extends Node2D
## Constructeur du décor de la surface des Pyramides d'Égypte.
##   EgyptBuilder.build(layout, world) -> EgyptBuilder (Node2D racine triée en Y)
## Même API que WorldBuilder (docs/CONVENTIONS.md) : get_doors(), get_stairs_areas() (meta
## `stairs`), signal stairs_entered(stairs), get_room_at_world(pos), set_stairs_cooldown(sec) ;
## en plus get_roofs(), get_props(), get_wall_body(), prerender_hide().
##
## Rendu 2D « de secours » dessiné en code (sable, dalles de grès, murs 3/4 en grès, ombres
## chaudes, torches) : en jeu, le fond pré-rendu (tools/prerender/eg_scene.py →
## assets/prerender/egypt_pyramids/<seed>/) remplace sol, murs, décors et toits
## (PrerenderBackdrop.attach_to masque Ground, Walls, FloorDetails, Prop_*, les toits restent
## logiques). Collisions des murs fusionnées (couche world), portes EgDoor, décors EgProp
## (atlas assets/sprites/egypt_pyramids/atlas.png), toits plats des chambres (EgRoof :
## s'effacent quand le joueur entre), lueurs additives des torches (un seul nœud).
## Performance : aucun _draw par image (sauf extraction), aucune lumière dynamique.

signal stairs_entered(stairs: FloorLayout.Stairs)

const TS := float(FloorLayout.TILE_SIZE)
const LAYER_WORLD := 1
const MASK_PLAYER := 2
const DoorScript := preload("res://scripts/biomes/egypt_pyramids/eg_door.gd")
const PropScript := preload("res://scripts/biomes/egypt_pyramids/eg_prop.gd")
const Pop := preload("res://scripts/biomes/egypt_pyramids/eg_populator.gd")
const FONT: Font = preload("res://assets/fonts/nunito/Nunito-Variable.ttf")
const OUTLINE := Color(0.2, 0.1, 0.06)
const SHADOW := Color(0.3, 0.14, 0.08)

## Libellés et formes des conteneurs / cachettes du biome (BiomeRegistry.DEF_SCRIPTS).
const CONTAINER_DEFS := {
	&"eg_jar": {"name": "Jarre scellée", "block": Vector2(28, 14), "reach": 4.0, "shadow": 0.0},
	&"eg_sarcophagus": {"name": "Sarcophage", "block": Vector2(56, 22), "reach": 6.0, "shadow": 0.0},
	&"eg_chest": {"name": "Coffre de bois", "block": Vector2(44, 18), "reach": 4.0, "shadow": 0.0},
	&"eg_gold_chest": {"name": "Coffre doré du Pharaon", "block": Vector2(50, 20), "reach": 6.0, "shadow": 0.0},
	&"eg_altar": {"name": "Autel aux offrandes", "block": Vector2(54, 20), "reach": 6.0, "shadow": 0.0},
	&"eg_basket": {"name": "Panier de vannerie", "block": Vector2(30, 14), "reach": 4.0, "shadow": 0.0},
	&"eg_mummy": {"name": "Momie", "block": Vector2.ZERO, "reach": 12.0, "shadow": 0.0},
	&"eg_corpse": {"name": "Pilleur momifié", "block": Vector2.ZERO, "reach": 12.0, "shadow": 0.0},
}
const HIDE_DEFS := {
	&"eg_sarcophagus_hide": {"name": "Dans le sarcophage", "block": Vector2(56, 22), "reach": 6.0, "shadow": 0.0},
	&"eg_big_jar": {"name": "Dans la grande jarre", "block": Vector2(36, 18), "reach": 6.0, "shadow": 0.0},
	&"eg_hay_cart": {"name": "Sous la charrette", "block": Vector2(90, 24), "reach": 10.0, "shadow": 0.0},
}

var layout: FloorLayout = null
var palette: Dictionary = {}
var wall_height: float = 52.0

var _doors: Array[DoorNode] = []
var _stairs_areas: Array[Area2D] = []
var _roofs: Array[Node2D] = []
var _props: Array[Node2D] = []
var _wall_body: StaticBody2D = null
var _stairs_cooldown: float = 0.5
var _room_grid: PackedInt32Array = PackedInt32Array()
var _building_grid: PackedInt32Array = PackedInt32Array()
var _glows: Array = []
var _container_kind_at: Dictionary = {}
var _hide_kind_at: Dictionary = {}
var _contract: Dictionary = {}


static func build(p_layout: FloorLayout, world: Resource = null) -> EgyptBuilder:
	var root := EgyptBuilder.new()
	root.name = "World"
	root.layout = p_layout
	root._build(world)
	return root


# --- API -----------------------------------------------------------------------

func get_doors() -> Array[DoorNode]:
	return _doors


func get_stairs_areas() -> Array[Area2D]:
	return _stairs_areas


func get_roofs() -> Array[Node2D]:
	return _roofs


func get_props() -> Array[Node2D]:
	return _props


func get_wall_body() -> StaticBody2D:
	return _wall_body


## (Pré-rendu) Masque les visuels remplacés par le fond pré-calculé.
func prerender_hide() -> void:
	for nm: String in ["Glows", "Landmarks"]:
		var n := get_node_or_null(NodePath(nm))
		if n is CanvasItem:
			(n as CanvasItem).visible = false


func get_room_at_world(pos: Vector2) -> FloorLayout.Room:
	if layout == null:
		return null
	var c := FloorLayout.world_to_cell(pos)
	if not layout.in_bounds(c):
		return null
	var id := _room_grid[c.y * layout.size.x + c.x]
	return layout.get_room(id) if id >= 0 else null


func get_building_at_world(pos: Vector2) -> FloorLayout.Building:
	var c := FloorLayout.world_to_cell(pos)
	var id := building_id_at(c)
	return layout.buildings[id] if id >= 0 else null


func set_stairs_cooldown(sec: float) -> void:
	_stairs_cooldown = maxf(sec, 0.0)
	set_process(_stairs_cooldown > 0.0)


func _process(delta: float) -> void:
	if _stairs_cooldown > 0.0:
		_stairs_cooldown = maxf(_stairs_cooldown - delta, 0.0)
	else:
		set_process(false)


# --- Construction ----------------------------------------------------------------

func _build(world: Resource) -> void:
	y_sort_enabled = true
	if layout == null:
		push_warning("EgyptBuilder: layout null.")
		return
	palette = {}
	var wp: Variant = world.get("palette") if world != null else null
	if wp is Dictionary:
		palette = (wp as Dictionary).duplicate()
	wall_height = _cfg_f("wall_height", Balance.get_float("world_builder", "wall_height", 52.0))
	_stairs_cooldown = Balance.get_float("world_builder", "stairs_cooldown", 0.5)
	if layout.has_meta(&"render_contract"):
		_contract = layout.get_meta(&"render_contract")
	_build_grids()
	_build_ground()
	_build_walls()
	_build_landmarks()
	_build_doors()
	_build_stairs()
	_build_props()
	_build_extraction()
	_build_roofs()
	_build_ambience()
	for s in layout.container_spawns:
		_container_kind_at[s.cell] = s.kind
	for h in layout.hiding_spot_spawns:
		_hide_kind_at[h.cell] = h.kind
	child_entered_tree.connect(_on_child_entered)


static func _cfg_f(key: String, def: float) -> float:
	return Balance.get_float("egypt_pyramids", key, def)


static func _cfg_c(key: String, def: Color) -> Color:
	var v: Variant = Balance.get_value("egypt_pyramids", key, def)
	return v if v is Color else def


func _build_grids() -> void:
	var n := layout.size.x * layout.size.y
	_room_grid.resize(n)
	_room_grid.fill(-1)
	_building_grid.resize(n)
	_building_grid.fill(-1)
	var rooms := layout.rooms.duplicate()
	rooms.sort_custom(func(a: FloorLayout.Room, b: FloorLayout.Room) -> bool: return a.rect.get_area() > b.rect.get_area())
	for r: FloorLayout.Room in rooms:
		_fill_grid(_room_grid, r.rect, r.id)
	for b: FloorLayout.Building in layout.buildings:
		_fill_grid(_building_grid, b.rect, b.id)


func _fill_grid(grid: PackedInt32Array, r: Rect2i, v: int) -> void:
	var w := layout.size.x
	for y: int in range(maxi(r.position.y, 0), mini(r.end.y, layout.size.y)):
		for x: int in range(maxi(r.position.x, 0), mini(r.end.x, w)):
			grid[y * w + x] = v


func room_id_at(c: Vector2i) -> int:
	if not layout.in_bounds(c):
		return -1
	return _room_grid[c.y * layout.size.x + c.x]


func room_at(c: Vector2i) -> FloorLayout.Room:
	var id := room_id_at(c)
	return layout.get_room(id) if id >= 0 else null


func building_id_at(c: Vector2i) -> int:
	if not layout.in_bounds(c):
		return -1
	return _building_grid[c.y * layout.size.x + c.x]


func role_at(c: Vector2i) -> String:
	var r := room_at(c)
	return r.tags[0] if r != null and r.tags.size() > 0 else ""


static func hash01(x: int, y: int, s: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


func add_glow(pos: Vector2, radius: float, strength: float = 1.0, color: Color = Color(1.0, 0.62, 0.26)) -> void:
	_glows.append([pos, radius, strength, color])


func col(key: String, def: Color) -> Color:
	var v: Variant = palette.get(key, null)
	return v if v is Color else def


# --- Sol -------------------------------------------------------------------------

func _build_ground() -> void:
	var ground := Ground.new()
	ground.name = "Ground"
	ground.builder = self
	ground.z_index = 0
	add_child(ground)


## Sable (STREET), dalles de grès (FLOOR), ombres portées des murs, braises au sol : un nœud dessiné une fois.
class Ground extends Node2D:
	var builder: EgyptBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var sand := builder.col("sand", Color(0.9, 0.74, 0.46))
		var flo := builder.col("floor", Color(0.74, 0.6, 0.4))
		var full := Rect2(Vector2(-14, -14) * TS, (Vector2(L.size) + Vector2(28, 28)) * TS)
		draw_rect(full, sand.darkened(0.12))
		for r: Rect2i in WorldBuilder.merge_cells(L, func(t: int) -> bool: return t == FloorLayout.Tile.STREET or t == FloorLayout.Tile.DOOR):
			draw_rect(Rect2(Vector2(r.position) * TS, Vector2(r.size) * TS), sand)
		for r2: Rect2i in WorldBuilder.merge_cells(L, func(t: int) -> bool: return t == FloorLayout.Tile.FLOOR):
			var rr := Rect2(Vector2(r2.position) * TS, Vector2(r2.size) * TS)
			draw_rect(rr, flo)
		# Dalles : joints toutes les cases, variation de teinte.
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				var t := L.get_tile(c)
				var o := Vector2(c) * TS
				if t == FloorLayout.Tile.FLOOR:
					var v := 0.94 + 0.12 * EgyptBuilder.hash01(x, y, 3)
					draw_rect(Rect2(o + Vector2(2, 2), Vector2(TS - 4, TS - 4)), Color(flo.r * v, flo.g * v, flo.b * v))
					draw_rect(Rect2(o, Vector2(TS, 2)), Color(flo.darkened(0.35), 0.6))
					draw_rect(Rect2(o, Vector2(2, TS)), Color(flo.darkened(0.35), 0.6))
				elif t == FloorLayout.Tile.STREET:
					var h := EgyptBuilder.hash01(x, y, 1)
					if h < 0.07:
						# Ondulation de dune / caillou.
						draw_circle(o + Vector2(TS * 0.5, TS * 0.6), 6.0 + 10.0 * h / 0.07, Color(sand.lightened(0.18), 0.5))
					elif h < 0.1:
						draw_circle(o + Vector2(TS * 0.4, TS * 0.5), 3.0, Color(sand.darkened(0.3), 0.6))
		# Ombres chaudes au pied des murs (nord et ouest).
		for y2: int in L.size.y:
			for x2: int in L.size.x:
				var c2 := Vector2i(x2, y2)
				if not FloorLayout.is_walkable_tile(L.get_tile(c2)):
					continue
				var o2 := Vector2(c2) * TS
				if L.get_tile(c2 + Vector2i.UP) == FloorLayout.Tile.WALL:
					draw_rect(Rect2(o2, Vector2(TS, 30.0)), Color(SHADOW, 0.28))
					draw_rect(Rect2(o2, Vector2(TS, 14.0)), Color(SHADOW, 0.2))
				if L.get_tile(c2 + Vector2i.LEFT) == FloorLayout.Tile.WALL:
					draw_rect(Rect2(o2, Vector2(20.0, TS)), Color(SHADOW, 0.22))
		# Lumière du couchant : dégradé chaud (nord-ouest) → ambré (sud-est).
		var pts := PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)])
		draw_polygon(pts, PackedColorArray([Color(1.0, 0.72, 0.4, 0.14), Color(1.0, 0.6, 0.35, 0.1), Color(0.9, 0.45, 0.3, 0.16), Color(1.0, 0.68, 0.4, 0.08)]))


# --- Murs ------------------------------------------------------------------------

func _build_walls() -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	walls.z_index = 10
	add_child(walls)
	var d := WallLayer.new()
	d.name = "WallFaces"
	d.builder = self
	walls.add_child(d)
	_wall_body = StaticBody2D.new()
	_wall_body.name = "WallBodies"
	_wall_body.collision_layer = LAYER_WORLD
	_wall_body.collision_mask = 0
	walls.add_child(_wall_body)
	for r: Rect2i in WorldBuilder.merge_cells(layout, func(t: int) -> bool: return FloorLayout.is_opaque_tile(t)):
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(r.size) * TS
		cs.shape = shape
		cs.position = (Vector2(r.position) + Vector2(r.size) * 0.5) * TS
		_wall_body.add_child(cs)
	var full := Rect2(Vector2.ZERO, Vector2(layout.size) * TS)
	for side: Rect2 in [Rect2(full.position - Vector2(TS, TS), Vector2(full.size.x + 2.0 * TS, TS)),
			Rect2(Vector2(-TS, full.end.y), Vector2(full.size.x + 2.0 * TS, TS)),
			Rect2(Vector2(-TS, 0), Vector2(TS, full.size.y)), Rect2(Vector2(full.end.x, 0), Vector2(TS, full.size.y))]:
		var cs2 := CollisionShape2D.new()
		var shape2 := RectangleShape2D.new()
		shape2.size = side.size
		cs2.shape = shape2
		cs2.position = side.get_center()
		_wall_body.add_child(cs2)


## Cases murées couvertes par un grand repère (pyramide, sphinx, rocher…) : dessinées par Landmarks.
func _landmark_cells() -> Dictionary:
	var out := {}
	for e: Variant in layout.landmarks:
		if e is Dictionary and e.get("rect") is Rect2i:
			var r: Rect2i = e["rect"]
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					out[Vector2i(x, y)] = String(e.get("kind", ""))
	return out


class WallLayer extends Node2D:
	var builder: EgyptBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var lm := builder._landmark_cells()
		var wall := builder.col("wall", Color(0.6, 0.42, 0.26))
		var stone := builder.col("sandstone", Color(0.82, 0.64, 0.42))
		var wh := builder.wall_height
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				if L.get_tile(c) != FloorLayout.Tile.WALL or lm.has(c):
					continue
				var o := Vector2(c) * TS
				var face := FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN))
				var cap_h := TS - wh if face else TS
				var v := 0.92 + 0.14 * EgyptBuilder.hash01(x, y, 9)
				var cap := Color(stone.r * v, stone.g * v, stone.b * v)
				draw_rect(Rect2(o, Vector2(TS, cap_h)), cap)
				if L.get_tile(c + Vector2i.UP) != FloorLayout.Tile.WALL:
					draw_rect(Rect2(o, Vector2(TS, 3)), Color(1.0, 0.9, 0.7, 0.5))
				if L.get_tile(c + Vector2i.LEFT) != FloorLayout.Tile.WALL:
					draw_rect(Rect2(o, Vector2(3, cap_h)), Color(1.0, 0.9, 0.7, 0.4))
				if L.get_tile(c + Vector2i.RIGHT) != FloorLayout.Tile.WALL:
					draw_rect(Rect2(o + Vector2(TS - 4, 0), Vector2(4, cap_h)), Color(SHADOW, 0.45))
				if face:
					var f := Rect2(o + Vector2(0, cap_h), Vector2(TS, wh))
					var fv := 0.9 + 0.12 * EgyptBuilder.hash01(x, y, 11)
					draw_rect(f, Color(wall.r * fv, wall.g * fv, wall.b * fv))
					# Assises de grès (joints horizontaux) et frise de hiéroglyphes sur les chambres.
					var yy := f.position.y + 12.0
					while yy < f.end.y - 4.0:
						draw_line(Vector2(f.position.x, yy), Vector2(f.end.x, yy), Color(wall.darkened(0.35), 0.7), 1.5)
						var jx := f.position.x + (TS * 0.5 if int(yy / 12.0) % 2 == 0 else TS * 0.2)
						draw_line(Vector2(jx, yy), Vector2(jx, yy + 12.0), Color(wall.darkened(0.35), 0.5), 1.2)
						yy += 12.0
					if builder.building_id_at(c) >= 0:
						draw_rect(Rect2(f.position + Vector2(4, 4), Vector2(TS - 8, 10)), Color(0.95, 0.78, 0.4, 0.55))
						for k: int in 4:
							draw_rect(Rect2(f.position + Vector2(8.0 + float(k) * 13.0, 6.0), Vector2(4, 6)), Color(OUTLINE, 0.6))
					draw_rect(Rect2(f.position, Vector2(TS, 2)), OUTLINE)
					draw_rect(Rect2(f.position.x, f.end.y - 2.0, TS, 2.0), OUTLINE)
					draw_rect(Rect2(f.position + Vector2(0, 2), Vector2(TS, 4)), Color(1.0, 0.9, 0.7, 0.3))
				draw_rect(Rect2(o, Vector2(TS, cap_h)), OUTLINE, false, 1.0)


## Pyramides, sphinx, obélisques, rochers, ruines, palmiers, dunes : grands repères posés sur
## leurs cases murées (un nœud dessiné une fois, z 10 trié en Y à la rangée du bas).
func _build_landmarks() -> void:
	var holder := Node2D.new()
	holder.name = "Landmarks"
	holder.y_sort_enabled = true
	holder.z_index = 10
	add_child(holder)
	for e: Variant in layout.landmarks:
		if not (e is Dictionary) or not (e.get("rect") is Rect2i):
			continue
		var lm := Landmark.new()
		lm.kind = StringName(String(e.get("kind", "rock")))
		lm.rect = e["rect"]
		lm.builder = self
		var r: Rect2i = lm.rect
		lm.position = Vector2((float(r.position.x) + float(r.size.x) * 0.5) * TS, float(r.end.y) * TS)
		holder.add_child(lm)
		if lm.kind == &"obelisk":
			add_glow(lm.position + Vector2(0, -TS * 2.2), 40.0, 0.5, Color(1.0, 0.85, 0.5))


class Landmark extends Node2D:
	var kind: StringName = &"rock"
	var rect: Rect2i = Rect2i()
	var builder: EgyptBuilder = null

	func _draw() -> void:
		var w := float(rect.size.x) * TS
		var h := float(rect.size.y) * TS
		var stone := builder.col("sandstone", Color(0.82, 0.64, 0.42))
		var dark := builder.col("sandstone_dark", Color(0.52, 0.36, 0.22))
		match kind:
			&"pyramid_big", &"pyramid_small":
				var apex := Vector2(0.0, -h - w * 0.55)
				var bl := Vector2(-w * 0.5, 0.0)
				var br := Vector2(w * 0.5, 0.0)
				var tl := Vector2(-w * 0.5, -h)
				var tr := Vector2(w * 0.5, -h)
				draw_colored_polygon(PackedVector2Array([bl, br, apex]), stone.lightened(0.08))
				draw_colored_polygon(PackedVector2Array([bl, apex, tl]), dark)
				draw_colored_polygon(PackedVector2Array([br, apex, tr]), stone.darkened(0.15))
				var n := int(h / 14.0)
				for k: int in n:
					var f := float(k) / float(n)
					draw_line(bl.lerp(apex, f), br.lerp(apex, f), Color(OUTLINE, 0.25), 1.0)
				# Entrée sombre.
				draw_rect(Rect2(-10.0, -34.0, 20.0, 34.0), Color(0.12, 0.07, 0.05))
				draw_polyline(PackedVector2Array([bl, apex, br, bl]), OUTLINE, 2.0)
			&"sphinx":
				# Colosse assis : socle, corps, tête (vu de 3/4).
				draw_rect(Rect2(-w * 0.5, -h * 0.35, w, h * 0.35), dark)
				draw_rect(Rect2(-w * 0.5, -h * 0.35, w, h * 0.35), OUTLINE, false, 2.0)
				draw_rect(Rect2(-w * 0.36, -h * 0.95, w * 0.72, h * 0.62), stone)
				draw_rect(Rect2(-w * 0.36, -h * 0.95, w * 0.72, h * 0.62), OUTLINE, false, 2.0)
				draw_circle(Vector2(0.0, -h * 1.05), w * 0.26, stone.lightened(0.1))
				draw_rect(Rect2(-w * 0.32, -h * 1.1, w * 0.64, h * 0.12), Color(0.95, 0.78, 0.36))
				draw_arc(Vector2(0.0, -h * 1.05), w * 0.26, 0.0, TAU, 24, OUTLINE, 2.0)
			&"obelisk":
				draw_colored_polygon(PackedVector2Array([Vector2(-14, 0), Vector2(14, 0), Vector2(8, -150), Vector2(-8, -150)]), stone)
				draw_colored_polygon(PackedVector2Array([Vector2(-8, -150), Vector2(8, -150), Vector2(0, -168)]), Color(0.98, 0.82, 0.4))
				draw_polyline(PackedVector2Array([Vector2(-14, 0), Vector2(14, 0), Vector2(8, -150), Vector2(0, -168), Vector2(-8, -150), Vector2(-14, 0)]), OUTLINE, 2.0)
			&"palm":
				draw_rect(Rect2(-5, -90, 10, 90), Color(0.48, 0.32, 0.2))
				draw_rect(Rect2(-5, -90, 10, 90), OUTLINE, false, 1.5)
				for k: int in 7:
					var a := float(k) * TAU / 7.0
					var tip := Vector2(cos(a) * 46.0, -90.0 + sin(a) * 20.0 + 12.0)
					draw_line(Vector2(0, -92), tip, OUTLINE, 9.0)
					draw_line(Vector2(0, -92), tip, Color(0.3, 0.52, 0.24), 6.0)
			&"ruin":
				draw_rect(Rect2(-w * 0.5 + 4, -h * 0.5, w - 8, h * 0.5), stone.darkened(0.1))
				draw_rect(Rect2(-w * 0.5 + 4, -h * 0.5 - 30, 18, 30), stone)
				draw_rect(Rect2(w * 0.5 - 30, -h * 0.5 - 18, 18, 18), stone)
				draw_rect(Rect2(-w * 0.5 + 4, -h * 0.5 - 30, w - 8, h * 0.5 + 30), OUTLINE, false, 1.5)
			&"dune":
				draw_set_transform(Vector2(0, -h * 0.3), 0.0, Vector2(1.0, 0.45))
				draw_circle(Vector2.ZERO, w * 0.5, builder.col("sand", Color(0.9, 0.74, 0.46)).lightened(0.14))
				draw_arc(Vector2.ZERO, w * 0.5, PI, TAU, 24, Color(1, 0.95, 0.8, 0.5), 3.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			_:
				# Rocher.
				draw_set_transform(Vector2(0, -h * 0.4), 0.0, Vector2(1.0, 0.8))
				draw_circle(Vector2.ZERO, w * 0.5, dark)
				draw_circle(Vector2(-w * 0.12, -h * 0.15), w * 0.34, stone.darkened(0.08))
				draw_arc(Vector2.ZERO, w * 0.5, 0.0, TAU, 20, OUTLINE, 2.0)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Portes ----------------------------------------------------------------------

func _build_doors() -> void:
	for d: FloorLayout.Door in layout.doors:
		var door: DoorNode = DoorScript.new()
		door.name = "Door_%d" % d.id
		door.setup(d, _door_kind(d), wall_height)
		door.z_index = 10
		add_child(door)
		_doors.append(door)
		add_glow(FloorLayout.cell_to_world(d.cell) + Vector2(0, -wall_height * 0.5), 40.0, 0.4, Color(1.0, 0.6, 0.25))


func _door_kind(d: FloorLayout.Door) -> StringName:
	if d.state == FloorLayout.DoorState.LOCKED:
		return DoorScript.KIND_SEALED
	for rid: int in [d.room_a, d.room_b]:
		var r := layout.get_room(rid)
		if r != null and r.type == FloorLayout.ROOM_BOSS:
			return DoorScript.KIND_BRONZE
	return DoorScript.KIND_STONE


# --- Escaliers (aucun en surface, API conservée) -----------------------------------------

func _build_stairs() -> void:
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
		shape.size = Vector2(TS, TS) * 0.6
		cs.shape = shape
		area.add_child(cs)
		add_child(area)
		area.body_entered.connect(_on_stairs_body_entered.bind(st))
		_stairs_areas.append(area)


func _on_stairs_body_entered(body: Node2D, st: FloorLayout.Stairs) -> void:
	if _stairs_cooldown > 0.0:
		return
	if body.is_in_group(&"player"):
		stairs_entered.emit(st)


# --- Décors ----------------------------------------------------------------------

func _build_props() -> void:
	var shared := PropScript.make_shared_body()
	add_child(shared)
	for s: FloorLayout.Spawn in layout.prop_spawns:
		var pos: Vector2
		if Pop.BIG.has(s.kind) and s.size == Vector2i.ONE:
			var fp: Vector2i = Pop.BIG[s.kind]
			var x0 := s.cell.x - (fp.x - 1) / 2
			pos = Vector2(float(x0) + float(fp.x) * 0.5, float(s.cell.y) + 1.0 - float(fp.y) * 0.5) * TS
		else:
			pos = FloorLayout.cell_to_world(s.cell) + Vector2(0.0, TS * 0.25) + s.offset
		var p := PropScript.create(s.kind, pos, shared, s.flip)
		add_child(p)
		_props.append(p)
		var def: Dictionary = PropScript.def_of(s.kind)
		if def.has("glow"):
			var go: Vector2 = p.call("get_glow_offset")
			add_glow(pos + go, float(def["glow"]), 1.0, def.get("tint", Color(1.0, 0.65, 0.3)))
	# Torches du contrat de rendu (sur les murs) : lueurs seulement.
	for t: Variant in _contract.get("torches", []):
		if t is Vector2i:
			add_glow(FloorLayout.cell_to_world(t) + Vector2(0, -20.0), 80.0, 0.9, Color(1.0, 0.6, 0.22))


# --- Extraction -------------------------------------------------------------------

func _build_extraction() -> void:
	if layout.extraction_cells.is_empty():
		return
	var glow := WorldBuilder.ExtractionGlow.new()
	glow.name = "ExtractionGlow"
	glow.cells = layout.extraction_cells.duplicate()
	glow.color = palette.get("extraction", Color(0.3, 0.85, 0.45, 0.45))
	glow.z_index = 1
	glow.pulse_speed = Balance.get_float("world_builder", "extraction_pulse_speed", 2.2)
	add_child(glow)
	# Un marqueur par groupe de cases (deux sorties).
	var groups: Array = []
	for c: Vector2i in layout.extraction_cells:
		var placed := false
		for g: Array in groups:
			if absi((g[0] as Vector2i).x - c.x) + absi((g[0] as Vector2i).y - c.y) < 6:
				g.append(c)
				placed = true
				break
		if not placed:
			groups.append([c])
	for g2: Array in groups:
		var center := Vector2.ZERO
		for c2: Vector2i in g2:
			center += FloorLayout.cell_to_world(c2)
		center /= float(g2.size())
		var flare := WorldBuilder.ExtractionFlare.new()
		flare.name = "ExtractionFlare"
		flare.position = center + Vector2(0.0, TS * 0.3)
		flare.z_index = 10
		flare.add_to_group(&"extraction_markers")
		add_child(flare)


# --- Toits des chambres ---------------------------------------------------------------

func _build_roofs() -> void:
	var holder := Node2D.new()
	holder.name = "Roofs"
	holder.z_index = 50
	holder.z_as_relative = false
	add_child(holder)
	for b: FloorLayout.Building in layout.buildings:
		var roof := EgRoof.new()
		roof.name = "Roof_%d_%s" % [b.id, String(b.archetype)]
		roof.archetype = b.archetype
		roof.label = b.name
		var r := Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
		roof.footprint = r
		roof.roof_rect = Rect2(r.position.x - 4.0, r.position.y - 4.0, r.size.x + 8.0, r.size.y - wall_height + 4.0)
		roof.hidden_alpha = Balance.get_float("world_builder", "roof_hidden_alpha", 0.1)
		roof.fade_duration = Balance.get_float("world_builder", "roof_fade_duration", 0.25)
		roof.sandstone = col("sandstone", Color(0.82, 0.64, 0.42))
		holder.add_child(roof)
		_roofs.append(roof)


## Toit plat de grès (dalles, rebord, trappe, sable soufflé) qui s'efface quand le joueur entre.
class EgRoof extends Node2D:
	var archetype: StringName = &""
	var label: String = ""
	var footprint: Rect2 = Rect2()
	var roof_rect: Rect2 = Rect2()
	var hidden_alpha: float = 0.1
	var fade_duration: float = 0.25
	var sandstone: Color = Color(0.82, 0.64, 0.42)
	var _player: Node2D = null
	var _inside: bool = false
	var _check_left: float = 0.0
	var _tween: Tween = null

	func _ready() -> void:
		z_index = 50
		z_as_relative = false

	func is_player_inside() -> bool:
		return _inside

	func contains_world(pos: Vector2) -> bool:
		return footprint.has_point(pos)

	func _process(delta: float) -> void:
		_check_left -= delta
		if _check_left > 0.0:
			return
		_check_left = 0.1
		if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
			_player = get_tree().get_first_node_in_group(&"player") as Node2D
		var inside := _player != null and contains_world(_player.global_position)
		if inside == _inside:
			return
		_inside = inside
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", hidden_alpha if inside else 1.0, fade_duration)

	func _draw() -> void:
		var r := roof_rect
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return
		draw_rect(Rect2(r.position + Vector2(10, 10), r.size + Vector2(6, 4)), Color(SHADOW, 0.25))
		var base := sandstone.darkened(0.06) if archetype != &"sanctuary" else Color(0.9, 0.72, 0.4)
		draw_rect(r, base)
		var hs := int(r.position.x * 3.0 + r.position.y * 7.0)
		var y := r.position.y
		var k := 0
		while y < r.end.y - 1.0:
			var x := r.position.x + (0.0 if k % 2 == 0 else TS * 0.5)
			while x < r.end.x - 1.0:
				var q := Rect2(x + 2.0, y + 2.0, minf(TS, r.end.x - x) - 4.0, minf(TS * 0.5, r.end.y - y) - 4.0)
				var v := 0.92 + 0.14 * EgyptBuilder.hash01(int(x), int(y), hs)
				draw_rect(q, Color(base.r * v, base.g * v, base.b * v))
				x += TS
			y += TS * 0.5
			k += 1
		# Sable soufflé sur les dalles.
		for j: int in int(r.get_area() / (TS * TS * 2.5)):
			var p := r.position + Vector2(EgyptBuilder.hash01(hs, j, 21) * r.size.x, EgyptBuilder.hash01(hs, j, 22) * r.size.y)
			draw_circle(p, 10.0 + 12.0 * EgyptBuilder.hash01(hs, j, 23), Color(0.95, 0.8, 0.52, 0.35))
		# Lumière rasante (chaud à l'ouest, ombre à l'est).
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([Color(1.0, 0.8, 0.45, 0.22), Color(0.9, 0.5, 0.3, 0.16), Color(0.5, 0.25, 0.2, 0.28), Color(1.0, 0.7, 0.4, 0.1)]))
		# Rebord (corniche).
		draw_rect(Rect2(r.position, Vector2(r.size.x, 8.0)), base.lightened(0.25))
		draw_rect(Rect2(r.position, Vector2(8.0, r.size.y)), base.lightened(0.2))
		draw_rect(Rect2(r.end.x - 8.0, r.position.y, 8.0, r.size.y), base.darkened(0.3))
		draw_rect(Rect2(r.position.x, r.end.y - 10.0, r.size.x, 10.0), base.darkened(0.25))
		if archetype == &"sanctuary":
			# Disque solaire doré au centre du sanctuaire.
			draw_circle(r.get_center(), 22.0, Color(1.0, 0.82, 0.36))
			draw_arc(r.get_center(), 22.0, 0.0, TAU, 24, OUTLINE, 2.0)
			draw_arc(r.get_center(), 32.0, 0.0, TAU, 24, Color(1.0, 0.82, 0.36, 0.6), 3.0)
		elif r.size.x > TS * 3.0 and r.size.y > TS * 2.0:
			# Trappe d'accès.
			var tp := Rect2(r.position + Vector2(r.size.x * 0.6, r.size.y * 0.35), Vector2(TS * 0.6, TS * 0.45))
			draw_rect(tp, Color(0.2, 0.12, 0.08))
			draw_rect(tp, OUTLINE, false, 2.0)
		draw_rect(r, OUTLINE, false, 3.0)
		_sign(r)

	func _sign(r: Rect2) -> void:
		var text := label.to_upper()
		if text.is_empty():
			return
		var fs := 18
		var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while w > r.size.x - 20.0 and fs > 10:
			fs -= 2
			w = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := r.get_center().x
		var cy := r.end.y - 22.0
		var box := Rect2(cx - w * 0.5 - 8.0, cy - fs * 0.85, w + 16.0, fs * 1.3)
		draw_rect(box, Color(0.3, 0.16, 0.08, 0.85))
		draw_rect(box, Color(1.0, 0.82, 0.36, 0.9), false, 1.5)
		var base := Vector2(cx - w * 0.5, cy + fs * 0.3)
		draw_string(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.9, 0.6))


# --- Ambiance ----------------------------------------------------------------------

func _build_ambience() -> void:
	var cm := CanvasModulate.new()
	cm.name = "AmbientTint"
	cm.color = _cfg_c("ambient_surface", Color(1.0, 0.93, 0.84))
	add_child(cm)
	var glows := GlowLayer.new()
	glows.name = "Glows"
	glows.glows = _glows
	glows.strength = Balance.get_float("world_builder", "glow_strength", 1.0) * _cfg_f("glow_strength", 1.0)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glows.material = mat
	glows.z_index = 45
	glows.z_as_relative = false
	add_child(glows)


class GlowLayer extends Node2D:
	var glows: Array = []
	var strength: float = 1.0

	func _draw() -> void:
		for g: Array in glows:
			var p: Vector2 = g[0]
			var rad: float = g[1]
			var k: float = float(g[2]) * strength
			var c: Color = g[3]
			draw_circle(p, rad, Color(c, 0.14 * k))
			draw_circle(p, rad * 0.55, Color(c, 0.16 * k))
			draw_circle(p, rad * 0.25, Color(c.lerp(Color.WHITE, 0.4), 0.2 * k))


# --- Butin : conteneurs et cachettes propres au biome ------------------------------

func _on_child_entered(n: Node) -> void:
	if n.name == "Loot" and not n.child_entered_tree.is_connected(_patch_loot):
		n.child_entered_tree.connect(_patch_loot)


func _patch_loot(n: Node) -> void:
	if n is LootContainer:
		var c := n as LootContainer
		var want: StringName = _container_kind_at.get(c.cell, &"")
		if want != &"" and want != c.kind and not LootContainer.is_known_kind(want):
			c.kind = want
			c.name = "Container_%s" % String(want)
			c.ready.connect(_patch_def.bind(c, CONTAINER_DEFS.get(want, {})), CONNECT_ONE_SHOT)
	elif n is HidingSpot:
		var h := n as HidingSpot
		var want2: StringName = _hide_kind_at.get(h.cell, &"")
		if want2 != &"" and want2 != h.kind and not HidingSpot.DEFS.has(want2):
			h.kind = want2
			h.name = "Hide_%s" % String(want2)
			h.ready.connect(_patch_def.bind(h, HIDE_DEFS.get(want2, {})), CONNECT_ONE_SHOT)


static func _patch_def(n: Node, def: Dictionary) -> void:
	if def.is_empty() or not is_instance_valid(n):
		return
	var cur: Variant = n.get("_def")
	if cur is Dictionary:
		var d: Dictionary = (cur as Dictionary).duplicate()
		d.merge(def, true)
		n.set("_def", d)
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
