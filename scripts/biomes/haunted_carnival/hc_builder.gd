class_name HauntedCarnivalBuilder
extends Node2D
## Constructeur du décor du rez-de-chaussée du Carnaval hanté.
##   HauntedCarnivalBuilder.build(layout, world) -> HauntedCarnivalBuilder (Node2D racine triée en Y)
## Même API que WorldBuilder (docs/CONVENTIONS.md) : get_doors(), get_stairs_areas() (meta
## `stairs`), signal stairs_entered(stairs), get_room_at_world(pos), set_stairs_cooldown(sec) ;
## en plus get_roofs(), get_props(), get_wall_body(), prerender_hide().
##
## Le rez-de-chaussée est PRÉ-RENDU (tools/prerender/hc_scene.py → assets/prerender/
## haunted_carnival/<seed>/) : PrerenderBackdrop remplace les visuels de ce constructeur et
## garde ses collisions, portes, toits logiques (chapiteau, stands, roulottes : s'effacent quand
## le joueur entre) et décors (collisions seulement, sprites masqués). Les visuels 2D ci-dessous
## (sol peint, murs plats, disques des manèges, décors en formes simples) servent de repli quand
## aucun paquet n'est disponible (seed inconnue, tests).
##
## Performance : aucun _draw par image (sauf extraction), aucune lumière dynamique, quelques
## nœuds statiques dessinés une fois.

signal stairs_entered(stairs: FloorLayout.Stairs)

const TS := float(FloorLayout.TILE_SIZE)
const LAYER_WORLD := 1
const MASK_PLAYER := 2
const DoorScript := preload("res://scripts/biomes/haunted_carnival/hc_door.gd")
const Pop := preload("res://scripts/biomes/haunted_carnival/hc_populator.gd")
const Plan := preload("res://scripts/biomes/haunted_carnival/hc_plan.gd")
const FONT: Font = preload("res://assets/fonts/nunito/Nunito-Variable.ttf")
const OUTLINE := Color(0.08, 0.05, 0.1)
const NIGHT := Color(0.1, 0.06, 0.22)

## Libellés et formes des conteneurs / cachettes du biome (format LootContainer.DEFS, scale
## 0.55 : sprites à 1/0.55 px par unité monde, pieds en bas au centre).
const CONTAINER_DEFS := {
	&"hc_fair_crate": {"name": "Caisse de forain", "block": Vector2(44, 18), "reach": 4.0, "shadow": 0.0},
	&"hc_stand_counter": {"name": "Comptoir du stand", "block": Vector2(56, 18), "reach": 6.0, "shadow": 0.0},
	&"hc_caravan_chest": {"name": "Coffre de roulotte", "block": Vector2(46, 18), "reach": 4.0, "shadow": 0.0},
	&"hc_trash_can": {"name": "Poubelle du parc", "block": Vector2(24, 14), "reach": 4.0, "shadow": 0.0},
	&"hc_corpse": {"name": "Forain tombé", "block": Vector2.ZERO, "reach": 12.0, "shadow": 0.0},
	&"hc_plush_corpse": {"name": "Peluche éventrée", "block": Vector2.ZERO, "reach": 10.0, "shadow": 0.0},
}
const HIDE_DEFS := {
	&"hc_photo_booth": {"name": "Dans le photomaton", "block": Vector2(44, 18), "reach": 6.0, "shadow": 0.0},
	&"hc_dumpster": {"name": "Dans la benne", "block": Vector2(70, 22), "reach": 8.0, "shadow": 0.0},
	&"hc_plush_heap": {"name": "Sous les peluches", "block": Vector2(56, 20), "reach": 8.0, "shadow": 0.0},
	&"hc_stand_back": {"name": "Derrière le comptoir", "block": Vector2(72, 18), "reach": 8.0, "shadow": 0.0},
	&"hc_caravan_bed": {"name": "Sous la couchette", "block": Vector2(60, 18), "reach": 6.0, "shadow": 0.0},
}

