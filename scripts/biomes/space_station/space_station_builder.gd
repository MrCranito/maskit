class_name SpaceStationBuilder
extends Node2D
## Constructeur du décor d'un pont de la Station Orbitale Kagami (même API que WorldBuilder,
## cf. docs/CONVENTIONS.md « Cartes et biomes ») :
##   SpaceStationBuilder.build(layout, world) -> SpaceStationBuilder (Node2D, y_sort)
##   get_doors(), get_stairs_areas() (meta `stairs`), signal stairs_entered(stairs),
##   get_room_at_world(pos), set_stairs_cooldown(sec), get_wall_body(), get_props().
## Contenu : espace étoilé + planète dans le vide, sols métalliques tuilables par matière
## (shader commun), décalques/ombres/bandes de danger (un nœud dessiné une fois), murs 3/4
## (faces : panneaux, conduites, hublots sur la coque, écrans ambrés, alarmes rouges),
## collisions fusionnées (couche world), portes coulissantes (ss_door.gd), ascenseurs,
## décors (atlas), capsules d'extraction, teinte froide, lueurs précalculées (néons cyan,
## écrans, alarmes rouges pulsées par simple modulation), une couche de particules.
## Performance : aucun _draw par image, aucune lumière dynamique, 2 atlas + 7 textures.
## Assets : art/blender/space_station/*.py

signal stairs_entered(stairs: FloorLayout.Stairs)

const TS := float(FloorLayout.TILE_SIZE)
const LAYER_WORLD := 1
const MASK_PLAYER := 2
const DIR_TEX := "res://assets/textures/space_station/"
const TEX_DECK: Texture2D = preload("res://assets/textures/space_station/floor_deck.png")
const TEX_GRATE: Texture2D = preload("res://assets/textures/space_station/floor_grate.png")
const TEX_HANGAR: Texture2D = preload("res://assets/textures/space_station/floor_hangar.png")
const TEX_LAB: Texture2D = preload("res://assets/textures/space_station/floor_lab.png")
const TEX_ENGINE: Texture2D = preload("res://assets/textures/space_station/floor_engine.png")
const TEX_COMMAND: Texture2D = preload("res://assets/textures/space_station/floor_command.png")
const TEX_SPACE: Texture2D = preload("res://assets/textures/space_station/space.png")
const TEX_WALLS: Texture2D = preload("res://assets/textures/space_station/walls.png")
const TEX_MOTE: Texture2D = preload("res://assets/textures/space_station/mote.png")
const TEX_MACRO: Texture2D = preload("res://assets/textures/ground/macro.png")
const GROUND_SHADER: Shader = preload("res://assets/shaders/ground.gdshader")
const WallsMeta := preload("res://assets/textures/space_station/walls_meta.gd")
const Prop := preload("res://scripts/biomes/space_station/ss_prop.gd")
const DoorScript := preload("res://scripts/biomes/space_station/ss_door.gd")
const TILE_TEX_WORLD := 256.0
const OUTLINE := Color(0.04, 0.05, 0.09)
const SHADOW := Color(0.03, 0.05, 0.16)
const COOL := Color(0.72, 0.9, 1.0)
const CYAN := Color(0.35, 0.88, 1.0)
const AMBER := Color(1.0, 0.66, 0.22)
const RED := Color(1.0, 0.2, 0.14)

enum Ground { VOID, DECK, GRATE, HANGAR, LAB, ENGINE, COMMAND }

const GROUND_TEX := {
	Ground.DECK: [TEX_DECK, 0.1, Color(1, 1, 1)], Ground.GRATE: [TEX_GRATE, 0.08, Color(0.95, 0.97, 1.0)],
	Ground.HANGAR: [TEX_HANGAR, 0.14, Color(1, 1, 1)], Ground.LAB: [TEX_LAB, 0.06, Color(0.66, 0.72, 0.82)],
	Ground.ENGINE: [TEX_ENGINE, 0.16, Color(1, 0.97, 0.95)], Ground.COMMAND: [TEX_COMMAND, 0.08, Color(1, 1, 1)],
}
const LAB_ROLES := {"lab": true, "lab_vault": true, "infirmary": true, "hydroponics": true}

## Conteneurs et cachettes propres au biome (absents de LootContainer.DEFS / HidingSpot.DEFS :
## voir _patch_loot). Mêmes clés que ces DEFS.
const CONTAINER_DEFS := {
	&"locker": {"name": "Casier", "scale": 0.55, "block": Vector2(36, 14), "reach": 4.0, "shadow": 20.0, "foot": 4.0},
	&"cargo_crate": {"name": "Caisse cargo", "scale": 0.55, "block": Vector2(54, 18), "reach": 2.0, "shadow": 32.0, "foot": 4.0},
	&"med_cabinet": {"name": "Armoire médicale", "scale": 0.55, "block": Vector2(48, 14), "reach": 4.0, "shadow": 28.0, "foot": 4.0},
	&"armory_chest": {"name": "Coffre d'armurerie", "scale": 0.55, "block": Vector2(60, 18), "reach": 4.0, "shadow": 34.0, "foot": 4.0},
	&"cryo_pod": {"name": "Capsule cryogénique", "scale": 0.55, "block": Vector2(84, 22), "reach": 14.0, "shadow": 46.0, "foot": 4.0},
	&"terminal": {"name": "Terminal", "scale": 0.55, "block": Vector2(40, 16), "reach": 4.0, "shadow": 24.0, "foot": 4.0},
}
const HIDING_DEFS := {
	&"locker": {"name": "Casier double", "scale": 0.55, "block": Vector2(50, 14), "shadow": 28.0, "foot": 4.0, "reach": 4.0},
	&"vent": {"name": "Conduit d'aération", "scale": 0.55, "block": Vector2(54, 16), "shadow": 0.0, "foot": 4.0, "reach": 8.0},
	&"cryo": {"name": "Capsule cryogénique", "scale": 0.55, "block": Vector2(40, 16), "shadow": 24.0, "foot": 4.0, "reach": 4.0},
}
## Grands décors : décalage (monde) du centre de l'empreinte depuis la case d'appui.
## Échelle des décors muraux de l'aménagement.
const WALL_DECOR_SCALE := 1.3
const BIG_OFFSET := {&"shuttle": Vector2(0, -64), &"reactor_core": Vector2(-32, -32)}

