extends RefCounted
## Structure d'un étage de la station sous-marine « Abysse Nérée ».
##
## Modules (salles) = rectangles d'acier murés posés sur une grille de « baies »
## (colonnes x rangées). Couloirs = tubes vitrés de 3 cases de large (droits ou en Z)
## reliant deux modules voisins, avec un sas rond (porte) à chaque extrémité.
## Arbre couvrant aléatoire + quelques boucles. Certains modules ont une annexe
## (cloison + porte) : cabine, salle des échantillons verrouillée (super_loot)…
## Escaliers (ascenseurs / échelles) : sur la rangée haute de l'intérieur d'un
## module (contre le mur nord), à la MÊME case sur l'étage cible ; le module
## d'arrivée de l'étage inférieur est forcé pour contenir cette case.
## Pur données (FloorLayout), déterministe (RandomNumberGenerator seedé).

const Cfg := preload("res://scripts/biomes/underwater/uw_config.gd")
const T := FloorLayout.Tile

const SIDE_N := 0
const SIDE_S := 1
const SIDE_W := 2
const SIDE_E := 3

## Clefs des salles super_loot (objets data/items/<id>.tres).
const KEY_LAB := &"key_uw_lab"
const KEY_TRENCH := &"key_uw_trench"

## Noms de salles par rôle (Room.tags[0]).
const NAMES := {
	&"moon_pool": ["Bassin d'amarrage"],
	&"pod_bay": ["Baie des capsules", "Sas de remontée"],
	&"quarters": ["Quartiers de l'équipage", "Dortoir des plongeurs"],
	&"cabin": ["Cabine", "Cabine du second", "Cabine du médecin"],
	&"mess": ["Mess", "Cantine"],
	&"infirmary": ["Infirmerie"],
	&"storage": ["Soute", "Réserve de matériel"],
	&"comms": ["Salle radio", "Poste de commandement"],
	&"workshop": ["Atelier", "Atelier des scaphandres"],
	&"aquarium": ["Galerie des aquariums", "Bassins d'observation"],
	&"bio_lab": ["Laboratoire de biologie", "Laboratoire marin"],
	&"sample_vault": ["Salle des échantillons"],
	&"hydroponics": ["Serre d'algues"],
	&"server": ["Salle des serveurs"],
	&"office": ["Bureau du directeur", "Bureau des recherches"],
	&"dissection": ["Salle de dissection"],
	&"lab_storage": ["Réserve du laboratoire"],
	&"decon": ["Sas de décontamination"],
	&"pump_room": ["Salle des pompes"],
	&"trench_vault": ["Chambre forte de la fosse"],
	&"engine": ["Salle des machines inondée"],
	&"ballast": ["Réservoirs de ballast"],
	&"maintenance": ["Atelier de maintenance"],
	&"flooded_hall": ["Coursive inondée", "Puits inondé"],
	&"boss_lair": ["Antre du Gardien des Profondeurs"],
	&"escape_pod": ["Capsule de secours"],
}

## Rôles ordinaires par étage (tirés sans remise, puis on recommence la liste).
const POOLS := {
	0: [&"quarters", &"mess", &"infirmary", &"storage", &"comms", &"workshop", &"quarters", &"storage", &"mess"],
	-1: [&"aquarium", &"hydroponics", &"server", &"office", &"dissection", &"lab_storage", &"decon", &"aquarium", &"bio_lab"],
	-2: [&"pump_room", &"engine", &"ballast", &"maintenance", &"flooded_hall", &"engine", &"ballast", &"pump_room"],
}
## Rôles dont le sol est inondé (eau peu profonde, purement visuelle).
const FLOODED_ROLES: Array[StringName] = [&"engine", &"flooded_hall", &"boss_lair", &"ballast"]


class Module:
	var idx: int = -1
	var slot: Vector2i
	var rect: Rect2i                         ## Emprise murs compris
	var role: StringName = &""
	var type: StringName = &"combat"
	var name: String = ""
	var forced: bool = false                 ## Imposé par un escalier venant d'un autre étage
	var stairs: Array[Vector2i] = []         ## Cases d'escalier dans ce module
	var door_sides: Dictionary = {}          ## côté → case de porte de couloir
	var forbid: Dictionary = {}              ## Cases de mur interdites aux portes
	var annex_role: StringName = &""
	var annex_type: StringName = &""
	var annex_key: StringName = &""
	var annex_inner: Rect2i = Rect2i()       ## Intérieur de l'annexe
	var annex_door: Vector2i = Vector2i(-1, -1)
	var annex_door_vertical: bool = false
	var main_inner: Rect2i = Rect2i()        ## Intérieur hors annexe
	var room_id: int = -1
	var annex_room_id: int = -1
	var building_id: int = -1

	func inner() -> Rect2i:
		return rect.grow(-1)

	func center() -> Vector2i:
		return rect.get_center()


