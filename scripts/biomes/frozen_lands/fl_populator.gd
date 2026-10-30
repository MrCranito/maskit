extends RefCounted
## Peuplement d'un étage des Terres gelées : décors (prop_spawns), conteneurs
## (container_spawns), cachettes (hiding_spot_spawns) et ennemis (enemy_spawns).
## Mêmes règles que le peuplement de la station : objets bloquants jamais sur / à côté d'une
## porte, d'un escalier, du spawn ou d'une case d'extraction, jamais de façon à couper un passage
## (anneau 3×3 connexe) ; ennemis : tirages indépendants de la difficulté → nombre croissant.
## L'ameublement dépend du rôle de la salle (Room.tags[0]). Les décors (prop_spawns) sont des
## kinds du biome rendus dans la scène Blender (fl_scene.py) ; en jeu ils ne servent qu'aux
## collisions (fl_prop.gd : emprise, aucun sprite 2D quand le fond pré-rendu est actif).

const Cfg := preload("res://scripts/biomes/frozen_lands/fl_config.gd")
const T := FloorLayout.Tile

## Rôle → [kind, min, max, placement] ; placement : wall, center, any.
const PROPS := {
	&"lab": [[&"fl_lab_bench", 1, 2, &"wall"], [&"fl_cryo_tank", 1, 2, &"wall"], [&"fl_console", 1, 1, &"wall"]],
	&"cryo_vault": [[&"fl_cryo_tank", 2, 3, &"wall"], [&"fl_lab_bench", 0, 1, &"wall"]],
	&"barracks": [[&"fl_bunk", 2, 4, &"wall"], [&"fl_stove", 0, 1, &"wall"]],
	&"mess_hall": [[&"fl_table", 2, 3, &"center"], [&"fl_stove", 1, 1, &"wall"]],
	&"infirmary": [[&"fl_med_bed", 2, 3, &"wall"], [&"fl_cryo_tank", 0, 1, &"wall"]],
	&"command": [[&"fl_console", 2, 4, &"wall"], [&"fl_map_table", 1, 1, &"center"]],
	&"radio": [[&"fl_console", 2, 3, &"wall"], [&"fl_radio_rack", 1, 2, &"wall"]],
	&"bunker": [[&"fl_crate_stack", 2, 3, &"wall"], [&"fl_barrels", 1, 2, &"wall"], [&"fl_sandbags", 0, 1, &"any"]],
	&"armory": [[&"fl_weapon_rack", 2, 3, &"wall"], [&"fl_crate_stack", 0, 1, &"wall"]],
	&"storage": [[&"fl_crate_stack", 2, 4, &"wall"], [&"fl_barrels", 1, 2, &"wall"]],
	&"generator": [[&"fl_generator", 1, 2, &"wall"], [&"fl_barrels", 1, 2, &"wall"], [&"fl_pipes", 1, 2, &"wall"]],
	&"workshop": [[&"fl_workbench", 1, 2, &"wall"], [&"fl_crate_stack", 0, 1, &"wall"], [&"fl_barrels", 0, 1, &"wall"]],
	&"hangar": [[&"fl_crate_stack", 1, 2, &"wall"], [&"fl_barrels", 1, 2, &"wall"], [&"fl_tool_cart", 0, 1, &"any"]],
	&"garage": [[&"fl_crate_stack", 1, 2, &"wall"], [&"fl_barrels", 1, 1, &"wall"]],
	&"guard_tower": [[&"fl_sandbags", 1, 2, &"wall"], [&"fl_crate_stack", 0, 1, &"wall"]],
	&"observatory": [[&"fl_console", 1, 2, &"wall"], [&"fl_telescope", 1, 1, &"center"]],
	&"closet": [[&"fl_crate_stack", 0, 1, &"wall"]],
	&"yard": [[&"fl_crate_stack", 2, 4, &"any"], [&"fl_barrels", 1, 3, &"any"], [&"fl_sandbags", 1, 2, &"any"], [&"fl_antenna", 0, 1, &"center"]],
	&"walkway": [[&"fl_barrels", 0, 1, &"wall"]],
	&"crystal_lab": [],
	&"ramp": [[&"fl_sandbags", 1, 2, &"wall"], [&"fl_barrels", 0, 1, &"wall"]],
	&"gate": [[&"fl_sandbags", 0, 1, &"wall"]],
	&"heliport": [[&"fl_barrels", 1, 2, &"any"], [&"fl_crate_stack", 0, 1, &"any"]],
	&"dock": [[&"fl_crate_stack", 1, 2, &"any"], [&"fl_barrels", 0, 1, &"any"]],
	&"snow": [],
}

