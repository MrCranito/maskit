class_name WorldBuilder
extends Node2D
## Constructeur du décor d'un étage (module « Décor », cf. docs/CONVENTIONS.md, phase 3).
##   WorldBuilder.build(layout, world) -> WorldBuilder (Node2D racine, y_sort activé)
## Contient : sol (chunks dessinés une fois, textures répétées), murs 3/4 avec
## collisions fusionnées (couche world), porches, toits (BuildingRoof, z 50),
## portes (DoorNode), escaliers (Area2D, meta `stairs`), décors (WorldProp),
## marqueurs d'extraction.
##
## Modèle 3/4 : chaque case WALL reste dans sa case. Si la case au sud est
## praticable, la partie basse de la case montre la FACE AVANT du mur (hauteur
## `wall_height`), le haut montre le DESSUS (plus sombre). Les murs ne débordent
## jamais sur le sol praticable, donc ils peuvent être dessinés derrière tous les
## personnages (nœud Walls en z 10, y = 0 → trié en premier).
## Lumière : soleil couchant à l'ouest → arêtes ouest éclairées, ombres bleu nuit
## portées vers le bas-droite.

signal stairs_entered(stairs: FloorLayout.Stairs)

const TS := float(FloorLayout.TILE_SIZE)
const LAYER_WORLD := 1
const MASK_PLAYER := 2
const DOOR_SCENE_PATH := "res://scenes/dungeon/door.tscn"
const TEX_SAND: Texture2D = preload("res://assets/sprites/far_west/tiles/sand.svg")
const TEX_PLANKS: Texture2D = preload("res://assets/sprites/far_west/tiles/planks.svg")
const TEX_MINE: Texture2D = preload("res://assets/sprites/far_west/tiles/mine_floor.svg")
## Taille (unités monde) couverte par une répétition de texture de sol.
const TILE_TEX_WORLD := 256.0
const OUTLINE := Color(0.09, 0.05, 0.08)

## Matériaux de sol
enum Ground { VOID, SAND, PLANKS, MINE }
## Matériaux de mur
enum WallMat { WOOD, ADOBE, FENCE, ROCK }

const DEFAULT_PALETTE := {
	"void": Color(0.07, 0.1, 0.18),
	"shadow": Color(0.12, 0.15, 0.32),
	"wood": Color(0.6, 0.47, 0.34),
	"wood_weathered": Color(0.68, 0.6, 0.5),
	"adobe": Color(0.78, 0.52, 0.36),
	"wall": Color(0.38, 0.25, 0.19),
	"mine_wall": Color(0.24, 0.18, 0.15),
	"extraction": Color(0.3, 0.85, 0.45, 0.45),
}

var layout: FloorLayout = null
var palette: Dictionary = {}
var wall_height: float = 52.0

var _doors: Array[DoorNode] = []
var _stairs_areas: Array[Area2D] = []
var _roofs: Array[BuildingRoof] = []
var _props: Array[WorldProp] = []
var _wall_body: StaticBody2D = null
var _stairs_cooldown: float = 0.5
## Grilles précalculées (index y * w + x) : id de salle (-1) et id de bâtiment (-1).
var _room_grid: PackedInt32Array = PackedInt32Array()
var _building_grid: PackedInt32Array = PackedInt32Array()


## Construit l'étage complet. `world` : WorldData (ou null → palette par défaut).
static func build(p_layout: FloorLayout, world: Resource = null) -> WorldBuilder:
	var root := WorldBuilder.new()
	root.name = "World"
	root.layout = p_layout
	root._build(world)
	return root


# --- API -----------------------------------------------------------------------

func get_doors() -> Array[DoorNode]:
	return _doors


func get_stairs_areas() -> Array[Area2D]:
	return _stairs_areas


func get_roofs() -> Array[BuildingRoof]:
	return _roofs


func get_props() -> Array[WorldProp]:
	return _props


## Corps statique des murs (couche world, rectangles fusionnés).
func get_wall_body() -> StaticBody2D:
	return _wall_body


## Salle contenant la position monde `pos` (la plus petite si chevauchement), ou null.
func get_room_at_world(pos: Vector2) -> FloorLayout.Room:
	if layout == null:
		return null
	var c := FloorLayout.world_to_cell(pos)
	if not layout.in_bounds(c):
		return null
	var id := _room_grid[c.y * layout.size.x + c.x]
	return layout.get_room(id) if id >= 0 else null


## Bâtiment dont l'emprise contient `pos` (monde), ou null.
func get_building_at_world(pos: Vector2) -> FloorLayout.Building:
	if layout == null:
		return null
	var c := FloorLayout.world_to_cell(pos)
	if not layout.in_bounds(c):
		return null
	var id := _building_grid[c.y * layout.size.x + c.x]
	return layout.buildings[id] if id >= 0 else null


## Ignore les entrées dans les escaliers pendant `sec` secondes (arrivée sur un étage).
func set_stairs_cooldown(sec: float) -> void:
	_stairs_cooldown = maxf(sec, 0.0)


func _process(delta: float) -> void:
	if _stairs_cooldown > 0.0:
		_stairs_cooldown = maxf(_stairs_cooldown - delta, 0.0)


# --- Construction ----------------------------------------------------------------

func _build(world: Resource) -> void:
	y_sort_enabled = true
	if layout == null:
		push_warning("WorldBuilder: layout null.")
		return
	_read_palette(world)
	wall_height = Balance.get_float("world_builder", "wall_height", 52.0)
	_stairs_cooldown = Balance.get_float("world_builder", "stairs_cooldown", 0.5)
	_build_grids()
	_build_ground()
	_build_walls()
	_build_porches()
	_build_doors()
	_build_stairs()
	_build_props()
	_build_extraction()
	_build_roofs()


func _read_palette(world: Resource) -> void:
	palette = DEFAULT_PALETTE.duplicate()
	if world == null:
		return
	var wp: Variant = world.get("palette")
	if wp is Dictionary:
		for k: Variant in (wp as Dictionary).keys():
			var v: Variant = (wp as Dictionary)[k]
			if v is Color:
				palette[String(k)] = v


func col(key: String) -> Color:
	var c: Variant = palette.get(key, null)
	return c if c is Color else Color.MAGENTA


func _build_grids() -> void:
	var n := layout.size.x * layout.size.y
	_room_grid.resize(n)
	_room_grid.fill(-1)
	_building_grid.resize(n)
	_building_grid.fill(-1)
	# Salles triées de la plus grande à la plus petite : la plus petite gagne.
	var rooms := layout.rooms.duplicate()
	rooms.sort_custom(func(a: FloorLayout.Room, b: FloorLayout.Room) -> bool:
		return a.rect.get_area() > b.rect.get_area())
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


func building_id_at(c: Vector2i) -> int:
	if not layout.in_bounds(c):
		return -1
	return _building_grid[c.y * layout.size.x + c.x]


func is_mine_cell(c: Vector2i) -> bool:
	if layout.floor_index < 0:
		return true
	var rid := room_id_at(c)
	if rid >= 0:
		var r := layout.get_room(rid)
		if r != null and (r.tags.has("mine") or r.tags.has("tunnel")):
			return true
	return false


func ground_at(c: Vector2i) -> int:
	var t := layout.get_tile(c)
	match t:
		FloorLayout.Tile.VOID, FloorLayout.Tile.WALL:
			return Ground.VOID
		FloorLayout.Tile.STREET:
			return Ground.MINE if layout.floor_index < 0 else Ground.SAND
		_:
			return Ground.MINE if is_mine_cell(c) else Ground.PLANKS


func wall_mat_at(c: Vector2i) -> int:
	if layout.floor_index < 0:
		return WallMat.ROCK
	var bid := building_id_at(c)
	if bid < 0:
		return WallMat.FENCE
	match layout.buildings[bid].archetype:
		&"bank", &"church", &"sheriff":
			return WallMat.ADOBE
		&"mine":
			return WallMat.ROCK if is_mine_cell(c + Vector2i.DOWN) else WallMat.WOOD
		_:
			return WallMat.WOOD


