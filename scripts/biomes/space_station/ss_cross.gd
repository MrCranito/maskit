extends RefCounted
## Pont principal (0) de la Station Orbitale en CROIX, façon maquette (docs/reference/cartes.png,
## colonne « Station spatiale ») : format portrait, symétrique autour d'une coursive centrale
## nord-sud.
##   - nord : sas d'amarrage (navette), antenne parabolique et panneaux solaires dans le vide ;
##   - deux grandes ailes (modules ouverts, vus en coupe) de part et d'autre de la coursive ;
##   - petits modules fermés (toit) contre la coursive : labo scellé, réduits, ascenseurs ;
##   - centre : hall carré autour du CENTRE DE CONTRÔLE circulaire (dôme vitré, consoles en
##     anneau), bras est-ouest (coursive de 3 cases) jusqu'aux sas d'amarrage des bouts de bras ;
##   - bas : hall de fret, modules latéraux, salles « rouges », hangar d'arrivée (spawn) ;
##   - deux cylindres-réacteurs en diagonale, reliés par des tubes (couloirs en escalier).
## Variations par seed : largeurs des ailes / bras / modules bas, découpe BSP des blocs, rôles,
## sas d'extraction (2 des 3), côtés des ascenseurs, modules endommagés en gravité faible,
## position des décors hors jeu (antenne, panneaux, navettes).
## Les données du rendu pré-calculé (tools/prerender/ss_scene.py) sont jointes au layout en
## métadonnée « render_contract » (exportée par tools/prerender/export_layout.gd).
## Ne pose aucun spawn (voir ss_populator.gd). Déterministe, < 10 ms.

const Cfg := preload("res://scripts/biomes/space_station/ss_config.gd")
const Deck := preload("res://scripts/biomes/space_station/ss_deck.gd")
const T := FloorLayout.Tile

const W := 64
const H := 116
## Coursive centrale : colonnes SPINE_X0..SPINE_X0+3 (axe de symétrie x = 32, miroir x' = 63 - x).
const SPINE_X0 := 30
const SPINE_W := 4
## Centre de contrôle : centre (cases, coordonnées continues) et rayon du sol.
const DOME_C := Vector2(32.0, 54.0)
const DOME_R := 8.0
## Bras est-ouest : rangées de la coursive.
const ARM_Y0 := 53
const ARM_H := 3

const EXTRA_ROLE_NAMES := {
	&"control_center": "Centre de contrôle", &"hall": "Hall", &"reactor_pod": "Module réacteur",
	&"tube": "Tube de liaison", &"airlock": "Sas d'amarrage",
}


class Mod:
	var rect: Rect2i                 ## Murs compris
	var inner: Rect2i                ## Sol (salle)
	var role: StringName = &""
	var type: StringName = FloorLayout.ROOM_COMBAT
	var name: String = ""
	var slot: String = ""            ## Zone de la croix (wing_w, narrow_e, arm_nw…)
	var roof: bool = false           ## Module fermé (toit qui s'efface quand on entre)
	var round_c: Vector2 = Vector2.ZERO
	var round_r: float = 0.0         ## > 0 : salle circulaire
	var key: StringName = &""
	var open: bool = false           ## Reliée par des ouvertures (pas de porte)
	var corridor: bool = false
	var damaged: bool = false        ## Gravité faible
	var arch: StringName = &"ss_module"
	var room: FloorLayout.Room = null
	var building: FloorLayout.Building = null
	var unit: int = -1


class Result:
	var layout: FloorLayout
	var mods: Array[Mod] = []
	var up_cell: Vector2i = Vector2i(-1, -1)
	var down_cell: Vector2i = Vector2i(-1, -1)


static func mirror_rect(r: Rect2i) -> Rect2i:
	return Rect2i(W - r.end.x, r.position.y, r.size.x, r.size.y)


static func mirror_cell(c: Vector2i) -> Vector2i:
	return Vector2i(W - 1 - c.x, c.y)


## Cases des ascenseurs du pont 0 (tirage indépendant des tentatives) : {up, down}.
static func lift_cells(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "ss_cross_lift"])
	var west := Vector2i(27, 28)
	var east := mirror_cell(west)
	if rng.randf() < 0.5:
		return {"up": west, "down": east}
	return {"up": east, "down": west}


static func build(seed_value: int) -> Result:
	var attempts := Cfg.geti("cross_attempts", 12)
	for attempt in attempts:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "ss_cross", attempt])
		var res := _try(rng, attempt >= attempts / 2, lift_cells(seed_value))
		if res != null:
			return res
	push_error("SpaceStation: pont en croix impossible à générer (seed %d)" % seed_value)
	return null


# --- Construction -------------------------------------------------------------------------