class Corridor:
	var a: int = -1
	var b: int = -1
	var segs: Array[Rect2i] = []
	var door_a: Vector2i
	var door_b: Vector2i
	var vertical_doors: bool = false         ## Portes dans des murs verticaux (couloir horizontal)
	var room_ids: PackedInt32Array = PackedInt32Array()


## Résultat : layout + cases bloquées en plus (bassin d'amarrage…) + escaliers vers
## l'étage inférieur (cases).
class Result:
	var layout: FloorLayout
	var blocked: Array[Vector2i] = []
	var down_stairs: Array[Vector2i] = []


## Construit l'étage `floor_index`. `up_stairs` : cases des escaliers venant de
## l'étage supérieur (vides pour l'étage 0). `has_lower` : un étage existe dessous.
static func build(seed_value: int, floor_index: int, up_stairs: Array[Vector2i], has_lower: bool) -> Result:
	var attempts := Cfg.geti("station_attempts", 24)
	for attempt in attempts:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "uw_station", floor_index, attempt])
		var res := _try_build(rng, floor_index, up_stairs, has_lower, attempt < attempts - 1)
		if res != null:
			return res
	# Dernier recours : sans annexe ni boucle (réussit toujours par construction).
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = hash([seed_value, "uw_station_fallback", floor_index])
	var res2 := _try_build(rng2, floor_index, up_stairs, has_lower, false)
	if res2 == null:
		push_error("UnderwaterGenerator: échec de génération de l'étage %d" % floor_index)
	return res2


static func grid_cols() -> int:
	return Cfg.geti("grid_cols", 4)


static func grid_rows() -> int:
	return Cfg.geti("grid_rows", 3)


static func slot_size() -> Vector2i:
	return Vector2i(Cfg.geti("slot_w", 18), Cfg.geti("slot_h", 15))


static func margin() -> int:
	return Cfg.geti("map_margin", 2)


static func map_size() -> Vector2i:
	var s := slot_size()
	var m := margin()
	return Vector2i(m * 2 + s.x * grid_cols(), m * 2 + s.y * grid_rows())


## Emprise autorisée d'un module dans sa baie (marge de 2 cases de chaque côté).
static func slot_bounds(slot: Vector2i) -> Rect2i:
	var s := slot_size()
	var m := margin()
	return Rect2i(m + slot.x * s.x + 2, m + slot.y * s.y + 2, s.x - 4, s.y - 4)


static func slot_of_cell(c: Vector2i) -> Vector2i:
	var s := slot_size()
	var m := margin()
	return Vector2i(clampi((c.x - m) / s.x, 0, grid_cols() - 1), clampi((c.y - m) / s.y, 0, grid_rows() - 1))


# --- Construction ----------------------------------------------------------------

