extends RefCounted
## Peuplement d'un étage de la station : décors (prop_spawns), conteneurs
## (container_spawns), cachettes (hiding_spot_spawns) et ennemis (enemy_spawns).
## Mêmes règles que le peuplement Far West : objets bloquants jamais sur / à côté
## d'une porte ou d'un escalier, jamais sur le spawn ni l'extraction, jamais de
## manière à couper un passage ; ennemis hors du rayon de sécurité du spawn ;
## nombre d'ennemis croissant avec la difficulté (tirages indépendants de la difficulté).
## L'ameublement dépend du rôle de la salle (Room.tags[0]).

const Cfg := preload("res://scripts/biomes/underwater/uw_config.gd")
const T := FloorLayout.Tile

## Rôle → [kind, min, max, placement] ; placement : &"wall", &"center" ou &"any".
const PROPS := {
	&"moon_pool": [[&"oxygen_rack", 1, 2, &"wall"], [&"diving_suit", 1, 2, &"wall"], [&"lamp_post", 1, 2, &"wall"], [&"cable_spool", 0, 1, &"wall"]],
	&"pod_bay": [[&"alarm_light", 1, 2, &"wall"], [&"oxygen_rack", 0, 1, &"wall"], [&"console", 1, 1, &"wall"], [&"lamp_post", 0, 1, &"wall"]],
	&"quarters": [[&"bunk_bed", 2, 3, &"wall"], [&"lamp_post", 0, 1, &"wall"], [&"desk", 0, 1, &"wall"]],
	&"cabin": [[&"bunk_bed", 1, 1, &"wall"], [&"desk", 0, 1, &"wall"]],
	&"mess": [[&"mess_table", 2, 3, &"center"], [&"lamp_post", 1, 1, &"wall"], [&"crate_stack", 0, 1, &"wall"]],
	&"infirmary": [[&"med_bed", 2, 3, &"wall"], [&"specimen_tank", 0, 1, &"wall"], [&"console", 0, 1, &"wall"]],
	&"storage": [[&"crate_stack", 1, 3, &"wall"], [&"oxygen_rack", 1, 1, &"wall"], [&"cable_spool", 0, 1, &"any"]],
	&"comms": [[&"console", 2, 3, &"wall"], [&"server_rack", 0, 1, &"wall"], [&"desk", 0, 1, &"wall"]],
	&"workshop": [[&"cable_spool", 1, 2, &"any"], [&"pipes", 1, 1, &"wall"], [&"diving_suit", 0, 1, &"wall"], [&"crate_stack", 0, 1, &"wall"]],
	&"aquarium": [[&"aquarium_tank", 2, 4, &"wall"], [&"coral_cluster", 0, 1, &"any"], [&"lamp_post", 0, 1, &"wall"]],
	&"bio_lab": [[&"lab_bench", 2, 3, &"center"], [&"specimen_tank", 1, 2, &"wall"], [&"console", 0, 1, &"wall"]],
	&"sample_vault": [[&"specimen_tank", 1, 2, &"wall"]],
	&"hydroponics": [[&"hydro_planter", 2, 4, &"center"], [&"pipes", 0, 1, &"wall"], [&"lamp_post", 1, 1, &"wall"]],
	&"server": [[&"server_rack", 2, 4, &"wall"], [&"console", 1, 1, &"wall"], [&"alarm_light", 0, 1, &"wall"]],
	&"office": [[&"desk", 1, 1, &"wall"], [&"aquarium_tank", 0, 1, &"wall"], [&"console", 0, 1, &"wall"]],
	&"dissection": [[&"lab_bench", 1, 2, &"center"], [&"specimen_tank", 1, 2, &"wall"], [&"med_bed", 0, 1, &"wall"]],
	&"lab_storage": [[&"crate_stack", 1, 2, &"wall"], [&"specimen_tank", 0, 1, &"wall"], [&"oxygen_rack", 0, 1, &"wall"]],
	&"decon": [[&"pipes", 1, 2, &"wall"], [&"alarm_light", 1, 1, &"wall"], [&"diving_suit", 0, 1, &"wall"]],
	&"pump_room": [[&"pump", 1, 2, &"wall"], [&"pipes", 1, 2, &"wall"], [&"valve_wheel", 1, 2, &"wall"], [&"alarm_light", 0, 1, &"wall"]],
	&"trench_vault": [[&"coral_cluster", 0, 1, &"wall"]],
	&"engine": [[&"generator", 1, 1, &"wall"], [&"pipes", 1, 2, &"wall"], [&"valve_wheel", 0, 1, &"wall"], [&"kelp", 1, 2, &"any"], [&"coral_cluster", 1, 2, &"any"], [&"alarm_light", 1, 1, &"wall"]],
	&"ballast": [[&"pipes", 1, 2, &"wall"], [&"pump", 0, 1, &"wall"], [&"valve_wheel", 1, 1, &"wall"], [&"coral_cluster", 0, 1, &"any"]],
	&"maintenance": [[&"cable_spool", 1, 1, &"any"], [&"diving_suit", 1, 1, &"wall"], [&"crate_stack", 0, 1, &"wall"], [&"lamp_post", 1, 1, &"wall"], [&"pipes", 0, 1, &"wall"]],
	&"flooded_hall": [[&"kelp", 1, 3, &"any"], [&"coral_cluster", 1, 2, &"any"], [&"alarm_light", 0, 1, &"wall"], [&"pipes", 0, 1, &"wall"]],
	&"boss_lair": [[&"coral_cluster", 2, 4, &"wall"], [&"kelp", 1, 2, &"wall"], [&"alarm_light", 1, 1, &"wall"]],
	&"escape_pod": [[&"alarm_light", 1, 1, &"wall"], [&"oxygen_rack", 0, 1, &"wall"], [&"lamp_post", 0, 1, &"wall"]],
	&"tube": [[&"coral_cluster", 0, 1, &"wall"], [&"valve_wheel", 0, 1, &"wall"]],
	&"catwalk": [[&"pipes", 0, 1, &"wall"], [&"valve_wheel", 0, 1, &"wall"], [&"kelp", 0, 1, &"wall"]],
}

