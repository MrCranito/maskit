class_name UnderwaterBuilder
extends Node2D
## Constructeur du décor de la station sous-marine « Abysse Nérée » (contrat des biomes,
## docs/CONVENTIONS.md : même API que WorldBuilder).
##   UnderwaterBuilder.build(layout, world) -> UnderwaterBuilder (Node2D racine, y_sort activé)
##   get_doors(), get_stairs_areas() (meta `stairs`), signal stairs_entered(stairs),
##   get_room_at_world(pos), set_stairs_cooldown(sec), get_wall_body(), get_props().
##
## Contenu : sol (un nœud par matière : tôles d'acier, carrelage de labo, caillebotis des
## tubes, fond marin ; shader tuilable partagé), eau peu profonde des salles inondées (un
## nœud, shader de caustiques), décalques et ombres (un nœud dessiné une fois), murs 3/4
## (faces de l'atlas : acier riveté, hublots, cloisons de labo, vitrages des tubes sur les
## fonds marins, acier rongé de bernacles) + lampes, alarmes et coraux muraux, collisions
## fusionnées (couche world), sas ronds (UnderwaterDoor), échelles / trappes (Area2D, meta
## `stairs`), décors (UnderwaterProp, atlas unique), capsule d'extraction, lueurs additives
## précalculées (lampes chaudes, alarmes rouges, écrans, rais de lumière), une couche de
## bulles (particules GPU), teinte d'ambiance bleu-vert (CanvasModulate).
## Performance : aucun _draw par image (sauf la pulsation de l'extraction, reprise du Far
## West), aucune lumière dynamique, deux atlas → peu d'appels de dessin.
## Assets : art/blender/underwater/uw_tiles.py, uw_props.py.

signal stairs_entered(stairs: FloorLayout.Stairs)

const TS := float(FloorLayout.TILE_SIZE)
const LAYER_WORLD := 1
const MASK_PLAYER := 2
const SECTION := "underwater"
const TEX_DECK: Texture2D = preload("res://assets/textures/underwater/deck.png")
const TEX_LAB: Texture2D = preload("res://assets/textures/underwater/lab.png")
const TEX_GRATE: Texture2D = preload("res://assets/textures/underwater/grate.png")
const TEX_SEABED: Texture2D = preload("res://assets/textures/underwater/seabed.png")
const TEX_CAUSTICS: Texture2D = preload("res://assets/textures/underwater/caustics.png")
const TEX_BUBBLE: Texture2D = preload("res://assets/textures/underwater/bubble.png")
const TEX_WALLS: Texture2D = preload("res://assets/textures/underwater/walls.png")
const TEX_MACRO: Texture2D = preload("res://assets/textures/ground/macro.png")
const GROUND_SHADER: Shader = preload("res://assets/shaders/ground.gdshader")
const WallsMeta := preload("res://assets/textures/underwater/walls_meta.gd")
const TILE_TEX_WORLD := 256.0
const OUTLINE := Color(0.04, 0.05, 0.08)
const NIGHT := Color(0.04, 0.1, 0.24)
const WARM := Color(1.0, 0.62, 0.28)
const ALARM := Color(1.0, 0.16, 0.1)
const CYAN := Color(0.35, 0.9, 1.0)

enum Ground { VOID, DECK, LAB, GRATE }
enum WallKind { STEEL, LAB, RUST, GLASS }

## Rôles de salles carrelées (laboratoire, infirmerie).
const LAB_ROLES: Array[String] = ["aquarium", "bio_lab", "sample_vault", "dissection", "hydroponics", "office",
	"lab_storage", "decon", "infirmary", "server"]

