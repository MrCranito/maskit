extends RefCounted
## Rez-de-chaussée (0) d'une ville Far West et étage (1) des bâtiments à étage.
##
## Étage 0 : une rue principale horizontale (couloir extérieur de 5-7 cases),
## bordée au nord et au sud par des rangées de bâtiments dont la façade touche
## la rue. Entre deux bâtiments : ruelles (couloirs extérieurs de 3-4 cases)
## qui mènent à une petite place derrière la rangée, ou placettes ouvertes sur
## la rue. Les intérieurs ne sont accessibles que par des portes.
## Étage 1 : uniquement les étages des bâtiments qui en ont (saloon, hôtel),
## même emprise ; le reste de la grille est VOID.
##
## Toutes les salles reçoivent dans `tags[0]` leur rôle d'ameublement
## (ex. "saloon_hall", "street", "alley") ; tags[1] = archétype ou "outdoor".

const Cfg := preload("res://scripts/dungeon/gen/gen_config.gd")
const Tpl := preload("res://scripts/dungeon/gen/building_templates.gd")
const T := FloorLayout.Tile


## Résultat de la génération de l'étage 0 (structure, sans spawns).
class TownResult:
	var layout: FloorLayout
	## Bâtiments à étage : { building_id, plan (Plan), origin (Vector2i), flip_x, flip_y }.
	var upper_specs: Array[Dictionary] = []
	## Cases des escaliers descendant vers la mine.
	var mine_stairs: Array[Vector2i] = []


class Slot:
	var kind: StringName      ## &"building", &"alley", &"notch"
	var width: int
	var plan: Tpl.Plan
	var gap_after: int = 0