var layout: FloorLayout = null
var palette: Dictionary = {}
var wall_height: float = 52.0

var _doors: Array[DoorNode] = []
var _stairs_areas: Array[Area2D] = []
var _props: Array[Node2D] = []
var _wall_body: StaticBody2D = null
var _stairs_cooldown: float = 0.5
var _room_grid: PackedInt32Array = PackedInt32Array()
## Lueurs fixes [pos, rayon, couleur, force] et alarmes pulsées [pos, rayon].
var _glows: Array = []
var _alarms: Array = []
var _container_kind: Dictionary = {}
var _hiding_kind: Dictionary = {}
## (Pré-rendu) Toits logiques des modules fermés (layout.buildings) : BuildingRoof sans dessin
## (roof_rect vide) dont le fondu « joueur dedans » pilote les intérieurs du fond pré-calculé
## (PrerenderBackdrop.attach_to, même contrat que WorldBuilder.get_roofs()).
var _roofs: Array[BuildingRoof] = []


static func build(p_layout: FloorLayout, world: Resource = null) -> SpaceStationBuilder:
	var root := SpaceStationBuilder.new()
	root.name = "World"
	root.layout = p_layout
	root._build(world)
	return root


# --- API -----------------------------------------------------------------------------

func get_doors() -> Array[DoorNode]:
	return _doors


func get_stairs_areas() -> Array[Area2D]:
	return _stairs_areas


func get_props() -> Array[Node2D]:
	return _props


func get_wall_body() -> StaticBody2D:
	return _wall_body


func get_roofs() -> Array[BuildingRoof]:
	return _roofs


## (Pré-rendu) Masque les visuels remplacés par le fond pré-calculé (espace, plateformes
## d'ascenseur, lueurs et alarmes peintes) ; PrerenderBackdrop.attach_to masque déjà Ground,
## Walls (visuels), FloorDetails et les décors, et neutralise AmbientTint.
func prerender_hide() -> void:
	for nm: String in ["Space", "LiftVisual", "Glows", "Alarms"]:
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


func set_stairs_cooldown(sec: float) -> void:
	_stairs_cooldown = maxf(sec, 0.0)
	set_process(_stairs_cooldown > 0.0)


func _process(delta: float) -> void:
	if _stairs_cooldown > 0.0:
		_stairs_cooldown = maxf(_stairs_cooldown - delta, 0.0)
	else:
		set_process(false)


# --- Construction ----------------------------------------------------------------------

func _cfg(key: String, def: Variant) -> Variant:
	var v: Variant = Balance.get_value("space_station", key, null)
	return def if v == null else v


func _build(world: Resource) -> void:
	y_sort_enabled = true
	if layout == null:
		push_warning("SpaceStationBuilder: layout null.")
		return
	if world != null and world.get("palette") is Dictionary:
		palette = (world.get("palette") as Dictionary).duplicate()
	wall_height = float(_cfg("wall_height", 52.0))
	_stairs_cooldown = float(_cfg("stairs_cooldown", 0.5))
	_build_grid()
	_build_space()
	_build_ground()
	_build_walls()
	_build_doors()
	_build_stairs()
	_build_props()
	_build_extraction()
	_build_roofs()
	_build_lights()
	_build_ambience()
	_prepare_loot_patch()


func _build_grid() -> void:
	var n := layout.size.x * layout.size.y
	_room_grid.resize(n)
	_room_grid.fill(-1)
	var rooms := layout.rooms.duplicate()
	rooms.sort_custom(func(a: FloorLayout.Room, b: FloorLayout.Room) -> bool: return a.rect.get_area() > b.rect.get_area())
	var w := layout.size.x
	for r: FloorLayout.Room in rooms:
		for y: int in range(maxi(r.rect.position.y, 0), mini(r.rect.end.y, layout.size.y)):
			for x: int in range(maxi(r.rect.position.x, 0), mini(r.rect.end.x, w)):
				_room_grid[y * w + x] = r.id


func room_at_cell(c: Vector2i) -> FloorLayout.Room:
	if not layout.in_bounds(c):
		return null
	var id := _room_grid[c.y * layout.size.x + c.x]
	return layout.get_room(id) if id >= 0 else null


static func role_of(r: FloorLayout.Room) -> String:
	return r.tags[0] if r != null and r.tags.size() > 0 else ""


static func is_corridor(r: FloorLayout.Room) -> bool:
	return r != null and (r.tags.has("corridor") or r.tags.has("conduit"))


## Hash déterministe [0, 1) d'une case.
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


# --- Espace ------------------------------------------------------------------------------

## Le vide hors coque : ciel étoilé tuilé (une seule texture répétée) + planète annelée.
func _build_space() -> void:
	var sp := SpaceLayer.new()
	sp.name = "Space"
	sp.builder = self
	sp.z_index = -1
	sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(sp)