## Grands décors : rôle → [kind, largeur, hauteur (cases)] posés au centre de la salle.
const BIG_PROPS := {&"hangar": [&"fl_helicopter", 5, 3], &"garage": [&"fl_snowcat", 3, 2], &"crystal_lab": [&"fl_crystal_core", 3, 3]}

## Structures extérieures (plateau de neige) : [kind, largeur, hauteur (cases)] — avant-postes,
## citernes, conteneurs, radars, autoneiges garées. Nombre = surface / outdoor_structures_area.
const OUTDOOR := [[&"fl_outpost", 3, 3], [&"fl_fuel_tanks", 3, 2], [&"fl_containers", 3, 2], [&"fl_radar", 2, 2],
		[&"fl_snowcat", 3, 2]]

## Décors autorisés dans un couloir étroit.
const NARROW_OK := {}

## Rôle → cachettes {kind: poids}.
const HIDING := {
	&"barracks": {&"fl_locker": 2.0},
	&"lab": {&"fl_cryo": 2.0},
	&"infirmary": {&"fl_cryo": 2.0},
	&"storage": {&"fl_locker": 1.0, &"fl_snowdrift": 0.5},
	&"bunker": {&"fl_locker": 1.0},
	&"workshop": {&"fl_locker": 1.0},
	&"hangar": {&"fl_locker": 1.0, &"fl_snowdrift": 1.0},
	&"garage": {&"fl_locker": 1.0},
	&"command": {&"fl_locker": 1.0},
	&"radio": {&"fl_locker": 1.0},
	&"yard": {&"fl_snowdrift": 2.0},
	&"heliport": {&"fl_snowdrift": 2.0},
	&"dock": {&"fl_snowdrift": 1.0},
	&"guard_tower": {&"fl_locker": 1.0},
	&"observatory": {&"fl_locker": 1.0},
}

## Rôle → conteneurs {kind: poids}.
const CONTAINERS := {
	&"lab": {&"fl_cryo_pod": 2.0, &"fl_sample_case": 2.0, &"fl_footlocker": 0.5},
	&"cryo_vault": {&"fl_cryo_pod": 2.0, &"fl_sample_case": 1.0},
	&"barracks": {&"fl_footlocker": 3.0, &"fl_frozen_corpse": 0.5},
	&"mess_hall": {&"fl_footlocker": 1.0, &"fl_supply_crate": 1.0},
	&"infirmary": {&"fl_sample_case": 2.0, &"fl_cryo_pod": 1.0},
	&"command": {&"fl_footlocker": 1.0, &"fl_ammo_box": 1.0, &"fl_sample_case": 0.5},
	&"radio": {&"fl_footlocker": 1.0, &"fl_ammo_box": 0.5},
	&"bunker": {&"fl_ammo_box": 3.0, &"fl_supply_crate": 2.0, &"fl_fuel_drum": 1.0},
	&"armory": {&"fl_ammo_box": 3.0, &"fl_supply_crate": 1.0},
	&"storage": {&"fl_supply_crate": 4.0, &"fl_fuel_drum": 1.5},
	&"generator": {&"fl_fuel_drum": 3.0, &"fl_supply_crate": 1.0},
	&"workshop": {&"fl_supply_crate": 2.0, &"fl_ammo_box": 1.0, &"fl_fuel_drum": 1.0},
	&"hangar": {&"fl_supply_crate": 3.0, &"fl_fuel_drum": 2.0, &"fl_sled": 1.0},
	&"garage": {&"fl_sled": 2.0, &"fl_fuel_drum": 2.0, &"fl_supply_crate": 1.0},
	&"guard_tower": {&"fl_ammo_box": 3.0, &"fl_frozen_corpse": 1.0},
	&"observatory": {&"fl_footlocker": 1.0, &"fl_sample_case": 1.0},
	&"closet": {&"fl_supply_crate": 2.0, &"fl_footlocker": 1.0},
	&"yard": {&"fl_supply_crate": 3.0, &"fl_fuel_drum": 1.0, &"fl_sled": 1.0, &"fl_frozen_corpse": 0.8},
	&"walkway": {&"fl_supply_crate": 1.0, &"fl_frozen_corpse": 0.5},
	&"ramp": {&"fl_supply_crate": 1.0, &"fl_frozen_corpse": 0.5},
	&"gate": {&"fl_ammo_box": 1.0},
	&"heliport": {&"fl_supply_crate": 2.0, &"fl_fuel_drum": 2.0},
	&"dock": {&"fl_supply_crate": 2.0, &"fl_sled": 1.0, &"fl_frozen_corpse": 1.0},
	&"snow": {&"fl_frozen_corpse": 2.0, &"fl_sled": 1.0, &"fl_supply_crate": 1.0},
	&"crystal_lab": {&"fl_sample_case": 2.0, &"fl_cryo_pod": 1.0},
}

