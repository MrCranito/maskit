extends RefCounted
## Rez-de-chaussée (0) des Galeries Lumière façon maquette (docs/reference/cartes.png, colonne
## « Centre commercial abandonné ») : format portrait, grand bâtiment rectangulaire vu de dessus,
## de nuit, avec le PARKING extérieur au sud.
##   - ceinture de boutiques tout autour (rangée nord, ailes ouest et est, rangée sud) ;
##   - bloc d'ancrage (cinéma) au milieu de la rangée nord, en saillie ;
##   - grande galerie carrelée au centre : îlots de boutiques, deux paires d'ESCALATORS
##     (escaliers vers la galerie haute et le parking souterrain), ATRIUM carré à FONTAINE
##     bordé de jardinières (4 ouvertures) ;
##   - hall d'entrée vitré au sud, ouvert sur le parking (places marquées, terre-pleins plantés,
##     voitures abandonnées) où arrive le joueur ;
##   - quais de livraison (extraction) aux deux coins nord ; bijouterie scellée (super_loot),
##     salle d'arcade, café à enseigne néon.
## Boutiques « fermées » (toit qui s'efface quand on entre) ou « ouvertes » (vues en coupe,
## comme la maquette). Portes dans un mur droit, jamais dans le mur NORD d'une boutique à toit
## (le toit, rendu incliné vers le nord, la cacherait).
## Variations par seed : profondeur des ailes, découpe des boutiques, rôles et noms, boutiques
## à toit, position de la bijouterie et de l'arcade.
## Contrat de rendu (tools/prerender/mall_scene.py) en métadonnée « render_contract ».
## Ne pose aucun spawn (voir mall_populator.gd). Déterministe.

const Cfg := preload("res://scripts/biomes/mall/mall_config.gd")
const Layout := preload("res://scripts/biomes/mall/mall_layout.gd")
const T := FloorLayout.Tile
const DS := FloorLayout.DoorState

const W := 66
const H := 124
## Galerie centrale (sol carrelé) entre les ailes et les rangées nord / sud.
const GAL := Rect2i(15, 14, 36, 83)
## Atrium (bordure = jardinières, murs compris).
const ATRIUM := Rect2i(22, 41, 22, 26)
## Escalators (corps, murs) ; le pied (escalier) est la case juste au sud.
const ESC_N := [Rect2i(29, 22, 3, 12), Rect2i(34, 22, 3, 12)]
const ESC_S := [Rect2i(27, 75, 3, 15), Rect2i(36, 75, 3, 15)]
const ISLANDS := [Rect2i(18, 24, 8, 8), Rect2i(40, 24, 8, 8), Rect2i(17, 72, 8, 8), Rect2i(41, 72, 8, 8)]
const HALL := Rect2i(24, 97, 18, 9)
const PARKING := Rect2i(1, 106, 64, 16)
const TREES := [Rect2i(21, 109, 2, 12), Rect2i(43, 109, 2, 12)]

const EXTRA_NAMES := {&"dock": "Quai de livraison", &"cinema": "Cinéma Le Paradiso", &"arcade": "Salle d'arcade Néon Galaxy"}


class Mod:
	var rect: Rect2i
	var inner: Rect2i
	var role: StringName = &"shop_clothes"
	var arch: StringName = &"clothes"
	var type: StringName = FloorLayout.ROOM_COMBAT
	var name: String = ""
	var slot: String = ""
	var roof: bool = false
	var key: StringName = &""
	var facade: Vector2i = Vector2i.ZERO   ## côté de la porte principale (vers la galerie)
	var room: FloorLayout.Room = null
	var building: FloorLayout.Building = null
	var unit: int = -1


class Result:
	var layout: FloorLayout
	var mods: Array[Mod] = []


static func mirror_rect(r: Rect2i) -> Rect2i:
	return Rect2i(W - r.end.x, r.position.y, r.size.x, r.size.y)


static func build(seed_value: int, stairs_targets: Dictionary) -> Result:
	for attempt in 10:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "mall_plan", attempt])
		var r := _try(rng, stairs_targets)
		if r != null:
			return r
	push_error("Mall: rez-de-chaussée impossible à générer (seed %d)" % seed_value)
	return null


## Cases des escalators du rez-de-chaussée (pieds) : {"up": [2 cases], "down": [2 cases]}.
static func stair_cells() -> Dictionary:
	var up: Array[Vector2i] = []
	var down: Array[Vector2i] = []
	for e: Rect2i in ESC_N:
		up.append(Vector2i(e.position.x + 1, e.end.y))
	for e2: Rect2i in ESC_S:
		down.append(Vector2i(e2.position.x + 1, e2.end.y))
	return {"up": up, "down": down}