## Hash déterministe [0, 1) d'une case (variations de décor).
static func hash01(x: int, y: int, s: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


# --- Sol -------------------------------------------------------------------------

func _build_ground() -> void:
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.z_index = 0
	add_child(ground)
	var chunk := int(Balance.get_value("world_builder", "chunk_cells", 16))
	chunk = maxi(chunk, 4)
	for cy: int in range(0, layout.size.y, chunk):
		for cx: int in range(0, layout.size.x, chunk):
			var d := GroundChunk.new()
			d.name = "Chunk_%d_%d" % [cx, cy]
			d.builder = self
			d.cells = Rect2i(cx, cy, mini(chunk, layout.size.x - cx), mini(chunk, layout.size.y - cy))
			d.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			d.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			ground.add_child(d)
	var decals := GroundDecals.new()
	decals.name = "Decals"
	decals.builder = self
	ground.add_child(decals)


## Morceau de sol (chunk) : textures répétées par segments, détails, ombres.
class GroundChunk extends Node2D:
	var builder: WorldBuilder = null
	var cells: Rect2i = Rect2i()

	func _draw() -> void:
		var L := builder.layout
		var void_col := builder.col("void")
		var shadow := builder.col("shadow")
		for y: int in range(cells.position.y, cells.end.y):
			var x := cells.position.x
			while x < cells.end.x:
				var g := builder.ground_at(Vector2i(x, y))
				var tint := builder._ground_tint(Vector2i(x, y), g)
				var x1 := x + 1
				while x1 < cells.end.x and builder.ground_at(Vector2i(x1, y)) == g \
						and builder._ground_tint(Vector2i(x1, y), g) == tint:
					x1 += 1
				var r := Rect2(Vector2(x, y) * TS, Vector2(x1 - x, 1) * TS)
				_draw_ground_run(r, g, tint, void_col)
				x = x1
		# Détails et ombres, case par case.
		for y: int in range(cells.position.y, cells.end.y):
			for x: int in range(cells.position.x, cells.end.x):
				var c := Vector2i(x, y)
				var t := L.get_tile(c)
				if t == FloorLayout.Tile.VOID:
					_draw_void_edge(c)
					continue
				if not FloorLayout.is_walkable_tile(t):
					continue
				var g := builder.ground_at(c)
				if g == Ground.SAND:
					_draw_street_details(c)
				elif g == Ground.MINE:
					_draw_mine_details(c)
				_draw_wall_shadows(c, shadow)

	func _draw_ground_run(r: Rect2, g: int, tint: Color, void_col: Color) -> void:
		var tex: Texture2D = null
		match g:
			Ground.SAND:
				tex = TEX_SAND
			Ground.PLANKS:
				tex = TEX_PLANKS
			Ground.MINE:
				tex = TEX_MINE
			_:
				if builder.layout.floor_index == 0:
					tex = TEX_SAND
				elif builder.layout.floor_index < 0:
					tex = TEX_MINE
		if tex != null:
			var k := float(tex.get_width()) / TILE_TEX_WORLD
			draw_texture_rect_region(tex, r, Rect2(r.position * k, r.size * k), tint)
		else:
			draw_rect(r, void_col)

	func _draw_street_details(c: Vector2i) -> void:
		var o := Vector2(c) * TS
		var h1 := WorldBuilder.hash01(c.x, c.y, 1)
		if h1 < 0.16:
			# Touffe d'herbe sèche.
			var p := o + Vector2(10.0 + WorldBuilder.hash01(c.x, c.y, 2) * 44.0, 16.0 + WorldBuilder.hash01(c.x, c.y, 3) * 40.0)
			draw_set_transform(p + Vector2(4, 2), 0.0, Vector2(1.0, 0.35))
			draw_circle(Vector2.ZERO, 9.0, Color(0.12, 0.15, 0.32, 0.3))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for i: int in 7:
				var a := -PI * 0.5 + (float(i) - 3.0) * 0.28
				var l := 10.0 + float((i * 5) % 7)
				var tip := p + Vector2(cos(a), sin(a)) * l
				draw_line(p, tip, Color(0.36, 0.3, 0.14), 3.0)
				draw_line(p, tip, Color(0.82, 0.72, 0.36) if i % 2 == 0 else Color(0.66, 0.6, 0.28), 1.6)
		elif h1 < 0.36:
			# Cailloux (ombre portée bas-droite, reflet haut-gauche).
			for i: int in 3:
				var hp := WorldBuilder.hash01(c.x, c.y, 10 + i)
				var p2 := o + Vector2(8.0 + hp * 48.0, 10.0 + WorldBuilder.hash01(c.x, c.y, 20 + i) * 44.0)
				var rr := 2.5 + hp * 3.5
				draw_set_transform(p2 + Vector2(1.5, 1.5), 0.0, Vector2(1.0, 0.7))
				draw_circle(Vector2.ZERO, rr + 1.2, Color(0.12, 0.15, 0.32, 0.45))
				draw_set_transform(p2, 0.0, Vector2(1.0, 0.7))
				draw_circle(Vector2.ZERO, rr + 1.0, OUTLINE)
				draw_circle(Vector2.ZERO, rr, Color(0.7, 0.6, 0.52))
				draw_circle(Vector2(-rr * 0.3, -rr * 0.3), rr * 0.45, Color(0.92, 0.82, 0.68))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif h1 < 0.4:
			# Fissure de terre sèche.
			var p3 := o + Vector2(14.0, 20.0 + h1 * 60.0)
			var pts := PackedVector2Array([p3, p3 + Vector2(10, 4), p3 + Vector2(18, -2), p3 + Vector2(30, 5), p3 + Vector2(38, 1)])
			draw_polyline(pts, Color(0.5, 0.33, 0.2, 0.7), 1.6)

	## Bord du vide (désert hors-carte, talus) : liseré sombre + cailloux, ombre bleue.
	func _draw_void_edge(c: Vector2i) -> void:
		var L := builder.layout
		var o := Vector2(c) * TS
		var shadow := builder.col("shadow")
		var dirs := {Vector2i.UP: [o, o + Vector2(TS, 0)], Vector2i.DOWN: [o + Vector2(0, TS), o + Vector2(TS, TS)],
			Vector2i.LEFT: [o, o + Vector2(0, TS)], Vector2i.RIGHT: [o + Vector2(TS, 0), o + Vector2(TS, TS)]}
		var any := false
		for d: Vector2i in dirs:
			if not FloorLayout.is_walkable_tile(L.get_tile(c + d)):
				continue
			any = true
			var seg: Array = dirs[d]
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var inward := -Vector2(d) * 10.0
			draw_polygon(PackedVector2Array([a, b, b + inward, a + inward]),
				PackedColorArray([Color(shadow, 0.55), Color(shadow, 0.55), Color(shadow, 0.0), Color(shadow, 0.0)]))
			draw_line(a, b, Color(0.2, 0.12, 0.14, 0.9), 3.0)
			for i: int in 3:
				var f := (float(i) + 0.3 + WorldBuilder.hash01(c.x, c.y, 90 + i) * 0.4) / 3.0
				var p := a.lerp(b, f) + inward * 0.6
				var rr := 3.5 + WorldBuilder.hash01(c.x + i, c.y, 91) * 4.0
				draw_circle(p, rr + 1.2, OUTLINE)
				draw_circle(p, rr, Color(0.56, 0.44, 0.44))
				draw_circle(p + Vector2(-1, -1), rr * 0.45, Color(0.78, 0.64, 0.58))
		if not any and builder.layout.floor_index == 0 and WorldBuilder.hash01(c.x, c.y, 95) < 0.05:
			# Buisson sec / rocher isolé dans le désert hors carte.
			var p2 := o + Vector2(32, 36)
			draw_set_transform(p2 + Vector2(6, 3), 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, 12.0, Color(shadow, 0.35))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_circle(p2, 9.0, OUTLINE)
			draw_circle(p2, 7.5, Color(0.5, 0.4, 0.42))
			draw_circle(p2 + Vector2(-2, -2), 3.5, Color(0.7, 0.58, 0.54))

	func _draw_mine_details(c: Vector2i) -> void:
		var h1 := WorldBuilder.hash01(c.x, c.y, 5)
		if h1 < 0.08:
			var p := Vector2(c) * TS + Vector2(20.0 + h1 * 200.0, 30.0)
			draw_circle(p, 3.0, Color(1.0, 0.82, 0.3, 0.85))
			draw_circle(p + Vector2(-1, -1), 1.2, Color(1.0, 0.96, 0.7))

	func _draw_wall_shadows(c: Vector2i, shadow: Color) -> void:
		var L := builder.layout
		var o := Vector2(c) * TS
		var n := L.get_tile(c + Vector2i.UP)
		var w := L.get_tile(c + Vector2i.LEFT)
		var nw := L.get_tile(c + Vector2i(-1, -1))
		var a := Color(shadow, 0.5)
		var z := Color(shadow, 0.0)
		if FloorLayout.is_opaque_tile(n):
			# Ombre portée du mur au nord, plus longue côté rue.
			var depth := 26.0 if L.get_tile(c) == FloorLayout.Tile.STREET else 18.0
			draw_polygon(PackedVector2Array([o, o + Vector2(TS, 0), o + Vector2(TS, depth), o + Vector2(0, depth)]),
				PackedColorArray([a, a, z, z]))
			draw_line(o + Vector2(0, 1), o + Vector2(TS, 1), Color(shadow, 0.6), 2.0)
		if FloorLayout.is_opaque_tile(w):
			draw_polygon(PackedVector2Array([o, o + Vector2(14, 0), o + Vector2(14, TS), o + Vector2(0, TS)]),
				PackedColorArray([Color(shadow, 0.4), z, z, Color(shadow, 0.4)]))
		elif FloorLayout.is_opaque_tile(nw) and not FloorLayout.is_opaque_tile(n):
			draw_polygon(PackedVector2Array([o, o + Vector2(14, 0), o + Vector2(0, 18)]),
				PackedColorArray([Color(shadow, 0.35), z, z]))


## Teinte du sol selon la salle (bâtiment) ; légère variation par case pour la rue.
func _ground_tint(c: Vector2i, g: int) -> Color:
	match g:
		Ground.VOID:
			if layout.floor_index == 0:
				return Color(0.4, 0.33, 0.45)
			return Color(0.3, 0.26, 0.36)
		Ground.PLANKS:
			var bid := building_id_at(c)
			if bid >= 0:
				match layout.buildings[bid].archetype:
					&"bank":
						return Color(0.82, 0.74, 0.74)
					&"church":
						return Color(1.08, 1.0, 0.92)
					&"sheriff":
						return Color(0.86, 0.84, 0.86)
					&"stable":
						return Color(1.05, 0.95, 0.78)
					&"hotel":
						return Color(0.9, 0.8, 0.84)
			return Color.WHITE
		_:
			return Color.WHITE


## Ornières de roues sur les grandes rues + planches de trottoir (dessinés une fois).
class GroundDecals extends Node2D:
	var builder: WorldBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var full := Rect2(Vector2.ZERO, Vector2(L.size) * TS)
		var shadow := builder.col("shadow")
		if L.floor_index < 0:
			# Mine : vignettage bleu nuit léger.
			draw_polygon(PackedVector2Array([full.position, Vector2(full.end.x, 0), full.end, Vector2(0, full.end.y)]),
				PackedColorArray([Color(shadow, 0.1), Color(shadow, 0.25), Color(shadow, 0.3), Color(shadow, 0.15)]))
			return
		# Lumière de coucher de soleil : chaud au nord-ouest, violet au sud-est.
		draw_polygon(PackedVector2Array([full.position, Vector2(full.end.x, 0), full.end, Vector2(0, full.end.y)]),
			PackedColorArray([Color(1.0, 0.62, 0.3, 0.14), Color(0.95, 0.45, 0.45, 0.08),
				Color(0.42, 0.26, 0.55, 0.16), Color(0.9, 0.5, 0.4, 0.06)]))
		# Flaques de lumière de lampe à pétrole dans les intérieurs.
		for room: FloorLayout.Room in L.rooms:
			if room.outdoor or room.rect.get_area() < 6:
				continue
			var rr := Rect2(Vector2(room.rect.position) * TS, Vector2(room.rect.size) * TS)
			var rad := minf(rr.size.x, rr.size.y) * 0.5
			var cc := rr.get_center()
			for k: int in 4:
				var f := 1.0 - float(k) * 0.22
				draw_circle(cc, rad * f, Color(1.0, 0.72, 0.38, 0.05))
			# Coins assombris.
			draw_polygon(PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]),
				PackedColorArray([Color(shadow, 0.18), Color(shadow, 0.24), Color(shadow, 0.3), Color(shadow, 0.22)]))
		# Ombres longues portées par les bâtiments vers l'est (soleil à l'ouest).
		var reach := TS * 0.9
		for b: FloorLayout.Building in L.buildings:
			var br := Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
			var p0 := Vector2(br.end.x, br.position.y + TS * 0.4)
			var p1 := Vector2(br.end.x, br.end.y)
			draw_polygon(PackedVector2Array([p0, p0 + Vector2(reach, TS * 0.35), p1 + Vector2(reach, TS * 0.2), p1]),
				PackedColorArray([Color(shadow, 0.42), Color(shadow, 0.0), Color(shadow, 0.0), Color(shadow, 0.42)]))
		if L.floor_index != 0:
			return
		for r: FloorLayout.Room in L.rooms:
			if not r.outdoor:
				continue
			var rr := Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS)
			if r.rect.size.x >= 8 and r.rect.size.x >= r.rect.size.y * 2:
				for off: float in [-0.17, 0.17]:
					_rut(rr.position + Vector2(0, rr.size.y * (0.5 + off)), Vector2(rr.size.x, 0), r.id)
			elif r.rect.size.y >= 8 and r.rect.size.y >= r.rect.size.x * 2 and r.rect.size.x >= 3:
				for off2: float in [-0.2, 0.2]:
					_rut(rr.position + Vector2(rr.size.x * (0.5 + off2), 0), Vector2(0, rr.size.y), r.id + 7)

	func _rut(from: Vector2, span: Vector2, s: int) -> void:
		var steps := int(span.length() / 24.0)
		if steps < 2:
			return
		var side := Vector2(-span.y, span.x).normalized()
		var pts := PackedVector2Array()
		for i: int in steps + 1:
			var f := float(i) / float(steps)
			var wob := sin(f * 9.0 + float(s)) * 4.0 + (WorldBuilder.hash01(i, s, 3) - 0.5) * 3.0
			pts.append(from + span * f + side * wob)
		var dark := Color(0.55, 0.36, 0.22, 0.35)
		var light := Color(1.0, 0.86, 0.6, 0.35)
		draw_polyline(pts, dark, 9.0)
		var pts2 := PackedVector2Array()
		for p: Vector2 in pts:
			pts2.append(p + side * -5.5)
		draw_polyline(pts2, light, 2.0)
		var pts3 := PackedVector2Array()
		for p: Vector2 in pts:
			pts3.append(p + side * 2.0)
		draw_polyline(pts3, Color(0.45, 0.28, 0.18, 0.3), 3.0)