## Conteneur des coffres garantis des salles scellées.
const VAULT_CHEST := &"fl_ammo_box"


class Ctx:
	var L: FloorLayout
	var tiles: PackedByteArray
	var w: int = 0
	var world: WorldData
	var blocked: Dictionary = {}
	var reserved: Dictionary = {}
	var enemy_cells: Dictionary = {}
	var access: Dictionary = {}
	var room_of: PackedInt32Array
	var door_adj: Dictionary = {}
	var cand_cache: Dictionary = {}

	func room_id_at(p: Vector2i) -> int:
		if not L.in_bounds(p):
			return -1
		return room_of[p.y * L.size.x + p.x]


static func populate(L: FloorLayout, world: WorldData, seed_value: int, difficulty: int) -> void:
	var c := Ctx.new()
	c.L = L
	c.tiles = L.tiles
	c.w = L.size.x
	c.world = world
	_reserve(c)
	_index_rooms(c)
	for room0 in L.rooms:
		if BIG_PROPS.has(_role(room0)):
			_place_big(c, room0, BIG_PROPS[_role(room0)])
	for room1 in L.rooms:
		if room1.tags.has("outdoor"):
			var rng1 := RandomNumberGenerator.new()
			rng1.seed = hash([seed_value, L.floor_index, room1.id, "fl_outdoor"])
			_place_outdoor(c, room1, rng1)
	for room in L.rooms:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, L.floor_index, room.id, "fl_furnish"])
		_furnish(c, room, rng)
	for room2 in L.rooms:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([seed_value, L.floor_index, room2.id, "fl_containers"])
		_containers(c, room2, rng2)
	_hiding_spots(c, seed_value)
	for room3 in L.rooms:
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = hash([seed_value, L.floor_index, room3.id, "fl_enemies"])
		_enemies(c, room3, rng3, difficulty)


## Nombre d'ennemis attendu pour une salle (exposé pour les tests/debug).
static func enemy_count(room: FloorLayout.Room, floor_index: int, difficulty: int, roll: float) -> int:
	var dens := Cfg.by_index("enemy_density", difficulty, [0.020, 0.028, 0.036, 0.046, 0.058])
	var tmul := float(Cfg.get_dict("enemy_room_mult", {}).get(String(room.type), 1.0))
	var fmul := float(Cfg.get_dict("enemy_floor_mult", {}).get(str(floor_index), 1.0))
	var area := float(room.rect.get_area())
	# Grands extérieurs (plateau) : densité réduite (une partie de la surface est de la neige vide).
	if room.tags.has("outdoor"):
		area = minf(area, Cfg.getf("outdoor_area_cap", 220.0))
	var n := area * dens * tmul * fmul + roll
	var cap := Cfg.geti("enemy_max_per_room", 9)
	var bonus := 0
	if room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS:
		bonus = Cfg.geti("guards_min", 2) + int(Cfg.by_index("guards_bonus", difficulty, [0, 0, 1, 1, 2]))
		cap += bonus
	return mini(int(floor(n)) + bonus, cap)


static func _role(room: FloorLayout.Room) -> StringName:
	return StringName(room.tags[0]) if room.tags.size() > 0 else &"snow"