class SpaceLayer extends Node2D:
	var builder: SpaceStationBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var full := Rect2(Vector2(-14, -14) * TS, (Vector2(L.size) + Vector2(28, 28)) * TS)
		draw_texture_rect(SpaceStationBuilder.TEX_SPACE, full, true, Color(0.9, 0.95, 1.0))
		# Planète annelée et lune, à l'ouest et au nord-est de la station.
		var reg := SpaceStationBuilder.wall_region("planet")
		var pr := Rect2(Vector2(-9.5, float(L.size.y) * 0.25) * TS, Vector2(9.0, 9.0) * TS)
		draw_texture_rect_region(SpaceStationBuilder.TEX_WALLS, pr, reg)
		var mreg := SpaceStationBuilder.wall_region("moon")
		draw_texture_rect_region(SpaceStationBuilder.TEX_WALLS, Rect2(Vector2(float(L.size.x) + 2.0, -6.0) * TS, Vector2(3.0, 3.0) * TS), mreg)


# --- Sol -----------------------------------------------------------------------------------

func ground_at(c: Vector2i) -> int:
	var t := layout.get_tile(c)
	if not FloorLayout.is_walkable_tile(t):
		return Ground.VOID
	var r := room_at_cell(c)
	if t == FloorLayout.Tile.DOOR:
		r = room_at_cell(c + Vector2i.DOWN) if room_at_cell(c + Vector2i.DOWN) != null else r
	if r == null or is_corridor(r):
		return Ground.GRATE
	var role := role_of(r)
	if role == "hangar" or role == "pod_bay":
		return Ground.HANGAR
	if LAB_ROLES.has(role):
		return Ground.LAB
	if layout.floor_index < 0:
		return Ground.ENGINE
	if layout.floor_index > 0:
		return Ground.COMMAND
	return Ground.DECK


func _build_ground() -> void:
	var ground := Node2D.new()
	ground.name = "Ground"
	add_child(ground)
	var w := layout.size.x
	var h := layout.size.y
	var key := PackedInt32Array()
	key.resize(w * h)
	for y: int in h:
		for x: int in w:
			var c := Vector2i(x, y)
			# Les murs reçoivent le sol de la case du dessous (rien ne transparaît sous la face).
			var g := ground_at(c)
			if g == Ground.VOID and layout.get_tile(c) == FloorLayout.Tile.WALL:
				g = ground_at(c + Vector2i.DOWN)
				if g == Ground.VOID:
					g = Ground.GRATE
			key[y * w + x] = g
	for g2: int in GROUND_TEX:
		var rects := _merge_key(key, g2)
		if rects.is_empty():
			continue
		var m: Array = GROUND_TEX[g2]
		var layer := GroundLayer.new()
		layer.name = "Ground_%s" % Ground.keys()[g2]
		layer.rects = rects
		layer.tint = m[2]
		var sm := ShaderMaterial.new()
		sm.shader = GROUND_SHADER
		sm.set_shader_parameter(&"tex_a", m[0])
		sm.set_shader_parameter(&"tex_b", m[0])
		sm.set_shader_parameter(&"macro", TEX_MACRO)
		sm.set_shader_parameter(&"tile_world", TILE_TEX_WORLD)
		sm.set_shader_parameter(&"b_amount", 0.0)
		sm.set_shader_parameter(&"value_var", m[1])
		sm.set_shader_parameter(&"warp", 0.0)
		layer.material = sm
		ground.add_child(layer)
	var decals := GroundDecals.new()
	decals.name = "Decals"
	decals.builder = self
	decals.z_index = 1
	ground.add_child(decals)


func _merge_key(key: PackedInt32Array, v: int) -> Array[Rect2]:
	var w := layout.size.x
	var h := layout.size.y
	var used := PackedByteArray()
	used.resize(w * h)
	var out: Array[Rect2] = []
	for y: int in h:
		var x := 0
		while x < w:
			if key[y * w + x] != v or used[y * w + x] != 0:
				x += 1
				continue
			var x1 := x
			while x1 < w and key[y * w + x1] == v and used[y * w + x1] == 0:
				x1 += 1
			var y1 := y + 1
			while y1 < h:
				var ok := true
				for xx: int in range(x, x1):
					if key[y1 * w + xx] != v or used[y1 * w + xx] != 0:
						ok = false
						break
				if not ok:
					break
				y1 += 1
			for yy: int in range(y, y1):
				for xx2: int in range(x, x1):
					used[yy * w + xx2] = 1
			out.append(Rect2(Vector2(x, y) * TS, Vector2(x1 - x, y1 - y) * TS))
			x = x1
	return out


class GroundLayer extends Node2D:
	var rects: Array[Rect2] = []
	var tint: Color = Color.WHITE

	func _draw() -> void:
		for r: Rect2 in rects:
			draw_rect(r, tint)