# --- Murs ------------------------------------------------------------------------

func _build_walls() -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	walls.z_index = 10
	walls.position = Vector2.ZERO
	add_child(walls)
	var chunk := maxi(int(Balance.get_value("world_builder", "chunk_cells", 16)), 4)
	for cy: int in range(0, layout.size.y, chunk):
		for cx: int in range(0, layout.size.x, chunk):
			var d := WallChunk.new()
			d.name = "WallChunk_%d_%d" % [cx, cy]
			d.builder = self
			d.cells = Rect2i(cx, cy, mini(chunk, layout.size.x - cx), mini(chunk, layout.size.y - cy))
			walls.add_child(d)
	_wall_body = StaticBody2D.new()
	_wall_body.name = "WallBodies"
	_wall_body.collision_layer = LAYER_WORLD
	_wall_body.collision_mask = 0
	walls.add_child(_wall_body)
	for r: Rect2i in merge_cells(layout, func(t: int) -> bool: return FloorLayout.is_opaque_tile(t)):
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(r.size) * TS
		cs.shape = shape
		cs.position = (Vector2(r.position) + Vector2(r.size) * 0.5) * TS
		_wall_body.add_child(cs)
	# Bord de carte : ceinture de sécurité autour de la grille.
	var full := Rect2(Vector2.ZERO, Vector2(layout.size) * TS)
	for side: Rect2 in [Rect2(full.position - Vector2(TS, TS), Vector2(full.size.x + 2.0 * TS, TS)),
			Rect2(Vector2(-TS, full.end.y), Vector2(full.size.x + 2.0 * TS, TS)),
			Rect2(Vector2(-TS, 0), Vector2(TS, full.size.y)),
			Rect2(Vector2(full.end.x, 0), Vector2(TS, full.size.y))]:
		var cs2 := CollisionShape2D.new()
		var shape2 := RectangleShape2D.new()
		shape2.size = side.size
		cs2.shape = shape2
		cs2.position = side.get_center()
		_wall_body.add_child(cs2)