static func _narrow(room: FloorLayout.Room) -> bool:
	return _role(room) == &"walkway" and mini(room.rect.size.x, room.rect.size.y) < 3


# --- Réservations ----------------------------------------------------------------------

static func _index_rooms(c: Ctx) -> void:
	var L := c.L
	c.room_of = PackedInt32Array()
	c.room_of.resize(L.size.x * L.size.y)
	c.room_of.fill(-1)
	var area := PackedInt32Array()
	area.resize(L.size.x * L.size.y)
	area.fill(1 << 30)
	for r in L.rooms:
		var a := r.rect.get_area()
		for y in range(maxi(r.rect.position.y, 0), mini(r.rect.end.y, L.size.y)):
			for x in range(maxi(r.rect.position.x, 0), mini(r.rect.end.x, L.size.x)):
				var i := y * L.size.x + x
				if a < area[i]:
					area[i] = a
					c.room_of[i] = r.id
	for d in L.doors:
		c.door_adj[d.cell] = true
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			c.door_adj[d.cell + dir] = true


static func _reserve(c: Ctx) -> void:
	var L := c.L
	var around: Array[Vector2i] = []
	for d in L.doors:
		around.append(d.cell)
	for s in L.stairs:
		around.append(s.cell)
	for a in around:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				c.reserved[a + Vector2i(dx, dy)] = true
	for dy2 in range(-2, 3):
		for dx2 in range(-2, 3):
			c.reserved[L.player_spawn + Vector2i(dx2, dy2)] = true
	for e in L.extraction_cells:
		for dy3 in range(-1, 2):
			for dx3 in range(-1, 2):
				c.reserved[e + Vector2i(dx3, dy3)] = true
	# Ouvertures (salles « open » et passerelles) : passage libre devant et derrière chaque case du
	# bord de la salle qui donne sur une case praticable hors salle.
	for r in L.rooms:
		if not (r.tags.has("open") or r.tags.has("corridor")):
			continue
		var rr := r.rect
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				if x != rr.position.x and x != rr.end.x - 1 and y != rr.position.y and y != rr.end.y - 1:
					continue
				var p := Vector2i(x, y)
				if not FloorLayout.is_walkable_tile(L.get_tile(p)) or L.get_tile(p) == T.DOOR:
					continue
				var opening := false
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var q := p + d
					if not rr.has_point(q) and FloorLayout.is_walkable_tile(L.get_tile(q)) and L.get_tile(q) != T.DOOR:
						opening = true
				if not opening:
					continue
				for k in range(-1, 2):
					for kk in range(-1, 2):
						c.reserved[p + Vector2i(kk, k)] = true


