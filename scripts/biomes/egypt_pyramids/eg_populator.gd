extends RefCounted
## Peuplement d'un étage des Pyramides d'Égypte : décors (prop_spawns), conteneurs, cachettes
## et ennemis (mêmes règles que le peuplement Far West / centre commercial) :
## - décors, conteneurs et cachettes occupent leur case (bloquants) ; jamais sur ou à côté d'une
##   porte / d'un escalier / de l'arrivée / d'une extraction, jamais en coupant un passage ;
## - ennemis : tirages par salle (le total croît avec la difficulté) ; roster du monde par type
##   de salle, surchargé par rôle ; boss garanti dans le sanctuaire ; gardes au trésor.
## Ameublement choisi d'après Room.tags[0] (rôle posé par eg_plan.gd).

const Cfg := preload("res://scripts/biomes/egypt_pyramids/eg_config.gd")
const T := FloorLayout.Tile

## Emprise (cases) des grands décors : [largeur, hauteur]. Point d'appui = case du bas, au centre.
const BIG := {&"eg_sarcophagus_big": Vector2i(2, 1), &"eg_offering_table": Vector2i(2, 1), &"eg_tent": Vector2i(2, 2)}

## Rôle → [kind, min, max, placement] ; placement : &"wall", &"center", &"any".
const PROPS := {
	&"tomb": [[&"eg_sarcophagus_big", 1, 1, &"center"], [&"eg_canopic_jars", 1, 2, &"wall"], [&"eg_brazier", 0, 1, &"wall"]],
	&"trap_hall": [[&"eg_spikes", 2, 4, &"any"], [&"eg_rubble", 0, 1, &"any"]],
	&"guard_hall": [[&"eg_weapon_rack", 1, 2, &"wall"], [&"eg_brazier", 1, 1, &"wall"], [&"eg_bench", 0, 1, &"wall"]],
	&"offering": [[&"eg_offering_table", 1, 1, &"center"], [&"eg_canopic_jars", 1, 2, &"wall"], [&"eg_brazier", 1, 2, &"wall"]],
	&"embalming": [[&"eg_embalming_table", 1, 1, &"center"], [&"eg_canopic_jars", 1, 2, &"wall"], [&"eg_brazier", 0, 1, &"wall"]],
	&"scribe": [[&"eg_bench", 1, 2, &"wall"], [&"eg_scroll_shelf", 1, 1, &"wall"], [&"eg_brazier", 0, 1, &"wall"]],
	&"statue_hall": [[&"eg_statue", 2, 3, &"wall"], [&"eg_brazier", 1, 2, &"wall"]],
	&"treasury": [[&"eg_statue", 1, 1, &"wall"], [&"eg_brazier", 2, 2, &"wall"]],
	&"hypostyle": [[&"eg_brazier", 2, 3, &"wall"], [&"eg_statue", 1, 2, &"wall"], [&"eg_rubble", 1, 2, &"any"]],
	&"sanctuary": [[&"eg_statue", 2, 2, &"wall"], [&"eg_brazier", 4, 4, &"wall"]],
	&"court": [[&"eg_brazier", 1, 2, &"wall"], [&"eg_rubble", 0, 2, &"any"], [&"eg_statue", 0, 1, &"wall"]],
	&"gallery": [[&"eg_brazier", 3, 5, &"wall"], [&"eg_statue", 1, 3, &"wall"], [&"eg_rubble", 1, 3, &"any"]],
	&"inner_court": [[&"eg_brazier", 2, 4, &"wall"], [&"eg_rubble", 0, 2, &"any"]],
	&"desert": [[&"eg_rubble", 1, 3, &"any"], [&"eg_cactus", 0, 2, &"any"], [&"eg_bones", 0, 2, &"any"]],
	&"oasis": [[&"eg_tent", 1, 2, &"center"], [&"eg_rubble", 0, 1, &"any"], [&"eg_cactus", 1, 2, &"any"]],
	&"camp": [[&"eg_tent", 2, 3, &"center"], [&"eg_brazier", 1, 2, &"any"], [&"eg_weapon_rack", 0, 1, &"wall"]],
	&"dunes": [[&"eg_bones", 1, 3, &"any"], [&"eg_rubble", 1, 2, &"any"], [&"eg_cactus", 0, 2, &"any"]],
	&"avenue": [[&"eg_brazier", 2, 2, &"wall"], [&"eg_rubble", 0, 1, &"any"]],
	&"gate": [],
}

