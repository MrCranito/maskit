extends RefCounted
## Peuplement du rez-de-chaussée du Carnaval hanté : décors (prop_spawns), conteneurs,
## cachettes et ennemis. Même logique que le peuplement des zones ouvertes du centre
## commercial (mall_populator.gd) :
## - décors, conteneurs et cachettes occupent leur case (bloquants) ; jamais sur ou à côté
##   d'une porte / du spawn / d'une extraction, jamais en coupant un passage (anneau 3×3
##   connexe) ;
## - ennemis : tirages par salle indépendants de la difficulté (le total croît avec elle) ;
##   roster du monde par type de salle, surchargé par rôle ; boss garanti dans la piste du
##   chapiteau (salle boss), gardes dans la roulotte du Directeur (super_loot).
## Ameublement choisi d'après Room.tags[0] (rôle posé par hc_plan.gd).
## Roster provisoire = monstres mall_* (bestiaire propre du carnaval : phase 2).

const Cfg := preload("res://scripts/biomes/haunted_carnival/hc_config.gd")
const Plan := preload("res://scripts/biomes/haunted_carnival/hc_plan.gd")
const Fur := preload("res://scripts/dungeon/gen/furnisher.gd")
const T := FloorLayout.Tile

## Emprise (cases) des grands décors : [largeur, hauteur]. Point d'appui = case du bas, centre.
const BIG := {
	&"hc_bumper_car": Vector2i(2, 1), &"hc_food_cart": Vector2i(2, 1), &"hc_cage": Vector2i(2, 1),
	&"hc_bleachers": Vector2i(3, 1), &"hc_ring_barrier": Vector2i(2, 1), &"hc_shooting_counter": Vector2i(2, 1),
}

