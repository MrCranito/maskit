class_name ExtractionPlan
extends RefCounted
## Extractions d'un étage ([extraction] de data/balance.cfg) : une permanente, des temporaires
## à durée de vie et des trappes d'urgence fermées à clef.
##
## Appliqué par Raid._generate_floors APRÈS la génération et l'aménagement (le peuplement des
## générateurs et les cartes pré-rendues ne changent pas). Un étage sans case d'extraction
## reste sans extraction. Sinon, les emplacements possibles (blocs 2×2 libres : rue ou
## plancher, atteignables sans clef, hors décors / conteneurs / cachettes / emprise rendue,
## loin des portes et escaliers) sont classés en quatre options :
##   A. au bout du parcours : le plus loin du départ, de préférence en extérieur (rue, place) ;
##   B. à mi-parcours : distance de marche la plus proche de mid_ratio × distance de A ;
##   C. près d'un escalier (à stairs_max_cells cases au plus) ;
##   D. la zone d'extraction posée par le générateur de l'étage.
## A devient l'extraction PERMANENTE (toujours ouverte). B, C et D deviennent les extractions
## TEMPORAIRES (complétées si besoin jusqu'à temporary_zones) : chacune ferme à `closes_at` s
## (horloge du raid) = base + distance × per_cell (+ bonus par étage), au moins `min_gap` s
## après la précédente : la plus proche ferme la première.
## Trappes d'urgence (hatches_per_floor, +1 sur un grand étage) : ailleurs, de préférence en
## intérieur ; s'ouvrent avec une clef de trappe, jamais affichées sur la carte.
## Déterministe : un RandomNumberGenerator initialisé par `seed_value` (même étage chez l'hôte
## et l'invité en coop).

const KIND_PERMANENT := &"permanent"
const KIND_TEMPORARY := &"temporary"
const KIND_HATCH := &"hatch"

## Une zone : cases, nom de direction, ouverture / fermeture (s, horloge du raid).
class Spec:
	var cells: Array[Vector2i] = []
	var name: String = ""
	## KIND_PERMANENT, KIND_TEMPORARY ou KIND_HATCH.
	var kind: StringName = KIND_TEMPORARY
	## Option de placement (« A » bout du parcours, « B » mi-parcours, « C » escalier,
	## « D » générateur, « + » complément, « T » trappe) : debug et tests.
	var option: String = ""
	## Distance de marche (cases) depuis le point d'apparition de l'étage.
	var distance: float = 0.0
	var opens_at: float = 0.0
	## INF : ne ferme jamais.
	var closes_at: float = INF
	## Rang des temporaires par distance (0 = la plus proche) ; -1 pour les autres.
	var rank: int = 0

	func is_hatch() -> bool:
		return kind == KIND_HATCH


static func cfg_f(key: String, def: float) -> float:
	return Balance.get_float("extraction", key, def)


static func cfg_i(key: String, def: int) -> int:
	return int(Balance.get_value("extraction", key, def))


static func _make(cd: Dictionary, kind: StringName, option: String) -> Spec:
	var s := Spec.new()
	s.cells.assign(cd["cells"])
	s.distance = float(cd["d"])
	s.kind = kind
	s.option = option
	return s


