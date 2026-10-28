class_name WorldBuilder
extends Node2D
## Constructeur du décor d'un étage (module « Décor », cf. docs/CONVENTIONS.md, phase 3).
##   WorldBuilder.build(layout, world) -> WorldBuilder (Node2D racine, y_sort activé)
## Contient : sol (un nœud par matière, shader tuilable), décalques et ombres (un nœud
## dessiné une fois, atlas), murs 3/4 (faces peintes de l'atlas des murs) avec
## collisions fusionnées (couche world), porches (kit Blender), toits (BuildingRoof, z 50),
## portes (DoorNode), escaliers (Area2D, meta `stairs`), décors (WorldProp, atlas unique),
## lueurs chaudes additives précalculées (un seul nœud), poussière (une couche de
## particules GPU), teinte d'ambiance (CanvasModulate), marqueurs d'extraction.
##
## Performance (iPhone) : aucun _draw par image, aucune lumière dynamique ; tout le
## décor statique vient de 2 atlas (murs/sols, décors/kit) → peu de draw calls.
## Assets : art/blender/build_tiles.py, build_buildings.py, build_props.py.
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
const TEX_SAND: Texture2D = preload("res://assets/textures/ground/sand.png")
const TEX_SAND_B: Texture2D = preload("res://assets/textures/ground/sand_b.png")
const TEX_PLANKS: Texture2D = preload("res://assets/textures/ground/planks.png")
const TEX_MINE: Texture2D = preload("res://assets/textures/ground/mine.png")
const TEX_MACRO: Texture2D = preload("res://assets/textures/ground/macro.png")
const TEX_WALLS: Texture2D = preload("res://assets/textures/walls.png")
const TEX_DUST: Texture2D = preload("res://assets/textures/dust.png")
const GROUND_SHADER: Shader = preload("res://assets/shaders/ground.gdshader")
const WallsMeta := preload("res://assets/textures/walls_meta.gd")
## Taille (unités monde) couverte par une répétition de texture de sol (512 px à 2 px/u).
const TILE_TEX_WORLD := 256.0
const OUTLINE := Color(0.09, 0.05, 0.08)
const NIGHT := Color(0.12, 0.14, 0.34)
## Échelle des décors muraux (rendus à l'échelle des meubles, agrandis pour la lisibilité).
const WALL_DECOR_SCALE := 1.3

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