static func _try(rng: RandomNumberGenerator, targets: Dictionary) -> Result:
	var L := FloorLayout.new(Vector2i(W, H))
	L.floor_index = 0
	var res := Result.new()
	res.layout = L
	var mods: Array[Mod] = []
	var used := {}
	var belt := rng.randi_range(13, 15)   # bord intérieur des ailes (x du mur côté galerie)
	# 1. Sols ouverts : galerie, hall, parking.
	var gal := Rect2i(belt + 1, GAL.position.y, W - 2 * (belt + 1), GAL.size.y)
	L.fill_rect(gal, T.STREET)
	L.fill_rect(Rect2i(HALL.position.x + 1, HALL.position.y, HALL.size.x - 2, HALL.size.y - 1), T.STREET)
	L.fill_rect(PARKING, T.STREET)
	# Portes vitrées du hall vers le parking.
	L.fill_rect(Rect2i(28, HALL.end.y - 1, 10, 1), T.STREET)

	# 2. Ceinture de boutiques.
	# Ailes ouest / est : découpe verticale (hauteur 7 à 11), porte sur le mur côté galerie.
	for side in 2:
		var x0 := 1
		var bw := belt
		var ys := _split(2, GAL.end.y, 7, 11, rng)
		for i in ys.size():
			var r := Rect2i(x0, ys[i].x, bw, ys[i].y)
			if side == 1:
				r = mirror_rect(r)
			var m := _shop(r, rng, used)
			m.slot = ("belt_w" if side == 0 else "belt_e")
			m.facade = Vector2i.RIGHT if side == 0 else Vector2i.LEFT
			if i == 0:
				m.role = &"service"
				m.arch = &"dock"
				m.type = FloorLayout.ROOM_EXTRACTION
				m.name = "%s %s" % [EXTRA_NAMES[&"dock"], "ouest" if side == 0 else "est"]
				m.slot = "dock_" + ("w" if side == 0 else "e")
			else:
				m.roof = rng.randf() < 0.12
			mods.append(m)
	# Rangée nord (entre les ailes) avec le cinéma en saillie au milieu.
	var cine := Rect2i(26, 1, 14, 13)
	var cm := Mod.new()
	cm.rect = cine
	cm.inner = cine.grow(-1)
	cm.role = &"cinema_lobby"
	cm.arch = &"cinema"
	cm.type = FloorLayout.ROOM_COMBAT
	cm.name = EXTRA_NAMES[&"cinema"]
	cm.roof = true
	cm.slot = "cinema"
	cm.facade = Vector2i.DOWN
	mods.append(cm)
	for seg: Vector2i in [Vector2i(belt, cine.position.x), Vector2i(cine.end.x - 1, W - 1 - belt)]:
		var xs := _split(seg.x, seg.y, 6, 9, rng)
		for xx: Vector2i in xs:
			var m2 := _shop(Rect2i(xx.x, 2, xx.y, 12), rng, used)
			m2.slot = "row_n"
			m2.facade = Vector2i.DOWN
			m2.roof = rng.randf() < 0.25
			mods.append(m2)
	# Rangée sud : boutiques de part et d'autre du hall (ouvertes, porte au nord).
	for seg2: Vector2i in [Vector2i(belt, HALL.position.x), Vector2i(HALL.end.x - 1, W - 1 - belt)]:
		var xs2 := _split(seg2.x, seg2.y, 6, 9, rng)
		for xx2: Vector2i in xs2:
			var m3 := _shop(Rect2i(xx2.x, GAL.end.y, xx2.y, HALL.end.y - GAL.end.y), rng, used)
			m3.slot = "row_s"
			m3.facade = Vector2i.UP
			mods.append(m3)
	# Coins sud-ouest / sud-est (sous les ailes) : réserves ouvertes.
	for side2 in 2:
		var cr := Rect2i(1, GAL.end.y, belt, HALL.end.y - GAL.end.y)
		if side2 == 1:
			cr = mirror_rect(cr)
		var m4 := _shop(cr, rng, used)
		m4.role = &"stockroom"
		m4.arch = &"service"
		m4.type = FloorLayout.ROOM_LOOT
		m4.name = "Réserve " + ("ouest" if side2 == 0 else "est")
		m4.slot = "corner_s"
		mods.append(m4)
	# Îlots de boutiques dans la galerie (ouverts, vus en coupe comme sur la maquette).
	for i2 in ISLANDS.size():
		var ir: Rect2i = ISLANDS[i2]
		var m5 := _shop(ir, rng, used)
		m5.slot = "island"
		m5.roof = false
		mods.append(m5)
	# Supérette : la plus grande boutique de la rangée nord.
	var big: Mod = null
	for mm in mods:
		if mm.slot == "row_n" and (big == null or mm.inner.get_area() > big.inner.get_area()):
			big = mm
	if big != null:
		big.role = &"supermarket"
		big.arch = &"supermarket"
		big.type = FloorLayout.ROOM_LOOT
		big.name = "Supérette Primeur"
	# Café à enseigne néon : une boutique de la rangée sud ; arcade : une boutique d'aile.
	var row_s: Array[Mod] = []
	var belts: Array[Mod] = []
	for m6 in mods:
		if m6.slot == "row_s":
			row_s.append(m6)
		elif m6.slot.begins_with("belt_"):
			belts.append(m6)
	if not row_s.is_empty():
		var cafe: Mod = row_s[rng.randi_range(0, row_s.size() - 1)]
		cafe.role = &"shop_cafe"
		cafe.arch = &"cafe"
		cafe.type = FloorLayout.ROOM_REST
		cafe.name = "Café des Arcades"
	var arc: Mod = belts[rng.randi_range(0, belts.size() - 1)]
	arc.role = &"arcade"
	arc.arch = &"arcade"
	arc.type = FloorLayout.ROOM_COMBAT
	arc.name = EXTRA_NAMES[&"arcade"]
	arc.roof = false
	# Bijouterie scellée : une boutique d'aile (porte unique verrouillée sur la galerie).
	var jcands: Array[Mod] = []
	for b2 in belts:
		if b2 != arc and b2.rect.position.y > GAL.position.y + 1:
			jcands.append(b2)
	var jw: Mod = jcands[rng.randi_range(0, jcands.size() - 1)]
	jw.role = &"shop_jewelry"
	jw.arch = &"jewelry"
	jw.type = FloorLayout.ROOM_SUPER_LOOT
	jw.key = Layout.KEY_JEWELRY
	jw.name = "Bijouterie Éclat d'Or"
	jw.roof = true

	# 3. Creusement des boutiques.
	for m7 in mods:
		L.fill_rect(m7.rect, T.WALL)
	for m8 in mods:
		L.fill_rect(m8.inner, T.FLOOR)
	# Obstacles de la galerie : jardinières de l'atrium (4 ouvertures), escalators.
	var a := ATRIUM
	for x in range(a.position.x, a.end.x):
		for y in [a.position.y, a.end.y - 1]:
			if absi(x * 2 + 1 - (a.position.x + a.end.x)) > 4:
				L.set_tile(Vector2i(x, y), T.WALL)
	for y2 in range(a.position.y, a.end.y):
		for x2 in [a.position.x, a.end.x - 1]:
			if absi(y2 * 2 + 1 - (a.position.y + a.end.y)) > 4:
				L.set_tile(Vector2i(x2, y2), T.WALL)
	for e: Rect2i in ESC_N + ESC_S:
		L.fill_rect(e, T.WALL)
	for t: Rect2i in TREES:
		L.fill_rect(t, T.WALL)
	_fence(L)

	# 4. Escaliers (pieds des escalators).
	var sc := stair_cells()
	var up_t: Array = targets.get("up", [])
	var down_t: Array = targets.get("down", [])
	for i3 in 2:
		var c: Vector2i = sc["up"][i3]
		_stairs(L, c, true, 1, up_t[i3] if i3 < up_t.size() else c)
		var c2: Vector2i = sc["down"][i3]
		_stairs(L, c2, false, -1, down_t[i3] if i3 < down_t.size() else c2)

	# 5. Bâtiments (boutiques à toit) et salles.
	for m9 in mods:
		if m9.roof:
			m9.building = L.add_building(m9.arch, m9.name, m9.rect)
	for m10 in mods:
		var bid := m10.building.id if m10.building != null else -1
		m10.room = L.add_room(m10.inner, false, m10.type, m10.name, bid)
		m10.room.tags = PackedStringArray([String(m10.role), String(m10.arch)])
		if m10.roof:
			m10.room.tags.append("roofed")
	var gal_room := L.add_room(gal, true, FloorLayout.ROOM_CORRIDOR, "Galerie des Lumières")
	gal_room.tags = PackedStringArray(["gallery", "open"])
	var atr := L.add_room(a.grow(-1), true, FloorLayout.ROOM_COMBAT, "Atrium de la fontaine")
	atr.tags = PackedStringArray(["atrium", "open"])
	var hall := L.add_room(Rect2i(HALL.position.x + 1, HALL.position.y, HALL.size.x - 2, HALL.size.y), true,
		FloorLayout.ROOM_COMBAT, "Hall d'entrée")
	hall.tags = PackedStringArray(["entrance", "open"])
	var park := L.add_room(PARKING, true, FloorLayout.ROOM_SPAWN, "Parking des Galeries")
	park.tags = PackedStringArray(["parking", "open"])

	# 6. Portes.
	if not _connect(L, mods, rng):
		return null

	# 7. Apparition (parking), extraction (quais de livraison).
	L.player_spawn = Vector2i(32 + rng.randi_range(-2, 1), PARKING.end.y - 3)
	for m11 in mods:
		if m11.type != FloorLayout.ROOM_EXTRACTION:
			continue
		var ctr := m11.inner.get_center()
		for dy in 2:
			for dx in 2:
				var ec := Vector2i(ctr.x - 1 + dx, m11.inner.position.y + 1 + dy)
				if L.get_tile(ec) == T.FLOOR:
					L.extraction_cells.append(ec)
	if not _validate(L, mods):
		return null
	res.mods = mods
	_contract(L, mods, rng)
	return res


