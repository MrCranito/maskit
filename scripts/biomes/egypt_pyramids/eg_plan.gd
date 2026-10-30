extends RefCounted
## Surface (étage 0) des Pyramides d'Égypte façon maquette (docs/reference/cartes_2.png, colonne
## de droite) : un complexe de temples en grès vu de dessus, en CROIX, au coucher du soleil.
## Les bâtiments sont accolés (murs partagés) et en décrochement (plan en redans) :
##
##                 [ pyramide ]      [ TEMPLE NORD : salle hypostyle ]      [ pyramide ]
##        [ pavillon NW ]                       ║                       [ pavillon NE ]
##            [ aile W ][        GRAND TEMPLE : chambres / cour à piliers        ][ aile E ]
##   [pyr]    [ aile W ][            SANCTUAIRE doré au cœur (boss)              ][ aile E ]   [pyr]
##        [ pavillon SW ][                 ║ porte-pylône ║                 ][ pavillon SE ]
##                            [sphinx]  escalier / avenue  [sphinx]
##           [ grande pyramide ]          arrivée              [ petite pyramide ]
##
## Chaque bâtiment est un « module » (_module) : emprise murée ; avec cour, une bande de chambres
## (3 cases) entoure une cour à ciel ouvert reliée à l'extérieur par des portails de 2 cases
## (couloirs) ; sans cour, une grille de chambres. Les chambres reçoivent un rôle (tombe, couloir
## piégé, gardes, offrandes, embaumement, scribes, statues) et ~moitié un toit (s'efface quand on
## entre). Le trésor (super_loot, dalle scellée key_eg_treasury) est une chambre d'un pavillon
## d'angle ; le sanctuaire (boss) est au centre de la cour du grand temple, porte au sud.
## Variations par seed : découpe et rôles des chambres, toits, pavillon du trésor, position des
## petites pyramides, rochers, groupes de palmiers, ruines, dunes.
## Contrat de rendu (tools/prerender/eg_scene.py) en métadonnée « render_contract ».
## Ne pose aucun spawn d'ennemi / conteneur (voir eg_populator.gd). Déterministe.

const T := FloorLayout.Tile
const DS := FloorLayout.DoorState

const W := 72
const H := 88
const KEY_TREASURY := &"key_eg_treasury"

## Grand temple (emprise murs compris), sa cour à piliers, le sanctuaire.
const ENCLOSURE := Rect2i(21, 23, 30, 30)
const SANCTUARY := Rect2i(30, 32, 12, 12)
## Temple nord (salle hypostyle à ciel ouvert entourée de chambres), accolé au grand temple.
const NORTH := Rect2i(27, 6, 18, 18)
## Ailes et pavillons d'angle, détachés par des passages de sable (2 à 3 cases).
const WING_W := Rect2i(9, 28, 10, 18)
const WING_E := Rect2i(53, 28, 10, 18)
const PAV := {&"nw": Rect2i(4, 11, 15, 14), &"ne": Rect2i(53, 11, 15, 14), &"sw": Rect2i(3, 49, 16, 18), &"se": Rect2i(53, 49, 16, 18)}
## Porte-pylône au sud du grand temple (couloir central de 2 cases, corps de garde de chaque côté).
const GATEHOUSE := Rect2i(31, 52, 10, 8)
const PYLONS := [Rect2i(31, 52, 4, 8), Rect2i(37, 52, 4, 8)]
## Avenue des sphinx (arrivée), colosses assis, escalier monumental (décor, non bloquant).
const AVENUE := Rect2i(30, 60, 12, 27)
const SPHINX := [Rect2i(22, 63, 8, 11), Rect2i(42, 63, 8, 11)]
const STAIRS := Rect2i(31, 66, 10, 4)
const SPAWN := Vector2i(35, 85)
## Pyramides : grandes (coins), petites (milieu des côtés, décalées par seed ; bas-droite).
const PYR_BIG := [Rect2i(0, 0, 15, 10), Rect2i(57, 0, 15, 10), Rect2i(1, 70, 16, 17)]
const PYR_SMALL := [Rect2i(1, 31, 6, 6), Rect2i(65, 31, 6, 6), Rect2i(55, 72, 11, 11)]
const OASIS_POOL := Rect2i(1, 25, 5, 4)
const EXTRACTION := [Vector2i(66, 26), Vector2i(67, 26), Vector2i(66, 27), Vector2i(67, 27),
	Vector2i(3, 46), Vector2i(4, 46), Vector2i(3, 47), Vector2i(4, 47)]

## Rôles des chambres : [rôle, type, nom].
const CHAMBERS := [
	[&"tomb", FloorLayout.ROOM_LOOT, "Chambre funéraire"],
	[&"trap_hall", FloorLayout.ROOM_TRAP, "Couloir aux dalles piégées"],
	[&"guard_hall", FloorLayout.ROOM_COMBAT, "Salle des gardes"],
	[&"offering", FloorLayout.ROOM_LOOT, "Salle des offrandes"],
	[&"embalming", FloorLayout.ROOM_COMBAT, "Salle d'embaumement"],
	[&"scribe", FloorLayout.ROOM_REST, "Cellule des scribes"],
	[&"statue_hall", FloorLayout.ROOM_COMBAT, "Galerie des statues"],
]
const COURT_NAMES := {&"nw": "Cour du temple d'Anubis", &"ne": "Cour du temple de Thot", &"sw": "Cour du temple de Sobek", &"se": "Cour du temple de Bastet"}