## Papier peint / lambris intérieur par archétype (régions `face_int_*` de l'atlas des murs).
const INTERIOR_FACE := {
	&"saloon": "int_red", &"bank": "int_green", &"sheriff": "int_plank", &"church": "int_cream",
	&"hotel": "int_purple", &"store": "int_green", &"stable": "int_plank", &"mine": "int_plank",
}
## Teinte multiplicative des façades extérieures par archétype (bois délavé / adobe).
const FACADE_TINT := {
	&"saloon": Color(1.0, 0.86, 0.78), &"store": Color(0.86, 0.96, 0.9), &"hotel": Color(0.98, 0.86, 0.9),
	&"stable": Color(1.0, 0.8, 0.7), &"church": Color(1.08, 1.06, 1.04), &"bank": Color(1.04, 0.94, 0.86),
	&"sheriff": Color(0.96, 0.92, 0.88), &"mine": Color(0.9, 0.86, 0.82),
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
## Sources de lumière chaude (monde) : [position, rayon, intensité].
var _glows: Array = []


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
	_build_ambience()


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


## Région (px) `idx` (modulo) de l'atlas des murs.
static func wall_region(key: String, idx: int = 0) -> Rect2:
	var list: Array = WallsMeta.REGIONS.get(key, WallsMeta.REGIONS["white"])
	var r: Array = list[posmod(idx, list.size())]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## Ajoute une source de lumière chaude (lueur additive précalculée).
func add_glow(pos: Vector2, radius: float, strength: float = 1.0) -> void:
	_glows.append([pos, radius, strength])


# --- Sol -------------------------------------------------------------------------

## Un nœud par matière de sol (sable, plancher, mine, vide) : chaque nœud dessine
## une fois tous les rectangles fusionnés de sa matière, avec le shader tuilable.
func _build_ground() -> void:
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.z_index = 0
	add_child(ground)
	var mats := {
		Ground.SAND: [TEX_SAND, TEX_SAND_B, 0.85, 0.1, 0.05],
		Ground.PLANKS: [TEX_PLANKS, TEX_PLANKS, 0.0, 0.08, 0.0],
		Ground.MINE: [TEX_MINE, TEX_MINE, 0.0, 0.16, 0.05],
	}
	var void_tex: Texture2D = TEX_SAND_B if layout.floor_index == 0 else TEX_MINE
	var void_tint := Color(0.66, 0.5, 0.5) if layout.floor_index == 0 else Color(0.32, 0.28, 0.4)
	for g: int in [Ground.VOID, Ground.SAND, Ground.PLANKS, Ground.MINE]:
		var rects := _ground_rects(g)
		if rects.is_empty():
			continue
		var m: Array = mats.get(g, [void_tex, void_tex, 0.0, 0.18, 0.05])
		var layer := GroundLayer.new()
		layer.name = "Ground_%s" % Ground.keys()[g]
		layer.rects = rects
		layer.builder = self
		layer.ground = g
		layer.tint = void_tint if g == Ground.VOID else Color.WHITE
		var sm := ShaderMaterial.new()
		sm.shader = GROUND_SHADER
		sm.set_shader_parameter(&"tex_a", m[0])
		sm.set_shader_parameter(&"tex_b", m[1])
		sm.set_shader_parameter(&"macro", TEX_MACRO)
		sm.set_shader_parameter(&"tile_world", TILE_TEX_WORLD)
		sm.set_shader_parameter(&"b_amount", m[2])
		sm.set_shader_parameter(&"value_var", m[3])
		sm.set_shader_parameter(&"warp", m[4])
		layer.material = sm
		ground.add_child(layer)
	var decals := GroundDecals.new()
	decals.name = "Decals"
	decals.builder = self
	ground.add_child(decals)


## Rectangles (monde) fusionnés couvrant la matière `g`, avec teinte par bâtiment.
## Retour : Array de [Rect2, Color].
func _ground_rects(g: int) -> Array:
	var w := layout.size.x
	var h := layout.size.y
	var key := PackedInt32Array()
	key.resize(w * h)
	for y: int in h:
		for x: int in w:
			var c := Vector2i(x, y)
			key[y * w + x] = (building_id_at(c) + 2) if ground_at(c) == g else 0
	var used := PackedByteArray()
	used.resize(w * h)
	var out: Array = []
	for y: int in h:
		var x := 0
		while x < w:
			var k := key[y * w + x]
			if k == 0 or used[y * w + x] != 0:
				x += 1
				continue
			var x1 := x
			while x1 < w and key[y * w + x1] == k and used[y * w + x1] == 0:
				x1 += 1
			var y1 := y + 1
			while y1 < h:
				var ok := true
				for xx: int in range(x, x1):
					if key[y1 * w + xx] != k or used[y1 * w + xx] != 0:
						ok = false
						break
				if not ok:
					break
				y1 += 1
			for yy: int in range(y, y1):
				for xx: int in range(x, x1):
					used[yy * w + xx] = 1
			var r := Rect2(Vector2(x, y) * TS, Vector2(x1 - x, y1 - y) * TS)
			# Le vide déborde d'une case autour de la carte (pas de bord noir à l'écran).
			if g == Ground.VOID:
				if x == 0:
					r = r.grow_side(SIDE_LEFT, TS * 12.0)
				if x1 == w:
					r = r.grow_side(SIDE_RIGHT, TS * 12.0)
				if y == 0:
					r = r.grow_side(SIDE_TOP, TS * 12.0)
				if y1 == h:
					r = r.grow_side(SIDE_BOTTOM, TS * 12.0)
			out.append([r, _ground_tint(Vector2i(x, y), g)])
			x = x1
	return out


## Couche de sol d'une matière (dessinée une seule fois).
class GroundLayer extends Node2D:
	var builder: WorldBuilder = null
	var rects: Array = []
	var ground: int = 0
	var tint: Color = Color.WHITE

	func _draw() -> void:
		for e: Array in rects:
			var c: Color = e[1]
			draw_rect(e[0], Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, 1.0))


## Teinte du sol selon la salle (bâtiment).
func _ground_tint(c: Vector2i, g: int) -> Color:
	match g:
		Ground.PLANKS:
			var bid := building_id_at(c)
			if bid >= 0:
				match layout.buildings[bid].archetype:
					&"bank":
						return Color(0.8, 0.74, 0.74)
					&"church":
						return Color(1.1, 1.02, 0.92)
					&"sheriff":
						return Color(0.88, 0.84, 0.84)
					&"stable":
						return Color(1.08, 0.96, 0.8)
					&"hotel":
						return Color(0.88, 0.78, 0.84)
					&"store":
						return Color(0.96, 0.92, 0.84)
			return Color.WHITE
		_:
			return Color.WHITE


