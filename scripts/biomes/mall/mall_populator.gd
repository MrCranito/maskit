extends RefCounted
## Peuplement d'un étage du centre commercial : décors (prop_spawns), conteneurs,
## cachettes et ennemis. Même logique que le peuplement Far West (dungeon/gen/populator.gd) :
## - décors, conteneurs et cachettes occupent leur case (bloquants) ; jamais sur ou à côté
##   d'une porte / d'un escalier / du spawn / d'une extraction, jamais en coupant un passage ;
## - grands décors (fontaine, voitures, gondoles) : emprise de plusieurs cases, posés
##   seulement si l'emprise ET son pourtour sont libres (aucune coupure possible) ;
## - ennemis : tirages par salle indépendants de la difficulté (le total croît avec elle) ;
##   roster du monde par type de salle, surchargé par rôle (robots sur les balcons, clones dans
##   les boutiques de vêtements, araignées au cinéma…), regroupés par zones ; 2e rangée du
##   bestiaire surtout en combat et aux étages profonds ; boss garanti dans la salle boss.
## Ameublement choisi d'après Room.tags[0] (rôle posé par mall_layout.gd).

const Cfg := preload("res://scripts/biomes/mall/mall_config.gd")
const Fur := preload("res://scripts/dungeon/gen/furnisher.gd")
const Tpl := preload("res://scripts/biomes/mall/mall_templates.gd")
const PropScript := preload("res://scripts/biomes/mall/mall_prop.gd")
const T := FloorLayout.Tile

## Emprise (cases) des grands décors : [largeur, hauteur]. Le point d'appui (spawn) est
## la case du bas, au centre (colonne (w-1)/2 depuis la gauche).
const BIG := {
	&"fountain": Vector2i(7, 5), &"car_wreck": Vector2i(2, 1), &"store_shelf": Vector2i(2, 1),
	&"cinema_seats": Vector2i(2, 1),
}