## Décalques (atlas des décors), ombres des murs, seuils à bandes, balisage : dessinés une fois.
class GroundDecals extends Node2D:
	var builder: SpaceStationBuilder = null

	func _piece(piece: String, center: Vector2, mod: Color = Color.WHITE, k: float = 1.0, rot: float = 0.0) -> void:
		if not Prop.has_piece(piece):
			return
		var reg := Prop.piece_region(piece)
		var size := reg.size / Prop.PX_PER_WORLD * k
		if rot != 0.0:
			draw_set_transform(center, rot, Vector2.ONE)
			draw_texture_rect_region(Prop.ATLAS, Rect2(-size * 0.5, size), reg, mod)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(Prop.ATLAS, Rect2(center - size * 0.5, size), reg, mod)

	func _draw() -> void:
		var L := builder.layout
		var walls := SpaceStationBuilder.TEX_WALLS
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				var t := L.get_tile(c)
				if t != FloorLayout.Tile.FLOOR:
					continue
				_detail(c)
		_corridor_strips()
		_door_thresholds()
		_hangar_marks()
		# Ombres et occlusion par-dessus.
		var gv := SpaceStationBuilder.wall_region("grad_v")
		var gh := SpaceStationBuilder.wall_region("grad_h")
		var gl := SpaceStationBuilder.wall_region("grad_h_left")
		for y2: int in L.size.y:
			for x2: int in L.size.x:
				var c2 := Vector2i(x2, y2)
				if not FloorLayout.is_walkable_tile(L.get_tile(c2)):
					continue
				var o := Vector2(c2) * TS
				if FloorLayout.is_opaque_tile(L.get_tile(c2 + Vector2i.UP)):
					draw_texture_rect_region(walls, Rect2(o, Vector2(TS, 30.0)), gv, Color(SpaceStationBuilder.SHADOW, 0.6))
				if FloorLayout.is_opaque_tile(L.get_tile(c2 + Vector2i.LEFT)):
					draw_texture_rect_region(walls, Rect2(o, Vector2(20.0, TS)), gh, Color(SpaceStationBuilder.SHADOW, 0.5))
				if FloorLayout.is_opaque_tile(L.get_tile(c2 + Vector2i.RIGHT)):
					draw_texture_rect_region(walls, Rect2(o + Vector2(TS - 14.0, 0), Vector2(14.0, TS)), gl, Color(SpaceStationBuilder.SHADOW, 0.35))

	func _detail(c: Vector2i) -> void:
		var h := SpaceStationBuilder.hash01(c.x, c.y, 1)
		var o := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		var j := Vector2(SpaceStationBuilder.hash01(c.x, c.y, 2) - 0.5, SpaceStationBuilder.hash01(c.x, c.y, 3) - 0.5) * TS * 0.5
		var rot := SpaceStationBuilder.hash01(c.x, c.y, 4) * TAU
		var r := builder.room_at_cell(c)
		var corridor := SpaceStationBuilder.is_corridor(r)
		var machines := builder.layout.floor_index < 0
		if h < 0.035:
			_piece("decal_oil", o + j, Color(1, 1, 1, 0.75), 1.0, rot)
		elif h < 0.05 and (machines or SpaceStationBuilder.role_of(r) in ["pumps", "coolant", "reactor", "lab"]):
			_piece("decal_coolant", o + j, Color(1, 1, 1, 0.85), 0.9, rot)
		elif h < 0.065:
			_piece("decal_papers", o + j, Color(1, 1, 1, 0.8), 1.0, rot)
		elif h < 0.075:
			_piece("decal_scorch", o + j, Color(1, 1, 1, 0.7), 1.0, rot)
		elif h < 0.095 and not corridor:
			_piece("decal_drain", o, Color(1, 1, 1, 0.9), 0.8)
		elif h < 0.11 and corridor:
			_piece("decal_cables", o + Vector2(0, j.y), Color(1, 1, 1, 0.9), 1.0, 0.0 if r.rect.size.x >= r.rect.size.y else PI * 0.5)

	## Balisage lumineux le long des coursives (bord nord) et flèches aux carrefours.
	func _corridor_strips() -> void:
		var L := builder.layout
		for r: FloorLayout.Room in L.rooms:
			if not SpaceStationBuilder.is_corridor(r):
				continue
			var horiz := r.rect.size.x >= r.rect.size.y
			if horiz:
				var y := float(r.rect.end.y) * TS - 8.0
				for x: int in range(r.rect.position.x, r.rect.end.x):
					if L.get_tile(Vector2i(x, r.rect.end.y)) == FloorLayout.Tile.WALL and L.get_tile(Vector2i(x, r.rect.end.y - 1)) == FloorLayout.Tile.FLOOR:
						_piece("decal_lightstrip", Vector2((float(x) + 0.5) * TS, y), Color(1, 1, 1, 0.85), 0.5)
			else:
				var xw := float(r.rect.position.x) * TS + 6.0
				for y2: int in range(r.rect.position.y, r.rect.end.y):
					if L.get_tile(Vector2i(r.rect.position.x - 1, y2)) == FloorLayout.Tile.WALL and L.get_tile(Vector2i(r.rect.position.x, y2)) == FloorLayout.Tile.FLOOR:
						_piece("decal_lightstrip", Vector2(xw, (float(y2) + 0.5) * TS), Color(1, 1, 1, 0.85), 0.5, PI * 0.5)
			if r.rect.get_area() >= 12 and SpaceStationBuilder.hash01(r.rect.position.x, r.rect.position.y, 9) < 0.7:
				var ctr := (Vector2(r.rect.position) + Vector2(r.rect.size) * 0.5) * TS
				_piece("decal_arrow", ctr, Color(1, 1, 1, 0.55), 0.9, (PI * 0.5 if horiz else 0.0) + (PI if SpaceStationBuilder.hash01(r.id, 3, 5) < 0.5 else 0.0))

	## Bandes jaunes et noires au sol de part et d'autre de chaque sas.
	func _door_thresholds() -> void:
		var L := builder.layout
		for d: FloorLayout.Door in L.doors:
			var o := (Vector2(d.cell) + Vector2(0.5, 0.5)) * TS
			var col := Color(1, 0.55, 0.55, 0.9) if d.state == FloorLayout.DoorState.LOCKED else Color(1, 1, 1, 0.85)
			if d.vertical:
				for sx: float in [-1.0, 1.0]:
					_piece("decal_hazard", o + Vector2(sx * TS * 0.62, 0), col, 0.5, PI * 0.5)
			else:
				for sy: float in [-1.0, 1.0]:
					_piece("decal_hazard", o + Vector2(0, sy * TS * 0.62), col, 0.5)

	## Hangar : cadre de bandes autour de l'aire de la navette.
	func _hangar_marks() -> void:
		var L := builder.layout
		for s: FloorLayout.Spawn in L.prop_spawns:
			if s.kind != &"shuttle":
				continue
			var ctr := FloorLayout.cell_to_world(s.cell) + SpaceStationBuilder.BIG_OFFSET[&"shuttle"]
			var half := Vector2(TS * 2.4, TS * 1.7)
			var x := -half.x
			while x < half.x - 1.0:
				_piece("decal_hazard", ctr + Vector2(x + 32.0, -half.y), Color(1, 1, 1, 0.7), 0.5)
				_piece("decal_hazard", ctr + Vector2(x + 32.0, half.y), Color(1, 1, 1, 0.7), 0.5)
				x += 64.0


