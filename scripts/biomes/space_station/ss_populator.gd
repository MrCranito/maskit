extends RefCounted
## Peuplement d'un pont de la Station Orbitale : décors (prop_spawns), conteneurs
## (container_spawns), cachettes (hiding_spot_spawns) et ennemis (enemy_spawns).
## Mêmes règles que le peuplement Far West :
## - objets bloquants jamais sur/à côté d'une porte, d'un ascenseur, du spawn ou d'une
##   case d'extraction, et jamais de façon à couper un passage (anneau 3×3 connexe) ;
## - grands décors (navette, cœur du réacteur) : empreinte de plusieurs cases au centre ;
## - coursives de 2 cases : aucun objet bloquant (circulation) ;
## - ennemis : tirages indépendants de la difficulté → nombre croissant avec elle.
## L'ameublement dépend du rôle de la salle (Room.tags[0]).

const Cfg := preload("res://scripts/biomes/space_station/ss_config.gd")
const Fur := preload("res://scripts/dungeon/gen/furnisher.gd")
const Tpl := preload("res://scripts/biomes/space_station/ss_templates.gd")
const PropScript := preload("res://scripts/biomes/space_station/ss_prop.gd")
const T := FloorLayout.Tile

## Rôle → [kind, min, max, placement] ; placement : wall, center, any.
const PROPS := {
	&"hangar": [[&"cargo_stack", 2, 3, &"wall"], [&"fuel_drums", 1, 2, &"wall"], [&"warning_beacon", 1, 2, &"wall"], [&"floor_cables", 1, 1, &"any"]],
	&"pod_bay": [[&"escape_pod", 2, 3, &"wall"], [&"warning_beacon", 1, 1, &"wall"], [&"console", 1, 1, &"wall"]],
	&"quarters": [[&"bunk_bed", 2, 3, &"wall"], [&"vending_machine", 0, 1, &"wall"], [&"plant_bed", 0, 1, &"wall"]],
	&"mess_hall": [[&"mess_table", 2, 3, &"center"], [&"vending_machine", 1, 2, &"wall"]],
	&"infirmary": [[&"med_bed", 2, 3, &"wall"], [&"specimen_tank", 0, 1, &"wall"], [&"console", 0, 1, &"wall"]],
	&"lab": [[&"lab_bench", 1, 2, &"wall"], [&"specimen_tank", 1, 2, &"wall"], [&"console", 1, 1, &"wall"], [&"holo_table", 0, 1, &"center"]],
	&"lab_vault": [[&"specimen_tank", 1, 2, &"wall"], [&"lab_bench", 0, 1, &"wall"]],
	&"storage": [[&"cargo_stack", 2, 3, &"wall"], [&"fuel_drums", 1, 2, &"wall"]],
	&"cargo_hold": [[&"cargo_stack", 3, 4, &"any"], [&"fuel_drums", 1, 2, &"wall"], [&"floor_cables", 0, 1, &"any"]],
	&"hydroponics": [[&"plant_bed", 2, 4, &"any"], [&"pipe_cluster", 0, 1, &"wall"]],
	&"workshop": [[&"workbench", 1, 2, &"wall"], [&"power_node", 0, 1, &"wall"], [&"floor_cables", 1, 1, &"any"], [&"cargo_stack", 0, 1, &"wall"]],
	&"server_room": [[&"server_rack", 2, 4, &"wall"], [&"console", 1, 1, &"wall"], [&"floor_cables", 1, 1, &"any"]],
	&"closet": [[&"cargo_stack", 0, 1, &"wall"], [&"pipe_cluster", 0, 1, &"wall"]],
	&"bridge": [[&"console", 3, 4, &"wall"], [&"captain_chair", 1, 1, &"center"], [&"holo_table", 1, 1, &"center"]],
	&"radar": [[&"holo_table", 1, 1, &"center"], [&"console", 2, 2, &"wall"]],
	&"officer_quarters": [[&"bunk_bed", 1, 1, &"wall"], [&"console", 0, 1, &"wall"], [&"plant_bed", 0, 1, &"wall"]],
	&"armory": [[&"weapon_rack", 2, 3, &"wall"]],
	&"briefing": [[&"holo_table", 1, 1, &"center"], [&"mess_table", 1, 1, &"center"], [&"console", 1, 1, &"wall"]],
	&"observatory": [[&"captain_chair", 1, 2, &"center"], [&"plant_bed", 1, 1, &"wall"], [&"holo_table", 0, 1, &"center"]],
	&"captain_cabin": [[&"bunk_bed", 1, 1, &"wall"], [&"console", 1, 1, &"wall"], [&"plant_bed", 1, 1, &"wall"], [&"captain_chair", 0, 1, &"center"]],
	&"comms": [[&"console", 2, 3, &"wall"], [&"server_rack", 1, 2, &"wall"]],
	&"reactor": [[&"pipe_cluster", 3, 5, &"wall"], [&"coolant_tank", 2, 3, &"wall"], [&"power_node", 1, 2, &"wall"], [&"warning_beacon", 2, 3, &"wall"], [&"floor_cables", 2, 3, &"any"]],
	&"core_vault": [[&"power_node", 1, 2, &"wall"], [&"coolant_tank", 0, 1, &"wall"]],
	&"pumps": [[&"pipe_cluster", 2, 3, &"wall"], [&"coolant_tank", 1, 2, &"wall"], [&"floor_cables", 0, 1, &"any"]],
	&"coolant": [[&"coolant_tank", 2, 3, &"wall"], [&"pipe_cluster", 1, 2, &"wall"]],
	&"generator": [[&"power_node", 2, 3, &"wall"], [&"floor_cables", 1, 2, &"any"], [&"warning_beacon", 1, 1, &"wall"]],
	&"maintenance_pod": [[&"escape_pod", 1, 2, &"wall"], [&"warning_beacon", 1, 1, &"wall"]],
	&"command_pod": [[&"escape_pod", 1, 2, &"wall"], [&"warning_beacon", 1, 1, &"wall"]],
	&"corridor": [[&"warning_beacon", 0, 1, &"wall"], [&"pipe_cluster", 0, 1, &"wall"], [&"floor_cables", 0, 1, &"any"]],
	&"conduit": [[&"floor_cables", 0, 1, &"any"]],
}