## Décalques (atlas des décors) + ombres portées + bords, dessinés une seule fois.
## Tout est en rectangles texturés d'atlas : rendu groupé en très peu d'appels.
class GroundDecals extends Node2D:
	var builder: WorldBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var atlas := WorldProp.ATLAS
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				var t := L.get_tile(c)
				if t == FloorLayout.Tile.VOID:
					_void_detail(atlas, c)
					continue
				if not FloorLayout.is_walkable_tile(t):
					continue
				var g := builder.ground_at(c)
				if g == Ground.SAND:
					_street_detail(atlas, c)
				elif g == Ground.MINE:
					_mine_detail(atlas, c)
				elif g == Ground.PLANKS:
					_plank_detail(atlas, c)
		_ruts(atlas)
		_sunset(L)
		# Ombres et occlusion par-dessus les décalques.
		var walls := WorldBuilder.TEX_WALLS
		for y2: int in L.size.y:
			for x2: int in L.size.x:
				var c2 := Vector2i(x2, y2)
				var t2 := L.get_tile(c2)
				if FloorLayout.is_walkable_tile(t2):
					_wall_shadows(walls, c2)
				elif t2 == FloorLayout.Tile.VOID:
					_void_edge(walls, c2)
		_building_shadows(walls)

	func _piece(atlas: Texture2D, piece: String, center: Vector2, mod: Color = Color.WHITE, k: float = 1.0, flip: bool = false) -> void:
		if not WorldProp.has_piece(piece):
			return
		var reg := WorldProp.piece_region(piece)
		var size := reg.size / WorldProp.PX_PER_WORLD * k
		var dst := Rect2(center - size * 0.5, size)
		if flip:
			dst = Rect2(Vector2(dst.end.x, dst.position.y), Vector2(-dst.size.x, dst.size.y))
		draw_texture_rect_region(atlas, dst, reg, mod)

	func _street_detail(atlas: Texture2D, c: Vector2i) -> void:
		var h := WorldBuilder.hash01(c.x, c.y, 1)
		var o := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		var j := Vector2(WorldBuilder.hash01(c.x, c.y, 2) - 0.5, WorldBuilder.hash01(c.x, c.y, 3) - 0.5) * TS * 0.6
		var flip := WorldBuilder.hash01(c.x, c.y, 4) < 0.5
		if h < 0.07:
			_piece(atlas, "decal_grass_%d" % int(WorldBuilder.hash01(c.x, c.y, 5) * 3.0), o + j, Color.WHITE, 1.0, flip)
		elif h < 0.13:
			_piece(atlas, "decal_pebbles_%d" % int(WorldBuilder.hash01(c.x, c.y, 6) * 3.0), o + j, Color.WHITE, 1.0, flip)
		elif h < 0.155:
			_piece(atlas, "decal_crack_%d" % int(WorldBuilder.hash01(c.x, c.y, 7) * 2.0), o + j, Color(1, 1, 1, 0.8), 1.0, flip)
		elif h < 0.17:
			_piece(atlas, "decal_hoofprints", o + j, Color(1, 1, 1, 0.7), 1.0, flip)
		elif h < 0.172 and WorldBuilder.hash01(c.x, c.y, 11) < 0.3:
			_piece(atlas, "decal_bones", o + j, Color.WHITE, 1.0, flip)

	func _void_detail(atlas: Texture2D, c: Vector2i) -> void:
		if builder.layout.floor_index != 0:
			return
		var h := WorldBuilder.hash01(c.x, c.y, 95)
		var o := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		if h < 0.08:
			_piece(atlas, "decal_grass_%d" % int(WorldBuilder.hash01(c.x, c.y, 96) * 3.0), o, Color(0.8, 0.7, 0.72), 1.2)
		elif h < 0.13:
			_piece(atlas, "decal_pebbles_2", o, Color(0.8, 0.72, 0.74), 1.3)

	func _mine_detail(atlas: Texture2D, c: Vector2i) -> void:
		var h := WorldBuilder.hash01(c.x, c.y, 5)
		var o := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		if h < 0.06:
			_piece(atlas, "decal_pebbles_%d" % int(WorldBuilder.hash01(c.x, c.y, 8) * 3.0), o, Color(0.62, 0.58, 0.68), 1.0)
		elif h < 0.09:
			_piece(atlas, "decal_crack_0", o, Color(0.5, 0.45, 0.6, 0.7))

	func _plank_detail(atlas: Texture2D, c: Vector2i) -> void:
		var h := WorldBuilder.hash01(c.x, c.y, 9)
		var o := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		var bid := builder.building_id_at(c)
		var arch: StringName = builder.layout.buildings[bid].archetype if bid >= 0 else &""
		if arch == &"stable" and h < 0.35:
			_piece(atlas, "decal_straw", o, Color.WHITE, 1.0, h < 0.17)
		elif h < 0.05:
			_piece(atlas, "decal_stain", o, Color(1, 1, 1, 0.6))

	## Lumière de couchant sur toute la carte (un seul polygone) : chaud au nord-ouest,
	## violet au sud-est ; intérieurs/mine : vignettage bleu nuit discret.
	func _sunset(L: FloorLayout) -> void:
		var full := Rect2(Vector2(-12, -12) * TS, (Vector2(L.size) + Vector2(24, 24)) * TS)
		var pts := PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)])
		if L.floor_index == 0:
			draw_polygon(pts, PackedColorArray([Color(1.0, 0.6, 0.28, 0.16), Color(1.0, 0.5, 0.45, 0.1),
				Color(0.46, 0.28, 0.6, 0.16), Color(0.95, 0.5, 0.4, 0.08)]))
		else:
			var n := WorldBuilder.NIGHT
			draw_polygon(pts, PackedColorArray([Color(n, 0.06), Color(n, 0.16), Color(n, 0.22), Color(n, 0.12)]))

	## Ornières de roues le long des grandes rues (ville).
	func _ruts(atlas: Texture2D) -> void:
		var L := builder.layout
		if L.floor_index != 0 or not WorldProp.has_piece("decal_rut"):
			return
		var reg := WorldProp.piece_region("decal_rut")
		var seg := reg.size / WorldProp.PX_PER_WORLD
		for r: FloorLayout.Room in L.rooms:
			if not r.outdoor:
				continue
			var rr := Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS)
			if r.rect.size.x >= 6 and r.rect.size.x >= r.rect.size.y * 2:
				var y := rr.get_center().y - seg.y * 0.5 + TS * 0.25
				var x := rr.position.x
				while x < rr.end.x - 1.0:
					var w := minf(seg.x, rr.end.x - x)
					draw_texture_rect_region(atlas, Rect2(x, y, w, seg.y), Rect2(reg.position, Vector2(w * WorldProp.PX_PER_WORLD, reg.size.y)), Color(1, 1, 1, 0.85))
					x += w

	## Tapis devant le bar du saloon / l'autel / la réception.
	func _rugs(atlas: Texture2D) -> void:
		var L := builder.layout
		for r: FloorLayout.Room in L.rooms:
			if r.outdoor or r.rect.size.x < 4 or r.rect.size.y < 3:
				continue
			if r.tags.has("saloon_hall") or r.tags.has("church_nave") or r.tags.has("hotel_reception") or r.tags.has("bank_hall"):
				var rr := Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS)
				_piece(atlas, "decal_rug", rr.get_center(), Color.WHITE, 1.15)

	func _wall_shadows(walls: Texture2D, c: Vector2i) -> void:
		var L := builder.layout
		var o := Vector2(c) * TS
		var n := L.get_tile(c + Vector2i.UP)
		var w := L.get_tile(c + Vector2i.LEFT)
		var shadow := WorldBuilder.NIGHT
		var gv := WorldBuilder.wall_region("grad_v")
		var gh := WorldBuilder.wall_region("grad_h")
		var interior := L.get_tile(c) != FloorLayout.Tile.STREET
		if FloorLayout.is_opaque_tile(n):
			var depth := 34.0 if not interior else 24.0
			draw_texture_rect_region(walls, Rect2(o, Vector2(TS, depth)), gv, Color(shadow, 0.55))
		if FloorLayout.is_opaque_tile(w):
			draw_texture_rect_region(walls, Rect2(o, Vector2(18.0, TS)), gh, Color(shadow, 0.45))

	## Bord du vide (talus) : ombre bleue vers l'intérieur de la case vide.
	func _void_edge(walls: Texture2D, c: Vector2i) -> void:
		var L := builder.layout
		var o := Vector2(c) * TS
		var shadow := WorldBuilder.NIGHT
		if FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN)):
			draw_texture_rect_region(walls, Rect2(o + Vector2(0, TS - 16.0), Vector2(TS, 16.0)), WorldBuilder.wall_region("grad_v_up"), Color(shadow, 0.5))
		if FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.RIGHT)):
			draw_texture_rect_region(walls, Rect2(o + Vector2(TS - 14.0, 0), Vector2(14.0, TS)), WorldBuilder.wall_region("grad_h_left"), Color(shadow, 0.4))

	## Ombres longues des bâtiments vers l'est (soleil couchant à l'ouest).
	func _building_shadows(walls: Texture2D) -> void:
		var L := builder.layout
		if L.floor_index != 0:
			return
		var gh := WorldBuilder.wall_region("grad_h")
		for b: FloorLayout.Building in L.buildings:
			var br := Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
			var x := br.end.x
			var y0 := br.position.y + TS * 0.5
			var r := Rect2(x, y0, TS * 1.3, br.end.y - y0 + TS * 0.2)
			draw_texture_rect_region(walls, r, gh, Color(WorldBuilder.NIGHT, 0.42))