static func _try(rng: RandomNumberGenerator, simple: bool, lifts: Dictionary) -> Result:
	var L := FloorLayout.new(Vector2i(W, H))
	L.floor_index = 0
	var res := Result.new()
	res.layout = L
	var mods: Array[Mod] = []
	var corridors: Array[Mod] = []
	# Paramètres (symétriques) : largeur des ailes, des modules du bras et des modules bas.
	var wx0 := rng.randi_range(8, 10)         # bord ouest des ailes nord
	var ax0 := rng.randi_range(4, 5)          # bord ouest des modules du bras (sas collé à l'ouest)
	var lx0 := rng.randi_range(10, 12)        # bord ouest des modules bas
	var rr := rng.randf_range(5.6, 6.0)       # rayon des réacteurs
	# Sas d'extraction : 2 des 3 (nord, ouest, est).
	var ex_pick := rng.randi_range(0, 2)      # sas qui n'est PAS une extraction (0 n, 1 o, 2 e)
	if Cfg.geti("cross_all_extractions", 0) == 1:
		ex_pick = -1

	# 1. Coursives et places (sol) : coursive centrale nord, grande place autour du centre de
	#    contrôle, place de fret, coursive sud vers le hangar.
	var spine_n := _corr(Rect2i(SPINE_X0, 14, SPINE_W, 20), "Coursive centrale nord", &"corridor", "v")
	var hall_c := _corr(Rect2i(16, 34, 32, 29), "Place du centre de contrôle", &"hall", "hall")
	var hall_f := _corr(Rect2i(22, 64, 20, 18), "Place de fret", &"hall", "hall")
	var spine_s := _corr(Rect2i(SPINE_X0, 82, SPINE_W, 20), "Coursive centrale sud", &"corridor", "v")
	for c: Mod in [spine_n, hall_c, hall_f, spine_s]:
		corridors.append(c)
		L.fill_rect(c.inner, T.FLOOR)
	# Large ouverture entre les deux places (rangée 63).
	var gap0 := rng.randi_range(25, 27)
	for x in range(gap0, W - gap0):
		L.set_tile(Vector2i(x, 63), T.FLOOR)

	# 2. Modules rectangulaires.
	var n_sas := _mod(Rect2i(20, 4, 24, 10), &"pod_bay", "sas_n")
	var w_sas := _mod(Rect2i(ax0 - 4, 50, 5, 7), &"pod_bay", "sas_w")
	var e_sas := _mod(mirror_rect(w_sas.rect), &"pod_bay", "sas_e")
	var sas: Array[Mod] = [n_sas, w_sas, e_sas]
	for i in 3:
		var s: Mod = sas[i]
		if i == ex_pick:
			s.role = &"airlock"
			s.type = FloorLayout.ROOM_LOOT
		else:
			s.type = FloorLayout.ROOM_EXTRACTION
	n_sas.name = "Sas d'amarrage nord"
	w_sas.name = "Sas d'amarrage ouest"
	e_sas.name = "Sas d'amarrage est"
	mods.append_array(sas)
	var hangar := _mod(Rect2i(24, 101, 16, 13), &"hangar", "hangar")
	hangar.type = FloorLayout.ROOM_SPAWN
	hangar.open = true
	mods.append(hangar)
	# Modules fermés (toits) contre la coursive : flancs du module nord, ascenseurs, réduits,
	# salles des machines de part et d'autre de l'entrée du hangar.
	for side in 2:
		var fl := Rect2i(20, 13, 10, 9)
		var lift := Rect2i(25, 27, 5, 7)
		var clo := Rect2i(20, 27, 6, 7)
		var mach := Rect2i(21, 93, 9, 9)
		if side == 1:
			fl = mirror_rect(fl)
			lift = mirror_rect(lift)
			clo = mirror_rect(clo)
			mach = mirror_rect(mach)
		var sfx := "w" if side == 0 else "e"
		var top := _mod(fl, &"", "narrow_" + sfx)
		top.roof = true
		var lm := _mod(lift, &"elevator", "lift_" + sfx)
		lm.roof = true
		lm.type = FloorLayout.ROOM_REST
		lm.arch = &"ss_lift"
		var cm := _mod(clo, &"closet", "closet_" + sfx)
		cm.roof = true
		cm.type = FloorLayout.ROOM_LOOT
		var mm := _mod(mach, &"generator", "mach_" + sfx)
		mm.roof = true
		mm.type = FloorLayout.ROOM_TRAP if rng.randf() < 0.4 else FloorLayout.ROOM_LOOT
		mm.name = "Salle des machines " + ("ouest" if side == 0 else "est")
		mods.append_array([top, lm, cm, mm])
	# Blocs découpés (BSP) : ailes, cou, nacelles, bras, nacelles basses, modules bas, salles rouges.
	var free: Array[Mod] = []
	for side2 in 2:
		var sfx2 := "w" if side2 == 0 else "e"
		var blocks := [
			[Rect2i(wx0, 10, 21 - wx0, 18), "wing_" + sfx2, 140.0],
			[Rect2i(20, 21, 10, 7), "neck_" + sfx2, 999.0],
			[Rect2i(8, 34, 8, 9), "pod_" + sfx2, 999.0],
			[Rect2i(ax0, 45, 16 - ax0, 18), "arm_" + sfx2, 110.0],
			[Rect2i(8, 62, 8, 8), "pod2_" + sfx2, 999.0],
			[Rect2i(lx0, 69, 22 - lx0, 14), "low_" + sfx2, 999.0],
			[Rect2i(21, 82, 9, 12), "red_" + sfx2, 999.0],
		]
		for b: Array in blocks:
			var r: Rect2i = b[0]
			if side2 == 1:
				r = mirror_rect(r)
			var leaves: Array[Rect2i] = []
			_bsp(r, leaves, rng, 0, float(b[2]) if not simple else 9999.0)
			for lr in leaves:
				var m := _mod(lr, &"", String(b[1]))
				mods.append(m)
				free.append(m)
	# Modules ronds : centre de contrôle (dôme) et réacteurs.
	var dome := _round_mod(DOME_C, DOME_R, &"control_center", "dome")
	dome.open = true
	dome.roof = true
	dome.arch = &"ss_dome"
	dome.type = FloorLayout.ROOM_COMBAT
	dome.name = String(EXTRA_ROLE_NAMES[&"control_center"])
	var react_w := _round_mod(Vector2(7.5, 103.0), rr, &"reactor_pod", "reactor_w")
	var react_e := _round_mod(Vector2(W - 7.5, 103.0), rr, &"reactor_pod", "reactor_e")
	for rm: Mod in [react_w, react_e]:
		rm.roof = true
		rm.open = true
		rm.arch = &"ss_reactor"
		rm.type = FloorLayout.ROOM_TRAP if rng.randf() < 0.5 else FloorLayout.ROOM_COMBAT
	react_w.name = "Module réacteur ouest"
	react_e.name = "Module réacteur est"

	# 3. Rôles des modules libres.
	_assign_roles(mods, free, rng)
	# Flancs du module nord : labo scellé d'un côté (super_loot), serveurs / infirmerie de l'autre.
	var vault_side := rng.randi_range(0, 1)
	for m2 in mods:
		if m2.slot.begins_with("narrow_"):
			var is_vault := (m2.slot == "narrow_w") == (vault_side == 0)
			if is_vault:
				m2.role = &"lab_vault"
				m2.type = FloorLayout.ROOM_SUPER_LOOT
				m2.key = Deck.KEY_LAB
				m2.name = String(Deck.ROLE_NAMES[&"lab_vault"])
			else:
				m2.role = &"server_room" if rng.randf() < 0.6 else &"infirmary"
				m2.type = FloorLayout.ROOM_LOOT if rng.randf() < 0.6 else FloorLayout.ROOM_REST
				m2.name = String(Deck.ROLE_NAMES[m2.role])
	# Armurerie scellée : une des nacelles (petit module octogonal), fermée par un toit.
	if rng.randf() < Cfg.getf("cross_armory_chance", 1.0):
		var cands: Array[Mod] = []
		for m3 in free:
			if m3.slot.begins_with("pod") and not (m3.role in [&"mess_hall", &"infirmary", &"lab", &"quarters"]):
				cands.append(m3)
		if not cands.is_empty():
			var best: Mod = cands[rng.randi_range(0, cands.size() - 1)]
			best.role = &"armory"
			best.type = FloorLayout.ROOM_SUPER_LOOT
			best.key = Deck.KEY_ARMORY
			best.roof = true
			best.name = String(Deck.ROLE_NAMES[&"armory"])
	# Modules endommagés (gravité faible) : 1 à 2, ailes, réacteurs, bras ou nacelles.
	var dmg_cands: Array[Mod] = []
	for m4 in mods:
		if m4.type == FloorLayout.ROOM_SUPER_LOOT or m4.type == FloorLayout.ROOM_SPAWN or m4.type == FloorLayout.ROOM_EXTRACTION:
			continue
		if m4.slot.begins_with("wing_") or m4.slot.begins_with("reactor_") or m4.slot.begins_with("arm_") or m4.slot.begins_with("low_"):
			dmg_cands.append(m4)
	var n_dmg := rng.randi_range(Cfg.geti("cross_damaged_min", 1), Cfg.geti("cross_damaged_max", 2))
	for k in n_dmg:
		if dmg_cands.is_empty():
			break
		var pick: Mod = dmg_cands[rng.randi_range(0, dmg_cands.size() - 1)]
		pick.damaged = true
		dmg_cands.erase(pick)
	mods.append_array([dome, react_w, react_e])

	# 4. Creusement : murs puis sols des modules rectangulaires, puis modules ronds.
	for m5 in mods:
		if m5.round_r > 0.0:
			continue
		L.fill_rect(m5.rect, T.WALL)
	for m6 in mods:
		if m6.round_r > 0.0:
			continue
		L.fill_rect(m6.inner, T.FLOOR)
	for m7 in mods:
		if m7.round_r <= 0.0:
			continue
		L.fill_rect(m7.rect, T.WALL)
		for y2 in range(m7.inner.position.y, m7.inner.end.y):
			for x2 in range(m7.inner.position.x, m7.inner.end.x):
				if Vector2(x2 + 0.5, y2 + 0.5).distance_to(m7.round_c) <= m7.round_r:
					L.set_tile(Vector2i(x2, y2), T.FLOOR)
	# Ouvertures du centre de contrôle (4 axes) et du hangar (vers la coursive sud).
	_dome_openings(L, dome)
	for x3 in range(SPINE_X0, SPINE_X0 + SPINE_W):
		L.set_tile(Vector2i(x3, 101), T.FLOOR)
	# Tubes réacteurs ↔ salles rouges (escalier de carrés de 4 cases).
	var tubes: Array = []
	for side3 in 2:
		var sq: Array[Rect2i] = [Rect2i(11, 95, 4, 4), Rect2i(13, 93, 4, 4), Rect2i(15, 91, 4, 4), Rect2i(17, 89, 4, 4)]
		var door := Vector2i(21, 90)
		if side3 == 1:
			for i2 in sq.size():
				sq[i2] = mirror_rect(sq[i2])
			door = mirror_cell(door)
		var tm := Mod.new()
		tm.corridor = true
		tm.roof = true
		tm.arch = &"ss_tube"
		tm.role = &"tube"
		tm.type = FloorLayout.ROOM_CORRIDOR
		tm.slot = "tube_" + ("w" if side3 == 0 else "e")
		tm.name = "Tube de liaison " + ("ouest" if side3 == 0 else "est")
		tm.rect = Rect2i(14, 89, 7, 8) if side3 == 0 else mirror_rect(Rect2i(14, 89, 7, 8))
		for q in sq:
			L.fill_rect(q, T.FLOOR)
		tubes.append({"mod": tm, "squares": sq, "door": door})
	_fence(L)

	# 5. Escaliers (ascenseurs) : case du haut, au centre de la cabine.
	for m8 in mods:
		if m8.role != &"elevator":
			continue
		var cell := Vector2i(m8.inner.position.x + m8.inner.size.x / 2, m8.inner.position.y)
		var up: bool = cell == lifts["up"]
		_add_stairs(L, cell, up, 1 if up else -1)
		if up:
			res.up_cell = cell
		else:
			res.down_cell = cell

	# 6. Bâtiments (modules à toit) et salles.
	for m9 in mods:
		if m9.roof:
			m9.building = L.add_building(m9.arch, m9.name, m9.rect)
	for m10 in mods:
		var bid := m10.building.id if m10.building != null else -1
		m10.room = L.add_room(m10.inner, false, m10.type, m10.name, bid)
		m10.room.tags.append(String(m10.role))
		if m10.round_r > 0.0:
			m10.room.tags.append("round")
		if m10.open:
			m10.room.tags.append("open")
		if m10.damaged:
			m10.room.tags.append("damaged")
	for c2 in corridors:
		c2.room = L.add_room(c2.inner, false, FloorLayout.ROOM_CORRIDOR, c2.name)
		c2.room.tags.append(String(c2.role))
		c2.room.tags.append("corridor")
		c2.room.tags.append(c2.slot)
	for tb: Dictionary in tubes:
		var tm2: Mod = tb["mod"]
		tm2.building = L.add_building(tm2.arch, tm2.name, tm2.rect)
		var k2 := 0
		for q2: Rect2i in tb["squares"]:
			var rq := L.add_room(q2, false, FloorLayout.ROOM_CORRIDOR, tm2.name if k2 == 0 else "%s (%d)" % [tm2.name, k2 + 1], tm2.building.id)
			rq.tags.append("tube")
			rq.tags.append("corridor")
			if k2 == 0:
				tm2.room = rq
			k2 += 1
		corridors.append(tm2)
	# Cases d'ouverture (murs percés) : rattachées à la salle voisine la plus logique.
	_orphan_cells(L)

	# 7. Portes.
	if not _connect(L, mods, tubes, rng):
		return null

	# 8. Apparition, extraction, gravité faible.
	L.player_spawn = Vector2i(SPINE_X0 + rng.randi_range(1, 2), hangar.inner.end.y - 2)
	for s2 in sas:
		if s2.type != FloorLayout.ROOM_EXTRACTION:
			continue
		var ctr := s2.inner.get_center()
		var x0 := ctr.x - 1
		var y0 := ctr.y - 1 if s2.slot != "sas_n" else s2.inner.position.y + 1
		for dy in 2:
			for dx in 2:
				var ec := Vector2i(x0 + dx, y0 + dy)
				if L.get_tile(ec) == T.FLOOR and not L.extraction_cells.has(ec):
					L.extraction_cells.append(ec)
	var grid := room_grid(L)
	for m11 in mods:
		if not m11.damaged:
			continue
		for y4 in range(m11.inner.position.y, m11.inner.end.y):
			for x4 in range(m11.inner.position.x, m11.inner.end.x):
				var lc := Vector2i(x4, y4)
				if FloorLayout.is_walkable_tile(L.get_tile(lc)) and grid[y4 * W + x4] == m11.room.id:
					L.low_gravity_cells[lc] = true
	if not _validate(L, mods):
		return null
	res.mods = mods
	_render_contract(L, mods, corridors, tubes, rng)
	return res