## Calcule L.extraction_specs (et remplace L.extraction_cells par les cases de la permanente
## et des temporaires ; les trappes n'y sont pas). `blocked` : rectangles monde infranchissables
## en plus des tuiles (emprise d'une carte pré-rendue).
static func apply(L: FloorLayout, seed_value: int, blocked: Array[Rect2] = []) -> void:
	L.extraction_specs.clear()
	if L.extraction_cells.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var dist := walk_distances(L)
	var gen: Array[Spec] = []
	for g: Array in ExtractionZone.group_cells(L.extraction_cells):
		var s := Spec.new()
		s.cells.assign(g)
		s.distance = _zone_distance(s.cells, dist, L)
		s.option = "D"
		gen.append(s)
	gen.sort_custom(func(a: Spec, b: Spec) -> bool: return a.distance < b.distance)
	var cands := candidates(L, dist, blocked)
	var chosen: Array[Spec] = []
	# A : permanente au bout du parcours (sinon la zone du générateur la plus lointaine).
	var perm := _pick_far_open(cands, L, rng)
	if perm == null:
		perm = gen.pop_back()
	perm.kind = KIND_PERMANENT
	perm.option = "A"
	chosen.append(perm)
	# Temporaires : options B, C, D dans cet ordre, puis compléments.
	var want := maxi(cfg_i("temporary_zones", 3), 0)
	var temps: Array[Spec] = []
	if want > 0:
		var b := _pick_mid(cands, chosen, perm.distance * cfg_f("mid_ratio", 0.55))
		if b != null:
			temps.append(b)
			chosen.append(b)
	if temps.size() < want:
		var c := _pick_stairs(cands, chosen, L)
		if c != null:
			temps.append(c)
			chosen.append(c)
	for d: Spec in gen:
		if temps.size() >= want:
			break
		if not _too_close(d.cells, chosen):
			temps.append(d)
			chosen.append(d)
	while temps.size() < want:
		var s2 := _pick_spread(cands, chosen, L, rng)
		if s2 == null:
			break
		s2.option = "+"
		temps.append(s2)
		chosen.append(s2)
	temps.sort_custom(func(a: Spec, b2: Spec) -> bool: return a.distance < b2.distance)
	var timed := bool(Balance.get_value("extraction", "timed_zones", true))
	var prev := -INF
	for i in temps.size():
		var s3 := temps[i]
		s3.kind = KIND_TEMPORARY
		s3.rank = i
		if not timed:
			continue
		var t := cfg_f("lifetime_base", 180.0) + s3.distance * cfg_f("lifetime_per_cell", 3.0) \
			+ absf(float(L.floor_index)) * cfg_f("lifetime_floor_bonus", 60.0)
		t = clampf(t, cfg_f("lifetime_min", 120.0), cfg_f("lifetime_max", 900.0))
		t = maxf(t, prev + cfg_f("lifetime_min_gap", 75.0))
		s3.closes_at = t
		prev = t
	perm.rank = -1
	var specs: Array[Spec] = []
	specs.append_array(temps)
	specs.append(perm)
	_name_zones(specs, L)
	var all_cells: Array[Vector2i] = []
	for s4: Spec in specs:
		all_cells.append_array(s4.cells)
	L.extraction_cells = all_cells
	var hatches := _pick_hatches(cands, specs, L, rng)
	_name_zones(hatches, L, "Trappe ")
	specs.append_array(hatches)
	L.extraction_specs.assign(specs)


## Nombre de trappes de l'étage : hatches_per_floor, +1 au-delà de hatch_big_floor_cells cases
## praticables.
static func hatch_count(L: FloorLayout) -> int:
	var n := maxi(cfg_i("hatches_per_floor", 1), 0)
	if n == 0:
		return 0
	var walk := 0
	for t: int in L.tiles:
		if t == FloorLayout.Tile.STREET or t == FloorLayout.Tile.FLOOR:
			walk += 1
	if walk >= cfg_i("hatch_big_floor_cells", 2600):
		n += 1
	return n


## Option A : candidat le plus loin du départ, de préférence tout en rue (extérieur).
static func _pick_far_open(cands: Array, L: FloorLayout, rng: RandomNumberGenerator) -> Spec:
	var jitter := cfg_f("zone_pick_jitter", 4.0)
	for outdoor: bool in [true, false]:
		var best: Dictionary = {}
		var best_score := -INF
		for cd: Dictionary in cands:
			if outdoor and not _all_tiles(L, cd["cells"], FloorLayout.Tile.STREET):
				continue
			var score := float(cd["d"]) + rng.randf() * jitter
			if score > best_score:
				best_score = score
				best = cd
		if not best.is_empty():
			return _make(best, KIND_PERMANENT, "A")
	return null


## Option B : distance de marche la plus proche de `target`.
static func _pick_mid(cands: Array, chosen: Array[Spec], target: float) -> Spec:
	var best: Dictionary = {}
	var best_gap := INF
	for cd: Dictionary in cands:
		if _too_close(cd["cells"], chosen):
			continue
		var gap := absf(float(cd["d"]) - target)
		if gap < best_gap:
			best_gap = gap
			best = cd
	return null if best.is_empty() else _make(best, KIND_TEMPORARY, "B")


