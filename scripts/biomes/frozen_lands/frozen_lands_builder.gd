class_name FrozenLandsBuilder
extends Node2D
## Constructeur du décor de la surface des Terres gelées (même API que WorldBuilder,
## cf. docs/CONVENTIONS.md « Cartes et biomes ») :
##   FrozenLandsBuilder.build(layout, world) -> FrozenLandsBuilder (Node2D, y_sort)
##   get_doors(), get_stairs_areas() (meta `stairs`), signal stairs_entered(stairs),
##   get_room_at_world(pos), set_stairs_cooldown(sec), get_wall_body(), get_props(), get_roofs(),
##   prerender_hide().
## La carte est PRÉ-RENDUE (tools/prerender/fl_scene.py → assets/prerender/frozen_lands/<seed>/) :
## ce constructeur fournit les collisions (murs, décors), les portes (fl_door.gd), les toits
## logiques des bunkers (BuildingRoof sans dessin : leur fondu pilote les intérieurs du fond et les
## tranches d'occultation), l'extraction, les lueurs (cristaux, alarmes) et une couche de flocons.
## Sans paquet pré-rendu (ou plan différent), un dessin 2D de secours (sol neige / béton, murs 3/4
## en béton, eau noire) reste lisible. Performance : aucun _draw par image, aucune lumière dynamique.

signal stairs_entered(stairs: FloorLayout.Stairs)

const TS := float(FloorLayout.TILE_SIZE)
const LAYER_WORLD := 1
const MASK_PLAYER := 2
const Prop := preload("res://scripts/biomes/frozen_lands/fl_prop.gd")
const DoorScript := preload("res://scripts/biomes/frozen_lands/fl_door.gd")
const OUTLINE := Color(0.04, 0.05, 0.09)
const SHADOW := Color(0.06, 0.1, 0.22)
const SNOW := Color(0.86, 0.91, 0.97)
const SNOW_DARK := Color(0.7, 0.78, 0.88)
const ICE_EDGE := Color(0.5, 0.75, 0.95)
const WATER := Color(0.03, 0.06, 0.12)
const CONCRETE := Color(0.5, 0.54, 0.6)
const CONCRETE_DARK := Color(0.34, 0.38, 0.44)
const FLOOR_IN := Color(0.42, 0.46, 0.52)
const FLOOR_LAB := Color(0.55, 0.62, 0.7)
const CYAN := Color(0.45, 0.9, 1.0)
const RED := Color(1.0, 0.2, 0.18)

## Conteneurs et cachettes propres au biome (absents de LootContainer.DEFS / HidingSpot.DEFS :
## voir _prepare_loot_patch). Mêmes clés que ces DEFS.
const CONTAINER_DEFS := {
	&"fl_supply_crate": {"name": "Caisse militaire", "scale": 0.55, "block": Vector2(54, 18), "reach": 2.0, "shadow": 32.0, "foot": 4.0},
	&"fl_ammo_box": {"name": "Caisse de munitions", "scale": 0.55, "block": Vector2(44, 16), "reach": 4.0, "shadow": 26.0, "foot": 4.0},
	&"fl_fuel_drum": {"name": "Baril de carburant", "scale": 0.55, "block": Vector2(30, 14), "reach": 4.0, "shadow": 20.0, "foot": 4.0},
	&"fl_footlocker": {"name": "Casier de soldat", "scale": 0.55, "block": Vector2(36, 14), "reach": 4.0, "shadow": 20.0, "foot": 4.0},
	&"fl_cryo_pod": {"name": "Cuve cryogénique", "scale": 0.55, "block": Vector2(84, 22), "reach": 14.0, "shadow": 46.0, "foot": 4.0},
	&"fl_sample_case": {"name": "Mallette d'échantillons", "scale": 0.55, "block": Vector2(34, 14), "reach": 4.0, "shadow": 20.0, "foot": 4.0},
	&"fl_sled": {"name": "Traîneau de ravitaillement", "scale": 0.55, "block": Vector2(70, 22), "reach": 6.0, "shadow": 40.0, "foot": 4.0},
	&"fl_frozen_corpse": {"name": "Soldat gelé", "scale": 0.55, "block": Vector2.ZERO, "reach": 12.0, "shadow": 0.0, "foot": 4.0},
}
const HIDING_DEFS := {
	&"fl_locker": {"name": "Armoire métallique", "scale": 0.55, "block": Vector2(50, 14), "shadow": 28.0, "foot": 4.0, "reach": 4.0},
	&"fl_cryo": {"name": "Cuve cryogénique vide", "scale": 0.55, "block": Vector2(40, 16), "shadow": 24.0, "foot": 4.0, "reach": 4.0},
	&"fl_snowdrift": {"name": "Congère", "scale": 0.55, "block": Vector2(56, 18), "shadow": 0.0, "foot": 4.0, "reach": 8.0},
}