static func _corr(inner: Rect2i, name: String, role: StringName, slot: String) -> Mod:
	var m := Mod.new()
	m.inner = inner
	m.rect = inner.grow(1)
	m.name = name
	m.role = role
	m.slot = slot
	m.corridor = true
	m.type = FloorLayout.ROOM_CORRIDOR
	return m


static func _mod(rect: Rect2i, role: StringName, slot: String) -> Mod:
	var m := Mod.new()
	m.rect = rect
	m.inner = rect.grow(-1)
	m.role = role
	m.slot = slot
	m.name = String(Deck.ROLE_NAMES.get(role, EXTRA_ROLE_NAMES.get(role, String(role))))
	return m


static func _round_mod(c: Vector2, r: float, role: StringName, slot: String) -> Mod:
	var m := Mod.new()
	m.round_c = c
	m.round_r = r
	var x0 := int(ceil(c.x - r - 0.5))
	var x1 := int(floor(c.x + r - 0.5))
	var y0 := int(ceil(c.y - r - 0.5))
	var y1 := int(floor(c.y + r - 0.5))
	m.inner = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	m.rect = m.inner.grow(1)
	m.role = role
	m.slot = slot
	return m


## Découpe BSP (murs partagés), modules de Deck.MIN_ROOM cases au moins.
static func _bsp(r: Rect2i, out: Array[Rect2i], rng: RandomNumberGenerator, depth: int, target: float) -> void:
	var mn := Deck.MIN_ROOM
	var can_x := r.size.x >= mn * 2 - 1
	var can_y := r.size.y >= mn * 2 - 1
	var area := float((r.size.x - 2) * (r.size.y - 2))
	var split := (can_x or can_y) and area > target * 1.25 and depth < 3
	if not split:
		out.append(r)
		return
	var along_x := can_x and (not can_y or r.size.x > r.size.y or (r.size.x == r.size.y and rng.randf() < 0.5))
	if along_x:
		var s := rng.randi_range(r.position.x + mn - 1, r.end.x - mn)
		_bsp(Rect2i(r.position.x, r.position.y, s - r.position.x + 1, r.size.y), out, rng, depth + 1, target)
		_bsp(Rect2i(s, r.position.y, r.end.x - s, r.size.y), out, rng, depth + 1, target)
	else:
		var s2 := rng.randi_range(r.position.y + mn - 1, r.end.y - mn)
		_bsp(Rect2i(r.position.x, r.position.y, r.size.x, s2 - r.position.y + 1), out, rng, depth + 1, target)
		_bsp(Rect2i(r.position.x, s2, r.size.x, r.end.y - s2), out, rng, depth + 1, target)