static func build(seed_value: int, world: WorldData) -> TownResult:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "town"])
	var want_upper := world.floors_max >= 1
	var want_mine := world.floors_min <= -1

	# --- Choix des bâtiments ---------------------------------------------
	var required: Array[StringName] = []
	for a: StringName in [&"saloon", &"bank", &"sheriff", &"mine"]:
		if world.has_archetype(a) and (a != &"mine" or want_mine):
			required.append(a)
	var optional: Array[StringName] = []
	for a2: StringName in world.building_archetypes:
		if not required.has(a2) and a2 != &"mine":
			optional.append(a2)
	var n := Cfg.range_i(rng, "buildings_min", "buildings_max", 5, 8)
	var chosen: Array[StringName] = required.duplicate()
	var pool := optional.duplicate()
	_shuffle(pool, rng)
	while chosen.size() < n and not optional.is_empty():
		if pool.is_empty():
			pool = optional.duplicate()
			_shuffle(pool, rng)
		chosen.append(pool.pop_back())
	_shuffle(chosen, rng)

	# --- Plans (gabarits) ------------------------------------------------
	var ctx := {"super_budget": Cfg.geti("super_loot_max_per_floor", 2)}
	# La banque passe en premier pour garantir son coffre scellé.
	var order: Array[int] = []
	for i in chosen.size():
		if chosen[i] == &"bank":
			order.push_front(i)
		else:
			order.append(i)
	var plans: Array = []
	plans.resize(chosen.size())
	for i2 in order:
		plans[i2] = _build_plan(chosen[i2], rng, ctx)

	# --- Répartition en deux rangées --------------------------------------
	var rows: Array = [[], []]   # 0 = nord, 1 = sud
	var row_w: Array[int] = [0, 0]
	for p: Tpl.Plan in plans:
		var r := 0 if row_w[0] <= row_w[1] else 1
		var s := Slot.new()
		s.kind = &"building"
		s.width = p.size.x
		s.plan = p
		s.gap_after = rng.randi_range(Cfg.geti("building_gap_min", 0), Cfg.geti("building_gap_max", 2))
		rows[r].append(s)
		row_w[r] += s.width + s.gap_after
	# Ruelles et placettes, insérées entre deux bâtiments.
	var n_alleys := Cfg.range_i(rng, "alleys_min", "alleys_max", 1, 3)
	for k in n_alleys:
		var r2 := rng.randi_range(0, 1)
		if rows[r2].size() < 2:
			r2 = 1 - r2
		var a3 := Slot.new()
		a3.kind = &"alley"
		a3.width = Cfg.range_i(rng, "alley_width_min", "alley_width_max", 3, 4)
		rows[r2].insert(rng.randi_range(1, rows[r2].size() - 1), a3)
	if rng.randf() < Cfg.getf("notch_chance", 0.6):
		var r3 := rng.randi_range(0, 1)
		var nt := Slot.new()
		nt.kind = &"notch"
		nt.width = Cfg.range_i(rng, "notch_width_min", "notch_width_max", 7, 10)
		rows[r3].insert(rng.randi_range(1, rows[r3].size() - 1), nt)
	# Pas de ruelle collée à une autre ruelle/placette.
	for r4 in 2:
		var row: Array = rows[r4]
		for i3 in range(row.size() - 1, 0, -1):
			if (row[i3] as Slot).kind != &"building" and (row[i3 - 1] as Slot).kind != &"building":
				row.remove_at(i3)

	# --- Dimensions -------------------------------------------------------
	var sw := Cfg.range_i(rng, "street_width_min", "street_width_max", 5, 7)
	var west := Cfg.geti("town_margin_west", 6)
	var east := Cfg.geti("town_margin_east", 7)
	var plaza_h_max := Cfg.geti("plaza_depth_max", 6)
	var depth: Array[int] = [0, 0]
	var has_alley: Array[bool] = [false, false]
	var widths: Array[int] = [0, 0]
	for r5 in 2:
		for s2: Slot in rows[r5]:
			widths[r5] += s2.width + s2.gap_after
			if s2.kind == &"building":
				depth[r5] = maxi(depth[r5], s2.plan.size.y)
			elif s2.kind == &"alley":
				has_alley[r5] = true
	var row_depth: Array[int] = []
	for r6 in 2:
		row_depth.append(depth[r6] + (plaza_h_max + 2 if has_alley[r6] else 0))
	var W := maxi(widths[0], widths[1]) + west + east
	W = maxi(W, Cfg.geti("town_width_min", 60))
	# Hauteur minimale : marge (VOID) répartie au nord et au sud.
	var h_min := Cfg.geti("town_height_min", 40)
	var deficit := h_min - (2 + row_depth[0] + sw + row_depth[1])
	if deficit > 0:
		row_depth[0] += deficit / 2
		row_depth[1] += deficit - deficit / 2
	var H := 1 + row_depth[0] + sw + row_depth[1] + 1
	var street_y := 1 + row_depth[0]
	var street := Rect2i(1, street_y, W - 2, sw)

	var L := FloorLayout.new(Vector2i(W, H))
	L.floor_index = 0
	var res := TownResult.new()
	res.layout = L
	L.fill_rect(street, T.STREET)

	# Tronçons de rue : entrée (spawn), rue principale, sortie (extraction).
	var seg_w := Cfg.geti("street_end_length", 9)
	var r_spawn := L.add_room(Rect2i(1, street_y, seg_w, sw), true, FloorLayout.ROOM_SPAWN, "Entrée de la ville")
	r_spawn.tags = PackedStringArray(["street_entry", "outdoor"])
	var r_main := L.add_room(Rect2i(1 + seg_w, street_y, W - 2 - 2 * seg_w, sw), true, FloorLayout.ROOM_COMBAT, "Rue principale")
	r_main.tags = PackedStringArray(["street", "outdoor"])
	var r_exit := L.add_room(Rect2i(W - 1 - seg_w, street_y, seg_w, sw), true, FloorLayout.ROOM_EXTRACTION, "Relais de la diligence")
	r_exit.tags = PackedStringArray(["street_exit", "outdoor"])

	# --- Placement des rangées --------------------------------------------
	var alley_rooms: Array[FloorLayout.Room] = []
	var occupied_rects: Array[Rect2i] = []
	var pending_plazas: Array[Dictionary] = []
	for r7 in 2:
		var north := r7 == 0
		var x := west + rng.randi_range(0, maxi(0, W - west - east - widths[r7]))
		for s3: Slot in rows[r7]:
			match s3.kind:
				&"building":
					var p2 := s3.plan
					var origin := Vector2i(x, street_y - p2.size.y) if north else Vector2i(x, street.end.y)
					var flip_x := rng.randf() < 0.5
					_stamp_building(L, p2, origin, flip_x, not north, rng, res, want_upper)
					occupied_rects.append(Rect2i(origin, p2.size))
				&"alley":
					var alen := depth[r7] + 1
					var ar := Rect2i(x, street_y - alen, s3.width, alen) if north else Rect2i(x, street.end.y, s3.width, alen)
					L.fill_rect(ar, T.STREET)
					var room := L.add_room(ar, true, FloorLayout.ROOM_COMBAT, _pick(["Ruelle du croque-mort", "Ruelle des chercheurs d'or", "Passage du maréchal-ferrant", "Ruelle aux coyotes"], rng))
					room.tags = PackedStringArray(["alley", "outdoor"])
					alley_rooms.append(room)
					pending_plazas.append({"alley": ar, "north": north, "room": room})
				&"notch":
					var nd := Cfg.range_i(rng, "notch_depth_min", "notch_depth_max", 3, 5)
					var nr := Rect2i(x, street_y - nd, s3.width, nd) if north else Rect2i(x, street.end.y, s3.width, nd)
					L.fill_rect(nr, T.STREET)
					var room2 := L.add_room(nr, true, FloorLayout.ROOM_REST if rng.randf() < 0.5 else FloorLayout.ROOM_COMBAT, _pick(["Place du puits", "Place de l'abreuvoir", "Corral"], rng))
					room2.tags = PackedStringArray(["plaza", "outdoor"])
					occupied_rects.append(nr)
			x += s3.width + s3.gap_after

	# Placettes au bout des ruelles (derrière les bâtiments).
	var plazas: Array[FloorLayout.Room] = []
	for pp: Dictionary in pending_plazas:
		var ar2: Rect2i = pp["alley"]
		var north2: bool = pp["north"]
		var ph := Cfg.range_i(rng, "plaza_depth_min", "plaza_depth_max", 4, 6)
		var ext_l := rng.randi_range(2, 4)
		var ext_r := rng.randi_range(2, 4)
		var py := ar2.position.y - ph if north2 else ar2.end.y
		var pr := Rect2i(ar2.position.x - ext_l, py, ar2.size.x + ext_l + ext_r, ph)
		pr = pr.intersection(Rect2i(1, 1, W - 2, H - 2))
		var clash := false
		for o in occupied_rects:
			if o.grow(1).intersects(pr):
				clash = true
		if clash or pr.size.y < 3:
			continue
		L.fill_rect(pr, T.STREET)
		occupied_rects.append(pr)
		var room3 := L.add_room(pr, true, FloorLayout.ROOM_LOOT if rng.randf() < 0.5 else FloorLayout.ROOM_COMBAT, _pick(["Cimetière", "Arrière-cour", "Place du gibet", "Enclos à bétail", "Dépôt de bois"], rng))
		room3.tags = PackedStringArray(["backyard", "outdoor"])
		plazas.append(room3)
		pp["plaza"] = room3

	# --- Escaliers, spawn, extraction -------------------------------------
	L.player_spawn = Vector2i(2, street_y + sw / 2)
	var ex := Vector2i(W - 4, street_y + sw / 2 - 1)
	for c: Vector2i in [ex, ex + Vector2i.RIGHT, ex + Vector2i.DOWN, ex + Vector2i.ONE]:
		L.extraction_cells.append(c)
	# Seconde extraction possible : la placette la plus à l'est (loin du spawn).
	if not plazas.is_empty() and rng.randf() < Cfg.getf("second_extraction_chance", 0.5):
		var best: FloorLayout.Room = plazas[0]
		for pz in plazas:
			if pz.rect.get_center().x > best.rect.get_center().x:
				best = pz
		if best.rect.get_center().x > W / 2:
			best.type = FloorLayout.ROOM_EXTRACTION
			var cc := best.rect.get_center()
			L.extraction_cells.append(cc)
			L.extraction_cells.append(cc + Vector2i.RIGHT)

	_fence(L)
	return res