## Fusionne en rectangles (gloutonnement : segments par ligne, prolongés vers le bas)
## les cases dont la tuile satisfait `predicate(tile) -> bool`.
static func merge_cells(p_layout: FloorLayout, predicate: Callable) -> Array[Rect2i]:
	var w := p_layout.size.x
	var h := p_layout.size.y
	var ok := PackedByteArray()
	ok.resize(w * h)
	for i: int in w * h:
		ok[i] = 1 if bool(predicate.call(p_layout.tiles[i])) else 0
	var used := PackedByteArray()
	used.resize(w * h)
	var out: Array[Rect2i] = []
	for y: int in h:
		var x := 0
		while x < w:
			var i0 := y * w + x
			if used[i0] != 0 or ok[i0] == 0:
				x += 1
				continue
			var x1 := x
			while x1 < w and used[y * w + x1] == 0 and ok[y * w + x1] != 0:
				x1 += 1
			var y1 := y + 1
			while y1 < h:
				var full := true
				for xx: int in range(x, x1):
					var j := y1 * w + xx
					if used[j] != 0 or ok[j] == 0:
						full = false
						break
				if not full:
					break
				y1 += 1
			for yy: int in range(y, y1):
				for xx: int in range(x, x1):
					used[yy * w + xx] = 1
			out.append(Rect2i(x, y, x1 - x, y1 - y))
			x = x1
	return out


## Côté de façade et position de la porte d'entrée d'un bâtiment.
## Renvoie {bottom: bool, door_x: float (NAN si pas de porte sur rue), has_street: bool}.
func facade_info(b: FloorLayout.Building) -> Dictionary:
	var info := {"bottom": true, "door_x": NAN, "has_street": false}
	for did: int in b.door_ids:
		if did < 0 or did >= layout.doors.size():
			continue
		var d := layout.doors[did]
		var ra := layout.get_room(d.room_a)
		var rb := layout.get_room(d.room_b)
		var outside := (ra != null and ra.outdoor) or (rb != null and rb.outdoor)
		if not outside or d.vertical:
			continue
		info["has_street"] = true
		info["bottom"] = d.cell.y >= b.rect.end.y - 1
		info["door_x"] = (float(d.cell.x) + 0.5) * TS
		break
	return info