# --- Murs ------------------------------------------------------------------------

func _build_walls() -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	walls.z_index = 10
	walls.position = Vector2.ZERO
	add_child(walls)
	var d := WallLayer.new()
	d.name = "WallFaces"
	d.builder = self
	walls.add_child(d)
	_collect_wall_glows()
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


## Tous les murs de l'étage (un seul nœud, dessiné une fois) : dessus + face avant
## peinte (bois, adobe, palissade, roche, papier peint/lambris intérieurs, fenêtres
## éclairées). Uniquement des rectangles de l'atlas des murs → rendu groupé.
class WallLayer extends Node2D:
	var builder: WorldBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var tex := WorldBuilder.TEX_WALLS
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				if L.get_tile(c) == FloorLayout.Tile.WALL:
					_draw_wall_cell(tex, c)

	func _is_wall(c: Vector2i) -> bool:
		var t := builder.layout.get_tile(c)
		return t == FloorLayout.Tile.WALL or t == FloorLayout.Tile.DOOR

	func _rect(tex: Texture2D, r: Rect2, col: Color) -> void:
		draw_texture_rect_region(tex, r, WorldBuilder.wall_region("white"), col)

	func _draw_wall_cell(tex: Texture2D, c: Vector2i) -> void:
		var L := builder.layout
		var wh := builder.wall_height
		var mat := builder.wall_mat_at(c)
		var face := FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN))
		var o := Vector2(c) * TS
		var cap_h := TS - wh if face else TS
		# Dessus : matière tuilable (une case = 128 px), plus sombre (dans l'ombre du toit).
		var cap_key: String = {WallMat.ROCK: "cap_rock", WallMat.ADOBE: "cap_adobe", WallMat.FENCE: "cap_fence"}.get(mat, "cap_wood")
		var cr := WorldBuilder.wall_region(cap_key)
		var src := Rect2(cr.position + Vector2(0, posmod(c.y, 2) * 0.0), Vector2(cr.size.x, cr.size.y * cap_h / TS))
		var cap_mod := Color(0.62, 0.58, 0.7) if mat != WallMat.ROCK else Color(0.85, 0.82, 0.95)
		if mat == WallMat.FENCE:
			cap_mod = Color(0.78, 0.66, 0.6)
		draw_texture_rect_region(tex, Rect2(o, Vector2(TS, cap_h)), src, cap_mod)
		# Arêtes : liseré chaud côté ouest/nord (couchant), contour sombre.
		var lit := Color(1.0, 0.78, 0.52, 0.55)
		if not _is_wall(c + Vector2i.UP):
			_rect(tex, Rect2(o + Vector2(0, 2), Vector2(TS, 3)), lit)
			_rect(tex, Rect2(o, Vector2(TS, 2)), OUTLINE)
		if not _is_wall(c + Vector2i.LEFT):
			_rect(tex, Rect2(o + Vector2(2, 0), Vector2(3, cap_h)), lit)
			_rect(tex, Rect2(o, Vector2(2, TS)), OUTLINE)
		if not _is_wall(c + Vector2i.RIGHT):
			_rect(tex, Rect2(o + Vector2(TS - 5, 0), Vector2(4, cap_h)), Color(WorldBuilder.NIGHT, 0.5))
			_rect(tex, Rect2(o + Vector2(TS - 1.5, 0), Vector2(2, TS)), OUTLINE)
		if face:
			_draw_face(tex, c, Rect2(o + Vector2(0, cap_h), Vector2(TS, wh)), mat)
			_rect(tex, Rect2(o + Vector2(0, cap_h - 1), Vector2(TS, 2)), OUTLINE)

	func _draw_face(tex: Texture2D, c: Vector2i, f: Rect2, _mat: int) -> void:
		var L := builder.layout
		var fd := builder.face_desc(c)
		draw_texture_rect_region(tex, f, WorldBuilder.wall_region(fd["key"], fd["v"]), fd["mod"])
		if bool(fd["lamp"]):
			var at := Vector2(f.get_center().x, f.position.y + 14.0)
			draw_texture_rect_region(WorldProp.ATLAS, WorldProp.piece_dest("kit_lantern", at), WorldProp.piece_region("kit_lantern"))
		var wd: Variant = L.wall_decor_cells.get(c, null)
		if wd != null and WorldProp.has_piece(String(wd)):
			# Décor mural (cadre, affiche, étagère…) : point d'appui = bas du décor, posé
			# contre la face (léger retrait au-dessus de la plinthe).
			var at2 := Vector2(f.get_center().x, f.end.y - 4.0)
			draw_texture_rect_region(WorldProp.ATLAS, WorldProp.piece_dest(String(wd), at2, WALL_DECOR_SCALE), WorldProp.piece_region(String(wd)))
		# Contours verticaux là où la face se termine (angles du bâtiment).
		var west_open := not _is_wall(c + Vector2i.LEFT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(-1, 1)))
		var east_open := not _is_wall(c + Vector2i.RIGHT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(1, 1)))
		if west_open:
			_rect(tex, Rect2(f.position + Vector2(2, 0), Vector2(3, f.size.y)), Color(1.0, 0.8, 0.56, 0.45))
			_rect(tex, Rect2(f.position, Vector2(2, f.size.y)), OUTLINE)
		if east_open:
			draw_texture_rect_region(tex, Rect2(f.end.x - 10.0, f.position.y, 10.0, f.size.y), WorldBuilder.wall_region("grad_h_left"), Color(WorldBuilder.NIGHT, 0.5))
			_rect(tex, Rect2(f.end.x - 1.5, f.position.y, 2, f.size.y), OUTLINE)
		_rect(tex, Rect2(f.position.x, f.end.y - 1.5, f.size.x, 2.0), OUTLINE)


