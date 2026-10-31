class_name MallBuilder
extends Node2D
## Constructeur du décor d'un étage du centre commercial « Galeries Lumière ».
##   MallBuilder.build(layout, world) -> MallBuilder (Node2D racine triée en Y)
## Même API que WorldBuilder (docs/CONVENTIONS.md) : get_doors(), get_stairs_areas() (meta
## `stairs`), signal stairs_entered(stairs), get_room_at_world(pos), set_stairs_cooldown(sec) ;
## en plus get_roofs(), get_props(), get_wall_body().
##
## Contenu : sols (un nœud par matière, shader tuilable, textures assets/textures/mall/ground),
## décalques/ombres/lumière du couchant (un nœud dessiné une fois, atlas), murs 3/4 (atlas
## assets/textures/mall/walls.png : vitrines, enduit, faïence, béton, bureaux, acrotère) avec
## collisions fusionnées (couche world), néons des devantures, vide de l'atrium (étage 1) et
## verrière (toit), escalators/escaliers, portes (MallDoor : rideaux métalliques, portes
## vitrées, portes blindées à badge), décors (atlas assets/sprites/mall/atlas.png), plafonds des
## boutiques avec enseigne néon (s'effacent quand le joueur entre), lueurs additives
## précalculées (un nœud), une couche de particules (poussière dans la lumière), teinte d'ambiance.
##
## Performance : aucun _draw par image (sauf extraction, comme le Far West), aucune lumière
## dynamique, quelques nœuds statiques ; tout le décor vient de 2 atlas + 7 textures de sol.
## Art : art/blender/mall/build_mall_tiles.py, build_mall_props.py.

signal stairs_entered(stairs: FloorLayout.Stairs)

const TS := float(FloorLayout.TILE_SIZE)
## Échelle des décors muraux de l'aménagement.
const WALL_DECOR_SCALE := 1.3
const LAYER_WORLD := 1
const MASK_PLAYER := 2
const DoorScript := preload("res://scripts/biomes/mall/mall_door.gd")
const PropScript := preload("res://scripts/biomes/mall/mall_prop.gd")
const Pop := preload("res://scripts/biomes/mall/mall_populator.gd")
const WallsMeta := preload("res://assets/textures/mall/walls_meta.gd")
const TEX_WALLS: Texture2D = preload("res://assets/textures/mall/walls.png")
const TEX_TILES: Texture2D = preload("res://assets/textures/mall/ground/tiles.png")
const TEX_LINO: Texture2D = preload("res://assets/textures/mall/ground/lino.png")
const TEX_PARQUET: Texture2D = preload("res://assets/textures/mall/ground/parquet.png")
const TEX_CARPET: Texture2D = preload("res://assets/textures/mall/ground/carpet.png")
const TEX_MARBLE: Texture2D = preload("res://assets/textures/mall/ground/marble.png")
const TEX_CONCRETE: Texture2D = preload("res://assets/textures/mall/ground/concrete.png")
const TEX_ROOF: Texture2D = preload("res://assets/textures/mall/ground/roof.png")
const TEX_MACRO: Texture2D = preload("res://assets/textures/mall/ground/macro.png")
const GROUND_SHADER: Shader = preload("res://assets/shaders/ground.gdshader")
const FONT: Font = preload("res://assets/fonts/nunito/Nunito-Variable.ttf")
const TILE_TEX_WORLD := 256.0
const OUTLINE := Color(0.08, 0.06, 0.1)
const NIGHT := Color(0.12, 0.14, 0.34)

enum Ground { VOID, TILES, LINO, PARQUET, CARPET, MARBLE, CONCRETE, ROOF }

const GROUND_OF_ARCH := {
	&"supermarket": Ground.LINO, &"pharmacy": Ground.LINO, &"service": Ground.LINO, &"technical": Ground.CONCRETE,
	&"security": Ground.LINO, &"trash": Ground.CONCRETE, &"clothes": Ground.PARQUET, &"shoes": Ground.PARQUET,
	&"books": Ground.PARQUET, &"perfume": Ground.PARQUET, &"cafe": Ground.PARQUET, &"sports": Ground.LINO,
	&"toys": Ground.LINO, &"department": Ground.PARQUET, &"cinema": Ground.CARPET, &"offices": Ground.CARPET,
	&"arcade": Ground.CARPET, &"jewelry": Ground.MARBLE, &"electronics": Ground.MARBLE, &"phones": Ground.MARBLE,
}
## Couleurs d'accent (néons) des devantures.
const NEONS: Array[Color] = [Color(1.0, 0.3, 0.72), Color(0.66, 0.38, 1.0), Color(0.36, 0.92, 1.0), Color(1.0, 0.62, 0.3), Color(1.0, 0.36, 0.5)]
## Teinte des murs intérieurs peints par archétype.
const INT_TINT := {
	&"clothes": Color(1.0, 0.82, 0.88), &"shoes": Color(0.9, 0.86, 1.0), &"books": Color(0.96, 0.9, 0.78),
	&"perfume": Color(0.98, 0.8, 0.92), &"cafe": Color(0.96, 0.84, 0.7), &"sports": Color(0.78, 0.92, 1.0),
	&"toys": Color(1.0, 0.92, 0.66), &"department": Color(0.94, 0.86, 0.96), &"cinema": Color(0.7, 0.36, 0.44),
	&"arcade": Color(0.56, 0.44, 0.8), &"jewelry": Color(0.74, 0.66, 0.86), &"electronics": Color(0.7, 0.8, 0.92),
	&"phones": Color(0.74, 0.86, 0.94),
}
const TILE_ARCH := [&"supermarket", &"pharmacy", &"service", &"security", &"technical", &"trash"]