## Morceau de murs : dessus sombre + face avant (bois, adobe, palissade, roche).
class WallChunk extends Node2D:
	var builder: WorldBuilder = null
	var cells: Rect2i = Rect2i()

	func _draw() -> void:
		var L := builder.layout
		for y: int in range(cells.position.y, cells.end.y):
			for x: int in range(cells.position.x, cells.end.x):
				var c := Vector2i(x, y)
				if L.get_tile(c) == FloorLayout.Tile.WALL:
					_draw_wall_cell(c)

	func _is_wall(c: Vector2i) -> bool:
		var t := builder.layout.get_tile(c)
		return t == FloorLayout.Tile.WALL or t == FloorLayout.Tile.DOOR

	func _draw_wall_cell(c: Vector2i) -> void:
		var L := builder.layout
		var wh := builder.wall_height
		var mat := builder.wall_mat_at(c)
		var south := L.get_tile(c + Vector2i.DOWN)
		var face := FloorLayout.is_walkable_tile(south)
		var o := Vector2(c) * TS
		var cap_h := TS - wh if face else TS
		var cap := Rect2(o, Vector2(TS, cap_h))
		var top_col := _cap_color(mat)
		draw_rect(cap, top_col)
		# Texture du dessus.
		match mat:
			WallMat.ROCK:
				for i: int in 3:
					var hp := WorldBuilder.hash01(c.x, c.y, 40 + i)
					var p := o + Vector2(8.0 + hp * 48.0, 6.0 + WorldBuilder.hash01(c.x, c.y, 50 + i) * maxf(cap_h - 12.0, 1.0))
					draw_circle(p, 4.0 + hp * 5.0, top_col.lightened(0.12))
					draw_circle(p + Vector2(2, 2), 3.0 + hp * 3.0, top_col.darkened(0.2))
			WallMat.ADOBE:
				if cap_h > 20.0 and WorldBuilder.hash01(c.x, c.y, 41) < 0.3:
					draw_line(o + Vector2(14, 12), o + Vector2(26, 22), top_col.darkened(0.25), 1.4)
			_:
				# Planches du dessus (dans le sens du mur).
				var horiz := _is_wall(c + Vector2i.LEFT) or _is_wall(c + Vector2i.RIGHT)
				if horiz and not (_is_wall(c + Vector2i.UP) and _is_wall(c + Vector2i.DOWN)):
					var yy := o.y + 5.0
					while yy < o.y + cap_h - 2.0:
						draw_line(Vector2(o.x, yy), Vector2(o.x + TS, yy), top_col.darkened(0.22), 1.2)
						yy += 9.0
				else:
					var xx := o.x + 10.0
					while xx < o.x + TS:
						draw_line(Vector2(xx, o.y), Vector2(xx, o.y + cap_h), top_col.darkened(0.22), 1.2)
						xx += 11.0
		# Arêtes : contour sombre là où le dessus touche autre chose qu'un mur ;
		# liseré clair côté ouest/nord (lumière rasante du couchant).
		var lit := top_col.lightened(0.35)
		if not _is_wall(c + Vector2i.UP):
			draw_line(o + Vector2(0, 2), o + Vector2(TS, 2), lit, 3.0)
			draw_line(o, o + Vector2(TS, 0), OUTLINE, 2.5)
		if not _is_wall(c + Vector2i.LEFT):
			draw_line(o + Vector2(2, 0), o + Vector2(2, cap_h), lit, 3.0)
			draw_line(o, o + Vector2(0, TS), OUTLINE, 2.5)
		if not _is_wall(c + Vector2i.RIGHT):
			draw_line(o + Vector2(TS - 3, 0), o + Vector2(TS - 3, cap_h), top_col.darkened(0.35), 4.0)
			draw_line(o + Vector2(TS, 0), o + Vector2(TS, TS), OUTLINE, 2.5)
		if face:
			_draw_face(c, Rect2(o + Vector2(0, cap_h), Vector2(TS, wh)), mat)
			draw_line(o + Vector2(0, cap_h), o + Vector2(TS, cap_h), OUTLINE, 2.0)

	func _cap_color(mat: int) -> Color:
		match mat:
			WallMat.ADOBE:
				return builder.col("adobe").darkened(0.38)
			WallMat.ROCK:
				return builder.col("mine_wall").darkened(0.1)
			WallMat.FENCE:
				return builder.col("wall").darkened(0.15)
			_:
				return builder.col("wall")

	func _draw_face(c: Vector2i, f: Rect2, mat: int) -> void:
		var L := builder.layout
		var south_c := c + Vector2i.DOWN
		var bid := builder.building_id_at(c)
		var south_rid := builder.room_id_at(south_c)
		var south_room: FloorLayout.Room = L.get_room(south_rid) if south_rid >= 0 else null
		var interior := mat != WallMat.ROCK and south_room != null and not south_room.outdoor \
			and builder.building_id_at(south_c) >= 0 and L.get_tile(south_c) != FloorLayout.Tile.STREET
		var west_open := not _is_wall(c + Vector2i.LEFT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(-1, 1)))
		var east_open := not _is_wall(c + Vector2i.RIGHT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(1, 1)))
		if interior:
			_face_interior(c, f, bid)
		else:
			match mat:
				WallMat.ADOBE:
					_face_adobe(c, f)
				WallMat.FENCE:
					_face_fence(c, f)
				WallMat.ROCK:
					_face_rock(c, f)
				_:
					_face_wood(c, f)
			if bid >= 0 and _is_window_cell(c, bid):
				_draw_window(f, L.buildings[bid].archetype)
		# Bas du mur : occlusion bleue + contour net.
		draw_polygon(PackedVector2Array([f.position + Vector2(0, f.size.y - 10), f.position + Vector2(TS, f.size.y - 10), f.end, f.position + Vector2(0, f.size.y)]),
			PackedColorArray([Color(0.1, 0.12, 0.3, 0.0), Color(0.1, 0.12, 0.3, 0.0), Color(0.1, 0.12, 0.3, 0.45), Color(0.1, 0.12, 0.3, 0.45)]))
		draw_line(Vector2(f.position.x, f.end.y), f.end, OUTLINE, 2.5)
		if west_open:
			draw_line(f.position, Vector2(f.position.x, f.end.y), OUTLINE, 2.5)
		if east_open:
			draw_line(Vector2(f.end.x, f.position.y), f.end, OUTLINE, 2.5)
			# Arête est dans l'ombre.
			draw_rect(Rect2(f.end.x - 6.0, f.position.y, 6.0, f.size.y), Color(0.1, 0.12, 0.3, 0.3))

	func _grad(r: Rect2, a: Color, b: Color) -> void:
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([a, a, b, b]))

	func _face_wood(c: Vector2i, f: Rect2) -> void:
		var base := builder.col("wood_weathered")
		var bid := builder.building_id_at(c)
		if bid >= 0:
			match builder.layout.buildings[bid].archetype:
				&"saloon":
					base = Color(0.74, 0.5, 0.34)
				&"store":
					base = Color(0.62, 0.66, 0.56)
				&"hotel":
					base = Color(0.72, 0.56, 0.6)
				&"stable":
					base = Color(0.7, 0.42, 0.3)
		_grad(f, base.lightened(0.12), base.darkened(0.28))
		# Clins horizontaux (bardage à recouvrement).
		var y := f.position.y + 9.0
		while y < f.end.y - 4.0:
			draw_line(Vector2(f.position.x, y), Vector2(f.end.x, y), base.darkened(0.42), 1.6)
			draw_line(Vector2(f.position.x, y + 1.5), Vector2(f.end.x, y + 1.5), base.lightened(0.2), 1.0)
			y += 9.0
		# Joints de planches décalés.
		var jx := f.position.x + 10.0 + WorldBuilder.hash01(c.x, c.y, 60) * 40.0
		draw_line(Vector2(jx, f.position.y + 9), Vector2(jx, f.position.y + 18), base.darkened(0.42), 1.2)
		# Liseré haut (corniche).
		draw_rect(Rect2(f.position, Vector2(TS, 5.0)), base.lightened(0.3))
		draw_line(f.position + Vector2(0, 5), f.position + Vector2(TS, 5), OUTLINE, 1.4)

	func _face_adobe(c: Vector2i, f: Rect2) -> void:
		var base := builder.col("adobe")
		var bid := builder.building_id_at(c)
		if bid >= 0 and builder.layout.buildings[bid].archetype == &"church":
			base = Color(0.94, 0.84, 0.7)
		elif bid >= 0 and builder.layout.buildings[bid].archetype == &"bank":
			base = Color(0.9, 0.7, 0.5)
		_grad(f, base.lightened(0.1), base.darkened(0.22))
		# Enduit écaillé et fissures.
		var h := WorldBuilder.hash01(c.x, c.y, 61)
		if h < 0.4:
			var p := f.position + Vector2(10.0 + h * 80.0, 16.0)
			draw_rect(Rect2(p, Vector2(14, 8)), base.darkened(0.18))
			draw_line(p + Vector2(0, 2), p + Vector2(3, 0), base.darkened(0.35), 1.0)
			for i: int in 2:
				draw_rect(Rect2(p + Vector2(2 + i * 6, 2), Vector2(5, 3)), Color(0.66, 0.36, 0.26))
		elif h < 0.7:
			var q := f.position + Vector2(20.0 + h * 20.0, 10.0)
			draw_polyline(PackedVector2Array([q, q + Vector2(4, 8), q + Vector2(1, 15), q + Vector2(6, 24)]), base.darkened(0.4), 1.2)
		# Bandeau haut + vigas.
		draw_rect(Rect2(f.position, Vector2(TS, 6.0)), base.lightened(0.22))
		draw_line(f.position + Vector2(0, 6), f.position + Vector2(TS, 6), base.darkened(0.4), 1.4)
		if (c.x % 2) == 0:
			var v := Rect2(f.position + Vector2(26, 8), Vector2(10, 7))
			draw_rect(Rect2(v.position + Vector2(2, 3), v.size), Color(0.1, 0.12, 0.3, 0.4))
			draw_rect(v, Color(0.44, 0.27, 0.16))
			draw_rect(v, OUTLINE, false, 1.2)

	func _face_fence(c: Vector2i, f: Rect2) -> void:
		# Palissade : poteaux pointus sur fond d'ombre (on voit à travers).
		draw_rect(f, Color(0.16, 0.14, 0.26, 0.85))
		var base := builder.col("wood_weathered").darkened(0.08)
		var n := 4
		var w := TS / float(n)
		for i: int in n:
			var x0 := f.position.x + float(i) * w + 1.5
			var top := f.position.y + 6.0 + WorldBuilder.hash01(c.x * 4 + i, c.y, 62) * 6.0
			var pts := PackedVector2Array([Vector2(x0, f.end.y), Vector2(x0, top + 6.0), Vector2(x0 + w * 0.5 - 1.5, top), Vector2(x0 + w - 3.0, top + 6.0), Vector2(x0 + w - 3.0, f.end.y)])
			draw_polygon(pts, PackedColorArray([base.darkened(0.3), base.lightened(0.1), base.lightened(0.2), base, base.darkened(0.3)]))
			pts.append(pts[0])
			draw_polyline(pts, OUTLINE, 1.4)
		for yy: float in [f.position.y + 18.0, f.end.y - 12.0]:
			draw_rect(Rect2(f.position.x, yy, TS, 5.0), base.darkened(0.15))
			draw_rect(Rect2(f.position.x, yy, TS, 5.0), OUTLINE, false, 1.0)

	func _face_rock(c: Vector2i, f: Rect2) -> void:
		var base := builder.col("mine_wall").lightened(0.15)
		_grad(f, base.lightened(0.15), base.darkened(0.3))
		for i: int in 4:
			var hx := WorldBuilder.hash01(c.x, c.y, 70 + i)
			var hy := WorldBuilder.hash01(c.x, c.y, 80 + i)
			var p := f.position + Vector2(6.0 + hx * 50.0, 8.0 + hy * (f.size.y - 16.0))
			var r := 6.0 + hx * 6.0
			var pts := PackedVector2Array()
			for k: int in 6:
				var a := float(k) * TAU / 6.0 + hy
				pts.append(p + Vector2(cos(a), sin(a) * 0.75) * r * (0.8 + 0.3 * WorldBuilder.hash01(k, i, c.x)))
			draw_colored_polygon(pts, base.lerp(Color(0.5, 0.42, 0.42), hx * 0.6))
			draw_line(pts[3], pts[4], base.lightened(0.35), 1.4)
			pts.append(pts[0])
			draw_polyline(pts, OUTLINE, 1.2)
		# Étai de bois tous les 3 blocs.
		if c.x % 3 == 0:
			draw_rect(Rect2(f.position.x + 24, f.position.y, 12, f.size.y), Color(0.5, 0.34, 0.22))
			draw_rect(Rect2(f.position.x + 24, f.position.y, 12, f.size.y), OUTLINE, false, 1.4)
			draw_line(f.position + Vector2(26, 2), Vector2(f.position.x + 26, f.end.y - 2), Color(0.76, 0.56, 0.36), 1.4)

	func _face_interior(c: Vector2i, f: Rect2, bid: int) -> void:
		var paper := Color(0.46, 0.16, 0.18)
		if bid >= 0:
			match builder.layout.buildings[bid].archetype:
				&"bank":
					paper = Color(0.18, 0.34, 0.28)
				&"sheriff":
					paper = Color(0.56, 0.5, 0.42)
				&"church":
					paper = Color(0.9, 0.82, 0.68)
				&"hotel":
					paper = Color(0.36, 0.22, 0.4)
				&"store":
					paper = Color(0.5, 0.58, 0.46)
				&"stable", &"mine":
					paper = Color(0.56, 0.4, 0.28)
		var upper := Rect2(f.position, Vector2(TS, f.size.y * 0.55))
		_grad(upper, paper.lightened(0.1), paper.darkened(0.15))
		var x := f.position.x + 8.0
		while x < f.end.x:
			draw_line(Vector2(x, upper.position.y), Vector2(x, upper.end.y), paper.lightened(0.18), 1.6)
			x += 16.0
		var low := Rect2(Vector2(f.position.x, upper.end.y), Vector2(TS, f.size.y - upper.size.y))
		_grad(low, Color(0.5, 0.3, 0.18), Color(0.28, 0.16, 0.1))
		draw_rect(Rect2(low.position + Vector2(8, 5), Vector2(TS - 16, low.size.y - 10)), Color(0.22, 0.12, 0.08), false, 1.4)
		draw_line(low.position, Vector2(low.end.x, low.position.y), Color(0.82, 0.6, 0.38), 2.5)
		draw_rect(Rect2(f.position, Vector2(TS, 4.0)), Color(0.36, 0.22, 0.14))

	func _is_window_cell(c: Vector2i, bid: int) -> bool:
		var b := builder.layout.buildings[bid]
		if c.x <= b.rect.position.x or c.x >= b.rect.end.x - 1:
			return false
		# Façade : rangée haute ou basse de l'emprise.
		if c.y != b.rect.position.y and c.y != b.rect.end.y - 1:
			return false
		for dx: int in [-1, 0, 1]:
			if builder.layout.get_tile(c + Vector2i(dx, 0)) == FloorLayout.Tile.DOOR:
				return false
		return (c.x - b.rect.position.x) % 2 == 0 or b.archetype == &"saloon"

	func _draw_window(f: Rect2, archetype: StringName) -> void:
		var w := Rect2(f.position + Vector2(14, 11), Vector2(TS - 28, f.size.y - 22))
		if archetype == &"church":
			w = Rect2(f.position + Vector2(22, 10), Vector2(20, f.size.y - 18))
		# Volets.
		if archetype != &"church" and archetype != &"bank":
			var sh := Color(0.24, 0.38, 0.4) if archetype != &"saloon" else Color(0.5, 0.2, 0.14)
			for sx: float in [w.position.x - 8.0, w.end.x]:
				draw_rect(Rect2(sx, w.position.y, 8.0, w.size.y), sh)
				draw_rect(Rect2(sx, w.position.y, 8.0, w.size.y), OUTLINE, false, 1.2)
				draw_line(Vector2(sx + 1, w.position.y + 6), Vector2(sx + 7, w.position.y + 6), sh.lightened(0.3), 1.0)
		draw_rect(w.grow(2.0), Color(0.86, 0.72, 0.52))
		# Vitre : reflet du couchant (orange → violet).
		draw_polygon(PackedVector2Array([w.position, Vector2(w.end.x, w.position.y), w.end, Vector2(w.position.x, w.end.y)]),
			PackedColorArray([Color(1.0, 0.66, 0.36), Color(0.86, 0.42, 0.46), Color(0.2, 0.16, 0.3), Color(0.32, 0.2, 0.34)]))
		draw_line(w.position + Vector2(3, w.size.y - 4), w.position + Vector2(w.size.x * 0.6, 3), Color(1.0, 0.92, 0.75, 0.6), 2.0)
		draw_line(Vector2(w.get_center().x, w.position.y), Vector2(w.get_center().x, w.end.y), Color(0.36, 0.22, 0.14), 2.0)
		draw_line(Vector2(w.position.x, w.get_center().y), Vector2(w.end.x, w.get_center().y), Color(0.36, 0.22, 0.14), 2.0)
		draw_rect(w.grow(2.0), OUTLINE, false, 1.8)