## Rôle → [kind, min, max, placement] ; placement : &"wall", &"center", &"any".
const PROPS := {
	&"entrance": [[&"planter", 1, 2, &"wall"], [&"mall_map", 1, 1, &"wall"], [&"bench", 0, 1, &"wall"], [&"debris", 1, 2, &"any"], [&"puddle", 0, 1, &"any"], [&"trash_bin", 0, 1, &"wall"]],
	&"atrium": [[&"palm_pot", 6, 9, &"any"], [&"bench", 6, 9, &"center"], [&"planter", 4, 6, &"center"], [&"food_table", 2, 4, &"center"], [&"display_table", 1, 2, &"center"], [&"puddle", 2, 3, &"any"], [&"debris", 2, 3, &"any"], [&"neon_sign", 1, 2, &"any"]],
	&"gallery": [[&"planter", 5, 8, &"center"], [&"bench", 6, 9, &"center"], [&"trash_bin", 2, 4, &"wall"], [&"neon_sign", 1, 2, &"wall"], [&"puddle", 2, 4, &"any"], [&"debris", 5, 8, &"any"], [&"mall_map", 1, 2, &"wall"], [&"palm_pot", 3, 5, &"wall"], [&"display_table", 3, 5, &"center"], [&"food_table", 3, 5, &"center"]],
	&"balcony": [[&"planter", 0, 2, &"wall"], [&"bench", 0, 1, &"wall"], [&"neon_sign", 0, 1, &"wall"], [&"debris", 0, 1, &"any"], [&"puddle", 0, 1, &"any"]],
	&"food_court": [[&"food_table", 3, 6, &"center"], [&"trash_bin", 1, 2, &"wall"], [&"palm_pot", 0, 1, &"wall"], [&"neon_sign", 1, 1, &"wall"]],
	&"shop_clothes": [[&"clothes_rack", 2, 4, &"any"], [&"mannequin", 1, 3, &"wall"], [&"checkout", 0, 1, &"wall"]],
	&"shop_electronics": [[&"tv_wall", 1, 2, &"wall"], [&"store_shelf", 1, 1, &"wall"], [&"checkout", 0, 1, &"wall"]],
	&"shop_pharmacy": [[&"medicine_shelf", 2, 3, &"wall"], [&"checkout", 1, 1, &"wall"]],
	&"shop_toys": [[&"toy_pile", 1, 3, &"any"], [&"store_shelf", 1, 1, &"wall"]],
	&"shop_shoes": [[&"store_shelf", 1, 2, &"wall"], [&"bench", 1, 1, &"center"], [&"mannequin", 0, 1, &"wall"]],
	&"shop_perfume": [[&"medicine_shelf", 1, 2, &"wall"], [&"mannequin", 0, 1, &"wall"], [&"checkout", 0, 1, &"wall"]],
	&"shop_books": [[&"store_shelf", 2, 3, &"wall"], [&"bench", 0, 1, &"center"]],
	&"shop_sports": [[&"clothes_rack", 1, 2, &"any"], [&"store_shelf", 1, 1, &"wall"], [&"mannequin", 0, 1, &"wall"]],
	&"shop_cafe": [[&"food_table", 1, 3, &"center"], [&"checkout", 1, 1, &"wall"], [&"palm_pot", 0, 1, &"wall"]],
	&"shop_jewelry": [[&"checkout", 1, 1, &"wall"], [&"mannequin", 0, 1, &"wall"], [&"palm_pot", 0, 1, &"wall"]],
	&"supermarket": [[&"store_shelf", 4, 8, &"center"], [&"checkout", 2, 3, &"wall"], [&"debris", 0, 2, &"any"]],
	&"stockroom": [[&"store_shelf", 1, 1, &"wall"], [&"debris", 0, 1, &"any"]],
	&"cinema_lobby": [[&"popcorn_machine", 1, 1, &"wall"], [&"neon_sign", 1, 1, &"wall"], [&"mall_map", 0, 1, &"wall"], [&"planter", 0, 1, &"wall"]],
	&"cinema_hall": [[&"cinema_seats", 3, 6, &"center"]],
	&"arcade": [[&"arcade_cabinet", 3, 6, &"wall"], [&"neon_sign", 0, 1, &"wall"]],
	&"office": [[&"desk", 1, 2, &"any"], [&"filing_cabinet", 1, 2, &"wall"], [&"palm_pot", 0, 1, &"wall"]],
	&"service": [[&"debris", 0, 2, &"any"], [&"trash_bin", 0, 1, &"wall"], [&"filing_cabinet", 0, 1, &"wall"]],
	&"office_corridor": [[&"palm_pot", 0, 1, &"wall"], [&"filing_cabinet", 0, 1, &"wall"]],
	&"director": [[&"desk", 1, 1, &"center"], [&"filing_cabinet", 1, 2, &"wall"], [&"palm_pot", 1, 1, &"wall"]],
	&"roof": [[&"ac_unit", 6, 9, &"any"], [&"roof_vent", 4, 7, &"any"], [&"puddle", 4, 7, &"any"], [&"debris", 2, 3, &"any"], [&"planter", 2, 4, &"any"], [&"palm_pot", 1, 2, &"any"], [&"generator", 0, 1, &"wall"]],
	&"helipad": [[&"roof_vent", 0, 1, &"wall"]],
	&"parking": [[&"car_wreck", 4, 7, &"center"], [&"traffic_cone", 2, 5, &"any"], [&"puddle", 2, 4, &"any"], [&"debris", 1, 3, &"any"], [&"trash_bin", 0, 2, &"wall"]],
	&"ramp": [[&"traffic_cone", 1, 3, &"any"]],
	&"technical": [[&"generator", 1, 1, &"wall"], [&"filing_cabinet", 0, 1, &"wall"], [&"debris", 0, 1, &"any"]],
	&"security": [[&"desk", 1, 1, &"wall"], [&"tv_wall", 1, 1, &"wall"], [&"filing_cabinet", 0, 1, &"wall"]],
	&"trash": [[&"trash_bin", 2, 3, &"wall"], [&"debris", 1, 2, &"any"]],
}

