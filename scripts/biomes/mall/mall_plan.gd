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
	# (Refonte maquette, retour utilisateur) Boutiques de tailles très variées, blocs irréguliers
	# qui avancent dans la galerie, passages de service et renfoncements entre les blocs, contour
	# extérieur en escalier (non rectangulaire). Ordre : éléments centraux fixes (atrium,
	# escalators et leurs blocs), puis rangée nord, ailes, coins et rangée sud, chaque boutique
	# raccourcie jusqu'à laisser au moins GAP cases de galerie devant elle.
	var core: Array[Rect2i] = [ATRIUM]
	for e0: Rect2i in ESC_N + ESC_S:
		core.append(e0)
	var passages: Array[Rect2i] = []

	# 1. Blocs centraux : boutiques adossées aux escalators.
	var en0: Rect2i = ESC_N[0]
	var en1: Rect2i = ESC_N[1]
	for side in 2:
		var w := rng.randi_range(7, 11)
		var h := rng.randi_range(8, 13)
		var y := rng.randi_range(19, 23)
		var r := Rect2i(en0.position.x - w + 1, y, w, h) if side == 0 else Rect2i(en1.end.x - 1, y, w, h)
		var m := _shop(r, rng, used)
		m.slot = "island"
		m.facade = Vector2i.LEFT if side == 0 else Vector2i.RIGHT
		mods.append(m)
		core.append(r)
	for side2 in 2:
		var es: Rect2i = ESC_S[side2]
		var y2 := rng.randi_range(70, 76)
		var yb := es.end.y - 1
		# un ou deux commerces empilés le long de l'escalator
		var w2 := rng.randi_range(7, 10)
		var cut := y2 + rng.randi_range(6, 9) if yb - y2 >= 14 and rng.randf() < 0.6 else yb
		for part in ([Vector2i(y2, cut), Vector2i(cut, yb)] if cut < yb else [Vector2i(y2, yb)]):
			var r2 := Rect2i(es.position.x - w2 + 1, part.x, w2, part.y - part.x + 1) if side2 == 0 \
				else Rect2i(es.end.x - 1, part.x, w2, part.y - part.x + 1)
			if r2.size.y < 7:
				continue
			var m2 := _shop(r2, rng, used)
			m2.slot = "island"
			m2.facade = Vector2i.LEFT if side2 == 0 else Vector2i.RIGHT
			mods.append(m2)
			core.append(r2)

	# 2. Rangée nord : cinéma en saillie (plus haut), boutiques de largeurs variées, haut et bas
	# en escalier ; passages de service occasionnels vers le mur nord.
	var cw := rng.randi_range(14, 18)
	var cine := Rect2i(33 - cw / 2, 1, cw, rng.randi_range(12, 15))
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
	# 3. Ailes ouest / est (générées séparément : plan asymétrique comme la maquette).
	for side3 in 2:
		_belt(L, mods, used, rng, side3, core, passages)
	for seg: Array in [[0, cine.position.x], [1, cine.end.x - 1]]:
		_north_row(mods, used, rng, int(seg[0]), int(seg[1]), core, passages)
	# 4. Coins sud (réserves) et rangée sud de part et d'autre du hall.
	for side4 in 2:
		_south_row(mods, used, rng, side4, core)
	# Grandes enseignes : supérette = la plus grande du nord ; arcade = la plus grande des ailes ;
	# café (food court) = la plus grande du sud.
	var big: Mod = _largest(mods, "row_n")
	if big != null:
		big.role = &"supermarket"
		big.arch = &"supermarket"
		big.type = FloorLayout.ROOM_LOOT
		big.name = "Supérette Primeur"
	var cafe: Mod = _largest(mods, "row_s")
	if cafe != null:
		cafe.role = &"shop_cafe"
		cafe.arch = &"cafe"
		cafe.type = FloorLayout.ROOM_REST
		cafe.name = "Food court des Arcades"
	var belts: Array[Mod] = []
	for m6 in mods:
		if m6.slot.begins_with("belt_"):
			belts.append(m6)
	var arc: Mod = _largest(mods, "belt_")
	arc.role = &"arcade"
	arc.arch = &"arcade"
	arc.type = FloorLayout.ROOM_COMBAT
	arc.name = EXTRA_NAMES[&"arcade"]
	arc.roof = false
	# Bijouterie scellée : une boutique d'aile (porte unique verrouillée sur la galerie).
	var jcands: Array[Mod] = []
	for b2 in belts:
		if b2 != arc and b2.rect.position.y > GAL.position.y + 1 and b2.inner.size.x >= 5 and b2.inner.size.y >= 5:
			jcands.append(b2)
	if jcands.is_empty():
		return null
	var jw: Mod = jcands[rng.randi_range(0, jcands.size() - 1)]
	jw.role = &"shop_jewelry"
	jw.arch = &"jewelry"
	jw.type = FloorLayout.ROOM_SUPER_LOOT
	jw.key = Layout.KEY_JEWELRY
	jw.name = "Bijouterie Éclat d'Or"
	jw.roof = true

	# 5. Sols : galerie (cases de l'enveloppe hors boutiques), passages, hall, parking.
	var gal := Rect2i(1, 1, W - 2, GAL.end.y - 1)
	_fill_gallery(L, mods, passages)
	L.fill_rect(Rect2i(HALL.position.x + 1, HALL.position.y, HALL.size.x - 2, HALL.size.y - 1), T.STREET)
	L.fill_rect(PARKING, T.STREET)
	L.fill_rect(Rect2i(28, HALL.end.y - 1, 10, 1), T.STREET)
	# 6. Creusement des boutiques.
	for m7 in mods:
		L.fill_rect(m7.rect, T.WALL)
	for m8 in mods:
		L.fill_rect(m8.inner, T.FLOOR)
	# Obstacles de la galerie : jardinières de l'atrium (4 ouvertures), escalators.
	var a := ATRIUM
	for x in range(a.position.x, a.end.x):
		for y3 in [a.position.y, a.end.y - 1]:
			if absi(x * 2 + 1 - (a.position.x + a.end.x)) > 4:
				L.set_tile(Vector2i(x, y3), T.WALL)
	for y4 in range(a.position.y, a.end.y):
		for x2 in [a.position.x, a.end.x - 1]:
			if absi(y4 * 2 + 1 - (a.position.y + a.end.y)) > 4:
				L.set_tile(Vector2i(x2, y4), T.WALL)
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