## Rôle → [kind, min, max, placement] ; placement : &"wall", &"center", &"any".
const PROPS := {
	&"entrance": [[&"hc_lamp_post", 2, 3, &"wall"], [&"hc_debris", 2, 4, &"any"], [&"hc_balloon_bunch", 1, 2, &"any"], [&"hc_barrier", 1, 3, &"any"], [&"hc_trash_bin", 1, 2, &"wall"]],
	&"avenue": [[&"hc_lamp_post", 4, 7, &"wall"], [&"hc_debris", 4, 8, &"any"], [&"hc_barrier", 2, 4, &"any"], [&"hc_food_cart", 1, 3, &"center"], [&"hc_dead_tree", 1, 2, &"wall"], [&"hc_trash_bin", 2, 4, &"wall"], [&"hc_sign_post", 1, 2, &"any"]],
	&"alley": [[&"hc_lamp_post", 1, 3, &"wall"], [&"hc_debris", 2, 4, &"any"], [&"hc_dead_tree", 0, 2, &"wall"], [&"hc_barrier", 0, 2, &"any"], [&"hc_trash_bin", 0, 2, &"wall"]],
	&"plaza": [[&"hc_lamp_post", 3, 5, &"any"], [&"hc_balloon_bunch", 2, 3, &"any"], [&"hc_bench", 3, 5, &"center"], [&"hc_debris", 3, 5, &"any"], [&"hc_food_cart", 1, 2, &"center"], [&"hc_sign_post", 1, 2, &"any"]],
	&"wheel_yard": [[&"hc_lamp_post", 2, 3, &"any"], [&"hc_barrier", 2, 4, &"any"], [&"hc_debris", 2, 4, &"any"], [&"hc_dead_tree", 1, 2, &"wall"], [&"hc_bench", 1, 2, &"center"]],
	&"ride_yard": [[&"hc_lamp_post", 1, 3, &"any"], [&"hc_barrier", 2, 4, &"any"], [&"hc_bumper_car", 1, 3, &"center"], [&"hc_debris", 2, 4, &"any"], [&"hc_dead_tree", 0, 2, &"wall"], [&"hc_balloon_bunch", 0, 1, &"any"]],
	&"stand_shooting": [[&"hc_shooting_counter", 1, 1, &"wall"], [&"hc_prize_shelf", 1, 1, &"wall"]],
	&"stand_candy": [[&"hc_candy_machine", 1, 1, &"wall"], [&"hc_prize_shelf", 0, 1, &"wall"]],
	&"stand_ducks": [[&"hc_duck_pool", 1, 1, &"center"], [&"hc_prize_shelf", 0, 1, &"wall"]],
	&"stand_prizes": [[&"hc_prize_shelf", 1, 2, &"wall"], [&"hc_plush_pile", 1, 2, &"any"]],
	&"stand_fortune": [[&"hc_crystal_table", 1, 1, &"center"], [&"hc_prize_shelf", 0, 1, &"wall"]],
	&"stand_popcorn": [[&"hc_candy_machine", 1, 1, &"wall"], [&"hc_bench", 0, 1, &"wall"]],
	&"stand_hammer": [[&"hc_hammer_tower", 1, 1, &"wall"], [&"hc_prize_shelf", 0, 1, &"wall"]],
	&"stand_souvenirs": [[&"hc_prize_shelf", 1, 2, &"wall"], [&"hc_plush_pile", 0, 1, &"any"]],
	&"tent_mirrors": [[&"hc_mirror", 3, 6, &"wall"], [&"hc_mirror", 1, 3, &"center"]],
	&"tent_freaks": [[&"hc_cage", 2, 3, &"wall"], [&"hc_plush_pile", 0, 1, &"any"], [&"hc_bench", 0, 2, &"center"]],
	&"tent_theatre": [[&"hc_bench", 3, 5, &"center"], [&"hc_puppet_stage", 1, 1, &"wall"]],
	&"caravan_home": [[&"hc_bunk", 1, 1, &"wall"], [&"hc_trunk", 0, 1, &"wall"]],
	&"caravan_storage": [[&"hc_crate_stack", 1, 2, &"wall"], [&"hc_plush_pile", 0, 1, &"any"]],
	&"caravan_director": [[&"hc_bunk", 1, 1, &"wall"], [&"hc_crystal_table", 0, 1, &"center"]],
	&"ticket_booth": [[&"hc_prize_shelf", 0, 1, &"wall"]],
	&"service_yard": [[&"hc_crate_stack", 1, 2, &"wall"], [&"hc_debris", 1, 2, &"any"], [&"hc_trash_bin", 0, 1, &"wall"]],
	&"hall_hangar": [[&"hc_bumper_car", 2, 4, &"center"], [&"hc_crate_stack", 1, 2, &"wall"], [&"hc_barrier", 0, 2, &"any"]],
	&"hall_workshop": [[&"hc_crate_stack", 2, 3, &"wall"], [&"hc_trunk", 1, 2, &"wall"], [&"hc_hammer_tower", 0, 1, &"wall"], [&"hc_debris", 1, 2, &"any"]],
	&"hall_museum": [[&"hc_cage", 1, 2, &"wall"], [&"hc_mirror", 2, 4, &"wall"], [&"hc_crystal_table", 0, 1, &"center"]],
	&"hall_arcade": [[&"hc_candy_machine", 2, 4, &"wall"], [&"hc_prize_shelf", 1, 2, &"wall"], [&"hc_bench", 0, 2, &"center"]],
	&"big_top": [[&"hc_bleachers", 3, 5, &"wall"], [&"hc_ring_barrier", 2, 4, &"center"], [&"hc_cage", 0, 1, &"wall"], [&"hc_debris", 2, 3, &"any"]],
}