## Description de la face avant d'un mur (case WALL dont le sud est praticable) :
## {key: région de l'atlas des murs, v: variante, mod: teinte, window: bool, lamp: bool}.
func face_desc(c: Vector2i) -> Dictionary:
	var mat := wall_mat_at(c)
	var south_c := c + Vector2i.DOWN
	var bid := building_id_at(c)
	var arch: StringName = layout.buildings[bid].archetype if bid >= 0 else &""
	var south_rid := room_id_at(south_c)
	var south_room: FloorLayout.Room = layout.get_room(south_rid) if south_rid >= 0 else null
	var interior := mat != WallMat.ROCK and south_room != null and not south_room.outdoor \
		and building_id_at(south_c) >= 0 and layout.get_tile(south_c) != FloorLayout.Tile.STREET
	var d := {"key": "", "v": int(hash01(c.x, c.y, 60) * 4.0), "mod": Color.WHITE, "window": false, "lamp": false}
	if interior:
		d["key"] = "face_" + String(INTERIOR_FACE.get(arch, "int_plank"))
		d["mod"] = Color(0.92, 0.86, 0.82)
		return d
	match mat:
		WallMat.ADOBE:
			d["key"] = "face_adobe"
		WallMat.FENCE:
			d["key"] = "face_fence"
		WallMat.ROCK:
			d["key"] = "face_rock"
			# Lampe de mineur accrochée à la paroi, une case sur ~6.
			d["lamp"] = hash01(c.x, c.y, 62) < 0.16 and FloorLayout.is_walkable_tile(layout.get_tile(south_c))
		_:
			d["key"] = "face_wood"
	d["mod"] = FACADE_TINT.get(arch, Color.WHITE)
	if bid >= 0 and (mat == WallMat.WOOD or mat == WallMat.ADOBE) and _is_window_cell(c, bid):
		d["key"] = "window_wood" if mat == WallMat.WOOD else "window_adobe"
		d["v"] = 1 if arch == &"saloon" else int(hash01(c.x, c.y, 61) * 3.0)
		d["window"] = true
	return d