static func _try_build(rng: RandomNumberGenerator, floor_index: int, up_stairs: Array[Vector2i], has_lower: bool, allow_extras: bool) -> Result:
	var size := map_size()
	var L := FloorLayout.new(size)
	L.floor_index = floor_index
	var cols := grid_cols()
	var rows := grid_rows()

	# 1) Baies occupées : baies imposées par les escaliers + tirage, ensemble connexe.
	var forced_slots := {}
	for s in up_stairs:
		forced_slots[slot_of_cell(s)] = true
	var want := clampi(Cfg.range_i(rng, "modules_min", "modules_max", 8, 11), forced_slots.size() + 3, cols * rows)
	var occupied := _pick_slots(rng, cols, rows, want, forced_slots)
	if occupied.is_empty():
		return null

	# 2) Rectangles des modules.
	var modules: Array[Module] = []
	var by_slot := {}
	var wmin := Cfg.geti("module_w_min", 9)
	var wmax := Cfg.geti("module_w_max", 14)
	var hmin := Cfg.geti("module_h_min", 8)
	var hmax := Cfg.geti("module_h_max", 11)
	for slot: Vector2i in occupied:
		var m := Module.new()
		m.idx = modules.size()
		m.slot = slot
		var b := slot_bounds(slot)
		var stairs_here: Array[Vector2i] = []
		for s2 in up_stairs:
			if slot_of_cell(s2) == slot:
				stairs_here.append(s2)
		if not stairs_here.is_empty():
			m.forced = true
			var r := _forced_rect(rng, b, stairs_here, wmin, wmax, hmin, hmax)
			if r.size.x <= 0:
				return null
			m.rect = r
			for s3 in stairs_here:
				m.stairs.append(s3)
		else:
			var w := rng.randi_range(wmin, mini(wmax, b.size.x))
			var h := rng.randi_range(hmin, mini(hmax, b.size.y))
			m.rect = Rect2i(b.position.x + rng.randi_range(0, b.size.x - w), b.position.y + rng.randi_range(0, b.size.y - h), w, h)
		modules.append(m)
		by_slot[slot] = m.idx

	# 3) Arbre couvrant (Prim aléatoire sur la grille des baies).
	var edges: Array[Vector2i] = []
	var in_tree := {0: true}
	var degree := PackedInt32Array()
	degree.resize(modules.size())
	while in_tree.size() < modules.size():
		var cand: Array[Vector2i] = []
		for i: int in in_tree:
			for j: int in _slot_neighbors(modules[i].slot, by_slot):
				if not in_tree.has(j):
					cand.append(Vector2i(i, j))
		if cand.is_empty():
			return null
		var e := cand[rng.randi_range(0, cand.size() - 1)]
		edges.append(e)
		in_tree[e.y] = true
		degree[e.x] += 1
		degree[e.y] += 1

	# 4) Rôles spéciaux.
	var arrival := -1
	for m2 in modules:
		if m2.forced:
			arrival = m2.idx
			break
	var spawn_idx := -1
	if floor_index == 0:
		# Bassin d'amarrage : module le plus à l'ouest (le sous-marin arrive du large).
		var best := 1 << 30
		for m3 in modules:
			var score := m3.center().x * 4 + absi(m3.center().y - size.y / 2)
			if score < best and m3.rect.size.x >= 9 and m3.rect.size.y >= 8:
				best = score
				spawn_idx = m3.idx
		if spawn_idx < 0:
			return null
		modules[spawn_idx].role = &"moon_pool"
		modules[spawn_idx].type = FloorLayout.ROOM_SPAWN
		arrival = spawn_idx
	var dist := _bfs(modules, edges, arrival)
	var boss_idx := -1
	if floor_index <= -2 and allow_extras:
		# Antre du boss : feuille de l'arbre la plus éloignée de l'arrivée.
		var bd := -1
		for m4 in modules:
			if m4.forced or m4.role != &"" or degree[m4.idx] != 1:
				continue
			if dist[m4.idx] > bd:
				bd = dist[m4.idx]
				boss_idx = m4.idx
		if boss_idx >= 0:
			modules[boss_idx].role = &"boss_lair"
			modules[boss_idx].type = FloorLayout.ROOM_BOSS
	# Extraction : étage 0 toujours (le plus loin du bassin), étage -2 parfois.
	var extraction_idx := -1
	if floor_index == 0 or (floor_index <= -2 and rng.randf() < Cfg.getf("deep_extraction_chance", 0.6)):
		var bx := -1.0
		var sp_c := modules[arrival].center() if arrival >= 0 else Vector2i(0, size.y / 2)
		for m5 in modules:
			if m5.forced or m5.role != &"":
				continue
			var d := float(absi(m5.center().x - sp_c.x) + absi(m5.center().y - sp_c.y)) + float(dist[m5.idx]) * 2.0
			if d > bx:
				bx = d
				extraction_idx = m5.idx
		if extraction_idx >= 0:
			modules[extraction_idx].role = &"pod_bay" if floor_index == 0 else &"escape_pod"
			modules[extraction_idx].type = FloorLayout.ROOM_EXTRACTION

	# 5) Boucles (jamais vers l'antre du boss).
	if allow_extras:
		var loops := Cfg.range_i(rng, "loops_min", "loops_max", 1, 3)
		var extra: Array[Vector2i] = []
		for m6 in modules:
			for j2: int in _slot_neighbors(m6.slot, by_slot):
				if j2 <= m6.idx or j2 == boss_idx or m6.idx == boss_idx:
					continue
				if edges.has(Vector2i(m6.idx, j2)) or edges.has(Vector2i(j2, m6.idx)):
					continue
				extra.append(Vector2i(m6.idx, j2))
		for n in mini(loops, extra.size()):
			var k := rng.randi_range(0, extra.size() - 1)
			edges.append(extra[k])
			extra.remove_at(k)

	# 6) Escaliers vers l'étage inférieur (rangée haute d'un module ordinaire).
	var down_stairs: Array[Vector2i] = []
	if has_lower:
		var n_down := 1 + (1 if rng.randf() < Cfg.getf("second_stairs_chance", 0.45) else 0)
		var hosts: Array[int] = []
		for m7 in modules:
			if m7.role == &"" and not m7.forced:
				hosts.append(m7.idx)
		# Plutôt au milieu du parcours : tri par distance à l'arrivée, on prend le milieu.
		hosts.sort_custom(func(a: int, b: int) -> bool: return dist[a] < dist[b] or (dist[a] == dist[b] and a < b))
		var picks: Array[int] = []
		if not hosts.is_empty():
			picks.append(hosts[hosts.size() / 2])
			if n_down > 1 and hosts.size() > 2:
				picks.append(hosts[hosts.size() - 1] if hosts[hosts.size() - 1] != picks[0] else hosts[0])
		if picks.is_empty():
			return null
		for hi in picks:
			var hm := modules[hi]
			var inn := hm.inner()
			var sx := rng.randi_range(inn.position.x + 1, inn.end.x - 2)
			var sc := Vector2i(sx, inn.position.y)
			hm.stairs.append(sc)
			down_stairs.append(sc)
	for m8 in modules:
		for st in m8.stairs:
			for dx in range(-2, 3):
				m8.forbid[Vector2i(st.x + dx, m8.rect.position.y)] = true

	# 7) Rôles ordinaires et types.
	var pool: Array = (POOLS.get(floor_index, POOLS[-2]) as Array).duplicate()
	_shuffle(pool, rng)
	var pi := 0
	var weights := Cfg.get_dict("room_type_weights", {"combat": 4.0, "loot": 3.0, "trap": 1.5, "rest": 1.0})
	for m9 in modules:
		if m9.role == &"":
			m9.role = pool[pi % pool.size()]
			pi += 1
			m9.type = _role_type(m9.role, weights, rng)
		var names: Array = NAMES.get(m9.role, ["Module"])
		m9.name = names[rng.randi_range(0, names.size() - 1)]

	# 8) Murs et sols des modules.
	for m10 in modules:
		_walled(L, m10.rect)

	# 9) Couloirs (tubes vitrés).
	var corridors: Array[Corridor] = []
	for e2 in edges:
		var c := _corridor(rng, modules[e2.x], modules[e2.y])
		if c == null:
			return null
		corridors.append(c)
		for sg in c.segs:
			for mm in modules:
				if sg.intersects(mm.rect):
					return null
			_carve(L, sg)

	# 10) Annexes (cloison + porte) : salle des échantillons, chambre forte, cabines.
	var vault_role := &""
	var vault_key := &""
	if allow_extras and floor_index == -1:
		vault_role = &"sample_vault"
		vault_key = KEY_LAB
	elif allow_extras and floor_index <= -2:
		vault_role = &"trench_vault"
		vault_key = KEY_TRENCH
	if vault_role != &"":
		var hosts2: Array[int] = []
		for m11 in modules:
			if m11.type == FloorLayout.ROOM_SPAWN or m11.type == FloorLayout.ROOM_BOSS or m11.type == FloorLayout.ROOM_EXTRACTION:
				continue
			hosts2.append(m11.idx)
		_shuffle(hosts2, rng)
		# Préférence : laboratoire de biologie / salle des pompes.
		var pref := &"bio_lab" if floor_index == -1 else &"pump_room"
		hosts2.sort_custom(func(a: int, b: int) -> bool: return int(modules[a].role == pref) > int(modules[b].role == pref))
		var placed := false
		for h2 in hosts2:
			if _make_annex(L, modules[h2], rng, vault_role, FloorLayout.ROOM_SUPER_LOOT, vault_key, 3):
				if floor_index == -1:
					modules[h2].role = &"bio_lab"
					modules[h2].name = (NAMES[&"bio_lab"] as Array)[rng.randi_range(0, 1)]
				placed = true
				break
		if not placed:
			return null
	if allow_extras:
		for m12 in modules:
			if m12.annex_role != &"":
				continue
			if m12.role == &"quarters" and rng.randf() < Cfg.getf("cabin_chance", 0.8):
				_make_annex(L, m12, rng, &"cabin", _role_type(&"cabin", weights, rng), &"", 3)
			elif m12.role == &"office" and rng.randf() < 0.5:
				_make_annex(L, m12, rng, &"lab_storage", FloorLayout.ROOM_LOOT, &"", 3)
	for m13 in modules:
		if m13.annex_role == &"":
			m13.main_inner = m13.inner()

	# 11) Salles, bâtiments (un par module), portes.
	for m14 in modules:
		var bld := L.add_building(m14.role, m14.name, m14.rect)
		m14.building_id = bld.id
		var room := L.add_room(m14.main_inner, false, m14.type, m14.name, bld.id)
		room.tags.append(String(m14.role))
		room.tags.append("module")
		if FLOODED_ROLES.has(m14.role):
			room.tags.append("flooded")
		m14.room_id = room.id
		if m14.annex_role != &"":
			var anames: Array = NAMES.get(m14.annex_role, ["Annexe"])
			var ar := L.add_room(m14.annex_inner, false, m14.annex_type, anames[rng.randi_range(0, anames.size() - 1)], bld.id)
			ar.tags.append(String(m14.annex_role))
			ar.tags.append("module")
			ar.tags.append("annex")
			m14.annex_room_id = ar.id
	var tube_tag := "catwalk" if floor_index <= -2 else "tube"
	var tube_name := "Coursive" if floor_index <= -2 else "Tube vitré"
	for c2 in corridors:
		for sg2 in c2.segs:
			var cr := L.add_room(sg2, false, FloorLayout.ROOM_CORRIDOR, tube_name)
			cr.tags.append(tube_tag)
			cr.tags.append("corridor")
			c2.room_ids.append(cr.id)
	for c3 in corridors:
		var ma := modules[c3.a]
		var mb := modules[c3.b]
		L.add_door(c3.door_a, c3.vertical_doors, FloorLayout.DoorState.CLOSED, c3.room_ids[0], ma.room_id, &"", ma.building_id)
		L.add_door(c3.door_b, c3.vertical_doors, FloorLayout.DoorState.CLOSED, c3.room_ids[c3.room_ids.size() - 1], mb.room_id, &"", mb.building_id)
	for m15 in modules:
		if m15.annex_role == &"":
			continue
		var st := FloorLayout.DoorState.LOCKED if m15.annex_key != &"" else FloorLayout.DoorState.CLOSED
		L.add_door(m15.annex_door, m15.annex_door_vertical, st, m15.room_id, m15.annex_room_id, m15.annex_key, m15.building_id)

	# 12) Escaliers.
	for s4 in up_stairs:
		_add_stairs(L, s4, true, floor_index + 1)
	for s5 in down_stairs:
		_add_stairs(L, s5, false, floor_index - 1)

	# Murs des tubes : toute case vide autour d'un segment devient un mur.
	for c4 in corridors:
		for sg3 in c4.segs:
			var g := sg3.grow(1)
			for yy2 in range(g.position.y, g.end.y):
				for xx2 in range(g.position.x, g.end.x):
					if L.get_tile(Vector2i(xx2, yy2)) == T.VOID:
						L.set_tile(Vector2i(xx2, yy2), T.WALL)

	# 13) Spawn joueur, bassin d'amarrage, extraction.
	var res := Result.new()
	res.layout = L
	res.down_stairs = down_stairs
	if floor_index == 0:
		var dock := modules[spawn_idx]
		var inn2 := dock.main_inner
		var pc := Vector2i(inn2.position.x + inn2.size.x / 2, inn2.position.y + inn2.size.y / 2)
		for yy in range(pc.y - 1, pc.y + 1):
			for xx in range(pc.x - 1, pc.x + 2):
				res.blocked.append(Vector2i(xx, yy))
		L.add_spawn(L.prop_spawns, pc, &"moon_pool", dock.room_id)
		L.player_spawn = Vector2i(pc.x, mini(pc.y + 2, inn2.end.y - 1))
	else:
		L.player_spawn = _arrival_cell(L, up_stairs[0]) if not up_stairs.is_empty() else modules[0].inner().get_center()
	if extraction_idx >= 0:
		var em := modules[extraction_idx]
		var ec := em.main_inner.get_center()
		for cc: Vector2i in [ec, ec + Vector2i.RIGHT, ec + Vector2i.DOWN, ec + Vector2i.ONE]:
			if L.get_tile(cc) == T.FLOOR and em.main_inner.has_point(cc):
				L.extraction_cells.append(cc)

	# 14) Validation structurelle (rapide ; la connexité découle du graphe : arbre
	# couvrant de modules, tubes continus, portes entre deux cases praticables,
	# annexes fermées par une seule porte). Les tests vérifient par remplissage.
	for c5 in corridors:
		for sg4 in c5.segs:
			for yy3 in range(sg4.position.y, sg4.end.y):
				for xx3 in range(sg4.position.x, sg4.end.x):
					if L.get_tile(Vector2i(xx3, yy3)) != T.FLOOR:
						return null
	for d2 in L.doors:
		var n1 := d2.cell + (Vector2i.LEFT if d2.vertical else Vector2i.UP)
		var n2 := d2.cell + (Vector2i.RIGHT if d2.vertical else Vector2i.DOWN)
		if not FloorLayout.is_walkable_tile(L.get_tile(n1)) or not FloorLayout.is_walkable_tile(L.get_tile(n2)):
			return null
	return res