## Option C : candidat le plus proche d'un escalier (stairs_max_cells cases au plus).
static func _pick_stairs(cands: Array, chosen: Array[Spec], L: FloorLayout) -> Spec:
	if L.stairs.is_empty():
		return null
	var best: Dictionary = {}
	var best_d := cfg_f("stairs_max_cells", 12.0)
	for cd: Dictionary in cands:
		if _too_close(cd["cells"], chosen):
			continue
		var p := Vector2(cd["cells"][0]) + Vector2(0.5, 0.5)
		for st: FloorLayout.Stairs in L.stairs:
			var d := p.distance_to(Vector2(st.cell))
			if d <= best_d:
				best_d = d
				best = cd
	return null if best.is_empty() else _make(best, KIND_TEMPORARY, "C")


## Trappes : loin des extractions et entre elles, à hatch_min_spawn_cells du départ au moins,
## de préférence en intérieur (plancher) ; tirage au hasard parmi les emplacements restants.
static func _pick_hatches(cands: Array, specs: Array[Spec], L: FloorLayout, rng: RandomNumberGenerator) -> Array[Spec]:
	var out: Array[Spec] = []
	var n := hatch_count(L)
	var min_d := cfg_i("hatch_min_spawn_cells", 14)
	var gap := float(cfg_i("hatch_min_gap_cells", 12))
	for k in n:
		var placed: Array[Spec] = []
		placed.append_array(specs)
		placed.append_array(out)
		var pick: Dictionary = {}
		for indoor: bool in [true, false]:
			var pool: Array = []
			for cd: Dictionary in cands:
				if int(cd["d"]) < min_d or _too_close(cd["cells"], placed, gap):
					continue
				if indoor and not _all_tiles(L, cd["cells"], FloorLayout.Tile.FLOOR):
					continue
				pool.append(cd)
			if not pool.is_empty():
				pick = pool[rng.randi_range(0, pool.size() - 1)]
				break
		if pick.is_empty():
			break
		var s := _make(pick, KIND_HATCH, "T")
		s.rank = -1
		out.append(s)
	return out


static func _all_tiles(L: FloorLayout, cells: Array, tile: int) -> bool:
	for c: Vector2i in cells:
		if L.get_tile(c) != tile:
			return false
	return true


## Distance de marche (cases, 4-voisinage) depuis le point d'apparition ; portes verrouillées
## infranchissables. Case → int.
static func walk_distances(L: FloorLayout) -> Dictionary:
	var dist := {L.player_spawn: 0}
	var queue: Array[Vector2i] = [L.player_spawn]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var dc: int = dist[c]
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if dist.has(n):
				continue
			var t := L.get_tile(n)
			if not FloorLayout.is_walkable_tile(t):
				continue
			if t == FloorLayout.Tile.DOOR:
				var door := L.get_door_at(n)
				if door != null and door.state == FloorLayout.DoorState.LOCKED:
					continue
			dist[n] = dc + 1
			queue.append(n)
	return dist


static func _zone_distance(cells: Array[Vector2i], dist: Dictionary, L: FloorLayout) -> float:
	var best := INF
	for c: Vector2i in cells:
		if dist.has(c):
			best = minf(best, float(dist[c]))
	if best == INF and not cells.is_empty():
		best = Vector2(cells[0]).distance_to(Vector2(L.player_spawn)) * 1.5
	return best