## Rôle → conteneurs possibles {kind: poids}.
const CONTAINERS := {
	&"entrance": {&"mall_vending": 1.0, &"mall_corpse": 1.0, &"mall_stock_box": 0.5},
	&"atrium": {&"mall_cart": 1.0, &"mall_corpse": 1.0, &"mall_vending": 0.5},
	&"gallery": {&"mall_vending": 2.0, &"mall_cart": 1.5, &"mall_corpse": 1.0, &"mall_stock_box": 1.0},
	&"balcony": {&"mall_vending": 1.0, &"mall_corpse": 1.0, &"mall_stock_box": 0.5},
	&"food_court": {&"mall_register": 1.0, &"mall_vending": 2.0, &"mall_corpse": 1.0},
	&"shop_clothes": {&"mall_register": 2.0, &"mall_display": 1.0, &"mall_stock_box": 1.0, &"mall_corpse": 0.5},
	&"shop_electronics": {&"mall_display": 3.0, &"mall_register": 1.0, &"mall_stock_box": 1.0},
	&"shop_pharmacy": {&"mall_register": 1.5, &"mall_display": 2.0, &"mall_stock_box": 1.0},
	&"shop_toys": {&"mall_register": 1.0, &"mall_stock_box": 2.0, &"mall_display": 1.0},
	&"shop_shoes": {&"mall_register": 1.0, &"mall_stock_box": 2.0},
	&"shop_perfume": {&"mall_display": 2.0, &"mall_register": 1.0},
	&"shop_books": {&"mall_register": 1.0, &"mall_stock_box": 2.0},
	&"shop_sports": {&"mall_register": 1.0, &"mall_stock_box": 1.0, &"mall_display": 1.0},
	&"shop_cafe": {&"mall_register": 2.0, &"mall_vending": 1.0, &"mall_corpse": 0.5},
	&"shop_jewelry": {&"mall_display": 2.0, &"mall_jewel_safe": 1.0},
	&"supermarket": {&"mall_cart": 3.0, &"mall_register": 2.0, &"mall_stock_box": 2.0, &"mall_corpse": 0.5},
	&"stockroom": {&"mall_stock_box": 3.0, &"mall_cart": 1.0},
	&"cinema_lobby": {&"mall_register": 1.0, &"mall_vending": 2.0, &"mall_corpse": 1.0},
	&"cinema_hall": {&"mall_corpse": 1.0, &"mall_stock_box": 0.5},
	&"arcade": {&"mall_vending": 2.0, &"mall_register": 1.0},
	&"office": {&"mall_stock_box": 1.5, &"mall_corpse": 1.0, &"mall_display": 0.5},
	&"service": {&"mall_stock_box": 2.0, &"mall_corpse": 0.5},
	&"office_corridor": {&"mall_vending": 1.0},
	&"director": {&"mall_jewel_safe": 1.0, &"mall_stock_box": 1.0},
	&"vault": {&"mall_jewel_safe": 1.0},
	&"roof": {&"mall_stock_box": 1.0, &"mall_corpse": 1.0},
	&"helipad": {&"mall_stock_box": 1.0},
	&"parking": {&"mall_cart": 2.0, &"mall_corpse": 1.0, &"mall_stock_box": 1.0},
	&"ramp": {&"mall_cart": 1.0},
	&"technical": {&"mall_stock_box": 2.0, &"mall_corpse": 1.0},
	&"security": {&"mall_stock_box": 1.0, &"mall_corpse": 1.0},
	&"trash": {&"mall_stock_box": 2.0, &"mall_cart": 1.0, &"mall_corpse": 1.0},
}

## Rôle → cachettes {kind: poids}. Rôles absents : pas de cachette.
const HIDING := {
	&"shop_clothes": {&"mall_fitting_room": 3.0},
	&"shop_sports": {&"mall_fitting_room": 2.0, &"mall_shelving": 1.0},
	&"supermarket": {&"mall_shelving": 3.0, &"mall_counter": 1.0},
	&"stockroom": {&"mall_shelving": 2.0},
	&"shop_books": {&"mall_shelving": 2.0},
	&"shop_pharmacy": {&"mall_shelving": 1.0, &"mall_counter": 1.0},
	&"shop_toys": {&"mall_shelving": 1.0},
	&"shop_cafe": {&"mall_counter": 2.0},
	&"shop_electronics": {&"mall_counter": 1.0},
	&"food_court": {&"mall_counter": 2.0},
	&"cinema_lobby": {&"mall_counter": 1.0},
	&"entrance": {&"mall_counter": 1.0},
	&"gallery": {&"mall_counter": 0.5},
	&"office": {&"mall_counter": 1.0},
	&"security": {&"mall_counter": 1.0},
	&"parking": {&"mall_car": 3.0},
	&"ramp": {&"mall_car": 1.0},
	&"technical": {&"mall_shelving": 1.0},
	&"roof": {&"mall_shelving": 1.0},
	&"office_corridor": {&"mall_counter": 1.0},
	&"cinema_hall": {&"mall_counter": 0.5},
	&"arcade": {&"mall_counter": 1.0},
}

