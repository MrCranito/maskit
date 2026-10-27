extends RefCounted
## Peuplement d'un étage déjà structuré : décors (prop_spawns), conteneurs
## (container_spawns) et ennemis (enemy_spawns).
##
## Règles :
## - décors et conteneurs occupent leur case (considérés bloquants) ; jamais sur
##   ou à côté d'une porte / d'un escalier, jamais sur le spawn joueur ni une
##   case d'extraction, et jamais de manière à couper un passage (test local :
##   les cases libres autour restent connexes entre elles) ;
## - ennemis : une case libre par ennemi, hors portes/escaliers, hors du rayon
##   de sécurité autour du spawn joueur ;
## - le nombre d'ennemis ne dépend de la difficulté que via la densité : les
##   tirages aléatoires par salle sont indépendants de la difficulté, donc le
##   total est croissant avec la difficulté pour une même seed.
##
## L'ameublement est choisi d'après le rôle de la salle (Room.tags[0], posé par
## les constructeurs : saloon_hall, jail_cell, street, tunnel…).

const Cfg := preload("res://scripts/dungeon/gen/gen_config.gd")
const T := FloorLayout.Tile

## Rôle → liste de [kind, min, max, placement] ; placement : &"wall" (contre un
## mur), &"center" (loin des murs) ou &"any".
const PROPS := {
	&"street_entry": [[&"cactus", 1, 2, &"wall"], [&"wanted_poster", 1, 1, &"wall"], [&"tumbleweed", 0, 1, &"any"]],
	&"street": [[&"hitching_post", 2, 4, &"wall"], [&"water_trough", 1, 2, &"wall"], [&"lantern", 1, 3, &"wall"], [&"wanted_poster", 1, 2, &"wall"], [&"tumbleweed", 1, 3, &"any"], [&"wagon_wheel", 0, 2, &"wall"], [&"cactus", 0, 2, &"wall"]],
	&"street_exit": [[&"hitching_post", 1, 2, &"wall"], [&"lantern", 1, 1, &"wall"], [&"cactus", 1, 2, &"wall"]],
	&"alley": [[&"wagon_wheel", 0, 1, &"wall"], [&"lantern", 0, 1, &"wall"], [&"tumbleweed", 0, 1, &"any"]],
	&"backyard": [[&"cactus", 1, 3, &"any"], [&"hay_bale", 0, 2, &"wall"], [&"wagon_wheel", 0, 1, &"wall"]],
	&"plaza": [[&"water_trough", 1, 1, &"center"], [&"bench", 1, 2, &"wall"], [&"water_tower", 0, 1, &"wall"], [&"cactus", 0, 2, &"wall"]],
	&"saloon_hall": [[&"saloon_bar", 1, 1, &"wall"], [&"piano", 1, 1, &"wall"], [&"poker_table", 2, 3, &"center"], [&"lantern", 1, 2, &"wall"]],
	&"saloon_office": [[&"desk", 1, 1, &"wall"], [&"safe", 0, 1, &"wall"]],
	&"storage": [[&"shelf", 1, 2, &"wall"]],
	&"bank_hall": [[&"counter", 1, 2, &"wall"], [&"bench", 1, 2, &"wall"], [&"wanted_poster", 0, 1, &"wall"]],
	&"bank_office": [[&"desk", 1, 1, &"wall"]],
	&"bank_vault": [[&"safe", 1, 2, &"wall"]],
	&"sheriff_office": [[&"desk", 1, 1, &"wall"], [&"wanted_poster", 1, 2, &"wall"], [&"lantern", 0, 1, &"wall"]],
	&"jail_cell": [[&"jail_bars", 1, 2, &"wall"], [&"bed", 1, 1, &"wall"]],
	&"sheriff_armory": [[&"shelf", 1, 2, &"wall"]],
	&"store_shop": [[&"counter", 1, 1, &"wall"], [&"shelf", 1, 3, &"wall"]],
	&"office": [[&"desk", 1, 1, &"wall"]],
	&"hotel_reception": [[&"counter", 1, 1, &"wall"], [&"bench", 0, 2, &"wall"], [&"lantern", 0, 1, &"wall"]],
	&"hotel_dining": [[&"poker_table", 1, 2, &"center"], [&"piano", 0, 1, &"wall"]],
	&"corridor": [[&"lantern", 0, 1, &"wall"]],
	&"upper_corridor": [[&"lantern", 0, 1, &"wall"]],
	&"bedroom": [[&"bed", 1, 1, &"wall"], [&"lantern", 0, 1, &"wall"]],
	&"suite": [[&"bed", 1, 1, &"wall"], [&"desk", 0, 1, &"wall"]],
	&"gaming_room": [[&"poker_table", 1, 2, &"center"]],
	&"stable_main": [[&"hay_bale", 2, 4, &"wall"], [&"water_trough", 1, 1, &"wall"], [&"hitching_post", 0, 2, &"wall"]],
	&"stable_box": [[&"hay_bale", 1, 2, &"wall"]],
	&"church_nave": [[&"altar", 1, 1, &"wall"], [&"pew", 3, 6, &"center"], [&"lantern", 0, 2, &"wall"]],
	&"church_sacristy": [[&"altar", 0, 1, &"wall"]],
	&"mine_entrance": [[&"rail_track", 2, 4, &"any"], [&"mine_cart", 1, 1, &"wall"], [&"lantern", 1, 2, &"wall"], [&"support_beam", 0, 2, &"wall"]],
	&"mine_tools": [[&"shelf", 1, 1, &"wall"], [&"mine_cart", 0, 1, &"wall"]],
	&"mine_entry": [[&"rail_track", 1, 2, &"any"], [&"mine_cart", 1, 1, &"wall"], [&"lantern", 1, 1, &"wall"], [&"support_beam", 0, 1, &"wall"]],
	&"ore_room": [[&"ore_pile", 1, 2, &"wall"], [&"mine_cart", 0, 1, &"wall"], [&"rail_track", 1, 2, &"any"], [&"support_beam", 0, 1, &"wall"], [&"lantern", 0, 1, &"wall"]],
	&"tunnel": [[&"rail_track", 0, 1, &"any"]],
}