## Blocs 2×2 libres : Array de {"cells": Array[Vector2i], "d": int (distance de marche)}.
static func candidates(L: FloorLayout, dist: Dictionary, blocked: Array[Rect2] = []) -> Array:
	var busy := {}
	for list: Array in [L.prop_spawns, L.container_spawns, L.hiding_spot_spawns, L.enemy_spawns, L.landmark_spawns]:
		for sp: FloorLayout.Spawn in list:
			for c: Vector2i in FloorLayout.spawn_cells(sp):
				busy[c] = true
	var keep_out := {}
	var margin := cfg_i("zone_keep_out", 2)
	var pois: Array[Vector2i] = []
	for d: FloorLayout.Door in L.doors:
		pois.append(d.cell)
	for st: FloorLayout.Stairs in L.stairs:
		pois.append(st.cell)
	for p: Vector2i in pois:
		for dy in range(-margin, margin + 1):
			for dx in range(-margin, margin + 1):
				keep_out[p + Vector2i(dx, dy)] = true
	# Salles de super-loot et de boss : pas d'extraction dedans.
	for r: FloorLayout.Room in L.rooms:
		if r.type == FloorLayout.ROOM_SUPER_LOOT or r.type == FloorLayout.ROOM_BOSS:
			for ry in range(r.rect.position.y, r.rect.end.y):
				for rx in range(r.rect.position.x, r.rect.end.x):
					keep_out[Vector2i(rx, ry)] = true
	var min_spawn := cfg_i("zone_min_spawn_cells", 12)
	var ts := float(FloorLayout.TILE_SIZE)
	var out: Array = []
	for y in range(1, L.size.y - 2):
		for x in range(1, L.size.x - 2):
			var c0 := Vector2i(x, y)
			if not dist.has(c0) or int(dist[c0]) < min_spawn:
				continue
			var cells: Array[Vector2i] = [c0, c0 + Vector2i.RIGHT, c0 + Vector2i.DOWN, c0 + Vector2i.ONE]
			var ok := true
			for c: Vector2i in cells:
				var t := L.get_tile(c)
				if (t != FloorLayout.Tile.STREET and t != FloorLayout.Tile.FLOOR) or busy.has(c) \
						or keep_out.has(c) or not dist.has(c) or L.extraction_cells.has(c):
					ok = false
					break
			if not ok:
				continue
			if not blocked.is_empty():
				var box := Rect2(Vector2(c0) * ts, Vector2(2, 2) * ts).grow(-4.0)
				for b: Rect2 in blocked:
					if b.intersects(box):
						ok = false
						break
			if ok:
				out.append({"cells": cells, "d": int(dist[c0])})
	return out


static func _too_close(cells: Array, specs: Array[Spec], gap: float = -1.0) -> bool:
	if gap < 0.0:
		gap = float(cfg_i("zone_min_gap_cells", 14))
	for s: Spec in specs:
		for a: Vector2i in s.cells:
			if Vector2(a).distance_to(Vector2(cells[0])) < gap:
				return true
	return false


## Candidat le plus éloigné des zones déjà choisies et du départ, avec une distance de marche
## différente de celles des zones existantes (sinon la contrainte est relâchée).
static func _pick_spread(cands: Array, specs: Array[Spec], L: FloorLayout, rng: RandomNumberGenerator) -> Spec:
	var dgap := cfg_f("zone_distance_gap_cells", 10.0)
	var jitter := cfg_f("zone_pick_jitter", 4.0)
	for strict: bool in [true, false]:
		var best: Dictionary = {}
		var best_score := -INF
		for cd: Dictionary in cands:
			var cells: Array = cd["cells"]
			if _too_close(cells, specs):
				continue
			if strict:
				var clash := false
				for s: Spec in specs:
					if absf(float(cd["d"]) - s.distance) < dgap:
						clash = true
						break
				if clash:
					continue
			var p := Vector2(cells[0])
			var score := p.distance_to(Vector2(L.player_spawn))
			for s2: Spec in specs:
				score = minf(score, p.distance_to(Vector2(s2.cells[0])))
			score += rng.randf() * jitter
			if score > best_score:
				best_score = score
				best = cd
		if not best.is_empty():
			var out := Spec.new()
			out.cells.assign(best["cells"])
			out.distance = float(best["d"])
			return out
	return null


const DIRS := ["Est", "Sud-Est", "Sud", "Sud-Ouest", "Ouest", "Nord-Ouest", "Nord", "Nord-Est"]
const DIRS4 := ["Est", "Sud", "Ouest", "Nord"]


## Nom de direction (par rapport au centre de l'étage), unique sur l'étage.
static func _name_zones(specs: Array[Spec], L: FloorLayout, prefix: String = "") -> void:
	var used := {}
	var center := Vector2(L.size) * 0.5
	for s: Spec in specs:
		var c := Vector2.ZERO
		for cc: Vector2i in s.cells:
			c += Vector2(cc) + Vector2(0.5, 0.5)
		c /= maxf(s.cells.size(), 1.0)
		var rel := (c - center) / (Vector2(L.size) * 0.5)
		var nm := "Centre"
		if rel.length() > 0.2:
			var a := rel.angle()
			nm = DIRS[posmod(roundi(a / (TAU / 8.0)), 8)]
			if used.has(nm):
				nm = DIRS4[posmod(roundi(a / (TAU / 4.0)), 4)]
		var base := nm
		var k := 2
		while used.has(nm):
			nm = "%s %d" % [base, k]
			k += 1
		used[nm] = true
		s.name = prefix + nm