## Rôle → cachettes possibles {kind: poids}. Rôles absents : pas de cachette.
const HIDING := {
	&"moon_pool": {&"uw_pipes": 1.0, &"uw_locker": 1.0},
	&"pod_bay": {&"uw_locker": 1.0},
	&"quarters": {&"uw_locker": 3.0},
	&"cabin": {&"uw_locker": 2.0},
	&"mess": {&"uw_locker": 1.0, &"uw_lab_table": 1.0},
	&"infirmary": {&"uw_lab_table": 1.0, &"uw_locker": 1.0},
	&"storage": {&"uw_pipes": 1.0, &"uw_locker": 1.0},
	&"comms": {&"uw_locker": 1.0},
	&"workshop": {&"uw_pipes": 2.0},
	&"bio_lab": {&"uw_lab_table": 3.0},
	&"dissection": {&"uw_lab_table": 2.0},
	&"hydroponics": {&"uw_lab_table": 1.0},
	&"lab_storage": {&"uw_locker": 1.0},
	&"decon": {&"uw_locker": 2.0},
	&"office": {&"uw_lab_table": 1.0},
	&"pump_room": {&"uw_pipes": 3.0},
	&"engine": {&"uw_pipes": 2.0},
	&"ballast": {&"uw_pipes": 2.0},
	&"maintenance": {&"uw_locker": 1.0, &"uw_pipes": 1.0},
	&"catwalk": {&"uw_pipes": 1.0},
}

## Rôle → conteneurs possibles {kind: poids}.
const CONTAINERS := {
	&"moon_pool": {&"uw_crate": 2.0, &"uw_tank": 1.0, &"uw_diver_corpse": 0.5},
	&"pod_bay": {&"uw_crate": 1.0, &"uw_locker": 1.0},
	&"quarters": {&"uw_locker": 3.0, &"uw_crate": 1.0},
	&"cabin": {&"uw_locker": 2.0, &"uw_crate": 0.5},
	&"mess": {&"uw_crate": 2.0, &"uw_locker": 1.0},
	&"infirmary": {&"uw_lab_cabinet": 2.0, &"uw_locker": 1.0},
	&"storage": {&"uw_crate": 3.0, &"uw_tank": 1.0},
	&"comms": {&"uw_locker": 2.0, &"uw_crate": 1.0},
	&"workshop": {&"uw_crate": 2.0, &"uw_tank": 1.0},
	&"aquarium": {&"uw_lab_cabinet": 1.0, &"uw_diver_corpse": 1.0},
	&"bio_lab": {&"uw_lab_cabinet": 3.0, &"uw_sample_chest": 0.5},
	&"sample_vault": {&"uw_sample_chest": 3.0, &"uw_lab_cabinet": 1.0},
	&"hydroponics": {&"uw_crate": 1.0, &"uw_lab_cabinet": 1.0},
	&"server": {&"uw_locker": 1.0},
	&"office": {&"uw_locker": 1.0, &"uw_lab_cabinet": 1.0, &"uw_sample_chest": 0.3},
	&"dissection": {&"uw_lab_cabinet": 2.0, &"uw_diver_corpse": 1.0},
	&"lab_storage": {&"uw_lab_cabinet": 2.0, &"uw_crate": 2.0},
	&"decon": {&"uw_locker": 2.0},
	&"pump_room": {&"uw_tank": 2.0, &"uw_crate": 1.0},
	&"trench_vault": {&"uw_sample_chest": 3.0, &"uw_tank": 1.0},
	&"engine": {&"uw_diver_corpse": 2.0, &"uw_tank": 1.0},
	&"ballast": {&"uw_tank": 3.0},
	&"maintenance": {&"uw_crate": 2.0, &"uw_locker": 1.0},
	&"flooded_hall": {&"uw_diver_corpse": 2.0, &"uw_crate": 1.0},
	&"boss_lair": {&"uw_diver_corpse": 2.0, &"uw_sample_chest": 0.5},
	&"escape_pod": {&"uw_crate": 1.0},
	&"tube": {&"uw_diver_corpse": 1.0, &"uw_crate": 1.0},
	&"catwalk": {&"uw_diver_corpse": 1.0, &"uw_tank": 0.5},
}