class Mod:
	var rect: Rect2i            ## emprise murs compris
	var inner: Rect2i           ## sol
	var role: StringName = &"tomb"
	var arch: StringName = &"chamber"
	var type: StringName = FloorLayout.ROOM_COMBAT
	var name: String = ""
	var slot: String = ""       ## nom du module (central, north, wing_w, pav_nw…)
	var roof: bool = true
	var open: bool = false      ## cour à ciel ouvert reliée par portail (pas de porte requise)
	var key: StringName = &""
	var room: FloorLayout.Room = null
	var building: FloorLayout.Building = null
	var unit: int = -1
	var facade: Vector2i = Vector2i.ZERO   ## côté préféré de la porte


class Result:
	var layout: FloorLayout
	var mods: Array[Mod] = []


static func build(seed_value: int) -> Result:
	for attempt in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "eg_plan2", attempt])
		var r := _try(rng)
		if r != null:
			return r
	push_error("Egypt: surface impossible à générer (seed %d)" % seed_value)
	return null


static func _try(rng: RandomNumberGenerator) -> Result:
	var T0 := Time.get_ticks_usec()
	var L := FloorLayout.new(Vector2i(W, H))
	L.floor_index = 0
	var res := Result.new()
	res.layout = L
	var mods: Array[Mod] = []
	var columns: Array[Vector2i] = []
	var landmarks: Array = []
	var gates: Array[Rect2i] = []
	var used := {}
	# 1. Sable partout.
	L.fill_rect(Rect2i(1, 1, W - 2, H - 2), T.STREET)

	# 2. Modules (ordre : les murs partagés sont réécrits par le suivant, portails alignés).
	var treasury_slot: StringName = [&"nw", &"ne", &"sw", &"se"][rng.randi_range(0, 3)]
	var central := _module(L, ENCLOSURE, rng, "central", 3, [Vector2i.UP, Vector2i.DOWN], used, gates, 0.6, 9.0)
	var north := _module(L, NORTH, rng, "north", 3, [Vector2i.DOWN, Vector2i.UP], used, gates, 0.5)
	# Le grand temple est reconstruit après le temple nord : son portail nord rejoint celui du nord.
	for g: Rect2i in gates:
		L.fill_rect(g, T.FLOOR)
	var wing_w := _module(L, WING_W, rng, "wing_w", 0, [], used, gates, 0.6)
	var wing_e := _module(L, WING_E, rng, "wing_e", 0, [], used, gates, 0.6)
	var pav_gates := {&"nw": [Vector2i.RIGHT, Vector2i.DOWN], &"ne": [Vector2i.LEFT, Vector2i.DOWN], &"sw": [Vector2i.RIGHT, Vector2i.UP], &"se": [Vector2i.LEFT, Vector2i.UP]}
	var pavs := {}
	for k: StringName in PAV:
		pavs[k] = _module(L, PAV[k], rng, "pav_" + String(k), 3, pav_gates[k], used, gates, 0.5)
	var gh := _gatehouse(L, used)
	gates.append(Rect2i(35, GATEHOUSE.position.y, 2, GATEHOUSE.size.y))
	for g2: Rect2i in gates:
		L.fill_rect(g2, T.FLOOR)
	for part: Array in [central, north, wing_w, wing_e, gh]:
		mods.append_array(part)
	for k2: StringName in PAV:
		mods.append_array(pavs[k2])

	# 3. Cours : rôles. Grand temple = cour à piliers + sanctuaire ; nord = hypostyle ; pavillons = cours.
	for m in mods:
		if not m.open:
			continue
		if m.slot == "central":
			m.role = &"inner_court"
			m.name = "Cour à piliers du grand temple"
		elif m.slot == "north":
			m.role = &"hypostyle"
			m.arch = &"hypostyle"
			m.name = "Salle hypostyle"
		else:
			m.role = &"court"
			m.name = COURT_NAMES.get(StringName(m.slot.substr(4)), "Cour")
	# Sanctuaire au cœur de la cour du grand temple.
	L.fill_rect(SANCTUARY, T.WALL)
	L.fill_rect(SANCTUARY.grow(-1), T.FLOOR)
	var sa := Mod.new()
	sa.rect = SANCTUARY
	sa.inner = SANCTUARY.grow(-1)
	sa.role = &"sanctuary"
	sa.arch = &"sanctuary"
	sa.type = FloorLayout.ROOM_BOSS
	sa.name = "Sanctuaire du Pharaon"
	sa.slot = "sanctuary"
	# Sans toit : la planche montre le sanctuaire à ciel ouvert (dais à l'ankh d'or, torches).
	sa.roof = false
	sa.facade = Vector2i.DOWN
	mods.append(sa)
	# Colonnade de la cour à piliers (anneau à 1 case du bord), colonnes de l'hypostyle et des cours.
	var cc := _court_of(mods, "central")
	if cc.size.x > 0:
		for x in range(cc.position.x + 1, cc.end.x - 1, 3):
			for y in [cc.position.y + 1, cc.end.y - 2]:
				if x != 35 and x != 36:
					columns.append(Vector2i(x, y))
		for y2 in range(cc.position.y + 4, cc.end.y - 3, 3):
			for x2 in [cc.position.x + 1, cc.end.x - 2]:
				columns.append(Vector2i(x2, y2))
	var nc := _court_of(mods, "north")
	if nc.size.x > 0:
		for x3 in [nc.position.x + 1, nc.end.x - 2]:
			for y3 in range(nc.position.y + 1, nc.end.y - 1, 2):
				columns.append(Vector2i(x3, y3))
	for k3: StringName in PAV:
		var pc := _court_of(mods, "pav_" + String(k3))
		if pc.size.x >= 6 and pc.size.y >= 6:
			for c in [pc.position, Vector2i(pc.end.x - 1, pc.position.y), Vector2i(pc.position.x, pc.end.y - 1), pc.end - Vector2i.ONE]:
				columns.append(c)
	for c2 in columns:
		L.set_tile(c2, T.WALL)

	# 4. Trésor : une chambre d'un pavillon d'angle.
	var cands: Array[Mod] = []
	for m2 in mods:
		if m2.slot == "pav_" + String(treasury_slot) and not m2.open and m2.inner.size.x >= 3 and m2.inner.size.y >= 3:
			cands.append(m2)
	if cands.is_empty():
		return null
	var tm: Mod = cands[rng.randi_range(0, cands.size() - 1)]
	tm.role = &"treasury"
	tm.arch = &"treasury"
	tm.type = FloorLayout.ROOM_SUPER_LOOT
	tm.key = KEY_TREASURY
	tm.name = "Chambre du trésor"
	tm.roof = true

	# 5. Pyramides, sphinx, puis rochers / obélisques / palmiers / ruines / dunes.
	for p: Rect2i in PYR_BIG:
		L.fill_rect(p, T.WALL)
		landmarks.append({"kind": &"pyramid_big", "rect": p})
	var smalls: Array = []
	for i in PYR_SMALL.size():
		var p2: Rect2i = PYR_SMALL[i]
		if i < 2:
			p2.position.y += rng.randi_range(0, 4)
		L.fill_rect(p2, T.WALL)
		landmarks.append({"kind": &"pyramid_small", "rect": p2})
		smalls.append(p2)
	for s: Rect2i in SPHINX:
		L.fill_rect(s, T.WALL)
		landmarks.append({"kind": &"sphinx", "rect": s})
	if OS.has_environment("EG_DEBUG"):
		print("t_before_scatter %.1f" % ((Time.get_ticks_usec() - T0) / 1000.0))
	_scatter(L, rng, landmarks, smalls, mods)
	_fence(L)

	# 6. Bâtiments (chambres à toit) et salles.
	for m3 in mods:
		if m3.roof and not m3.open:
			m3.building = L.add_building(m3.arch, m3.name, m3.rect)
			m3.building.porch_side = m3.facade
	for m4 in mods:
		var bid := m4.building.id if m4.building != null else -1
		m4.room = L.add_room(m4.inner, m4.open, m4.type, m4.name, bid)
		m4.room.tags = PackedStringArray([String(m4.role), "open" if m4.open else String(m4.arch)])
		if m4.building != null:
			m4.room.tags.append("roofed")
	for g3: Rect2i in gates:
		var gr := L.add_room(g3, true, FloorLayout.ROOM_CORRIDOR, "Portail")
		gr.tags = PackedStringArray(["gate", "open"])
	var outs := [
		[Rect2i(0, 0, W, H), FloorLayout.ROOM_CORRIDOR, "Désert", "desert"],
		[Rect2i(1, 1, 70, 10), FloorLayout.ROOM_LOOT, "Plateau des pyramides", "desert"],
		[Rect2i(1, 11, 8, 59), FloorLayout.ROOM_EXTRACTION, "Dunes de l'ouest", "dunes"],
		[Rect2i(63, 11, 8, 59), FloorLayout.ROOM_COMBAT, "Dunes de l'est", "dunes"],
		[Rect2i(55, 25, 16, 3), FloorLayout.ROOM_EXTRACTION, "Campement des pilleurs", "camp"],
		[Rect2i(1, 24, 7, 7), FloorLayout.ROOM_REST, "Oasis", "oasis"],
		[Rect2i(19, 11, 8, 12), FloorLayout.ROOM_TRAP, "Allée des obélisques", "desert"],
		[Rect2i(45, 11, 8, 12), FloorLayout.ROOM_COMBAT, "Ruines de l'est", "desert"],
		[Rect2i(19, 24, 2, 29), FloorLayout.ROOM_CORRIDOR, "Passage ouest", "desert"],
		[Rect2i(51, 24, 2, 29), FloorLayout.ROOM_CORRIDOR, "Passage est", "desert"],
		[Rect2i(19, 53, 12, 13), FloorLayout.ROOM_COMBAT, "Parvis ouest", "desert"],
		[Rect2i(41, 53, 12, 13), FloorLayout.ROOM_COMBAT, "Parvis est", "desert"],
		[Rect2i(1, 67, 29, 20), FloorLayout.ROOM_COMBAT, "Nécropole sud-ouest", "desert"],
		[Rect2i(42, 67, 29, 20), FloorLayout.ROOM_LOOT, "Nécropole sud-est", "desert"],
		[AVENUE, FloorLayout.ROOM_SPAWN, "Avenue des Sphinx", "avenue"],
	]
	for o: Array in outs:
		var orm := L.add_room(o[0], true, o[1], o[2], -1)
		orm.tags = PackedStringArray([String(o[3]), "open"])

	if OS.has_environment("EG_DEBUG"):
		print("t_before_doors %.1f" % ((Time.get_ticks_usec() - T0) / 1000.0))
	# 7. Portes.
	if not _connect(L, mods, rng):
		if OS.has_environment("EG_DEBUG"):
			print("connect failed")
		return null

	# 8. Arrivée, extraction (campement + dunes de l'ouest).
	L.player_spawn = SPAWN
	for ex: Vector2i in EXTRACTION:
		if L.get_tile(ex) == T.STREET:
			L.extraction_cells.append(ex)
	if OS.has_environment("EG_DEBUG"):
		print("t_after_doors %.1f" % ((Time.get_ticks_usec() - T0) / 1000.0))
	if not _validate(L, mods):
		if OS.has_environment("EG_DEBUG"):
			print("validate failed")
			_debug_dump(L)
		return null
	res.mods = mods
	L.landmarks = landmarks
	_contract(L, mods, columns, landmarks, smalls, gates, rng)
	if OS.has_environment("EG_DEBUG"):
		print("t_end %.1f" % ((Time.get_ticks_usec() - T0) / 1000.0))
	return res