## Rôle → conteneurs possibles {kind: poids}.
const CONTAINERS := {
	&"tomb": {&"eg_sarcophagus": 3.0, &"eg_jar": 1.0, &"eg_mummy": 1.0},
	&"trap_hall": {&"eg_jar": 2.0, &"eg_corpse": 1.0},
	&"guard_hall": {&"eg_chest": 1.0, &"eg_jar": 1.0, &"eg_corpse": 1.5},
	&"offering": {&"eg_altar": 2.0, &"eg_jar": 2.0, &"eg_basket": 1.0},
	&"embalming": {&"eg_jar": 2.0, &"eg_mummy": 2.0},
	&"scribe": {&"eg_basket": 2.0, &"eg_jar": 1.0, &"eg_chest": 0.5},
	&"statue_hall": {&"eg_jar": 2.0, &"eg_altar": 0.5, &"eg_corpse": 0.5},
	&"treasury": {&"eg_gold_chest": 1.0},
	&"hypostyle": {&"eg_jar": 2.0, &"eg_altar": 1.0, &"eg_corpse": 1.0},
	&"sanctuary": {&"eg_gold_chest": 1.0, &"eg_altar": 1.0},
	&"court": {&"eg_jar": 2.0, &"eg_basket": 1.0, &"eg_corpse": 0.5},
	&"gallery": {&"eg_jar": 2.0, &"eg_basket": 1.0, &"eg_corpse": 1.0},
	&"inner_court": {&"eg_jar": 1.0, &"eg_altar": 1.0},
	&"desert": {&"eg_jar": 1.0, &"eg_corpse": 1.5, &"eg_basket": 0.5},
	&"oasis": {&"eg_basket": 2.0, &"eg_jar": 1.0},
	&"camp": {&"eg_chest": 2.0, &"eg_basket": 2.0, &"eg_corpse": 1.0},
	&"dunes": {&"eg_corpse": 2.0, &"eg_jar": 1.0},
	&"avenue": {&"eg_jar": 1.0},
}

## Rôle → cachettes {kind: poids}.
const HIDING := {
	&"tomb": {&"eg_sarcophagus_hide": 3.0},
	&"offering": {&"eg_big_jar": 2.0},
	&"embalming": {&"eg_sarcophagus_hide": 2.0},
	&"scribe": {&"eg_big_jar": 2.0},
	&"guard_hall": {&"eg_big_jar": 1.0},
	&"statue_hall": {&"eg_big_jar": 1.0},
	&"hypostyle": {&"eg_big_jar": 2.0},
	&"court": {&"eg_big_jar": 1.0, &"eg_hay_cart": 1.0},
	&"gallery": {&"eg_big_jar": 1.0},
	&"desert": {&"eg_hay_cart": 1.0},
	&"oasis": {&"eg_hay_cart": 2.0},
	&"camp": {&"eg_hay_cart": 2.0, &"eg_big_jar": 1.0},
	&"dunes": {&"eg_hay_cart": 1.0},
}

## Rôle → roster d'ennemis prioritaire sur celui du monde (roster provisoire fw_*).
const ROLE_ROSTER := {
	&"tomb": {&"fw_bandit": 2.0, &"fw_raider": 2.0, &"fw_bruiser": 0.5},
	&"trap_hall": {&"fw_raider": 3.0, &"fw_bandit": 1.0},
	&"guard_hall": {&"fw_marauder": 2.0, &"fw_sharpshooter": 1.5, &"fw_bandit": 2.0},
	&"camp": {&"fw_bandit": 3.0, &"fw_sharpshooter": 1.5, &"fw_guard_dog": 1.0},
	&"dunes": {&"fw_guard_dog": 2.0, &"fw_bandit": 2.0, &"fw_raider": 1.0},
	&"hypostyle": {&"fw_marauder": 1.5, &"fw_bandit": 2.0, &"fw_sharpshooter": 1.0},
}

const BESTIARY_SECTION := "bestiary_egypt_pyramids"
const SUPER_LOOT_CONTAINER := &"eg_gold_chest"