## Décors : kind → block (collision, unités monde ; ZERO = traversable), couleur du repli 2D,
## hauteur du repli (px), glow (rayon, couleur).
const PROP_DEFS := {
	&"hc_lamp_post": {"block": Vector2(14, 10), "col": Color(0.3, 0.28, 0.36), "h": 70.0, "glow": 90.0, "tint": Color(1.0, 0.75, 0.42)},
	&"hc_debris": {"block": Vector2.ZERO, "col": Color(0.34, 0.26, 0.32), "h": 8.0},
	&"hc_balloon_bunch": {"block": Vector2(12, 10), "col": Color(0.9, 0.3, 0.5), "h": 60.0, "glow": 30.0, "tint": Color(1.0, 0.4, 0.7)},
	&"hc_barrier": {"block": Vector2(56, 12), "col": Color(0.66, 0.6, 0.62), "h": 20.0},
	&"hc_trash_bin": {"block": Vector2(22, 14), "col": Color(0.3, 0.42, 0.34), "h": 26.0},
	&"hc_food_cart": {"block": Vector2(100, 34), "col": Color(0.8, 0.2, 0.25), "h": 40.0, "glow": 50.0, "tint": Color(1.0, 0.7, 0.4)},
	&"hc_dead_tree": {"block": Vector2(20, 14), "col": Color(0.22, 0.16, 0.2), "h": 90.0},
	&"hc_sign_post": {"block": Vector2(12, 10), "col": Color(0.55, 0.36, 0.3), "h": 56.0},
	&"hc_bench": {"block": Vector2(56, 16), "col": Color(0.5, 0.3, 0.28), "h": 18.0},
	&"hc_bumper_car": {"block": Vector2(110, 40), "col": Color(0.2, 0.5, 0.8), "h": 26.0},
	&"hc_shooting_counter": {"block": Vector2(110, 30), "col": Color(0.6, 0.4, 0.3), "h": 30.0},
	&"hc_prize_shelf": {"block": Vector2(56, 18), "col": Color(0.7, 0.5, 0.35), "h": 48.0},
	&"hc_candy_machine": {"block": Vector2(40, 24), "col": Color(0.95, 0.5, 0.7), "h": 50.0, "glow": 36.0, "tint": Color(1.0, 0.5, 0.8)},
	&"hc_duck_pool": {"block": Vector2(58, 40), "col": Color(0.3, 0.55, 0.75), "h": 14.0},
	&"hc_plush_pile": {"block": Vector2(44, 22), "col": Color(0.85, 0.6, 0.7), "h": 28.0},
	&"hc_crystal_table": {"block": Vector2(44, 30), "col": Color(0.45, 0.3, 0.6), "h": 30.0, "glow": 40.0, "tint": Color(0.7, 0.5, 1.0)},
	&"hc_hammer_tower": {"block": Vector2(30, 20), "col": Color(0.8, 0.2, 0.2), "h": 90.0},
	&"hc_mirror": {"block": Vector2(40, 10), "col": Color(0.7, 0.8, 0.95), "h": 60.0},
	&"hc_cage": {"block": Vector2(110, 40), "col": Color(0.3, 0.3, 0.36), "h": 56.0},
	&"hc_puppet_stage": {"block": Vector2(90, 30), "col": Color(0.7, 0.15, 0.2), "h": 60.0},
	&"hc_bunk": {"block": Vector2(56, 30), "col": Color(0.6, 0.4, 0.35), "h": 24.0},
	&"hc_trunk": {"block": Vector2(40, 22), "col": Color(0.45, 0.28, 0.2), "h": 24.0},
	&"hc_crate_stack": {"block": Vector2(50, 30), "col": Color(0.6, 0.45, 0.3), "h": 44.0},
	&"hc_bleachers": {"block": Vector2(170, 34), "col": Color(0.5, 0.3, 0.3), "h": 36.0},
	&"hc_ring_barrier": {"block": Vector2(110, 14), "col": Color(0.85, 0.2, 0.25), "h": 16.0},
}
const CENTERED := [&"hc_bumper_car", &"hc_food_cart", &"hc_cage", &"hc_bleachers", &"hc_ring_barrier", &"hc_shooting_counter"]

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