## Libellés et formes des conteneurs/cachettes du biome (tant que LootContainer.DEFS /
## HidingSpot.DEFS ne les connaissent pas : cf. _patch_loot).
const CONTAINER_DEFS := {
	&"mall_register": {"name": "Caisse enregistreuse", "block": Vector2(44, 18), "reach": 4.0, "shadow": 0.0},
	&"mall_display": {"name": "Présentoir vitré", "block": Vector2(50, 18), "reach": 6.0, "shadow": 0.0},
	&"mall_jewel_safe": {"name": "Coffre de bijouterie", "block": Vector2(48, 20), "reach": 6.0, "shadow": 0.0},
	&"mall_cart": {"name": "Chariot de supermarché", "block": Vector2(50, 18), "reach": 6.0, "shadow": 0.0},
	&"mall_vending": {"name": "Distributeur automatique", "block": Vector2(44, 20), "reach": 6.0, "shadow": 0.0},
	&"mall_stock_box": {"name": "Cartons de stock", "block": Vector2(44, 18), "reach": 4.0, "shadow": 0.0},
	&"mall_corpse": {"name": "Pilleur tombé", "block": Vector2.ZERO, "reach": 12.0, "shadow": 0.0},
}
const HIDE_DEFS := {
	&"mall_fitting_room": {"name": "Cabine d'essayage", "block": Vector2(50, 16), "reach": 6.0, "shadow": 0.0},
	&"mall_shelving": {"name": "Derrière le rayonnage", "block": Vector2(70, 18), "reach": 8.0, "shadow": 0.0},
	&"mall_counter": {"name": "Derrière le comptoir", "block": Vector2(80, 18), "reach": 8.0, "shadow": 0.0},
	&"mall_car": {"name": "Dans la voiture", "block": Vector2(130, 34), "reach": 12.0, "shadow": 0.0},
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
## Lueurs additives : [position, rayon, intensité, couleur].
var _glows: Array = []
var _container_kind_at: Dictionary = {}
var _hide_kind_at: Dictionary = {}
var _atrium: Rect2i = Rect2i()


static func build(p_layout: FloorLayout, world: Resource = null) -> MallBuilder:
	var root := MallBuilder.new()
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


## (Pré-rendu) Masque les visuels remplacés par le fond pré-calculé (escalators, lueurs peintes) ;
## PrerenderBackdrop.attach_to masque déjà Ground, Walls (visuels), FloorDetails, décors et toits.
func prerender_hide() -> void:
	for nm: String in ["StairsVisual", "Glows"]:
		var n := get_node_or_null(NodePath(nm))
		if n is CanvasItem:
			(n as CanvasItem).visible = false


func get_props() -> Array[Node2D]:
	return _props


func get_wall_body() -> StaticBody2D:
	return _wall_body


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
		push_warning("MallBuilder: layout null.")
		return
	palette = {}
	var wp: Variant = world.get("palette") if world != null else null
	if wp is Dictionary:
		palette = (wp as Dictionary).duplicate()
	wall_height = _cfg_f("wall_height", Balance.get_float("world_builder", "wall_height", 52.0))
	_stairs_cooldown = Balance.get_float("world_builder", "stairs_cooldown", 0.5)
	_build_grids()
	_find_atrium()
	_build_ground()
	_build_walls()
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
	return Balance.get_float("mall", key, def)


static func _cfg_c(key: String, def: Color) -> Color:
	var v: Variant = Balance.get_value("mall", key, def)
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


func _find_atrium() -> void:
	for r in layout.rooms:
		if r.tags.size() > 0 and (r.tags[0] == "atrium" or (r.tags[0] == "balcony" and r.name.begins_with("Balcons"))):
			_atrium = r.rect
	if layout.floor_index == 2:
		# Verrière : plus grand bloc de VOID intérieur.
		var best := Rect2i()
		for rr: Rect2i in WorldBuilder.merge_cells(layout, func(t: int) -> bool: return t == FloorLayout.Tile.VOID):
			if rr.position.x > 0 and rr.position.y > 0 and rr.end.x < layout.size.x and rr.end.y < layout.size.y and rr.get_area() > best.get_area():
				best = rr
		_atrium = best


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


func arch_at(c: Vector2i) -> StringName:
	var b := building_id_at(c)
	return layout.buildings[b].archetype if b >= 0 else &""


func role_at(c: Vector2i) -> String:
	var r := room_at(c)
	return r.tags[0] if r != null and r.tags.size() > 0 else ""


## Néon d'une boutique (déterministe par bâtiment).
func neon_of(bid: int) -> Color:
	if bid < 0:
		return NEONS[0]
	return NEONS[posmod(bid * 7 + layout.floor_index * 3, NEONS.size())]


static func hash01(x: int, y: int, s: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


static func wall_region(key: String, idx: int = 0) -> Rect2:
	var list: Array = WallsMeta.REGIONS.get(key, WallsMeta.REGIONS["white"])
	var r: Array = list[posmod(idx, list.size())]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


func add_glow(pos: Vector2, radius: float, strength: float = 1.0, color: Color = Color(1.0, 0.6, 0.26)) -> void:
	_glows.append([pos, radius, strength, color])


# --- Sol -------------------------------------------------------------------------

func ground_at(c: Vector2i) -> int:
	var t := layout.get_tile(c)
	match t:
		FloorLayout.Tile.VOID, FloorLayout.Tile.WALL:
			return Ground.VOID
		FloorLayout.Tile.STREET:
			if layout.floor_index < 0:
				return Ground.CONCRETE
			if layout.floor_index >= 2:
				return Ground.ROOF
			return Ground.TILES
	var arch := arch_at(c)
	if arch == &"":
		return Ground.TILES if layout.floor_index >= 0 else Ground.CONCRETE
	if role_at(c) == "stockroom":
		return Ground.LINO
	return int(GROUND_OF_ARCH.get(arch, Ground.TILES))


func _build_ground() -> void:
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.z_index = 0
	add_child(ground)
	var mats := {
		Ground.TILES: [TEX_TILES, 0.07, 0.0], Ground.LINO: [TEX_LINO, 0.08, 0.0], Ground.PARQUET: [TEX_PARQUET, 0.08, 0.0],
		Ground.CARPET: [TEX_CARPET, 0.08, 0.0], Ground.MARBLE: [TEX_MARBLE, 0.06, 0.0], Ground.CONCRETE: [TEX_CONCRETE, 0.14, 0.04],
		Ground.ROOF: [TEX_ROOF, 0.12, 0.04],
	}
	var void_tex: Texture2D = TEX_CONCRETE if layout.floor_index <= 0 else TEX_ROOF
	for g: int in [Ground.VOID, Ground.TILES, Ground.LINO, Ground.PARQUET, Ground.CARPET, Ground.MARBLE, Ground.CONCRETE, Ground.ROOF]:
		var rects := _ground_rects(g)
		if rects.is_empty():
			continue
		var m: Array = mats.get(g, [void_tex, 0.18, 0.05])
		var layer := GroundLayer.new()
		layer.name = "Ground_%s" % Ground.keys()[g]
		layer.rects = rects
		layer.tint = _cfg_c("void_tint", Color(0.42, 0.38, 0.5)) if g == Ground.VOID else Color.WHITE
		var sm := ShaderMaterial.new()
		sm.shader = GROUND_SHADER
		sm.set_shader_parameter(&"tex_a", m[0])
		sm.set_shader_parameter(&"tex_b", m[0])
		sm.set_shader_parameter(&"macro", TEX_MACRO)
		sm.set_shader_parameter(&"tile_world", TILE_TEX_WORLD)
		sm.set_shader_parameter(&"b_amount", 0.0)
		sm.set_shader_parameter(&"value_var", m[1])
		sm.set_shader_parameter(&"warp", m[2])
		layer.material = sm
		ground.add_child(layer)
	var decals := Decals.new()
	decals.name = "Decals"
	decals.builder = self
	ground.add_child(decals)


## Rectangles fusionnés (monde) d'une matière, avec teinte par bâtiment : [Rect2, Color].
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
			if g == Ground.VOID:
				if x == 0:
					r = r.grow_side(SIDE_LEFT, TS * 14.0)
				if x1 == w:
					r = r.grow_side(SIDE_RIGHT, TS * 14.0)
				if y == 0:
					r = r.grow_side(SIDE_TOP, TS * 14.0)
				if y1 == h:
					r = r.grow_side(SIDE_BOTTOM, TS * 14.0)
			var tint := Color.WHITE
			if k >= 2 and g != Ground.VOID:
				var v := 0.9 + 0.16 * hash01(k, layout.floor_index, 5)
				tint = Color(v, v * (0.96 + 0.06 * hash01(k, 1, 6)), v * (0.94 + 0.08 * hash01(k, 2, 7)))
			out.append([r, tint])
			x = x1
	return out


class GroundLayer extends Node2D:
	var rects: Array = []
	var tint: Color = Color.WHITE

	func _draw() -> void:
		for e: Array in rects:
			var c: Color = e[1]
			draw_rect(e[0], Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, 1.0))


## Décalques, ombres, lumière du couchant, vide de l'atrium / verrière : dessinés une fois.
class Decals extends Node2D:
	var builder: MallBuilder = null

	func _piece(piece: String, center: Vector2, mod: Color = Color.WHITE, k: float = 1.0, flip: bool = false) -> void:
		if not PropScript.has_piece(piece):
			return
		var reg := PropScript.piece_region(piece)
		var size := reg.size / PropScript.PX_PER_WORLD * k
		var dst := Rect2(center - size * 0.5, size)
		if flip:
			dst = Rect2(Vector2(dst.end.x, dst.position.y), Vector2(-dst.size.x, dst.size.y))
		draw_texture_rect_region(PropScript.ATLAS, dst, reg, mod)

	func _rect(r: Rect2, col: Color) -> void:
		draw_texture_rect_region(MallBuilder.TEX_WALLS, r, MallBuilder.wall_region("white"), col)

	func _grad(key: String, r: Rect2, col: Color) -> void:
		draw_texture_rect_region(MallBuilder.TEX_WALLS, r, MallBuilder.wall_region(key), col)

	func _draw() -> void:
		var L := builder.layout
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				var t := L.get_tile(c)
				if FloorLayout.is_walkable_tile(t):
					_cell_detail(c, t)
		_interiors()
		_parking_lines()
		_roof_pavers()
		_helipad()
		_atrium_void()
		_sun()
		for y2: int in L.size.y:
			for x2: int in L.size.x:
				var c2 := Vector2i(x2, y2)
				var t2 := L.get_tile(c2)
				if FloorLayout.is_walkable_tile(t2):
					_wall_shadows(c2)
				elif t2 == FloorLayout.Tile.VOID and not builder._atrium.has_point(c2):
					_void_edge(c2)

	func _cell_detail(c: Vector2i, t: int) -> void:
		var h := MallBuilder.hash01(c.x, c.y, 1)
		var o := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		var j := Vector2(MallBuilder.hash01(c.x, c.y, 2) - 0.5, MallBuilder.hash01(c.x, c.y, 3) - 0.5) * TS * 0.6
		var flip := MallBuilder.hash01(c.x, c.y, 4) < 0.5
		var fl := builder.layout.floor_index
		var outdoor := t == FloorLayout.Tile.STREET
		if fl < 0:
			if h < 0.03:
				_piece("decal_oil", o + j, Color(1, 1, 1, 0.6), 1.0, flip)
			elif h < 0.09:
				_piece("decal_crack_%d" % int(MallBuilder.hash01(c.x, c.y, 5) * 2.0), o + j, Color(0.7, 0.7, 0.8, 0.7))
			elif h < 0.12:
				_piece("decal_damp", o + j, Color(1, 1, 1, 0.8), 1.0, flip)
			elif h < 0.14:
				_piece("decal_papers", o + j, Color(1, 1, 1, 0.9), 1.0, flip)
			return
		if fl >= 2 and outdoor:
			if h < 0.06:
				_piece("decal_moss_%d" % int(MallBuilder.hash01(c.x, c.y, 5) * 3.0), o + j, Color.WHITE, 1.0, flip)
			elif h < 0.1:
				_piece("decal_weeds_%d" % int(MallBuilder.hash01(c.x, c.y, 6) * 3.0), o + j, Color.WHITE, 1.0, flip)
			elif h < 0.12:
				_piece("decal_leaves", o + j, Color.WHITE, 1.0, flip)
			return
		if outdoor:
			if h < 0.045:
				_piece("decal_moss_%d" % int(MallBuilder.hash01(c.x, c.y, 5) * 3.0), o + j, Color.WHITE, 1.0, flip)
			elif h < 0.085:
				_piece("decal_weeds_%d" % int(MallBuilder.hash01(c.x, c.y, 6) * 3.0), o + j, Color.WHITE, 1.0, flip)
			elif h < 0.11:
				_piece("decal_leaves", o + j, Color.WHITE, 1.0, flip)
			elif h < 0.13:
				_piece("decal_glass", o + j, Color.WHITE, 1.0, flip)
			elif h < 0.145:
				_piece("decal_papers", o + j, Color.WHITE, 1.0, flip)
			elif h < 0.16:
				_piece("decal_rubble", o + j, Color.WHITE, 1.0, flip)
		else:
			if h < 0.05:
				_piece("decal_papers", o + j, Color.WHITE, 1.0, flip)
			elif h < 0.08:
				_piece("decal_glass", o + j, Color(1, 1, 1, 0.9), 1.0, flip)
			elif h < 0.1:
				_piece("decal_crack_%d" % int(MallBuilder.hash01(c.x, c.y, 7) * 2.0), o + j, Color(1, 1, 1, 0.7), 1.0, flip)
			elif h < 0.115:
				_piece("decal_moss_%d" % int(MallBuilder.hash01(c.x, c.y, 8) * 3.0), o + j, Color(1, 1, 1, 0.8), 0.8, flip)

	## Intérieurs de boutiques plus sombres (bleu nuit) : contraste avec les galeries ensoleillées.
	func _interiors() -> void:
		var L := builder.layout
		var a := MallBuilder._cfg_f("interior_shade", 0.24)
		for r: Rect2i in WorldBuilder.merge_cells(L, func(t: int) -> bool: return t == FloorLayout.Tile.FLOOR):
			var rr := Rect2(Vector2(r.position) * TS, Vector2(r.size) * TS)
			_rect(rr, Color(MallBuilder.NIGHT, a))

	## Places de parking : lignes blanches + flèches (étage -1).
	func _parking_lines() -> void:
		var L := builder.layout
		if L.floor_index >= 0 or not PropScript.has_piece("decal_line"):
			return
		# Rangées de places : séparateurs le long des murs nord/sud et de chaque rangée de piliers.
		var rows: Array[int] = [3, L.size.y - 4]
		for y0: int in range(2, L.size.y - 2):
			for x0: int in range(4, L.size.x - 4):
				if L.get_tile(Vector2i(x0, y0)) == FloorLayout.Tile.WALL and FloorLayout.is_walkable_tile(L.get_tile(Vector2i(x0, y0 + 1))) \
						and FloorLayout.is_walkable_tile(L.get_tile(Vector2i(x0, y0 - 1))):
					if not rows.has(y0):
						rows.append(y0)
					break
		for y: int in rows:
			for x: int in range(3, L.size.x - 2, 2):
				var c := Vector2i(x, y)
				if L.get_tile(c) == FloorLayout.Tile.STREET and L.get_tile(c + Vector2i.LEFT) == FloorLayout.Tile.STREET:
					_piece("decal_line", Vector2(float(x) * TS, (float(y) + 0.5) * TS), Color(1, 1, 1, 0.55), 0.55)
		for r in L.rooms:
			if r.tags.size() > 0 and r.tags[0] == "ramp":
				var rr := Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS)
				_piece("decal_arrow", rr.get_center() + Vector2(TS * 1.5, -TS * 1.6), Color(1, 1, 1, 0.8), 1.4, true)
				_piece("decal_arrow", rr.get_center() + Vector2(TS * 1.5, TS * 1.6), Color(1, 1, 1, 0.8), 1.4, true)
				# Lumière du jour qui descend la rampe.
				_grad("grad_h_left", Rect2(rr.position - Vector2(TS * 0.2, 0), Vector2(TS * 4.0, rr.size.y)), Color(1.0, 0.7, 0.4, 0.35))

	## Toit : chemins de dalles sur plots (anneau autour de la verrière, allée vers l'héliport)
	## et chéneaux le long de l'acrotère.
	func _roof_pavers() -> void:
		var L := builder.layout
		if L.floor_index < 2:
			return
		var A := builder._atrium
		var cells: Dictionary = {}
		if A.size.x > 0:
			for y: int in range(A.position.y - 2, A.end.y + 2):
				for x: int in range(A.position.x - 2, A.end.x + 2):
					cells[Vector2i(x, y)] = true
		var cy := A.get_center().y if A.size.x > 0 else L.size.y / 2
		for x2: int in range(2, L.size.x - 2):
			cells[Vector2i(x2, cy)] = true
		for c: Vector2i in cells:
			if L.get_tile(c) != FloorLayout.Tile.STREET:
				continue
			var o := Vector2(c) * TS
			for k: int in 4:
				var q := Rect2(o + Vector2(float(k % 2) * TS * 0.5 + 2.0, float(k / 2) * TS * 0.5 + 2.0), Vector2(TS * 0.5 - 4.0, TS * 0.5 - 4.0))
				var v := 0.86 + 0.1 * MallBuilder.hash01(c.x * 2 + k % 2, c.y * 2 + k / 2, 41)
				_rect(Rect2(q.position + Vector2(2, 3), q.size), Color(MallBuilder.NIGHT, 0.25))
				_rect(q, Color(0.82 * v, 0.78 * v, 0.76 * v))
				_rect(Rect2(q.position, Vector2(q.size.x, 2.0)), Color(1, 0.96, 0.9, 0.5))
		# Chéneaux : bande sombre et humide au pied de l'acrotère.
		for y3: int in L.size.y:
			for x3: int in L.size.x:
				var c3 := Vector2i(x3, y3)
				if L.get_tile(c3) == FloorLayout.Tile.STREET and L.get_tile(c3 + Vector2i.UP) == FloorLayout.Tile.WALL and builder.building_id_at(c3 + Vector2i.UP) < 0:
					_rect(Rect2(Vector2(c3) * TS + Vector2(0, 30.0), Vector2(TS, 10.0)), Color(0.32, 0.3, 0.38, 0.6))

	func _helipad() -> void:
		var L := builder.layout
		for r in L.rooms:
			if r.tags.size() > 0 and r.tags[0] == "helipad":
				var cc := Vector2(L.extraction_cells[0] + Vector2i.ONE) * TS if not L.extraction_cells.is_empty() else Vector2(r.rect.get_center()) * TS
				_piece("decal_helipad", cc, Color(1, 1, 1, 0.92), 1.5)

	## Étage 1 : vide de l'atrium (on voit la fontaine en contrebas) ; toit : verrière.
	func _atrium_void() -> void:
		var L := builder.layout
		var A := builder._atrium
		if A.size.x <= 0:
			return
		var white := MallBuilder.wall_region("white")
		var tex := MallBuilder.TEX_WALLS
		if L.floor_index == 1:
			var hole := Rect2i()
			for rr: Rect2i in WorldBuilder.merge_cells(L, func(t: int) -> bool: return t == FloorLayout.Tile.VOID):
				if A.encloses(rr) and rr.get_area() > hole.get_area():
					hole = rr
			if hole.get_area() == 0:
				return
			var hr := Rect2(Vector2(hole.position) * TS, Vector2(hole.size) * TS)
			# Sol du rez-de-chaussée en contrebas (sombre, légèrement décalé : profondeur).
			var k := float(MallBuilder.TEX_TILES.get_width()) / MallBuilder.TILE_TEX_WORLD
			draw_texture_rect_region(MallBuilder.TEX_TILES, hr, Rect2(hr.position * k + Vector2(0, -60), hr.size * k), Color(0.5, 0.42, 0.46))
			_piece("prop_fountain", hr.get_center() + Vector2(0, TS * 0.6), Color(0.62, 0.52, 0.56), 0.9)
			# Paroi de la trémie (face sud du bord nord) + ombre portée.
			_rect(Rect2(hr.position, Vector2(hr.size.x, 46.0)), Color(0.34, 0.28, 0.36))
			_rect(Rect2(hr.position + Vector2(0, 40.0), Vector2(hr.size.x, 6.0)), Color(0.2, 0.16, 0.24))
			_grad("grad_v", Rect2(hr.position + Vector2(0, 46.0), Vector2(hr.size.x, 70.0)), Color(MallBuilder.NIGHT, 0.6))
			_grad("grad_h", Rect2(hr.position, Vector2(60.0, hr.size.y)), Color(MallBuilder.NIGHT, 0.5))
			# Rayons de soleil qui tombent dans le vide.
			for i: int in 3:
				var x := hr.position.x + hr.size.x * (0.2 + 0.3 * float(i))
				draw_colored_polygon(PackedVector2Array([Vector2(x, hr.position.y), Vector2(x + 50, hr.position.y), Vector2(x + 140, hr.end.y), Vector2(x + 70, hr.end.y)]),
					Color(1.0, 0.7, 0.45, 0.1))
			# Garde-corps vitrés sur les 4 bords.
			var glass := Color(0.7, 0.85, 0.95, 0.28)
			var rail := Color(0.82, 0.84, 0.92)
			_rect(Rect2(hr.position.x, hr.position.y - 22.0, hr.size.x, 22.0), glass)
			_rect(Rect2(hr.position.x, hr.position.y - 24.0, hr.size.x, 4.0), rail)
			_rect(Rect2(hr.position.x, hr.end.y - 22.0, hr.size.x, 22.0), glass)
			_rect(Rect2(hr.position.x, hr.end.y - 24.0, hr.size.x, 4.0), rail)
			_rect(Rect2(hr.position.x, hr.end.y - 2.0, hr.size.x, 2.0), MallBuilder.OUTLINE)
			for sx: float in [hr.position.x, hr.end.x - 5.0]:
				_rect(Rect2(sx, hr.position.y - 22.0, 5.0, hr.size.y + 22.0), rail)
				_rect(Rect2(sx, hr.position.y - 22.0, 1.5, hr.size.y + 22.0), MallBuilder.OUTLINE)
			var x2 := hr.position.x
			while x2 <= hr.end.x:
				_rect(Rect2(x2 - 1.5, hr.position.y - 24.0, 3.0, 24.0), rail)
				_rect(Rect2(x2 - 1.5, hr.end.y - 24.0, 3.0, 24.0), rail)
				x2 += TS
		elif L.floor_index == 2:
			var vr := Rect2(Vector2(A.position) * TS, Vector2(A.size) * TS)
			# Bord de la verrière (costière) + vitrage teinté du couchant.
			_rect(vr.grow(10.0), Color(0.36, 0.34, 0.42))
			_rect(Rect2(vr.position.x - 10.0, vr.end.y, vr.size.x + 20.0, 14.0), Color(0.26, 0.24, 0.32))
			var n := 0
			var y := vr.position.y
			while y < vr.end.y - 1.0:
				var x := vr.position.x
				while x < vr.end.x - 1.0:
					var pane := Rect2(x + 3.0, y + 3.0, TS - 6.0, TS - 6.0)
					var hh := MallBuilder.hash01(int(x), int(y), 31)
					var tt := clampf(((pane.position.x - vr.position.x) + (pane.position.y - vr.position.y) * 1.4) / maxf(vr.size.x + vr.size.y * 1.4, 1.0), 0.0, 1.0)
					if hh < 0.12:
						# Vitre brisée : on voit l'atrium en contrebas.
						var kk := float(MallBuilder.TEX_TILES.get_width()) / MallBuilder.TILE_TEX_WORLD
						draw_texture_rect_region(MallBuilder.TEX_TILES, pane, Rect2(pane.position * kk, pane.size * kk), Color(0.42, 0.34, 0.38))
						_rect(Rect2(pane.position, Vector2(pane.size.x, 8.0)), Color(0.1, 0.08, 0.14, 0.7))
						_piece("decal_glass", pane.get_center() + Vector2(4, 6), Color(1, 1, 1, 0.9), 0.8)
					else:
						# Verre sombre bleu-violet qui reflète une bande de ciel de couchant.
						var band := clampf(1.0 - absf(tt - 0.42) / 0.22, 0.0, 1.0)
						var col := Color(0.24, 0.24, 0.42).lerp(Color(1.0, 0.64, 0.4), band * 0.6).lerp(Color(0.62, 0.36, 0.62), clampf(tt - 0.7, 0.0, 1.0))
						_rect(pane, Color(col, 0.95))
						_rect(Rect2(pane.position, Vector2(pane.size.x, 4.0)), Color(1, 1, 1, 0.15))
						if hh > 0.55:
							draw_line(pane.position + Vector2(8, pane.size.y - 10), pane.position + Vector2(pane.size.x * 0.55, 8), Color(1, 0.96, 0.9, 0.5), 2.5)
						if hh > 0.88:
							_piece("decal_moss_%d" % (n % 3), pane.position + Vector2(14, 14), Color(1, 1, 1, 0.85), 0.6)
					n += 1
					x += TS
				y += TS
			# Meneaux.
			var x3 := vr.position.x
			while x3 <= vr.end.x + 0.5:
				_rect(Rect2(x3 - 3.0, vr.position.y, 6.0, vr.size.y), Color(0.3, 0.3, 0.38))
				x3 += TS
			var y3 := vr.position.y
			while y3 <= vr.end.y + 0.5:
				_rect(Rect2(vr.position.x, y3 - 3.0, vr.size.x, 6.0), Color(0.3, 0.3, 0.38))
				y3 += TS
			for e: Rect2 in [Rect2(vr.position.x - 10.0, vr.position.y - 10.0, vr.size.x + 20.0, 2.0), Rect2(vr.position.x - 10.0, vr.end.y + 22.0, vr.size.x + 20.0, 2.0),
					Rect2(vr.position.x - 10.0, vr.position.y - 10.0, 2.0, vr.size.y + 34.0), Rect2(vr.end.x + 8.0, vr.position.y - 10.0, 2.0, vr.size.y + 34.0)]:
				draw_texture_rect_region(tex, e, white, MallBuilder.OUTLINE)
			_grad("grad_v", Rect2(vr.position.x - 4.0, vr.end.y + 24.0, vr.size.x + 24.0, 40.0), Color(MallBuilder.NIGHT, 0.45))

	## Lumière : coucher de soleil qui entre par la verrière (taches chaudes en biais dans
	## l'atrium et les galeries), dégradé global chaud au nord-ouest / violet au sud-est.
	func _sun() -> void:
		var L := builder.layout
		var full := Rect2(Vector2(-14, -14) * TS, (Vector2(L.size) + Vector2(28, 28)) * TS)
		var pts := PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)])
		if L.floor_index >= 0:
			var k := 1.3 if L.floor_index == 2 else 1.0
			draw_polygon(pts, PackedColorArray([Color(1.0, 0.6, 0.3, 0.14 * k), Color(1.0, 0.5, 0.48, 0.09 * k),
				Color(0.46, 0.28, 0.62, 0.16 * k), Color(0.95, 0.5, 0.42, 0.07 * k)]))
		else:
			var n := MallBuilder.NIGHT
			draw_polygon(pts, PackedColorArray([Color(n, 0.1), Color(n, 0.18), Color(n, 0.24), Color(n, 0.14)]))
		var A := builder._atrium
		if L.floor_index == 0 and A.size.x > 0:
			var ar := Rect2(Vector2(A.position) * TS, Vector2(A.size) * TS)
			for i: int in 4:
				var x := ar.position.x + ar.size.x * (0.05 + 0.24 * float(i))
				var w := TS * (0.8 + 0.5 * MallBuilder.hash01(i, 3, 9))
				draw_colored_polygon(PackedVector2Array([Vector2(x, ar.position.y - TS), Vector2(x + w, ar.position.y - TS),
					Vector2(x + w + TS * 2.2, ar.end.y + TS * 0.5), Vector2(x + TS * 2.2, ar.end.y + TS * 0.5)]), Color(1.0, 0.74, 0.46, 0.16))

	func _wall_shadows(c: Vector2i) -> void:
		var L := builder.layout
		var o := Vector2(c) * TS
		var n := L.get_tile(c + Vector2i.UP)
		var w := L.get_tile(c + Vector2i.LEFT)
		var sh := MallBuilder.NIGHT
		if n == FloorLayout.Tile.WALL or (n == FloorLayout.Tile.VOID and not builder._atrium.has_point(c + Vector2i.UP)):
			_grad("grad_v", Rect2(o, Vector2(TS, 44.0)), Color(sh, 0.55))
		if w == FloorLayout.Tile.WALL:
			_grad("grad_h", Rect2(o, Vector2(26.0, TS)), Color(sh, 0.45))

	func _void_edge(c: Vector2i) -> void:
		var L := builder.layout
		var o := Vector2(c) * TS
		if FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN)):
			_grad("grad_v_up", Rect2(o + Vector2(0, TS - 16.0), Vector2(TS, 16.0)), Color(MallBuilder.NIGHT, 0.5))


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
	_collect_wall_glows()
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