var layout: FloorLayout = null
var palette: Dictionary = {}
var wall_height: float = 52.0

var _doors: Array[DoorNode] = []
var _stairs_areas: Array[Area2D] = []
var _props: Array[Node2D] = []
var _wall_body: StaticBody2D = null
var _stairs_cooldown: float = 0.5
var _room_grid: PackedInt32Array = PackedInt32Array()
var _glows: Array = []
var _alarms: Array = []
var _container_kind: Dictionary = {}
var _hiding_kind: Dictionary = {}
var _roofs: Array[BuildingRoof] = []


static func build(p_layout: FloorLayout, world: Resource = null) -> FrozenLandsBuilder:
	var root := FrozenLandsBuilder.new()
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


## (Pré-rendu) Masque les visuels remplacés par le fond pré-calculé ; PrerenderBackdrop.attach_to
## masque déjà Ground, Walls (visuels) et les décors (get_props), et neutralise AmbientTint.
func prerender_hide() -> void:
	for nm: String in ["Water", "Glows", "Alarms"]:
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
	var v: Variant = Balance.get_value("frozen_lands", key, null)
	return def if v == null else v


func _build(world: Resource) -> void:
	y_sort_enabled = true
	if layout == null:
		push_warning("FrozenLandsBuilder: layout null.")
		return
	if world != null and world.get("palette") is Dictionary:
		palette = (world.get("palette") as Dictionary).duplicate()
	wall_height = float(_cfg("wall_height", 52.0))
	_stairs_cooldown = float(_cfg("stairs_cooldown", 0.5))
	_build_grid()
	_build_water()
	_build_ground()
	_build_walls()
	_build_doors()
	_build_stairs()
	_build_props()
	_build_extraction()
	_build_roofs()
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


## Hash déterministe [0, 1) d'une case.
static func hash01(x: int, y: int, s: int = 0) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


func add_glow(pos: Vector2, radius: float, color: Color, strength: float = 1.0) -> void:
	_glows.append([pos, radius, color, strength])


# --- Eau, sol (secours 2D) -------------------------------------------------------------------

func _build_water() -> void:
	var wl := WaterLayer.new()
	wl.name = "Water"
	wl.builder = self
	wl.z_index = -1
	add_child(wl)


class WaterLayer extends Node2D:
	var builder: FrozenLandsBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var full := Rect2(Vector2(-14, -14) * TS, (Vector2(L.size) + Vector2(28, 28)) * TS)
		draw_rect(full, WATER)
		# Quelques plaques de banquise claires dans l'eau noire.
		for k: int in 40:
			var p := full.position + Vector2(FrozenLandsBuilder.hash01(k, 1, 7), FrozenLandsBuilder.hash01(k, 2, 7)) * full.size
			var c := FloorLayout.world_to_cell(p)
			if L.in_bounds(c) and L.get_tile(c) != FloorLayout.Tile.VOID:
				continue
			var s := 40.0 + FrozenLandsBuilder.hash01(k, 3, 7) * 90.0
			draw_rect(Rect2(p, Vector2(s, s * 0.6)), Color(SNOW_DARK, 0.5))


func _build_ground() -> void:
	var g := GroundLayer.new()
	g.name = "Ground"
	g.builder = self
	add_child(g)


class GroundLayer extends Node2D:
	var builder: FrozenLandsBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var w := L.size.x
		for y: int in L.size.y:
			var x := 0
			while x < w:
				var t := L.get_tile(Vector2i(x, y))
				if not FloorLayout.is_walkable_tile(t) and t != FloorLayout.Tile.WALL:
					x += 1
					continue
				var col := _col(Vector2i(x, y))
				var x1 := x + 1
				while x1 < w and _col(Vector2i(x1, y)) == col:
					x1 += 1
				draw_rect(Rect2(Vector2(x, y) * TS, Vector2(x1 - x, 1) * TS), col)
				x = x1
		# Ombres des murs (nord et ouest des cases praticables).
		for y2: int in L.size.y:
			for x2: int in L.size.x:
				var c2 := Vector2i(x2, y2)
				if not FloorLayout.is_walkable_tile(L.get_tile(c2)):
					continue
				var o := Vector2(c2) * TS
				if FloorLayout.is_opaque_tile(L.get_tile(c2 + Vector2i.UP)):
					draw_rect(Rect2(o, Vector2(TS, 22.0)), Color(SHADOW, 0.35))
				if FloorLayout.is_opaque_tile(L.get_tile(c2 + Vector2i.LEFT)):
					draw_rect(Rect2(o, Vector2(14.0, TS)), Color(SHADOW, 0.25))

	func _col(c: Vector2i) -> Color:
		var L := builder.layout
		var t := L.get_tile(c)
		if t == FloorLayout.Tile.WALL:
			# Les murs reçoivent le sol de la case du dessous.
			var s := L.get_tile(c + Vector2i.DOWN)
			t = s if FloorLayout.is_walkable_tile(s) else FloorLayout.Tile.STREET
		if t == FloorLayout.Tile.STREET:
			return SNOW if FrozenLandsBuilder.hash01(c.x, c.y, 3) < 0.85 else SNOW_DARK
		var r := builder.room_at_cell(c)
		var role := FrozenLandsBuilder.role_of(r)
		if role in ["lab", "cryo_vault", "infirmary", "crystal_lab", "observatory"]:
			return FLOOR_LAB
		if role in ["walkway", "yard", "ramp", "gate"]:
			return CONCRETE
		return FLOOR_IN


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


