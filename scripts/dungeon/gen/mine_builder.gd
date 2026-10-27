extends RefCounted
## Sous-sol (-1) : mine en galeries étroites (2-3 cases) reliant des salles de
## minerai. La grille a la même taille que le rez-de-chaussée et l'escalier
## montant est sur la même case que l'escalier descendant de l'entrée de mine.
## Une salle scellée (boss ou super_loot) possible, accessible par une seule
## porte verrouillée.

const Cfg := preload("res://scripts/dungeon/gen/gen_config.gd")
const T := FloorLayout.Tile


class Chamber:
	var rect: Rect2i      ## Emprise murs compris
	var room: FloorLayout.Room


## Construit la mine. `stairs_cells` : cases des escaliers venant de l'étage 0.
## Renvoie le layout (structure seule, sans spawns).
static func build(size: Vector2i, stairs_cells: Array[Vector2i], seed_value: int) -> FloorLayout:
	var attempts := Cfg.geti("mine_attempts", 12)
	for attempt in attempts:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "mine", attempt])
		var L := _try_build(size, stairs_cells, rng, attempt < attempts - 1)
		if L != null:
			return L
	# Inatteignable : la dernière tentative sans salle scellée réussit toujours.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash([seed_value, "mine_fallback"])
	return _try_build(size, stairs_cells, rng2, false)