## Rôle → conteneurs possibles {kind: poids}.
const CONTAINERS := {
	&"entrance": {&"hc_trash_can": 1.5, &"hc_corpse": 1.0, &"hc_fair_crate": 0.5},
	&"avenue": {&"hc_trash_can": 2.0, &"hc_fair_crate": 1.0, &"hc_corpse": 1.0, &"hc_plush_corpse": 0.6},
	&"alley": {&"hc_trash_can": 1.5, &"hc_fair_crate": 1.0, &"hc_corpse": 0.8},
	&"plaza": {&"hc_trash_can": 1.5, &"hc_corpse": 1.0, &"hc_plush_corpse": 1.0, &"hc_fair_crate": 0.5},
	&"wheel_yard": {&"hc_fair_crate": 1.5, &"hc_corpse": 1.0, &"hc_trash_can": 1.0},
	&"ride_yard": {&"hc_fair_crate": 1.5, &"hc_corpse": 1.0, &"hc_plush_corpse": 0.8, &"hc_trash_can": 0.8},
	&"stand_shooting": {&"hc_stand_counter": 2.0, &"hc_fair_crate": 1.0},
	&"stand_candy": {&"hc_stand_counter": 2.0, &"hc_fair_crate": 1.0},
	&"stand_ducks": {&"hc_stand_counter": 2.0, &"hc_plush_corpse": 0.5},
	&"stand_prizes": {&"hc_stand_counter": 1.0, &"hc_plush_corpse": 2.0, &"hc_fair_crate": 1.0},
	&"stand_fortune": {&"hc_caravan_chest": 1.5, &"hc_stand_counter": 1.0},
	&"stand_popcorn": {&"hc_stand_counter": 2.0, &"hc_trash_can": 1.0},
	&"stand_hammer": {&"hc_stand_counter": 2.0, &"hc_fair_crate": 1.0},
	&"stand_souvenirs": {&"hc_stand_counter": 2.0, &"hc_fair_crate": 1.0, &"hc_plush_corpse": 0.5},
	&"tent_mirrors": {&"hc_corpse": 1.5, &"hc_fair_crate": 1.0},
	&"tent_freaks": {&"hc_fair_crate": 2.0, &"hc_corpse": 1.0, &"hc_plush_corpse": 1.0},
	&"tent_theatre": {&"hc_fair_crate": 1.5, &"hc_caravan_chest": 1.0, &"hc_plush_corpse": 1.0},
	&"caravan_home": {&"hc_caravan_chest": 3.0, &"hc_fair_crate": 1.0},
	&"caravan_storage": {&"hc_fair_crate": 3.0, &"hc_caravan_chest": 1.0},
	&"caravan_director": {&"hc_caravan_chest": 1.0},
	&"ticket_booth": {&"hc_stand_counter": 3.0, &"hc_trash_can": 0.5},
	&"service_yard": {&"hc_fair_crate": 2.0, &"hc_trash_can": 1.0, &"hc_corpse": 1.0},
	&"big_top": {&"hc_fair_crate": 1.0, &"hc_corpse": 1.5, &"hc_plush_corpse": 1.0},
	&"hall_hangar": {&"hc_fair_crate": 3.0, &"hc_corpse": 1.0, &"hc_trash_can": 0.5},
	&"hall_workshop": {&"hc_fair_crate": 3.0, &"hc_caravan_chest": 1.0},
	&"hall_museum": {&"hc_caravan_chest": 1.5, &"hc_corpse": 1.5, &"hc_plush_corpse": 1.0},
	&"hall_arcade": {&"hc_stand_counter": 2.0, &"hc_trash_can": 1.0, &"hc_corpse": 0.5},
}