## Grands décors : rôle → [kind, largeur, hauteur (cases)] posés au centre de la salle.
const BIG_PROPS := {&"hangar": [&"shuttle", 5, 3], &"reactor": [&"reactor_core", 2, 2]}

## Décors autorisés dans une coursive étroite (non gênants).
const NARROW_OK := {&"floor_cables": true}

## Rôle → cachettes {kind: poids} (locker, vent, cryo).
const HIDING := {
	&"hangar": {&"locker": 1.0, &"vent": 1.0},
	&"quarters": {&"locker": 2.0},
	&"officer_quarters": {&"locker": 2.0},
	&"captain_cabin": {&"locker": 1.0},
	&"storage": {&"locker": 1.0, &"vent": 1.0},
	&"cargo_hold": {&"vent": 1.0},
	&"infirmary": {&"cryo": 2.0},
	&"lab": {&"cryo": 1.0, &"vent": 1.0},
	&"mess_hall": {&"vent": 1.0},
	&"workshop": {&"locker": 1.0, &"vent": 1.0},
	&"server_room": {&"vent": 1.0},
	&"closet": {&"locker": 2.0},
	&"briefing": {&"locker": 1.0},
	&"comms": {&"vent": 1.0},
	&"hydroponics": {&"vent": 1.0},
	&"pumps": {&"vent": 2.0},
	&"coolant": {&"vent": 1.0},
	&"generator": {&"vent": 1.0},
	&"corridor": {&"vent": 1.0},
}