func _is_window_cell(c: Vector2i, bid: int) -> bool:
	var b := layout.buildings[bid]
	if c.x <= b.rect.position.x or c.x >= b.rect.end.x - 1:
		return false
	# Façade : rangée haute ou basse de l'emprise.
	if c.y != b.rect.position.y and c.y != b.rect.end.y - 1:
		return false
	for dx: int in [-1, 0, 1]:
		if layout.get_tile(c + Vector2i(dx, 0)) == FloorLayout.Tile.DOOR:
			return false
	return (c.x - b.rect.position.x) % 2 == 0 or b.archetype == &"saloon"


## Lueurs des fenêtres éclairées et des lampes de mine (calculées à la construction).
func _collect_wall_glows() -> void:
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			var c := Vector2i(x, y)
			if layout.get_tile(c) != FloorLayout.Tile.WALL or not FloorLayout.is_walkable_tile(layout.get_tile(c + Vector2i.DOWN)):
				continue
			var fd := face_desc(c)
			var center := Vector2(float(x) + 0.5, float(y) + 1.0) * TS - Vector2(0.0, wall_height * 0.5)
			if bool(fd["window"]):
				add_glow(center + Vector2(0, 16), 48.0, 0.55)
			elif bool(fd["lamp"]):
				add_glow(Vector2((float(x) + 0.5) * TS, float(y + 1) * TS + 10.0), 150.0, 1.0)


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
		# Lanterne murale à côté de la porte (lueur chaude).
		if not is_nan(porch.door_x):
			add_glow(Vector2(porch.door_x + TS * 0.62, float(b.rect.end.y) * TS - 30.0), 64.0, 0.9)


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
				_deck(Rect2(float(x) * TS, y0, float(x1 - x) * TS, depth), bool(fi["bottom"]))
				x = x1

	func _deck(r: Rect2, bottom: bool) -> void:
		var tex := WorldBuilder.TEX_WALLS
		var cap := WorldBuilder.wall_region("cap_fence")
		var white := WorldBuilder.wall_region("white")
		# Ombre portée du trottoir (bas-droite).
		draw_texture_rect_region(tex, Rect2(r.position + Vector2(6, r.size.y), Vector2(r.size.x, 8)), WorldBuilder.wall_region("grad_v"), Color(WorldBuilder.NIGHT, 0.45))
		# Planches perpendiculaires à la rue : la matière (clins horizontaux) tournée
		# n'existe pas, on tuile le bardage par blocs d'une case (lattes lisibles).
		var x := r.position.x
		while x < r.end.x - 0.5:
			var w := minf(TS, r.end.x - x)
			draw_texture_rect_region(tex, Rect2(x, r.position.y, w, r.size.y), Rect2(cap.position, Vector2(w * 2.0, r.size.y * 2.0)), Color(1.05, 0.92, 0.8))
			x += w
		# Chant avant (épaisseur du plancher) + contour.
		var lip := r.end.y - 6.0 if bottom else r.position.y
		draw_texture_rect_region(tex, Rect2(r.position.x, lip, r.size.x, 6.0), white, Color(0.36, 0.22, 0.16))
		draw_texture_rect_region(tex, Rect2(r.position.x, lip, r.size.x, 1.5), white, Color(0.95, 0.74, 0.5))
		for e: Rect2 in [Rect2(r.position, Vector2(r.size.x, 2)), Rect2(r.position.x, r.end.y - 2, r.size.x, 2),
				Rect2(r.position, Vector2(2, r.size.y)), Rect2(r.end.x - 2, r.position.y, 2, r.size.y)]:
			draw_texture_rect_region(tex, e, white, OUTLINE)