static func build(p_layout: FloorLayout, world: Resource = null) -> HauntedCarnivalBuilder:
	var root := HauntedCarnivalBuilder.new()
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
	for nm: String in ["Rides", "Glows", "Gate"]:
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
		push_warning("HauntedCarnivalBuilder: layout null.")
		return
	palette = {}
	var wp: Variant = world.get("palette") if world != null else null
	if wp is Dictionary:
		palette = (wp as Dictionary).duplicate()
	wall_height = _cfg_f("wall_height", Balance.get_float("world_builder", "wall_height", 52.0))
	_stairs_cooldown = Balance.get_float("world_builder", "stairs_cooldown", 0.5)
	_build_grids()
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
	return Balance.get_float("haunted_carnival", key, def)


static func _cfg_c(key: String, def: Color) -> Color:
	var v: Variant = Balance.get_value("haunted_carnival", key, def)
	return v if v is Color else def


func _build_grids() -> void:
	var n := layout.size.x * layout.size.y
	_room_grid = Plan.room_grid(layout)
	_building_grid.resize(n)
	_building_grid.fill(-1)
	for b: FloorLayout.Building in layout.buildings:
		var ellipse := b.archetype == &"big_top"
		for y2: int in range(maxi(b.rect.position.y, 0), mini(b.rect.end.y, layout.size.y)):
			for x2: int in range(maxi(b.rect.position.x, 0), mini(b.rect.end.x, layout.size.x)):
				if ellipse and Plan.tent_d(x2, y2) > 1.0:
					continue
				_building_grid[y2 * layout.size.x + x2] = b.id


func room_id_at(c: Vector2i) -> int:
	if not layout.in_bounds(c):
		return -1
	return _room_grid[c.y * layout.size.x + c.x]


func building_id_at(c: Vector2i) -> int:
	if not layout.in_bounds(c):
		return -1
	return _building_grid[c.y * layout.size.x + c.x]


func role_at(c: Vector2i) -> String:
	var id := room_id_at(c)
	var r := layout.get_room(id) if id >= 0 else null
	return r.tags[0] if r != null and r.tags.size() > 0 else ""