## Conteneur garanti des salles super_loot.
const VAULT_CHEST := &"uw_sample_chest"


class Ctx:
	var L: FloorLayout
	var world: WorldData
	var blocked: Dictionary = {}
	var reserved: Dictionary = {}
	var enemy_cells: Dictionary = {}
	var room_of: PackedInt32Array
	var door_adj: Dictionary = {}
	var cand_cache: Dictionary = {}

	func room_id_at(p: Vector2i) -> int:
		if not L.in_bounds(p):
			return -1
		return room_of[p.y * L.size.x + p.x]


## `extra_blocked` : cases déjà occupées par un grand décor (bassin d'amarrage).
static func populate(L: FloorLayout, world: WorldData, seed_value: int, difficulty: int, extra_blocked: Array[Vector2i]) -> void:
	var c := Ctx.new()
	c.L = L
	c.world = world
	_reserve(c)
	for b in extra_blocked:
		c.blocked[b] = true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				c.reserved[b + Vector2i(dx, dy)] = true
	_index_rooms(c)
	for room in L.rooms:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "uw", L.floor_index, room.id, "furnish"])
		_furnish(c, room, rng)
	for room2 in L.rooms:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([seed_value, "uw", L.floor_index, room2.id, "containers"])
		_containers(c, room2, rng2)
	_hiding_spots(c, seed_value)
	for room3 in L.rooms:
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = hash([seed_value, "uw", L.floor_index, room3.id, "enemies"])
		_enemies(c, room3, rng3, difficulty)


## Nombre d'ennemis attendu pour une salle (exposé pour les tests/debug).
static func enemy_count(room: FloorLayout.Room, floor_index: int, difficulty: int, roll: float) -> int:
	var dens := Cfg.by_index("enemy_density", difficulty, [0.020, 0.028, 0.036, 0.046, 0.058])
	var tmul := float(Cfg.get_dict("enemy_room_mult", {}).get(String(room.type), 1.0))
	var fmul := float(Cfg.get_dict("enemy_floor_mult", {}).get(str(floor_index), 1.0))
	var area := float(room.rect.get_area())
	var n := area * dens * tmul * fmul + roll
	var cap := Cfg.geti("enemy_max_per_room", 9)
	var bonus := 0
	if room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS:
		bonus = Cfg.geti("guards_min", 2) + int(Cfg.by_index("guards_bonus", difficulty, [0, 0, 1, 1, 2]))
		cap += bonus
	return mini(int(floor(n)) + bonus, cap)


# --- Réservations ---------------------------------------------------------

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
	for dy2 in range(-1, 2):
		for dx2 in range(-1, 2):
			c.reserved[L.player_spawn + Vector2i(dx2, dy2)] = true
	for e in L.extraction_cells:
		for dy3 in range(-1, 2):
			for dx3 in range(-1, 2):
				c.reserved[e + Vector2i(dx3, dy3)] = true


static func _passable(c: Ctx, p: Vector2i) -> bool:
	return FloorLayout.is_walkable_tile(c.L.get_tile(p)) and not c.blocked.has(p)