## Rôle → conteneurs possibles {kind: poids}.
const CONTAINERS := {
	&"street_entry": {&"barrel": 1.0, &"crate": 1.0},
	&"street": {&"wagon": 2.0, &"barrel": 2.0, &"crate": 2.0, &"corpse": 1.0},
	&"street_exit": {&"stagecoach": 3.0, &"crate": 1.0},
	&"alley": {&"barrel": 2.0, &"crate": 2.0, &"corpse": 1.0},
	&"backyard": {&"wagon": 1.0, &"crate": 2.0, &"corpse": 1.5},
	&"plaza": {&"barrel": 1.0, &"wagon": 1.0},
	&"saloon_hall": {&"barrel": 2.0, &"crate": 1.0, &"corpse": 1.0},
	&"saloon_office": {&"cupboard": 2.0, &"chest": 1.0},
	&"storage": {&"crate": 3.0, &"barrel": 2.0},
	&"bank_hall": {&"cupboard": 1.0, &"corpse": 1.0},
	&"bank_office": {&"cupboard": 2.0, &"wardrobe": 1.0},
	&"bank_vault": {&"chest": 1.0},
	&"sheriff_office": {&"cupboard": 2.0, &"chest": 1.0},
	&"jail_cell": {&"corpse": 2.0, &"crate": 1.0},
	&"sheriff_armory": {&"chest": 2.0, &"crate": 1.0},
	&"store_shop": {&"crate": 2.0, &"barrel": 2.0, &"cupboard": 1.0},
	&"office": {&"cupboard": 2.0, &"wardrobe": 1.0},
	&"hotel_reception": {&"cupboard": 1.0, &"chest": 0.5},
	&"hotel_dining": {&"cupboard": 2.0, &"barrel": 1.0},
	&"corridor": {&"crate": 1.0},
	&"upper_corridor": {&"crate": 1.0},
	&"bedroom": {&"wardrobe": 2.0, &"cupboard": 1.0, &"chest": 0.5, &"corpse": 0.5},
	&"suite": {&"chest": 2.0, &"wardrobe": 1.0},
	&"gaming_room": {&"chest": 1.0, &"cupboard": 1.0},
	&"stable_main": {&"wagon": 2.0, &"barrel": 1.0, &"crate": 1.0},
	&"stable_box": {&"crate": 2.0, &"barrel": 1.0},
	&"church_nave": {&"corpse": 1.0, &"chest": 0.5},
	&"church_sacristy": {&"wardrobe": 2.0, &"chest": 1.0},
	&"mine_entrance": {&"crate": 2.0, &"barrel": 1.0},
	&"mine_tools": {&"crate": 2.0, &"chest": 1.0},
	&"mine_entry": {&"crate": 1.0},
	&"ore_room": {&"crate": 2.0, &"barrel": 1.0, &"chest": 1.0, &"corpse": 1.0},
	&"tunnel": {&"corpse": 1.0, &"crate": 1.0},
}