## Face avant d'un mur (case WALL dont le sud est praticable) :
## {key, v, mod, neon (Color, a = 0 si aucun), cap}.
func face_desc(c: Vector2i) -> Dictionary:
	var south := c + Vector2i.DOWN
	var sroom := room_at(south)
	var s_out := sroom == null or sroom.outdoor or layout.get_tile(south) == FloorLayout.Tile.STREET
	var bid := building_id_at(c)
	var d := {"key": "face_plaster", "v": int(hash01(c.x, c.y, 60) * 4.0), "mod": Color.WHITE, "neon": Color(0, 0, 0, 0), "cap": "cap_plaster"}
	var fl := layout.floor_index
	if fl < 0:
		d["key"] = "face_concrete"
		d["cap"] = "cap_concrete"
		if not s_out:
			d["key"] = "face_tile"
			d["mod"] = Color(0.86, 0.88, 0.9)
		return d
	if fl >= 2:
		d["cap"] = "cap_roof"
		if bid >= 0:
			d["cap"] = "cap_dark"
			d["key"] = "face_glass" if s_out else "face_office"
		else:
			d["key"] = "face_parapet"
		return d
	if not s_out:
		var sb := building_id_at(south)
		var arch: StringName = layout.buildings[sb].archetype if sb >= 0 else &""
		d["cap"] = "cap_dark" if bid >= 0 else "cap_plaster"
		if TILE_ARCH.has(arch) or (sroom != null and sroom.tags.size() > 0 and sroom.tags[0] == "stockroom"):
			d["key"] = "face_tile"
		elif arch == &"offices":
			d["key"] = "face_office"
		else:
			d["key"] = "face_int"
			d["mod"] = INT_TINT.get(arch, Color(0.95, 0.9, 0.86))
		return d
	if bid >= 0:
		d["key"] = "face_vitrine"
		d["cap"] = "cap_dark"
		d["neon"] = neon_of(bid)
	return d