## Rôle → roster d'ennemis prioritaire sur celui du monde (même format que enemy_roster) :
## robots sur les balcons et au poste de sécurité, clones parmi les cabines d'essayage, araignées
## dans le noir du cinéma, zombies au parking…
const ROLE_ROSTER := {
	&"balcony": {&"mall_security_bot": 2.0, &"mall_flayer": 2.0, &"mall_zombie": 1.0},
	&"shop_clothes": {&"mall_clone": 3.0, &"mall_zombie": 1.0, &"mall_flayer": 0.5},
	&"cinema_hall": {&"mall_night_spider": 3.0, &"mall_clone": 1.5, &"mall_zombie": 1.0},
	&"arcade": {&"mall_clone": 2.0, &"mall_night_spider": 1.0, &"mall_zombie": 1.0},
	&"security": {&"mall_security_bot": 3.0, &"mall_zombie": 0.5},
	&"parking": {&"mall_zombie": 3.0, &"mall_brute": 0.8, &"mall_night_spider": 1.0, &"mall_flayer": 1.0},
	&"roof": {&"mall_security_bot": 2.0, &"mall_flayer": 1.5, &"mall_brute": 0.8},
	&"helipad": {&"mall_security_bot": 2.0, &"mall_brute": 1.0},
}

## Réglages du bestiaire (section [bestiary_mall] de balance.cfg, lue directement : générateur
## utilisable sans autoload).
const BESTIARY_SECTION := "bestiary_mall"


## Conteneur imposé dans les salles super_loot (coffres de bijouterie).
const SUPER_LOOT_CONTAINER := &"mall_jewel_safe"


class Ctx:
	var L: FloorLayout
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
	c.world = world
	_reserve(c)
	_index_rooms(c)
	_centerpieces(c)
	# Salles intérieures à gabarit (boutiques, réserves, bureaux…) : aménagement ordonné ; les
	# espaces ouverts (galeries, parking, toit) gardent l'ameublement par règles ci-dessous.
	c.fur = Fur.make_ctx(L, c.blocked, c.reserved, c.enemy_cells, c.room_of, furniture_defs(), world.has_container)
	Fur.prepare(c.fur, Tpl.templates(), seed_value, "mall")
	for room in L.rooms:
		if Fur.templated(c.fur, room):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, L.floor_index, room.id, "mall_furnish"])
		_furnish(c, room, rng)
	for room2 in L.rooms:
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = hash([seed_value, L.floor_index, room2.id, "mall_containers"])
		_containers(c, room2, rng2)
	_hiding_spots(c, seed_value)
	for room3 in L.rooms:
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = hash([seed_value, L.floor_index, room3.id, "mall_enemies"])
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


static func enemy_count(room: FloorLayout.Room, floor_index: int, difficulty: int, roll: float) -> int:
	var dens := Cfg.by_index("enemy_density", difficulty, [0.020, 0.028, 0.036, 0.046, 0.058])
	var tmul := float(Cfg.get_dict("enemy_room_mult", {}).get(String(room.type), 1.0))
	var fmul := float(Cfg.get_dict("mall_enemy_floor_mult", {}).get(str(floor_index), 1.0))
	var n := float(room.rect.get_area()) * dens * tmul * fmul + roll
	var cap := Cfg.geti("enemy_max_per_room", 9)
	var bonus := 0
	if room.type == FloorLayout.ROOM_SUPER_LOOT:
		bonus = Cfg.geti("guards_min", 2) + int(Cfg.by_index("guards_bonus", difficulty, [0, 0, 1, 1, 2]))
		cap += bonus
	elif room.type == FloorLayout.ROOM_BOSS:
		# Gardes de l'arène (escorte d'élite comprise), réglés à part des salles au trésor.
		bonus = Cfg.geti("boss_guards_min", Cfg.geti("guards_min", 2)) \
				+ int(Cfg.by_index("boss_guards_bonus", difficulty, Cfg.get_arr("guards_bonus", [0, 0, 1, 1, 2])))
		cap += bonus
	return mini(int(floor(n)) + bonus, cap)


## Cases occupées par un spawn de décor : emprise du gabarit (Spawn.size) ou grand décor (BIG).
static func spawn_footprint(s: FloorLayout.Spawn) -> Array[Vector2i]:
	if s.size != Vector2i.ONE:
		return FloorLayout.spawn_cells(s)
	return footprint(s.kind, s.cell)