## Rôle → cachettes {kind: poids}. Rôles absents : pas de cachette.
const HIDING := {
	&"avenue": {&"hc_photo_booth": 2.0, &"hc_dumpster": 1.0},
	&"alley": {&"hc_dumpster": 2.0, &"hc_photo_booth": 1.0},
	&"plaza": {&"hc_photo_booth": 2.0, &"hc_dumpster": 1.0},
	&"wheel_yard": {&"hc_dumpster": 1.0, &"hc_photo_booth": 1.0},
	&"ride_yard": {&"hc_dumpster": 2.0, &"hc_photo_booth": 1.0},
	&"stand_prizes": {&"hc_plush_heap": 3.0},
	&"stand_souvenirs": {&"hc_plush_heap": 2.0},
	&"stand_candy": {&"hc_stand_back": 2.0},
	&"stand_shooting": {&"hc_stand_back": 2.0},
	&"stand_ducks": {&"hc_stand_back": 1.0},
	&"stand_popcorn": {&"hc_stand_back": 2.0},
	&"stand_hammer": {&"hc_stand_back": 1.0},
	&"stand_fortune": {&"hc_stand_back": 1.0},
	&"tent_freaks": {&"hc_plush_heap": 1.0},
	&"tent_theatre": {&"hc_stand_back": 1.0},
	&"caravan_home": {&"hc_caravan_bed": 3.0},
	&"caravan_storage": {&"hc_plush_heap": 2.0},
	&"service_yard": {&"hc_dumpster": 2.0},
	&"entrance": {&"hc_photo_booth": 1.0},
	&"hall_hangar": {&"hc_dumpster": 2.0},
	&"hall_workshop": {&"hc_dumpster": 1.0, &"hc_stand_back": 1.0},
	&"hall_museum": {&"hc_plush_heap": 1.0},
	&"hall_arcade": {&"hc_photo_booth": 3.0},
}

## Rôle → roster d'ennemis prioritaire sur celui du monde (monstres mall_* provisoires) :
## clones dans le palais des glaces, araignées sous les toiles, brutes au tape-fort…
const ROLE_ROSTER := {
	&"tent_mirrors": {&"mall_clone": 3.0, &"mall_night_spider": 1.0},
	&"tent_freaks": {&"mall_night_spider": 2.0, &"mall_brute": 1.5, &"mall_zombie": 1.0},
	&"stand_hammer": {&"mall_brute": 2.0, &"mall_zombie": 1.0},
	&"ride_yard": {&"mall_zombie": 2.0, &"mall_flayer": 1.5, &"mall_night_spider": 1.0, &"mall_security_bot": 0.5},
	&"wheel_yard": {&"mall_zombie": 2.0, &"mall_flayer": 1.5, &"mall_brute": 0.5},
	&"plaza": {&"mall_zombie": 2.0, &"mall_flayer": 2.0, &"mall_clone": 1.0, &"mall_security_bot": 1.0},
	&"hall_museum": {&"mall_clone": 2.0, &"mall_night_spider": 2.0},
	&"hall_hangar": {&"mall_security_bot": 2.0, &"mall_zombie": 2.0, &"mall_brute": 1.0},
}

const BESTIARY_SECTION := "bestiary_mall"
const SUPER_LOOT_CONTAINER := &"hc_caravan_chest"


class Ctx:
	var L: FloorLayout
	var world: WorldData
	var blocked: Dictionary = {}
	var reserved: Dictionary = {}
	var enemy_cells: Dictionary = {}
	var room_of: PackedInt32Array
	var door_adj: Dictionary = {}
	var cand_cache: Dictionary = {}
	var access: Dictionary = {}
	var fur: Fur.Ctx = null          ## test de connexité locale déroulé (Fur.keeps)
	var room_cells: Dictionary = {}  ## room_id → Array[Vector2i] praticables de la salle

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
	# Contexte minimal du furnisher (Fur.keeps n'utilise que tiles / blocked / access).
	c.fur = Fur.Ctx.new()
	c.fur.L = L
	c.fur.blocked = c.blocked
	c.fur.reserved = c.reserved
	c.fur.enemy_cells = c.enemy_cells
	c.fur.room_of = c.room_of
	c.fur.has_container = world.has_container
	c.access = c.fur.access
	for room in L.rooms:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, L.floor_index, room.id, "hc_furnish"])
		_furnish(c, room, rng)
	for room2 in L.rooms:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([seed_value, L.floor_index, room2.id, "hc_containers"])
		_containers(c, room2, rng2)
	_hiding_spots(c, seed_value)
	for room3 in L.rooms:
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = hash([seed_value, L.floor_index, room3.id, "hc_enemies"])
		_enemies(c, room3, rng3, difficulty)