## Mur de bord de plateau (falaise de glace) : voisin d'une case vide.
func is_cliff(c: Vector2i) -> bool:
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var n := c + d
		if not layout.in_bounds(n) or layout.get_tile(n) == FloorLayout.Tile.VOID:
			return true
	return false


class WallLayer extends Node2D:
	var builder: FrozenLandsBuilder = null

	func _draw() -> void:
		var L := builder.layout
		var wh := builder.wall_height
		for y: int in L.size.y:
			for x: int in L.size.x:
				var c := Vector2i(x, y)
				if L.get_tile(c) != FloorLayout.Tile.WALL:
					continue
				var o := Vector2(c) * TS
				var cliff := builder.is_cliff(c)
				var face := FloorLayout.is_walkable_tile(L.get_tile(c + Vector2i.DOWN))
				var cap_h := TS - wh if face else TS
				var cap := SNOW if cliff else CONCRETE.lightened(0.25)
				draw_rect(Rect2(o, Vector2(TS, cap_h)), cap)
				if face:
					var f := Rect2(o + Vector2(0, cap_h), Vector2(TS, wh))
					draw_rect(f, ICE_EDGE if cliff else CONCRETE)
					draw_rect(Rect2(f.position, Vector2(TS, 4.0)), (ICE_EDGE if cliff else CONCRETE).lightened(0.3))
					if not cliff and builder.hash01(x, y, 11) < 0.08:
						draw_rect(Rect2(f.position + Vector2(20, 16), Vector2(24, 10)), RED.darkened(0.3))
					draw_rect(f, OUTLINE, false, 1.5)
				draw_rect(Rect2(o, Vector2(TS, cap_h)), OUTLINE, false, 1.0)
				if not cliff and builder.hash01(x, y, 12) < 0.06:
					# Alarme rouge sur le haut des murs de la base.
					builder._alarms.append([o + Vector2(TS * 0.5, cap_h * 0.5), 100.0])


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
			col = Color(1.0, 0.66, 0.2)
		if not d.vertical:
			add_glow(Vector2((float(d.cell.x) + 0.5) * TS, float(d.cell.y) * TS + 6.0), 34.0, col, 0.5)


# --- Escaliers (sous-sol futur) ---------------------------------------------------------------

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
		add_glow(FloorLayout.cell_to_world(st.cell), 110.0, CYAN, 1.0)
		_stairs_areas.append(area)


func _on_stairs_body_entered(body: Node2D, st: FloorLayout.Stairs) -> void:
	if _stairs_cooldown > 0.0:
		return
	if body.is_in_group(&"player"):
		stairs_entered.emit(st)


# --- Décors ----------------------------------------------------------------------------------

func _build_props() -> void:
	var shared := Prop.make_shared_body()
	add_child(shared)
	for s: FloorLayout.Spawn in layout.prop_spawns:
		var pos := FloorLayout.cell_to_world(s.cell) + Vector2(0.0, TS * 0.25) + s.offset
		var p := Prop.create(s.kind, pos, shared, s.flip, s.size)
		add_child(p)
		_props.append(p)
		var g: Array = p.call("get_glow")
		if g.is_empty():
			continue
		add_glow(pos + g[0], 260.0 if s.size != Vector2i.ONE else 80.0, g[1], 1.4 if s.size != Vector2i.ONE else 0.8)


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
	# Groupes de cases (héliport / ponton) : une balise par groupe.
	var groups: Array = []
	for c: Vector2i in layout.extraction_cells:
		var placed := false
		for g: Array in groups:
			if Vector2(c).distance_to(Vector2(g[0] as Vector2i)) < 6.0:
				g.append(c)
				placed = true
				break
		if not placed:
			groups.append([c])
	var glow := ExtractionGlow.new()
	glow.name = "ExtractionGlow"
	glow.cells = layout.extraction_cells.duplicate()
	var ec: Variant = palette.get("extraction", Color(0.3, 1.0, 0.75, 0.45))
	glow.color = ec if ec is Color else Color(0.3, 1.0, 0.75)
	glow.z_index = 1
	glow.pulse_speed = Balance.get_float("world_builder", "extraction_pulse_speed", 2.2)
	add_child(glow)
	for g2: Array in groups:
		var center := Vector2.ZERO
		for c2: Vector2i in g2:
			center += FloorLayout.cell_to_world(c2)
		center /= float(g2.size())
		var beacon := ExtractionBeacon.new()
		beacon.name = "ExtractionBeacon"
		beacon.position = center + Vector2(0.0, TS * 0.2)
		beacon.z_index = 10
		beacon.add_to_group(&"extraction_markers")
		add_child(beacon)
		add_glow(center, 150.0, Color(0.3, 1.0, 0.7), 1.0)