static func hash01(x: int, y: int, s: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


func add_glow(pos: Vector2, radius: float, strength: float = 1.0, color: Color = Color(1.0, 0.7, 0.4)) -> void:
	_glows.append([pos, radius, strength, color])


# --- Sol (repli 2D) ---------------------------------------------------------------

func _build_ground() -> void:
	var ground := Ground.new()
	ground.name = "Ground"
	ground.builder = self
	ground.z_index = 0
	add_child(ground)
	var rides := Rides.new()
	rides.name = "Rides"
	rides.builder = self
	rides.z_index = 1
	add_child(rides)


class Ground extends Node2D:
	var builder: HauntedCarnivalBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var pal := builder.palette
		var void_c: Color = pal.get("void", Color(0.08, 0.05, 0.14))
		var full := Rect2(Vector2(-14, -14) * TS, (Vector2(L.size) + Vector2(28, 28)) * TS)
		draw_rect(full, void_c)
		var street: Color = pal.get("street", Color(0.4, 0.3, 0.44))
		var floor_c: Color = pal.get("floor", Color(0.42, 0.32, 0.36))
		var pavers: Color = pal.get("pavers", Color(0.46, 0.4, 0.52))
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				var t := L.get_tile(c)
				if not FloorLayout.is_walkable_tile(t):
					continue
				var r := Rect2(Vector2(c) * TS, Vector2(TS, TS))
				var h := HauntedCarnivalBuilder.hash01(x, y, 1)
				var col: Color
				if t == FloorLayout.Tile.STREET:
					var role := builder.role_at(c)
					col = pavers if role in ["plaza", "entrance", "avenue"] else street
					col = col.darkened(0.08 * h)
				else:
					col = floor_c.lightened(0.1 * h)
				draw_rect(r, col)
				if h < 0.08:
					draw_circle(r.get_center() + Vector2(h * 300.0 - 12.0, 6.0), 4.0 + h * 20.0, Color(0.2, 0.14, 0.24, 0.5))
		# Ombres au pied des murs.
		for y2: int in L.size.y:
			for x2: int in L.size.x:
				var c2 := Vector2i(x2, y2)
				if not FloorLayout.is_walkable_tile(L.get_tile(c2)):
					continue
				var o := Vector2(c2) * TS
				if L.get_tile(c2 + Vector2i.UP) == FloorLayout.Tile.WALL:
					draw_rect(Rect2(o, Vector2(TS, 20.0)), Color(NIGHT, 0.4))
				if L.get_tile(c2 + Vector2i.LEFT) == FloorLayout.Tile.WALL:
					draw_rect(Rect2(o, Vector2(14.0, TS)), Color(NIGHT, 0.3))
		# Teinte nocturne violette globale.
		var pts := PackedVector2Array([full.position, Vector2(full.end.x, full.position.y), full.end, Vector2(full.position.x, full.end.y)])
		draw_polygon(pts, PackedColorArray([Color(0.4, 0.1, 0.6, 0.14), Color(0.8, 0.2, 0.6, 0.1), Color(0.3, 0.1, 0.5, 0.18), Color(0.6, 0.2, 0.7, 0.1)]))


## Repli 2D des manèges et de la grande roue (disques de cases murées) : plateau rond + rayons.
class Rides extends Node2D:
	var builder: HauntedCarnivalBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var c: Dictionary = L.get_meta(&"render_contract", {})
		for rd: Dictionary in c.get("rides", []):
			var ctr: Vector2 = rd["c"]
			var r: float = float(rd["r"])
			var p := ctr * TS
			var rad := r * TS
			draw_circle(p + Vector2(6, 8), rad, Color(NIGHT, 0.35))
			draw_circle(p, rad, Color(0.5, 0.36, 0.5))
			draw_arc(p, rad, 0.0, TAU, 48, OUTLINE, 3.0)
			var kind := String(rd["kind"])
			var n := 12 if kind == "ferris_wheel" else 8
			for k in n:
				var a := float(k) * TAU / float(n)
				var col := Color(0.85, 0.2, 0.3) if k % 2 == 0 else Color(0.95, 0.9, 0.85)
				draw_line(p, p + Vector2(cos(a), sin(a)) * rad * 0.95, col, 3.0)
				if kind != "ferris_wheel":
					draw_circle(p + Vector2(cos(a + 0.2), sin(a + 0.2)) * rad * 0.7, rad * 0.14, col)
			draw_circle(p, rad * 0.18, Color(1.0, 0.78, 0.3))
			draw_arc(p, rad * 0.18, 0.0, TAU, 16, OUTLINE, 2.0)
			if kind == "ferris_wheel":
				draw_arc(p, rad * 0.6, 0.0, TAU, 40, Color(1.0, 0.6, 0.8), 2.0)
			builder.add_glow(p, rad * 1.4, 0.8, Color(1.0, 0.45, 0.85) if kind == "ferris_wheel" else Color(1.0, 0.7, 0.4))
		# Pylônes des montagnes russes (zone nord-est).
		var pts: Array = c.get("coaster_in", [])
		for i in range(pts.size() - 1):
			var a: Array = pts[i]
			var b: Array = pts[i + 1]
			draw_line(Vector2(a[0], a[1]) * TS, Vector2(b[0], b[1]) * TS, Color(0.8, 0.15, 0.2), 8.0)
			draw_line(Vector2(a[0], a[1]) * TS, Vector2(b[0], b[1]) * TS, OUTLINE, 2.0)


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


## Couleur de mur selon ce qu'il borde (repli 2D) : toile rayée des stands / tentes, bois des
## roulottes, fer du portail, planches des palissades.
func wall_style(c: Vector2i) -> Dictionary:
	var bid := building_id_at(c)
	var arch: StringName = layout.buildings[bid].archetype if bid >= 0 else &""
	var ride := false
	var contract: Dictionary = layout.get_meta(&"render_contract", {})
	for rd: Dictionary in contract.get("rides", []):
		if Vector2(c.x + 0.5, c.y + 0.5).distance_to(rd["c"]) <= float(rd["r"]) + 0.01:
			ride = true
	if ride:
		return {"cap": Color(0.5, 0.36, 0.5), "face": Color(0.4, 0.28, 0.42), "stripe": false}
	match arch:
		&"big_top", &"mirrors", &"freaks", &"theatre":
			return {"cap": Color(0.72, 0.14, 0.18), "face": Color(0.82, 0.74, 0.7), "stripe": true}
		&"caravan", &"director_caravan":
			return {"cap": Color(0.46, 0.28, 0.3), "face": Color(0.62, 0.38, 0.34), "stripe": false}
		&"ticket_booth":
			return {"cap": Color(0.7, 0.55, 0.2), "face": Color(0.82, 0.64, 0.3), "stripe": false}
		&"":
			if c.y >= Plan.GATE.position.y and c.y < Plan.GATE.end.y and c.x >= Plan.GATE.position.x and c.x < Plan.GATE.end.x:
				return {"cap": Color(0.32, 0.3, 0.4), "face": Color(0.24, 0.22, 0.32), "stripe": false}
			return {"cap": Color(0.36, 0.26, 0.32), "face": Color(0.3, 0.2, 0.26), "stripe": false}
	return {"cap": Color(0.72, 0.14, 0.18), "face": Color(0.86, 0.8, 0.76), "stripe": true}


class WallLayer extends Node2D:
	var builder: HauntedCarnivalBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var wh := builder.wall_height
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				if L.get_tile(c) != FloorLayout.Tile.WALL:
					continue
				var face := FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN))
				var o := Vector2(c) * TS
				var cap_h := TS - wh if face else TS
				var st := builder.wall_style(c)
				var cap: Color = st["cap"]
				draw_rect(Rect2(o, Vector2(TS, cap_h)), cap.lightened(0.12 * HauntedCarnivalBuilder.hash01(x, y, 3)))
				if L.get_tile(c + Vector2i.UP) != FloorLayout.Tile.WALL:
					draw_rect(Rect2(o, Vector2(TS, 2)), OUTLINE)
				if L.get_tile(c + Vector2i.LEFT) != FloorLayout.Tile.WALL:
					draw_rect(Rect2(o, Vector2(2, TS)), OUTLINE)
				if L.get_tile(c + Vector2i.RIGHT) != FloorLayout.Tile.WALL:
					draw_rect(Rect2(o + Vector2(TS - 2, 0), Vector2(2, TS)), OUTLINE)
				if face:
					var f := Rect2(o + Vector2(0, cap_h), Vector2(TS, wh))
					var fc: Color = st["face"]
					draw_rect(f, fc)
					if bool(st["stripe"]):
						var sx := f.position.x
						var k := 0
						while sx < f.end.x:
							if k % 2 == 0:
								draw_rect(Rect2(sx, f.position.y, minf(10.0, f.end.x - sx), f.size.y), Color(0.72, 0.14, 0.18))
							sx += 10.0
							k += 1
					draw_rect(Rect2(f.position, Vector2(TS, 3.0)), Color(NIGHT, 0.5))
					draw_rect(Rect2(f.position.x, f.end.y - 1.5, f.size.x, 2.0), OUTLINE)
					draw_rect(Rect2(o + Vector2(0, cap_h - 1), Vector2(TS, 2)), OUTLINE)