## Dessus d'un mur sans face visible.
func cap_for(c: Vector2i) -> String:
	if layout.floor_index < 0:
		return "cap_concrete"
	if building_id_at(c) >= 0:
		return "cap_dark"
	return "cap_roof" if layout.floor_index >= 2 else "cap_plaster"


class WallLayer extends Node2D:
	var builder: MallBuilder = null

	func _draw() -> void:
		var L := builder.layout
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				if L.get_tile(c) == FloorLayout.Tile.WALL:
					_cell(c)

	func _is_wall(c: Vector2i) -> bool:
		var t := builder.layout.get_tile(c)
		return t == FloorLayout.Tile.WALL or t == FloorLayout.Tile.DOOR

	func _rect(r: Rect2, col: Color) -> void:
		draw_texture_rect_region(MallBuilder.TEX_WALLS, r, MallBuilder.wall_region("white"), col)

	func _cell(c: Vector2i) -> void:
		var L := builder.layout
		var tex := MallBuilder.TEX_WALLS
		var wh := builder.wall_height
		var face := FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN))
		var o := Vector2(c) * TS
		var cap_h := TS - wh if face else TS
		var fd: Dictionary = builder.face_desc(c) if face else {}
		var cap_key: String = fd["cap"] if face else builder.cap_for(c)
		var cr := MallBuilder.wall_region(cap_key)
		var cap_mod := Color(1.15, 1.08, 1.2) if cap_key == "cap_dark" else Color(0.78, 0.74, 0.86)
		draw_texture_rect_region(tex, Rect2(o, Vector2(TS, cap_h)), Rect2(cr.position, Vector2(cr.size.x, cr.size.y * cap_h / TS)), cap_mod)
		var lit := Color(1.0, 0.8, 0.58, 0.5)
		if not _is_wall(c + Vector2i.UP):
			_rect(Rect2(o + Vector2(0, 2), Vector2(TS, 3)), lit)
			_rect(Rect2(o, Vector2(TS, 2)), MallBuilder.OUTLINE)
		if not _is_wall(c + Vector2i.LEFT):
			_rect(Rect2(o + Vector2(2, 0), Vector2(3, cap_h)), lit)
			_rect(Rect2(o, Vector2(2, TS)), MallBuilder.OUTLINE)
		if not _is_wall(c + Vector2i.RIGHT):
			_rect(Rect2(o + Vector2(TS - 5, 0), Vector2(4, cap_h)), Color(MallBuilder.NIGHT, 0.5))
			_rect(Rect2(o + Vector2(TS - 1.5, 0), Vector2(2, TS)), MallBuilder.OUTLINE)
		if face:
			var f := Rect2(o + Vector2(0, cap_h), Vector2(TS, wh))
			draw_texture_rect_region(tex, f, MallBuilder.wall_region(fd["key"], fd["v"]), fd["mod"])
			var wd: Variant = L.wall_decor_cells.get(c, null)
			if wd != null and PropScript.has_piece(String(wd)):
				# Décor mural de l'aménagement (affiche, horloge, étagère…), posé sur la face.
				draw_texture_rect_region(PropScript.ATLAS, PropScript.piece_dest(String(wd), Vector2(f.get_center().x, f.end.y - 4.0), WALL_DECOR_SCALE), PropScript.piece_region(String(wd)))
			var neon: Color = fd["neon"]
			if neon.a > 0.0:
				var nr := MallBuilder.wall_region("neon")
				draw_texture_rect_region(tex, Rect2(f.position + Vector2(4, 1), Vector2(TS - 8, 6)), nr, neon)
				draw_texture_rect_region(tex, Rect2(f.position + Vector2(10, 2), Vector2(TS - 20, 3)), nr, Color(1, 1, 1, 0.8))
			var west_open := not _is_wall(c + Vector2i.LEFT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(-1, 1)))
			var east_open := not _is_wall(c + Vector2i.RIGHT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(1, 1)))
			if west_open:
				_rect(Rect2(f.position + Vector2(2, 0), Vector2(3, f.size.y)), Color(1.0, 0.82, 0.6, 0.4))
				_rect(Rect2(f.position, Vector2(2, f.size.y)), MallBuilder.OUTLINE)
			if east_open:
				draw_texture_rect_region(tex, Rect2(f.end.x - 10.0, f.position.y, 10.0, f.size.y), MallBuilder.wall_region("grad_h_left"), Color(MallBuilder.NIGHT, 0.5))
				_rect(Rect2(f.end.x - 1.5, f.position.y, 2, f.size.y), MallBuilder.OUTLINE)
			_rect(Rect2(o + Vector2(0, cap_h - 1), Vector2(TS, 2)), MallBuilder.OUTLINE)
			_rect(Rect2(f.position.x, f.end.y - 1.5, f.size.x, 2.0), MallBuilder.OUTLINE)


