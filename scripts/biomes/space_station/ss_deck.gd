extends RefCounted
## Structure d'un pont de la Station Orbitale (sans spawns : voir ss_populator.gd).
##
## Squelette commun à tous les ponts d'un même run (« Plan ») : une grille de coursives
## fermées (2-3 cases) — `xs` verticales, `ys` horizontales — qui découpe la coque en
## blocs. Chaque pont :
##   1. retire quelques tronçons de coursive (fusionne deux blocs voisins → grandes salles),
##   2. creuse les coursives, puis découpe chaque bloc (BSP, murs partagés d'une case) en
##      modules rectangulaires ou octogonaux (« circulaires »), parfois traversés par un
##      conduit de service de 2 cases,
##   3. relie chaque salle par une porte à sas (ou une large ouverture pour le hangar)
##      à la coursive ou à une salle voisine déjà reliée ; les salles super_loot ont une
##      unique porte verrouillée, la salle du réacteur une unique porte.
## Les cages d'ascenseur sont à la même position sur tous les ponts (escaliers :
## target_cell == cell). Pont 1 (commandement) : coque réduite aux colonnes centrales.

const Cfg := preload("res://scripts/biomes/space_station/ss_config.gd")
const T := FloorLayout.Tile

const KEY_LAB := &"key_space_lab"
const KEY_ARMORY := &"key_space_armory"
const KEY_REACTOR := &"key_space_reactor"

const DECK_MACHINES := -1
const DECK_MAIN := 0
const DECK_COMMAND := 1

## Taille minimale (murs compris) d'un module.
const MIN_ROOM := 6

## Rôles (Room.tags[0]) → nom affiché.
const ROLE_NAMES := {
	&"hangar": "Hangar d'arrivée", &"pod_bay": "Baie des capsules de sauvetage",
	&"quarters": "Quartiers de l'équipage", &"mess_hall": "Réfectoire", &"infirmary": "Infirmerie",
	&"lab": "Laboratoire", &"lab_vault": "Laboratoire scellé", &"storage": "Entrepôt",
	&"hydroponics": "Serre hydroponique", &"workshop": "Atelier", &"server_room": "Salle des serveurs",
	&"elevator": "Ascenseur", &"closet": "Réduit technique",
	&"bridge": "Passerelle", &"radar": "Salle radar", &"officer_quarters": "Quartiers des officiers",
	&"armory": "Armurerie", &"briefing": "Salle de briefing", &"observatory": "Observatoire",
	&"captain_cabin": "Cabine du commandant", &"comms": "Salle des communications",
	&"reactor": "Salle du réacteur", &"core_vault": "Chambre forte du cœur", &"pumps": "Salle des pompes",
	&"coolant": "Circuit de refroidissement", &"generator": "Salle des générateurs", &"cargo_hold": "Soute",
	&"maintenance_pod": "Sas des capsules de maintenance", &"command_pod": "Capsule d'évacuation des officiers",
	&"corridor": "Coursive", &"conduit": "Conduit de service",
}

## Rôles de salles « circulaires » (octogonales) possibles.
const ROUND_ROLES := {&"reactor": 1.0, &"radar": 1.0, &"observatory": 1.0, &"lab": 0.5, &"hydroponics": 0.6, &"briefing": 0.3, &"generator": 0.4}


class Plan:
	var size: Vector2i
	## Coursives verticales : (x, largeur) ; horizontales : (y, largeur).
	var xs: Array[Vector2i] = []
	var ys: Array[Vector2i] = []
	## Bloc (colonne, rangée) de la cage d'ascenseur 0↔1 et de l'échelle 0↔-1.
	var up_block: Vector2i
	var down_block: Vector2i
	var up_left: bool = true
	var down_left: bool = true
	var up_cell: Vector2i
	var down_cell: Vector2i

	func ncols() -> int:
		return xs.size() + 1

	func nrows() -> int:
		return ys.size() + 1

	## [x0, x1[ de la colonne c (murs compris).
	func col_span(c: int) -> Vector2i:
		var x0 := 0 if c == 0 else xs[c - 1].x + xs[c - 1].y
		var x1 := size.x if c == xs.size() else xs[c].x
		return Vector2i(x0, x1)

	func row_span(r: int) -> Vector2i:
		var y0 := 0 if r == 0 else ys[r - 1].x + ys[r - 1].y
		var y1 := size.y if r == ys.size() else ys[r].x
		return Vector2i(y0, y1)

	func block_rect(b: Vector2i) -> Rect2i:
		var cs := col_span(b.x)
		var rs := row_span(b.y)
		return Rect2i(cs.x, rs.x, cs.y - cs.x, rs.y - rs.x)

	## Tranche de 5 cases de large (murs compris) contre une coursive verticale.
	func shaft_slice(b: Vector2i, left: bool) -> Rect2i:
		var r := block_rect(b)
		var x := r.position.x if left else r.end.x - 5
		return Rect2i(x, r.position.y, 5, r.size.y)

	## Cabine (5×5 murs compris) en haut de la tranche.
	func shaft_rect(b: Vector2i, left: bool) -> Rect2i:
		var s := shaft_slice(b, left)
		return Rect2i(s.position, Vector2i(5, 5))

	func shaft_cell(b: Vector2i, left: bool) -> Vector2i:
		var s := shaft_rect(b, left)
		return Vector2i(s.position.x + 2, s.position.y + 1)


class Seg:
	var rect: Rect2i
	var horizontal: bool = true
	var line: int = 0
	var piece: int = 0
	var block_a: Vector2i     ## Au-dessus / à gauche
	var block_b: Vector2i     ## En dessous / à droite
	var node_a: Vector2i = Vector2i(-1, -1)
	var node_b: Vector2i = Vector2i(-1, -1)
	var inside: bool = true   ## Dans la coque du pont
	var kept: bool = true


class Spec:
	var rect: Rect2i          ## Murs compris
	var role: StringName = &"storage"
	var type: StringName = &"combat"
	var name: String = ""
	var round: bool = false
	var key: StringName = &""
	var corridor: bool = false
	var open_side: int = -1   ## Côté ouvert (hangar) : 0 ouest, 1 est, 2 nord, 3 sud
	var room: FloorLayout.Room = null
	var unit: int = -1


## Résultat d'un pont : layout + infos pour le peuplement.
class Deck:
	var layout: FloorLayout
	var specs: Array[Spec] = []