static func _court_of(mods: Array[Mod], slot: String) -> Rect2i:
	for m in mods:
		if m.open and m.slot == slot:
			return m.inner
	return Rect2i()


## Module de temple : emprise R murée. band > 0 : bande de chambres (band cases) autour d'une cour
## à ciel ouvert ; `gate_sides` : portails de 2 cases de la cour au bord de l'emprise (couloirs
## ajoutés à `gates`). band = 0 : grille de chambres. `roof_p` : probabilité de toit par chambre.
static func _module(L: FloorLayout, R: Rect2i, rng: RandomNumberGenerator, slot: String, band: int, gate_sides: Array,
		used: Dictionary, gates: Array[Rect2i], roof_p: float, seg_len: float = 6.0) -> Array[Mod]:
	var out: Array[Mod] = []
	L.fill_rect(R, T.WALL)
	var inner := R.grow(-1)
	var chambers: Array[Rect2i] = []
	var center := inner.get_center()
	if band > 0:
		var court := Rect2i(inner.position.x + band + 1, inner.position.y + band + 1, inner.size.x - 2 * band - 2, inner.size.y - 2 * band - 2)
		L.fill_rect(court, T.FLOOR)
		var gx := court.position.x + court.size.x / 2 - 1
		var gy := court.position.y + court.size.y / 2 - 1
		var strips := [[Rect2i(inner.position.x, inner.position.y, inner.size.x, band), Vector2i.UP],
			[Rect2i(inner.position.x, inner.end.y - band, inner.size.x, band), Vector2i.DOWN],
			[Rect2i(inner.position.x, court.position.y, band, court.size.y), Vector2i.LEFT],
			[Rect2i(inner.end.x - band, court.position.y, band, court.size.y), Vector2i.RIGHT]]
		for st: Array in strips:
			var r: Rect2i = st[0]
			var side: Vector2i = st[1]
			var horiz := side.y != 0
			var a0 := r.position.x if horiz else r.position.y
			var a1 := r.end.x if horiz else r.end.y
			var parts: Array = []
			if gate_sides.has(side):
				var g := gx if horiz else gy
				parts = [[a0, g - 1], [g + 3, a1]]
			else:
				parts = [[a0, a1]]
			for pa: Array in parts:
				var length: int = pa[1] - pa[0]
				if length < 2:
					continue
				var n := clampi(int(round(float(length) / seg_len)), 1, 4)
				for seg: Vector2i in _split(pa[0], pa[1], n, 3, rng):
					chambers.append(Rect2i(seg.x, r.position.y, seg.y, band) if horiz else Rect2i(r.position.x, seg.x, band, seg.y))
		for side2: Vector2i in gate_sides:
			var cr := Rect2i()
			match side2:
				Vector2i.UP:
					cr = Rect2i(gx, R.position.y, 2, court.position.y - R.position.y)
				Vector2i.DOWN:
					cr = Rect2i(gx, court.end.y, 2, R.end.y - court.end.y)
				Vector2i.LEFT:
					cr = Rect2i(R.position.x, gy, court.position.x - R.position.x, 2)
				_:
					cr = Rect2i(court.end.x, gy, R.end.x - court.end.x, 2)
			L.fill_rect(cr, T.FLOOR)
			gates.append(cr)
		var cm := Mod.new()
		cm.rect = court.grow(1)
		cm.inner = court
		cm.role = &"court"
		cm.arch = &"court"
		cm.type = FloorLayout.ROOM_COMBAT
		cm.slot = slot
		cm.roof = false
		cm.open = true
		out.append(cm)
	else:
		var nx := maxi(1, int(round(float(inner.size.x) / 6.0)))
		var ny := maxi(1, int(round(float(inner.size.y) / 6.0)))
		for sx: Vector2i in _split(inner.position.x, inner.end.x, nx, 3, rng):
			for sy: Vector2i in _split(inner.position.y, inner.end.y, ny, 3, rng):
				chambers.append(Rect2i(sx.x, sy.x, sx.y, sy.y))
	for c: Rect2i in chambers:
		L.fill_rect(c, T.FLOOR)
		var m := Mod.new()
		m.inner = c
		m.rect = c.grow(1)
		m.slot = slot
		var mc := c.get_center()
		var dv := mc - center
		# Porte de préférence vers la cour (module à cour), sinon vers l'extérieur.
		var sgn := -1 if band > 0 else 1
		if absi(dv.x) * R.size.y > absi(dv.y) * R.size.x:
			m.facade = Vector2i(signi(dv.x) * sgn, 0)
		else:
			m.facade = Vector2i(0, signi(dv.y) * sgn)
		if m.facade == Vector2i.ZERO:
			m.facade = Vector2i.DOWN
		var def: Array = CHAMBERS[rng.randi_range(0, CHAMBERS.size() - 1)]
		m.role = def[0]
		m.type = def[1]
		var nm: String = def[2]
		var k := 2
		while used.has(nm):
			nm = "%s %s" % [def[2], _roman(k)]
			k += 1
		used[nm] = true
		m.name = nm
		# Peu de toits : la planche montre presque toutes les salles à ciel ouvert.
		m.roof = rng.randf() < roof_p * 0.22
		out.append(m)
	return out