static func _build_plan(a: StringName, rng: RandomNumberGenerator, ctx: Dictionary) -> Tpl.Plan:
	for attempt in 12:
		var budget := int(ctx["super_budget"])
		var p := Tpl.build(a, rng, ctx)
		if _plan_ok(p):
			return p
		ctx["super_budget"] = budget
	# Repli : magasin (toujours valide).
	return Tpl.build(&"store", rng, ctx)


## Toutes les salles du plan sont reliées à l'extérieur par des portes.
static func _plan_ok(p: Tpl.Plan) -> bool:
	var seen := {Tpl.OUTSIDE: true}
	var changed := true
	while changed:
		changed = false
		for d in p.doors:
			if seen.has(d.a) != seen.has(d.b):
				seen[d.a] = true
				seen[d.b] = true
				changed = true
	for i in p.rooms.size():
		if not seen.has(i):
			return false
	return true


## Applique un plan sur la grille (avec retournements), crée bâtiment, salles,
## portes et escaliers.
static func _stamp_building(L: FloorLayout, p: Tpl.Plan, origin: Vector2i, flip_x: bool, flip_y: bool, rng: RandomNumberGenerator, res: TownResult, want_upper: bool) -> void:
	var names: Dictionary = {}
	var b := L.add_building(p.archetype, "", Rect2i(origin, p.size))
	b.name = _building_name(p.archetype, rng, res)
	L.carve_walled_rect(b.rect, T.WALL)
	var ids: Array[int] = []
	for pr in p.rooms:
		var gr := tf_rect(pr.rect, p.size, flip_x, flip_y)
		gr.position += origin
		L.fill_rect(gr, T.FLOOR)
		var t := pr.type if pr.type != &"" else _pick_room_type(rng)
		var room := L.add_room(gr, false, t, pr.name, b.id)
		room.tags = PackedStringArray([String(pr.role), String(p.archetype)])
		ids.append(room.id)
	var street_room := -1
	for d in p.doors:
		var c := tf_cell(d.cell, p.size, flip_x, flip_y) + origin
		var ra := ids[d.a] if d.a != Tpl.OUTSIDE else _outdoor_room_at(L, c, flip_y)
		var rb := ids[d.b] if d.b != Tpl.OUTSIDE else _outdoor_room_at(L, c, flip_y)
		L.add_door(c, d.vertical, d.state, ra, rb, d.key_id, b.id)
	for i in p.stairs.size():
		var up := p.stairs_up[i]
		if up and not want_upper:
			continue
		var sc := tf_cell(p.stairs[i], p.size, flip_x, flip_y) + origin
		L.set_tile(sc, T.STAIRS_UP if up else T.STAIRS_DOWN)
		var st := FloorLayout.Stairs.new()
		st.cell = sc
		st.up = up
		st.target_floor = 1 if up else -1
		st.target_cell = sc
		L.stairs.append(st)
		if not up:
			res.mine_stairs.append(sc)
	if p.has_upper and want_upper:
		res.upper_specs.append({"building_id": b.id, "plan": p, "origin": origin, "flip_x": flip_x, "flip_y": flip_y})