static func _passable(c: Ctx, p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= c.w or p.y >= c.L.size.y:
		return false
	var t := c.tiles[p.y * c.w + p.x]
	return t != T.VOID and t != T.WALL and not c.blocked.has(p)


## Poser un obstacle en p garde connexes les cases praticables libres de l'anneau 3×3 et laisse
## un voisin libre à chaque conteneur / cachette voisin.
static func _keeps(c: Ctx, p: Vector2i) -> bool:
	var ring: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var q := p + Vector2i(dx, dy)
			if _passable(c, q):
				ring.append(q)
	if ring.is_empty():
		return false
	var seen := {ring[0]: true}
	var stack: Array[Vector2i] = [ring[0]]
	while not stack.is_empty():
		var q2: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := q2 + d
			if not seen.has(n) and ring.has(n):
				seen[n] = true
				stack.append(n)
	if seen.size() != ring.size():
		return false
	for d2: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var a := p + d2
		if not c.access.has(a):
			continue
		var free := false
		for d3: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var b := a + d3
			if b != p and _passable(c, b) and not c.access.has(b):
				free = true
		if not free:
			return false
	return true


static func _candidates(c: Ctx, room: FloorLayout.Room, placement: StringName) -> Array[Vector2i]:
	var key := "%d:%s" % [room.id, placement]
	if c.cand_cache.has(key):
		return c.cand_cache[key]
	var l_wall: Array[Vector2i] = []
	var l_center: Array[Vector2i] = []
	var l_any: Array[Vector2i] = []
	var L := c.L
	var w := L.size.x
	var tiles := L.tiles
	var r := room.rect
	var rid := room.id
	var room_of := c.room_of
	var reserved := c.reserved
	for y in range(maxi(r.position.y, 1), mini(r.end.y, L.size.y - 1)):
		var row := y * w
		for x in range(maxi(r.position.x, 1), mini(r.end.x, w - 1)):
			var i := row + x
			if room_of[i] != rid:
				continue
			var t := tiles[i]
			if t != T.FLOOR and t != T.STREET:
				continue
			var p := Vector2i(x, y)
			if reserved.has(p):
				continue
			l_any.append(p)
			var ta := tiles[i - 1]
			var tb := tiles[i + 1]
			var tc := tiles[i - w]
			var td := tiles[i + w]
			if ta == T.WALL or ta == T.VOID or tb == T.WALL or tb == T.VOID or tc == T.WALL or tc == T.VOID or td == T.WALL or td == T.VOID:
				l_wall.append(p)
			else:
				l_center.append(p)
	c.cand_cache["%d:wall" % room.id] = l_wall
	c.cand_cache["%d:center" % room.id] = l_center
	c.cand_cache["%d:any" % room.id] = l_any
	return c.cand_cache[key]


static func _place_blocking(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, placement: StringName) -> Vector2i:
	var p := _try_place(c, room, rng, placement)
	if p.x < 0 and placement != &"any":
		p = _try_place(c, room, rng, &"any")
	return p


static func _try_place(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, placement: StringName) -> Vector2i:
	var cells := _candidates(c, room, placement)
	var tries := Cfg.geti("place_tries", 24)
	while tries > 0 and not cells.is_empty():
		tries -= 1
		var i := rng.randi_range(0, cells.size() - 1)
		var p: Vector2i = cells[i]
		if c.blocked.has(p) or c.enemy_cells.has(p):
			cells.remove_at(i)
			continue
		if placement == &"center":
			var crowded := false
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if c.blocked.has(p + d):
					crowded = true
			if crowded:
				continue
		if _keeps(c, p):
			c.blocked[p] = true
			cells.remove_at(i)
			return p
	return Vector2i(-1, -1)


# --- Décors -----------------------------------------------------------------------------

static func _furnish(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var entries: Array = PROPS.get(role, [])
	var narrow := _narrow(room)
	var scale := 1.0
	if role == &"walkway":
		scale = maxf(1.0, float(maxi(room.rect.size.x, room.rect.size.y)) / 14.0)
	for e: Array in entries:
		var kind: StringName = e[0]
		if not c.world.has_prop(kind):
			continue
		if narrow and not NARROW_OK.has(kind):
			continue
		var n := int(round(rng.randi_range(int(e[1]), int(e[2])) * scale))
		for k in n:
			var p := _place_blocking(c, room, rng, e[3])
			if p.x < 0:
				break
			c.L.add_spawn(c.L.prop_spawns, p, kind, room.id)


## Grand décor centré : toute l'empreinte est bloquée, à distance des murs et portes.
static func _place_big(c: Ctx, room: FloorLayout.Room, def: Array) -> void:
	var kind: StringName = def[0]
	if not c.world.has_prop(kind):
		return
	var w: int = def[1]
	var h: int = def[2]
	var ctr := room.rect.get_center()
	var origin := Vector2i(-1, -1)
	for off: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(0, -1)]:
		var o := ctr - Vector2i(w / 2, h / 2) + off
		var ok := true
		for y in range(o.y - 1, o.y + h + 1):
			for x in range(o.x - 1, o.x + w + 1):
				var p := Vector2i(x, y)
				if c.L.get_tile(p) != T.FLOOR or c.reserved.has(p) or c.room_id_at(p) != room.id:
					ok = false
		if ok:
			origin = o
			break
	if origin.x < 0:
		return
	for y2 in range(origin.y, origin.y + h):
		for x2 in range(origin.x, origin.x + w):
			c.blocked[Vector2i(x2, y2)] = true
	var s := c.L.add_spawn(c.L.prop_spawns, Vector2i(origin.x + w / 2, origin.y + h - 1), kind, room.id)
	s.size = Vector2i(w, h)


## Structures sur la neige : empreinte entière sur la neige de la salle, entourée d'un anneau
## d'une case praticable libre (réservé ensuite) → le passage contourne toujours la structure.
static func _place_outdoor(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var area := float(room.rect.get_area())
	var n := int(floor(area / maxf(Cfg.getf("outdoor_structures_area", 170.0), 1.0)))
	var r := room.rect
	for k in n:
		var def: Array = OUTDOOR[rng.randi_range(0, OUTDOOR.size() - 1)]
		var kind: StringName = def[0]
		if not c.world.has_prop(kind):
			continue
		var w: int = def[1]
		var h: int = def[2]
		for t in 30:
			var o := Vector2i(rng.randi_range(r.position.x + 1, r.end.x - w - 1), rng.randi_range(r.position.y + 1, r.end.y - h - 1))
			var ok := true
			for y in range(o.y - 2, o.y + h + 2):
				for x in range(o.x - 2, o.x + w + 2):
					var p := Vector2i(x, y)
					var ring2 := x < o.x - 1 or x > o.x + w or y < o.y - 1 or y > o.y + h
					if ring2:
						# 2e anneau : seulement pas d'autre structure (passage large)
						if c.blocked.has(p) and c.room_id_at(p) == room.id:
							ok = false
						continue
					if c.L.get_tile(p) != T.STREET or c.reserved.has(p) or c.blocked.has(p) or c.room_id_at(p) != room.id:
						ok = false
						break
				if not ok:
					break
			if not ok:
				continue
			for y2 in range(o.y - 1, o.y + h + 1):
				for x2 in range(o.x - 1, o.x + w + 1):
					c.reserved[Vector2i(x2, y2)] = true
			for y3 in range(o.y, o.y + h):
				for x3 in range(o.x, o.x + w):
					c.blocked[Vector2i(x3, y3)] = true
			var s := c.L.add_spawn(c.L.prop_spawns, Vector2i(o.x + w / 2, o.y + h - 1), kind, room.id)
			s.size = Vector2i(w, h)
			break


# --- Conteneurs ---------------------------------------------------------------------------

static func _containers(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	if _narrow(room):
		return
	var weights: Dictionary = CONTAINERS.get(role, {&"fl_supply_crate": 1.0})
	var filtered := {}
	for k: StringName in weights:
		if c.world.has_container(k):
			filtered[k] = weights[k]
	if filtered.is_empty():
		return
	var dens := Cfg.getf("container_density", 0.03)
	var tmul := float(Cfg.get_dict("container_room_mult", {}).get(String(room.type), 1.0))
	var area := float(room.rect.get_area())
	if room.tags.has("outdoor"):
		area = minf(area, Cfg.getf("outdoor_area_cap", 220.0))
	var n := int(floor(area * dens * tmul + rng.randf()))
	var mn := 0
	if room.type == FloorLayout.ROOM_LOOT:
		mn = 1
	if room.type == FloorLayout.ROOM_SUPER_LOOT:
		mn = Cfg.geti("super_loot_chests", 2)
	n = clampi(maxi(n, mn), 0, Cfg.geti("container_max_per_room", 5))
	for i in n:
		var kind: StringName = VAULT_CHEST if room.type == FloorLayout.ROOM_SUPER_LOOT and i < mn and c.world.has_container(VAULT_CHEST) else _weighted(filtered, rng)
		var p := _place_blocking(c, room, rng, &"wall")
		if p.x < 0:
			break
		c.access[p] = true
		c.L.add_spawn(c.L.container_spawns, p, kind, room.id)


# --- Cachettes ------------------------------------------------------------------------------

static func _hiding_spots(c: Ctx, seed_value: int) -> void:
	var L := c.L
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, L.floor_index, "fl_hiding"])
	var rooms: Array[FloorLayout.Room] = []
	for room in L.rooms:
		if HIDING.has(_role(room)) and not _narrow(room) and room.type != FloorLayout.ROOM_SUPER_LOOT and room.type != FloorLayout.ROOM_BOSS:
			rooms.append(room)
	if rooms.is_empty():
		return
	for i in range(rooms.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := rooms[i]
		rooms[i] = rooms[j]
		rooms[j] = tmp
	var cfg := Cfg.cfg()
	var per_room := float(cfg.get_value("loot", "hiding_spots_per_room", 0.25))
	var mn := int(cfg.get_value("loot", "hiding_spots_min", 3))
	var mx := int(cfg.get_value("loot", "hiding_spots_max", 7))
	var want := clampi(int(round(L.rooms.size() * per_room)), mn, mx)
	var placed := 0
	for pass_i in 2:
		for room in rooms:
			if placed >= want:
				return
			var kind := _weighted(HIDING[_role(room)], rng)
			if not c.world.has_container(kind) and not HIDING_ALWAYS.has(kind):
				continue
			var p := _place_blocking(c, room, rng, &"wall")
			if p.x < 0:
				continue
			c.access[p] = true
			L.add_spawn(L.hiding_spot_spawns, p, kind, room.id)
			placed += 1

## Cachettes qui ne sont pas des conteneurs du monde (toujours autorisées).
const HIDING_ALWAYS := {&"fl_locker": true, &"fl_cryo": true, &"fl_snowdrift": true}


# --- Ennemis -------------------------------------------------------------------------------

static func _enemies(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, difficulty: int) -> void:
	if room.type == FloorLayout.ROOM_SPAWN:
		return
	var roster := c.world.get_roster(room.type)
	if roster.is_empty():
		return
	var roll := rng.randf()
	var n := enemy_count(room, c.L.floor_index, difficulty, roll)
	if n <= 0:
		return
	var safe := Cfg.geti("spawn_safe_radius", 9)
	var sealed := room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS
	var cells: Array[Vector2i] = []
	var r := room.rect
	var L := c.L
	var w := L.size.x
	var tiles := L.tiles
	var ext := {}
	for e in L.extraction_cells:
		ext[e] = true
	var ps := L.player_spawn
	var rid := room.id
	var room_of := c.room_of
	var blocked := c.blocked
	var ecells := c.enemy_cells
	var dadj := c.door_adj
	# Grands extérieurs : un échantillon régulier des cases suffit (et accélère le tirage).
	var stride := 1
	if room.tags.has("outdoor"):
		stride = 2
	for y in range(maxi(r.position.y, 0), mini(r.end.y, L.size.y), stride):
		var row := y * w
		for x in range(maxi(r.position.x, 0), mini(r.end.x, w), stride):
			var i := row + x
			if room_of[i] != rid:
				continue
			var t := tiles[i]
			if t != T.FLOOR and t != T.STREET:
				continue
			if not sealed and absi(x - ps.x) + absi(y - ps.y) < safe:
				continue
			var p := Vector2i(x, y)
			if blocked.has(p) or ecells.has(p) or ext.has(p):
				continue
			if dadj.has(p) and not sealed:
				continue
			cells.append(p)
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	var kinds: Array[StringName] = []
	var keys: Array = roster.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var total := 0.0
	for k0: Variant in keys:
		total += float(roster[k0])
	for k in Cfg.geti("enemy_max_per_room", 9) + 8:
		var roll2 := rng.randf() * total
		var pick: StringName = StringName(keys[keys.size() - 1])
		for k1: Variant in keys:
			roll2 -= float(roster[k1])
			if roll2 <= 0.0:
				pick = StringName(k1)
				break
		kinds.append(pick)
	if room.type == FloorLayout.ROOM_BOSS and c.world.boss_kind != &"":
		kinds[0] = c.world.boss_kind
		var ctr := room.rect.get_center()
		var best := -1
		var bd := 1 << 30
		for i3 in cells.size():
			var dd := absi(cells[i3].x - ctr.x) + absi(cells[i3].y - ctr.y)
			if dd < bd:
				bd = dd
				best = i3
		if best > 0:
			var t2 := cells[0]
			cells[0] = cells[best]
			cells[best] = t2
	for i2 in mini(n, cells.size()):
		c.enemy_cells[cells[i2]] = true
		c.L.add_spawn(c.L.enemy_spawns, cells[i2], kinds[i2], room.id)


static func _weighted(w: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var keys: Array = w.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var total := 0.0
	for k: Variant in keys:
		total += float(w[k])
	var roll := rng.randf() * total
	for k2: Variant in keys:
		roll -= float(w[k2])
		if roll <= 0.0:
			return StringName(k2)
	return StringName(keys[keys.size() - 1])