class Ctx:
	var L: FloorLayout
	var world: WorldData
	var blocked: Dictionary = {}    ## Cases occupées par décor/conteneur
	var reserved: Dictionary = {}   ## Cases interdites (portes, escaliers, abords, spawn, extraction)
	var enemy_cells: Dictionary = {}
	var room_of: PackedInt32Array      ## Case → id de salle (la plus petite), -1 sinon
	var door_adj: Dictionary = {}      ## Portes et leurs 4 voisines
	var cand_cache: Dictionary = {}    ## "room:placement" → Array[Vector2i]

	func room_id_at(p: Vector2i) -> int:
		if not L.in_bounds(p):
			return -1
		return room_of[p.y * L.size.x + p.x]


static func populate(L: FloorLayout, world: WorldData, seed_value: int, difficulty: int) -> void:
	var c := Ctx.new()
	c.L = L
	c.world = world
	_reserve(c)
	_index_rooms(c)
	for room in L.rooms:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, L.floor_index, room.id, "furnish"])
		_furnish(c, room, rng)
	# Conteneurs avant ennemis : la position des conteneurs ne dépend pas de la
	# difficulté (le nombre d'ennemis, lui, en dépend).
	for room2 in L.rooms:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([seed_value, L.floor_index, room2.id, "containers"])
		_containers(c, room2, rng2)
	for room3 in L.rooms:
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = hash([seed_value, L.floor_index, room3.id, "enemies"])
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

## Table case → salle (équivalent de FloorLayout.room_at, précalculé).
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


static func _near_wall(c: Ctx, p: Vector2i) -> bool:
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var t := c.L.get_tile(p + d)
		if t == T.WALL or t == T.VOID:
			return true
	return false


## Bloquer p ne coupe aucun passage : les cases libres de l'anneau 3x3 autour
## de p restent connexes entre elles (en 4-voisinage, dans l'anneau).
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


## Cases candidates (fixes) d'une salle pour un objet bloquant, mises en cache
## par (salle, placement). Les cases occupées en sont retirées au fil de l'eau.
static func _candidates(c: Ctx, room: FloorLayout.Room, placement: StringName) -> Array[Vector2i]:
	var key := "%d:%s" % [room.id, placement]
	if c.cand_cache.has(key):
		return c.cand_cache[key]
	# Un seul passage sur la salle remplit les trois listes (wall, center, any).
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
			var t := tiles[i]
			if t != T.FLOOR and t != T.STREET:
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


## Tirages aléatoires dans les candidates jusqu'à trouver une case libre qui ne
## coupe aucun passage. Les cases devenues inutilisables sont retirées du cache.
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
			# Pas collé à un autre objet : laisse circuler autour des tables/bancs.
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
	return StringName(room.tags[0]) if room.tags.size() > 0 else &"street"


# --- Décors ------------------------------------------------------------------

static func _furnish(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var entries: Array = PROPS.get(role, [])
	var scale := 1.0
	if room.outdoor and role == &"street":
		scale = maxf(1.0, room.rect.size.x / 30.0)
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
	var weights: Dictionary = CONTAINERS.get(role, {&"crate": 1.0})
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
		var kind: StringName = &"chest" if room.type == FloorLayout.ROOM_SUPER_LOOT and i < mn and c.world.has_container(&"chest") else _weighted(filtered, rng)
		var p := _place_blocking(c, room, rng, &"wall")
		if p.x < 0:
			break
		c.L.add_spawn(c.L.container_spawns, p, kind, room.id)


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
	# Ordre des cases indépendant de la difficulté (pour la croissance).
	var cells: Array[Vector2i] = []
	var r := room.rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var p := Vector2i(x, y)
			var t := c.L.get_tile(p)
			if t != T.FLOOR and t != T.STREET:
				continue
			if c.blocked.has(p) or c.enemy_cells.has(p) or c.room_id_at(p) != room.id:
				continue
			if c.L.extraction_cells.has(p) or c.L.get_tile(p) == T.DOOR:
				continue
			if c.door_adj.has(p):
				# Les gardes d'une petite salle scellée peuvent se tenir près de la porte.
				if not sealed:
					continue
			# Les salles scellées sont derrière une porte verrouillée : pas de rayon de sécurité.
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
	# Le boss de la salle boss : un seul colosse garanti.
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