## Lueurs des néons de devantures et des lampes de parking (calculées une fois).
func _collect_wall_glows() -> void:
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			var c := Vector2i(x, y)
			if layout.get_tile(c) != FloorLayout.Tile.WALL or not FloorLayout.is_walkable_tile(layout.get_tile(c + Vector2i.DOWN)):
				continue
			var fd := face_desc(c)
			var neon: Color = fd["neon"]
			var base := Vector2((float(x) + 0.5) * TS, float(y + 1) * TS)
			if neon.a > 0.0 and posmod(x, 2) == 0:
				add_glow(base + Vector2(0, -wall_height + 6.0), 54.0, 0.8, neon)
				add_glow(base + Vector2(0, 26.0), 70.0, 0.45, neon)
			elif layout.floor_index < 0 and hash01(x, y, 70) < 0.3:
				# Néon de sodium du parking (lampe sur le pilier / le mur).
				add_glow(base + Vector2(0, -wall_height + 10.0), 150.0, 0.9, Color(1.0, 0.6, 0.24))


# --- Portes ----------------------------------------------------------------------

func _build_doors() -> void:
	for d: FloorLayout.Door in layout.doors:
		var door: DoorNode = DoorScript.new()
		door.name = "Door_%d" % d.id
		door.setup(d, _door_kind(d), wall_height)
		var bid := building_id_at(d.cell)
		door.set("accent", neon_of(bid))
		door.z_index = 10
		add_child(door)
		_doors.append(door)