## Rôle → conteneurs {kind: poids}.
const CONTAINERS := {
	&"hangar": {&"cargo_crate": 3.0, &"locker": 1.0},
	&"pod_bay": {&"locker": 2.0, &"med_cabinet": 1.0},
	&"quarters": {&"locker": 3.0, &"cargo_crate": 0.5},
	&"mess_hall": {&"cargo_crate": 1.0, &"locker": 1.0},
	&"infirmary": {&"med_cabinet": 3.0, &"cryo_pod": 1.0},
	&"lab": {&"terminal": 2.0, &"med_cabinet": 1.0, &"cryo_pod": 1.0},
	&"lab_vault": {&"terminal": 1.0, &"cryo_pod": 1.0},
	&"storage": {&"cargo_crate": 4.0, &"locker": 1.0},
	&"cargo_hold": {&"cargo_crate": 4.0, &"locker": 0.5},
	&"hydroponics": {&"cargo_crate": 1.0},
	&"workshop": {&"cargo_crate": 2.0, &"locker": 1.0, &"terminal": 0.5},
	&"server_room": {&"terminal": 3.0},
	&"closet": {&"locker": 2.0, &"cargo_crate": 1.0},
	&"bridge": {&"terminal": 2.0, &"locker": 1.0},
	&"radar": {&"terminal": 2.0},
	&"officer_quarters": {&"locker": 3.0, &"armory_chest": 0.3},
	&"armory": {&"armory_chest": 2.0, &"locker": 1.0},
	&"briefing": {&"terminal": 1.0, &"locker": 1.0},
	&"observatory": {&"locker": 1.0},
	&"captain_cabin": {&"armory_chest": 1.0, &"locker": 1.0, &"terminal": 1.0},
	&"comms": {&"terminal": 3.0},
	&"reactor": {&"cryo_pod": 1.0, &"cargo_crate": 1.0},
	&"core_vault": {&"terminal": 1.0},
	&"pumps": {&"cargo_crate": 2.0, &"locker": 1.0, &"cryo_pod": 0.5},
	&"coolant": {&"cargo_crate": 1.0, &"cryo_pod": 0.5},
	&"generator": {&"cargo_crate": 2.0, &"locker": 1.0},
	&"maintenance_pod": {&"locker": 1.0},
	&"command_pod": {&"locker": 1.0},
	&"corridor": {&"cargo_crate": 1.0, &"cryo_pod": 0.5},
}

## Conteneur des coffres garantis des salles scellées.
const VAULT_CHEST := &"armory_chest"


class Ctx:
	var L: FloorLayout
	var tiles: PackedByteArray
	var w: int = 0
	var world: WorldData
	var blocked: Dictionary = {}
	var reserved: Dictionary = {}
	var enemy_cells: Dictionary = {}
	var room_of: PackedInt32Array
	var door_adj: Dictionary = {}
	var cand_cache: Dictionary = {}
	var fur: Fur.Ctx = null          ## Aménagement par gabarits (salles intérieures)

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
	# Pièces maîtresses (navette, cœur du réacteur) d'abord, puis aménagement par gabarits des
	# salles qui en ont un ; les autres (hangar, coursives…) gardent l'ameublement par règles.
	for room0 in L.rooms:
		if BIG_PROPS.has(_role(room0)):
			_place_big(c, room0, BIG_PROPS[_role(room0)])
	c.fur = Fur.make_ctx(L, c.blocked, c.reserved, c.enemy_cells, c.room_of, furniture_defs(), world.has_container)
	Fur.prepare(c.fur, Tpl.TEMPLATES, seed_value, "ss")
	c.tiles = L.tiles   # les cloisons ont modifié la grille
	for room in L.rooms:
		if Fur.templated(c.fur, room):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, L.floor_index, room.id, "ss_furnish"])
		_furnish(c, room, rng)
	for room2 in L.rooms:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([seed_value, L.floor_index, room2.id, "ss_containers"])
		_containers(c, room2, rng2)
	_hiding_spots(c, seed_value)
	for room3 in L.rooms:
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = hash([seed_value, L.floor_index, room3.id, "ss_enemies"])
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


static func _role(room: FloorLayout.Room) -> StringName:
	return StringName(room.tags[0]) if room.tags.size() > 0 else &"corridor"


static func _narrow(room: FloorLayout.Room) -> bool:
	return _role(room) == &"conduit" or (_role(room) == &"corridor" and mini(room.rect.size.x, room.rect.size.y) < 3)


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
	for dy2 in range(-1, 2):
		for dx2 in range(-1, 2):
			c.reserved[L.player_spawn + Vector2i(dx2, dy2)] = true
	for e in L.extraction_cells:
		for dy3 in range(-1, 2):
			for dx3 in range(-1, 2):
				c.reserved[e + Vector2i(dx3, dy3)] = true
	# Ouvertures (hangar, côté est) : passage libre devant et derrière l'ouverture.
	for r in L.rooms:
		if not r.tags.has("open"):
			continue
		var ox := r.rect.end.x - 1
		for y in range(r.rect.position.y, r.rect.end.y):
			if L.get_tile(Vector2i(ox, y)) != T.FLOOR:
				continue
			for k in range(-1, 2):
				for kk in range(-1, 2):
					c.reserved[Vector2i(ox + kk, y + k)] = true