## Rôles des modules découpés : obligatoires d'abord (plus grands modules des ailes et des bras),
## puis tirage selon la zone.
static func _assign_roles(_mods: Array[Mod], free: Array[Mod], rng: RandomNumberGenerator) -> void:
	var by_zone := {"wing": [], "arm": [], "low": [], "red": [], "neck": [], "pod": [], "pod2": []}
	for m in free:
		var z := m.slot.split("_")[0]
		(by_zone[z] as Array).append(m)
	var cmp := func(a: Mod, b: Mod) -> bool:
		if a.inner.get_area() != b.inner.get_area():
			return a.inner.get_area() > b.inner.get_area()
		return a.rect.position.y * 1000 + a.rect.position.x < b.rect.position.y * 1000 + b.rect.position.x
	for z2: String in by_zone:
		(by_zone[z2] as Array).sort_custom(cmp)
	# Ailes : réfectoire + quartiers + labo ; bras : infirmerie + quartiers.
	var req := {"wing": [&"mess_hall", &"lab"], "arm": [&"infirmary", &"quarters"], "low": [&"cargo_hold"], "red": [],
		"neck": [&"quarters"], "pod": [], "pod2": []}
	var pools := {
		"wing": {&"quarters": 2.0, &"hydroponics": 1.5, &"server_room": 1.0, &"workshop": 1.0, &"storage": 1.0, &"lab": 0.6, &"mess_hall": 0.4},
		"arm": {&"quarters": 2.0, &"storage": 2.0, &"workshop": 1.5, &"infirmary": 0.6, &"server_room": 0.8},
		"low": {&"storage": 2.0, &"cargo_hold": 1.5, &"workshop": 1.5},
		"red": {&"workshop": 1.5, &"storage": 1.5, &"cargo_hold": 1.0},
		"neck": {&"quarters": 1.5, &"server_room": 1.0, &"storage": 1.0, &"infirmary": 0.5},
		"pod": {&"storage": 1.5, &"workshop": 1.0, &"server_room": 1.0, &"quarters": 1.0},
		"pod2": {&"storage": 1.5, &"workshop": 1.0, &"hydroponics": 1.0},
	}
	for z3: String in by_zone:
		var lst: Array = by_zone[z3]
		var rq: Array = (req[z3] as Array).duplicate()
		# Ordre des obligatoires mélangé (variété des plans).
		for i in range(rq.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Variant = rq[i]
			rq[i] = rq[j]
			rq[j] = tmp
		for k in lst.size():
			var m2: Mod = lst[k]
			m2.role = rq[k] if k < rq.size() else Deck._weighted(pools[z3], rng)
	var tw := Cfg.get_dict("room_type_weights", {"combat": 4.0, "loot": 3.0, "trap": 1.5, "rest": 1.0})
	for m3 in free:
		match m3.role:
			&"closet", &"storage", &"cargo_hold":
				m3.type = FloorLayout.ROOM_LOOT if rng.randf() < 0.7 else FloorLayout.ROOM_COMBAT
			&"mess_hall", &"workshop":
				m3.type = FloorLayout.ROOM_COMBAT
			&"infirmary":
				m3.type = FloorLayout.ROOM_REST if rng.randf() < 0.5 else FloorLayout.ROOM_LOOT
			_:
				m3.type = StringName(Deck._weighted(tw, rng))
	# Noms (lettres si plusieurs modules du même rôle).
	var by_role := {}
	for m4 in free:
		m4.name = String(Deck.ROLE_NAMES.get(m4.role, String(m4.role)))
		if not by_role.has(m4.role):
			by_role[m4.role] = []
		(by_role[m4.role] as Array).append(m4)
	for role: StringName in by_role:
		var l2: Array = by_role[role]
		if l2.size() < 2:
			continue
		l2.sort_custom(func(a: Mod, b: Mod) -> bool:
			return a.rect.position.y * 1000 + a.rect.position.x < b.rect.position.y * 1000 + b.rect.position.x)
		for k2 in l2.size():
			(l2[k2] as Mod).name = "%s %s" % [(l2[k2] as Mod).name, "ABCDEFGHIJKLMNOP"[mini(k2, 15)]]


## Ouvertures du centre de contrôle : axes nord/sud (largeur de la coursive) et est/ouest
## (largeur du bras), à travers l'anneau de murs.
static func _dome_openings(L: FloorLayout, d: Mod) -> void:
	var r := d.rect
	for x in range(SPINE_X0, SPINE_X0 + SPINE_W):
		for y in range(r.position.y, r.end.y):
			if Vector2(x + 0.5, y + 0.5).distance_to(d.round_c) > d.round_r and absf(y + 0.5 - d.round_c.y) > 1.0:
				L.set_tile(Vector2i(x, y), T.FLOOR)
	for y2 in range(ARM_Y0, ARM_Y0 + ARM_H):
		for x2 in range(r.position.x, r.end.x):
			if Vector2(x2 + 0.5, y2 + 0.5).distance_to(d.round_c) > d.round_r:
				L.set_tile(Vector2i(x2, y2), T.FLOOR)


## Toute case VOID voisine (8) d'une case marchable devient un mur ; bord de grille muré.
static func _fence(L: FloorLayout) -> void:
	var tiles := L.tiles
	for y in H:
		for x in W:
			var i := y * W + x
			if (x == 0 or y == 0 or x == W - 1 or y == H - 1) and tiles[i] != T.VOID:
				tiles[i] = T.WALL
	var src := tiles.duplicate()
	for y2 in range(1, H - 1):
		for x2 in range(1, W - 1):
			var t := src[y2 * W + x2]
			if t == T.VOID or t == T.WALL:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var j := (y2 + dy) * W + x2 + dx
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


## Cases marchables hors de toute salle (murs percés : ouvertures) : agrandit la salle de la
## coursive / du hall voisin d'une case pour les couvrir (sinon salle du module voisin ouvert).
static func _orphan_cells(L: FloorLayout) -> void:
	var grid := room_grid(L)
	var tiles := L.tiles
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			var t := tiles[i]
			if t == T.VOID or t == T.WALL or grid[i] >= 0:
				continue
			var best: FloorLayout.Room = null
			for j: int in [i - W, i + W, i - 1, i + 1]:
				if grid[j] < 0:
					continue
				var r := L.rooms[grid[j]]
				if best == null or (r.tags.has("corridor") and not best.tags.has("corridor")):
					best = r
			if best != null:
				best.rect = best.rect.merge(Rect2i(Vector2i(x, y), Vector2i.ONE))


## Index de salle par case (la plus petite salle qui la contient, comme FloorLayout.room_at).
static func room_grid(L: FloorLayout) -> PackedInt32Array:
	var grid := PackedInt32Array()
	grid.resize(W * H)
	grid.fill(-1)
	var area := PackedInt32Array()
	area.resize(W * H)
	area.fill(1 << 30)
	for r in L.rooms:
		var a := r.rect.get_area()
		for y in range(maxi(r.rect.position.y, 0), mini(r.rect.end.y, H)):
			for x in range(maxi(r.rect.position.x, 0), mini(r.rect.end.x, W)):
				var i := y * W + x
				if a < area[i]:
					area[i] = a
					grid[i] = r.id
	return grid


# --- Portes ---------------------------------------------------------------------------------

## Relie chaque module fermé au réseau (coursives, halls, modules ouverts = unité 0) par une
## porte coulissante dans un mur droit. Jamais dans le mur NORD d'un module à toit (le toit,
## rendu incliné vers le nord, le masquerait). Labo / armurerie : une seule porte verrouillée.
static func _connect(L: FloorLayout, mods: Array[Mod], tubes: Array, rng: RandomNumberGenerator) -> bool:
	var tiles := L.tiles
	var unit := PackedInt32Array()
	unit.resize(W * H)
	unit.fill(-1)
	var closed: Array[Mod] = []
	for m in mods:
		if m.open or m.corridor:
			continue
		closed.append(m)
		m.unit = closed.size()
		for y in range(m.inner.position.y, m.inner.end.y):
			for x in range(m.inner.position.x, m.inner.end.x):
				var t := tiles[y * W + x]
				if t != T.VOID and t != T.WALL:
					unit[y * W + x] = m.unit
	for i in W * H:
		if unit[i] < 0 and tiles[i] != T.VOID and tiles[i] != T.WALL:
			unit[i] = 0
	var by_unit := {}
	for m2 in closed:
		by_unit[m2.unit] = m2
	var stairs := {}
	for st in L.stairs:
		stairs[st.cell] = true
	# Cases des tubes : le réseau réacteur/tube n'est relié que par la porte fixe du tube.
	var tube_cells := {}
	for tb0: Dictionary in tubes:
		for q: Rect2i in tb0["squares"]:
			for yy in range(q.position.y - 1, q.end.y + 1):
				for xx in range(q.position.x - 1, q.end.x + 1):
					tube_cells[Vector2i(xx, yy)] = true
	# Candidats : case mur entre deux unités, dans un mur droit.
	var groups := {}
	for y2 in range(1, H - 1):
		for x2 in range(1, W - 1):
			var i2 := y2 * W + x2
			if tiles[i2] != T.WALL or tube_cells.has(Vector2i(x2, y2)):
				continue
			var l := unit[i2 - 1]
			var rt := unit[i2 + 1]
			var up := unit[i2 - W]
			var dn := unit[i2 + W]
			if l >= 0 and rt >= 0 and l != rt and tiles[i2 - W] == T.WALL and tiles[i2 + W] == T.WALL:
				_cand(groups, l, rt, Vector2i(x2, y2), true)
			elif up >= 0 and dn >= 0 and up != dn and tiles[i2 - 1] == T.WALL and tiles[i2 + 1] == T.WALL:
				# Mur nord d'un module à toit (unité au sud) : porte invisible depuis la caméra.
				if dn > 0 and (by_unit[dn] as Mod).roof:
					continue
				_cand(groups, up, dn, Vector2i(x2, y2), false)
	var keys := _sorted_keys(groups)
	var door_cells := {}
	var connected := {0: true}
	var pending: Array[Mod] = []
	for m3 in closed:
		if m3.type != FloorLayout.ROOM_SUPER_LOOT:
			pending.append(m3)
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for m4 in pending.duplicate():
			var g := _pick(groups, keys, m4.unit, connected, by_unit, door_cells, stairs, false)
			if g.is_empty():
				continue
			_door(L, m4, g, door_cells, rng, FloorLayout.DoorState.CLOSED, &"")
			connected[m4.unit] = true
			pending.erase(m4)
			progress = true
	if not pending.is_empty():
		return false
	for m5 in closed:
		if m5.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		var g2 := _pick(groups, keys, m5.unit, connected, by_unit, door_cells, stairs, false)
		if g2.is_empty():
			return false
		_door(L, m5, g2, door_cells, rng, FloorLayout.DoorState.LOCKED, m5.key)
	# Boucles : portes supplémentaires (jamais vers une salle scellée, un ascenseur).
	var extra := Cfg.getf("extra_door_chance", 0.35)
	for m6 in closed:
		if m6.type == FloorLayout.ROOM_SUPER_LOOT or m6.role == &"elevator" or rng.randf() >= extra:
			continue
		var g3 := _pick(groups, keys, m6.unit, connected, by_unit, door_cells, stairs, true)
		if not g3.is_empty():
			_door(L, m6, g3, door_cells, rng, FloorLayout.DoorState.CLOSED, &"")
	# Tubes → salles rouges (porte fixe dans le mur ouest/est de la salle rouge).
	for tb: Dictionary in tubes:
		var dc: Vector2i = tb["door"]
		var inner_side := dc + (Vector2i.RIGHT if dc.x < W / 2 else Vector2i.LEFT)
		var outer_side := dc - (Vector2i.RIGHT if dc.x < W / 2 else Vector2i.LEFT)
		var ra := L.room_at(inner_side)
		var rb := L.room_at(outer_side)
		if ra == null or rb == null or L.get_tile(dc) != T.WALL:
			return false
		var tm: Mod = tb["mod"]
		L.add_door(dc, true, FloorLayout.DoorState.CLOSED, rb.id, ra.id, &"", tm.building.id)
	return true


static func _cand(groups: Dictionary, a: int, b: int, c: Vector2i, vertical: bool) -> void:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append([c, vertical])


## Clés de `groups` dans l'ordre de parcours de _pick (triées une seule fois par l'appelant :
## `groups` ne change plus une fois les candidats recensés).
static func _sorted_keys(groups: Dictionary) -> Array:
	var keys: Array = groups.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
	return keys


static func _pick(groups: Dictionary, keys: Array, u: int, connected: Dictionary, by_unit: Dictionary, door_cells: Dictionary, stairs: Dictionary, extra: bool) -> Dictionary:
	var best := {}
	var best_score := -1.0
	var mu: Mod = by_unit[u]
	for key: Vector2i in keys:
		if key.x != u and key.y != u:
			continue
		var v := key.y if key.x == u else key.x
		if not connected.has(v):
			continue
		if v > 0:
			var other: Mod = by_unit[v]
			if other.type == FloorLayout.ROOM_SUPER_LOOT or other.role == &"elevator":
				continue
		if (mu.role == &"elevator" or mu.type == FloorLayout.ROOM_SUPER_LOOT) and v > 0:
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
		if score > best_score:
			best_score = score
			best = {"v": v, "cands": cands}
	return best


static func _door_ok(cell: Vector2i, door_cells: Dictionary, stairs: Dictionary) -> bool:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if door_cells.has(cell + Vector2i(dx, dy)):
				return false
	for st: Vector2i in stairs:
		if absi(st.x - cell.x) + absi(st.y - cell.y) <= 1:
			return false
	return true


static func _door(L: FloorLayout, m: Mod, g: Dictionary, door_cells: Dictionary, rng: RandomNumberGenerator, state: int, key: StringName) -> void:
	var cands: Array = g["cands"]
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		var ca: Vector2i = a[0]
		var cb: Vector2i = b[0]
		return ca.x + ca.y * 1000 < cb.x + cb.y * 1000)
	var mid := cands.size() / 2
	var j := clampi(mid + rng.randi_range(-2, 2), 0, cands.size() - 1)
	var c: Array = cands[j]
	var cell: Vector2i = c[0]
	var vertical: bool = c[1]
	var a := L.room_at(cell + (Vector2i.LEFT if vertical else Vector2i.UP))
	var b := L.room_at(cell + (Vector2i.RIGHT if vertical else Vector2i.DOWN))
	var other := b if a == m.room else a
	var bid := m.building.id if m.building != null else -1
	L.add_door(cell, vertical, state, m.room.id, other.id if other != null else -1, key, bid)
	door_cells[cell] = true