## Largeur minimale de galerie laissée devant une boutique (cases).
const GAP := 3
## Bas de la ceinture (rangée sud) : dernière rangée de mur des boutiques sud.
const SOUTH_Y := 105


## Rectangle libre : pas de chevauchement (hors murs partagés) avec les boutiques, le hall et
## les passages ; au moins GAP cases avec les éléments centraux.
static func _fits(r: Rect2i, mods: Array[Mod], core: Array[Rect2i], passages: Array[Rect2i]) -> bool:
	if r.position.x < 1 or r.position.y < 1 or r.end.x > W - 1 or r.end.y > SOUTH_Y + 1:
		return false
	if r.size.x < 7 or r.size.y < 7:
		return false
	for m in mods:
		if r.grow(-1).intersects(m.rect) or m.inner.intersects(r):
			return false
	if r.grow(-1).intersects(HALL) or HALL.grow(-1).intersects(r):
		return false
	for c in core:
		if r.grow(GAP).intersects(c):
			return false
	for p in passages:
		if r.intersects(p):
			return false
	return true


static func _mir(r: Rect2i, side: int) -> Rect2i:
	return mirror_rect(r) if side == 1 else r


## Taille tirée par classe : petite boutique / kiosque, moyenne, grande enseigne.
static func _size_class(rng: RandomNumberGenerator, small: Vector2i, medium: Vector2i, large: Vector2i) -> int:
	var roll := rng.randf()
	if roll < 0.3:
		return rng.randi_range(small.x, small.y)
	if roll < 0.78:
		return rng.randi_range(medium.x, medium.y)
	return rng.randi_range(large.x, large.y)