# --- Murs ------------------------------------------------------------------------------------

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
			Rect2(Vector2(-TS, 0), Vector2(TS, full.size.y)),
			Rect2(Vector2(full.end.x, 0), Vector2(TS, full.size.y))]:
		var cs2 := CollisionShape2D.new()
		var shape2 := RectangleShape2D.new()
		shape2.size = side.size
		cs2.shape = shape2
		cs2.position = side.get_center()
		_wall_body.add_child(cs2)


func is_hull(c: Vector2i) -> bool:
	var n := c + Vector2i.UP
	return not layout.in_bounds(n) or layout.get_tile(n) == FloorLayout.Tile.VOID


## Face avant d'un mur dont le sud est praticable : {key, v, glow: Color|null, alarm: bool}.
func face_desc(c: Vector2i) -> Dictionary:
	var south := c + Vector2i.DOWN
	var r := room_at_cell(south)
	var role := role_of(r)
	var corr := is_corridor(r)
	var h := hash01(c.x, c.y, 60)
	var v := int(hash01(c.x, c.y, 61) * 4.0)
	var d := {"key": "face_panel", "v": v, "glow": null, "alarm": false}
	var deck := layout.floor_index
	var win_chance := 0.25 if deck < 0 else 0.6
	if is_hull(c) and hash01(c.x, c.y, 62) < win_chance and layout.get_tile(c + Vector2i.LEFT) == FloorLayout.Tile.WALL and layout.get_tile(c + Vector2i.RIGHT) == FloorLayout.Tile.WALL:
		d["key"] = "face_window"
		d["glow"] = Color(0.45, 0.65, 1.0)
		return d
	if h < 0.05:
		d["key"] = "face_alarm"
		d["alarm"] = true
		return d
	if h < 0.13:
		d["key"] = "face_screen"
		d["v"] = 0 if hash01(c.x, c.y, 63) < 0.5 else 1
		d["glow"] = AMBER if d["v"] == 0 else CYAN
		return d
	if deck < 0:
		d["key"] = "face_machine"
		if v == 2:
			d["glow"] = AMBER
	elif corr:
		d["key"] = "face_pipes" if deck == 0 or hash01(c.x, c.y, 64) < 0.5 else "face_panel"
	elif LAB_ROLES.has(role):
		d["key"] = "face_lab"
	elif deck > 0:
		d["key"] = "face_command"
	return d


func cap_key(c: Vector2i) -> String:
	if is_hull(c):
		return "cap_hull"
	if layout.floor_index < 0:
		return "cap_machine"
	if layout.floor_index > 0:
		return "cap_command"
	return "cap_metal"


class WallLayer extends Node2D:
	var builder: SpaceStationBuilder = null

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
		draw_texture_rect_region(SpaceStationBuilder.TEX_WALLS, r, SpaceStationBuilder.wall_region("white"), col)

	func _cell(c: Vector2i) -> void:
		var L := builder.layout
		var tex := SpaceStationBuilder.TEX_WALLS
		var wh := builder.wall_height
		var face := FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN))
		var o := Vector2(c) * TS
		var cap_h := TS - wh if face else TS
		var cr := SpaceStationBuilder.wall_region(builder.cap_key(c))
		var src := Rect2(cr.position + Vector2(float(posmod(c.x, 2)) * 0.0, 0.0), Vector2(cr.size.x, cr.size.y * cap_h / TS))
		draw_texture_rect_region(tex, Rect2(o, Vector2(TS, cap_h)), src, Color(0.8, 0.86, 0.98))
		var lit := Color(0.62, 0.86, 1.0, 0.55)
		if not _is_wall(c + Vector2i.UP):
			_rect(Rect2(o + Vector2(0, 2), Vector2(TS, 2.5)), lit)
			_rect(Rect2(o, Vector2(TS, 2)), OUTLINE)
		if not _is_wall(c + Vector2i.LEFT):
			_rect(Rect2(o + Vector2(2, 0), Vector2(2.5, cap_h)), lit)
			_rect(Rect2(o, Vector2(2, TS)), OUTLINE)
		if not _is_wall(c + Vector2i.RIGHT):
			_rect(Rect2(o + Vector2(TS - 5, 0), Vector2(4, cap_h)), Color(SpaceStationBuilder.SHADOW, 0.55))
			_rect(Rect2(o + Vector2(TS - 1.5, 0), Vector2(2, TS)), OUTLINE)
		if not face:
			if not _is_wall(c + Vector2i.DOWN) and L.get_tile(c + Vector2i.DOWN) == FloorLayout.Tile.VOID:
				_rect(Rect2(o + Vector2(0, TS - 2), Vector2(TS, 2)), OUTLINE)
			return
		var f := Rect2(o + Vector2(0, cap_h), Vector2(TS, wh))
		var fd := builder.face_desc(c)
		draw_texture_rect_region(tex, f, SpaceStationBuilder.wall_region(fd["key"], fd["v"]), Color(0.92, 0.95, 1.0))
		var wd: Variant = L.wall_decor_cells.get(c, null)
		if wd != null and Prop.has_piece(String(wd)):
			# Décor mural de l'aménagement (écran, grille, signalétique…), posé sur la face.
			draw_texture_rect_region(Prop.ATLAS, Prop.piece_dest(String(wd), Vector2(f.get_center().x, f.end.y - 4.0), WALL_DECOR_SCALE), Prop.piece_region(String(wd)))
		var west_open := not _is_wall(c + Vector2i.LEFT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(-1, 1)))
		var east_open := not _is_wall(c + Vector2i.RIGHT) or FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i(1, 1)))
		if west_open:
			_rect(Rect2(f.position + Vector2(2, 0), Vector2(3, f.size.y)), Color(0.6, 0.85, 1.0, 0.45))
			_rect(Rect2(f.position, Vector2(2, f.size.y)), OUTLINE)
		if east_open:
			draw_texture_rect_region(tex, Rect2(f.end.x - 10.0, f.position.y, 10.0, f.size.y), SpaceStationBuilder.wall_region("grad_h_left"), Color(SpaceStationBuilder.SHADOW, 0.55))
			_rect(Rect2(f.end.x - 1.5, f.position.y, 2, f.size.y), OUTLINE)
		_rect(Rect2(o + Vector2(0, cap_h - 1), Vector2(TS, 2)), OUTLINE)
		_rect(Rect2(f.position.x, f.end.y - 1.5, f.size.x, 2.0), OUTLINE)