static func _passable(c: Ctx, p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= c.w or p.y >= c.L.size.y:
		return false
	var t := c.tiles[p.y * c.w + p.x]
	return t != T.VOID and t != T.WALL and not c.blocked.has(p)


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
			if tiles[i] != T.FLOOR or c.room_of[i] != room.id:
				continue
			var p := Vector2i(x, y)
			if c.reserved.has(p):
				continue
			l_any.append(p)
			var nw := false
			for j: int in [i - 1, i + 1, i - w, i + w]:
				if tiles[j] == T.WALL or tiles[j] == T.VOID:
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
		# Connexité locale + accès conservé aux conteneurs / cachettes voisins.
		if Fur.keeps(c.fur, p):
			c.blocked[p] = true
			cells.remove_at(i)
			return p
	return Vector2i(-1, -1)


# --- Aménagement par gabarits ------------------------------------------------------------

static var _defs_cache: Dictionary = {}


## Définitions de mobilier (collision de ss_prop.gd + compléments du gabarit), décors de l'atlas.
static func furniture_defs() -> Dictionary:
	if not _defs_cache.is_empty():
		return _defs_cache
	for k: StringName in PropScript.DEFS:
		if not PropScript.is_known_kind(k):
			continue
		var d: Dictionary = (PropScript.DEFS[k] as Dictionary).duplicate()
		d.merge(Tpl.META.get(k, {}), true)
		_defs_cache[k] = d
	return _defs_cache


# --- Décors -----------------------------------------------------------------------------

static func _furnish(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var entries: Array = PROPS.get(role, [])
	var narrow := _narrow(room)
	var scale := 1.0
	if role == &"corridor":
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
	for off: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(1, -1)]:
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
	# Cellule d'appui : bas-centre de l'empreinte.
	c.L.add_spawn(c.L.prop_spawns, Vector2i(origin.x + w / 2, origin.y + h - 1), kind, room.id)


# --- Conteneurs ---------------------------------------------------------------------------

static func _containers(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	if _narrow(room) or role == &"elevator":
		return
	var weights: Dictionary = CONTAINERS.get(role, {&"cargo_crate": 1.0})
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
	if Fur.templated(c.fur, room):
		# Salle aménagée : conteneurs intégrés au mobilier (emplacements du gabarit).
		var firsts: Array = []
		if room.type == FloorLayout.ROOM_SUPER_LOOT and c.world.has_container(VAULT_CHEST):
			for k in mn:
				firsts.append(VAULT_CHEST)
		Fur.loot(c.fur, room, c.L.container_spawns, n, func() -> StringName: return _weighted(filtered, rng), firsts, "loot")
		return
	for i in n:
		var kind: StringName = VAULT_CHEST if room.type == FloorLayout.ROOM_SUPER_LOOT and i < mn and c.world.has_container(VAULT_CHEST) else _weighted(filtered, rng)
		var p := _place_blocking(c, room, rng, &"wall")
		if p.x < 0:
			break
		c.fur.access[p] = true
		c.L.add_spawn(c.L.container_spawns, p, kind, room.id)


# --- Cachettes ------------------------------------------------------------------------------

static func _hiding_spots(c: Ctx, seed_value: int) -> void:
	var L := c.L
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, L.floor_index, "ss_hiding"])
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
			if Fur.templated(c.fur, room):
				if Fur.loot(c.fur, room, L.hiding_spot_spawns, 1, func() -> StringName: return kind, [kind], "hide") > 0:
					placed += 1
				continue
			var p := _place_blocking(c, room, rng, &"wall")
			if p.x < 0:
				continue
			c.fur.access[p] = true
			L.add_spawn(L.hiding_spot_spawns, p, kind, room.id)
			placed += 1


# --- Ennemis -------------------------------------------------------------------------------

static func _enemies(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, difficulty: int) -> void:
	if room.type == FloorLayout.ROOM_SPAWN or _role(room) == &"elevator":
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
	for y in range(maxi(r.position.y, 0), mini(r.end.y, L.size.y)):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, w)):
			var i := y * w + x
			if tiles[i] != T.FLOOR or c.room_of[i] != room.id:
				continue
			var p := Vector2i(x, y)
			if c.blocked.has(p) or c.enemy_cells.has(p) or ext.has(p):
				continue
			if c.door_adj.has(p) and not sealed:
				continue
			if not sealed and absi(x - ps.x) + absi(y - ps.y) < safe:
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
		# Le boss au plus près du centre de l'arène.
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