# --- Plan -------------------------------------------------------------------------

static func make_plan(seed_value: int) -> Plan:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "space_plan"])
	var p := Plan.new()
	p.size = Vector2i(Cfg.range_i(rng, "deck_width", 62, 68), Cfg.range_i(rng, "deck_height", 40, 46))
	var nv := Cfg.geti("vertical_corridors", 3)
	var nh := Cfg.geti("horizontal_corridors", 2)
	var cw := Cfg.get_arr("corridor_width", [2, 3])
	# Coursives verticales réparties sur la largeur (colonnes de blocs ≥ 12 cases).
	var widths: Array[int] = []
	for i in nv:
		widths.append(rng.randi_range(int(cw[0]), int(cw[1])))
	var main_h := rng.randi_range(0, nh - 1)
	var hwidths: Array[int] = []
	for j in nh:
		hwidths.append(3 if j == main_h else rng.randi_range(int(cw[0]), int(cw[1])))
	p.xs = _spread(rng, p.size.x, widths, 12)
	p.ys = _spread(rng, p.size.y, hwidths, 11)
	# Cages : 0↔1 dans les colonnes centrales (le pont 1 n'a que celles-là),
	# hors rangée nord (réservée à la passerelle) ; 0↔-1 ailleurs, hors hangar et baie.
	var up_cands: Array[Vector2i] = []
	for c in range(1, p.ncols() - 1):
		for r in range(1, p.nrows()):
			up_cands.append(Vector2i(c, r))
	p.up_block = up_cands[rng.randi_range(0, up_cands.size() - 1)]
	var down_cands: Array[Vector2i] = []
	for c2 in p.ncols():
		for r2 in p.nrows():
			var b := Vector2i(c2, r2)
			if b == p.up_block or b == hangar_block(p) or b == pod_block(p):
				continue
			if absi(b.x - p.up_block.x) + absi(b.y - p.up_block.y) < 2:
				continue
			down_cands.append(b)
	p.down_block = down_cands[rng.randi_range(0, down_cands.size() - 1)]
	p.up_left = _slice_left(p, p.up_block, rng)
	p.down_left = _slice_left(p, p.down_block, rng)
	p.up_cell = p.shaft_cell(p.up_block, p.up_left)
	p.down_cell = p.shaft_cell(p.down_block, p.down_left)
	return p


## Positions de coursives (x, w) réparties avec jitter ; segments ≥ min_seg.
static func _spread(rng: RandomNumberGenerator, total: int, widths: Array[int], min_seg: int) -> Array[Vector2i]:
	var n := widths.size()
	var sum_w := 0
	for w in widths:
		sum_w += w
	var free := total - sum_w
	var base := float(free) / float(n + 1)
	var out: Array[Vector2i] = []
	var pos := 0
	for i in n:
		var seg := int(round(base + rng.randf_range(-1.5, 1.5)))
		seg = maxi(seg, min_seg)
		var remaining_min := (n - i) * min_seg + _sum_from(widths, i + 1)
		seg = mini(seg, total - pos - widths[i] - remaining_min)
		out.append(Vector2i(pos + seg, widths[i]))
		pos += seg + widths[i]
	return out


static func _sum_from(a: Array[int], from: int) -> int:
	var s := 0
	for i in range(from, a.size()):
		s += a[i]
	return s


## La tranche d'une cage longe une coursive verticale intérieure.
static func _slice_left(p: Plan, b: Vector2i, rng: RandomNumberGenerator) -> bool:
	if b.x == 0:
		return false
	if b.x == p.ncols() - 1:
		return true
	return rng.randf() < 0.5


static func hangar_block(p: Plan) -> Vector2i:
	return Vector2i(0, p.nrows() / 2)


static func pod_block(p: Plan) -> Vector2i:
	return Vector2i(p.ncols() - 1, p.nrows() / 2)


# --- Pont ---------------------------------------------------------------------------

static func build(p: Plan, deck: int, seed_value: int) -> Deck:
	var attempts := Cfg.geti("deck_attempts", 16)
	for attempt in attempts:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "space_deck", deck, attempt])
		var d := _try_build(p, deck, rng, attempt >= attempts / 2)
		if d != null:
			if attempt > 0 and OS.is_debug_build() and OS.has_environment("SS_DEBUG"):
				print("SpaceStation: pont %d obtenu à la tentative %d" % [deck, attempt])
			return d
	push_error("SpaceStation: pont %d impossible à générer (seed %d)" % [deck, seed_value])
	return null


static func _active_cols(p: Plan, deck: int) -> Vector2i:
	if deck == DECK_COMMAND:
		return Vector2i(1, p.ncols() - 2)
	return Vector2i(0, p.ncols() - 1)


static func _hull_x(p: Plan, deck: int) -> Vector2i:
	if deck == DECK_COMMAND:
		var last := p.xs[p.xs.size() - 1]
		return Vector2i(p.xs[0].x - 1, last.x + last.y + 1)
	return Vector2i(0, p.size.x)