func _door_kind(d: FloorLayout.Door) -> StringName:
	if d.state == FloorLayout.DoorState.LOCKED:
		return DoorScript.KIND_VAULT_STEEL
	var ra := layout.get_room(d.room_a)
	var rb := layout.get_room(d.room_b)
	var outside := (ra != null and ra.outdoor) or (rb != null and rb.outdoor)
	var arch := arch_at(d.cell)
	if arch == &"offices" or arch == &"cinema":
		return DoorScript.KIND_GLASS
	if outside and layout.floor_index >= 0:
		return DoorScript.KIND_SHUTTER
	return DoorScript.KIND_STEEL


# --- Escaliers / escalators -------------------------------------------------------

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
		add_glow(FloorLayout.cell_to_world(st.cell), 70.0, 0.6, Color(0.55, 0.9, 1.0) if is_escalator(st) else Color(1.0, 0.75, 0.4))
		_stairs_areas.append(area)


func is_escalator(st: FloorLayout.Stairs) -> bool:
	return (layout.floor_index == 0 and st.target_floor == 1) or (layout.floor_index == 1 and st.target_floor == 0)


## Liaison parking ↔ hall dont la case est adossée à un mur au sud : ascenseur.
func is_elevator(st: FloorLayout.Stairs) -> bool:
	var pair := (layout.floor_index == 0 and st.target_floor == -1) or (layout.floor_index == -1 and st.target_floor == 0)
	return pair and layout.get_tile(st.cell + Vector2i.DOWN) == FloorLayout.Tile.WALL


func _on_stairs_body_entered(body: Node2D, st: FloorLayout.Stairs) -> void:
	if _stairs_cooldown > 0.0:
		return
	if body.is_in_group(&"player"):
		stairs_entered.emit(st)


class StairsVisual extends Node2D:
	var builder: MallBuilder = null

	func _draw() -> void:
		for st: FloorLayout.Stairs in builder.layout.stairs:
			var r := Rect2(Vector2(st.cell) * TS, Vector2(TS, TS))
			if builder.is_escalator(st):
				_escalator(r, st.up)
			elif builder.is_elevator(st):
				_elevator(r, st.up)
			elif st.up:
				_steps_up(r)
			else:
				_steps_down(r)
			_arrow(r.get_center(), st.up)

	func _escalator(r: Rect2, up: bool) -> void:
		draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0.1, 0.12, 0.3, 0.4))
		# Marches métalliques rainurées (plus claires vers le haut si on monte).
		var n := 7
		var h := (r.size.y - 4.0) / float(n)
		for i: int in n:
			var y := r.position.y + 2.0 + float(i) * h
			var f := float(i) / float(n - 1)
			var c := Color(0.78, 0.8, 0.88).lerp(Color(0.34, 0.34, 0.44), f if up else 1.0 - f)
			draw_rect(Rect2(r.position.x + 11.0, y, r.size.x - 22.0, h - 1.5), c)
			for gx: int in 5:
				var xx := r.position.x + 15.0 + float(gx) * (r.size.x - 30.0) / 4.0
				draw_line(Vector2(xx, y + 1.0), Vector2(xx, y + h - 2.5), c.darkened(0.25), 1.0)
			draw_line(Vector2(r.position.x + 11.0, y + h - 1.5), Vector2(r.end.x - 11.0, y + h - 1.5), Color(1.0, 0.85, 0.3, 0.9), 1.5)
		# Rampes latérales en verre + main courante noire.
		for sx: float in [r.position.x + 1.0, r.end.x - 11.0]:
			draw_rect(Rect2(sx, r.position.y - 6.0, 10.0, r.size.y + 6.0), Color(0.62, 0.78, 0.9, 0.5))
			draw_rect(Rect2(sx + 2.0, r.position.y - 8.0, 6.0, r.size.y + 8.0), Color(0.12, 0.1, 0.14))
			draw_rect(Rect2(sx, r.position.y - 6.0, 10.0, r.size.y + 6.0), OUTLINE, false, 1.4)
		draw_rect(r, OUTLINE, false, 2.0)

	## Ascenseur (cabine vue de dessus) : plancher strié, portes coulissantes ouvertes au nord,
	## voyant de direction et plafonnier.
	func _elevator(r: Rect2, up: bool) -> void:
		draw_rect(Rect2(r.position + Vector2(5, 6), r.size), Color(0.1, 0.12, 0.3, 0.4))
		draw_rect(r, Color(0.46, 0.48, 0.56))
		var inner := r.grow(-7.0)
		draw_rect(inner, Color(0.3, 0.31, 0.38))
		var y := inner.position.y + 4.0
		while y < inner.end.y - 2.0:
			var x := inner.position.x + (4.0 if int(y) % 2 == 0 else 9.0)
			while x < inner.end.x - 4.0:
				draw_line(Vector2(x, y), Vector2(x + 5.0, y + 3.0), Color(0.56, 0.58, 0.66), 1.6)
				x += 10.0
			y += 7.0
		# Portes ouvertes (vantaux repliés de part et d'autre) en haut.
		draw_rect(Rect2(r.position.x + 2.0, r.position.y, 14.0, 7.0), Color(0.72, 0.74, 0.82))
		draw_rect(Rect2(r.end.x - 16.0, r.position.y, 14.0, 7.0), Color(0.72, 0.74, 0.82))
		draw_rect(Rect2(r.position.x + 16.0, r.position.y, r.size.x - 32.0, 3.0), Color(1.0, 0.85, 0.3))
		# Voyant et plafonnier.
		draw_circle(r.get_center(), 18.0, Color(1.0, 0.95, 0.8, 0.12))
		draw_circle(Vector2(r.end.x - 11.0, r.end.y - 11.0), 4.0, Color(0.4, 1.0, 0.6) if up else Color(1.0, 0.6, 0.3))
		draw_rect(r, OUTLINE, false, 2.0)
		draw_rect(inner, OUTLINE, false, 1.2)

	func _steps_up(r: Rect2) -> void:
		draw_rect(Rect2(r.position + Vector2(6, 6), r.size), Color(0.1, 0.12, 0.3, 0.4))
		var n := 6
		var h := r.size.y / float(n)
		for i: int in n:
			var y := r.end.y - float(i + 1) * h
			var c := Color(0.42, 0.42, 0.5).lerp(Color(0.82, 0.8, 0.82), float(i) / float(n - 1))
			draw_rect(Rect2(r.position.x + 6.0, y, r.size.x - 12.0, h), c)
			draw_rect(Rect2(r.position.x + 6.0, y, r.size.x - 12.0, 3.0), Color(0.95, 0.8, 0.2, 0.9))
			draw_line(Vector2(r.position.x + 6.0, y + h), Vector2(r.end.x - 6.0, y + h), OUTLINE, 1.4)
		for sx: float in [r.position.x + 2.0, r.end.x - 8.0]:
			draw_rect(Rect2(sx, r.position.y, 6.0, r.size.y), Color(0.5, 0.5, 0.6))
			draw_rect(Rect2(sx, r.position.y, 6.0, r.size.y), OUTLINE, false, 1.2)
		draw_rect(r, OUTLINE, false, 2.0)

	func _steps_down(r: Rect2) -> void:
		draw_rect(r, Color(0.06, 0.05, 0.1))
		var n := 6
		var h := r.size.y / float(n)
		for i: int in n:
			var y := r.position.y + float(i) * h
			var c := Color(0.8, 0.78, 0.8).lerp(Color(0.14, 0.12, 0.18), float(i) / float(n - 1))
			var inset := float(i) * 2.0
			draw_rect(Rect2(r.position.x + 8.0 + inset, y, r.size.x - 16.0 - inset * 2.0, h - 2.0), c)
			draw_rect(Rect2(r.position.x + 8.0 + inset, y, r.size.x - 16.0 - inset * 2.0, 2.0), Color(0.95, 0.8, 0.2, 0.8 * (1.0 - float(i) / float(n))))
		for sx: float in [r.position.x + 2.0, r.end.x - 8.0]:
			draw_rect(Rect2(sx, r.position.y, 6.0, r.size.y), Color(0.5, 0.5, 0.6))
			draw_rect(Rect2(sx, r.position.y, 6.0, r.size.y), OUTLINE, false, 1.2)
		draw_rect(r, OUTLINE, false, 2.0)

	func _arrow(c: Vector2, up: bool) -> void:
		var s := -1.0 if up else 1.0
		var pts := PackedVector2Array([c + Vector2(-9, 4.0 * -s), c + Vector2(0, -5.0 * -s), c + Vector2(9, 4.0 * -s)])
		draw_polyline(pts, OUTLINE, 6.0)
		draw_polyline(pts, Color(0.6, 1.0, 0.95), 3.0)