## Bloquer p ne coupe aucun passage (anneau 3x3 autour de p connexe en 4-voisinage).
static func _keeps_connectivity(c: Ctx, p: Vector2i) -> bool:
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
	return seen.size() == ring.size()


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
	for y in range(maxi(r.position.y, 1), mini(r.end.y, L.size.y - 1)):
		for x in range(maxi(r.position.x, 1), mini(r.end.x, w - 1)):
			var i := y * w + x
			if tiles[i] != T.FLOOR:
				continue
			if c.room_of[i] != room.id:
				continue
			var p := Vector2i(x, y)
			if c.reserved.has(p):
				continue
			l_any.append(p)
			var nw := false
			for j: int in [i - 1, i + 1, i - w, i + w]:
				var tn := tiles[j]
				if tn == T.WALL or tn == T.VOID:
					nw = true
					break
			if nw:
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
		if _keeps_connectivity(c, p):
			c.blocked[p] = true
			cells.remove_at(i)
			return p
	return Vector2i(-1, -1)


static func _role(room: FloorLayout.Room) -> StringName:
	return StringName(room.tags[0]) if room.tags.size() > 0 else &"tube"


# --- Décors ------------------------------------------------------------------

static func _furnish(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var entries: Array = PROPS.get(role, [])
	# Les longs tubes reçoivent un peu plus de décors.
	var scale := 1.0
	if room.type == FloorLayout.ROOM_CORRIDOR:
		scale = clampf(maxf(room.rect.size.x, room.rect.size.y) / 8.0, 0.5, 2.0)
	for e: Array in entries:
		var kind: StringName = e[0]
		if not c.world.has_prop(kind):
			continue
		var n := int(round(rng.randi_range(int(e[1]), int(e[2])) * scale))
		for k in n:
			var p := _place_blocking(c, room, rng, e[3])
			if p.x < 0:
				break
			c.L.add_spawn(c.L.prop_spawns, p, kind, room.id)


# --- Conteneurs ----------------------------------------------------------------

static func _containers(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var weights: Dictionary = CONTAINERS.get(role, {&"uw_crate": 1.0})
	var filtered := {}
	for k: StringName in weights:
		if c.world.has_container(k):
			filtered[k] = weights[k]
	if filtered.is_empty():
		return
	var dens := Cfg.getf("container_density", 0.03)
	var tmul := float(Cfg.get_dict("container_room_mult", {}).get(String(room.type), 1.0))
	var n := int(floor(room.rect.get_area() * dens * tmul + rng.randf()))
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
		c.L.add_spawn(c.L.container_spawns, p, kind, room.id)


# --- Cachettes ------------------------------------------------------------------

static func _hiding_spots(c: Ctx, seed_value: int) -> void:
	var L := c.L
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "uw", L.floor_index, "hiding"])
	var rooms: Array[FloorLayout.Room] = []
	for room in L.rooms:
		if HIDING.has(_role(room)) and room.type != FloorLayout.ROOM_SUPER_LOOT and room.type != FloorLayout.ROOM_BOSS:
			rooms.append(room)
	if rooms.is_empty():
		return
	for i in range(rooms.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := rooms[i]
		rooms[i] = rooms[j]
		rooms[j] = tmp
	var per_room := float(Cfg.section_value("loot", "hiding_spots_per_room", 0.25))
	var mn := int(Cfg.section_value("loot", "hiding_spots_min", 3))
	var mx := int(Cfg.section_value("loot", "hiding_spots_max", 7))
	var want := clampi(int(round(L.rooms.size() * per_room)), mn, mx)
	var placed := 0
	for pass_i in 2:
		for room in rooms:
			if placed >= want:
				return
			var kind := _weighted(HIDING[_role(room)], rng)
			var p := _place_blocking(c, room, rng, &"wall")
			if p.x < 0:
				continue
			L.add_spawn(L.hiding_spot_spawns, p, kind, room.id)
			placed += 1


# --- Ennemis -------------------------------------------------------------------

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
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			if c.L.get_tile(p) != T.FLOOR:
				continue
			if c.blocked.has(p) or c.enemy_cells.has(p) or c.room_id_at(p) != room.id:
				continue
			if c.L.extraction_cells.has(p):
				continue
			if c.door_adj.has(p) and not sealed:
				continue
			if not sealed and absi(p.x - c.L.player_spawn.x) + absi(p.y - c.L.player_spawn.y) < safe:
				continue
			cells.append(p)
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	var kinds: Array[StringName] = []
	for k in Cfg.geti("enemy_max_per_room", 9) + 8:
		kinds.append(_weighted(roster, rng))
	if room.type == FloorLayout.ROOM_BOSS and c.world.boss_kind != &"":
		kinds[0] = c.world.boss_kind
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