class Ctx:
	var L: FloorLayout
	var world: WorldData
	var blocked: Dictionary = {}
	var reserved: Dictionary = {}
	var enemy_cells: Dictionary = {}
	var room_of: PackedInt32Array
	var door_adj: Dictionary = {}
	var cand_cache: Dictionary = {}
	var access: Dictionary = {}   ## cases de conteneurs / cachettes (doivent garder un voisin libre)
	var tries: int = 24

	func room_id_at(p: Vector2i) -> int:
		if not L.in_bounds(p):
			return -1
		return room_of[p.y * L.size.x + p.x]


static func populate(L: FloorLayout, world: WorldData, seed_value: int, difficulty: int) -> void:
	var c := Ctx.new()
	c.L = L
	c.world = world
	c.tries = Cfg.geti("place_tries", 24)
	var dbg := OS.has_environment("EG_DEBUG")
	var t0 := Time.get_ticks_usec()
	_reserve(c)
	_index_rooms(c)
	var t1 := Time.get_ticks_usec()
	for room in L.rooms:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, L.floor_index, room.id, "eg_furnish"])
		_furnish(c, room, rng)
	var t2 := Time.get_ticks_usec()
	for room2 in L.rooms:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([seed_value, L.floor_index, room2.id, "eg_containers"])
		_containers(c, room2, rng2)
	_hiding_spots(c, seed_value)
	var t3 := Time.get_ticks_usec()
	for room3 in L.rooms:
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = hash([seed_value, L.floor_index, room3.id, "eg_enemies"])
		_enemies(c, room3, rng3, difficulty)
	if dbg:
		print("pop reserve %.1f furnish %.1f cont %.1f enemies %.1f" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (Time.get_ticks_usec() - t3) / 1000.0])


static func footprint(kind: StringName, anchor: Vector2i, size: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var fp: Vector2i = size if size != Vector2i.ZERO else BIG.get(kind, Vector2i.ONE)
	var x0 := anchor.x - (fp.x - 1) / 2
	for dy in fp.y:
		for dx in fp.x:
			out.append(Vector2i(x0 + dx, anchor.y - dy))
	return out


static func spawn_footprint(s: FloorLayout.Spawn) -> Array[Vector2i]:
	if s.size != Vector2i.ONE:
		return FloorLayout.spawn_cells(s)
	return footprint(s.kind, s.cell)


static func enemy_count(room: FloorLayout.Room, floor_index: int, difficulty: int, roll: float) -> int:
	var dens := Cfg.by_index("enemy_density", difficulty, [0.020, 0.028, 0.036, 0.046, 0.058])
	var tmul := float(Cfg.get_dict("enemy_room_mult", {}).get(String(room.type), 1.0))
	var omul := Cfg.getf("eg_outdoor_enemy_mult", 0.45) if room.outdoor else 1.0
	var n := float(room.rect.get_area()) * dens * tmul * omul + roll
	var cap := Cfg.geti("enemy_max_per_room", 9)
	var bonus := 0
	if room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS:
		bonus = Cfg.geti("guards_min", 2) + int(Cfg.by_index("guards_bonus", difficulty, [0, 0, 1, 1, 2]))
		cap += bonus
	return mini(int(floor(n)) + bonus, cap)


# --- Réservations ---------------------------------------------------------------

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
	around.append(L.player_spawn)
	for e in L.extraction_cells:
		around.append(e)
	for a in around:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				c.reserved[a + Vector2i(dx, dy)] = true
	for d2 in L.doors:
		var axis := Vector2i.RIGHT if d2.vertical else Vector2i.DOWN
		c.reserved[d2.cell + axis * 2] = true
		c.reserved[d2.cell - axis * 2] = true
	# Passages à 2 cases (portails des temples = salles « gate », portes monumentales du grand
	# temple = « gates » du contrat de rendu) : couloirs étroits laissés libres.
	for r in L.rooms:
		if r.tags.size() > 0 and r.tags[0] == "gate":
			for y in range(r.rect.position.y, r.rect.end.y):
				for x in range(r.rect.position.x, r.rect.end.x):
					c.reserved[Vector2i(x, y)] = true
	var contract: Dictionary = L.get_meta(&"render_contract", {})
	for g: Variant in contract.get("gates", []):
		if g is Array and g.size() >= 2:
			for dy in range(-1, 2):
				for dx in range(-1, 3):
					c.reserved[Vector2i(int(g[0]) + dx, int(g[1]) + dy)] = true
	var ctr := L.player_spawn
	for dy2 in range(-3, 4):
		for dx2 in range(-3, 4):
			c.reserved[ctr + Vector2i(dx2, dy2)] = true


const RING: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]
static var _ring_tab: PackedByteArray = PackedByteArray()