## Lueurs des faces de murs (hublots, écrans, voyants) + alarmes pulsées.
func _collect_wall_glows() -> void:
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			var c := Vector2i(x, y)
			if layout.get_tile(c) != FloorLayout.Tile.WALL or not FloorLayout.is_walkable_tile(layout.get_tile(c + Vector2i.DOWN)):
				continue
			var fd := face_desc(c)
			var base := Vector2((float(x) + 0.5) * TS, float(y + 1) * TS)
			if bool(fd["alarm"]):
				_alarms.append([base + Vector2(0, -wall_height * 0.6), 120.0])
			elif fd["glow"] is Color:
				add_glow(base + Vector2(0, 8.0), 70.0, fd["glow"], 0.7)


# --- Portes ----------------------------------------------------------------------------------

func _build_doors() -> void:
	for d: FloorLayout.Door in layout.doors:
		var door: DoorNode = DoorScript.new()
		door.name = "Door_%d" % d.id
		door.setup(d, DoorNode.KIND_VAULT if d.state == FloorLayout.DoorState.LOCKED else DoorNode.KIND_WOOD, wall_height)
		door.z_index = 10
		add_child(door)
		_doors.append(door)
		var col := RED if d.state != FloorLayout.DoorState.OPEN else Color(0.4, 1.0, 0.5)
		if d.state == FloorLayout.DoorState.LOCKED:
			col = AMBER
		if not d.vertical:
			add_glow(Vector2((float(d.cell.x) + 0.5) * TS, float(d.cell.y) * TS + 6.0), 34.0, col, 0.5)


# --- Ascenseurs ------------------------------------------------------------------------------

func _build_stairs() -> void:
	var vis := LiftVisual.new()
	vis.name = "LiftVisual"
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
		add_glow(FloorLayout.cell_to_world(st.cell), 110.0, CYAN if st.up else AMBER, 1.0)
		_stairs_areas.append(area)


func _on_stairs_body_entered(body: Node2D, st: FloorLayout.Stairs) -> void:
	if _stairs_cooldown > 0.0:
		return
	if body.is_in_group(&"player"):
		stairs_entered.emit(st)


## Plateforme d'ascenseur : disque métallique, anneau lumineux, chevrons (montée cyan,
## descente ambre).
class LiftVisual extends Node2D:
	var builder: SpaceStationBuilder = null

	func _draw() -> void:
		for st: FloorLayout.Stairs in builder.layout.stairs:
			var c := FloorLayout.cell_to_world(st.cell)
			var col := SpaceStationBuilder.CYAN if st.up else SpaceStationBuilder.AMBER
			draw_rect(Rect2(c - Vector2(TS, TS) * 0.5, Vector2(TS, TS)).grow(-2.0), Color(0.12, 0.13, 0.18))
			draw_circle(c + Vector2(3, 4), TS * 0.44, Color(0.02, 0.03, 0.1, 0.5))
			draw_circle(c, TS * 0.44, OUTLINE)
			draw_circle(c, TS * 0.42, Color(0.32, 0.35, 0.44))
			draw_circle(c, TS * 0.34, Color(col, 0.9))
			draw_circle(c, TS * 0.3, Color(0.08, 0.1, 0.16))
			draw_arc(c, TS * 0.42, PI * 1.05, PI * 1.6, 12, Color(0.75, 0.82, 0.95), 2.0)
			for k: int in 8:
				var a := float(k) * TAU / 8.0
				draw_line(c + Vector2.from_angle(a) * TS * 0.36, c + Vector2.from_angle(a) * TS * 0.42, OUTLINE, 2.0)
			var s := -1.0 if st.up else 1.0
			for i: int in 2:
				var oy := (float(i) * 9.0 - 4.5) * s
				var pts := PackedVector2Array([c + Vector2(-9, oy + 4.0 * -s), c + Vector2(0, oy - 4.0 * -s), c + Vector2(9, oy + 4.0 * -s)])
				draw_polyline(pts, OUTLINE, 6.0)
				draw_polyline(pts, col.lightened(0.3), 3.0)


# --- Décors ----------------------------------------------------------------------------------

func _build_props() -> void:
	# Une seule StaticBody2D pour toutes les collisions de décors (shape owners).
	var shared := Prop.make_shared_body()
	add_child(shared)
	if not layout.decor_spawns.is_empty():
		var fl := FloorDetails.new()
		fl.name = "FloorDetails"
		fl.spawns = layout.decor_spawns
		fl.atlas = Prop.ATLAS
		fl.meta = Prop.AtlasMeta.PIECES
		fl.z_index = 1
		add_child(fl)
	for s: FloorLayout.Spawn in layout.prop_spawns:
		var pos := FloorLayout.cell_to_world(s.cell) + Vector2(0.0, TS * 0.25) + s.offset
		if BIG_OFFSET.has(s.kind):
			pos = FloorLayout.cell_to_world(s.cell) + BIG_OFFSET[s.kind] + Vector2(0.0, TS * 0.5)
		var p := Prop.create(s.kind, pos, shared, s.flip)
		add_child(p)
		_props.append(p)
		var g: Array = p.call("get_glow")
		if g.is_empty():
			continue
		var big := BIG_OFFSET.has(s.kind)
		if bool(g[2]):
			_alarms.append([pos + g[0], 90.0])
		else:
			add_glow(pos + g[0], 210.0 if big else 70.0, g[1], 1.2 if big else 0.8)


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