# --- Portes ----------------------------------------------------------------------

func _build_doors() -> void:
	for d: FloorLayout.Door in layout.doors:
		var door: DoorNode = DoorScript.new()
		door.name = "Door_%d" % d.id
		door.setup(d, _door_kind(d), wall_height)
		var bid := building_id_at(d.cell)
		var arch: StringName = layout.buildings[bid].archetype if bid >= 0 else &""
		door.set("accent", Color(0.74, 0.14, 0.18) if arch != &"mirrors" else Color(0.5, 0.3, 0.8))
		door.z_index = 10
		add_child(door)
		_doors.append(door)


func _door_kind(d: FloorLayout.Door) -> StringName:
	if d.state == FloorLayout.DoorState.LOCKED:
		return DoorScript.KIND_SEALED
	var arch: StringName = &""
	for r: FloorLayout.Room in [layout.get_room(d.room_a), layout.get_room(d.room_b)]:
		if r != null and r.building_id >= 0:
			arch = layout.buildings[r.building_id].archetype
		elif r != null and r.tags.size() > 1 and arch == &"":
			arch = StringName(r.tags[1])
	match arch:
		&"caravan", &"director_caravan":
			return DoorScript.KIND_CARAVAN
		&"service_yard", &"ticket_booth":
			return DoorScript.KIND_GATE
	return DoorScript.KIND_CURTAIN