static var _defs_cache: Dictionary = {}


## Définitions de mobilier (collision de mall_prop.gd + compléments du gabarit), décors de l'atlas.
static func furniture_defs() -> Dictionary:
	if not _defs_cache.is_empty():
		return _defs_cache
	for k: StringName in PropScript.DEFS:
		if not PropScript.has_piece("prop_" + String(k)):
			continue
		var d: Dictionary = (PropScript.DEFS[k] as Dictionary).duplicate()
		d.merge(Tpl.META.get(k, {}), true)
		_defs_cache[k] = d
	return _defs_cache


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
	# Les portes ont un dégagement de 2 cases devant/derrière (rideaux, couloirs étroits).
	for d2 in L.doors:
		var axis := Vector2i.RIGHT if d2.vertical else Vector2i.DOWN
		c.reserved[d2.cell + axis * 2] = true
		c.reserved[d2.cell - axis * 2] = true


static func _passable(c: Ctx, p: Vector2i) -> bool:
	return FloorLayout.is_walkable_tile(c.L.get_tile(p)) and not c.blocked.has(p)


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


## Grand décor : emprise + pourtour libres, praticables, non réservés et dans la salle.
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
	return StringName(room.tags[0]) if room.tags.size() > 0 else &"gallery"


# --- Décors ---------------------------------------------------------------------

## Pièces maîtresses posées avant le reste : la fontaine au centre de l'atrium.
static func _centerpieces(c: Ctx) -> void:
	for room in c.L.rooms:
		if _role(room) != &"atrium" or not c.world.has_prop(&"fountain"):
			continue
		var ctr := room.rect.get_center()
		for off: Vector2i in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 0), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(0, 3)]:
			var p := ctr + off
			if _big_fits(c, room, &"fountain", p):
				for q in footprint(&"fountain", p):
					c.blocked[q] = true
				c.L.add_spawn(c.L.prop_spawns, p, &"fountain", room.id)
				break


static func _furnish(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> void:
	var role := _role(room)
	var entries: Array = PROPS.get(role, [])
	var scale := 1.0
	if room.outdoor and (role == &"gallery" or role == &"balcony" or role == &"parking" or role == &"roof"):
		scale = maxf(1.0, float(maxi(room.rect.size.x, room.rect.size.y)) / 24.0)
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
	var weights: Dictionary = CONTAINERS.get(role, {&"mall_stock_box": 1.0})
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
		if room.type == FloorLayout.ROOM_SUPER_LOOT and c.world.has_container(SUPER_LOOT_CONTAINER):
			for k in mn:
				firsts.append(SUPER_LOOT_CONTAINER)
		Fur.loot(c.fur, room, c.L.container_spawns, n, func() -> StringName: return _weighted(filtered, rng), firsts, "loot")
		return
	for i in n:
		var forced := room.type == FloorLayout.ROOM_SUPER_LOOT and i < mn and c.world.has_container(SUPER_LOOT_CONTAINER)
		var kind: StringName = SUPER_LOOT_CONTAINER if forced else _weighted(filtered, rng)
		var p := _place_blocking(c, room, rng, &"wall")
		if p.x < 0:
			break
		c.fur.access[p] = true
		c.L.add_spawn(c.L.container_spawns, p, kind, room.id)


# --- Cachettes ---------------------------------------------------------------------

static func _hiding_spots(c: Ctx, seed_value: int) -> void:
	var L := c.L
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, L.floor_index, "mall_hiding"])
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
	var per_room := Cfg.getf("mall_hiding_spots_per_room", 0.3)
	var mn := Cfg.geti("mall_hiding_spots_min", 4)
	var mx := Cfg.geti("mall_hiding_spots_max", 9)
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
	var n := enemy_count(room, c.L.floor_index, difficulty, roll)
	if n <= 0:
		return
	var safe := Cfg.geti("spawn_safe_radius", 9)
	var stairs_safe := Cfg.geti("mall_stairs_safe_radius", 6)
	var sealed := room.type == FloorLayout.ROOM_SUPER_LOOT or room.type == FloorLayout.ROOM_BOSS
	var cells: Array[Vector2i] = []
	var r := room.rect
	# Même filtre case par case qu'avant, sur les tableaux bruts (hors grille = VOID, ignoré).
	var L := c.L
	var w := L.size.x
	var tiles := L.tiles
	var extr := {}
	for e in L.extraction_cells:
		extr[e] = true
	var spawn_check := not sealed and L.floor_index == 0
	var sp := L.player_spawn
	for y in range(maxi(r.position.y, 0), mini(r.end.y, L.size.y)):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, w)):
			var i := y * w + x
			var t := tiles[i]
			if t != T.FLOOR and t != T.STREET:
				continue
			if c.room_of[i] != room.id:
				continue
			var p := Vector2i(x, y)
			if c.blocked.has(p) or c.enemy_cells.has(p) or extr.has(p):
				continue
			if not sealed:
				if c.door_adj.has(p):
					continue
				if spawn_check and absi(x - sp.x) + absi(y - sp.y) < safe:
					continue
				if _near_stairs(c, p, stairs_safe):
					continue
			cells.append(p)
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp
	_group_cells(cells, n, rng)
	roster = _depth_roster(roster, room, c.L.floor_index)
	var kinds: Array[StringName] = []
	for k in Cfg.geti("enemy_max_per_room", 9) + 8:
		kinds.append(_weighted(roster, rng))
	if room.type == FloorLayout.ROOM_BOSS and c.world.boss_kind != &"":
		kinds[0] = c.world.boss_kind
	for i2 in mini(n, cells.size()):
		c.enemy_cells[cells[i2]] = true
		c.L.add_spawn(c.L.enemy_spawns, cells[i2], kinds[i2], room.id)