static func _try_build(p: Plan, deck: int, rng: RandomNumberGenerator, simple: bool) -> Deck:
	var L := FloorLayout.new(p.size)
	L.floor_index = deck
	var ac := _active_cols(p, deck)
	var hx := _hull_x(p, deck)
	var protected := {}
	if deck != DECK_MACHINES:
		protected[p.up_block] = true
	if deck != DECK_COMMAND:
		protected[p.down_block] = true
	if deck == DECK_MAIN:
		protected[hangar_block(p)] = true
		protected[pod_block(p)] = true

	# 1. Tronçons de coursive.
	var segs := _segments(p, ac)
	var merged := {}
	var merges: Array[Seg] = []
	if deck == DECK_COMMAND:
		# Passerelle : les deux blocs nord fusionnés si possible.
		for s in segs:
			if not s.horizontal and s.line == 1 and s.piece == 0 and s.inside and not protected.has(s.block_a) and not protected.has(s.block_b):
				_drop(s, segs, merged, merges)
	var chance := Cfg.getf("merge_chance", 0.35) * (0.0 if simple else 1.0)
	var order: Array[int] = []
	for i in segs.size():
		order.append(i)
	_shuffle(order, rng)
	for i2 in order:
		var s2 := segs[i2]
		if not s2.kept or not s2.inside:
			continue
		if protected.has(s2.block_a) or protected.has(s2.block_b) or merged.has(s2.block_a) or merged.has(s2.block_b):
			continue
		if not _in_cols(s2.block_a, ac) or not _in_cols(s2.block_b, ac):
			continue
		if rng.randf() >= chance:
			continue
		s2.kept = false
		if not _nodes_connected(p, segs, ac):
			s2.kept = true
			continue
		s2.kept = true
		_drop(s2, segs, merged, merges)

	# 2. Coursives creusées.
	var inner := Rect2i(maxi(hx.x + 1, 1), 1, mini(hx.y - 1, p.size.x - 1) - maxi(hx.x + 1, 1), p.size.y - 2)
	for s3 in segs:
		if s3.kept and s3.inside:
			L.fill_rect(s3.rect.intersection(inner), T.FLOOR)
	for i3 in p.xs.size():
		for j3 in p.ys.size():
			if i3 < ac.x - 1 or i3 > ac.y:
				continue
			L.fill_rect(Rect2i(p.xs[i3].x, p.ys[j3].x, p.xs[i3].y, p.ys[j3].y).intersection(inner), T.FLOOR)

	# 3. Régions (blocs fusionnés) → modules.
	var regions := _regions(p, ac, merges)
	var specs: Array[Spec] = []
	var plan_ok := _plan_rooms(p, deck, regions, specs, rng, simple)
	if not plan_ok:
		return null
	for sp in specs:
		if sp.corridor:
			continue
		L.fill_rect(sp.rect, T.WALL)
	for sp2 in specs:
		_carve_spec(L, sp2)
	_fence(L, hx)

	# 4. Escaliers / ascenseurs.
	match deck:
		DECK_MAIN:
			_add_stairs(L, p.up_cell, true, 1)
			_add_stairs(L, p.down_cell, false, -1)
		DECK_COMMAND:
			_add_stairs(L, p.up_cell, false, 0)
		DECK_MACHINES:
			_add_stairs(L, p.down_cell, true, 0)

	# 5. Salles (rooms) : modules puis coursives.
	for sp3 in specs:
		if sp3.corridor:
			continue
		var r := sp3.rect.grow(-1)
		if sp3.open_side >= 0:
			r = r.grow_side([SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM][sp3.open_side], 1)
		sp3.room = L.add_room(r, false, sp3.type, sp3.name)
		sp3.room.tags.append(String(sp3.role))
		if sp3.round:
			sp3.room.tags.append("round")
		if sp3.open_side >= 0:
			sp3.room.tags.append("open")
	_corridor_rooms(L, p, deck, segs, ac, inner, specs)

	# 6. Portes.
	if not _connect(L, specs, rng):
		return null

	# 7. Point d'apparition, extraction.
	_spawn_and_extraction(L, p, deck, specs)
	if not _validate(L, specs):
		return null
	var d := Deck.new()
	d.layout = L
	d.specs = specs
	return d


static func _in_cols(b: Vector2i, ac: Vector2i) -> bool:
	return b.x >= ac.x and b.x <= ac.y