## Salle extérieure en face d'une porte de façade.
static func _outdoor_room_at(L: FloorLayout, door_cell: Vector2i, flip_y: bool) -> int:
	var out := door_cell + (Vector2i.UP if flip_y else Vector2i.DOWN)
	var r := L.room_at(out)
	return r.id if r != null else -1


static func tf_cell(c: Vector2i, size: Vector2i, fx: bool, fy: bool) -> Vector2i:
	return Vector2i(size.x - 1 - c.x if fx else c.x, size.y - 1 - c.y if fy else c.y)


static func tf_rect(r: Rect2i, size: Vector2i, fx: bool, fy: bool) -> Rect2i:
	var x := size.x - r.end.x if fx else r.position.x
	var y := size.y - r.end.y if fy else r.position.y
	return Rect2i(x, y, r.size.x, r.size.y)


static func _pick_room_type(rng: RandomNumberGenerator) -> StringName:
	var w := Cfg.get_dict("room_type_weights", {"combat": 4.0, "loot": 3.0, "trap": 1.5, "rest": 1.0})
	return StringName(_weighted(w, rng))


static func _weighted(w: Dictionary, rng: RandomNumberGenerator) -> String:
	var keys := w.keys()
	keys.sort()
	var total := 0.0
	for k: Variant in keys:
		total += float(w[k])
	var roll := rng.randf() * total
	for k2: Variant in keys:
		roll -= float(w[k2])
		if roll <= 0.0:
			return String(k2)
	return String(keys[keys.size() - 1])


static func _building_name(a: StringName, rng: RandomNumberGenerator, res: TownResult) -> String:
	var defaults := {
		&"saloon": "Saloon", &"bank": "Banque", &"sheriff": "Bureau du shérif", &"store": "Magasin général",
		&"hotel": "Hôtel", &"stable": "Écurie", &"church": "Église", &"mine": "Entrée de la mine",
	}
	var name: String = defaults.get(a, String(a).capitalize())
	var world_names: Variant = null
	# Les noms viennent du WorldData via le cache statique (évite de passer world partout).
	if _names_cache.has(a):
		world_names = _names_cache[a]
	if world_names is PackedStringArray and (world_names as PackedStringArray).size() > 0:
		var arr: PackedStringArray = world_names
		name = arr[rng.randi_range(0, arr.size() - 1)]
	# Unicité dans la ville.
	var used: Array[String] = []
	for bb in res.layout.buildings:
		used.append(bb.name)
	var base := name
	var k := 2
	while used.has(name):
		name = "%s (%d)" % [base, k]
		k += 1
	return name


static var _names_cache: Dictionary = {}


static func set_names(world: WorldData) -> void:
	_names_cache = world.building_names.duplicate()


# --- Étage 1 ---------------------------------------------------------------