# --- Décors ----------------------------------------------------------------------

func _build_props() -> void:
	# Une seule StaticBody2D pour toutes les collisions de décors (shape owners).
	var shared := PropScript.make_shared_body()
	add_child(shared)
	if not layout.decor_spawns.is_empty():
		var fl := FloorDetails.new()
		fl.name = "FloorDetails"
		fl.spawns = layout.decor_spawns
		fl.atlas = PropScript.ATLAS
		fl.meta = PropScript.AtlasMeta.PIECES
		fl.z_index = 1
		add_child(fl)
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
		var go: Vector2 = p.call("get_glow_offset")
		if go != Vector2.INF and def.has("glow"):
			add_glow(pos + go, float(def["glow"]), 1.0, def.get("tint", Color(1.0, 0.7, 0.4)))


## Détails au sol non bloquants de l'aménagement (tapis, papiers, outils…) : pièces de l'atlas des
## décors du biome, un seul nœud dessiné une fois.
class FloorDetails extends Node2D:
	var spawns: Array[FloorLayout.Spawn] = []
	var atlas: Texture2D = null
	var meta: Dictionary = {}

	func _draw() -> void:
		for s: FloorLayout.Spawn in spawns:
			var e: Variant = meta.get(String(s.kind), null)
			if e == null:
				continue
			var r: Array = (e as Dictionary)["rect"]
			var reg := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
			var size := reg.size * 0.5
			draw_set_transform(FloorLayout.cell_to_world(s.cell) + s.offset, s.rot, Vector2(-1.0 if s.flip else 1.0, 1.0))
			draw_texture_rect_region(atlas, Rect2(-size * 0.5, size), reg)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	var center := Vector2.ZERO
	for c: Vector2i in layout.extraction_cells:
		center += FloorLayout.cell_to_world(c)
	center /= float(layout.extraction_cells.size())
	var flare := WorldBuilder.ExtractionFlare.new()
	flare.name = "ExtractionFlare"
	flare.position = center + Vector2(0.0, TS * 0.3)
	flare.z_index = 10
	flare.add_to_group(&"extraction_markers")
	add_child(flare)


# --- Plafonds des boutiques (enseignes néon) -----------------------------------------

func _build_roofs() -> void:
	var holder := Node2D.new()
	holder.name = "Roofs"
	holder.z_index = 50
	holder.z_as_relative = false
	add_child(holder)
	for b: FloorLayout.Building in layout.buildings:
		var roof := MallRoof.new()
		roof.name = "Roof_%d_%s" % [b.id, String(b.archetype)]
		roof.archetype = b.archetype
		roof.label = b.name
		roof.neon = neon_of(b.id)
		roof.floor_index = layout.floor_index
		var r := Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
		roof.footprint = r
		var side := _facade_side(b)
		roof.facade = side
		var top := r.position.y - 4.0
		if side == &"top":
			top = r.position.y + TS - 6.0
		roof.roof_rect = Rect2(r.position.x - 4.0, top, r.size.x + 8.0, r.end.y - wall_height - top)
		roof.hidden_alpha = Balance.get_float("world_builder", "roof_hidden_alpha", 0.1)
		roof.fade_duration = Balance.get_float("world_builder", "roof_fade_duration", 0.25)
		holder.add_child(roof)
		_roofs.append(roof)


## Côté de la façade (porte donnant sur un espace ouvert) : top, bottom, left, right.
func _facade_side(b: FloorLayout.Building) -> StringName:
	for did: int in b.door_ids:
		var d := layout.doors[did]
		var ra := layout.get_room(d.room_a)
		var rb := layout.get_room(d.room_b)
		if not ((ra != null and ra.outdoor) or (rb != null and rb.outdoor)):
			continue
		if d.vertical:
			return &"left" if d.cell.x <= b.rect.position.x else &"right"
		return &"bottom" if d.cell.y >= b.rect.end.y - 1 else &"top"
	return &"bottom"


class MallRoof extends Node2D:
	var archetype: StringName = &""
	var label: String = ""
	var neon: Color = Color(1, 0.3, 0.7)
	var floor_index: int = 0
	var footprint: Rect2 = Rect2()
	var roof_rect: Rect2 = Rect2()
	var facade: StringName = &"bottom"
	var hidden_alpha: float = 0.1
	var fade_duration: float = 0.25
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

	func _rect(r: Rect2, col: Color) -> void:
		draw_texture_rect_region(MallBuilder.TEX_WALLS, r, MallBuilder.wall_region("white"), col)

	func _draw() -> void:
		var r := roof_rect
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return
		var nt := MallBuilder.NIGHT
		draw_rect(Rect2(r.position + Vector2(10, 10), r.size + Vector2(6, 4)), Color(nt, 0.22))
		# Bac acier nervuré (couleur pastel propre à la boutique), béton au parking.
		var base := Color(0.72, 0.7, 0.72).lerp(neon, 0.14) if floor_index >= 0 else Color(0.5, 0.5, 0.58)
		_rect(r, base)
		var x := r.position.x + 4.0
		var i := 0
		while x < r.end.x - 4.0:
			_rect(Rect2(x, r.position.y, 5.0, r.size.y), base.lightened(0.16))
			_rect(Rect2(x + 5.0, r.position.y, 1.5, r.size.y), base.darkened(0.28))
			if i % 4 == 0:
				_rect(Rect2(x + 9.0, r.position.y, 1.0, r.size.y), Color(base.darkened(0.12), 0.6))
			x += 14.0
			i += 1
		# Coulures, mousse et feuilles (hachage par toit).
		var hs := int(r.position.x * 3.0 + r.position.y * 7.0)
		var n_spots := int(r.get_area() / (TS * TS * 3.0))
		for k in n_spots:
			var p := r.position + Vector2(MallBuilder.hash01(hs, k, 11) * r.size.x, MallBuilder.hash01(hs, k, 12) * r.size.y)
			var dec: String = ["decal_moss_0", "decal_moss_1", "decal_leaves", "decal_damp", "decal_moss_2"][k % 5]
			if PropScript.has_piece(dec):
				var reg := PropScript.piece_region(dec)
				draw_texture_rect_region(PropScript.ATLAS, Rect2(p - reg.size * 0.25, reg.size * 0.5), reg, Color(1, 1, 1, 0.75))
		# Lumière rasante du couchant (chaud en haut à gauche, violet en bas à droite).
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([Color(1.0, 0.7, 0.38, 0.26), Color(1.0, 0.58, 0.5, 0.12), Color(0.36, 0.24, 0.6, 0.3), Color(0.8, 0.5, 0.5, 0.1)]))
		# Lanterneaux (bande de puits de lumière) sur les grands toits.
		if floor_index >= 0 and r.size.x > 4.0 * TS and r.size.y > 3.0 * TS:
			var ns := int(r.size.x / (TS * 2.6))
			for j in ns:
				var sk := Rect2(r.position + Vector2(TS * 0.6 + float(j) * TS * 2.6, r.size.y * 0.22), Vector2(TS * 1.3, TS * 0.8))
				if sk.end.x > r.end.x - TS * 0.5:
					break
				_rect(Rect2(sk.position + Vector2(6, 8), sk.size), Color(nt, 0.35))
				_rect(sk.grow(5.0), Color(0.62, 0.6, 0.68))
				_rect(sk, Color(0.3, 0.32, 0.5))
				draw_colored_polygon(PackedVector2Array([sk.position, sk.position + Vector2(sk.size.x * 0.55, 0), sk.position + Vector2(sk.size.x * 0.2, sk.size.y), Vector2(sk.position.x, sk.end.y)]),
					Color(1.0, 0.68, 0.45, 0.55))
				draw_line(sk.position + Vector2(sk.size.x * 0.5, 4), sk.position + Vector2(sk.size.x * 0.3, sk.size.y - 4), Color(1, 0.95, 0.85, 0.6), 2.0)
				draw_rect(sk.grow(5.0), OUTLINE, false, 2.0)
		# Acrotère.
		_rect(Rect2(r.position, Vector2(r.size.x, 8.0)), Color(0.9, 0.84, 0.8))
		_rect(Rect2(r.position, Vector2(8.0, r.size.y)), Color(0.9, 0.84, 0.8))
		_rect(Rect2(r.end.x - 8.0, r.position.y, 8.0, r.size.y), Color(0.4, 0.36, 0.5))
		_rect(Rect2(r.position.x, r.end.y - 10.0, r.size.x, 10.0), Color(0.44, 0.38, 0.52))
		_rect(Rect2(r.position.x + 8.0, r.position.y + 8.0, r.size.x - 16.0, 4.0), Color(nt, 0.25))
		# Climatiseurs et bouches d'aération (sprites du kit), nombre ∝ surface.
		var n_ac := clampi(int(r.get_area() / (TS * TS * 24.0)), 1, 4)
		for k2 in n_ac:
			var fx := (float(k2) + 0.3 + 0.4 * MallBuilder.hash01(hs, k2, 21)) / float(n_ac)
			var fy := 0.5 + 0.3 * MallBuilder.hash01(hs, k2, 22)
			var at := r.position + Vector2(r.size.x * fx, r.size.y * fy)
			var piece := "prop_ac_unit" if k2 % 2 == 0 else "prop_roof_vent"
			if PropScript.has_piece(piece):
				draw_texture_rect_region(PropScript.ATLAS, PropScript.piece_dest(piece, at, 0.85), PropScript.piece_region(piece))
		draw_rect(r, OUTLINE, false, 3.0)
		_sign(r)

	## Enseigne néon : caisson sombre + lettres lumineuses côté façade.
	func _sign(r: Rect2) -> void:
		var text := label.to_upper()
		if floor_index < 0 or text.is_empty():
			return
		var fs := 22
		var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var maxw := r.size.x - 24.0
		if facade == &"left" or facade == &"right":
			maxw = r.size.x - 24.0
		while w > maxw and fs > 12:
			fs -= 2
			w = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := r.get_center().x
		var cy := r.end.y - 30.0 if facade != &"top" else r.position.y + 34.0
		if facade == &"left" or facade == &"right":
			cy = r.get_center().y
		var box := Rect2(cx - w * 0.5 - 12.0, cy - fs * 0.85, w + 24.0, fs * 1.35)
		draw_rect(Rect2(box.position + Vector2(5, 5), box.size), Color(MallBuilder.NIGHT, 0.4))
		draw_rect(box, Color(0.1, 0.08, 0.16))
		draw_rect(box, Color(neon, 0.9), false, 2.0)
		# Halo (dessiné une fois) puis lettres.
		for g: int in 3:
			draw_rect(box.grow(4.0 + float(g) * 5.0), Color(neon, 0.06), false, 5.0)
		var base := Vector2(cx - w * 0.5, cy + fs * 0.32)
		draw_string_outline(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(neon, 0.45))
		draw_string(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, neon.lerp(Color.WHITE, 0.55))