static func _shuffle(a: Array[int], rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


static func _drop(s: Seg, _segs: Array[Seg], merged: Dictionary, merges: Array[Seg]) -> void:
	s.kept = false
	merged[s.block_a] = true
	merged[s.block_b] = true
	merges.append(s)


static func _segments(p: Plan, ac: Vector2i) -> Array[Seg]:
	var out: Array[Seg] = []
	var nv := p.xs.size()
	var nh := p.ys.size()
	for j in nh:
		for k in nv + 1:
			var cs := p.col_span(k)
			var s := Seg.new()
			s.horizontal = true
			s.line = j
			s.piece = k
			s.rect = Rect2i(cs.x, p.ys[j].x, cs.y - cs.x, p.ys[j].y)
			s.block_a = Vector2i(k, j)
			s.block_b = Vector2i(k, j + 1)
			if k > 0:
				s.node_a = Vector2i(k - 1, j)
			if k < nv:
				s.node_b = Vector2i(k, j)
			s.inside = _in_cols(s.block_a, ac)
			out.append(s)
	for i in nv:
		for r in nh + 1:
			var rs := p.row_span(r)
			var s2 := Seg.new()
			s2.horizontal = false
			s2.line = i
			s2.piece = r
			s2.rect = Rect2i(p.xs[i].x, rs.x, p.xs[i].y, rs.y - rs.x)
			s2.block_a = Vector2i(i, r)
			s2.block_b = Vector2i(i + 1, r)
			if r > 0:
				s2.node_a = Vector2i(i, r - 1)
			if r < nh:
				s2.node_b = Vector2i(i, r)
			s2.inside = i >= ac.x - 1 and i <= ac.y
			out.append(s2)
	return out


## Les intersections de la coque restent reliées par les tronçons conservés.
static func _nodes_connected(p: Plan, segs: Array[Seg], ac: Vector2i) -> bool:
	var nodes: Array[Vector2i] = []
	for i in p.xs.size():
		if i < ac.x - 1 or i > ac.y:
			continue
		for j in p.ys.size():
			nodes.append(Vector2i(i, j))
	if nodes.is_empty():
		return true
	var adj := {}
	for s in segs:
		if not s.kept or not s.inside or s.node_a.x < 0 or s.node_b.x < 0:
			continue
		if not adj.has(s.node_a):
			adj[s.node_a] = []
		if not adj.has(s.node_b):
			adj[s.node_b] = []
		(adj[s.node_a] as Array).append(s.node_b)
		(adj[s.node_b] as Array).append(s.node_a)
	var seen := {nodes[0]: true}
	var stack: Array[Vector2i] = [nodes[0]]
	while not stack.is_empty():
		var n: Vector2i = stack.pop_back()
		for m: Vector2i in adj.get(n, []):
			if not seen.has(m):
				seen[m] = true
				stack.append(m)
	return seen.size() == nodes.size()


## Régions : [rect murs compris, blocs] (fusions comprises).
static func _regions(p: Plan, ac: Vector2i, merges: Array[Seg]) -> Array:
	var used := {}
	var out: Array = []
	for s in merges:
		var r := p.block_rect(s.block_a).merge(p.block_rect(s.block_b))
		out.append([r, [s.block_a, s.block_b]])
		used[s.block_a] = true
		used[s.block_b] = true
	for c in range(ac.x, ac.y + 1):
		for r2 in p.nrows():
			var b := Vector2i(c, r2)
			if not used.has(b):
				out.append([p.block_rect(b), [b]])
	# Ordre déterministe (haut-gauche d'abord).
	out.sort_custom(func(a: Array, b2: Array) -> bool:
		var ra: Rect2i = a[0]
		var rb: Rect2i = b2[0]
		return ra.position.y * 1000 + ra.position.x < rb.position.y * 1000 + rb.position.x)
	return out


# --- Programme des salles -------------------------------------------------------------

static func _region_has(region: Array, b: Vector2i) -> bool:
	return (region[1] as Array).has(b)


static func _plan_rooms(p: Plan, deck: int, regions: Array, specs: Array[Spec], rng: RandomNumberGenerator, simple: bool) -> bool:
	var leaves: Array[Spec] = []       ## Modules « libres » (rôle à attribuer)
	var reactor_region := -1
	if deck == DECK_MACHINES:
		# Réacteur : la plus grande région sans cage (fusionnée de préférence).
		var best := -1
		for i in regions.size():
			var reg: Array = regions[i]
			if _region_has(reg, p.down_block) or _region_has(reg, p.up_block):
				continue
			var a := (reg[0] as Rect2i).get_area() + (1000 if (reg[1] as Array).size() > 1 else 0)
			if a > best:
				best = a
				reactor_region = i
	for i2 in regions.size():
		var reg2: Array = regions[i2]
		var rect: Rect2i = reg2[0]
		if deck == DECK_MAIN and _region_has(reg2, hangar_block(p)):
			specs.append(_spec(rect, &"hangar", FloorLayout.ROOM_SPAWN))
			specs[-1].open_side = 1
			continue
		if deck == DECK_MAIN and _region_has(reg2, pod_block(p)):
			specs.append(_spec(rect, &"pod_bay", FloorLayout.ROOM_EXTRACTION))
			continue
		if deck == DECK_COMMAND and _region_has(reg2, Vector2i(1, 0)) and not _region_has(reg2, p.up_block):
			specs.append(_spec(rect, &"bridge", FloorLayout.ROOM_COMBAT))
			continue
		if i2 == reactor_region:
			var rs := _spec(rect, &"reactor", FloorLayout.ROOM_BOSS)
			rs.round = true
			specs.append(rs)
			continue
		var shaft_b := Vector2i(-1, -1)
		var left := true
		if (deck == DECK_MAIN or deck == DECK_COMMAND) and _region_has(reg2, p.up_block):
			shaft_b = p.up_block
			left = p.up_left
		elif (deck == DECK_MAIN or deck == DECK_MACHINES) and _region_has(reg2, p.down_block):
			shaft_b = p.down_block
			left = p.down_left
		var rest := rect
		if shaft_b.x >= 0:
			var slice := p.shaft_slice(shaft_b, left)
			var cab := p.shaft_rect(shaft_b, left)
			specs.append(_spec(cab, &"elevator", FloorLayout.ROOM_REST))
			if slice.size.y - 4 >= MIN_ROOM:
				leaves.append(_spec(Rect2i(slice.position.x, cab.end.y - 1, 5, slice.end.y - cab.end.y + 1), &"closet", FloorLayout.ROOM_LOOT))
			else:
				return false
			rest = Rect2i(slice.end.x - 1, rect.position.y, rect.end.x - slice.end.x + 1, rect.size.y) if left \
				else Rect2i(rect.position.x, rect.position.y, slice.position.x - rect.position.x + 1, rect.size.y)
		# Conduit de service traversant (plus fréquent en salle des machines).
		var cchance := Cfg.getf("conduit_chance_machines", 0.6) if deck == DECK_MACHINES else Cfg.getf("conduit_chance", 0.15)
		if not simple and shaft_b.x < 0 and rng.randf() < cchance:
			if _split_conduit(p, deck, rest, reg2, specs, leaves, rng):
				continue
		_bsp(rest, leaves, rng, 0)
	_assign_roles(deck, leaves, rng)
	for lf in leaves:
		specs.append(lf)
	# Salles scellées (super_loot) : au plus une par pont.
	var key := &""
	var vault_role := &""
	var vault_chance := 0.0
	match deck:
		DECK_MAIN:
			key = KEY_LAB
			vault_role = &"lab_vault"
			vault_chance = Cfg.getf("vault_chance_main", 0.6)
		DECK_COMMAND:
			key = KEY_ARMORY
			vault_role = &"armory"
			vault_chance = Cfg.getf("vault_chance_command", 1.0)
		DECK_MACHINES:
			key = KEY_REACTOR
			vault_role = &"core_vault"
			vault_chance = Cfg.getf("vault_chance_machines", 0.85)
	if rng.randf() < vault_chance:
		var best_i := -1
		var best_a := 1 << 30
		for i3 in leaves.size():
			var lf2 := leaves[i3]
			if lf2.role == &"closet" or lf2.type == FloorLayout.ROOM_EXTRACTION:
				continue
			var a2 := lf2.rect.get_area() + rng.randi_range(0, 20)
			if a2 < best_a:
				best_a = a2
				best_i = i3
		if best_i >= 0:
			var v := leaves[best_i]
			v.role = vault_role
			v.type = FloorLayout.ROOM_SUPER_LOOT
			v.key = key
			v.round = false
			v.name = String(ROLE_NAMES[vault_role])
	return true


static func _spec(rect: Rect2i, role: StringName, type: StringName) -> Spec:
	var s := Spec.new()
	s.rect = rect
	s.role = role
	s.type = type
	s.name = String(ROLE_NAMES.get(role, String(role)))
	return s


## Découpe BSP (murs partagés) : modules de MIN_ROOM cases au moins, ~1 module / 90 cases.
static func _bsp(r: Rect2i, out: Array[Spec], rng: RandomNumberGenerator, depth: int) -> void:
	var target := Cfg.getf("room_area_target", 95.0)
	var can_x := r.size.x >= MIN_ROOM * 2 - 1
	var can_y := r.size.y >= MIN_ROOM * 2 - 1
	var split := (can_x or can_y) and (float(r.get_area()) > target * 1.3 or (depth == 0 and rng.randf() < 0.5)) and depth < 4
	if not split:
		out.append(_spec(r, &"", FloorLayout.ROOM_COMBAT))
		return
	var along_x := can_x and (not can_y or r.size.x > r.size.y or (r.size.x == r.size.y and rng.randf() < 0.5))
	if along_x:
		var s := rng.randi_range(r.position.x + MIN_ROOM - 1, r.end.x - MIN_ROOM)
		_bsp(Rect2i(r.position.x, r.position.y, s - r.position.x + 1, r.size.y), out, rng, depth + 1)
		_bsp(Rect2i(s, r.position.y, r.end.x - s, r.size.y), out, rng, depth + 1)
	else:
		var s2 := rng.randi_range(r.position.y + MIN_ROOM - 1, r.end.y - MIN_ROOM)
		_bsp(Rect2i(r.position.x, r.position.y, r.size.x, s2 - r.position.y + 1), out, rng, depth + 1)
		_bsp(Rect2i(r.position.x, s2, r.size.x, r.end.y - s2), out, rng, depth + 1)


## Conduit de 2 cases traversant la région d'une coursive à l'autre.
static func _split_conduit(p: Plan, _deck: int, rect: Rect2i, reg: Array, specs: Array[Spec], leaves: Array[Spec], rng: RandomNumberGenerator) -> bool:
	var top_open := rect.position.y > 0
	var bottom_open := rect.end.y < p.size.y
	var left_open := rect.position.x > 0 and rect.position.x > p.xs[0].x - 2
	var right_open := rect.end.x < p.size.x
	var vertical := top_open and bottom_open and rect.size.x >= MIN_ROOM * 2 + 2
	var horizontal := left_open and right_open and rect.size.y >= MIN_ROOM * 2 + 2
	if (reg[1] as Array).size() > 1 and rng.randf() < 0.5:
		vertical = vertical and rect.size.x > rect.size.y
	if not vertical and not horizontal:
		return false
	if vertical and horizontal:
		if rng.randf() < 0.5:
			horizontal = false
		else:
			vertical = false
	var c := Spec.new()
	c.corridor = true
	c.role = &"conduit"
	c.type = FloorLayout.ROOM_CORRIDOR
	c.name = String(ROLE_NAMES[&"conduit"])
	if vertical:
		var x := rng.randi_range(rect.position.x + MIN_ROOM - 1, rect.end.x - MIN_ROOM - 3)
		c.rect = Rect2i(x, rect.position.y, 4, rect.size.y)
		_bsp(Rect2i(rect.position.x, rect.position.y, x - rect.position.x + 1, rect.size.y), leaves, rng, 1)
		_bsp(Rect2i(x + 3, rect.position.y, rect.end.x - x - 3, rect.size.y), leaves, rng, 1)
	else:
		var y := rng.randi_range(rect.position.y + MIN_ROOM - 1, rect.end.y - MIN_ROOM - 3)
		c.rect = Rect2i(rect.position.x, y, rect.size.x, 4)
		_bsp(Rect2i(rect.position.x, rect.position.y, rect.size.x, y - rect.position.y + 1), leaves, rng, 1)
		_bsp(Rect2i(rect.position.x, y + 3, rect.size.x, rect.end.y - y - 3), leaves, rng, 1)
	specs.append(c)
	return true


## Rôles des modules libres : rôles obligatoires d'abord (plus grands modules), puis tirage.
static func _assign_roles(deck: int, leaves: Array[Spec], rng: RandomNumberGenerator) -> void:
	var required: Array[StringName] = []
	var pool: Dictionary = {}
	match deck:
		DECK_MAIN:
			required = [&"mess_hall", &"infirmary", &"lab", &"quarters"]
			pool = {&"quarters": 3.0, &"storage": 2.0, &"hydroponics": 1.2, &"workshop": 1.0, &"lab": 0.4, &"server_room": 0.8, &"infirmary": 0.3, &"mess_hall": 0.3}
		DECK_COMMAND:
			required = [&"radar", &"officer_quarters", &"briefing", &"captain_cabin"]
			pool = {&"officer_quarters": 3.0, &"comms": 1.5, &"observatory": 1.2, &"server_room": 1.0, &"briefing": 0.5}
		_:
			required = [&"generator", &"pumps", &"workshop", &"cargo_hold"]
			pool = {&"storage": 3.0, &"coolant": 2.0, &"pumps": 1.0, &"generator": 1.0, &"cargo_hold": 1.5, &"workshop": 1.0}
	# Extraction optionnelle sur les ponts 1 et -1.
	var pod_chance := Cfg.getf("pod_chance_command", 0.4) if deck == DECK_COMMAND else Cfg.getf("pod_chance_machines", 0.5)
	var extra_pod := deck != DECK_MAIN and rng.randf() < pod_chance
	var free: Array[Spec] = []
	for lf in leaves:
		if lf.role == &"":
			free.append(lf)
	free.sort_custom(func(a: Spec, b: Spec) -> bool:
		if a.rect.get_area() != b.rect.get_area():
			return a.rect.get_area() > b.rect.get_area()
		return a.rect.position.y * 1000 + a.rect.position.x < b.rect.position.y * 1000 + b.rect.position.x)
	var idx := 0
	if extra_pod and free.size() > required.size() + 1:
		# Capsule : un module moyen (le dernier des grands).
		var pi := mini(required.size(), free.size() - 1)
		var pod := free[pi]
		pod.role = &"command_pod" if deck == DECK_COMMAND else &"maintenance_pod"
		pod.type = FloorLayout.ROOM_EXTRACTION
		free.remove_at(pi)
	for role: StringName in required:
		if idx >= free.size():
			break
		free[idx].role = role
		idx += 1
	for i in range(idx, free.size()):
		free[i].role = _weighted(pool, rng)
	var tw := Cfg.get_dict("room_type_weights", {"combat": 4.0, "loot": 3.0, "trap": 1.5, "rest": 1.0})
	for lf2 in leaves:
		if lf2.type == FloorLayout.ROOM_EXTRACTION:
			lf2.name = String(ROLE_NAMES[lf2.role])
			continue
		match lf2.role:
			&"closet", &"storage", &"cargo_hold":
				lf2.type = FloorLayout.ROOM_LOOT if rng.randf() < 0.7 else FloorLayout.ROOM_COMBAT
			&"mess_hall", &"briefing", &"workshop":
				lf2.type = FloorLayout.ROOM_COMBAT
			&"infirmary", &"observatory":
				lf2.type = FloorLayout.ROOM_REST if rng.randf() < 0.5 else FloorLayout.ROOM_LOOT
			&"coolant", &"pumps":
				lf2.type = FloorLayout.ROOM_TRAP if rng.randf() < 0.6 else FloorLayout.ROOM_COMBAT
			_:
				lf2.type = StringName(_weighted(tw, rng))
		lf2.name = String(ROLE_NAMES.get(lf2.role, String(lf2.role)))
		lf2.round = ROUND_ROLES.has(lf2.role) and rng.randf() < float(ROUND_ROLES[lf2.role]) \
			and lf2.rect.size.x >= 9 and lf2.rect.size.y >= 9
	# Plusieurs modules du même rôle : lettres A, B, C… dans l'ordre de lecture.
	var by_role := {}
	for lf3 in leaves:
		if not by_role.has(lf3.role):
			by_role[lf3.role] = []
		(by_role[lf3.role] as Array).append(lf3)
	for role2: StringName in by_role:
		var lst: Array = by_role[role2]
		if lst.size() < 2:
			continue
		lst.sort_custom(func(a: Spec, b: Spec) -> bool:
			return a.rect.position.y * 1000 + a.rect.position.x < b.rect.position.y * 1000 + b.rect.position.x)
		for k in lst.size():
			(lst[k] as Spec).name = "%s %s" % [(lst[k] as Spec).name, "ABCDEFGHIJKLMNOP"[mini(k, 15)]]


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


# --- Creusement ------------------------------------------------------------------------

static func _carve_spec(L: FloorLayout, s: Spec) -> void:
	if s.corridor:
		# Conduit : murs latéraux + sol, prolongé jusqu'aux coursives aux deux bouts.
		var inner := s.rect.grow(-1)
		if s.rect.size.x == 4:
			inner = Rect2i(s.rect.position.x + 1, s.rect.position.y, 2, s.rect.size.y)
			L.fill_rect(Rect2i(s.rect.position.x, s.rect.position.y, 1, s.rect.size.y), T.WALL)
			L.fill_rect(Rect2i(s.rect.end.x - 1, s.rect.position.y, 1, s.rect.size.y), T.WALL)
		else:
			inner = Rect2i(s.rect.position.x, s.rect.position.y + 1, s.rect.size.x, 2)
			L.fill_rect(Rect2i(s.rect.position.x, s.rect.position.y, s.rect.size.x, 1), T.WALL)
			L.fill_rect(Rect2i(s.rect.position.x, s.rect.end.y - 1, s.rect.size.x, 1), T.WALL)
		L.fill_rect(inner, T.FLOOR)
		return
	var r := s.rect.grow(-1)
	if not s.round:
		L.fill_rect(r, T.FLOOR)
	else:
		var k := float(mini(r.size.x, r.size.y)) / 3.4
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var dx := mini(x - r.position.x, r.end.x - 1 - x)
				var dy := mini(y - r.position.y, r.end.y - 1 - y)
				if float(dx + dy) + 0.5 >= k:
					L.set_tile(Vector2i(x, y), T.FLOOR)
	if s.open_side >= 0:
		# Large ouverture (hangar) : toute la hauteur utile du côté, sauf les coins.
		var x0 := s.rect.position.x if s.open_side == 0 else s.rect.end.x - 1
		var cy := r.get_center().y
		for y2 in range(cy - 1, cy + 2):
			L.set_tile(Vector2i(x0, y2), T.FLOOR)


## Toute case VOID voisine (8) d'une case marchable devient un mur ; bord de grille et
## hors coque jamais marchables.
static func _fence(L: FloorLayout, hx: Vector2i) -> void:
	var w := L.size.x
	var h := L.size.y
	var tiles := L.tiles
	for y in h:
		for x in w:
			var i := y * w + x
			var t := tiles[i]
			if (x < hx.x or x >= hx.y or x == 0 or y == 0 or x == w - 1 or y == h - 1) and t != T.VOID and t != T.WALL:
				tiles[i] = T.WALL
	var src := tiles.duplicate()
	for y2 in range(1, h - 1):
		for x2 in range(1, w - 1):
			var t2 := src[y2 * w + x2]
			if t2 == T.VOID or t2 == T.WALL:
				continue
			for j: int in [(y2 - 1) * w + x2 - 1, (y2 - 1) * w + x2, (y2 - 1) * w + x2 + 1, y2 * w + x2 - 1,
					y2 * w + x2 + 1, (y2 + 1) * w + x2 - 1, (y2 + 1) * w + x2, (y2 + 1) * w + x2 + 1]:
				if tiles[j] == T.VOID:
					tiles[j] = T.WALL
	L.tiles = tiles


static func _add_stairs(L: FloorLayout, cell: Vector2i, up: bool, target: int) -> void:
	L.set_tile(cell, T.STAIRS_UP if up else T.STAIRS_DOWN)
	var st := FloorLayout.Stairs.new()
	st.cell = cell
	st.up = up
	st.target_floor = target
	st.target_cell = cell
	L.stairs.append(st)


## Une salle par série continue de coursive (lignes horizontales intersections comprises,
## tronçons verticaux entre deux intersections), + conduits.
static func _corridor_rooms(L: FloorLayout, p: Plan, deck: int, segs: Array[Seg], ac: Vector2i, inner: Rect2i, specs: Array[Spec]) -> void:
	var hnames := ["Coursive nord", "Coursive centrale", "Coursive sud", "Coursive basse"]
	var vnames := ["Coursive transversale ouest", "Coursive transversale centrale", "Coursive transversale est", "Coursive transversale 4"]
	var prefix := "Galerie" if deck == DECK_MACHINES else ""
	for j in p.ys.size():
		var run := Rect2i()
		var has := false
		for k in p.xs.size() + 1:
			var s := _find_seg(segs, true, j, k)
			var r := s.rect.intersection(inner) if s.kept and s.inside else Rect2i()
			if r.size.x > 0:
				run = r if not has else run.merge(r)
				has = true
			if k < p.xs.size() and k >= ac.x - 1 and k <= ac.y:
				var node := Rect2i(p.xs[k].x, p.ys[j].x, p.xs[k].y, p.ys[j].y).intersection(inner)
				run = node if not has else run.merge(node)
				has = true
			var next_ok := k < p.xs.size() and _find_seg(segs, true, j, k + 1).kept and _find_seg(segs, true, j, k + 1).inside
			if has and not next_ok:
				var nm: String = hnames[mini(j + (1 if p.ys.size() == 2 and j == 1 else 0), 3)]
				if prefix != "":
					nm = nm.replace("Coursive", prefix)
				var room := L.add_room(run, false, FloorLayout.ROOM_CORRIDOR, nm)
				room.tags.append("corridor")
				room.tags.append("h")
				has = false
	for i in p.xs.size():
		for r2 in p.ys.size() + 1:
			var s2 := _find_seg(segs, false, i, r2)
			if not s2.kept or not s2.inside:
				continue
			var rr := s2.rect.intersection(inner)
			if rr.size.y <= 0 or rr.size.x <= 0:
				continue
			var nm2: String = vnames[mini(i, 3)]
			if prefix != "":
				nm2 = nm2.replace("Coursive", prefix)
			var room2 := L.add_room(rr, false, FloorLayout.ROOM_CORRIDOR, nm2)
			room2.tags.append("corridor")
			room2.tags.append("v")
	for sp in specs:
		if sp.corridor:
			var cr := Rect2i(sp.rect.position.x + 1, sp.rect.position.y, 2, sp.rect.size.y) if sp.rect.size.x == 4 \
				else Rect2i(sp.rect.position.x, sp.rect.position.y + 1, sp.rect.size.x, 2)
			sp.room = L.add_room(cr, false, FloorLayout.ROOM_CORRIDOR, sp.name)
			sp.room.tags.append("conduit")
			sp.room.tags.append("corridor")


static func _find_seg(segs: Array[Seg], horizontal: bool, line: int, piece: int) -> Seg:
	for s in segs:
		if s.horizontal == horizontal and s.line == line and s.piece == piece:
			return s
	return segs[0]


# --- Portes ------------------------------------------------------------------------------

## Relie toutes les salles au réseau de coursives (unité 0).
static func _connect(L: FloorLayout, specs: Array[Spec], rng: RandomNumberGenerator) -> bool:
	var w := L.size.x
	var h := L.size.y
	var tiles := L.tiles
	var unit := PackedInt32Array()
	unit.resize(w * h)
	unit.fill(-1)
	var rooms: Array[Spec] = []
	for sp in specs:
		if sp.corridor:
			continue
		rooms.append(sp)
		sp.unit = rooms.size()
		var r := sp.rect.grow(-1)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var tt := tiles[y * w + x]
				if tt != T.VOID and tt != T.WALL:
					unit[y * w + x] = sp.unit
	for i in w * h:
		if unit[i] < 0 and tiles[i] != T.VOID and tiles[i] != T.WALL:
			unit[i] = 0
	# Candidats : case mur entre deux unités différentes, alignée dans un mur droit.
	var groups := {}   ## "a:b" (a < b) → Array de [cell, vertical]
	for y2 in range(1, h - 1):
		for x2 in range(1, w - 1):
			var i2 := y2 * w + x2
			if tiles[i2] != T.WALL:
				continue
			var l := unit[i2 - 1]
			var rt := unit[i2 + 1]
			var up := unit[i2 - w]
			var dn := unit[i2 + w]
			if l >= 0 and rt >= 0 and l != rt and tiles[i2 - w] == T.WALL and tiles[i2 + w] == T.WALL:
				_add_cand(groups, l, rt, Vector2i(x2, y2), true)
			elif up >= 0 and dn >= 0 and up != dn and tiles[i2 - 1] == T.WALL and tiles[i2 + 1] == T.WALL:
				_add_cand(groups, up, dn, Vector2i(x2, y2), false)
	var stairs := {}
	for st in L.stairs:
		stairs[st.cell] = true
	# Index unité → groupes qui la concernent (ordre déterministe).
	var keys: Array = groups.keys()
	keys.sort()
	var unit_keys := {}
	for key: String in keys:
		var parts := key.split(":")
		for part: String in parts:
			var u := int(part)
			if not unit_keys.has(u):
				unit_keys[u] = []
			(unit_keys[u] as Array).append(key)
	groups["__units"] = unit_keys
	var door_cells := {}
	var connected := {0: true}
	var by_unit := {}
	for sp2 in rooms:
		by_unit[sp2.unit] = sp2
	var pending: Array[Spec] = []
	for sp3 in rooms:
		if sp3.type != FloorLayout.ROOM_SUPER_LOOT:
			pending.append(sp3)
	# Les ouvertures (hangar) sont déjà creusées : unité reliée d'office.
	for sp4 in rooms:
		if sp4.open_side >= 0:
			connected[sp4.unit] = true
			pending.erase(sp4)
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for sp5 in pending.duplicate():
			var target := _pick_group(groups, sp5.unit, connected, by_unit, door_cells, stairs, false)
			if target.is_empty():
				continue
			_place_door(L, sp5, target, by_unit, door_cells, rng, FloorLayout.DoorState.CLOSED, &"")
			connected[sp5.unit] = true
			pending.erase(sp5)
			progress = true
	if not pending.is_empty():
		return false
	# Salles scellées : une seule porte, verrouillée.
	for sp6 in rooms:
		if sp6.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		var tg := _pick_group(groups, sp6.unit, connected, by_unit, door_cells, stairs, false)
		if tg.is_empty():
			return false
		_place_door(L, sp6, tg, by_unit, door_cells, rng, FloorLayout.DoorState.LOCKED, sp6.key)
	# Portes supplémentaires (boucles), jamais vers une salle scellée ou le réacteur.
	var extra := Cfg.getf("extra_door_chance", 0.35)
	for sp7 in rooms:
		if sp7.type == FloorLayout.ROOM_SUPER_LOOT or sp7.type == FloorLayout.ROOM_BOSS or sp7.role == &"elevator":
			continue
		if rng.randf() >= extra:
			continue
		var tg2 := _pick_group(groups, sp7.unit, connected, by_unit, door_cells, stairs, true)
		if not tg2.is_empty():
			_place_door(L, sp7, tg2, by_unit, door_cells, rng, FloorLayout.DoorState.CLOSED, &"")
	return true


static func _add_cand(groups: Dictionary, a: int, b: int, c: Vector2i, vertical: bool) -> void:
	var key := "%d:%d" % [mini(a, b), maxi(a, b)]
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append([c, vertical])


## Groupe de candidats reliant `u` à une unité déjà reliée (coursive de préférence).
## `extra` : l'unité ne doit pas déjà avoir de porte vers la cible.
static func _pick_group(groups: Dictionary, u: int, connected: Dictionary, by_unit: Dictionary, door_cells: Dictionary, stairs: Dictionary, extra: bool) -> Dictionary:
	var best := {}
	var best_score := -1.0
	var keys: Array = (groups["__units"] as Dictionary).get(u, [])
	for key: String in keys:
		var parts := key.split(":")
		var a := int(parts[0])
		var b := int(parts[1])
		if a != u and b != u:
			continue
		var v := b if a == u else a
		if not connected.has(v):
			continue
		if v > 0:
			var other: Spec = by_unit[v]
			if other.type == FloorLayout.ROOM_SUPER_LOOT or other.type == FloorLayout.ROOM_BOSS or other.role == &"elevator":
				continue
		var spec_u: Spec = by_unit[u]
		if spec_u.role == &"elevator" and v > 0:
			continue
		var cands: Array = []
		var already := false
		for c: Array in groups[key]:
			var cell: Vector2i = c[0]
			if door_cells.has(cell):
				already = true
			if _door_ok(cell, door_cells, stairs):
				cands.append(c)
		if cands.is_empty() or (extra and already):
			continue
		var score := float(cands.size()) + (100.0 if v == 0 else 0.0)
		if spec_u.type == FloorLayout.ROOM_SUPER_LOOT or spec_u.type == FloorLayout.ROOM_BOSS:
			score += 0.0
		if score > best_score:
			best_score = score
			best = {"v": v, "cands": cands}
	return best


static func _door_ok(cell: Vector2i, door_cells: Dictionary, stairs: Dictionary) -> bool:
	if not door_cells.is_empty():
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if door_cells.has(cell + Vector2i(dx, dy)):
					return false
	for st: Vector2i in stairs:
		if absi(st.x - cell.x) + absi(st.y - cell.y) <= 1:
			return false
	return true


static func _place_door(L: FloorLayout, sp: Spec, target: Dictionary, by_unit: Dictionary, door_cells: Dictionary, rng: RandomNumberGenerator, state: int, key: StringName) -> void:
	var cands: Array = target["cands"]
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		var ca: Vector2i = a[0]
		var cb: Vector2i = b[0]
		return ca.x + ca.y * 1000 < cb.x + cb.y * 1000)
	var mid := cands.size() / 2
	var j := clampi(mid + rng.randi_range(-1, 1), 0, cands.size() - 1)
	var c: Array = cands[j]
	var cell: Vector2i = c[0]
	var v: int = target["v"]
	var other_id := -1
	if v > 0:
		var o: Spec = by_unit[v]
		other_id = o.room.id
	else:
		var probe := cell + (Vector2i.LEFT if bool(c[1]) else Vector2i.UP)
		var rr := L.room_at(probe)
		if rr == null or rr.id == sp.room.id:
			rr = L.room_at(cell + (Vector2i.RIGHT if bool(c[1]) else Vector2i.DOWN))
		other_id = rr.id if rr != null else -1
	L.add_door(cell, bool(c[1]), state, sp.room.id, other_id, key)
	door_cells[cell] = true