## Cases d'extraction au sol : lueur verte pulsée par modulate.
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


## Balise d'évacuation : mât, fumigène vert, panneau (dessin statique).
class ExtractionBeacon extends Node2D:
	func _draw() -> void:
		draw_set_transform(Vector2(6, 2), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 26.0, Color(0.02, 0.04, 0.12, 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(-4, -64, 8, 64), Color(0.5, 0.54, 0.6))
		draw_rect(Rect2(-4, -64, 3, 64), Color(0.74, 0.78, 0.84))
		draw_rect(Rect2(-4, -64, 8, 64), OUTLINE, false, 1.6)
		draw_rect(Rect2(-16, -84, 32, 22), Color(0.12, 0.14, 0.2))
		draw_rect(Rect2(-13, -81, 26, 16), Color(0.3, 1.0, 0.6))
		draw_rect(Rect2(-16, -84, 32, 22), OUTLINE, false, 1.8)
		var pts := PackedVector2Array([Vector2(-7, -69), Vector2(0, -78), Vector2(7, -69)])
		draw_polyline(pts, Color(0.05, 0.25, 0.12), 3.0)


# --- Lumières et ambiance ----------------------------------------------------------------------

func _build_ambience() -> void:
	var cm := CanvasModulate.new()
	cm.name = "AmbientTint"
	var v: Variant = _cfg("ambient_surface", Color(0.8, 0.88, 1.0))
	cm.color = v if v is Color else Color(0.8, 0.88, 1.0)
	add_child(cm)
	var strength := float(_cfg("glow_strength", 1.2))
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
		al.speed = float(_cfg("alarm_pulse_speed", 2.2))
		al.material = WorldProp.glow_material()
		al.z_index = 46
		al.z_as_relative = false
		add_child(al)
	_build_snowfall()


## Flocons portés par le vent (une seule couche GPU).
func _build_snowfall() -> void:
	var amount := int(_cfg("snow_amount", 90))
	if amount <= 0:
		return
	var area := Rect2(Vector2.ZERO, Vector2(layout.size) * TS)
	var p := GPUParticles2D.new()
	p.name = "Snowfall"
	p.amount = amount
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.z_index = 46
	p.z_as_relative = false
	p.position = area.get_center()
	p.visibility_rect = Rect2(-area.size * 0.5 - Vector2(64, 64), area.size + Vector2(128, 128))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(area.size.x * 0.5, area.size.y * 0.5, 0.0)
	pm.direction = Vector3(-0.6, 1.0, 0.0)
	pm.spread = 25.0
	pm.initial_velocity_min = 40.0
	pm.initial_velocity_max = 90.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.5
	pm.scale_max = 3.5
	var grad := Gradient.new()
	var c := Color(0.92, 0.97, 1.0)
	grad.set_color(0, Color(c, 0.0))
	grad.set_color(1, Color(c, 0.0))
	grad.add_point(0.2, Color(c, 0.7))
	grad.add_point(0.8, Color(c, 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	add_child(p)


## Lueurs additives précalculées (disque doux dessiné en code), dessinées une seule fois.
class GlowLayer extends Node2D:
	var glows: Array = []
	var strength: float = 1.0

	func _draw() -> void:
		for g: Array in glows:
			var p: Vector2 = g[0]
			var rad: float = g[1]
			var col: Color = g[2]
			var k: float = float(g[3]) * strength
			for i: int in 4:
				var f := 1.0 - float(i) / 4.0
				draw_circle(p, rad * f, Color(col, 0.07 * k))


## Alarmes rouges : dessinées une fois, pulsation par modulate (aucun redessin).
class AlarmLayer extends Node2D:
	var alarms: Array = []
	var speed: float = 2.2
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta
		modulate.a = 0.35 + 0.65 * maxf(sin(_t * speed), 0.0)

	func _draw() -> void:
		for a: Array in alarms:
			var p: Vector2 = a[0]
			var rad: float = a[1]
			for i: int in 4:
				var f := 1.0 - float(i) / 4.0
				draw_circle(p, rad * f, Color(RED, 0.1))


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