## Poteaux + auvent + décorations (bannières, lanterne, tonneaux) devant une façade sud
## (trié en Y avec les personnages). Pièces du kit Blender (atlas des décors).
class PorchFront extends Node2D:
	var builder: WorldBuilder = null
	var building: FloorLayout.Building = null
	var door_x: float = NAN

	func _draw() -> void:
		var atlas := WorldProp.ATLAS
		var walls := WorldBuilder.TEX_WALLS
		var white := WorldBuilder.wall_region("white")
		var r := building.rect
		var arch := building.archetype
		var x0 := float(r.position.x) * TS + 8.0
		var x1 := float(r.end.x) * TS - 8.0
		var wall_base := -0.85 * TS                      # bas de la face du mur (repère local)
		var beam_y := wall_base - 40.0                    # poutre de l'auvent
		var top_y := wall_base - builder.wall_height      # haut de la face (sous le toit)
		# Auvent : bande de tôle/bardeaux entre le haut du mur et la poutre, ombre portée dessous.
		var aw := Rect2(x0 - 6.0, top_y, x1 - x0 + 12.0, beam_y - top_y + 4.0)
		draw_texture_rect_region(walls, Rect2(aw.position.x + 4.0, aw.end.y, aw.size.x, 16.0), WorldBuilder.wall_region("grad_v"), Color(WorldBuilder.NIGHT, 0.55))
		var cols: Array = BuildingRoof.COLORS.get(arch, BuildingRoof.COLORS[&"saloon"])
		var lit: Color = cols[0]
		var cap := WorldBuilder.wall_region("cap_wood")
		var xx := aw.position.x
		while xx < aw.end.x - 0.5:
			var w := minf(TS, aw.end.x - xx)
			draw_texture_rect_region(walls, Rect2(xx, aw.position.y, w, aw.size.y), Rect2(cap.position, Vector2(w * 2.0, aw.size.y * 2.0)), lit.lerp(Color(0.8, 0.66, 0.54), 0.35))
			xx += w
		draw_texture_rect_region(walls, Rect2(aw.position.x, aw.end.y - 5.0, aw.size.x, 5.0), white, lit.darkened(0.45))
		draw_texture_rect_region(walls, Rect2(aw.position.x, aw.position.y, aw.size.x, 2.0), white, Color(1.0, 0.85, 0.6, 0.7))
		for e: Rect2 in [Rect2(aw.position.x, aw.end.y - 1.0, aw.size.x, 2.0), Rect2(aw.position.x - 1.0, aw.position.y, 2.0, aw.size.y),
				Rect2(aw.end.x - 1.0, aw.position.y, 2.0, aw.size.y)]:
			draw_texture_rect_region(walls, e, white, OUTLINE)
		# Bannières / lanterne accrochées sous l'auvent.
		var banner := ""
		match arch:
			&"saloon", &"hotel":
				banner = "kit_banner_red"
			&"sheriff":
				banner = "kit_banner_blue"
		if banner != "":
			for bx: float in [x0 + TS * 0.9, x1 - TS * 0.9]:
				if not is_nan(door_x) and absf(bx - door_x) < TS:
					continue
				_piece(atlas, banner, Vector2(bx, beam_y + 2.0), 0.9)
		if not is_nan(door_x):
			_piece(atlas, "kit_lantern", Vector2(door_x + TS * 0.62, wall_base - 34.0), 1.0)
		# Poteaux (kit Blender), sauf devant la porte.
		var post := "kit_post_iron" if arch == &"bank" else "kit_post"
		var n := maxi(int(round((x1 - x0) / (3.0 * TS))), 1)
		var post_h := WorldProp.piece_feet(post).y / WorldProp.PX_PER_WORLD
		var k := (-beam_y + 4.0) / maxf(post_h, 1.0)
		for i: int in n + 1:
			var px := lerpf(x0, x1, float(i) / float(n))
			if not is_nan(door_x) and absf(px - door_x) < TS * 0.75:
				continue
			_piece(atlas, post, Vector2(px, 0.0), k)
		# Tonneaux et sacs au bout du trottoir (magasin, écurie, saloon).
		if arch == &"store" or arch == &"stable" or arch == &"saloon":
			_piece(atlas, "kit_barrels", Vector2(x1 - TS * 0.55, -8.0), 1.0)

	func _piece(atlas: Texture2D, piece: String, at: Vector2, k: float) -> void:
		if WorldProp.has_piece(piece):
			draw_texture_rect_region(atlas, WorldProp.piece_dest(piece, at, k), WorldProp.piece_region(piece))


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
		if st.up and (is_mine_cell(st.cell) or layout.floor_index < 0):
			add_glow(FloorLayout.cell_to_world(st.cell), 90.0, 0.9)  # puits de lumière de la surface
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
	# Une seule StaticBody2D pour toutes les collisions de décors (shape owners).
	var shared := WorldProp.make_shared_body()
	add_child(shared)
	for s: FloorLayout.Spawn in layout.prop_spawns:
		var pos := FloorLayout.cell_to_world(s.cell) + Vector2(0.0, TS * 0.25) + s.offset
		var p := WorldProp.create(s.kind, pos, shared, s.flip)
		add_child(p)
		_props.append(p)
		var go := p.get_glow_offset()
		if go != Vector2.INF:
			var big := s.kind == &"lantern"
			add_glow(pos + go, (130.0 if layout.floor_index < 0 else 80.0) if big else 56.0, 1.0)
	if not layout.decor_spawns.is_empty():
		var fl := FloorDetails.new()
		fl.name = "FloorDetails"
		fl.spawns = layout.decor_spawns
		fl.z_index = 1
		add_child(fl)