## table[mask] = 1 si les cases allumées de l'anneau sont connexes entre elles (en 4-voisinage :
## deux cases de l'anneau sont voisines si consécutives dans l'ordre E, SE, S, SW, W, NW, N, NE).
static func _ring_table() -> PackedByteArray:
	if not _ring_tab.is_empty():
		return _ring_tab
	_ring_tab.resize(256)
	for m in 256:
		if m == 0:
			continue
		var first := -1
		for k in 8:
			if m & (1 << k):
				first = k
				break
		var seen := 1 << first
		var stack := [first]
		while not stack.is_empty():
			var k2: int = stack.pop_back()
			for nb: int in [(k2 + 1) % 8, (k2 + 7) % 8]:
				if (m & (1 << nb)) and not (seen & (1 << nb)):
					seen |= 1 << nb
					stack.append(nb)
		_ring_tab[m] = 1 if seen == m else 0
	return _ring_tab


static func _passable(c: Ctx, p: Vector2i) -> bool:
	return FloorLayout.is_walkable_tile(c.L.get_tile(p)) and not c.blocked.has(p)


## Poser un bloc en p laisse ses voisins praticables connexes entre eux (pas de coupure locale)
## et chaque conteneur / cachette voisin garde un accès.
static func _keeps(c: Ctx, p: Vector2i) -> bool:
	# Anneau des 8 voisins : bits 0..7 (E, SE, S, SW, W, NW, N, NE) ; connexe (4-voisinage dans
	# l'anneau) ⇔ les cases praticables forment un seul arc. Table précalculée.
	var mask := 0
	var i := 0
	for d0: Vector2i in RING:
		if _passable(c, p + d0):
			mask |= 1 << i
		i += 1
	if mask == 0 or _ring_table()[mask] == 0:
		return false
	for d2: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var a := p + d2
		if c.access.has(a):
			var free := false
			for d3: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var b := a + d3
				if b != p and _passable(c, b):
					free = true
			if not free:
				return false
	return true


static func _candidates(c: Ctx, room: FloorLayout.Room, placement: StringName) -> Array[Vector2i]:
	if c.cand_cache.is_empty():
		_build_candidates(c)
	var key := "%d:%s" % [room.id, placement]
	if not c.cand_cache.has(key):
		c.cand_cache[key] = [] as Array[Vector2i]
	return c.cand_cache[key]