## Porte-pylône : couloir central (2 cases) dans l'axe du grand temple, corps de garde à toit de
## chaque côté (les masses des pylônes au rendu).
static func _gatehouse(L: FloorLayout, used: Dictionary) -> Array[Mod]:
	var out: Array[Mod] = []
	var G := GATEHOUSE
	L.fill_rect(G, T.WALL)
	for cr: Rect2i in [Rect2i(G.position.x + 1, G.position.y + 1, 2, G.size.y - 2), Rect2i(G.end.x - 3, G.position.y + 1, 2, G.size.y - 2)]:
		L.fill_rect(cr, T.FLOOR)
		var m := Mod.new()
		m.inner = cr
		m.rect = cr.grow(1)
		m.role = &"guard_hall"
		m.arch = &"pylon"
		m.type = FloorLayout.ROOM_COMBAT
		var nm := "Corps de garde " + ("ouest" if cr.position.x < 35 else "est")
		used[nm] = true
		m.name = nm
		m.slot = "gatehouse"
		m.roof = true
		m.facade = Vector2i.RIGHT if cr.position.x < 35 else Vector2i.LEFT
		out.append(m)
	return out


static func _roman(n: int) -> String:
	var out := ""
	for pair: Array in [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		while n >= int(pair[0]):
			out += String(pair[1])
			n -= int(pair[0])
	return out


## Découpe [a, b) en n morceaux (murs partagés d'une case entre morceaux), largeur ≥ wmin.
static func _split(a: int, b: int, n: int, wmin: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var total := b - a - (n - 1)
	while n > 1 and total / n < wmin:
		n -= 1
		total = b - a - (n - 1)
	var sizes: Array[int] = []
	for i in n:
		sizes.append(total / n)
	for i2 in total - (total / n) * n:
		sizes[i2] += 1
	for i3 in n - 1:
		var d := rng.randi_range(-1, 1)
		if sizes[i3] + d >= wmin and sizes[i3 + 1] - d >= wmin:
			sizes[i3] += d
			sizes[i3 + 1] -= d
	var x := a
	for s in sizes:
		out.append(Vector2i(x, s))
		x += s + 1
	return out


## Rochers, obélisques, ruines ensablées, palmiers en groupes, dunes : cases murées sur le sable,
## jamais près des bâtiments, de l'avenue, de l'arrivée ni des extractions.
static func _scatter(L: FloorLayout, rng: RandomNumberGenerator, landmarks: Array, smalls: Array, mods: Array[Mod]) -> void:
	var forbidden := {}
	var protect: Array[Rect2i] = [AVENUE.grow(1), Rect2i(63, 24, 8, 6), Rect2i(1, 44, 7, 6), OASIS_POOL.grow(1)]
	for r: Rect2i in [ENCLOSURE, NORTH, WING_W, WING_E, GATEHOUSE]:
		protect.append(r.grow(1))
	for k: StringName in PAV:
		protect.append((PAV[k] as Rect2i).grow(1))
	for p: Rect2i in PYR_BIG:
		protect.append(p.grow(1))
	for s: Rect2i in smalls:
		protect.append(s.grow(1))
	for s2: Rect2i in SPHINX:
		protect.append(s2.grow(1))
	for pr in protect:
		_forbid(forbidden, pr)
	# Obélisques fixes (angles du grand temple côté nord, entrée de l'avenue).
	for c: Vector2i in [Vector2i(20, 22), Vector2i(51, 22), Vector2i(29, 61), Vector2i(42, 61)]:
		var r0 := Rect2i(c, Vector2i.ONE)
		if L.get_tile(c) == T.STREET:
			L.fill_rect(r0, T.WALL)
			landmarks.append({"kind": &"obelisk", "rect": r0})
			_forbid(forbidden, r0.grow(1))
	# Palmiers en bosquets (oasis, abords des pavillons, nécropoles).
	var groves: Array[Vector2i] = [Vector2i(22, 14), Vector2i(49, 14), Vector2i(17, 3), Vector2i(54, 3), Vector2i(3, 40),
		Vector2i(68, 41), Vector2i(4, 62), Vector2i(23, 79), Vector2i(48, 79), Vector2i(68, 66), Vector2i(24, 56), Vector2i(48, 56)]
	for g: Vector2i in groves:
		var n := rng.randi_range(2, 4)
		for t in 14:
			if n <= 0:
				break
			var p2 := g + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
			var r2 := Rect2i(p2, Vector2i.ONE)
			if _free(L, r2, forbidden) and _free(L, r2.grow(1), {}):
				L.fill_rect(r2, T.WALL)
				landmarks.append({"kind": &"palm", "rect": r2})
				_forbid(forbidden, Rect2i(p2 - Vector2i.ONE, Vector2i(3, 3)))
				n -= 1
	var kinds := [[&"rock", Vector2i(2, 2), 9], [&"rock_small", Vector2i(1, 1), 12], [&"ruin", Vector2i(3, 2), 10], [&"dune", Vector2i(3, 2), 6]]
	for kd: Array in kinds:
		var n2: int = kd[2]
		var tries := 80
		while n2 > 0 and tries > 0:
			tries -= 1
			var sz: Vector2i = kd[1]
			var p3 := Vector2i(rng.randi_range(1, W - 1 - sz.x), rng.randi_range(1, H - 1 - sz.y))
			var r3 := Rect2i(p3, sz)
			if not _free(L, r3.grow(1), forbidden):
				continue
			L.fill_rect(r3, T.WALL)
			landmarks.append({"kind": kd[0], "rect": r3})
			_forbid(forbidden, r3.grow(2))
			n2 -= 1


static func _free(L: FloorLayout, r: Rect2i, forbidden: Dictionary) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if L.get_tile(c) != T.STREET or forbidden.has(c):
				return false
	return true


static func _forbid(forbidden: Dictionary, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			forbidden[Vector2i(x, y)] = true


## Bord de grille muré.
static func _fence(L: FloorLayout) -> void:
	for y in H:
		L.set_tile(Vector2i(0, y), T.WALL)
		L.set_tile(Vector2i(W - 1, y), T.WALL)
	for x in W:
		L.set_tile(Vector2i(x, 0), T.WALL)
		L.set_tile(Vector2i(x, H - 1), T.WALL)


static func _debug_dump(L: FloorLayout) -> void:
	var reach := L.flood_reachable(L.player_spawn, true)
	for y in H:
		var line := ""
		for x in W:
			var c := Vector2i(x, y)
			var t := L.get_tile(c)
			var ch := "#" if t == T.WALL else ("D" if t == T.DOOR else ("." if t == T.FLOOR else " "))
			if FloorLayout.is_walkable_tile(t) and not reach.has(c):
				ch = "?"
			line += ch
		print(line)
	print("extraction ", L.extraction_cells.size())


# --- Portes -------------------------------------------------------------------------

## Chaque chambre reliée à un espace déjà relié (sable = unité 0, cour à portail, chambre voisine)
## par une porte dans un mur droit ; jamais dans le mur nord d'une chambre à toit (le toit incliné
## la cacherait) ; trésor et sanctuaire : une seule porte (scellée pour le trésor), donnant sur une
## cour ou le sable, jamais sur une autre chambre.
static func _connect(L: FloorLayout, mods: Array[Mod], rng: RandomNumberGenerator) -> bool:
	var tiles := L.tiles
	var unit := PackedInt32Array()
	unit.resize(W * H)
	unit.fill(-1)
	var by_unit := {}
	# Cours d'abord : le sanctuaire (dans la cour) écrase ensuite ses cases.
	var order: Array[Mod] = []
	for m0 in mods:
		if m0.open:
			order.append(m0)
	for m1 in mods:
		if not m1.open:
			order.append(m1)
	for i in order.size():
		var m := order[i]
		m.unit = i + 1
		by_unit[m.unit] = m
		for y in range(m.inner.position.y, m.inner.end.y):
			for x in range(m.inner.position.x, m.inner.end.x):
				unit[y * W + x] = m.unit
	for j in W * H:
		if tiles[j] == T.WALL or tiles[j] == T.VOID:
			unit[j] = -1
		elif unit[j] < 0:
			unit[j] = 0
	var groups := {}
	for y2 in range(1, H - 1):
		for x2 in range(1, W - 1):
			var i2 := y2 * W + x2
			if tiles[i2] != T.WALL:
				continue
			var l := unit[i2 - 1]
			var rt := unit[i2 + 1]
			var up := unit[i2 - W]
			var dn := unit[i2 + W]
			if l >= 0 and rt >= 0 and l != rt and tiles[i2 - W] == T.WALL and tiles[i2 + W] == T.WALL:
				_cand(groups, l, rt, Vector2i(x2, y2), true)
			elif up >= 0 and dn >= 0 and up != dn and tiles[i2 - 1] == T.WALL and tiles[i2 + 1] == T.WALL:
				if dn > 0 and (by_unit[dn] as Mod).roof and not (by_unit[dn] as Mod).open:
					continue
				_cand(groups, up, dn, Vector2i(x2, y2), false)
	# Index : unité → [[voisine, candidats]…] (clés triées une fois : déterministe).
	var keys: Array = groups.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
	var by_u := {}
	for key: Vector2i in keys:
		for pair: Array in [[key.x, key.y], [key.y, key.x]]:
			if not by_u.has(pair[0]):
				by_u[pair[0]] = []
			(by_u[pair[0]] as Array).append([pair[1], groups[key]])
	var door_cells := {}
	var connected := {0: true}
	for m2 in order:
		if m2.open:
			connected[m2.unit] = true
	var pending: Array[Mod] = []
	for m3 in order:
		if not m3.open and m3.type != FloorLayout.ROOM_SUPER_LOOT and m3.type != FloorLayout.ROOM_BOSS:
			pending.append(m3)
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for m4 in pending.duplicate():
			var g := _pick(by_u, m4, connected, by_unit, door_cells)
			if g.is_empty():
				continue
			_door(L, m4, g, door_cells, rng, DS.OPEN if rng.randf() < 0.3 else DS.CLOSED, &"")
			connected[m4.unit] = true
			pending.erase(m4)
			progress = true
	if not pending.is_empty():
		if OS.has_environment("EG_DEBUG"):
			for pm in pending:
				print("sans porte : ", pm.name, " ", pm.inner, " roof ", pm.roof, " facade ", pm.facade)
		return false
	for m5 in order:
		if m5.type != FloorLayout.ROOM_SUPER_LOOT and m5.type != FloorLayout.ROOM_BOSS:
			continue
		var g2 := _pick(by_u, m5, connected, by_unit, door_cells)
		if g2.is_empty():
			return false
		_door(L, m5, g2, door_cells, rng, DS.LOCKED if m5.type == FloorLayout.ROOM_SUPER_LOOT else DS.CLOSED, m5.key)
	return true


static func _cand(groups: Dictionary, a: int, b: int, c: Vector2i, vertical: bool) -> void:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append([c, vertical])


static func _side_of(m: Mod, cell: Vector2i, vertical: bool) -> Vector2i:
	if vertical:
		return Vector2i.RIGHT if cell.x >= m.inner.end.x else Vector2i.LEFT
	return Vector2i.DOWN if cell.y >= m.inner.end.y else Vector2i.UP


static func _pick(by_u: Dictionary, mu: Mod, connected: Dictionary, by_unit: Dictionary, door_cells: Dictionary) -> Dictionary:
	var special := mu.type == FloorLayout.ROOM_SUPER_LOOT or mu.type == FloorLayout.ROOM_BOSS
	var best := {}
	var best_score := -1.0
	for e: Array in by_u.get(mu.unit, []):
		var v: int = e[0]
		if not connected.has(v):
			continue
		var open_v := v == 0
		if v > 0:
			var other: Mod = by_unit[v]
			if other.type == FloorLayout.ROOM_SUPER_LOOT or other.type == FloorLayout.ROOM_BOSS:
				continue
			if special and not other.open:
				continue
			open_v = other.open
		var cands: Array = []
		for c: Array in e[1]:
			if _door_ok(c[0], door_cells):
				cands.append(c)
		if cands.is_empty():
			continue
		var score := float(cands.size()) + (100.0 if open_v else 0.0)
		for c2: Array in cands:
			if _side_of(mu, c2[0], c2[1]) == mu.facade:
				score += 30.0
				break
		if score > best_score:
			best_score = score
			best = {"v": v, "cands": cands}
	return best


static func _door_ok(cell: Vector2i, door_cells: Dictionary) -> bool:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if door_cells.has(cell + Vector2i(dx, dy)):
				return false
	return true


static func _door(L: FloorLayout, m: Mod, g: Dictionary, door_cells: Dictionary, rng: RandomNumberGenerator, state: int, key: StringName) -> void:
	var cands: Array = g["cands"]
	var pref: Array = []
	for c0: Array in cands:
		if _side_of(m, c0[0], c0[1]) == m.facade:
			pref.append(c0)
	if not pref.is_empty():
		cands = pref
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		var ca: Vector2i = a[0]
		var cb: Vector2i = b[0]
		return ca.x + ca.y * 1000 < cb.x + cb.y * 1000)
	var j := clampi(cands.size() / 2 + rng.randi_range(-1, 1), 0, cands.size() - 1)
	var c: Array = cands[j]
	var cell: Vector2i = c[0]
	var vertical: bool = c[1]
	var a := L.room_at(cell + (Vector2i.LEFT if vertical else Vector2i.UP))
	var b := L.room_at(cell + (Vector2i.RIGHT if vertical else Vector2i.DOWN))
	var other := b if a == m.room else a
	var bid := m.building.id if m.building != null else -1
	L.add_door(cell, vertical, state, m.room.id, other.id if other != null else -1, key, bid)
	door_cells[cell] = true


static func _validate(L: FloorLayout, mods: Array[Mod]) -> bool:
	if not FloorLayout.is_walkable_tile(L.get_tile(L.player_spawn)):
		return false
	var reach := _flood(L, true)
	var tiles := L.tiles
	for i in W * H:
		if reach[i] == 0 and FloorLayout.is_walkable_tile(tiles[i]):
			if OS.has_environment("EG_DEBUG"):
				print("unreachable ", Vector2i(i % W, i / W))
			return false
	var open_reach := _flood(L, false)
	for m in mods:
		if m.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		for y2 in range(m.inner.position.y, m.inner.end.y):
			for x2 in range(m.inner.position.x, m.inner.end.x):
				if open_reach[y2 * W + x2] != 0:
					return false
	return L.extraction_cells.size() >= 4


## Remplissage depuis l'arrivée (PackedByteArray : 1 = atteint) ; portes verrouillées
## franchies seulement si `through_locked`.
static func _flood(L: FloorLayout, through_locked: bool) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(W * H)
	var tiles := L.tiles
	var locked := PackedByteArray()
	locked.resize(W * H)
	if not through_locked:
		for d in L.doors:
			if d.state == DS.LOCKED:
				locked[d.cell.y * W + d.cell.x] = 1
	var start := L.player_spawn.y * W + L.player_spawn.x
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head := 0
	var total := W * H
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		# 4 voisins déroulés (pas d'allocation par case).
		var n := i - 1
		if n >= 0 and seen[n] == 0 and tiles[n] != T.WALL and tiles[n] != T.VOID and (through_locked or tiles[n] != T.DOOR or locked[n] == 0):
			seen[n] = 1
			queue.append(n)
		n = i + 1
		if n < total and seen[n] == 0 and tiles[n] != T.WALL and tiles[n] != T.VOID and (through_locked or tiles[n] != T.DOOR or locked[n] == 0):
			seen[n] = 1
			queue.append(n)
		n = i - W
		if n >= 0 and seen[n] == 0 and tiles[n] != T.WALL and tiles[n] != T.VOID and (through_locked or tiles[n] != T.DOOR or locked[n] == 0):
			seen[n] = 1
			queue.append(n)
		n = i + W
		if n < total and seen[n] == 0 and tiles[n] != T.WALL and tiles[n] != T.VOID and (through_locked or tiles[n] != T.DOOR or locked[n] == 0):
			seen[n] = 1
			queue.append(n)
	return seen


# --- Contrat de rendu ------------------------------------------------------------------

static func _contract(L: FloorLayout, mods: Array[Mod], columns: Array[Vector2i], landmarks: Array, smalls: Array, gates: Array[Rect2i], rng: RandomNumberGenerator) -> void:
	var ml: Array = []
	var courts: Array = []
	for m in mods:
		ml.append({"room": m.room.id, "rect": m.rect, "inner": m.inner, "role": String(m.role), "arch": String(m.arch),
			"slot": m.slot, "roof": m.roof and not m.open, "open": m.open, "type": String(m.type), "name": m.name,
			"building": m.building.id if m.building != null else -1, "facade": m.facade})
		if m.open:
			courts.append(m.inner)
	var cols: Array = []
	for c in columns:
		cols.append(c)
	# Torches : angles des cours, devant le sanctuaire, entrées des portails.
	var torches: Array = []
	for cr: Rect2i in courts:
		for p in [cr.position, Vector2i(cr.end.x - 1, cr.position.y), Vector2i(cr.position.x, cr.end.y - 1), cr.end - Vector2i.ONE]:
			var q: Vector2i = p
			if L.get_tile(q) == T.WALL:
				q += Vector2i(1 if q.x == cr.position.x else -1, 1 if q.y == cr.position.y else -1)
			if L.get_tile(q) == T.FLOOR:
				torches.append(q)
	for p2 in [Vector2i(34, 44), Vector2i(37, 44), Vector2i(34, 60), Vector2i(37, 60), Vector2i(31, 75), Vector2i(40, 75)]:
		if FloorLayout.is_walkable_tile(L.get_tile(p2)):
			torches.append(p2)
	var gl: Array = []
	for g: Rect2i in gates:
		gl.append([g.position.x, g.position.y])
	var gate_rects: Array = []
	for g2: Rect2i in gates:
		gate_rects.append(g2)
	# Chemins pavés (rendu, non bloquants) : du portail de chaque pavillon vers l'avenue / le parvis.
	var paths: Array = []
	for g3: Rect2i in gates:
		var outside := false
		for y in range(g3.position.y, g3.end.y):
			for x in range(g3.position.x, g3.end.x):
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if L.get_tile(Vector2i(x, y) + d) == T.STREET:
						outside = true
		if outside:
			paths.append([g3.get_center(), Vector2i(36, 63)])
	L.set_meta(&"render_contract", {"kind": "egypt_surface", "modules": ml, "columns": cols, "torches": torches,
		"enclosure": ENCLOSURE, "inner": _court_of(mods, "central"), "sanctuary": SANCTUARY, "pylons": PYLONS,
		"gatehouse": GATEHOUSE, "hypostyle": _court_of(mods, "north"), "avenue": AVENUE, "stairs": STAIRS,
		"courts": courts, "pyr_small": smalls, "landmarks": landmarks, "gates": gl, "gate_rects": gate_rects,
		"paths": paths, "oasis_pool": OASIS_POOL, "camp": [[64, 16], [66, 24], [69, 16]]})