# --- Toits logiques (pré-rendu) ---------------------------------------------------------------

func _build_roofs() -> void:
	for b: FloorLayout.Building in layout.buildings:
		var roof := BuildingRoof.new()
		roof.name = "Roof_%d_%s" % [b.id, String(b.archetype)]
		roof.archetype = b.archetype
		roof.building_name = b.name
		roof.footprint = Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
		roof.roof_rect = Rect2()
		add_child(roof)
		_roofs.append(roof)


# --- Extraction ------------------------------------------------------------------------------

func _build_extraction() -> void:
	if layout.extraction_cells.is_empty():
		return
	var glow := ExtractionGlow.new()
	glow.name = "ExtractionGlow"
	glow.cells = layout.extraction_cells.duplicate()
	var ec: Variant = palette.get("extraction", Color(0.3, 1.0, 0.75, 0.45))
	glow.color = ec if ec is Color else Color(0.3, 1.0, 0.75)
	glow.z_index = 1
	glow.pulse_speed = Balance.get_float("world_builder", "extraction_pulse_speed", 2.2)
	add_child(glow)
	var center := Vector2.ZERO
	for c: Vector2i in layout.extraction_cells:
		center += FloorLayout.cell_to_world(c)
	center /= float(layout.extraction_cells.size())
	var beacon := ExtractionBeacon.new()
	beacon.name = "ExtractionBeacon"
	beacon.position = center + Vector2(0.0, TS * 0.2)
	beacon.z_index = 10
	beacon.add_to_group(&"extraction_markers")
	add_child(beacon)
	add_glow(center, 150.0, Color(0.3, 1.0, 0.7), 1.0)


## Sas de capsule d'évacuation au sol (cases d'extraction) : lueur verte pulsée par modulate.
class ExtractionGlow extends Node2D:
	var cells: Array[Vector2i] = []
	var color: Color = Color(0.3, 1.0, 0.75)
	var pulse_speed: float = 2.2
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		modulate.a = 0.65 + 0.35 * sin(_t * pulse_speed)

	func _draw() -> void:
		var c := Color(color.r, color.g, color.b, 1.0)
		for cell: Vector2i in cells:
			var r := Rect2(Vector2(cell) * TS, Vector2(TS, TS))
			draw_rect(r.grow(-3.0), Color(c, 0.2))
			draw_rect(r.grow(-6.0), Color(c.lightened(0.3), 0.8), false, 3.0)
			draw_circle(r.get_center(), TS * 0.28, Color(c, 0.18))


## Balise de capsule : écoutille ronde, voyant vert, flèche montante (dessin statique).
class ExtractionBeacon extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2(6, 2), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 26.0, Color(0.02, 0.04, 0.12, 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(-5, -64, 10, 64), Color(0.3, 0.33, 0.42))
		draw_rect(Rect2(-5, -64, 3, 64), Color(0.6, 0.68, 0.8))
		draw_rect(Rect2(-5, -64, 10, 64), OUTLINE, false, 1.6)
		draw_rect(Rect2(-16, -84, 32, 22), Color(0.12, 0.14, 0.2))
		draw_rect(Rect2(-13, -81, 26, 16), Color(0.3, 1.0, 0.6))
		draw_rect(Rect2(-16, -84, 32, 22), OUTLINE, false, 1.8)
		var pts := PackedVector2Array([Vector2(-7, -69), Vector2(0, -78), Vector2(7, -69)])
		draw_polyline(pts, Color(0.05, 0.25, 0.12), 3.0)


# --- Lumières et ambiance ----------------------------------------------------------------------

## Plafonniers froids : flaques de lumière régulières dans les salles et les coursives.
func _build_lights() -> void:
	for r: FloorLayout.Room in layout.rooms:
		var corr := is_corridor(r)
		var step := 4
		var role := role_of(r)
		var col := COOL
		if role == "reactor":
			col = Color(0.4, 0.9, 1.0)
		elif role == "hydroponics":
			col = Color(0.8, 0.6, 1.0)
		elif layout.floor_index < 0 and not corr:
			col = Color(1.0, 0.82, 0.6)
		if corr:
			var horiz := r.rect.size.x >= r.rect.size.y
			var n := maxi(r.rect.size.x if horiz else r.rect.size.y, 1)
			var k := 1
			while k < n:
				var c := Vector2i(r.rect.position.x + k, r.rect.get_center().y) if horiz else Vector2i(r.rect.get_center().x, r.rect.position.y + k)
				if layout.get_tile(c) == FloorLayout.Tile.FLOOR:
					add_glow(FloorLayout.cell_to_world(c), 120.0, col, 0.7)
				k += step
			continue
		var y := r.rect.position.y + 1
		while y < r.rect.end.y:
			var x := r.rect.position.x + 1
			while x < r.rect.end.x:
				var c2 := Vector2i(mini(x + 1, r.rect.end.x - 1), mini(y + 1, r.rect.end.y - 1))
				if layout.get_tile(c2) == FloorLayout.Tile.FLOOR:
					add_glow(FloorLayout.cell_to_world(c2), 150.0, col, 0.75)
				x += step
			y += step