static func _shop(r: Rect2i, rng: RandomNumberGenerator, used: Dictionary) -> Mod:
	var m := Mod.new()
	m.rect = r
	m.inner = r.grow(-1)
	var def: Array = Layout._shop_def(rng, used)
	m.arch = def[0]
	m.role = def[1]
	m.name = def[2]
	m.type = FloorLayout.ROOM_REST if m.role == &"shop_cafe" else Layout._shop_type(rng)
	return m


## Découpe [a, b) (murs partagés : chaque rectangle va de x à x + w, w ≥ min+2) en morceaux.
static func _split(a: int, b: int, wmin: int, wmax: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var total := b - a
	var n := maxi(1, int(round(float(total) / float((wmin + wmax) / 2))))
	while n > 1 and total / n < wmin:
		n -= 1
	var sizes: Array[int] = []
	for i in n:
		sizes.append(total / n)
	for i2 in total - (total / n) * n:
		sizes[i2] += 1
	for i3 in n - 1:
		var d := rng.randi_range(-2, 2)
		if sizes[i3] + d >= wmin and sizes[i3 + 1] - d >= wmin:
			sizes[i3] += d
			sizes[i3 + 1] -= d
	var x := a
	for s in sizes:
		out.append(Vector2i(x, s + 1))
		x += s
	return out


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


static func _stairs(L: FloorLayout, c: Vector2i, up: bool, target: int, target_cell: Vector2i) -> void:
	L.set_tile(c, T.STAIRS_UP if up else T.STAIRS_DOWN)
	var s := FloorLayout.Stairs.new()
	s.cell = c
	s.up = up
	s.target_floor = target
	s.target_cell = target_cell
	L.stairs.append(s)


# --- Portes -------------------------------------------------------------------------

## Chaque boutique reliée à la galerie (unité 0) ou à une boutique voisine déjà reliée, par une
## porte dans un mur droit ; jamais dans le mur nord d'une boutique à toit ; bijouterie : une
## porte verrouillée sur la galerie.
static func _connect(L: FloorLayout, mods: Array[Mod], rng: RandomNumberGenerator) -> bool:
	var tiles := L.tiles
	var unit := PackedInt32Array()
	unit.resize(W * H)
	unit.fill(-1)
	var by_unit := {}
	for i in mods.size():
		var m := mods[i]
		m.unit = i + 1
		by_unit[m.unit] = m
		for y in range(m.inner.position.y, m.inner.end.y):
			for x in range(m.inner.position.x, m.inner.end.x):
				unit[y * W + x] = m.unit
	for j in W * H:
		if unit[j] < 0 and tiles[j] != T.VOID and tiles[j] != T.WALL:
			unit[j] = 0
	var stairs := {}
	for st in L.stairs:
		stairs[st.cell] = true
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
				if dn > 0 and (by_unit[dn] as Mod).roof:
					continue
				# Pas de porte de boutique sur le parking (façade extérieure) : seulement le hall.
				if up == 0 and L.get_tile(Vector2i(x2, y2 - 1)) == T.STREET and y2 - 1 >= PARKING.position.y:
					continue
				if dn == 0 and y2 + 1 >= PARKING.position.y:
					continue
				_cand(groups, up, dn, Vector2i(x2, y2), false)
	var door_cells := {}
	var connected := {0: true}
	var pending: Array[Mod] = []
	for m2 in mods:
		if m2.type != FloorLayout.ROOM_SUPER_LOOT:
			pending.append(m2)
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for m3 in pending.duplicate():
			var g := _pick(groups, m3, connected, by_unit, door_cells, stairs, false)
			if g.is_empty():
				continue
			_door(L, m3, g, door_cells, rng, _shutter(rng), &"")
			connected[m3.unit] = true
			pending.erase(m3)
			progress = true
	if not pending.is_empty():
		return false
	for m4 in mods:
		if m4.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		var g2 := _pick(groups, m4, connected, by_unit, door_cells, stairs, false)
		if g2.is_empty():
			return false
		_door(L, m4, g2, door_cells, rng, DS.LOCKED, m4.key)
	return true


static func _shutter(rng: RandomNumberGenerator) -> int:
	return DS.OPEN if rng.randf() < Cfg.getf("mall_shutter_open_chance", 0.3) else DS.CLOSED


static func _cand(groups: Dictionary, a: int, b: int, c: Vector2i, vertical: bool) -> void:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append([c, vertical])


static func _pick(groups: Dictionary, mu: Mod, connected: Dictionary, by_unit: Dictionary, door_cells: Dictionary, stairs: Dictionary, extra: bool) -> Dictionary:
	var u := mu.unit
	var best := {}
	var best_score := -1.0
	var keys: Array = groups.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
	for key: Vector2i in keys:
		if key.x != u and key.y != u:
			continue
		var v := key.y if key.x == u else key.x
		if not connected.has(v):
			continue
		if v > 0:
			var other: Mod = by_unit[v]
			if other.type == FloorLayout.ROOM_SUPER_LOOT:
				continue
			if mu.type == FloorLayout.ROOM_SUPER_LOOT:
				continue
		var cands: Array = []
		for c: Array in groups[key]:
			if _door_ok(c[0], door_cells, stairs):
				cands.append(c)
		if cands.is_empty():
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
		if absi(st.x - cell.x) + absi(st.y - cell.y) <= 2:
			return false
	return true


static func _door(L: FloorLayout, m: Mod, g: Dictionary, door_cells: Dictionary, rng: RandomNumberGenerator, state: int, key: StringName) -> void:
	var cands: Array = g["cands"]
	cands.sort_custom(func(a: Array, b: Array) -> bool:
		var ca: Vector2i = a[0]
		var cb: Vector2i = b[0]
		return ca.x + ca.y * 1000 < cb.x + cb.y * 1000)
	var j := clampi(cands.size() / 2 + rng.randi_range(-2, 2), 0, cands.size() - 1)
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
	var reach := L.flood_reachable(L.player_spawn, true)
	for y in H:
		for x in W:
			if FloorLayout.is_walkable_tile(L.get_tile(Vector2i(x, y))) and not reach.has(Vector2i(x, y)):
				return false
	var open_reach := L.flood_reachable(L.player_spawn, false)
	for m in mods:
		if m.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		for y2 in range(m.inner.position.y, m.inner.end.y):
			for x2 in range(m.inner.position.x, m.inner.end.x):
				if open_reach.has(Vector2i(x2, y2)):
					return false
	return L.extraction_cells.size() >= 2


# --- Contrat de rendu ------------------------------------------------------------------

static func _contract(L: FloorLayout, mods: Array[Mod], rng: RandomNumberGenerator) -> void:
	var ml: Array = []
	for m in mods:
		ml.append({"room": m.room.id, "rect": m.rect, "inner": m.inner, "role": String(m.role), "arch": String(m.arch),
			"slot": m.slot, "roof": m.roof, "type": String(m.type), "name": m.name,
			"building": m.building.id if m.building != null else -1, "facade": m.facade,
			"neon": rng.randi_range(0, 5)})
	var esc: Array = []
	for e: Rect2i in ESC_N + ESC_S:
		esc.append({"rect": e, "up": ESC_N.has(e)})
	# Voitures abandonnées hors jeu (rues autour du bâtiment) et lampadaires du parking.
	var cars: Array = []
	for i in 7:
		var side := rng.randi_range(0, 2)
		var p := Vector2(rng.randf_range(2.0, W - 2.0), rng.randf_range(-3.0, -1.0)) if side == 0 \
			else Vector2(rng.randf_range(-3.5, -1.5) if side == 1 else W + rng.randf_range(1.5, 3.5), rng.randf_range(8.0, 100.0))
		cars.append({"pos": [p.x, p.y], "rot": rng.randf_range(-20.0, 20.0) + (90.0 if side > 0 else 0.0), "color": rng.randi_range(0, 4)})
	L.set_meta(&"render_contract", {"kind": "mall_ground", "modules": ml, "escalators": esc, "atrium": ATRIUM,
		"hall": HALL, "parking": PARKING, "trees": TREES, "street_cars": cars})