# --- Escaliers (aucun au rez-de-chaussée ; API conservée) -------------------------

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
	var shared := StaticBody2D.new()
	shared.name = "PropBodies"
	shared.collision_layer = LAYER_WORLD
	shared.collision_mask = 0
	add_child(shared)
	for s: FloorLayout.Spawn in layout.prop_spawns:
		var pos: Vector2
		var big := Pop.BIG.has(s.kind) and s.size == Vector2i.ONE
		if big:
			var fp: Vector2i = Pop.BIG[s.kind]
			var x0 := s.cell.x - (fp.x - 1) / 2
			pos = Vector2(float(x0) + float(fp.x) * 0.5, float(s.cell.y) + 1.0 - float(fp.y) * 0.5) * TS
		else:
			pos = FloorLayout.cell_to_world(s.cell) + Vector2(0.0, TS * 0.25) + s.offset
		var p := Prop.new()
		p.name = "Prop_%s" % String(s.kind)
		p.kind = s.kind
		p.position = pos
		p.def = PROP_DEFS.get(s.kind, {"block": Vector2(24, 12), "col": Color(0.5, 0.4, 0.5), "h": 24.0})
		p.centered = CENTERED.has(s.kind)
		p.z_index = 10
		var block: Vector2 = p.def.get("block", Vector2.ZERO)
		if block != Vector2.ZERO:
			var oid := shared.create_shape_owner(p)
			var r0 := RectangleShape2D.new()
			r0.size = block
			shared.shape_owner_add_shape(oid, r0)
			var ctr := Vector2.ZERO if p.centered else Vector2(0.0, -block.y * 0.5)
			shared.shape_owner_set_transform(oid, Transform2D(0.0, pos + ctr))
		add_child(p)
		_props.append(p)
		if p.def.has("glow"):
			add_glow(pos + Vector2(0, -float(p.def.get("h", 20.0)) * 0.8), float(p.def["glow"]), 1.0, p.def.get("tint", Color(1.0, 0.7, 0.4)))


## Décor de repli (formes simples) : le rendu pré-calculé dessine le vrai décor.
class Prop extends Node2D:
	var kind: StringName = &""
	var def: Dictionary = {}
	var centered: bool = false

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

	func _draw() -> void:
		var block: Vector2 = def.get("block", Vector2(24, 12))
		var w := maxf(block.x, 20.0)
		var h := float(def.get("h", 24.0))
		var col: Color = def.get("col", Color(0.5, 0.4, 0.5))
		var base := Vector2.ZERO if not centered else Vector2(0.0, block.y * 0.5)
		draw_ellipse_shadow(base, w * 0.5, maxf(block.y, 10.0) * 0.5)
		if h <= 10.0:
			draw_circle(base + Vector2(0, -3), w * 0.3, col)
			return
		draw_rect(Rect2(base + Vector2(-w * 0.5, -h), Vector2(w, h)), col)
		draw_rect(Rect2(base + Vector2(-w * 0.5, -h), Vector2(w, h * 0.25)), col.lightened(0.25))
		draw_rect(Rect2(base + Vector2(-w * 0.5, -h), Vector2(w, h)), OUTLINE, false, 2.0)
		if def.has("glow"):
			draw_circle(base + Vector2(0, -h * 0.8), 6.0, def.get("tint", Color(1, 0.8, 0.5)))

	func draw_ellipse_shadow(c: Vector2, rx: float, ry: float) -> void:
		var pts := PackedVector2Array()
		for k in 16:
			var a := float(k) * TAU / 16.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, Color(NIGHT, 0.4))


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


# --- Toits (chapiteaux, auvents rayés, roulottes) -------------------------------------

func _build_roofs() -> void:
	var holder := Node2D.new()
	holder.name = "Roofs"
	holder.z_index = 50
	holder.z_as_relative = false
	add_child(holder)
	for b: FloorLayout.Building in layout.buildings:
		var roof := CarnivalRoof.new()
		roof.name = "Roof_%d_%s" % [b.id, String(b.archetype)]
		roof.archetype = b.archetype
		roof.label = b.name
		var r := Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
		roof.footprint = r
		roof.ellipse = b.archetype == &"big_top"
		roof.roof_rect = Rect2(r.position.x - 4.0, r.position.y - 4.0, r.size.x + 8.0, r.end.y - wall_height - r.position.y + 4.0)
		roof.hidden_alpha = Balance.get_float("world_builder", "roof_hidden_alpha", 0.1)
		roof.fade_duration = Balance.get_float("world_builder", "roof_fade_duration", 0.25)
		roof.color_index = int(hash01(b.id, 7, 9) * 4.0)
		holder.add_child(roof)
		_roofs.append(roof)