func _build_ambience() -> void:
	var cm := CanvasModulate.new()
	cm.name = "AmbientTint"
	var key := "ambient_main" if layout.floor_index == 0 else ("ambient_command" if layout.floor_index > 0 else "ambient_machines")
	var defaults := {"ambient_main": Color(0.86, 0.92, 1.0), "ambient_command": Color(0.84, 0.9, 1.0), "ambient_machines": Color(0.78, 0.76, 0.86)}
	var v: Variant = _cfg(key, defaults[key])
	cm.color = v if v is Color else defaults[key]
	add_child(cm)
	var strength := float(_cfg("glow_strength", 1.0))
	var glows := GlowLayer.new()
	glows.name = "Glows"
	glows.glows = _glows
	glows.strength = strength
	glows.material = WorldProp.glow_material()
	glows.z_index = 45
	glows.z_as_relative = false
	add_child(glows)
	if not _alarms.is_empty():
		var al := AlarmLayer.new()
		al.name = "Alarms"
		al.alarms = _alarms
		al.speed = float(_cfg("alarm_pulse_speed", 2.6))
		al.material = WorldProp.glow_material()
		al.z_index = 46
		al.z_as_relative = false
		add_child(al)
	_build_motes()


## Particules froides en suspension (une seule couche GPU).
func _build_motes() -> void:
	var amount := int(_cfg("motes_amount", 60))
	if amount <= 0:
		return
	var area := Rect2(Vector2.ZERO, Vector2(layout.size) * TS)
	var p := GPUParticles2D.new()
	p.name = "Motes"
	p.amount = amount
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.texture = TEX_MOTE
	p.z_index = 46
	p.z_as_relative = false
	p.position = area.get_center()
	p.visibility_rect = Rect2(-area.size * 0.5 - Vector2(64, 64), area.size + Vector2(128, 128))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area.size.x * 0.5, area.size.y * 0.5, 0.0)
	pm.direction = Vector3(0.3, -1.0, 0.0)
	pm.spread = 40.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 10.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.2
	pm.scale_max = 0.6
	var grad := Gradient.new()
	var c := Color(0.7, 0.92, 1.0)
	grad.set_color(0, Color(c, 0.0))
	grad.set_color(1, Color(c, 0.0))
	grad.add_point(0.3, Color(c, 0.35))
	grad.add_point(0.7, Color(c, 0.25))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	add_child(p)


## Lueurs additives précalculées (sprite radial de l'atlas), dessinées une seule fois.
class GlowLayer extends Node2D:
	var glows: Array = []
	var strength: float = 1.0

	func _draw() -> void:
		if not Prop.has_piece("glow"):
			return
		var reg := Prop.piece_region("glow")
		for g: Array in glows:
			var p: Vector2 = g[0]
			var rad: float = g[1]
			var col: Color = g[2]
			var k: float = float(g[3]) * strength
			draw_texture_rect_region(Prop.ATLAS, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), reg, Color(col, 0.32 * k))
			draw_texture_rect_region(Prop.ATLAS, Rect2(p - Vector2(rad, rad) * 0.35, Vector2(rad, rad) * 0.7), reg, Color(col.lightened(0.4), 0.3 * k))


## Alarmes rouges : dessinées une fois, pulsation par modulate (aucun redessin).
class AlarmLayer extends Node2D:
	var alarms: Array = []
	var speed: float = 2.6
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		modulate.a = 0.35 + 0.65 * maxf(sin(_t * speed), 0.0)

	func _draw() -> void:
		if not Prop.has_piece("glow"):
			return
		var reg := Prop.piece_region("glow")
		for a: Array in alarms:
			var p: Vector2 = a[0]
			var rad: float = a[1]
			draw_texture_rect_region(Prop.ATLAS, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0), reg, Color(SpaceStationBuilder.RED, 0.45))
			draw_texture_rect_region(Prop.ATLAS, Rect2(p - Vector2(rad, rad) * 0.3, Vector2(rad, rad) * 0.6), reg, Color(1.0, 0.6, 0.5, 0.4))


# --- Butin : conteneurs et cachettes du biome ------------------------------------------------

## LootSpawner (partagé) ne connaît que les kinds Far West : un kind inconnu devient
## « crate » / « barrel ». On rétablit le kind du layout AVANT le _ready du nœud (sprite,
## table de butin du biome) puis on applique la définition du biome (nom, collision…).
func _prepare_loot_patch() -> void:
	for s: FloorLayout.Spawn in layout.container_spawns:
		_container_kind[s.cell] = s.kind
	for h: FloorLayout.Spawn in layout.hiding_spot_spawns:
		_hiding_kind[h.cell] = h.kind
	child_entered_tree.connect(_on_child_entered)


func _on_child_entered(n: Node) -> void:
	if n.name == "Loot" or n.is_in_group(&"loot_root"):
		if not n.child_entered_tree.is_connected(_on_loot_child):
			n.child_entered_tree.connect(_on_loot_child)


func _on_loot_child(n: Node) -> void:
	if n is LootContainer:
		var c := n as LootContainer
		var k: StringName = _container_kind.get(c.cell, c.kind)
		if CONTAINER_DEFS.has(k) and not LootContainer.DEFS.has(k):
			c.kind = k
			c.name = "Container_%s" % String(k)
			c.ready.connect(func() -> void: c.set("_def", CONTAINER_DEFS[k]), CONNECT_ONE_SHOT)
	elif n is HidingSpot:
		var h := n as HidingSpot
		var k2: StringName = _hiding_kind.get(h.cell, h.kind)
		if HIDING_DEFS.has(k2) and not HidingSpot.DEFS.has(k2):
			h.kind = k2
			h.name = "Hide_%s" % String(k2)
			h.ready.connect(func() -> void: h.set("_def", HIDING_DEFS[k2]), CONNECT_ONE_SHOT)