# --- Apparition, extraction, validation ---------------------------------------------------

static func _spawn_and_extraction(L: FloorLayout, p: Plan, deck: int, specs: Array[Spec]) -> void:
	match deck:
		DECK_MAIN:
			for sp in specs:
				if sp.role == &"hangar":
					var r := sp.rect.grow(-1)
					L.player_spawn = Vector2i(r.position.x + 1, r.get_center().y)
		DECK_COMMAND:
			L.player_spawn = p.up_cell + Vector2i.DOWN
		_:
			L.player_spawn = p.down_cell + Vector2i.DOWN
	for sp2 in specs:
		if sp2.type != FloorLayout.ROOM_EXTRACTION:
			continue
		var r2 := sp2.rect.grow(-1)
		var c := r2.get_center()
		var x0 := r2.end.x - 3 if sp2.role == &"pod_bay" else c.x - 1
		for dy in [-1, 0]:
			for dx in [0, 1]:
				var cell := Vector2i(x0 + dx, c.y + dy)
				if L.get_tile(cell) == T.FLOOR and not L.extraction_cells.has(cell):
					L.extraction_cells.append(cell)


static func _validate(L: FloorLayout, specs: Array[Spec]) -> bool:
	if not FloorLayout.is_walkable_tile(L.get_tile(L.player_spawn)):
		return false
	var w := L.size.x
	var reach := _flood(L, L.player_spawn, true)
	var tiles := L.tiles
	for i in tiles.size():
		var t := tiles[i]
		if t != T.VOID and t != T.WALL and reach[i] == 0:
			return false
	var open_reach := _flood(L, L.player_spawn, false)
	for sp in specs:
		if sp.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		var r := sp.rect.grow(-1)
		for y2 in range(r.position.y, r.end.y):
			for x2 in range(r.position.x, r.end.x):
				if open_reach[y2 * w + x2] != 0:
					return false
	return true