# --- Porches (trottoir de planches, poteaux, auvent) -------------------------------

func _build_porches() -> void:
	if layout.floor_index != 0:
		return
	var deck := PorchDecks.new()
	deck.name = "PorchDecks"
	deck.builder = self
	deck.z_index = 1
	add_child(deck)
	for b: FloorLayout.Building in layout.buildings:
		var fi := facade_info(b)
		if not bool(fi["has_street"]) or not bool(fi["bottom"]):
			continue
		var porch := PorchFront.new()
		porch.name = "Porch_%d" % b.id
		porch.builder = self
		porch.building = b
		porch.door_x = float(fi["door_x"])
		porch.z_index = 10
		porch.position = Vector2(0.0, (float(b.rect.end.y) + 0.85) * TS)
		add_child(porch)


## Trottoirs de planches devant les façades (au sol, z 1).
class PorchDecks extends Node2D:
	var builder: WorldBuilder = null

	func _draw() -> void:
		var L := builder.layout
		for b: FloorLayout.Building in L.buildings:
			var fi := builder.facade_info(b)
			if not bool(fi["has_street"]):
				continue
			var row := b.rect.end.y if bool(fi["bottom"]) else b.rect.position.y - 1
			var x := b.rect.position.x
			while x < b.rect.end.x:
				if L.get_tile(Vector2i(x, row)) != FloorLayout.Tile.STREET:
					x += 1
					continue
				var x1 := x
				while x1 < b.rect.end.x and L.get_tile(Vector2i(x1, row)) == FloorLayout.Tile.STREET:
					x1 += 1
				var depth := TS * 0.85
				var y0 := float(row) * TS if bool(fi["bottom"]) else (float(row) + 1.0) * TS - depth
				var r := Rect2(float(x) * TS, y0, float(x1 - x) * TS, depth)
				_deck(r)
				x = x1

	func _deck(r: Rect2) -> void:
		var base := Color(0.66, 0.48, 0.32)
		draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0.12, 0.15, 0.32, 0.35))
		draw_rect(r, base)
		var x := r.position.x
		var i := 0
		while x < r.end.x:
			var w := 12.0
			var c := base.lightened(0.08) if i % 3 == 0 else (base.darkened(0.08) if i % 3 == 1 else base)
			draw_rect(Rect2(x, r.position.y, w, r.size.y), c)
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.32, 0.2, 0.12), 1.4)
			if i % 4 == 0:
				draw_circle(Vector2(x + 6, r.position.y + 6), 1.2, Color(0.25, 0.2, 0.22))
				draw_circle(Vector2(x + 6, r.end.y - 8), 1.2, Color(0.25, 0.2, 0.22))
			x += w
			i += 1
		# Chant avant éclairé + bordure.
		draw_rect(Rect2(r.position.x, r.end.y - 6.0, r.size.x, 6.0), base.darkened(0.35))
		draw_line(Vector2(r.position.x, r.end.y - 6.0), Vector2(r.end.x, r.end.y - 6.0), base.lightened(0.3), 1.6)
		draw_rect(r, OUTLINE, false, 2.0)