static func _bcfg(key: String, def: Variant) -> Variant:
	return Cfg.cfg().get_value(BESTIARY_SECTION, key, def)


## « Se regroupent par zones » : avec une probabilité `group_chance`, les `n_needed` premières cases
## d'apparition (déjà mélangées) sont réordonnées en groupes de `group_size` cases proches d'une
## ancre ; chaque groupe démarre autour d'une nouvelle ancre tirée parmi les cases restantes.
static func _group_cells(cells: Array[Vector2i], n_needed: int, rng: RandomNumberGenerator) -> void:
	if cells.size() < 3 or n_needed < 2 or rng.randf() >= float(_bcfg("group_chance", 0.75)):
		return
	var size := maxi(int(_bcfg("group_size", 4)), 1)
	var rest: Array[Vector2i] = cells.duplicate()
	cells.clear()
	var anchor: Vector2i = rest[0]
	while cells.size() < n_needed and not rest.is_empty():
		# Les `size` cases les plus proches de l'ancre (sélection partielle, sans tri complet).
		var take := mini(size, mini(rest.size(), n_needed - cells.size()))
		for _k in take:
			var best := 0
			var best_d := 1 << 30
			for i in rest.size():
				var c := rest[i]
				var dd := absi(c.x - anchor.x) + absi(c.y - anchor.y)
				if dd < best_d:
					best_d = dd
					best = i
			cells.append(rest[best])
			rest.remove_at(best)
		# Prochaine ancre : une case restante au hasard (déjà mélangées) → groupes séparés.
		if not rest.is_empty():
			anchor = rest[rest.size() - 1]
	cells.append_array(rest)


## 2e rangée de la planche (plus durs) : surtout en combat / extraction et aux étages profonds ;
## ailleurs au rez-de-chaussée, leurs poids sont multipliés par `row2_shallow_mult`.
static func _depth_roster(roster: Dictionary, room: FloorLayout.Room, floor_index: int) -> Dictionary:
	if floor_index != 0:
		return roster
	if room.type in [FloorLayout.ROOM_COMBAT, FloorLayout.ROOM_EXTRACTION, FloorLayout.ROOM_SUPER_LOOT, FloorLayout.ROOM_BOSS]:
		return roster
	var row2: Array = _bcfg("row2_kinds", ["mall_clone", "mall_brute", "mall_night_spider"])
	var mult := float(_bcfg("row2_shallow_mult", 0.3))
	var out := {}
	for k: Variant in roster:
		out[k] = float(roster[k]) * (mult if row2.has(String(k)) else 1.0)
	return out


## Case à moins de `r` (Manhattan) d'une arrivée d'escalier (pas d'ennemi au débarquement).
static func _near_stairs(c: Ctx, p: Vector2i, r: int) -> bool:
	for s in c.L.stairs:
		if absi(p.x - s.cell.x) + absi(p.y - s.cell.y) < r:
			return true
	return false


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