static func _try_build(size: Vector2i, stairs_cells: Array[Vector2i], rng: RandomNumberGenerator, allow_sealed: bool) -> FloorLayout:
	var L := FloorLayout.new(size)
	L.floor_index = -1
	var chambers: Array[Chamber] = []
	var bounds := Rect2i(1, 1, size.x - 2, size.y - 2)

	# Salle d'arrivée autour de chaque escalier.
	for sc in stairs_cells:
		var w := rng.randi_range(7, 9)
		var h := rng.randi_range(6, 7)
		var r := Rect2i(sc.x - rng.randi_range(2, w - 3), sc.y - 1, w, h)
		if sc.y > size.y / 2:
			r.position.y = sc.y - h + 2
		r = _clamp_rect(r, bounds)
		var ch := Chamber.new()
		ch.rect = r
		chambers.append(ch)

	# Autres salles de minerai.
	var target := Cfg.range_i(rng, "mine_rooms_min", "mine_rooms_max", 6, 9)
	var tries := 0
	while chambers.size() < target and tries < 400:
		tries += 1
		var w2 := rng.randi_range(Cfg.geti("mine_room_w_min", 6), Cfg.geti("mine_room_w_max", 11))
		var h2 := rng.randi_range(Cfg.geti("mine_room_h_min", 5), Cfg.geti("mine_room_h_max", 8))
		var r2 := Rect2i(rng.randi_range(1, size.x - w2 - 1), rng.randi_range(1, size.y - h2 - 1), w2, h2)
		var ok := true
		for c in chambers:
			if c.rect.grow(3).intersects(r2):
				ok = false
				break
		if ok:
			var ch2 := Chamber.new()
			ch2.rect = r2
			chambers.append(ch2)

	for c in chambers:
		L.carve_walled_rect(c.rect, T.FLOOR)

	# Salle scellée : la salle non-escalier la plus éloignée de l'arrivée.
	var sealed := -1
	if allow_sealed and rng.randf() < Cfg.getf("mine_sealed_chance", 0.7) and chambers.size() > stairs_cells.size() + 2:
		var best := -1.0
		for i in range(stairs_cells.size(), chambers.size()):
			var d := Vector2(chambers[i].rect.get_center() - chambers[0].rect.get_center()).length()
			if d > best:
				best = d
				sealed = i

	# Arbre couvrant (Prim) sur les salles non scellées + quelques boucles.
	var tunnels: Array[Rect2i] = []
	var in_tree: Array[int] = [0]
	var edges: Array[Vector2i] = []
	var rest: Array[int] = []
	for i in range(1, chambers.size()):
		if i != sealed:
			rest.append(i)
	while not rest.is_empty():
		var bi := -1
		var bj := -1
		var bd := INF
		for i in in_tree:
			for j in rest:
				var d2 := Vector2(chambers[i].rect.get_center() - chambers[j].rect.get_center()).length_squared()
				if d2 < bd:
					bd = d2
					bi = i
					bj = j
		edges.append(Vector2i(bi, bj))
		in_tree.append(bj)
		rest.erase(bj)
	var loops := Cfg.range_i(rng, "mine_loops_min", "mine_loops_max", 1, 2)
	for n in loops:
		if in_tree.size() < 3:
			break
		var a: int = in_tree[rng.randi_range(0, in_tree.size() - 1)]
		var b: int = in_tree[rng.randi_range(0, in_tree.size() - 1)]
		if a != b and not edges.has(Vector2i(a, b)) and not edges.has(Vector2i(b, a)):
			edges.append(Vector2i(a, b))

	var forbid := chambers[sealed].rect.grow(1) if sealed >= 0 else Rect2i()
	for e in edges:
		var tw := rng.randi_range(Cfg.geti("mine_tunnel_w_min", 2), Cfg.geti("mine_tunnel_w_max", 3))
		var legs := _l_path(chambers[e.x].rect.get_center(), chambers[e.y].rect.get_center(), tw, rng.randf() < 0.5)
		if sealed >= 0 and _hits(legs, forbid):
			legs = _l_path(chambers[e.x].rect.get_center(), chambers[e.y].rect.get_center(), tw, not _first_h(legs))
			if _hits(legs, forbid):
				return null
		for leg in legs:
			var lr := leg.intersection(bounds)
			_carve(L, lr)
			tunnels.append(lr)

	# Raccord de la salle scellée par une porte unique.
	var door_cell := Vector2i(-1, -1)
	var door_vertical := false
	var door_target := -1
	if sealed >= 0:
		var s := chambers[sealed].rect
		var best_j := -1
		var bd2 := INF
		for j in chambers.size():
			if j == sealed:
				continue
			var d3 := Vector2(chambers[j].rect.get_center() - s.get_center()).length_squared()
			if d3 < bd2:
				bd2 = d3
				best_j = j
		door_target = best_j
		var tc := chambers[best_j].rect.get_center()
		var sc2 := s.get_center()
		var dx := tc.x - sc2.x
		var dy := tc.y - sc2.y
		var start: Vector2i
		var horiz_first: bool
		if absi(dx) > absi(dy):
			door_vertical = true
			door_cell = Vector2i(s.end.x - 1 if dx > 0 else s.position.x, sc2.y)
			start = door_cell + (Vector2i.RIGHT if dx > 0 else Vector2i.LEFT)
			horiz_first = true
		else:
			door_cell = Vector2i(sc2.x, s.end.y - 1 if dy > 0 else s.position.y)
			start = door_cell + (Vector2i.DOWN if dy > 0 else Vector2i.UP)
			horiz_first = false
		var legs2 := _l_path(start, tc, 2, horiz_first)
		for leg2 in legs2:
			var lr2 := leg2.intersection(bounds)
			if lr2.intersects(s):
				lr2 = _clip_away(lr2, s)
			_carve(L, lr2)
			tunnels.append(lr2)

	# Réécrit les murs de la salle scellée (aucun tunnel ne doit l'avoir percée).
	if sealed >= 0:
		L.carve_walled_rect(chambers[sealed].rect, T.FLOOR)

	# Salles (rooms) : arrivée, puis les autres, puis tunnels.
	var types := _chamber_types(chambers.size(), stairs_cells.size(), sealed, rng)
	for i in chambers.size():
		var inner := chambers[i].rect.grow(-1)
		var nm := "Puits d'arrivée" if i < stairs_cells.size() else _chamber_name(types[i], rng)
		var room := L.add_room(inner, false, types[i], nm)
		room.tags.append("mine_entry" if i < stairs_cells.size() else "ore_room")
		room.tags.append("mine")
		chambers[i].room = room
	for tr in tunnels:
		if tr.get_area() <= 0:
			continue
		var troom := L.add_room(tr, false, FloorLayout.ROOM_CORRIDOR, "Galerie")
		troom.tags.append("tunnel")
		troom.tags.append("mine")

	if sealed >= 0:
		# Filon scellé : porte verrouillée ; antre du boss : porte simple fermée.
		if types[sealed] == FloorLayout.ROOM_SUPER_LOOT:
			L.add_door(door_cell, door_vertical, FloorLayout.DoorState.LOCKED, chambers[sealed].room.id, chambers[door_target].room.id, &"key_mine_vault")
		else:
			L.add_door(door_cell, door_vertical, FloorLayout.DoorState.CLOSED, chambers[sealed].room.id, chambers[door_target].room.id)

	# Escaliers montants.
	for sc3 in stairs_cells:
		L.set_tile(sc3, T.STAIRS_UP)
		var st := FloorLayout.Stairs.new()
		st.cell = sc3
		st.up = true
		st.target_floor = 0
		st.target_cell = sc3
		L.stairs.append(st)
	L.player_spawn = _arrival_cell(L, stairs_cells[0])

	# Extraction possible dans la salle la plus lointaine non scellée.
	for i in chambers.size():
		if types[i] == FloorLayout.ROOM_EXTRACTION:
			var c := chambers[i].rect.get_center()
			for cc: Vector2i in [c, c + Vector2i.RIGHT, c + Vector2i.DOWN, c + Vector2i.ONE]:
				if L.get_tile(cc) == T.FLOOR:
					L.extraction_cells.append(cc)

	_fence(L)
	# Validation : tout est atteignable (portes verrouillées comprises).
	var reach := L.flood_reachable(L.player_spawn, true)
	for y in size.y:
		for x in size.x:
			if FloorLayout.is_walkable_tile(L.get_tile(Vector2i(x, y))) and not reach.has(Vector2i(x, y)):
				return null
	if sealed >= 0 and types[sealed] == FloorLayout.ROOM_SUPER_LOOT:
		var open_reach := L.flood_reachable(L.player_spawn, false)
		if open_reach.has(chambers[sealed].rect.get_center()):
			return null
	return L