## Aile ouest (side 0) ou est (side 1, en miroir) : boutiques empilées de hauteurs et de
## profondeurs variées (le mur extérieur et la façade sur la galerie avancent ou reculent),
## passages de service vers le mur extérieur. Renvoie la rangée du dernier mur.
static func _belt(L: FloorLayout, mods: Array[Mod], used: Dictionary, rng: RandomNumberGenerator, side: int,
		core: Array[Rect2i], passages: Array[Rect2i]) -> int:
	var y := 2
	var y_end := rng.randi_range(84, 89)
	var first := true
	var last_pass := true
	while y < y_end:
		if not first and not last_pass and rng.randf() < 0.14 and y < y_end - 8:
			passages.append(_mir(Rect2i(2, y + 1, 26, 3), side))
			y += 4
			last_pass = true
			continue
		var h: int
		var depth: int
		var x0: int
		if first:
			h = rng.randi_range(8, 10)
			depth = rng.randi_range(12, 14)
			x0 = 1
		else:
			h = _size_class(rng, Vector2i(7, 7), Vector2i(8, 11), Vector2i(13, 17))
			depth = clampi(h + rng.randi_range(-1, 4), 8, 19)
			x0 = rng.randi_range(1, 3) if h >= 13 else rng.randi_range(1, 6)
		if y + h - 1 > y_end + 3:
			h = maxi(7, y_end + 3 - y + 1)
		var r := Rect2i(x0, y, depth, h)
		while depth > 7 and not _fits(_mir(r, side), mods, core, passages):
			depth -= 1
			r = Rect2i(x0, y, depth, h)
		if not _fits(_mir(r, side), mods, core, passages):
			passages.append(_mir(Rect2i(2, y + 1, 26, 3), side))
			y += 4
			last_pass = true
			continue
		var m := _shop(_mir(r, side), rng, used)
		m.slot = ("belt_w" if side == 0 else "belt_e")
		m.facade = Vector2i.RIGHT if side == 0 else Vector2i.LEFT
		if first:
			m.role = &"service"
			m.arch = &"dock"
			m.type = FloorLayout.ROOM_EXTRACTION
			m.name = "%s %s" % [EXTRA_NAMES[&"dock"], "ouest" if side == 0 else "est"]
			m.slot = "dock_" + ("w" if side == 0 else "e")
		else:
			m.roof = rng.randf() < 0.06
		mods.append(m)
		y += h - 1
		first = false
		last_pass = false
	L.set_meta(&"_belt_end_%d" % side, y)
	return y


## Rangée nord (d'un côté du cinéma) : largeurs, hauts et bas variés ; passages vers le nord.
static func _north_row(mods: Array[Mod], used: Dictionary, rng: RandomNumberGenerator, side: int, xlim_real: int,
		core: Array[Rect2i], passages: Array[Rect2i]) -> void:
	# en coordonnées « ouest » : le mur du cinéma est en xlim
	var xlim := xlim_real if side == 0 else W - 1 - xlim_real
	var x := 1
	var guard := 0
	while x < xlim - 6 and guard < 80:
		guard += 1
		var y0 := rng.randi_range(1, 5)
		var y1 := rng.randi_range(11, 16)
		var w := _size_class(rng, Vector2i(7, 7), Vector2i(8, 11), Vector2i(13, 17))
		if xlim - (x + w - 1) < 7:
			w = xlim - x + 1
		var r := Rect2i(x, y0, w, y1 - y0 + 1)
		if not _fits(_mir(r, side), mods, core, passages):
			# collé au quai / à l'aile : on décale (le creux devient un renfoncement muré)
			var r2 := Rect2i(x, y0, mini(w, 9), y1 - y0 + 1)
			if not _fits(_mir(r2, side), mods, core, passages):
				x += 1
				continue
			r = r2
		var m := _shop(_mir(r, side), rng, used)
		m.slot = "row_n"
		m.facade = Vector2i.DOWN
		m.roof = rng.randf() < 0.1
		mods.append(m)
		x = r.end.x - 1
		if xlim - x > 12 and rng.randf() < 0.18:
			passages.append(_mir(Rect2i(x + 1, 2, 3, 18), side))
			x += 4