class CarnivalRoof extends Node2D:
	var archetype: StringName = &""
	var label: String = ""
	var footprint: Rect2 = Rect2()
	var roof_rect: Rect2 = Rect2()
	var ellipse: bool = false
	var hidden_alpha: float = 0.1
	var fade_duration: float = 0.25
	var color_index: int = 0
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
		if not footprint.has_point(pos):
			return false
		if ellipse:
			var c := footprint.get_center()
			var dx := (pos.x - c.x) / (footprint.size.x * 0.5)
			var dy := (pos.y - c.y) / (footprint.size.y * 0.5)
			return dx * dx + dy * dy <= 1.0
		return true

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
		var red := Color(0.72, 0.14, 0.18)
		var white := Color(0.9, 0.84, 0.8)
		var alt: Color = [Color(0.72, 0.14, 0.18), Color(0.8, 0.5, 0.15), Color(0.5, 0.2, 0.6), Color(0.2, 0.45, 0.6)][color_index % 4]
		draw_rect(Rect2(r.position + Vector2(10, 10), r.size), Color(NIGHT, 0.25))
		match archetype:
			&"big_top", &"mirrors", &"freaks", &"theatre":
				# Chapiteau : rayons rouge / blanc depuis le mât central.
				var c := r.get_center()
				var n := 20
				var pts := PackedVector2Array()
				for k in n:
					var a0 := float(k) * TAU / float(n)
					var a1 := float(k + 1) * TAU / float(n)
					pts = PackedVector2Array([c, c + Vector2(cos(a0) * r.size.x * 0.5, sin(a0) * r.size.y * 0.5),
						c + Vector2(cos(a1) * r.size.x * 0.5, sin(a1) * r.size.y * 0.5)])
					draw_colored_polygon(pts, red if k % 2 == 0 else white)
				var ring := PackedVector2Array()
				for k2 in 48:
					var a := float(k2) * TAU / 48.0
					ring.append(c + Vector2(cos(a) * r.size.x * 0.5, sin(a) * r.size.y * 0.5))
				draw_polyline(ring, OUTLINE, 3.0, true)
				draw_circle(c, 9.0, Color(1.0, 0.78, 0.3))
				draw_circle(c, 9.0, OUTLINE, false, 2.0)
				for k3 in 12:
					var a2 := float(k3) * TAU / 12.0
					draw_circle(c + Vector2(cos(a2) * r.size.x * 0.46, sin(a2) * r.size.y * 0.46), 4.0, Color(1.0, 0.85, 0.5))
			&"caravan", &"director_caravan":
				draw_rect(r, Color(0.5, 0.32, 0.3))
				draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.3, r.size.x, r.size.y * 0.4), alt)
				var x := r.position.x + 6.0
				while x < r.end.x - 6.0:
					draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0.3, 0.18, 0.18), 1.5)
					x += 12.0
				draw_rect(r, OUTLINE, false, 3.0)
				draw_circle(Vector2(r.get_center().x, r.position.y + 14.0), 7.0, Color(0.3, 0.3, 0.36))
			&"ticket_booth":
				draw_rect(r, Color(0.9, 0.7, 0.25))
				var x2 := r.position.x
				var k4 := 0
				while x2 < r.end.x:
					draw_rect(Rect2(x2, r.position.y, minf(10.0, r.end.x - x2), r.size.y), red if k4 % 2 == 0 else white)
					x2 += 10.0
					k4 += 1
				draw_rect(r, OUTLINE, false, 3.0)
			_:
				# Stand : auvent rayé (rouge / blanc ou couleur variante / blanc), frise festonnée.
				var x3 := r.position.x
				var k5 := 0
				while x3 < r.end.x:
					draw_rect(Rect2(x3, r.position.y, minf(12.0, r.end.x - x3), r.size.y), alt if k5 % 2 == 0 else white)
					x3 += 12.0
					k5 += 1
				draw_rect(r, OUTLINE, false, 3.0)
				var fx := r.position.x
				while fx < r.end.x:
					draw_circle(Vector2(fx + 6.0, r.end.y), 6.0, alt)
					fx += 12.0
		_sign(r)

	func _sign(r: Rect2) -> void:
		var text := label.to_upper()
		if text.is_empty() or archetype in [&"service_yard"]:
			return
		var fs := 20
		var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while w > r.size.x - 20.0 and fs > 10:
			fs -= 2
			w = FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx := r.get_center().x
		var cy := r.end.y - 22.0
		var box := Rect2(cx - w * 0.5 - 10.0, cy - fs * 0.85, w + 20.0, fs * 1.35)
		draw_rect(box, Color(0.1, 0.06, 0.14))
		draw_rect(box, Color(1.0, 0.78, 0.3, 0.9), false, 2.0)
		var base := Vector2(cx - w * 0.5, cy + fs * 0.32)
		draw_string_outline(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(1.0, 0.5, 0.2, 0.4))
		draw_string(FONT, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.9, 0.6))