## Listes de cases candidates (mur / centre / toutes) de toutes les salles en un seul passage.
static func _build_candidates(c: Ctx) -> void:
	var L := c.L
	var w := L.size.x
	var tiles := L.tiles
	var lists := {}
	for r in L.rooms:
		lists[r.id] = [[] as Array[Vector2i], [] as Array[Vector2i], [] as Array[Vector2i]]
	for y in range(1, L.size.y - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			var t := tiles[i]
			if t != T.FLOOR and t != T.STREET:
				continue
			var rid := c.room_of[i]
			if rid < 0:
				continue
			var p := Vector2i(x, y)
			if c.reserved.has(p):
				continue
			var e: Array = lists[rid]
			(e[2] as Array[Vector2i]).append(p)
			var tl := tiles[i - 1]
			var tr := tiles[i + 1]
			var tu := tiles[i - w]
			var td := tiles[i + w]
			if tl == T.WALL or tl == T.VOID or tr == T.WALL or tr == T.VOID or tu == T.WALL or tu == T.VOID or td == T.WALL or td == T.VOID:
				(e[0] as Array[Vector2i]).append(p)
			else:
				(e[1] as Array[Vector2i]).append(p)
	for rid2: int in lists:
		var e2: Array = lists[rid2]
		c.cand_cache["%d:wall" % rid2] = e2[0]
		c.cand_cache["%d:center" % rid2] = e2[1]
		c.cand_cache["%d:any" % rid2] = e2[2]


static func _place_blocking(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, placement: StringName) -> Vector2i:
	var p := _try_place(c, room, rng, placement)
	if p.x < 0 and placement != &"any":
		p = _try_place(c, room, rng, &"any")
	return p


static func _try_place(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, placement: StringName) -> Vector2i:
	var cells := _candidates(c, room, placement)
	var tries := c.tries
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
		cells.remove_at(i)
	return Vector2i(-1, -1)


static func _try_place_big(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, kind: StringName) -> Vector2i:
	var cells := _candidates(c, room, &"any")
	var tries := c.tries
	while tries > 0 and not cells.is_empty():
		tries -= 1
		var p: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		if _big_fits(c, room, kind, p):
			for q in footprint(kind, p):
				c.blocked[q] = true
			return p
	return Vector2i(-1, -1)


static func _big_fits(c: Ctx, room: FloorLayout.Room, kind: StringName, p: Vector2i) -> bool:
	var fp := footprint(kind, p)
	for q in fp:
		if c.reserved.has(q) or c.enemy_cells.has(q) or c.room_id_at(q) != room.id:
			return false
		var t := c.L.get_tile(q)
		if t != T.FLOOR and t != T.STREET:
			return false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not _passable(c, q + Vector2i(dx, dy)):
					return false
	return true


static func _role(room: FloorLayout.Room) -> StringName:
	return StringName(room.tags[0]) if room.tags.size() > 0 else &"desert"


# --- Décors ---------------------------------------------------------------------

static func _furnish(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var entries: Array = PROPS.get(role, [])
	var scale := 1.0
	if room.outdoor:
		scale = clampf(float(room.rect.get_area()) / Cfg.getf("eg_outdoor_props_area", 220.0), 0.6, 2.0)
	for e: Array in entries:
		var kind: StringName = e[0]
		if not c.world.has_prop(kind):
			continue
		var n := int(round(rng.randi_range(int(e[1]), int(e[2])) * scale))
		for k in n:
			var p: Vector2i
			if BIG.has(kind):
				p = _try_place_big(c, room, rng, kind)
			else:
				p = _place_blocking(c, room, rng, e[3])
			if p.x < 0:
				break
			c.L.add_spawn(c.L.prop_spawns, p, kind, room.id)


# --- Conteneurs ------------------------------------------------------------------

static func _containers(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var weights: Dictionary = CONTAINERS.get(role, {})
	var filtered := {}
	for k: StringName in weights:
		if c.world.has_container(k):
			filtered[k] = weights[k]
	if filtered.is_empty():
		return
	var dens := Cfg.getf("container_density", 0.03)
	var tmul := float(Cfg.get_dict("container_room_mult", {}).get(String(room.type), 1.0))
	var omul := Cfg.getf("eg_outdoor_container_mult", 0.4) if room.outdoor else 1.0
	var n := int(floor(room.rect.get_area() * dens * tmul * omul + rng.randf()))
	var mn := 0
	if room.type == FloorLayout.ROOM_LOOT:
		mn = 1
	if room.type == FloorLayout.ROOM_SUPER_LOOT:
		mn = Cfg.geti("super_loot_chests", 2)
	if room.type == FloorLayout.ROOM_BOSS:
		mn = maxi(mn, 1)
	n = clampi(maxi(n, mn), 0, Cfg.geti("container_max_per_room", 5))
	for i in n:
		var forced := (room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS) and i < mn and c.world.has_container(SUPER_LOOT_CONTAINER)
		var kind: StringName = SUPER_LOOT_CONTAINER if forced else _weighted(filtered, rng)
		var p := _place_blocking(c, room, rng, &"wall")
		if p.x < 0:
			break
		c.access[p] = true
		c.L.add_spawn(c.L.container_spawns, p, kind, room.id)


# --- Cachettes ---------------------------------------------------------------------

static func _hiding_spots(c: Ctx, seed_value: int) -> void:
	var L := c.L
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, L.floor_index, "eg_hiding"])
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
	var per_room := Cfg.getf("eg_hiding_spots_per_room", 0.3)
	var mn := Cfg.geti("eg_hiding_spots_min", 5)
	var mx := Cfg.geti("eg_hiding_spots_max", 10)
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
			c.access[p] = true
			L.add_spawn(L.hiding_spot_spawns, p, kind, room.id)
			placed += 1


# --- Ennemis ------------------------------------------------------------------------

static func _enemies(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, difficulty: int) -> void:
	if room.type == FloorLayout.ROOM_SPAWN or room.type == FloorLayout.ROOM_CORRIDOR and _role(room) == &"gate":
		return
	var roster: Dictionary = ROLE_ROSTER.get(_role(room), c.world.get_roster(room.type))
	if room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS:
		roster = c.world.get_roster(room.type)
	if roster.is_empty():
		return
	var roll := rng.randf()
	var n := enemy_count(room, c.L.floor_index, difficulty, roll)
	if n <= 0:
		return
	var safe := Cfg.geti("spawn_safe_radius", 9)
	var sealed := room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS
	# Cases candidates (hors réservations, portes, abords de l'arrivée) : listes en cache par salle.
	var cells: Array[Vector2i] = []
	var pool: Array[Vector2i] = []
	if sealed:
		# Salles scellées (petites) : toutes les cases de sol, abords de porte compris.
		var r := room.rect
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var q := Vector2i(x, y)
				if (c.L.get_tile(q) == T.FLOOR or c.L.get_tile(q) == T.STREET) and c.room_id_at(q) == room.id:
					pool.append(q)
	else:
		pool = _candidates(c, room, &"any")
	for p: Vector2i in pool:
		if c.blocked.has(p) or c.enemy_cells.has(p):
			continue
		if c.door_adj.has(p) and not sealed:
			continue
		if not sealed and c.L.floor_index == 0 and absi(p.x - c.L.player_spawn.x) + absi(p.y - c.L.player_spawn.y) < safe:
			continue
		cells.append(p)
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	# Grandes zones de sable : on ne garde qu'un échantillon (déjà mélangé) pour le regroupement.
	if cells.size() > 160:
		cells.resize(160)
	_group_cells(cells, n, rng)
	var kinds: Array[StringName] = []
	for k in n + 1:
		kinds.append(_weighted(roster, rng))
	if room.type == FloorLayout.ROOM_BOSS and c.world.boss_kind != &"":
		kinds[0] = c.world.boss_kind
	for i2 in mini(n, cells.size()):
		c.enemy_cells[cells[i2]] = true
		c.L.add_spawn(c.L.enemy_spawns, cells[i2], kinds[i2], room.id)


static func _bcfg(key: String, def: Variant) -> Variant:
	return Cfg.cfg().get_value(BESTIARY_SECTION, key, def)


static func _group_cells(cells: Array[Vector2i], n_needed: int, rng: RandomNumberGenerator) -> void:
	if cells.size() < 3 or n_needed < 2 or rng.randf() >= float(_bcfg("group_chance", 0.7)):
		return
	var size := maxi(int(_bcfg("group_size", 3)), 1)
	var rest: Array[Vector2i] = cells.duplicate()
	cells.clear()
	var anchor: Vector2i = rest[0]
	while cells.size() < n_needed and not rest.is_empty():
		var take := mini(size, mini(rest.size(), n_needed - cells.size()))
		for _k in take:
			var best := 0
			var best_d := 1 << 30
			for i in rest.size():
				var cc := rest[i]
				var dd := absi(cc.x - anchor.x) + absi(cc.y - anchor.y)
				if dd < best_d:
					best_d = dd
					best = i
			cells.append(rest[best])
			rest.remove_at(best)
		if not rest.is_empty():
			anchor = rest[rest.size() - 1]
	cells.append_array(rest)


## Ordre des clés = ordre d'insertion (constantes et .tres) : déterministe sans tri.
static func _weighted(w: Dictionary, rng: RandomNumberGenerator) -> StringName:
	var keys: Array = w.keys()
	var total := 0.0
	for k: Variant in keys:
		total += float(w[k])
	var roll := rng.randf() * total
	for k2: Variant in keys:
		roll -= float(w[k2])
		if roll <= 0.0:
			return StringName(k2)
	return StringName(keys[keys.size() - 1])