## Coin sud (réserve) puis boutiques de la rangée sud jusqu'au hall, hauts en escalier.
static func _south_row(mods: Array[Mod], used: Dictionary, rng: RandomNumberGenerator, side: int,
		core: Array[Rect2i]) -> void:
	var none: Array[Rect2i] = []
	var yb := 0
	for m0 in mods:
		if m0.slot == ("belt_w" if side == 0 else "belt_e") or m0.slot == "dock_" + ("w" if side == 0 else "e"):
			yb = maxi(yb, m0.rect.end.y - 1)
	var x0 := rng.randi_range(1, 3)
	var d := rng.randi_range(10, 14)
	var cr := Rect2i(x0, yb, d, SOUTH_Y - yb + 1)
	while d > 7 and not _fits(_mir(cr, side), mods, core, none):
		d -= 1
		cr = Rect2i(x0, yb, d, SOUTH_Y - yb + 1)
	var x := 1
	if _fits(_mir(cr, side), mods, core, none):
		var m4 := _shop(_mir(cr, side), rng, used)
		m4.role = &"stockroom"
		m4.arch = &"service"
		m4.type = FloorLayout.ROOM_LOOT
		m4.name = "Réserve " + ("ouest" if side == 0 else "est")
		m4.slot = "corner_s"
		mods.append(m4)
		x = cr.end.x - 1
	var xlim := HALL.position.x
	var guard := 0
	while x < xlim - 6 and guard < 80:
		guard += 1
		var w := _size_class(rng, Vector2i(7, 7), Vector2i(8, 10), Vector2i(12, 16))
		if xlim - (x + w - 1) < 7:
			w = xlim - x + 1
		var placed := false
		for y0 in [rng.randi_range(89, 95), 93, 96, 98]:
			var r := Rect2i(x, y0, w, SOUTH_Y - y0 + 1)
			if _fits(_mir(r, side), mods, core, none):
				var m3 := _shop(_mir(r, side), rng, used)
				m3.slot = "row_s"
				m3.facade = Vector2i.UP
				mods.append(m3)
				x = r.end.x - 1
				placed = true
				break
		if not placed:
			x += 1


static func _largest(mods: Array[Mod], prefix: String) -> Mod:
	var best: Mod = null
	for m in mods:
		if not m.slot.begins_with(prefix) or m.role == &"service" or m.role == &"stockroom":
			continue
		if best == null or m.inner.get_area() > best.inner.get_area():
			best = m
	return best