## Eau peu profonde animée (caustiques qui glissent) : 2 lectures de texture, pas de boucle.
const WATER_SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D caustics : repeat_enable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.16, 0.5, 0.56, 0.42);
uniform float speed = 0.02;
varying vec2 world;
void vertex() { world = VERTEX; }
void fragment() {
	vec2 uv = world / 300.0;
	float a = texture(caustics, uv + vec2(TIME * speed, TIME * speed * 0.6)).a;
	float b = texture(caustics, uv * 1.37 + vec2(-TIME * speed * 0.8, TIME * speed * 0.3)).a;
	float c = min(a, b) * 1.6;
	COLOR = vec4(tint.rgb + vec3(0.55, 0.9, 0.9) * c * 0.5, tint.a * COLOR.a + c * 0.18 * COLOR.a);
}
"""

var layout: FloorLayout = null
var palette: Dictionary = {}
var wall_height: float = 52.0

var _doors: Array[DoorNode] = []
var _stairs_areas: Array[Area2D] = []
var _props: Array[UnderwaterProp] = []
var _wall_body: StaticBody2D = null
var _stairs_cooldown: float = 0.5
var _room_grid: PackedInt32Array = PackedInt32Array()
var _module_grid: PackedInt32Array = PackedInt32Array()
## Lueurs additives : [position, rayon, couleur, intensité].
var _glows: Array = []
## Rais de lumière : [rect monde, couleur].
var _shafts: Array = []
## Pièces du kit dessinées sur les faces des murs : [pièce, position (pieds)].
var _wall_pieces: Array = []


static func build(p_layout: FloorLayout, world: Resource = null) -> UnderwaterBuilder:
	var root := UnderwaterBuilder.new()
	root.name = "World"
	root.layout = p_layout
	root._build(world)
	return root


# --- API -----------------------------------------------------------------------

func get_doors() -> Array[DoorNode]:
	return _doors


func get_stairs_areas() -> Array[Area2D]:
	return _stairs_areas


func get_props() -> Array[UnderwaterProp]:
	return _props


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


## Ignore les entrées dans les escaliers pendant `sec` secondes (arrivée sur un étage).
func set_stairs_cooldown(sec: float) -> void:
	_stairs_cooldown = maxf(sec, 0.0)
	set_process(_stairs_cooldown > 0.0)


func _process(delta: float) -> void:
	if _stairs_cooldown > 0.0:
		_stairs_cooldown = maxf(_stairs_cooldown - delta, 0.0)
	else:
		set_process(false)


# --- Réglages ------------------------------------------------------------------------

static func _cfg(key: String, def: Variant) -> Variant:
	return Balance.get_value(SECTION, key, def)


# --- Construction ----------------------------------------------------------------

func _build(world: Resource) -> void:
	y_sort_enabled = true
	if layout == null:
		push_warning("UnderwaterBuilder: layout null.")
		return
	_read_palette(world)
	wall_height = float(_cfg("wall_height", 52.0))
	_stairs_cooldown = float(_cfg("stairs_cooldown", 0.5))
	_build_grids()
	_build_ground()
	_build_water()
	_build_walls()
	_build_doors()
	_build_stairs()
	_build_props()
	_build_extraction()
	_build_ambience()


func _read_palette(world: Resource) -> void:
	palette = {"extraction": Color(0.3, 0.95, 0.75, 0.45), "void": Color(0.03, 0.12, 0.2)}
	if world == null:
		return
	var wp: Variant = world.get("palette")
	if wp is Dictionary:
		for k: Variant in (wp as Dictionary).keys():
			var v: Variant = (wp as Dictionary)[k]
			if v is Color:
				palette[String(k)] = v


func col(key: String, fallback: Color = Color.MAGENTA) -> Color:
	var c: Variant = palette.get(key, null)
	return c if c is Color else fallback


func _build_grids() -> void:
	var n := layout.size.x * layout.size.y
	_room_grid.resize(n)
	_room_grid.fill(-1)
	_module_grid.resize(n)
	_module_grid.fill(-1)
	var rooms := layout.rooms.duplicate()
	rooms.sort_custom(func(a: FloorLayout.Room, b: FloorLayout.Room) -> bool:
		return a.rect.get_area() > b.rect.get_area())
	for r: FloorLayout.Room in rooms:
		_fill_grid(_room_grid, r.rect, r.id)
	for b: FloorLayout.Building in layout.buildings:
		_fill_grid(_module_grid, b.rect, b.id)


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


func module_id_at(c: Vector2i) -> int:
	if not layout.in_bounds(c):
		return -1
	return _module_grid[c.y * layout.size.x + c.x]


func role_at(c: Vector2i) -> String:
	var r := room_at(c)
	return r.tags[0] if r != null and r.tags.size() > 0 else ""


func is_flooded(c: Vector2i) -> bool:
	var r := room_at(c)
	return r != null and r.tags.has("flooded")


func ground_at(c: Vector2i) -> int:
	var t := layout.get_tile(c)
	if t == FloorLayout.Tile.VOID or t == FloorLayout.Tile.WALL:
		return Ground.VOID
	var r := room_at(c)
	if r == null:
		return Ground.DECK
	if r.type == FloorLayout.ROOM_CORRIDOR:
		return Ground.GRATE
	if LAB_ROLES.has(role_at(c)):
		return Ground.LAB
	return Ground.DECK


func wall_kind_at(c: Vector2i) -> int:
	var mid := module_id_at(c)
	if mid < 0:
		return WallKind.GLASS
	if layout.floor_index <= -2:
		return WallKind.RUST
	var arch := String(layout.buildings[mid].archetype)
	if LAB_ROLES.has(arch) and arch != "server":
		return WallKind.LAB
	return WallKind.STEEL


static func hash01(x: int, y: int, s: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


static func wall_region(key: String, idx: int = 0) -> Rect2:
	var list: Array = WallsMeta.REGIONS.get(key, WallsMeta.REGIONS["white"])
	var r: Array = list[posmod(idx, list.size())]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


func add_glow(pos: Vector2, radius: float, color: Color, strength: float = 1.0) -> void:
	_glows.append([pos, radius, color, strength])


# --- Sol -------------------------------------------------------------------------

func _build_ground() -> void:
	var ground := Node2D.new()
	ground.name = "Ground"
	ground.z_index = 0
	add_child(ground)
	# matière → [texture, variation de valeur, gauchissement, teinte]
	var mats := {
		Ground.VOID: [TEX_SEABED, 0.2, 0.08, Color(0.36, 0.52, 0.62)],
		Ground.DECK: [TEX_DECK, 0.1, 0.0, Color(1.0, 1.0, 1.0)],
		Ground.LAB: [TEX_LAB, 0.12, 0.0, Color(0.74, 0.84, 0.86)],
		Ground.GRATE: [TEX_GRATE, 0.08, 0.0, Color(0.95, 1.0, 1.0)],
	}
	for g: int in [Ground.VOID, Ground.DECK, Ground.LAB, Ground.GRATE]:
		var rects := _ground_rects(g)
		if rects.is_empty():
			continue
		var m: Array = mats[g]
		var layer := GroundLayer.new()
		layer.name = "Ground_%s" % Ground.keys()[g]
		layer.rects = rects
		layer.tint = m[3]
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
	var decals := GroundDecals.new()
	decals.name = "Decals"
	decals.builder = self
	ground.add_child(decals)


## Rectangles (monde) fusionnés couvrant la matière `g`, avec teinte par salle.
func _ground_rects(g: int) -> Array:
	var w := layout.size.x
	var h := layout.size.y
	var key := PackedInt32Array()
	key.resize(w * h)
	for y: int in h:
		for x: int in w:
			var c := Vector2i(x, y)
			key[y * w + x] = (module_id_at(c) + 2) if ground_at(c) == g else 0
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


func _ground_tint(c: Vector2i, g: int) -> Color:
	if g != Ground.DECK:
		return Color.WHITE
	match layout.floor_index:
		-2:
			return Color(0.82, 0.86, 0.86) if not is_flooded(c) else Color(0.7, 0.8, 0.82)
		-1:
			return Color(0.92, 0.98, 1.0)
	var mid := module_id_at(c)
	if mid >= 0 and layout.buildings[mid].archetype == &"moon_pool":
		return Color(0.95, 0.98, 1.0)
	return Color(1.0, 1.0, 1.0)


class GroundLayer extends Node2D:
	var rects: Array = []
	var tint: Color = Color.WHITE

	func _draw() -> void:
		for e: Array in rects:
			var c: Color = e[1]
			draw_rect(e[0], Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, 1.0))


## Décalques (flaques, taches, câbles, grilles, algues, bandes de danger, coraux au pied
## des murs), fond marin, ombres des murs : dessinés une seule fois, rectangles d'atlas.
class GroundDecals extends Node2D:
	var builder: UnderwaterBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var atlas := UnderwaterProp.ATLAS
		var walls := UnderwaterBuilder.TEX_WALLS
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				var t := L.get_tile(c)
				if t == FloorLayout.Tile.VOID:
					_seabed_detail(atlas, c)
				elif FloorLayout.is_walkable_tile(t):
					_floor_detail(atlas, c)
		_door_hazards(atlas)
		_mood(L)
		for y2: int in L.size.y:
			for x2: int in L.size.x:
				var c2 := Vector2i(x2, y2)
				var t2 := L.get_tile(c2)
				if FloorLayout.is_walkable_tile(t2):
					_wall_shadows(walls, c2)
				elif t2 == FloorLayout.Tile.VOID:
					_void_edge(walls, c2)

	func _piece(atlas: Texture2D, piece: String, center: Vector2, mod: Color = Color.WHITE, k: float = 1.0, flip: bool = false) -> void:
		if not UnderwaterProp.has_piece(piece):
			return
		var reg := UnderwaterProp.piece_region(piece)
		var size := reg.size / UnderwaterProp.PX_PER_WORLD * k
		var dst := Rect2(center - size * 0.5, size)
		if flip:
			dst = Rect2(Vector2(dst.end.x, dst.position.y), Vector2(-dst.size.x, dst.size.y))
		draw_texture_rect_region(atlas, dst, reg, mod)

	func _floor_detail(atlas: Texture2D, c: Vector2i) -> void:
		var L := builder.layout
		var h := UnderwaterBuilder.hash01(c.x, c.y, 1)
		var o := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		var j := Vector2(UnderwaterBuilder.hash01(c.x, c.y, 2) - 0.5, UnderwaterBuilder.hash01(c.x, c.y, 3) - 0.5) * TS * 0.5
		var flip := UnderwaterBuilder.hash01(c.x, c.y, 4) < 0.5
		var g := builder.ground_at(c)
		var deep := L.floor_index <= -2
		var flooded := builder.is_flooded(c)
		var near_wall := FloorLayout.is_opaque_tile(L.get_tile(c + Vector2i.UP)) or FloorLayout.is_opaque_tile(L.get_tile(c + Vector2i.LEFT)) \
			or FloorLayout.is_opaque_tile(L.get_tile(c + Vector2i.RIGHT)) or FloorLayout.is_opaque_tile(L.get_tile(c + Vector2i.DOWN))
		if flooded:
			if h < 0.18:
				_piece(atlas, "decal_silt", o + j, Color(1, 1, 1, 0.7), 1.0, flip)
			elif h < 0.3:
				_piece(atlas, "decal_algae_%d" % int(UnderwaterBuilder.hash01(c.x, c.y, 5) * 2.0), o + j, Color.WHITE, 1.0, flip)
			return
		var puddle := 0.05 if g != Ground.GRATE else 0.0
		if deep:
			puddle *= 2.5
		if h < puddle:
			_piece(atlas, "decal_puddle_%d" % int(UnderwaterBuilder.hash01(c.x, c.y, 6) * 3.0), o + j, Color(1, 1, 1, 0.85), 0.8, flip)
		elif h < puddle + 0.04 and g != Ground.LAB:
			_piece(atlas, "decal_stain_%d" % int(UnderwaterBuilder.hash01(c.x, c.y, 7) * 2.0), o + j, Color(1, 1, 1, 0.55), 1.0, flip)
		elif h < puddle + 0.06 and g == Ground.DECK:
			_piece(atlas, "decal_drain", o, Color.WHITE, 0.9)
		elif h < puddle + 0.085 and g != Ground.GRATE:
			_piece(atlas, "decal_cables", o + j, Color.WHITE, 0.8, flip)
		elif near_wall and (deep or g == Ground.GRATE) and h < puddle + 0.2:
			_piece(atlas, "decal_algae_%d" % int(UnderwaterBuilder.hash01(c.x, c.y, 8) * 2.0), o + j * 0.5, Color(1, 1, 1, 0.85), 0.8, flip)
		# Coraux et bernacles qui envahissent le pied des murs (Fosse, tubes).
		if FloorLayout.is_opaque_tile(L.get_tile(c + Vector2i.UP)) and (deep or g == Ground.GRATE) \
				and UnderwaterBuilder.hash01(c.x, c.y, 9) < (0.22 if deep else 0.08):
			_piece(atlas, "kit_wall_coral", o + Vector2(j.x, -TS * 0.36), Color.WHITE, 0.85, flip)

	func _seabed_detail(atlas: Texture2D, c: Vector2i) -> void:
		var h := UnderwaterBuilder.hash01(c.x, c.y, 95)
		var o := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		if h < 0.05:
			_piece(atlas, "prop_coral_cluster", o, Color(0.55, 0.65, 0.75), 1.0, h < 0.025)
		elif h < 0.09:
			_piece(atlas, "prop_kelp", o, Color(0.45, 0.6, 0.65), 1.0, h < 0.07)
		elif h < 0.14:
			_piece(atlas, "decal_algae_%d" % int(UnderwaterBuilder.hash01(c.x, c.y, 96) * 2.0), o, Color(0.6, 0.75, 0.8), 1.3)

	## Bandes jaunes et noires de part et d'autre des sas (murs horizontaux).
	func _door_hazards(atlas: Texture2D) -> void:
		for d: FloorLayout.Door in builder.layout.doors:
			var o := FloorLayout.cell_to_world(d.cell)
			var mod := Color(1, 1, 1, 0.8)
			if d.vertical:
				continue
			_piece(atlas, "decal_hazard", o + Vector2(0, TS * 0.62), mod, 0.42)
			_piece(atlas, "decal_hazard", o + Vector2(0, -TS * 0.42), mod, 0.42)

	## Ambiance : dégradé bleu-vert (plus clair en haut à gauche, abyssal en bas à droite).
	func _mood(L: FloorLayout) -> void:
		var full := Rect2(Vector2(-12, -12) * TS, (Vector2(L.size) + Vector2(24, 24)) * TS)
		var pts := PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)])
		var k := 1.0 + 0.4 * float(-L.floor_index)
		draw_polygon(pts, PackedColorArray([Color(0.3, 0.8, 0.9, 0.06), Color(0.1, 0.4, 0.6, 0.1 * k),
			Color(0.02, 0.08, 0.2, 0.2 * k), Color(0.05, 0.25, 0.4, 0.12 * k)]))

	func _wall_shadows(walls: Texture2D, c: Vector2i) -> void:
		var L := builder.layout
		var o := Vector2(c) * TS
		var gv := UnderwaterBuilder.wall_region("grad_v")
		var gh := UnderwaterBuilder.wall_region("grad_h")
		if FloorLayout.is_opaque_tile(L.get_tile(c + Vector2i.UP)):
			draw_texture_rect_region(walls, Rect2(o, Vector2(TS, 28.0)), gv, Color(UnderwaterBuilder.NIGHT, 0.6))
		if FloorLayout.is_opaque_tile(L.get_tile(c + Vector2i.LEFT)):
			draw_texture_rect_region(walls, Rect2(o, Vector2(18.0, TS)), gh, Color(UnderwaterBuilder.NIGHT, 0.5))

	func _void_edge(walls: Texture2D, c: Vector2i) -> void:
		var L := builder.layout
		var o := Vector2(c) * TS
		if FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN)):
			draw_texture_rect_region(walls, Rect2(o + Vector2(0, TS - 16.0), Vector2(TS, 16.0)), UnderwaterBuilder.wall_region("grad_v_up"), Color(UnderwaterBuilder.NIGHT, 0.5))


# --- Eau peu profonde ---------------------------------------------------------------

func _build_water() -> void:
	var rects: Array[Rect2] = []
	for r: FloorLayout.Room in layout.rooms:
		if r.tags.has("flooded"):
			rects.append(Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS))
	if rects.is_empty():
		return
	var water := WaterLayer.new()
	water.name = "Water"
	water.rects = rects
	water.z_index = 1
	var sh := Shader.new()
	sh.code = WATER_SHADER_CODE
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter(&"caustics", TEX_CAUSTICS)
	var wc := col("water", Color(0.16, 0.5, 0.56, 0.42))
	sm.set_shader_parameter(&"tint", Color(wc.r, wc.g, wc.b, float(_cfg("water_alpha", 0.42))))
	water.material = sm
	add_child(water)


class WaterLayer extends Node2D:
	var rects: Array[Rect2] = []

	func _draw() -> void:
		for r: Rect2 in rects:
			# Bord adouci : bande intérieure un peu moins opaque.
			draw_rect(r, Color(1, 1, 1, 0.75))
			draw_rect(r.grow(-10.0), Color(1, 1, 1, 0.25))


# --- Murs ------------------------------------------------------------------------

func _build_walls() -> void:
	var walls := Node2D.new()
	walls.name = "Walls"
	walls.z_index = 10
	add_child(walls)
	_collect_wall_details()
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
			Rect2(Vector2(-TS, 0), Vector2(TS, full.size.y)),
			Rect2(Vector2(full.end.x, 0), Vector2(TS, full.size.y))]:
		var cs2 := CollisionShape2D.new()
		var shape2 := RectangleShape2D.new()
		shape2.size = side.size
		cs2.shape = shape2
		cs2.position = side.get_center()
		_wall_body.add_child(cs2)


## Face avant d'un mur (case WALL dont le sud est praticable) : {key, v, mod, sea, kind}.
func face_desc(c: Vector2i) -> Dictionary:
	var kind := wall_kind_at(c)
	var v := int(hash01(c.x, c.y, 60) * 4.0)
	var d := {"key": "face_steel", "v": v, "mod": Color.WHITE, "sea": false, "kind": kind}
	var exterior := layout.get_tile(c + Vector2i.UP) == FloorLayout.Tile.VOID
	match kind:
		WallKind.GLASS:
			d["key"] = "face_glass"
			d["sea"] = true
		WallKind.RUST:
			d["key"] = "face_rust"
			d["mod"] = Color(0.92, 0.95, 0.98)
		WallKind.LAB:
			d["key"] = "face_lab"
			if exterior and hash01(c.x, c.y, 61) < 0.35:
				d["key"] = "face_lab_window"
				d["sea"] = true
		_:
			if exterior and hash01(c.x, c.y, 61) < 0.3:
				d["key"] = "face_window"
				d["sea"] = true
	if layout.floor_index == -1 and kind == WallKind.STEEL:
		d["mod"] = Color(0.92, 0.97, 1.0)
	return d


## Lampes murales, alarmes, lueurs des vitrages et rais de lumière (calculés une fois).
func _collect_wall_details() -> void:
	var wall_lamp_gap := int(_cfg("wall_lamp_every", 5))
	for y: int in layout.size.y:
		var run := 0
		for x: int in layout.size.x:
			var c := Vector2i(x, y)
			if layout.get_tile(c) != FloorLayout.Tile.WALL or not FloorLayout.is_walkable_tile(layout.get_tile(c + Vector2i.DOWN)) \
					or layout.get_tile(c + Vector2i.DOWN) == FloorLayout.Tile.STAIRS_UP or layout.get_tile(c + Vector2i.DOWN) == FloorLayout.Tile.STAIRS_DOWN:
				run = 0
				continue
			run += 1
			var fd := face_desc(c)
			var face_mid := Vector2((float(x) + 0.5) * TS, float(y + 1) * TS - wall_height * 0.5)
			if bool(fd["sea"]):
				add_glow(face_mid + Vector2(0, 18), 46.0, CYAN, 0.35)
				if int(fd["kind"]) == WallKind.GLASS and hash01(x, y, 70) < 0.45:
					# Rai de lumière de la surface qui traverse le vitrage et tombe sur le sol du tube.
					_shafts.append([Rect2(face_mid.x - 22.0 + hash01(x, y, 71) * 20.0, float(y + 1) * TS - 20.0, 44.0, TS * 2.4), Color(0.5, 0.95, 1.0, 0.16)])
				continue
			var lamp_here := run % wall_lamp_gap == 2
			if lamp_here:
				var alarm := (layout.floor_index <= -2 and hash01(x, y, 72) < 0.45) or hash01(x, y, 73) < 0.12
				var at := Vector2((float(x) + 0.5) * TS, float(y + 1) * TS - wall_height + 16.0)
				_wall_pieces.append(["kit_wall_alarm" if alarm else "kit_wall_lamp", at])
				if alarm:
					add_glow(at + Vector2(0, 8), 110.0, ALARM, 0.9)
				else:
					add_glow(at + Vector2(0, 10), 150.0, WARM, 1.1)


class WallLayer extends Node2D:
	var builder: UnderwaterBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var tex := UnderwaterBuilder.TEX_WALLS
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				if L.get_tile(c) == FloorLayout.Tile.WALL:
					_draw_wall_cell(tex, c)
		var atlas := UnderwaterProp.ATLAS
		for p: Array in builder._wall_pieces:
			var piece: String = p[0]
			if UnderwaterProp.has_piece(piece):
				draw_texture_rect_region(atlas, UnderwaterProp.piece_dest(piece, p[1]), UnderwaterProp.piece_region(piece))

	func _is_wall(c: Vector2i) -> bool:
		var t := builder.layout.get_tile(c)
		return t == FloorLayout.Tile.WALL or t == FloorLayout.Tile.DOOR

	func _rect(tex: Texture2D, r: Rect2, color: Color) -> void:
		draw_texture_rect_region(tex, r, UnderwaterBuilder.wall_region("white"), color)

	func _draw_wall_cell(tex: Texture2D, c: Vector2i) -> void:
		var L := builder.layout
		var wh := builder.wall_height
		var kind := builder.wall_kind_at(c)
		var face := FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN))
		var o := Vector2(c) * TS
		var cap_h := TS - wh if face else TS
		var cap_key: String = {WallKind.GLASS: "cap_glass", WallKind.RUST: "cap_rust", WallKind.LAB: "cap_lab"}.get(kind, "cap_steel")
		var cr := UnderwaterBuilder.wall_region(cap_key)
		var src := Rect2(cr.position + Vector2(float(posmod(c.x, 2)) * 64.0 * 0.0, 0.0), Vector2(cr.size.x, cr.size.y * cap_h / TS))
		var cap_mod := Color(0.78, 0.84, 0.92) if kind != WallKind.GLASS else Color(0.9, 1.0, 1.0)
		draw_texture_rect_region(tex, Rect2(o, Vector2(TS, cap_h)), src, cap_mod)
		var lit := Color(0.75, 0.95, 1.0, 0.45)
		if not _is_wall(c + Vector2i.UP):
			_rect(tex, Rect2(o + Vector2(0, 2), Vector2(TS, 3)), lit)
			_rect(tex, Rect2(o, Vector2(TS, 2)), UnderwaterBuilder.OUTLINE)
		if not _is_wall(c + Vector2i.LEFT):
			_rect(tex, Rect2(o + Vector2(2, 0), Vector2(3, cap_h)), lit)
			_rect(tex, Rect2(o, Vector2(2, TS)), UnderwaterBuilder.OUTLINE)
		if not _is_wall(c + Vector2i.RIGHT):
			_rect(tex, Rect2(o + Vector2(TS - 5, 0), Vector2(4, cap_h)), Color(UnderwaterBuilder.NIGHT, 0.5))
			_rect(tex, Rect2(o + Vector2(TS - 1.5, 0), Vector2(2, TS)), UnderwaterBuilder.OUTLINE)
		if face:
			var f := Rect2(o + Vector2(0, cap_h), Vector2(TS, wh))
			var fd := builder.face_desc(c)
			draw_texture_rect_region(tex, f, UnderwaterBuilder.wall_region(fd["key"], fd["v"]), fd["mod"])
			var west_open := not _is_wall(c + Vector2i.LEFT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(-1, 1)))
			var east_open := not _is_wall(c + Vector2i.RIGHT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(1, 1)))
			if west_open:
				_rect(tex, Rect2(f.position + Vector2(2, 0), Vector2(3, f.size.y)), Color(0.75, 0.95, 1.0, 0.4))
				_rect(tex, Rect2(f.position, Vector2(2, f.size.y)), UnderwaterBuilder.OUTLINE)
			if east_open:
				draw_texture_rect_region(tex, Rect2(f.end.x - 10.0, f.position.y, 10.0, f.size.y), UnderwaterBuilder.wall_region("grad_h_left"), Color(UnderwaterBuilder.NIGHT, 0.5))
				_rect(tex, Rect2(f.end.x - 1.5, f.position.y, 2, f.size.y), UnderwaterBuilder.OUTLINE)
			_rect(tex, Rect2(f.position.x, f.end.y - 1.5, f.size.x, 2.0), UnderwaterBuilder.OUTLINE)
			_rect(tex, Rect2(o + Vector2(0, cap_h - 1), Vector2(TS, 2)), UnderwaterBuilder.OUTLINE)


# --- Portes ----------------------------------------------------------------------

func _build_doors() -> void:
	for d: FloorLayout.Door in layout.doors:
		var door := UnderwaterDoor.new()
		door.name = "Door_%d" % d.id
		door.setup(d, DoorNode.KIND_VAULT if d.state == FloorLayout.DoorState.LOCKED else UnderwaterDoor.KIND_HATCH, wall_height)
		door.z_index = 10
		add_child(door)
		_doors.append(door)
		if d.state == FloorLayout.DoorState.LOCKED:
			add_glow(FloorLayout.cell_to_world(d.cell) + Vector2(0, 8), 70.0, ALARM, 0.6)


# --- Escaliers (échelles montantes, trappes descendantes) -------------------------------

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
		var vis := StairsPiece.new()
		vis.name = "StairsVisual_%d_%d" % [st.cell.x, st.cell.y]
		vis.piece = "kit_ladder_up" if st.up else "kit_hatch_down"
		vis.up = st.up
		vis.position = FloorLayout.cell_to_world(st.cell) + Vector2(0.0, TS * (0.22 if st.up else 0.08))
		vis.z_index = 10 if st.up else 1
		add_child(vis)
		if st.up:
			add_glow(FloorLayout.cell_to_world(st.cell) + Vector2(0, -10), 90.0, Color(1.0, 0.85, 0.5), 0.7)
		else:
			add_glow(FloorLayout.cell_to_world(st.cell), 70.0, Color(1.0, 0.75, 0.25), 0.45)


func _on_stairs_body_entered(body: Node2D, st: FloorLayout.Stairs) -> void:
	if _stairs_cooldown > 0.0:
		return
	if body.is_in_group(&"player"):
		stairs_entered.emit(st)


## Échelle / trappe (pièce du kit) + flèche de direction.
class StairsPiece extends Node2D:
	var piece: String = ""
	var up: bool = true

	func _draw() -> void:
		if UnderwaterProp.has_piece(piece):
			draw_texture_rect_region(UnderwaterProp.ATLAS, UnderwaterProp.piece_dest(piece, Vector2.ZERO), UnderwaterProp.piece_region(piece))
		var c := Vector2(0, -78.0) if up else Vector2(0, -40.0)
		var s := -1.0 if up else 1.0
		var pts := PackedVector2Array([c + Vector2(-10, 5.0 * -s), c + Vector2(0, -6.0 * -s), c + Vector2(10, 5.0 * -s)])
		draw_polyline(pts, UnderwaterBuilder.OUTLINE, 7.0)
		draw_polyline(pts, Color(1.0, 0.86, 0.3), 3.5)


# --- Décors ----------------------------------------------------------------------

func _build_props() -> void:
	for s: FloorLayout.Spawn in layout.prop_spawns:
		var pos := FloorLayout.cell_to_world(s.cell) + Vector2(0.0, TS * 0.25)
		var p := UnderwaterProp.create(s.kind, pos)
		add_child(p)
		_props.append(p)
		var g := p.get_glow()
		if not g.is_empty():
			add_glow(pos + (g[0] as Vector2), float(g[1]), g[2] as Color, 0.85)


# --- Extraction (capsule de remontée) ---------------------------------------------------

func _build_extraction() -> void:
	if layout.extraction_cells.is_empty():
		return
	var center := Vector2.ZERO
	for c: Vector2i in layout.extraction_cells:
		center += FloorLayout.cell_to_world(c)
	center /= float(layout.extraction_cells.size())
	var hatch := PodHatch.new()
	hatch.name = "EscapePod"
	hatch.position = center + Vector2(0, 26)
	hatch.z_index = 1
	add_child(hatch)
	var glow: Node2D = WorldBuilder.ExtractionGlow.new()
	glow.name = "ExtractionGlow"
	glow.set("cells", layout.extraction_cells.duplicate())
	glow.set("color", col("extraction"))
	glow.set("pulse_speed", float(_cfg("extraction_pulse_speed", 2.2)))
	glow.z_index = 1
	add_child(glow)
	var beacon := ExtractionBeacon.new()
	beacon.name = "ExtractionBeacon"
	beacon.position = center + Vector2(TS * 1.35, TS * 0.3)
	beacon.z_index = 10
	beacon.add_to_group(&"extraction_markers")
	add_child(beacon)
	add_glow(center, 130.0, Color(0.35, 1.0, 0.7), 0.8)
	add_glow(beacon.position + Vector2(0, -50), 70.0, Color(0.35, 1.0, 0.7), 1.0)


## Sas de la capsule de remontée, posé au sol.
class PodHatch extends Node2D:
	func _draw() -> void:
		if UnderwaterProp.has_piece("kit_pod"):
			draw_texture_rect_region(UnderwaterProp.ATLAS, UnderwaterProp.piece_dest("kit_pod", Vector2.ZERO), UnderwaterProp.piece_region("kit_pod"))


## Balise de remontée (bouée + feu vert) : sprite fixe, aucun traitement par image.
class ExtractionBeacon extends Node2D:
	func _draw() -> void:
		if UnderwaterProp.has_piece("kit_beacon"):
			draw_texture_rect_region(UnderwaterProp.ATLAS, UnderwaterProp.piece_dest("kit_beacon", Vector2.ZERO), UnderwaterProp.piece_region("kit_beacon"))


# --- Ambiance ---------------------------------------------------------------------

func _build_ambience() -> void:
	# Plafonniers : flaques de lumière chaude au centre des modules (contraste chaud / froid).
	for r: FloorLayout.Room in layout.rooms:
		if r.type == FloorLayout.ROOM_CORRIDOR:
			continue
		var rr := Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS)
		var rad := clampf(minf(rr.size.x, rr.size.y) * 0.55, 90.0, 230.0)
		var warm := Color(1.0, 0.8, 0.55) if not r.tags.has("flooded") else Color(0.5, 0.9, 1.0)
		if r.tags.size() > 0 and r.tags[0] == "moon_pool":
			for k2: float in [0.12, 0.88]:
				add_glow(Vector2(rr.position.x + rr.size.x * k2, rr.get_center().y + 40.0), rad * 0.8, warm, 0.5)
		elif r.rect.size.x > r.rect.size.y * 1.6:
			for k: float in [0.3, 0.7]:
				add_glow(Vector2(rr.position.x + rr.size.x * k, rr.get_center().y), rad, warm, 0.45)
		else:
			add_glow(rr.get_center(), rad, warm, 0.5)
	var cm := CanvasModulate.new()
	cm.name = "AmbientTint"
	var defaults := {0: Color(0.66, 0.78, 0.88), -1: Color(0.66, 0.78, 0.86), -2: Color(0.54, 0.68, 0.8)}
	var idx := clampi(layout.floor_index, -2, 0)
	var v: Variant = _cfg("ambient_%d" % absi(idx), defaults[idx])
	cm.color = v if v is Color else defaults[idx]
	add_child(cm)
	var glows := GlowLayer.new()
	glows.name = "Glows"
	glows.glows = _glows
	glows.shafts = _shafts
	glows.strength = float(_cfg("glow_strength", 1.0))
	glows.material = WorldProp.glow_material()
	glows.z_index = 45
	glows.z_as_relative = false
	add_child(glows)
	_build_bubbles()


## Bulles qui montent (une seule couche de particules GPU).
func _build_bubbles() -> void:
	var amount := int(_cfg("bubbles_amount", 60))
	if amount <= 0:
		return
	var area := Rect2()
	var first := true
	for r: FloorLayout.Room in layout.rooms:
		var rr := Rect2(Vector2(r.rect.position) * TS, Vector2(r.rect.size) * TS)
		area = rr if first else area.merge(rr)
		first = false
	if first:
		return
	var p := GPUParticles2D.new()
	p.name = "Bubbles"
	p.amount = amount + (amount / 2 if layout.floor_index <= -2 else 0)
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.texture = TEX_BUBBLE
	p.z_index = 46
	p.z_as_relative = false
	p.position = area.get_center()
	p.visibility_rect = Rect2(-area.size * 0.5 - Vector2(64, 64), area.size + Vector2(128, 128))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area.size.x * 0.5, area.size.y * 0.5, 0.0)
	pm.direction = Vector3(0.1, -1.0, 0.0)
	pm.spread = 12.0
	pm.initial_velocity_min = 10.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.12
	pm.scale_max = 0.45
	var grad := Gradient.new()
	var c := Color(0.75, 0.95, 1.0)
	grad.set_color(0, Color(c, 0.0))
	grad.set_color(1, Color(c, 0.0))
	grad.add_point(0.2, Color(c, 0.4))
	grad.add_point(0.8, Color(c, 0.3))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	add_child(p)


## Lueurs additives précalculées (sprite radial de l'atlas) et rais de lumière.
class GlowLayer extends Node2D:
	var glows: Array = []
	var shafts: Array = []
	var strength: float = 1.0

	func _draw() -> void:
		var atlas := UnderwaterProp.ATLAS
		if UnderwaterProp.has_piece("decal_shaft"):
			var sreg := UnderwaterProp.piece_region("decal_shaft")
			for s: Array in shafts:
				draw_texture_rect_region(atlas, s[0], sreg, Color(s[1], (s[1] as Color).a * strength))
		if not UnderwaterProp.has_piece("glow"):
			return
		var reg := UnderwaterProp.piece_region("glow")
		for g: Array in glows:
			var p: Vector2 = g[0]
			var rad: float = g[1]
			var c: Color = g[2]
			var k: float = float(g[3]) * strength
			draw_texture_rect_region(atlas, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), reg, Color(c, 0.45 * k))
			draw_texture_rect_region(atlas, Rect2(p - Vector2(rad, rad) * 0.35, Vector2(rad, rad) * 0.7), reg, Color(c.lightened(0.4), 0.35 * k))