## Cases occupées par l'emprise d'un grand décor dont le point d'appui est `anchor`.
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


static func enemy_count(room: FloorLayout.Room, difficulty: int, roll: float, area: int) -> int:
	var dens := Cfg.by_index("enemy_density", difficulty, [0.020, 0.028, 0.036, 0.046, 0.058])
	var tmul := float(Cfg.get_dict("enemy_room_mult", {}).get(String(room.type), 1.0))
	var omul := Cfg.getf("hc_outdoor_area_mult", 0.5) if room.outdoor else 1.0
	var n := float(area) * dens * tmul * omul + roll
	var cap := Cfg.geti("enemy_max_per_room", 9)
	var bonus := 0
	if room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS:
		bonus = Cfg.geti("guards_min", 2) + int(Cfg.by_index("guards_bonus", difficulty, [0, 0, 1, 1, 2]))
		cap += bonus
	return mini(int(floor(n)) + bonus, cap)


# --- Réservations ---------------------------------------------------------------

static func _index_rooms(c: Ctx) -> void:
	var L := c.L
	c.room_of = Plan.room_grid(L)
	var w := L.size.x
	var lists: Array = []
	lists.resize(L.rooms.size())
	for k in L.rooms.size():
		lists[k] = []
	var tiles := L.tiles
	var ro := c.room_of
	for i in ro.size():
		var rid := ro[i]
		if rid < 0:
			continue
		var t := tiles[i]
		if t == T.FLOOR or t == T.STREET:
			(lists[rid] as Array).append(Vector2i(i % w, i / w))
	for k2 in L.rooms.size():
		c.room_cells[L.rooms[k2].id] = lists[k2]
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
	# Portail d'entrée : passage dégagé.
	for y in range(Plan.GATE_OPEN.position.y - 2, Plan.GATE_OPEN.end.y + 2):
		for x in range(Plan.GATE_OPEN.position.x - 1, Plan.GATE_OPEN.end.x + 1):
			c.reserved[Vector2i(x, y)] = true


static func _passable(c: Ctx, p: Vector2i) -> bool:
	return FloorLayout.is_walkable_tile(c.L.get_tile(p)) and not c.blocked.has(p)


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
	for p: Vector2i in c.room_cells.get(room.id, []):
		if p.x < 1 or p.y < 1 or p.x >= w - 1 or p.y >= L.size.y - 1 or c.reserved.has(p):
			continue
		l_any.append(p)
		var i := p.y * w + p.x
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
			var bl := c.blocked
			if bl.has(p + Vector2i.LEFT) or bl.has(p + Vector2i.RIGHT) or bl.has(p + Vector2i.UP) or bl.has(p + Vector2i.DOWN):
				continue
		if Fur.keeps(c.fur, p):
			c.blocked[p] = true
			cells.remove_at(i)
			return p
	return Vector2i(-1, -1)


static func _try_place_big(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator, kind: StringName) -> Vector2i:
	var cells := _candidates(c, room, &"any")
	var tries := Cfg.geti("place_tries", 24)
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
	return StringName(room.tags[0]) if room.tags.size() > 0 else &"alley"


## Cases praticables réellement dans la salle (le chapiteau ovale déborde de son rectangle).
static func _room_area(c: Ctx, room: FloorLayout.Room) -> int:
	return (c.room_cells.get(room.id, []) as Array).size()


# --- Décors ---------------------------------------------------------------------