## Poteaux + auvent devant une façade sud (trié en Y avec les personnages).
class PorchFront extends Node2D:
	var builder: WorldBuilder = null
	var building: FloorLayout.Building = null
	var door_x: float = NAN

	func _draw() -> void:
		var r := building.rect
		var x0 := float(r.position.x) * TS + 6.0
		var x1 := float(r.end.x) * TS - 6.0
		var post_h := 86.0
		var posts: Array[float] = []
		var x := x0
		var spacing := 3.0 * TS
		var n := maxi(int(round((x1 - x0) / spacing)), 1)
		for i: int in n + 1:
			var px := lerpf(x0, x1, float(i) / float(n))
			if not is_nan(door_x) and absf(px - door_x) < TS * 0.75:
				continue
			posts.append(px)
		var wood := Color(0.62, 0.44, 0.3)
		var beam := Rect2(x0 - 4.0, -post_h - 6.0, x1 - x0 + 8.0, 8.0)
		for px: float in posts:
			# Ombre du poteau (bas-droite).
			draw_line(Vector2(px + 2, 0), Vector2(px + 22, 8), Color(0.1, 0.12, 0.3, 0.4), 6.0)
			draw_rect(Rect2(px - 4.0, -post_h, 8.0, post_h), wood)
			draw_rect(Rect2(px - 4.0, -post_h, 3.0, post_h), wood.lightened(0.3))
			draw_rect(Rect2(px - 4.0, -post_h, 8.0, post_h), OUTLINE, false, 1.8)
		draw_rect(beam, wood.darkened(0.1))
		draw_line(beam.position + Vector2(0, 2), Vector2(beam.end.x, beam.position.y + 2), wood.lightened(0.35), 2.0)
		draw_rect(beam, OUTLINE, false, 1.8)


# --- Portes ----------------------------------------------------------------------

func _build_doors() -> void:
	var scene: PackedScene = load(DOOR_SCENE_PATH) as PackedScene
	for d: FloorLayout.Door in layout.doors:
		var door: DoorNode = scene.instantiate() as DoorNode if scene != null else DoorNode.new()
		door.name = "Door_%d" % d.id
		door.setup(d, _door_kind(d), wall_height)
		door.z_index = 10
		add_child(door)
		_doors.append(door)


func _door_kind(d: FloorLayout.Door) -> StringName:
	if d.state == FloorLayout.DoorState.LOCKED:
		return DoorNode.KIND_VAULT
	var ra := layout.get_room(d.room_a)
	var rb := layout.get_room(d.room_b)
	var outside := (ra != null and ra.outdoor) or (rb != null and rb.outdoor)
	var bid := building_id_at(d.cell)
	if outside and bid >= 0 and layout.buildings[bid].archetype == &"saloon":
		return DoorNode.KIND_SALOON
	if is_mine_cell(d.cell):
		return DoorNode.KIND_VAULT if d.key_id != &"" else DoorNode.KIND_WOOD
	return DoorNode.KIND_WOOD


# --- Escaliers -------------------------------------------------------------------

func _build_stairs() -> void:
	var vis := StairsVisual.new()
	vis.name = "StairsVisual"
	vis.builder = self
	vis.z_index = 1
	add_child(vis)
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


## Escaliers : marches de bois (montée), trémie (descente), échelle de mine.
class StairsVisual extends Node2D:
	var builder: WorldBuilder = null

	func _draw() -> void:
		for st: FloorLayout.Stairs in builder.layout.stairs:
			var r := Rect2(Vector2(st.cell) * TS, Vector2(TS, TS))
			var mine := builder.is_mine_cell(st.cell) or builder.layout.floor_index < 0
			if mine:
				_ladder(r, st.up)
			elif st.up:
				_steps_up(r)
			else:
				_steps_down(r)

	func _steps_up(r: Rect2) -> void:
		# Volée de marches qui monte vers le nord (marches plus claires en haut).
		draw_rect(Rect2(r.position + Vector2(6, 6), r.size), Color(0.1, 0.12, 0.3, 0.4))
		var n := 6
		var h := r.size.y / float(n)
		for i: int in n:
			var y := r.end.y - float(i + 1) * h
			var inset := float(i) * 1.5
			var step := Rect2(r.position.x + 6.0 + inset, y, r.size.x - 12.0 - inset * 2.0, h)
			var c := Color(0.5, 0.32, 0.2).lerp(Color(0.9, 0.7, 0.46), float(i) / float(n - 1))
			draw_rect(step, c)
			draw_rect(Rect2(step.position, Vector2(step.size.x, 3.0)), c.lightened(0.25))
			draw_line(Vector2(step.position.x, step.end.y), step.end, OUTLINE, 1.6)
		# Limons et rampe.
		for sx: float in [r.position.x + 3.0, r.end.x - 9.0]:
			draw_rect(Rect2(sx, r.position.y, 6.0, r.size.y), Color(0.38, 0.22, 0.14))
			draw_rect(Rect2(sx, r.position.y, 6.0, r.size.y), OUTLINE, false, 1.4)
		_arrow(r.get_center(), true)
		draw_rect(r, OUTLINE, false, 2.0)

	func _steps_down(r: Rect2) -> void:
		draw_rect(r, Color(0.08, 0.06, 0.12))
		var n := 6
		var h := r.size.y / float(n)
		for i: int in n:
			var y := r.position.y + float(i) * h
			var c := Color(0.86, 0.66, 0.44).lerp(Color(0.16, 0.1, 0.12), float(i) / float(n - 1))
			var inset := float(i) * 2.0
			draw_rect(Rect2(r.position.x + 8.0 + inset, y, r.size.x - 16.0 - inset * 2.0, h - 2.0), c)
		for sx: float in [r.position.x + 2.0, r.end.x - 8.0]:
			draw_rect(Rect2(sx, r.position.y, 6.0, r.size.y), Color(0.5, 0.32, 0.2))
			draw_rect(Rect2(sx, r.position.y, 6.0, r.size.y), OUTLINE, false, 1.4)
		_arrow(r.get_center(), false)
		draw_rect(r, OUTLINE, false, 2.0)

	func _ladder(r: Rect2, up: bool) -> void:
		var hole := r.grow(-6.0)
		if up:
			# Puits de lumière chaude venant de la surface.
			draw_circle(r.get_center(), TS * 0.62, Color(1.0, 0.7, 0.35, 0.16))
			draw_rect(hole, Color(0.28, 0.2, 0.18))
		else:
			draw_rect(hole, Color(0.04, 0.03, 0.06))
			draw_rect(Rect2(hole.position, Vector2(hole.size.x, 10.0)), Color(0.18, 0.12, 0.12))
		# Cadre de bois.
		for e: Rect2 in [Rect2(r.position, Vector2(TS, 7.0)), Rect2(Vector2(r.position.x, r.end.y - 7.0), Vector2(TS, 7.0)),
				Rect2(r.position, Vector2(7.0, TS)), Rect2(Vector2(r.end.x - 7.0, r.position.y), Vector2(7.0, TS))]:
			draw_rect(e, Color(0.56, 0.38, 0.24))
			draw_rect(e, OUTLINE, false, 1.4)
		# Échelle.
		var lx := r.get_center().x - 13.0
		var rx := r.get_center().x + 13.0
		var rail := Color(0.8, 0.6, 0.38)
		var y := hole.position.y + 6.0
		while y < hole.end.y - 2.0:
			draw_line(Vector2(lx, y), Vector2(rx, y), OUTLINE, 5.0)
			draw_line(Vector2(lx, y), Vector2(rx, y), rail.darkened(0.15), 3.0)
			y += 10.0
		for xx: float in [lx, rx]:
			draw_line(Vector2(xx, r.position.y - 10.0 if up else hole.position.y), Vector2(xx, hole.end.y), OUTLINE, 7.0)
			draw_line(Vector2(xx, r.position.y - 10.0 if up else hole.position.y), Vector2(xx, hole.end.y), rail, 4.0)
		_arrow(r.get_center() + Vector2(0, -2), up)

	func _arrow(c: Vector2, up: bool) -> void:
		var s := -1.0 if up else 1.0
		var pts := PackedVector2Array([c + Vector2(-9, 4.0 * -s), c + Vector2(0, -5.0 * -s), c + Vector2(9, 4.0 * -s)])
		draw_polyline(pts, OUTLINE, 6.0)
		draw_polyline(pts, Color(1.0, 0.92, 0.66), 3.0)