## Baies occupées (connexes), baies imposées comprises.
static func _pick_slots(rng: RandomNumberGenerator, cols: int, rows: int, want: int, forced: Dictionary) -> Array[Vector2i]:
	for attempt in 30:
		var all: Array[Vector2i] = []
		for y in rows:
			for x in cols:
				all.append(Vector2i(x, y))
		var removed := cols * rows - want
		var keep := {}
		for s in all:
			keep[s] = true
		var order := all.duplicate()
		_shuffle(order, rng)
		for s2: Vector2i in order:
			if removed <= 0:
				break
			if forced.has(s2):
				continue
			keep.erase(s2)
			if _connected(keep):
				removed -= 1
			else:
				keep[s2] = true
		var out: Array[Vector2i] = []
		for s3 in all:
			if keep.has(s3):
				out.append(s3)
		if _connected(keep):
			return out
	return []


static func _connected(keep: Dictionary) -> bool:
	if keep.is_empty():
		return false
	var start: Vector2i = keep.keys()[0]
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if keep.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size() == keep.size()


static func _slot_neighbors(slot: Vector2i, by_slot: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if by_slot.has(slot + d):
			out.append(int(by_slot[slot + d]))
	return out


## Module imposé contenant les escaliers (rangée haute de l'intérieur, à 2 cases
## au moins des murs latéraux), dans les bornes de la baie.
static func _forced_rect(rng: RandomNumberGenerator, b: Rect2i, stairs: Array[Vector2i], wmin: int, wmax: int, hmin: int, hmax: int) -> Rect2i:
	var top := stairs[0].y - 1
	var minx := stairs[0].x
	var maxx := stairs[0].x
	for s in stairs:
		if s.y - 1 != top:
			return Rect2i()
		minx = mini(minx, s.x)
		maxx = maxi(maxx, s.x)
	if top < b.position.y:
		return Rect2i()
	var hcap := mini(hmax, b.end.y - top)
	if hcap < hmin:
		return Rect2i()
	var h := rng.randi_range(hmin, hcap)
	# x : minx >= x + 2 et maxx <= x + w - 3.
	for k in 20:
		var w := rng.randi_range(wmin, mini(wmax, b.size.x))
		var xlo := maxi(b.position.x, maxx + 3 - w)
		var xhi := mini(b.end.x - w, minx - 2)
		if xlo <= xhi:
			return Rect2i(rng.randi_range(xlo, xhi), top, w, h)
	return Rect2i()


static func _bfs(modules: Array[Module], edges: Array[Vector2i], start: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(modules.size())
	dist.fill(999)
	if start < 0:
		start = 0
	dist[start] = 0
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		for e in edges:
			var n := -1
			if e.x == c:
				n = e.y
			elif e.y == c:
				n = e.x
			if n >= 0 and dist[n] > dist[c] + 1:
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


static func _role_type(role: StringName, weights: Dictionary, rng: RandomNumberGenerator) -> StringName:
	match role:
		&"storage", &"lab_storage":
			return FloorLayout.ROOM_LOOT if rng.randf() < 0.75 else FloorLayout.ROOM_COMBAT
		&"infirmary", &"cabin":
			return FloorLayout.ROOM_REST if rng.randf() < 0.55 else FloorLayout.ROOM_LOOT
		&"engine", &"flooded_hall":
			return FloorLayout.ROOM_TRAP if rng.randf() < 0.4 else FloorLayout.ROOM_COMBAT
	return StringName(_weighted(weights, rng))


# --- Couloirs --------------------------------------------------------------------

## Tube de 3 cases entre deux modules voisins (droit si possible, sinon en Z).
static func _corridor(rng: RandomNumberGenerator, ma: Module, mb: Module) -> Corridor:
	var a := ma
	var b := mb
	var horizontal := a.slot.y == b.slot.y
	if horizontal and a.slot.x > b.slot.x or not horizontal and a.slot.y > b.slot.y:
		a = mb
		b = ma
	var c := Corridor.new()
	c.a = a.idx
	c.b = b.idx
	if horizontal:
		c.vertical_doors = true
		var xa := a.rect.end.x - 1     # mur est de a
		var xb := b.rect.position.x    # mur ouest de b
		var ya_opts := _door_positions(a, SIDE_E)
		var yb_opts := _door_positions(b, SIDE_W)
		if ya_opts.is_empty() or yb_opts.is_empty():
			return null
		var common: Array[int] = []
		for y in ya_opts:
			if yb_opts.has(y):
				common.append(y)
		var ya: int
		var yb: int
		if not common.is_empty() and rng.randf() < Cfg.getf("straight_tube_chance", 0.8):
			ya = common[rng.randi_range(0, common.size() - 1)]
			yb = ya
		else:
			ya = ya_opts[rng.randi_range(0, ya_opts.size() - 1)]
			yb = yb_opts[rng.randi_range(0, yb_opts.size() - 1)]
		c.door_a = Vector2i(xa, ya)
		c.door_b = Vector2i(xb, yb)
		if ya == yb:
			c.segs.append(Rect2i(xa + 1, ya - 1, xb - xa - 1, 3))
		else:
			var lo := xa + 2
			var hi := xb - 2
			if lo > hi:
				return null
			var mx := rng.randi_range(lo, hi)
			c.segs.append(Rect2i(xa + 1, ya - 1, mx + 2 - (xa + 1), 3))
			c.segs.append(Rect2i(mx - 1, mini(ya, yb) - 1, 3, absi(ya - yb) + 3))
			c.segs.append(Rect2i(mx - 1, yb - 1, xb - (mx - 1), 3))
		a.door_sides[SIDE_E] = c.door_a
		b.door_sides[SIDE_W] = c.door_b
	else:
		c.vertical_doors = false
		var ya2 := a.rect.end.y - 1    # mur sud de a
		var yb2 := b.rect.position.y   # mur nord de b
		var xa_opts := _door_positions(a, SIDE_S)
		var xb_opts := _door_positions(b, SIDE_N)
		if xa_opts.is_empty() or xb_opts.is_empty():
			return null
		var common2: Array[int] = []
		for x in xa_opts:
			if xb_opts.has(x):
				common2.append(x)
		var xa2: int
		var xb2: int
		if not common2.is_empty() and rng.randf() < Cfg.getf("straight_tube_chance", 0.8):
			xa2 = common2[rng.randi_range(0, common2.size() - 1)]
			xb2 = xa2
		else:
			xa2 = xa_opts[rng.randi_range(0, xa_opts.size() - 1)]
			xb2 = xb_opts[rng.randi_range(0, xb_opts.size() - 1)]
		c.door_a = Vector2i(xa2, ya2)
		c.door_b = Vector2i(xb2, yb2)
		if xa2 == xb2:
			c.segs.append(Rect2i(xa2 - 1, ya2 + 1, 3, yb2 - ya2 - 1))
		else:
			var lo2 := ya2 + 2
			var hi2 := yb2 - 2
			if lo2 > hi2:
				return null
			var my := rng.randi_range(lo2, hi2)
			c.segs.append(Rect2i(xa2 - 1, ya2 + 1, 3, my + 2 - (ya2 + 1)))
			c.segs.append(Rect2i(mini(xa2, xb2) - 1, my - 1, absi(xa2 - xb2) + 3, 3))
			c.segs.append(Rect2i(xb2 - 1, my - 1, 3, yb2 - (my - 1)))
		a.door_sides[SIDE_S] = c.door_a
		b.door_sides[SIDE_N] = c.door_b
	return c


## Positions possibles (ligne ou colonne) d'une porte de couloir sur le côté `side` :
## le tube de 3 cases doit toucher le mur hors des angles, hors cases interdites.
static func _door_positions(m: Module, side: int) -> Array[int]:
	var out: Array[int] = []
	var r := m.rect
	if side == SIDE_E or side == SIDE_W:
		var x := r.end.x - 1 if side == SIDE_E else r.position.x
		for y in range(r.position.y + 2, r.end.y - 2):
			if not m.forbid.has(Vector2i(x, y)):
				out.append(y)
	else:
		var y2 := r.end.y - 1 if side == SIDE_S else r.position.y
		for x2 in range(r.position.x + 2, r.end.x - 2):
			if not m.forbid.has(Vector2i(x2, y2)):
				out.append(x2)
	return out


## carve_walled_rect rapide (indices directs ; le rectangle est dans la grille).
static func _walled(L: FloorLayout, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		var edge_y := y == r.position.y or y == r.end.y - 1
		for x in range(r.position.x, r.end.x):
			L.set_tile(Vector2i(x, y), T.WALL if edge_y or x == r.position.x or x == r.end.x - 1 else T.FLOOR)


static func _carve(L: FloorLayout, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if L.get_tile(c) == T.VOID:
				L.set_tile(c, T.FLOOR)


# --- Annexes ---------------------------------------------------------------------

## Cloisonne une bande de `depth` cases d'intérieur le long d'un côté du module
## sans porte de couloir ni escalier ; porte au milieu de la cloison.
static func _make_annex(L: FloorLayout, m: Module, rng: RandomNumberGenerator, role: StringName, type: StringName, key: StringName, depth: int) -> bool:
	var inn := m.inner()
	var sides: Array[int] = [SIDE_N, SIDE_S, SIDE_W, SIDE_E]
	_shuffle(sides, rng)
	for side in sides:
		if m.door_sides.has(side):
			continue
		var d := depth + (1 if rng.randf() < 0.4 else 0)
		var annex: Rect2i
		var main: Rect2i
		var wall: Rect2i
		match side:
			SIDE_N:
				annex = Rect2i(inn.position.x, inn.position.y, inn.size.x, d)
				wall = Rect2i(inn.position.x, inn.position.y + d, inn.size.x, 1)
				main = Rect2i(inn.position.x, inn.position.y + d + 1, inn.size.x, inn.size.y - d - 1)
			SIDE_S:
				annex = Rect2i(inn.position.x, inn.end.y - d, inn.size.x, d)
				wall = Rect2i(inn.position.x, inn.end.y - d - 1, inn.size.x, 1)
				main = Rect2i(inn.position.x, inn.position.y, inn.size.x, inn.size.y - d - 1)
			SIDE_W:
				annex = Rect2i(inn.position.x, inn.position.y, d, inn.size.y)
				wall = Rect2i(inn.position.x + d, inn.position.y, 1, inn.size.y)
				main = Rect2i(inn.position.x + d + 1, inn.position.y, inn.size.x - d - 1, inn.size.y)
			_:
				annex = Rect2i(inn.end.x - d, inn.position.y, d, inn.size.y)
				wall = Rect2i(inn.end.x - d - 1, inn.position.y, 1, inn.size.y)
				main = Rect2i(inn.position.x, inn.position.y, inn.size.x - d - 1, inn.size.y)
		if main.size.x < 4 or main.size.y < 4:
			continue
		# Aucune porte de couloir ni escalier dans la bande (annexe + cloison).
		var strip := annex.merge(wall)
		var bad := false
		for dc: Vector2i in m.door_sides.values():
			# Une porte de mur perpendiculaire « regarde » la case intérieure voisine.
			for nb: Vector2i in [dc + Vector2i.LEFT, dc + Vector2i.RIGHT, dc + Vector2i.UP, dc + Vector2i.DOWN]:
				if strip.has_point(nb):
					bad = true
		for st in m.stairs:
			if strip.grow(1).has_point(st):
				bad = true
		if bad:
			continue
		# Porte de la cloison : pas devant une porte de couloir (case voisine dans main).
		var opts: Array[Vector2i] = []
		var vertical := side == SIDE_W or side == SIDE_E
		if vertical:
			for y in range(wall.position.y + 1, wall.end.y - 1):
				opts.append(Vector2i(wall.position.x, y))
		else:
			for x in range(wall.position.x + 1, wall.end.x - 1):
				opts.append(Vector2i(x, wall.position.y))
		if opts.is_empty():
			continue
		var dcell := opts[opts.size() / 2 + rng.randi_range(-1, 1) if opts.size() > 2 else 0]
		L.fill_rect(wall, T.WALL)
		m.annex_role = role
		m.annex_type = type
		m.annex_key = key
		m.annex_inner = annex
		m.main_inner = main
		m.annex_door = dcell
		m.annex_door_vertical = vertical
		return true
	return false


# --- Divers ----------------------------------------------------------------------

static func _add_stairs(L: FloorLayout, cell: Vector2i, up: bool, target: int) -> void:
	L.set_tile(cell, T.STAIRS_UP if up else T.STAIRS_DOWN)
	var st := FloorLayout.Stairs.new()
	st.cell = cell
	st.up = up
	st.target_floor = target
	st.target_cell = cell
	L.stairs.append(st)


static func _arrival_cell(L: FloorLayout, s: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
		if L.get_tile(s + d) == T.FLOOR:
			return s + d
	return s


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


static func _weighted(w: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys: Array = w.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	var total := 0.0
	for k: Variant in keys:
		total += float(w[k])
	var roll := rng.randf() * total
	for k2: Variant in keys:
		roll -= float(w[k2])
		if roll <= 0.0:
			return String(k2)
	return String(keys[keys.size() - 1])