# --- Ambiance ----------------------------------------------------------------------

func _build_ambience() -> void:
	var cm := CanvasModulate.new()
	cm.name = "AmbientTint"
	var keys := {-1: "ambient_parking", 0: "ambient_ground", 1: "ambient_upper", 2: "ambient_roof"}
	var defaults := {-1: Color(0.62, 0.66, 0.86), 0: Color(1.0, 0.9, 0.86), 1: Color(0.96, 0.86, 0.86), 2: Color(1.0, 0.88, 0.8)}
	var fi := clampi(layout.floor_index, -1, 2)
	cm.color = _cfg_c(keys[fi], defaults[fi])
	add_child(cm)
	# Puits de lumière chaude sous la verrière (atrium) et halos d'ambiance.
	if _atrium.size.x > 0 and layout.floor_index <= 1:
		var ac := Vector2(_atrium.get_center()) * TS
		add_glow(ac, TS * 4.5, 0.7, Color(1.0, 0.62, 0.32))
		add_glow(ac + Vector2(-TS * 3, -TS * 2), TS * 2.5, 0.5, Color(1.0, 0.5, 0.6))
	var flicker: Array = []
	if layout.floor_index < 0:
		flicker = _build_parking_lights()
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
	if not flicker.is_empty():
		var fl: Array = []
		for g: Array in flicker:
			fl.append([g[0], g[1], g[3], float(g[2]) * glows.strength])  # → [pos, rayon, couleur, intensité]
		var tex: Texture2D = PropScript.ATLAS if PropScript.has_piece("glow") else null
		var region := PropScript.piece_region("glow") if tex != null else Rect2()
		var al := AmbientLights.create(tex, region, fl, [], [])
		al.z_index = 46
		al.z_as_relative = false
		add_child(al)
	_build_dust()


## Parking (sous-sol) : néons de plafond froids en grille dans chaque zone praticable, flaques de
## lumière au sol ; un sur [mall] parking_flicker_every grésille (renvoyé, absent de _glows).
## Réglages : [mall] parking_light_step (cases), parking_light_radius (px), parking_light_strength,
## parking_light_color.
func _build_parking_lights() -> Array:
	var step := maxi(int(Balance.get_value("mall", "parking_light_step", 4)), 2)
	var radius := _cfg_f("parking_light_radius", 150.0)
	var k := _cfg_f("parking_light_strength", 0.7)
	var col := _cfg_c("parking_light_color", Color(0.78, 0.9, 1.0))
	var every := int(Balance.get_value("mall", "parking_flicker_every", 6))
	var flicker: Array = []
	var n := 0
	var seed_value := layout.size.x * 31 + layout.size.y * 7
	for r: FloorLayout.Room in layout.rooms:
		var y := r.rect.position.y + 1
		while y < r.rect.end.y:
			var x := r.rect.position.x + 1
			while x < r.rect.end.x:
				var c := Vector2i(mini(x + 1, r.rect.end.x - 1), mini(y + 1, r.rect.end.y - 1))
				if FloorLayout.is_walkable_tile(layout.get_tile(c)):
					n += 1
					var g := [FloorLayout.cell_to_world(c), radius, k, col]
					if every > 0 and (n + seed_value) % every == 0:
						flicker.append(g)
					else:
						_glows.append(g)
				x += step
			y += step
	return flicker


## Poussière / pollen en suspension dans la lumière (une seule couche de particules GPU).
func _build_dust() -> void:
	var amount := int(Balance.get_value("mall", "dust_amount", 80))
	if amount <= 0:
		return
	var area := Rect2()
	var first := true
	for r: FloorLayout.Room in layout.rooms:
		if not r.outdoor:
			continue
		var rr := Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS)
		area = rr if first else area.merge(rr)
		first = false
	if first:
		return
	var p := GPUParticles2D.new()
	p.name = "Dust"
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.texture = preload("res://assets/textures/dust.png")
	p.z_index = 46
	p.z_as_relative = false
	p.position = area.get_center()
	p.visibility_rect = Rect2(-area.size * 0.5 - Vector2(64, 64), area.size + Vector2(128, 128))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area.size.x * 0.5, area.size.y * 0.5, 0.0)
	pm.direction = Vector3(0.6, 0.4, 0.0)
	pm.spread = 40.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.25
	pm.scale_max = 0.8
	var grad := Gradient.new()
	var c := Color(1.0, 0.8, 0.62) if layout.floor_index >= 0 else Color(0.7, 0.8, 1.0)
	grad.set_color(0, Color(c, 0.0))
	grad.set_color(1, Color(c, 0.0))
	grad.add_point(0.3, Color(c, 0.3))
	grad.add_point(0.7, Color(c, 0.2))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	add_child(p)


class GlowLayer extends Node2D:
	var glows: Array = []
	var strength: float = 1.0

	func _draw() -> void:
		if not PropScript.has_piece("glow"):
			return
		var atlas := PropScript.ATLAS
		var reg := PropScript.piece_region("glow")
		for g: Array in glows:
			var p: Vector2 = g[0]
			var rad: float = g[1]
			var k: float = float(g[2]) * strength
			var col: Color = g[3]
			draw_texture_rect_region(atlas, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), reg, Color(col, 0.42 * k))
			draw_texture_rect_region(atlas, Rect2(p - Vector2(rad, rad) * 0.4, Vector2(rad, rad) * 0.8), reg, Color(col.lerp(Color.WHITE, 0.5), 0.3 * k))


# --- Butin : conteneurs et cachettes propres au biome ------------------------------

## LootSpawner ajoute un nœud « Loot » sous la racine : on y surveille les conteneurs et
## cachettes créés pour leur rendre leur kind du biome (LootContainer.create / HidingSpot.create
## remplacent un kind inconnu de leurs DEFS par crate / barrel). Aucun effet quand les DEFS
## partagés connaissent déjà ces kinds.
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
	var body := n.get_node_or_null(^"Body") as StaticBody2D
	if body != null:
		var block: Vector2 = def.get("block", Vector2.ZERO)
		if block == Vector2.ZERO:
			body.queue_free()
		else:
			var cs := body.get_child(0) as CollisionShape2D
			if cs != null and cs.shape is RectangleShape2D:
				var rs := RectangleShape2D.new()
				rs.size = block
				cs.shape = rs
				cs.position = Vector2(0.0, -block.y * 0.5)
	if n is CanvasItem:
		(n as CanvasItem).queue_redraw()