## Remplissage rapide (tableau d'octets) ; portes verrouillées franchies si `through_locked`.
static func _flood(L: FloorLayout, from: Vector2i, through_locked: bool) -> PackedByteArray:
	var w := L.size.x
	var tiles := L.tiles
	var n := tiles.size()
	# Praticable : 1 ; porte verrouillée bloquante : 0 si on ne les franchit pas.
	var ok := PackedByteArray()
	ok.resize(n)
	for i in n:
		var t := tiles[i]
		ok[i] = 1 if (t != T.VOID and t != T.WALL) else 0
	if not through_locked:
		for d in L.doors:
			if d.state == FloorLayout.DoorState.LOCKED:
				ok[d.cell.y * w + d.cell.x] = 0
	var seen := PackedByteArray()
	seen.resize(n)
	var stack := PackedInt32Array()
	stack.resize(n)
	var top := 0
	var start := from.y * w + from.x
	stack[0] = start
	top = 1
	seen[start] = 1
	while top > 0:
		top -= 1
		var i2 := stack[top]
		var j := i2 - 1
		if j >= 0 and seen[j] == 0 and ok[j] == 1:
			seen[j] = 1
			stack[top] = j
			top += 1
		j = i2 + 1
		if j < n and seen[j] == 0 and ok[j] == 1:
			seen[j] = 1
			stack[top] = j
			top += 1
		j = i2 - w
		if j >= 0 and seen[j] == 0 and ok[j] == 1:
			seen[j] = 1
			stack[top] = j
			top += 1
		j = i2 + w
		if j < n and seen[j] == 0 and ok[j] == 1:
			seen[j] = 1
			stack[top] = j
			top += 1
	return seen