# --- Décors ----------------------------------------------------------------------

func _build_props() -> void:
	for s: FloorLayout.Spawn in layout.prop_spawns:
		var pos := FloorLayout.cell_to_world(s.cell) + Vector2(0.0, TS * 0.25)
		var p := WorldProp.create(s.kind, pos)
		add_child(p)
		_props.append(p)


# --- Extraction ------------------------------------------------------------------

func _build_extraction() -> void:
	if layout.extraction_cells.is_empty():
		return
	var glow := ExtractionGlow.new()
	glow.name = "ExtractionGlow"
	glow.cells = layout.extraction_cells.duplicate()
	glow.color = col("extraction")
	glow.z_index = 1
	glow.pulse_speed = Balance.get_float("world_builder", "extraction_pulse_speed", 2.2)
	add_child(glow)
	# Une fusée de détresse par groupe de cases contiguës.
	var seen := {}
	for c: Vector2i in layout.extraction_cells:
		if seen.has(c):
			continue
		var group: Array[Vector2i] = []
		var stack: Array[Vector2i] = [c]
		seen[c] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			group.append(cur)
			for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var nb := cur + dir
				if not seen.has(nb) and layout.extraction_cells.has(nb):
					seen[nb] = true
					stack.append(nb)
		var center := Vector2.ZERO
		for g: Vector2i in group:
			center += FloorLayout.cell_to_world(g)
		center /= float(group.size())
		var flare := ExtractionFlare.new()
		flare.name = "ExtractionFlare"
		flare.position = center + Vector2(0.0, TS * 0.3)
		flare.z_index = 10
		flare.add_to_group(&"extraction_markers")
		add_child(flare)


## Lueur verte pulsée au sol sur les cases d'extraction.
class ExtractionGlow extends Node2D:
	var cells: Array[Vector2i] = []
	var color: Color = Color(0.3, 0.85, 0.45, 0.45)
	var pulse_speed: float = 2.2
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		modulate.a = 0.65 + 0.35 * sin(_t * pulse_speed)

	func _draw() -> void:
		var c := Color(color.r, color.g, color.b, 1.0)
		for cell: Vector2i in cells:
			var r := Rect2(Vector2(cell) * TS, Vector2(TS, TS))
			draw_rect(r.grow(-3.0), Color(c, 0.22))
			draw_circle(r.get_center(), TS * 0.5, Color(c, 0.18))
			draw_circle(r.get_center(), TS * 0.3, Color(c.lightened(0.4), 0.18))
			draw_rect(r.grow(-6.0), Color(c.lightened(0.3), 0.75), false, 3.0)


## Fusée de détresse plantée (piquet + flamme verte + petit drapeau).
class ExtractionFlare extends Node2D:
	var _t: float = 0.0
	var _redraw: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		_redraw -= delta
		if _redraw <= 0.0:
			_redraw = 1.0 / 20.0
			queue_redraw()

	func _draw() -> void:
		var f := 0.85 + 0.15 * sin(_t * 9.0) * sin(_t * 4.3)
		draw_set_transform(Vector2(8, 2), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, 16.0, Color(0.1, 0.12, 0.3, 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Halo.
		draw_circle(Vector2(0, -62), 46.0 * f, Color(0.3, 1.0, 0.5, 0.08))
		draw_circle(Vector2(0, -62), 28.0 * f, Color(0.4, 1.0, 0.6, 0.14))
		# Piquet.
		draw_rect(Rect2(-4, -56, 8, 56), Color(0.56, 0.38, 0.24))
		draw_rect(Rect2(-4, -56, 3, 56), Color(0.82, 0.62, 0.4))
		draw_rect(Rect2(-4, -56, 8, 56), OUTLINE, false, 1.6)
		# Drapeau vert qui flotte.
		var wave := sin(_t * 5.0) * 3.0
		var flag := PackedVector2Array([Vector2(4, -54), Vector2(30, -50 + wave), Vector2(28, -38 + wave), Vector2(4, -40)])
		draw_colored_polygon(flag, Color(0.22, 0.72, 0.36))
		draw_line(Vector2(6, -50), Vector2(28, -47 + wave), Color(0.6, 1.0, 0.7), 1.6)
		flag.append(flag[0])
		draw_polyline(flag, OUTLINE, 1.6)
		# Fusée : tube rouge + flamme verte.
		draw_rect(Rect2(-6, -72, 12, 18), Color(0.82, 0.18, 0.14))
		draw_rect(Rect2(-6, -72, 12, 18), OUTLINE, false, 1.6)
		var fl := PackedVector2Array([Vector2(-7, -72), Vector2(-3 + sin(_t * 13.0) * 2.0, -72 - 22.0 * f), Vector2(0, -80), Vector2(4 + sin(_t * 11.0) * 2.0, -72 - 26.0 * f), Vector2(7, -72)])
		draw_colored_polygon(fl, Color(0.36, 1.0, 0.5))
		draw_circle(Vector2(0, -78), 5.0 * f, Color(0.9, 1.0, 0.9))


# --- Toits -----------------------------------------------------------------------

func _build_roofs() -> void:
	var holder := Node2D.new()
	holder.name = "Roofs"
	holder.z_index = 50
	holder.z_as_relative = false
	add_child(holder)
	for b: FloorLayout.Building in layout.buildings:
		var roof := BuildingRoof.new()
		roof.name = "Roof_%d_%s" % [b.id, String(b.archetype)]
		roof.archetype = b.archetype
		roof.building_name = b.name
		roof.seed_value = b.id * 7919 + layout.floor_index * 31
		var fi := facade_info(b)
		roof.facade_bottom = bool(fi["bottom"])
		roof.facade_x = float(fi["door_x"])
		var r := Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
		roof.footprint = r
		# Le toit laisse voir la face avant du mur côté sud et, pour une façade
		# au nord, toute la rangée de façade (porte et fenêtres visibles de la rue).
		# Le toit couvre l'emprise sauf la face avant du mur sud (visible depuis la
		# rue). Façade au nord : la rangée du mur nord reste découverte (porte visible).
		var top := r.position.y - 4.0
		if not roof.facade_bottom:
			top = r.position.y + TS - 6.0
		roof.roof_rect = Rect2(r.position.x - 4.0, top, r.size.x + 8.0, r.end.y - wall_height - top)
		holder.add_child(roof)
		_roofs.append(roof)
