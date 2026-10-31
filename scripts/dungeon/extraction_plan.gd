class_name ExtractionPlan
extends RefCounted
## Zones d'extraction d'un étage à durée de vie ([extraction] de data/balance.cfg).
##
## Appliqué par Raid._generate_floors APRÈS la génération et l'aménagement (le peuplement des
## générateurs et les cartes pré-rendues ne changent pas) :
##   - un étage sans case d'extraction reste sans extraction ;
##   - sinon l'étage reçoit `zones_per_floor` zones (3) : les zones des générateurs sont gardées,
##     les manquantes sont posées sur des blocs 2×2 libres (rue ou plancher, atteignables sans
##     clef, hors décors / conteneurs / cachettes / emprise rendue, loin des portes et escaliers),
##     à des distances de marche différentes du point d'apparition ;
##   - chaque zone ferme à `closes_at` s (horloge du raid) : base + distance × per_cell (+ bonus
##     par étage), au moins `min_gap` s après la précédente : la plus proche ferme la première ;
##   - une zone d'urgence (la plus loin possible du départ) reste éteinte puis s'ouvre quand la
##     dernière zone ferme ; elle ne ferme plus, mais sa canalisation est plus longue.
## Déterministe : un RandomNumberGenerator initialisé par `seed_value` (même étage chez l'hôte
## et l'invité en coop).

## Une zone : cases, nom de direction, ouverture / fermeture (s, horloge du raid).
class Spec:
	var cells: Array[Vector2i] = []
	var name: String = ""
	## Distance de marche (cases) depuis le point d'apparition de l'étage.
	var distance: float = 0.0
	var opens_at: float = 0.0
	## INF : ne ferme jamais.
	var closes_at: float = INF
	var emergency: bool = false
	## Rang par distance (0 = la plus proche) ; -1 pour la zone d'urgence.
	var rank: int = 0


static func cfg_f(key: String, def: float) -> float:
	return Balance.get_float("extraction", key, def)


static func cfg_i(key: String, def: int) -> int:
	return int(Balance.get_value("extraction", key, def))


## Calcule L.extraction_specs (et complète L.extraction_cells). `blocked` : rectangles monde
## infranchissables en plus des tuiles (emprise d'une carte pré-rendue).
static func apply(L: FloorLayout, seed_value: int, blocked: Array[Rect2] = []) -> void:
	L.extraction_specs.clear()
	if L.extraction_cells.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var dist := walk_distances(L)
	var specs: Array[Spec] = []
	for g: Array in ExtractionZone.group_cells(L.extraction_cells):
		var s := Spec.new()
		s.cells.assign(g)
		s.distance = _zone_distance(s.cells, dist, L)
		specs.append(s)
	var want := maxi(cfg_i("zones_per_floor", 3), 1)
	if not bool(Balance.get_value("extraction", "timed_zones", true)):
		want = specs.size()
	# Trop de zones : on garde la plus proche, la plus lointaine et des intermédiaires.
	if specs.size() > want:
		specs.sort_custom(func(a: Spec, b: Spec) -> bool: return a.distance < b.distance)
		var kept: Array[Spec] = []
		for i in want:
			var idx := 0 if want == 1 else roundi(float(i) * float(specs.size() - 1) / float(want - 1))
			if not kept.has(specs[idx]):
				kept.append(specs[idx])
		specs = kept
	var cands: Array = []
	if specs.size() < want or bool(Balance.get_value("extraction", "emergency_zone", true)):
		cands = candidates(L, dist, blocked)
	while specs.size() < want:
		var s2 := _pick_spread(cands, specs, L, rng)
		if s2 == null:
			break
		specs.append(s2)
	specs.sort_custom(func(a: Spec, b: Spec) -> bool: return a.distance < b.distance)
	var timed := bool(Balance.get_value("extraction", "timed_zones", true))
	var prev := -INF
	for i in specs.size():
		var s3 := specs[i]
		s3.rank = i
		if not timed:
			s3.closes_at = INF
			continue
		var t := cfg_f("lifetime_base", 180.0) + s3.distance * cfg_f("lifetime_per_cell", 3.0) \
			+ absf(float(L.floor_index)) * cfg_f("lifetime_floor_bonus", 60.0)
		t = clampf(t, cfg_f("lifetime_min", 120.0), cfg_f("lifetime_max", 900.0))
		t = maxf(t, prev + cfg_f("lifetime_min_gap", 75.0))
		s3.closes_at = t
		prev = t
	# Zone d'urgence : la plus lointaine possible, ouverte quand la dernière zone ferme.
	if timed and not specs.is_empty() and bool(Balance.get_value("extraction", "emergency_zone", true)):
		var em := _pick_farthest(cands, specs)
		if em == null:
			# Pas de place : la zone la plus lointaine ne ferme jamais.
			specs[specs.size() - 1].closes_at = INF
		else:
			em.emergency = true
			em.rank = -1
			em.opens_at = specs[specs.size() - 1].closes_at
			em.closes_at = INF
			specs.append(em)
	_name_zones(specs, L)
	var all_cells: Array[Vector2i] = []
	for s4: Spec in specs:
		all_cells.append_array(s4.cells)
	L.extraction_cells = all_cells
	L.extraction_specs.assign(specs)


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


static func _too_close(cells: Array, specs: Array[Spec]) -> bool:
	var gap := float(cfg_i("zone_min_gap_cells", 14))
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


static func _pick_farthest(cands: Array, specs: Array[Spec]) -> Spec:
	var best: Dictionary = {}
	for cd: Dictionary in cands:
		if _too_close(cd["cells"], specs):
			continue
		if best.is_empty() or int(cd["d"]) > int(best["d"]):
			best = cd
	if best.is_empty():
		return null
	var out := Spec.new()
	out.cells.assign(best["cells"])
	out.distance = float(best["d"])
	return out


const DIRS := ["Est", "Sud-Est", "Sud", "Sud-Ouest", "Ouest", "Nord-Ouest", "Nord", "Nord-Est"]
const DIRS4 := ["Est", "Sud", "Ouest", "Nord"]


## Nom de direction (par rapport au centre de l'étage), unique sur l'étage.
static func _name_zones(specs: Array[Spec], L: FloorLayout) -> void:
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
		s.name = nm