# --- Ambiance ----------------------------------------------------------------------

func _build_ambience() -> void:
	var cm := CanvasModulate.new()
	cm.name = "AmbientTint"
	cm.color = _cfg_c("ambient_ground", Color(0.86, 0.78, 1.0))
	add_child(cm)
	# Portail à la tête de clown (repli 2D : une grande face lumineuse au-dessus du passage).
	var gate := GateSign.new()
	gate.name = "Gate"
	gate.z_index = 50
	gate.z_as_relative = false
	add_child(gate)
	add_glow(Vector2(float(Plan.GATE_OPEN.position.x + Plan.GATE_OPEN.size.x * 0.5), float(Plan.GATE_OPEN.position.y)) * TS, TS * 3.0, 0.9, Color(1.0, 0.4, 0.8))
	for d: FloorLayout.Door in layout.doors:
		add_glow(FloorLayout.cell_to_world(d.cell) + Vector2(0, -TS * 0.3), 60.0, 0.5, Color(1.0, 0.7, 0.4))
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


class GateSign extends Node2D:
	func _draw() -> void:
		var g := Plan.GATE_OPEN
		var c := Vector2(float(g.position.x) + float(g.size.x) * 0.5, float(g.position.y)) * TS
		var r := TS * 2.2
		draw_circle(c + Vector2(0, -r * 0.2), r, Color(0.95, 0.9, 0.92))
		draw_circle(c + Vector2(0, -r * 0.2), r, OUTLINE, false, 3.0)
		draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.16, Color(0.1, 0.05, 0.1))
		draw_circle(c + Vector2(r * 0.35, -r * 0.4), r * 0.16, Color(0.1, 0.05, 0.1))
		draw_circle(c + Vector2(0, -r * 0.1), r * 0.14, Color(0.85, 0.15, 0.2))
		draw_arc(c + Vector2(0, 0.0), r * 0.55, 0.3, PI - 0.3, 16, Color(0.6, 0.08, 0.14), 10.0)
		for k in 7:
			var a := 0.45 + float(k) * (PI - 0.9) / 6.0
			var p := c + Vector2(cos(a), sin(a)) * r * 0.55
			draw_rect(Rect2(p + Vector2(-5, -10), Vector2(10, 12)), Color(0.98, 0.95, 0.9))
		draw_rect(Rect2(c + Vector2(-r * 1.1, -r * 1.45), Vector2(r * 2.2, r * 0.35)), Color(0.5, 0.15, 0.5))
		draw_rect(Rect2(c + Vector2(-r * 1.1, -r * 1.45), Vector2(r * 2.2, r * 0.35)), Color(1.0, 0.8, 0.4), false, 2.0)
		var text := "CARNAVAL"
		var fs := 26
		var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(FONT, c + Vector2(-w * 0.5, -r * 1.2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.85, 0.5))


class GlowLayer extends Node2D:
	var glows: Array = []
	var strength: float = 1.0

	func _draw() -> void:
		for g: Array in glows:
			var p: Vector2 = g[0]
			var rad: float = g[1]
			var k: float = float(g[2]) * strength
			var col: Color = g[3]
			draw_circle(p, rad, Color(col, 0.08 * k))
			draw_circle(p, rad * 0.5, Color(col, 0.12 * k))
			draw_circle(p, rad * 0.2, Color(col.lerp(Color.WHITE, 0.5), 0.2 * k))


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