## Détails au sol non bloquants de l'aménagement (tapis, papiers, paille, rails…) :
## pièces de l'atlas des décors, un seul nœud dessiné une fois.
class FloorDetails extends Node2D:
	var spawns: Array[FloorLayout.Spawn] = []

	func _draw() -> void:
		for s: FloorLayout.Spawn in spawns:
			var piece := String(s.kind)
			if not WorldProp.has_piece(piece):
				continue
			var reg := WorldProp.piece_region(piece)
			var size := reg.size / WorldProp.PX_PER_WORLD
			var c := FloorLayout.cell_to_world(s.cell) + s.offset
			draw_set_transform(c, s.rot, Vector2(-1.0 if s.flip else 1.0, 1.0))
			draw_texture_rect_region(WorldProp.ATLAS, Rect2(-size * 0.5, size), reg)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
		# Le toit couvre l'emprise sauf la face avant du mur sud (visible depuis la
		# rue). Façade au nord : la rangée du mur nord reste découverte (porte visible).
		var top := r.position.y - 4.0
		if not roof.facade_bottom:
			top = r.position.y + TS - 6.0
		roof.roof_rect = Rect2(r.position.x - 4.0, top, r.size.x + 8.0, r.end.y - wall_height - top)
		holder.add_child(roof)
		_roofs.append(roof)


# --- Ambiance (léger : aucune lumière dynamique) -----------------------------------

func _build_ambience() -> void:
	# Teinte globale : couchant chaud en ville, intérieur d'étage plus sombre, mine bleue.
	var cm := CanvasModulate.new()
	cm.name = "AmbientTint"
	var key := "ambient_town" if layout.floor_index == 0 else ("ambient_upper" if layout.floor_index > 0 else "ambient_mine")
	var defaults := {"ambient_town": Color(1.0, 0.92, 0.84), "ambient_upper": Color(0.9, 0.8, 0.74), "ambient_mine": Color(0.6, 0.64, 0.84)}
	var v: Variant = Balance.get_value("world_builder", key, defaults[key])
	cm.color = v if v is Color else defaults[key]
	add_child(cm)
	# Lueurs chaudes (lanternes, fenêtres, bougies) : un seul nœud additif dessiné une fois.
	var glows := GlowLayer.new()
	glows.name = "Glows"
	glows.glows = _glows
	glows.strength = Balance.get_float("world_builder", "glow_strength", 1.0)
	glows.mine = layout.floor_index < 0
	glows.material = WorldProp.glow_material()
	glows.z_index = 45
	glows.z_as_relative = false
	add_child(glows)
	_build_dust()


## Poussière chaude en suspension dans les rues (une seule couche de particules GPU).
func _build_dust() -> void:
	var amount := int(Balance.get_value("world_builder", "dust_amount", 90))
	if amount <= 0:
		return
	var area := Rect2()
	var first := true
	for r: FloorLayout.Room in layout.rooms:
		if layout.floor_index == 0 and not r.outdoor:
			continue
		var rr := Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS)
		area = rr if first else area.merge(rr)
		first = false
	if first:
		return
	var p := GPUParticles2D.new()
	p.name = "Dust"
	p.amount = amount if layout.floor_index == 0 else amount / 2
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.texture = TEX_DUST
	p.z_index = 46
	p.z_as_relative = false
	p.position = area.get_center()
	p.visibility_rect = Rect2(-area.size * 0.5 - Vector2(64, 64), area.size + Vector2(128, 128))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area.size.x * 0.5, area.size.y * 0.5, 0.0)
	pm.direction = Vector3(1.0, -0.15, 0.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.25
	pm.scale_max = 0.9
	var grad := Gradient.new()
	var c := Color(1.0, 0.82, 0.58) if layout.floor_index >= 0 else Color(0.7, 0.8, 1.0)
	grad.set_color(0, Color(c, 0.0))
	grad.set_color(1, Color(c, 0.0))
	grad.add_point(0.3, Color(c, 0.32))
	grad.add_point(0.7, Color(c, 0.22))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	add_child(p)


## Lueurs additives précalculées (sprite radial de l'atlas), dessinées une seule fois.
class GlowLayer extends Node2D:
	var glows: Array = []
	var strength: float = 1.0
	var mine: bool = false

	func _draw() -> void:
		if not WorldProp.has_piece("glow"):
			return
		var atlas := WorldProp.ATLAS
		var reg := WorldProp.piece_region("glow")
		var warm := Color(1.0, 0.6, 0.26) if not mine else Color(1.0, 0.5, 0.16)
		for g: Array in glows:
			var p: Vector2 = g[0]
			var rad: float = g[1]
			var k: float = float(g[2]) * strength
			var a := 0.42 if not mine else 0.6
			draw_texture_rect_region(atlas, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), reg, Color(warm, a * k))
			draw_texture_rect_region(atlas, Rect2(p - Vector2(rad, rad) * 0.4, Vector2(rad, rad) * 0.8), reg, Color(1.0, 0.85, 0.6, 0.35 * k))