static func _chamber_types(n: int, n_entry: int, sealed: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var out: Array[StringName] = []
	var far := -1
	var has_extraction := rng.randf() < Cfg.getf("mine_extraction_chance", 0.5)
	for i in n:
		if i < n_entry:
			out.append(FloorLayout.ROOM_COMBAT)
		elif i == sealed:
			out.append(FloorLayout.ROOM_BOSS if rng.randf() < Cfg.getf("mine_boss_chance", 0.5) else FloorLayout.ROOM_SUPER_LOOT)
		else:
			var r := rng.randf()
			if r < 0.4:
				out.append(FloorLayout.ROOM_COMBAT)
			elif r < 0.75:
				out.append(FloorLayout.ROOM_LOOT)
			elif r < 0.92:
				out.append(FloorLayout.ROOM_TRAP)
			else:
				out.append(FloorLayout.ROOM_REST)
			far = i
	if has_extraction and far >= 0:
		out[far] = FloorLayout.ROOM_EXTRACTION
	return out


static func _chamber_name(t: StringName, rng: RandomNumberGenerator) -> String:
	match t:
		FloorLayout.ROOM_BOSS: return "Antre du colosse"
		FloorLayout.ROOM_SUPER_LOOT: return "Filon scellé"
		FloorLayout.ROOM_EXTRACTION: return "Puits d'aération"
		FloorLayout.ROOM_LOOT: return ["Salle du filon", "Dépôt de minerai", "Réserve de dynamite"][rng.randi_range(0, 2)]
		FloorLayout.ROOM_REST: return "Abri des mineurs"
		FloorLayout.ROOM_TRAP: return "Galerie effondrée"
	return ["Salle de minerai", "Carrefour des wagonnets", "Excavation"][rng.randi_range(0, 2)]


## Case marchable voisine de l'escalier (point d'arrivée du joueur).
static func _arrival_cell(L: FloorLayout, s: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
		if L.get_tile(s + d) == T.FLOOR or L.get_tile(s + d) == T.STREET:
			return s + d
	return s


static func _first_h(legs: Array[Rect2i]) -> bool:
	return legs.size() > 0 and legs[0].size.x > legs[0].size.y


## Chemin en L de largeur tw (deux rectangles) de a vers b.
static func _l_path(a: Vector2i, b: Vector2i, tw: int, horiz_first: bool) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var corner := Vector2i(b.x, a.y) if horiz_first else Vector2i(a.x, b.y)
	out.append(_seg(a, corner, tw))
	out.append(_seg(corner, b, tw))
	return out


static func _seg(a: Vector2i, b: Vector2i, tw: int) -> Rect2i:
	var x0 := mini(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var x1 := maxi(a.x, b.x)
	var y1 := maxi(a.y, b.y)
	var off := tw / 2
	if a.y == b.y:
		return Rect2i(x0, y0 - off, x1 - x0 + tw - off, tw)
	return Rect2i(x0 - off, y0, tw, y1 - y0 + tw - off)


static func _hits(legs: Array[Rect2i], r: Rect2i) -> bool:
	for l in legs:
		if l.intersects(r):
			return true
	return false


## Retire de lr la partie qui chevauche s (cas d'un segment partant de la porte).
static func _clip_away(lr: Rect2i, s: Rect2i) -> Rect2i:
	if lr.position.x >= s.end.x or lr.end.x <= s.position.x:
		return lr
	if lr.size.x > lr.size.y:
		if lr.position.x < s.position.x:
			return Rect2i(lr.position.x, lr.position.y, s.position.x - lr.position.x, lr.size.y)
		return Rect2i(s.end.x, lr.position.y, lr.end.x - s.end.x, lr.size.y)
	if lr.position.y < s.position.y:
		return Rect2i(lr.position.x, lr.position.y, lr.size.x, s.position.y - lr.position.y)
	return Rect2i(lr.position.x, s.end.y, lr.size.x, lr.end.y - s.end.y)


static func _carve(L: FloorLayout, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var t := L.get_tile(c)
			if t == T.VOID or t == T.WALL:
				L.set_tile(c, T.FLOOR)


static func _clamp_rect(r: Rect2i, b: Rect2i) -> Rect2i:
	var p := r.position
	p.x = clampi(p.x, b.position.x, b.end.x - r.size.x)
	p.y = clampi(p.y, b.position.y, b.end.y - r.size.y)
	return Rect2i(p, r.size)


## Toute case VOID voisine (8) d'une case marchable devient un mur.
static func _fence(L: FloorLayout) -> void:
	var w := L.size.x
	var h := L.size.y
	var src := L.tiles.duplicate()
	for y in h:
		for x in w:
			var i := y * w + x
			if not FloorLayout.is_walkable_tile(src[i]):
				continue
			for dy in range(-1, 2):
				var yy := y + dy
				if yy < 0 or yy >= h:
					continue
				for dx in range(-1, 2):
					var xx := x + dx
					if xx < 0 or xx >= w:
						continue
					var j := yy * w + xx
					if L.tiles[j] == T.VOID:
						L.tiles[j] = T.WALL
	# Le bord de la grille n'est jamais marchable.
	for x2 in L.size.x:
		for y2: int in [0, L.size.y - 1]:
			if FloorLayout.is_walkable_tile(L.get_tile(Vector2i(x2, y2))):
				L.set_tile(Vector2i(x2, y2), T.WALL)
	for y3 in L.size.y:
		for x3: int in [0, L.size.x - 1]:
			if FloorLayout.is_walkable_tile(L.get_tile(Vector2i(x3, y3))):
				L.set_tile(Vector2i(x3, y3), T.WALL)