static func _furnish(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var entries: Array = PROPS.get(role, [])
	var scale := 1.0
	if room.outdoor:
		scale = maxf(1.0, float(_room_area(c, room)) / Cfg.getf("hc_outdoor_props_area", 330.0))
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
	var weights: Dictionary = CONTAINERS.get(role, {&"hc_fair_crate": 1.0})
	var filtered := {}
	for k: StringName in weights:
		if c.world.has_container(k):
			filtered[k] = weights[k]
	if filtered.is_empty():
		return
	var dens := Cfg.getf("container_density", 0.03)
	var tmul := float(Cfg.get_dict("container_room_mult", {}).get(String(room.type), 1.0))
	var omul := Cfg.getf("hc_outdoor_container_mult", 0.45) if room.outdoor else 1.0
	var n := int(floor(_room_area(c, room) * dens * tmul * omul + rng.randf()))
	var mn := 0
	if room.type == FloorLayout.ROOM_LOOT:
		mn = 1
	if room.type == FloorLayout.ROOM_SUPER_LOOT:
		mn = Cfg.geti("super_loot_chests", 2)
	n = clampi(maxi(n, mn), 0, Cfg.geti("container_max_per_room", 5))
	for i in n:
		var forced := room.type == FloorLayout.ROOM_SUPER_LOOT and i < mn and c.world.has_container(SUPER_LOOT_CONTAINER)
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
	rng.seed = hash([seed_value, L.floor_index, "hc_hiding"])
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
	var per_room := Cfg.getf("hc_hiding_spots_per_room", 0.3)
	var mn := Cfg.geti("hc_hiding_spots_min", 5)
	var mx := Cfg.geti("hc_hiding_spots_max", 10)
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
	if room.type == FloorLayout.ROOM_SPAWN:
		return
	var roster: Dictionary = ROLE_ROSTER.get(_role(room), c.world.get_roster(room.type))
	if room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS:
		roster = c.world.get_roster(room.type)
	if roster.is_empty():
		return
	var roll := rng.randf()
	var n := enemy_count(room, difficulty, roll, _room_area(c, room))
	if n <= 0:
		return
	var safe := Cfg.geti("spawn_safe_radius", 9)
	var sealed := room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS
	var cells: Array[Vector2i] = []
	var extr := {}
	for e in c.L.extraction_cells:
		extr[e] = true
	var sp := c.L.player_spawn
	for p: Vector2i in c.room_cells.get(room.id, []):
		if c.blocked.has(p) or c.enemy_cells.has(p) or extr.has(p):
			continue
		if not sealed and (c.door_adj.has(p) or absi(p.x - sp.x) + absi(p.y - sp.y) < safe):
			continue
		cells.append(p)
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	_group_cells(cells, n, rng)
	var kinds: Array[StringName] = []
	for k in mini(n, cells.size()):
		kinds.append(_weighted(roster, rng))
	if kinds.is_empty():
		return
	if room.type == FloorLayout.ROOM_BOSS and c.world.boss_kind != &"":
		kinds[0] = c.world.boss_kind
	for i2 in mini(n, cells.size()):
		c.enemy_cells[cells[i2]] = true
		c.L.add_spawn(c.L.enemy_spawns, cells[i2], kinds[i2], room.id)


static func _bcfg(key: String, def: Variant) -> Variant:
	return Cfg.cfg().get_value(BESTIARY_SECTION, key, def)


static func _group_cells(cells: Array[Vector2i], n_needed: int, rng: RandomNumberGenerator) -> void:
	if cells.size() < 3 or n_needed < 2 or rng.randf() >= float(_bcfg("group_chance", 0.75)):
		return
	var size := maxi(int(_bcfg("group_size", 4)), 1)
	# Cases déjà mélangées : le regroupement se fait parmi les 160 premières (coût borné dans les
	# grandes cours ouvertes), le reste suit tel quel.
	var tail: Array[Vector2i] = []
	var rest: Array[Vector2i] = []
	for i0 in cells.size():
		if i0 < 160:
			rest.append(cells[i0])
		else:
			tail.append(cells[i0])
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
	cells.append_array(tail)


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