## Galerie : cases de l'enveloppe du bâtiment hors boutiques. Une case est dans l'enveloppe si
## une boutique la borde à l'ouest, à l'est ET au nord (sinon c'est un creux extérieur du contour
## en escalier, laissé vide), ou si elle appartient à un passage de service.
static func _fill_gallery(L: FloorLayout, mods: Array[Mod], passages: Array[Rect2i]) -> void:
	var inmod := PackedByteArray()
	inmod.resize(W * H)
	var wmin := PackedInt32Array()
	var emax := PackedInt32Array()
	var nmin := PackedInt32Array()
	wmin.resize(H)
	emax.resize(H)
	nmin.resize(W)
	wmin.fill(1 << 20)
	emax.fill(-1)
	nmin.fill(1 << 20)
	for m in mods:
		var r := m.rect
		for y in range(r.position.y, r.end.y):
			wmin[y] = mini(wmin[y], r.position.x)
			emax[y] = maxi(emax[y], r.end.x - 1)
			for x in range(r.position.x, r.end.x):
				inmod[y * W + x] = 1
		for x2 in range(r.position.x, r.end.x):
			nmin[x2] = mini(nmin[x2], r.position.y)
	# les passages de service bordent aussi la galerie (sinon la rangée face à un passage
	# serait prise pour un creux extérieur)
	for p0 in passages:
		for y5 in range(p0.position.y, p0.end.y):
			wmin[y5] = mini(wmin[y5], p0.position.x - 1)
			emax[y5] = maxi(emax[y5], p0.end.x)
		for x5 in range(p0.position.x, p0.end.x):
			nmin[x5] = mini(nmin[x5], p0.position.y - 1)
	for y2 in range(2, GAL.end.y):
		for x3 in range(2, W - 2):
			if inmod[y2 * W + x3] == 1:
				continue
			var c := Vector2i(x3, y2)
			var ok := x3 > wmin[y2] and x3 < emax[y2] and y2 > nmin[x3]
			if not ok:
				for p in passages:
					if p.has_point(c):
						ok = true
						break
			if ok:
				L.set_tile(c, T.STREET)


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
	var keys := _sorted_keys(groups)
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
			var g := _pick(groups, keys, m3, connected, by_unit, door_cells, stairs, false)
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
		var g2 := _pick(groups, keys, m4, connected, by_unit, door_cells, stairs, false)
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


## Clés de `groups` dans l'ordre de parcours de _pick (triées une seule fois par _connect :
## `groups` ne change plus une fois les candidats recensés).
static func _sorted_keys(groups: Dictionary) -> Array:
	var keys: Array = groups.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
	return keys


static func _pick(groups: Dictionary, keys: Array, mu: Mod, connected: Dictionary, by_unit: Dictionary, door_cells: Dictionary, stairs: Dictionary, extra: bool) -> Dictionary:
	var u := mu.unit
	var best := {}
	var best_score := -1.0
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
	var reach := _flood(L, true)
	var tiles := L.tiles
	for j in W * H:
		if reach[j] == 0 and FloorLayout.is_walkable_tile(tiles[j]):
			return false
	var open_reach := _flood(L, false)
	for m in mods:
		if m.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		for y2 in range(m.inner.position.y, m.inner.end.y):
			for x2 in range(m.inner.position.x, m.inner.end.x):
				if open_reach[y2 * W + x2] == 1:
					return false
	return L.extraction_cells.size() >= 2


## Cases atteintes depuis l'apparition (1 = atteinte), même règle que FloorLayout.flood_reachable
## (4-voisinage, cases marchables ; sans `through_locked`, une porte verrouillée arrête la
## propagation) mais sur une grille d'octets : _validate est appelé à chaque génération du
## rez-de-chaussée et le parcours par dictionnaire en était l'étape la plus lente.
static func _flood(L: FloorLayout, through_locked: bool) -> PackedByteArray:
	var tiles := L.tiles
	var stop := PackedByteArray()
	stop.resize(W * H)
	for j in W * H:
		if not FloorLayout.is_walkable_tile(tiles[j]):
			stop[j] = 1
	if not through_locked:
		# Comme get_door_at : la première porte enregistrée sur la case fait foi.
		var first := {}
		for d in L.doors:
			if not first.has(d.cell):
				first[d.cell] = d
		for cell: Vector2i in first:
			if L.in_bounds(cell) and tiles[cell.y * W + cell.x] == T.DOOR and (first[cell] as FloorLayout.Door).state == DS.LOCKED:
				stop[cell.y * W + cell.x] = 1
	var seen := PackedByteArray()
	seen.resize(W * H)
	var s := L.player_spawn
	var start := s.y * W + s.x
	seen[start] = 1
	var stack := PackedInt32Array([start])
	while not stack.is_empty():
		var c := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var cx := c % W
		for n: int in [c - 1 if cx > 0 else -1, c + 1 if cx < W - 1 else -1, c - W, c + W]:
			if n < 0 or n >= W * H or seen[n] == 1 or stop[n] == 1:
				continue
			seen[n] = 1
			stack.append(n)
	return seen


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