# --- Validation ------------------------------------------------------------------------------

static func _validate(L: FloorLayout, mods: Array[Mod]) -> bool:
	if not FloorLayout.is_walkable_tile(L.get_tile(L.player_spawn)):
		return false
	var reach := Deck._flood(L, L.player_spawn, true)
	var tiles := L.tiles
	for i in tiles.size():
		var t := tiles[i]
		if t != T.VOID and t != T.WALL and reach[i] == 0:
			return false
	var open_reach := Deck._flood(L, L.player_spawn, false)
	for m in mods:
		if m.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		for y in range(m.inner.position.y, m.inner.end.y):
			for x in range(m.inner.position.x, m.inner.end.x):
				if open_reach[y * W + x] != 0:
					return false
	if L.extraction_cells.is_empty() or L.stairs.size() != 2:
		return false
	return true


# --- Contrat de rendu (Blender) -----------------------------------------------------------------

## Métadonnée « render_contract » : modules (rect murs compris, rôle, toit, rond), coursives,
## tubes (polyligne), centre de contrôle, réacteurs, décors hors jeu (antenne, panneaux, navettes).
static func _render_contract(L: FloorLayout, mods: Array[Mod], corridors: Array[Mod], tubes: Array, rng: RandomNumberGenerator) -> void:
	var ml: Array = []
	for m in mods:
		var e := {"room": m.room.id, "rect": m.rect, "inner": m.inner, "role": String(m.role), "slot": m.slot,
			"roof": m.roof, "open": m.open, "type": String(m.type), "damaged": m.damaged,
			"building": m.building.id if m.building != null else -1, "arch": String(m.arch)}
		if m.round_r > 0.0:
			e["round"] = [m.round_c.x, m.round_c.y, m.round_r]
		ml.append(e)
	var cl: Array = []
	for c in corridors:
		if c.room == null:
			continue
		cl.append({"room": c.room.id, "inner": c.inner, "role": String(c.role), "slot": c.slot,
			"building": c.building.id if c.building != null else -1})
	var tl: Array = []
	for tb: Dictionary in tubes:
		var sq: Array = tb["squares"]
		var a: Rect2i = sq[0]
		var b: Rect2i = sq[sq.size() - 1]
		var tm: Mod = tb["mod"]
		tl.append({"building": tm.building.id, "squares": sq, "door": tb["door"],
			"from": [a.position.x + a.size.x * 0.5, a.position.y + a.size.y * 0.5],
			"to": [b.position.x + b.size.x * 0.5, b.position.y + b.size.y * 0.5]})
	# Décors hors jeu (dans le vide) : antenne parabolique au nord-ouest, panneaux solaires.
	var decor: Array = []
	var flip := false   # disposition de la maquette : antenne au nord-ouest, panneaux au nord-est
	rng.randf()
	var dish := Vector2(24.5 + rng.randf_range(-1.0, 1.0), 1.5)
	var solar := Vector2(52.0 + rng.randf_range(-1.5, 1.5), 4.5)
	if flip:
		dish.x = W - dish.x
		solar.x = W - solar.x
	decor.append({"kind": "dish", "pos": [dish.x, dish.y], "size": 7.5, "rot": rng.randf_range(-30.0, 30.0)})
	decor.append({"kind": "solar_array", "pos": [solar.x, solar.y], "size": 14.0, "rot": rng.randf_range(25.0, 40.0) * (-1.0 if flip else 1.0)})
	for side in 2:
		var px := 4.5 + rng.randf_range(-0.6, 0.6)
		if side == 1:
			px = W - px
		decor.append({"kind": "solar_wing", "pos": [px, 78.0 + rng.randf_range(-1.5, 1.5)], "size": 14.0,
			"rot": rng.randf_range(-10.0, 10.0)})
	decor.append({"kind": "antenna", "pos": [W * 0.5 + rng.randf_range(4.0, 9.0) * (1.0 if flip else -1.0), 4.5], "size": 3.0, "rot": 0.0})
	L.set_meta(&"render_contract", {"kind": "ss_cross", "modules": ml, "corridors": cl, "tubes": tl,
		"dome": [DOME_C.x, DOME_C.y, DOME_R], "decor": decor, "spine": [SPINE_X0, SPINE_W]})