## Étage des bâtiments à étage : couloir intérieur passant par l'escalier,
## chambres de part et d'autre. Même taille de grille que l'étage 0.
static func build_upper(seed_value: int, town: TownResult) -> FloorLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "upper"])
	var G := town.layout
	var L := FloorLayout.new(G.size)
	L.floor_index = 1
	var budget := Cfg.geti("super_loot_max_per_floor", 2)
	var first := true
	for spec: Dictionary in town.upper_specs:
		var p: Tpl.Plan = spec["plan"]
		var origin: Vector2i = spec["origin"]
		var fx: bool = spec["flip_x"]
		var fy: bool = spec["flip_y"]
		var gb := G.buildings[int(spec["building_id"])]
		var b := L.add_building(gb.archetype, gb.name, gb.rect)
		L.carve_walled_rect(b.rect, T.WALL)
		var w := p.size.x
		var h := p.size.y
		var up_stairs: Array[Vector2i] = []
		for i in p.stairs.size():
			if p.stairs_up[i]:
				up_stairs.append(p.stairs[i])
		var sy := up_stairs[0].y
		var cy0 := sy if sy + 1 <= h - 2 else sy - 1
		var cy1 := cy0 + 1
		var plan := Tpl.Plan.new()
		plan.size = p.size
		var cor := plan.add_room(Rect2i(1, cy0, w - 2, 2), FloorLayout.ROOM_CORRIDOR, "Couloir de l'étage", &"upper_corridor")
		for s in up_stairs:
			plan.add_stairs(s, false)
		var bands: Array[Rect2i] = []
		if cy0 - 2 >= 3:
			bands.append(Rect2i(1, 1, w - 2, cy0 - 2))
		if h - 3 - cy1 >= 3:
			bands.append(Rect2i(1, cy1 + 2, w - 2, h - 3 - cy1))
		var suite_done := false
		for band in bands:
			var k := maxi(2, (band.size.x + 1) / 5)
			var ws := Tpl.split_widths(band.size.x, k, 3, rng)
			var x := 1
			for j in k:
				var rr := Rect2i(x, band.position.y, ws[j], band.size.y)
				x += ws[j] + 1
				var sealed := not suite_done and budget > 0 and rng.randf() < Cfg.getf("upper_suite_chance", 0.4)
				var key: StringName = &""
				var ri: int
				if sealed:
					suite_done = true
					budget -= 1
					key = &"key_hotel_suite" if gb.archetype == &"hotel" else &"key_saloon_suite"
					ri = plan.add_room(rr, FloorLayout.ROOM_SUPER_LOOT, "Suite du patron" if gb.archetype == &"saloon" else "Suite présidentielle", &"suite")
				else:
					var nm := "Chambre %d" % (plan.rooms.size())
					if gb.archetype == &"saloon" and j == 0 and band.size.y >= 5:
						nm = "Salon de jeu"
						ri = plan.add_room(rr, &"", nm, &"gaming_room")
					else:
						ri = plan.add_room(rr, &"", nm, &"bedroom")
				if not Tpl.link(plan, rng, cor, ri, FloorLayout.DoorState.CLOSED, key):
					plan.rooms.pop_back()
					if sealed:
						suite_done = false
						budget += 1
		var ids: Array[int] = []
		for pr in plan.rooms:
			var gr := tf_rect(pr.rect, plan.size, fx, fy)
			gr.position += origin
			L.fill_rect(gr, T.FLOOR)
			var t := pr.type if pr.type != &"" else _pick_room_type(rng)
			var room := L.add_room(gr, false, t, pr.name, b.id)
			room.tags = PackedStringArray([String(pr.role), String(gb.archetype)])
			ids.append(room.id)
		for d in plan.doors:
			var c := tf_cell(d.cell, plan.size, fx, fy) + origin
			L.add_door(c, d.vertical, d.state, ids[d.a], ids[d.b], d.key_id, b.id)
		for s2 in up_stairs:
			var sc := tf_cell(s2, p.size, fx, fy) + origin
			L.set_tile(sc, T.STAIRS_DOWN)
			var st := FloorLayout.Stairs.new()
			st.cell = sc
			st.up = false
			st.target_floor = 0
			st.target_cell = sc
			L.stairs.append(st)
			if first:
				first = false
				L.player_spawn = _arrival(L, sc)
	return L


static func _arrival(L: FloorLayout, s: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
		if L.get_tile(s + d) == T.FLOOR or L.get_tile(s + d) == T.STREET:
			return s + d
	return s


# --- Aides -------------------------------------------------------------------

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


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


static func _pick(a: Array, rng: RandomNumberGenerator) -> Variant:
	return a[rng.randi_range(0, a.size() - 1)]
