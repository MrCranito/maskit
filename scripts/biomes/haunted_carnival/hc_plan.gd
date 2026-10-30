extends RefCounted
## Rez-de-chaussée (0) du Carnaval hanté façon maquette (docs/reference/cartes_2.png, colonne de
## gauche) : parc d'attractions maudit vu de dessus, DE NUIT, format portrait.
##   - GRANDE ROUE au nord-ouest (disque de cases murées : obstacle rendu en 3D) ;
##   - CHAPITEAU central ovale (piste de cirque = salle du BOSS, toit qui s'efface) sur une
##     grande place, trois entrées (sud, ouest, est) ;
##   - MANÈGES (chaises volantes au nord-est, tasses au sud-ouest, carrousel au sud-est) :
##     disques murés dans des zones ouvertes ;
##   - STANDS / baraques de foire en rangées le long de l'allée centrale (tir, confiseries,
##     pêche aux canards…), à auvent rayé (toit) ou ouverts (vus en coupe) ;
##   - ROULOTTES / caravanes (petites salles fermées) sur les côtés, dont la roulotte du
##     Directeur scellée (super_loot, clef key_hc_director) ;
##   - TENTES rouges et blanches (palais des glaces, tente des monstres) ;
##   - ENTRÉE monumentale au sud (portail à la tête de clown) sur le parvis où arrive le joueur,
##     billetteries de part et d'autre ;
##   - MONTAGNES RUSSES : rails rouges qui encadrent le parc (hors jeu, dans la marge rendue) et
##     une section de pylônes qui traverse la zone nord-est (obstacle / couloir) ;
##   - sorties de secours (extraction) aux deux coins nord, sous les rails.
## Allées en terre et pavés (STREET), intérieurs (FLOOR). Portes dans un mur droit, jamais dans
## le mur NORD d'un bâtiment à toit (le toit rendu incliné la cacherait).
## Variations par seed : découpe des stands, rôles et noms, stands couverts ou non, position des
## roulottes, rôle des tentes, tirage de la roulotte du Directeur.
## Contrat de rendu (tools/prerender/hc_scene.py) en métadonnée « render_contract ».
## Ne pose aucun spawn (voir hc_populator.gd). Déterministe.

const Cfg := preload("res://scripts/biomes/haunted_carnival/hc_config.gd")
const T := FloorLayout.Tile
const DS := FloorLayout.DoorState

const KEY_DIRECTOR := &"key_hc_director"

const W := 72
const H := 126
## Parvis de l'entrée (apparition) et portail à la tête de clown (deux rangées de mur).
const LOT := Rect2i(22, 111, 28, 14)
const GATE := Rect2i(16, 109, 40, 2)
const GATE_OPEN := Rect2i(33, 109, 6, 2)
## Grande place ovale pavée (centre, rayons) et sa boîte (compatibilité du contrat de rendu).
const PLAZA_C := Vector2(36.5, 47.0)
const PLAZA_R := Vector2(25.0, 19.5)
const PLAZA := Rect2i(11, 27, 52, 40)
## Chapiteau monumental (ovale, boîte englobante) : centre, rayons.
const TENT_RECT := Rect2i(19, 34, 35, 26)
const TENT_C := Vector2(36.5, 46.5)
const TENT_R := Vector2(17.0, 12.5)
## Anneau de gradins (cases murées) : tent_d dans ]RING, 1].
const RING := 0.74
## Quartiers (cours ovales) : [centre, rayons, rôle, nom, type de salle].
const YARDS := [
	[Vector2(15.5, 16.0), Vector2(12.5, 10.5), &"wheel_yard", "Esplanade de la Grande Roue", &"combat"],
	[Vector2(57.0, 16.0), Vector2(12.5, 10.5), &"ride_yard", "Cour des Chaises volantes", &"trap"],
	[Vector2(16.0, 86.0), Vector2(11.5, 10.0), &"ride_yard", "Cour des Tasses", &"combat"],
	[Vector2(56.0, 86.0), Vector2(11.5, 10.0), &"ride_yard", "Cour du Carrousel", &"loot"],
]
## Allées sinueuses : [points (cases), largeur, rôle, nom].
const PATHS := [
	[[Vector2(36.5, 64.0), Vector2(34.0, 73.0), Vector2(38.5, 82.0), Vector2(35.0, 91.0), Vector2(37.5, 100.0), Vector2(36.0, 110.0)], 5.0, &"avenue", "Allée des Lumières"],
	[[Vector2(36.5, 29.0), Vector2(35.0, 20.0), Vector2(38.0, 13.0), Vector2(36.0, 7.0)], 4.0, &"alley", "Allée du Belvédère"],
	[[Vector2(25.0, 9.0), Vector2(31.0, 6.5), Vector2(36.0, 6.0), Vector2(41.0, 6.5), Vector2(47.0, 9.0)], 3.0, &"alley", "Allée des Guirlandes"],
	[[Vector2(20.0, 32.0), Vector2(18.0, 25.0)], 4.0, &"alley", "Passage de la Grande Roue"],
	[[Vector2(53.0, 32.0), Vector2(55.0, 25.0)], 4.0, &"alley", "Passage des Chaises"],
	[[Vector2(13.0, 52.0), Vector2(6.5, 59.0), Vector2(7.0, 67.0), Vector2(12.0, 76.0)], 3.0, &"alley", "Chemin des Roulottes ouest"],
	[[Vector2(60.0, 52.0), Vector2(66.5, 59.0), Vector2(66.0, 67.0), Vector2(61.0, 76.0)], 3.0, &"alley", "Chemin des Roulottes est"],
	[[Vector2(26.0, 89.0), Vector2(31.0, 91.0), Vector2(35.0, 91.0)], 3.0, &"alley", "Ruelle des Tasses"],
	[[Vector2(46.0, 89.0), Vector2(41.0, 91.0), Vector2(37.0, 91.0)], 3.0, &"alley", "Ruelle du Carrousel"],
	[[Vector2(27.0, 62.0), Vector2(22.0, 70.0), Vector2(18.0, 76.0)], 3.0, &"alley", "Ruelle des Lampions"],
	[[Vector2(46.0, 62.0), Vector2(51.0, 70.0), Vector2(54.0, 76.0)], 3.0, &"alley", "Ruelle des Fanions"],
]
## Grande roue et manèges : [centre, rayon, kind].
const WHEEL := {"c": Vector2(15.5, 15.5), "r": 6.2, "kind": "ferris_wheel"}
const RIDES := [
	{"c": Vector2(57.5, 15.5), "r": 4.0, "kind": "swing_ride"},
	{"c": Vector2(16.5, 86.5), "r": 4.0, "kind": "teacups"},
	{"c": Vector2(55.5, 86.5), "r": 4.6, "kind": "carousel"},
]
const HALLS := [
	[&"hangar", &"hall_hangar", "Hangar des manèges", "Remise des wagonnets"],
	[&"workshop", &"hall_workshop", "Atelier des forains", "Forge du mécanicien"],
	[&"museum", &"hall_museum", "Musée des horreurs", "Cabinet de cire"],
	[&"arcade", &"hall_arcade", "Galerie des jeux", "Salle des flippers"],
]
## Kiosques (billetteries) du parvis.
const KIOSKS := [Rect2i(23, 112, 6, 6), Rect2i(43, 112, 6, 6)]
## Sorties de secours (extraction) au bout des chemins des roulottes : [rect, façade].
const EXITS := [[Rect2i(0, 60, 5, 7), Vector2i.RIGHT], [Rect2i(67, 60, 5, 7), Vector2i.LEFT]]
## Pylônes des montagnes russes traversant la cour nord-est (cases murées, polyligne).
const COASTER_IN := [Vector2i(47, 9), Vector2i(48, 13), Vector2i(49, 17), Vector2i(48, 21), Vector2i(47, 25)]

## Stands possibles : [archétype, rôle, noms…].
const STANDS := [
	[&"shooting", &"stand_shooting", "Tir à la carabine", "Stand de tir Bang-Bang"],
	[&"candy", &"stand_candy", "Confiseries Sucre d'Orge", "Barbe à papa Rosalie"],
	[&"ducks", &"stand_ducks", "Pêche aux canards", "Mare aux canards"],
	[&"prizes", &"stand_prizes", "Stand des lots", "Peluches géantes"],
	[&"fortune", &"stand_fortune", "Madame Zoltara", "Cabinet de voyance"],
	[&"popcorn", &"stand_popcorn", "Pop-corn du Roi", "Maïs soufflé Jojo"],
	[&"hammer", &"stand_hammer", "Tape-fort", "Marteau du Colosse"],
	[&"souvenirs", &"stand_souvenirs", "Souvenirs du Carnaval", "Masques & Grimaces"],
]


class Mod:
	var rect: Rect2i
	var inner: Rect2i
	var role: StringName = &"stand_candy"
	var arch: StringName = &"candy"
	var type: StringName = FloorLayout.ROOM_COMBAT
	var name: String = ""
	var slot: String = ""
	var roof: bool = false
	var key: StringName = &""
	var facade: Vector2i = Vector2i.ZERO
	var room: FloorLayout.Room = null
	var building: FloorLayout.Building = null
	var unit: int = -1
	var ellipse: bool = false   ## chapiteau : emprise ovale


class Result:
	var layout: FloorLayout
	var mods: Array[Mod] = []


static func build(seed_value: int) -> Result:
	for attempt in 10:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "hc_plan", attempt])
		var r := _try(rng)
		if r != null:
			return r
	push_error("HauntedCarnival: rez-de-chaussée impossible à générer (seed %d)" % seed_value)
	return null


## Cases du disque (centre, rayon) : obstacles des manèges.
static func disc_cells(c: Vector2, r: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(int(floor(c.y - r)) - 1, int(ceil(c.y + r)) + 1):
		for x in range(int(floor(c.x - r)) - 1, int(ceil(c.x + r)) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				out.append(Vector2i(x, y))
	return out


## Paramètre ovale d'une case (0 au centre, 1 sur le bord du chapiteau).
static func tent_d(x: int, y: int) -> float:
	var dx := (x + 0.5 - TENT_C.x) / TENT_R.x
	var dy := (y + 0.5 - TENT_C.y) / TENT_R.y
	return dx * dx + dy * dy


static func _try(rng: RandomNumberGenerator) -> Result:
	var L := FloorLayout.new(Vector2i(W, H))
	L.floor_index = 0
	var res := Result.new()
	res.layout = L
	var mods: Array[Mod] = []
	var used := {}
	# 1. Sols ouverts : place ovale, quartiers, allées sinueuses, parvis. `zone` : index de zone
	#    extérieure par case (première zone qui la creuse).
	var zone := PackedInt32Array()
	zone.resize(W * H)
	zone.fill(-1)
	var zones: Array = []   # [rôle, nom, type, cases (Array[Vector2i])]
	zones.append([&"plaza", "Place du Chapiteau", FloorLayout.ROOM_COMBAT, _carve_ellipse(L, zone, 0, PLAZA_C, PLAZA_R)])
	for y0: Array in YARDS:
		zones.append([y0[2], y0[3], y0[4], _carve_ellipse(L, zone, zones.size(), y0[0], y0[1])])
	for p0: Array in PATHS:
		zones.append([p0[2], p0[3], FloorLayout.ROOM_CORRIDOR, _carve_path(L, zone, zones.size(), p0[0], float(p0[1]))])
	var lot_cells: Array[Vector2i] = []
	_fill(L, LOT, T.STREET)
	for ly in range(LOT.position.y, LOT.end.y):
		for lx in range(LOT.position.x, LOT.end.x):
			var li := ly * W + lx
			if zone[li] < 0:
				zone[li] = zones.size()
			lot_cells.append(Vector2i(lx, ly))
	zones.append([&"entrance", "Parvis du Clown", FloorLayout.ROOM_SPAWN, lot_cells])
	_fill(L, GATE, T.WALL)
	_fill(L, GATE_OPEN, T.STREET)
	for gy in range(GATE_OPEN.position.y, GATE_OPEN.end.y):
		for gx in range(GATE_OPEN.position.x, GATE_OPEN.end.x):
			zone[gy * W + gx] = zones.size() - 1
	# Obstacles : grande roue, manèges, pylônes, chapiteau (réservés avant les bâtiments).
	var taken := PackedByteArray()
	taken.resize(W * H)
	var t0 := L.tiles
	for i0 in W * H:
		if t0[i0] != T.VOID:
			taken[i0] = 1
	for kr: Rect2i in KIOSKS:
		_mark(taken, kr)
	for e0: Array in EXITS:
		_mark(taken, e0[0])
	_mark(taken, GATE.grow(1))

	# 2. Modules fixes : chapiteau, sorties, kiosques.
	var mb := Mod.new()
	mb.rect = TENT_RECT
	mb.inner = TENT_RECT   # salle = boîte englobante ; cases hors ovale : place (étiquettes par case)
	mb.roof = true
	mb.ellipse = true
	mb.slot = "big_top"
	mb.arch = &"big_top"
	mb.role = &"big_top"
	mb.type = FloorLayout.ROOM_BOSS
	mb.name = "Piste du Grand Chapiteau"
	mb.facade = Vector2i.DOWN
	mods.append(mb)
	for i3 in EXITS.size():
		var me := Mod.new()
		me.rect = EXITS[i3][0]
		me.inner = me.rect.grow(-1)
		me.slot = "exit"
		me.arch = &"service_yard"
		me.role = &"service_yard"
		me.type = FloorLayout.ROOM_EXTRACTION
		me.name = "Sortie de secours %s" % ("ouest" if i3 == 0 else "est")
		me.facade = EXITS[i3][1]
		mods.append(me)
	for i2 in KIOSKS.size():
		var mk := Mod.new()
		mk.rect = KIOSKS[i2]
		mk.inner = mk.rect.grow(-1)
		mk.roof = true
		mk.slot = "kiosk"
		mk.arch = &"ticket_booth"
		mk.role = &"ticket_booth"
		mk.type = FloorLayout.ROOM_LOOT
		mk.name = ["Billetterie ouest", "Billetterie est"][i2]
		mk.facade = Vector2i.RIGHT if i2 == 0 else Vector2i.LEFT
		mods.append(mk)

	# 3. Bâtiments serrés le long des allées (placeur glouton sur les bords de rue) : tentes,
	#    halls en dur autour de la place, roulottes en périphérie, stands partout ailleurs.
	var edges := _street_edges(L, rng)
	var tents := _place(L, taken, zone, edges, rng, [Vector2i(11, 10), Vector2i(10, 11)], 2, "tent")
	var halls := _place(L, taken, zone, edges, rng, [Vector2i(10, 9), Vector2i(9, 10), Vector2i(11, 8), Vector2i(9, 8), Vector2i(8, 9)], Cfg.geti("hc_halls", 8), "hall")
	var cars := _place(L, taken, zone, edges, rng, [Vector2i(7, 5), Vector2i(5, 7), Vector2i(6, 5)], Cfg.geti("hc_caravans", 4), "caravan")
	var stands := _place(L, taken, zone, edges, rng, [Vector2i(7, 6), Vector2i(6, 7), Vector2i(8, 6), Vector2i(6, 6), Vector2i(6, 5), Vector2i(5, 6)], Cfg.geti("hc_stands_max", 40), "stand")
	if tents.size() < 2 or cars.size() < Cfg.geti("hc_caravans", 4) or stands.size() < 12:
		return null
	var tent_roles: Array = [[&"mirrors", &"tent_mirrors", "Palais des glaces", FloorLayout.ROOM_TRAP],
		[&"freaks", &"tent_freaks", "Tente des monstres", FloorLayout.ROOM_COMBAT],
		[&"theatre", &"tent_theatre", "Théâtre des marionnettes", FloorLayout.ROOM_LOOT]]
	for i in tents.size():
		var def: Array = tent_roles[(i + rng.randi_range(0, 2)) % tent_roles.size()]
		tent_roles.erase(def)
		var mt := _mod_of(tents[i])
		mt.arch = def[0]
		mt.role = def[1]
		mt.name = def[2]
		mt.type = def[3]
		mt.roof = true
		mt.slot = "tent"
		mods.append(mt)
	var hi := 0
	for h0: Array in halls:
		var mh := _mod_of(h0)
		var hdef: Array = HALLS[(hi + rng.randi_range(0, 1)) % HALLS.size()]
		mh.arch = hdef[0]
		mh.role = hdef[1]
		mh.name = hdef[2 + (hi % 2)]
		mh.type = [FloorLayout.ROOM_COMBAT, FloorLayout.ROOM_LOOT, FloorLayout.ROOM_TRAP, FloorLayout.ROOM_COMBAT][hi % 4]
		mh.slot = "hall"
		mh.roof = mh.facade != Vector2i.UP and rng.randf() < Cfg.getf("hc_hall_roof_chance", 0.5)
		mods.append(mh)
		hi += 1
	var director := rng.randi_range(0, cars.size() - 1)
	for k in cars.size():
		var mc := _mod_of(cars[k])
		mc.roof = true
		mc.slot = "caravan"
		if k == director:
			mc.arch = &"director_caravan"
			mc.role = &"caravan_director"
			mc.type = FloorLayout.ROOM_SUPER_LOOT
			mc.key = KEY_DIRECTOR
			mc.name = "Roulotte du Directeur"
		else:
			var cdef: Array = [[&"caravan", &"caravan_home", "Roulotte des forains", FloorLayout.ROOM_LOOT],
				[&"caravan", &"caravan_home", "Caravane de la dompteuse", FloorLayout.ROOM_REST],
				[&"caravan", &"caravan_storage", "Roulotte-réserve", FloorLayout.ROOM_LOOT],
				[&"caravan", &"caravan_home", "Roulotte des jumeaux", FloorLayout.ROOM_COMBAT]][k % 4]
			mc.arch = cdef[0]
			mc.role = cdef[1]
			mc.name = cdef[2]
			mc.type = cdef[3]
		mods.append(mc)
	for s0: Array in stands:
		var r0: Rect2i = s0[0]
		var ms := _stand(r0, rng, used)
		ms.facade = s0[1]
		ms.slot = "stand"
		ms.roof = ms.facade != Vector2i.UP and rng.randf() < Cfg.getf("hc_stand_roof_chance", 0.5)
		mods.append(ms)

	# 4. Creusement.
	for m7 in mods:
		if m7.ellipse:
			continue
		_fill(L, m7.rect, T.WALL)
	for m8 in mods:
		if m8.ellipse:
			continue
		_fill(L, m8.inner, T.FLOOR)
	# Chapiteau ovale : anneau de gradins murés (tent_d dans ]RING, 1]), piste au centre, trois
	# passages radiaux creusés (sud, ouest, est) dont la case extérieure devient une porte.
	for y in range(TENT_RECT.position.y, TENT_RECT.end.y):
		for x in range(TENT_RECT.position.x, TENT_RECT.end.x):
			var d := tent_d(x, y)
			if d <= 1.0:
				L.set_tile(Vector2i(x, y), T.WALL if d > RING else T.FLOOR)
	for ang: float in [PI / 2.0, PI, 0.0]:
		var ox := cos(ang)
		var oy := sin(ang)
		var kk := 1.0
		var first := true
		while kk > sqrt(RING) - 0.02:
			var cx := int(floor(TENT_C.x + ox * TENT_R.x * kk))
			var cy := int(floor(TENT_C.y + oy * TENT_R.y * kk))
			if tent_d(cx, cy) <= 1.0 and not first:
				L.set_tile(Vector2i(cx, cy), T.FLOOR)
			first = false
			kk -= 0.04
	for c in disc_cells(WHEEL["c"], WHEEL["r"]):
		L.set_tile(c, T.WALL)
	for rd: Dictionary in RIDES:
		for c2 in disc_cells(rd["c"], rd["r"]):
			L.set_tile(c2, T.WALL)
	for c3 in _coaster_cells():
		if L.get_tile(c3) == T.STREET:
			L.set_tile(c3, T.WALL)
	L.player_spawn = Vector2i(36 + rng.randi_range(-2, 1), LOT.end.y - 3)
	_fence(L)

	# 5. Bâtiments (à toit) et salles ; étiquettes de salle par case (zones organiques).
	for m9 in mods:
		if m9.roof:
			m9.building = L.add_building(m9.arch, m9.name, m9.rect)
	var lab := PackedInt32Array()
	lab.resize(W * H)
	lab.fill(-1)
	for zi in zones.size():
		var zc: Array = zones[zi]
		var cells: Array = zc[3]
		if cells.is_empty():
			continue
		var bb := Rect2i(cells[0], Vector2i.ONE)
		for cz: Vector2i in cells:
			bb = bb.expand(cz)
		bb.size += Vector2i.ONE
		var zr := L.add_room(bb, true, zc[2], zc[1])
		zr.tags = PackedStringArray([String(zc[0]), "open"])
		for cz2: Vector2i in cells:
			lab[cz2.y * W + cz2.x] = zr.id
	for m10 in mods:
		var bid := m10.building.id if m10.building != null else -1
		m10.room = L.add_room(m10.inner, false, m10.type, m10.name, bid)
		m10.room.tags = PackedStringArray([String(m10.role), String(m10.arch)])
		if m10.roof:
			m10.room.tags.append("roofed")
		for yy in range(m10.rect.position.y, m10.rect.end.y):
			for xx in range(m10.rect.position.x, m10.rect.end.x):
				if not m10.ellipse or tent_d(xx, yy) <= 1.0:
					lab[yy * W + xx] = m10.room.id
	L.set_meta(&"cell_rooms", lab)

	# 6. Portes.
	if not _connect(L, mods, rng):
		return null

	# 7. Extraction (sorties de secours) ; apparition déjà fixée (parvis).
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


static func _mark(taken: PackedByteArray, r: Rect2i) -> void:
	for y in range(maxi(r.position.y, 0), mini(r.end.y, H)):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, W)):
			taken[y * W + x] = 1


## Ellipse creusée en STREET (cases libres seulement) ; renvoie ses cases et étiquette `zone`.
static func _carve_ellipse(L: FloorLayout, zone: PackedInt32Array, zi: int, c: Vector2, r: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var tiles := L.tiles
	for y in range(maxi(int(c.y - r.y) - 1, 1), mini(int(c.y + r.y) + 2, H - 1)):
		for x in range(maxi(int(c.x - r.x) - 1, 1), mini(int(c.x + r.x) + 2, W - 1)):
			var dx := (x + 0.5 - c.x) / r.x
			var dy := (y + 0.5 - c.y) / r.y
			if dx * dx + dy * dy > 1.0:
				continue
			var i := y * W + x
			tiles[i] = T.STREET
			if zone[i] < 0:
				zone[i] = zi
				out.append(Vector2i(x, y))
	L.tiles = tiles
	return out


## Allée sinueuse : disques de diamètre `w` estampés le long de la polyligne lissée.
static func _carve_path(L: FloorLayout, zone: PackedInt32Array, zi: int, pts: Array, w: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var tiles := L.tiles
	var r := w * 0.5
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(int(a.distance_to(b)), 1)
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			for y in range(maxi(int(p.y - r) - 1, 1), mini(int(p.y + r) + 2, H - 1)):
				for x in range(maxi(int(p.x - r) - 1, 1), mini(int(p.x + r) + 2, W - 1)):
					if Vector2(x + 0.5, y + 0.5).distance_to(p) > r:
						continue
					var j := y * W + x
					tiles[j] = T.STREET
					if zone[j] < 0:
						zone[j] = zi
						out.append(Vector2i(x, y))
	L.tiles = tiles
	return out


## Bords de rue : [case de rue, direction vers une case VOID] mélangés (ordre déterministe).
static func _street_edges(L: FloorLayout, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var tiles := L.tiles
	for y in range(2, H - 2):
		for x in range(2, W - 2):
			var i := y * W + x
			if tiles[i] != T.STREET:
				continue
			if tiles[i - W] == T.VOID:
				out.append([Vector2i(x, y), Vector2i.UP])
			if tiles[i + W] == T.VOID:
				out.append([Vector2i(x, y), Vector2i.DOWN])
			if tiles[i - 1] == T.VOID:
				out.append([Vector2i(x, y), Vector2i.LEFT])
			if tiles[i + 1] == T.VOID:
				out.append([Vector2i(x, y), Vector2i.RIGHT])
	for k in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, k)
		var tmp: Variant = out[k]
		out[k] = out[j]
		out[j] = tmp
	return out


## Place jusqu'à `count` rectangles (tailles essayées dans l'ordre) dans le vide (VOID non pris)
## collés à un bord de rue ; façade = côté de la rue. Filtres par `kind` : tentes dans les cours
## sud, halls au bord de la place, roulottes loin de la place. Renvoie [[rect, façade], …].
static func _place(L: FloorLayout, taken: PackedByteArray, zone: PackedInt32Array, edges: Array, rng: RandomNumberGenerator,
		sizes: Array, count: int, kind: String) -> Array:
	var out: Array = []
	for e: Array in edges:
		if out.size() >= count:
			break
		var s: Vector2i = e[0]
		var d: Vector2i = e[1]
		if taken[(s.y + d.y) * W + s.x + d.x] != 0:
			continue
		var zs := zone[s.y * W + s.x]
		match kind:
			"tent":
				if s.y < 70 or d == Vector2i.DOWN:
					continue
			"hall":
				if zs != 0:
					continue
			"caravan":
				if zs == 0 or d == Vector2i.DOWN or Vector2(s).distance_to(PLAZA_C) < 30.0:
					continue
		for sz: Vector2i in sizes:
			var r := _rect_at(s, d, sz, rng)
			if _free(taken, r):
				_mark(taken, r)
				out.append([r, -d])
				break
	return out


## Rectangle de taille `sz` dont le mur de façade touche la case de rue `s` (côté `d`).
static func _rect_at(s: Vector2i, d: Vector2i, sz: Vector2i, rng: RandomNumberGenerator) -> Rect2i:
	var o := rng.randi_range(1, maxi((sz.x if d.y != 0 else sz.y) - 2, 1))
	match d:
		Vector2i.UP:
			return Rect2i(s.x - o, s.y - sz.y, sz.x, sz.y)
		Vector2i.DOWN:
			return Rect2i(s.x - o, s.y + 1, sz.x, sz.y)
		Vector2i.LEFT:
			return Rect2i(s.x - sz.x, s.y - o, sz.x, sz.y)
	return Rect2i(s.x + 1, s.y - o, sz.x, sz.y)


static func _free(taken: PackedByteArray, r: Rect2i) -> bool:
	if r.position.x < 0 or r.position.y < 1 or r.end.x > W or r.end.y > H - 1:
		return false
	for y in range(r.position.y, r.end.y):
		var row := y * W
		for x in range(r.position.x, r.end.x):
			if taken[row + x] != 0:
				return false
	return true


static func _mod_of(e: Array) -> Mod:
	var m := Mod.new()
	m.rect = e[0]
	m.inner = m.rect.grow(-1)
	m.facade = e[1]
	return m


## Remplissage direct du tableau de tuiles (rectangle borné à la grille) : même résultat que
## FloorLayout.fill_rect, sans test de bornes par case.
static func _fill(L: FloorLayout, r: Rect2i, t: int) -> void:
	var tiles := L.tiles
	var x0 := maxi(r.position.x, 0)
	var x1 := mini(r.end.x, W)
	for y in range(maxi(r.position.y, 0), mini(r.end.y, H)):
		var row := y * W
		for x in range(x0, x1):
			tiles[row + x] = t
	L.tiles = tiles


static func _stand(r: Rect2i, rng: RandomNumberGenerator, used: Dictionary) -> Mod:
	var m := Mod.new()
	m.rect = r
	m.inner = r.grow(-1)
	var def: Array = _stand_def(rng, used)
	m.arch = def[0]
	m.role = def[1]
	m.name = def[2]
	m.type = FloorLayout.ROOM_REST if m.role in [&"stand_candy", &"stand_popcorn"] else _stand_type(rng)
	return m


static func _stand_def(rng: RandomNumberGenerator, used: Dictionary) -> Array:
	for attempt in 12:
		var def: Array = STANDS[rng.randi_range(0, STANDS.size() - 1)]
		var names: Array = def.slice(2)
		var nm: String = names[rng.randi_range(0, names.size() - 1)]
		if not used.has(nm):
			used[nm] = true
			return [def[0], def[1], nm]
	var d2: Array = STANDS[rng.randi_range(0, STANDS.size() - 1)]
	var base: String = d2[2]
	var nm2 := base
	var i := 2
	while used.has(nm2):
		nm2 = "%s %d" % [base, i]
		i += 1
	used[nm2] = true
	return [d2[0], d2[1], nm2]


static func _stand_type(rng: RandomNumberGenerator) -> StringName:
	var w := Cfg.get_dict("hc_stand_type_weights", {"combat": 4.0, "loot": 3.0, "trap": 1.5, "rest": 1.0})
	var keys := w.keys()
	keys.sort()
	var total := 0.0
	for key: Variant in keys:
		total += float(w[key])
	var roll := rng.randf() * total
	for key2: Variant in keys:
		roll -= float(w[key2])
		if roll <= 0.0:
			return StringName(key2)
	return FloorLayout.ROOM_COMBAT


## Découpe [a, b) (murs partagés : chaque rectangle va de y à y + h, h ≥ min+2) en morceaux.
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
		var d := rng.randi_range(-1, 1)
		if sizes[i3] + d >= wmin and sizes[i3 + 1] - d >= wmin:
			sizes[i3] += d
			sizes[i3 + 1] -= d
	var x := a
	for s in sizes:
		out.append(Vector2i(x, s + 1))
		x += s
	return out


## Pylônes des montagnes russes traversant la zone nord-est : cases de la polyligne.
static func _coaster_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(COASTER_IN.size() - 1):
		var a: Vector2i = COASTER_IN[i]
		var b: Vector2i = COASTER_IN[i + 1]
		var n := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for k in n + 1:
			var c := Vector2i(a.x + roundi(float(b.x - a.x) * k / maxf(n, 1)), a.y + roundi(float(b.y - a.y) * k / maxf(n, 1)))
			if not out.has(c):
				out.append(c)
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
	for i2 in range(W + 1, W * (H - 1) - 1):
		if src[i2] != T.VOID:
			continue
		# Case VOID : devient mur si une voisine (8) est marchable (VOID = 0, WALL = 3).
		var a := src[i2 - 1]
		var b := src[i2 + 1]
		var c := src[i2 - W]
		var d := src[i2 + W]
		var e := src[i2 - W - 1]
		var f := src[i2 - W + 1]
		var g := src[i2 + W - 1]
		var h := src[i2 + W + 1]
		if (a != 0 and a != 3) or (b != 0 and b != 3) or (c != 0 and c != 3) or (d != 0 and d != 3) \
				or (e != 0 and e != 3) or (f != 0 and f != 3) or (g != 0 and g != 3) or (h != 0 and h != 3):
			tiles[i2] = T.WALL
	L.tiles = tiles


# --- Portes -------------------------------------------------------------------------

## Chaque module relié à l'extérieur (unité 0) ou à un module voisin déjà relié, par une porte
## dans un mur droit ; jamais dans le mur nord d'un module à toit ; roulotte du Directeur : une
## porte verrouillée. Le chapiteau reçoit jusqu'à trois portes (sud, ouest, est).
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
		var area := m.rect if m.ellipse else m.inner
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				if tiles[y * W + x] == T.FLOOR and (not m.ellipse or tent_d(x, y) <= 1.0):
					unit[y * W + x] = m.unit
	for j in W * H:
		if unit[j] < 0 and tiles[j] != T.VOID and tiles[j] != T.WALL:
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
				if dn > 0 and (by_unit[dn] as Mod).roof:
					continue
				# Pas de porte sur la façade extérieure du portail (parvis) sauf billetteries.
				if (up == 0 and y2 + 1 >= GATE.position.y and dn > 0 and (by_unit[dn] as Mod).slot != "kiosk"):
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
			var g := _pick(groups, m3, connected, by_unit, door_cells)
			if g.is_empty():
				continue
			var st := DS.OPEN if (m3.slot == "stand" and not m3.roof) else _shut(rng)
			if m3.slot == "exit" or m3.slot == "big_top":
				st = DS.OPEN if rng.randf() < 0.5 else DS.CLOSED
			_door(L, m3, g, door_cells, rng, st, &"", m3.facade)
			connected[m3.unit] = true
			pending.erase(m3)
			progress = true
	if not pending.is_empty():
		return false
	# Chapiteau : entrées ouest et est en plus (murs verticaux de l'anneau).
	for mb in mods:
		if mb.slot != "big_top":
			continue
		for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT]:
			var g3 := _pick(groups, mb, connected, by_unit, door_cells)
			if g3.is_empty():
				break
			_door(L, mb, g3, door_cells, rng, DS.CLOSED, &"", side)
	for m4 in mods:
		if m4.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		var g2 := _pick(groups, m4, connected, by_unit, door_cells)
		if g2.is_empty():
			return false
		_door(L, m4, g2, door_cells, rng, DS.LOCKED, m4.key, m4.facade)
	return true


static func _shut(rng: RandomNumberGenerator) -> int:
	return DS.OPEN if rng.randf() < Cfg.getf("hc_door_open_chance", 0.35) else DS.CLOSED


static func _cand(groups: Dictionary, a: int, b: int, c: Vector2i, vertical: bool) -> void:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append([c, vertical])


static func _pick(groups: Dictionary, mu: Mod, connected: Dictionary, by_unit: Dictionary, door_cells: Dictionary) -> Dictionary:
	var u := mu.unit
	var best := {}
	var best_score := -1.0
	if not groups.has("_keys"):
		var ks: Array = groups.keys()
		ks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
		groups["_keys"] = ks
	for key: Vector2i in groups["_keys"]:
		if key.x != u and key.y != u:
			continue
		var v := key.y if key.x == u else key.x
		if not connected.has(v):
			continue
		if v > 0:
			var other: Mod = by_unit[v]
			if other.type == FloorLayout.ROOM_SUPER_LOOT or mu.type == FloorLayout.ROOM_SUPER_LOOT:
				continue
			if other.slot == "big_top" or mu.slot == "big_top":
				continue
		var cands: Array = []
		for c: Array in groups[key]:
			if _door_ok(c[0], door_cells):
				cands.append(c)
		if cands.is_empty():
			continue
		var score := float(cands.size()) + (100.0 if v == 0 else 0.0)
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


## Porte au milieu du mur côté `facade` si possible (sinon n'importe quel candidat).
static func _door(L: FloorLayout, m: Mod, g: Dictionary, door_cells: Dictionary, rng: RandomNumberGenerator, state: int, key: StringName, facade: Vector2i) -> void:
	var cands: Array = g["cands"]
	var side: Array = []
	for c0: Array in cands:
		var cell0: Vector2i = c0[0]
		var ok := false
		match facade:
			Vector2i.DOWN: ok = not c0[1] and cell0.y >= m.rect.end.y - 1 - (1 if m.ellipse else 0)
			Vector2i.UP: ok = not c0[1] and cell0.y <= m.rect.position.y
			Vector2i.LEFT: ok = c0[1] and cell0.x <= m.rect.position.x + (1 if m.ellipse else 0)
			Vector2i.RIGHT: ok = c0[1] and cell0.x >= m.rect.end.x - 1 - (1 if m.ellipse else 0)
		if ok:
			side.append(c0)
	if side.is_empty():
		side = cands
	side.sort_custom(func(a: Array, b: Array) -> bool:
		var ca: Vector2i = a[0]
		var cb: Vector2i = b[0]
		return ca.x + ca.y * 1000 < cb.x + cb.y * 1000)
	var j := clampi(side.size() / 2 + rng.randi_range(-1, 1), 0, side.size() - 1)
	var c: Array = side[j]
	var cell: Vector2i = c[0]
	var vertical: bool = c[1]
	var ca := cell + (Vector2i.LEFT if vertical else Vector2i.UP)
	var cb := cell + (Vector2i.RIGHT if vertical else Vector2i.DOWN)
	var ia := room_id_at(L, ca)
	var ib := room_id_at(L, cb)
	var oid := ib if ia == m.room.id else ia
	var other := L.get_room(oid) if oid >= 0 else null
	var bid := m.building.id if m.building != null else -1
	L.add_door(cell, vertical, state, m.room.id, other.id if other != null else -1, key, bid)
	door_cells[cell] = true


## Salle contenant `c` autre que `exclude` (la plus petite) : le chapiteau ovale a une boîte
## englobante qui déborde sur la place.
static func room_at_ex(L: FloorLayout, c: Vector2i, exclude: FloorLayout.Room) -> FloorLayout.Room:
	var best: FloorLayout.Room = null
	for r in L.rooms:
		if r == exclude or not r.rect.has_point(c):
			continue
		if best == null or r.rect.get_area() < best.rect.get_area():
			best = r
	return best


## Grille salle par case (id, -1 hors salle) tenant compte de l'ovale du chapiteau : les cases de
## sa boîte englobante hors de l'ovale appartiennent à la salle environnante (place). Plus petite
## salle prioritaire. Utilisée par le peupleur et le constructeur.
static func room_grid(L: FloorLayout) -> PackedInt32Array:
	if L.has_meta(&"cell_rooms"):
		return (L.get_meta(&"cell_rooms") as PackedInt32Array).duplicate()
	var w := L.size.x
	var g := PackedInt32Array()
	g.resize(w * L.size.y)
	g.fill(-1)
	var rooms := L.rooms.duplicate()
	rooms.sort_custom(func(a: FloorLayout.Room, b: FloorLayout.Room) -> bool: return a.rect.get_area() > b.rect.get_area())
	var big: FloorLayout.Room = null
	for r: FloorLayout.Room in rooms:
		if r.tags.size() > 0 and r.tags[0] == "big_top":
			big = r
			continue
		for y in range(maxi(r.rect.position.y, 0), mini(r.rect.end.y, L.size.y)):
			for x in range(maxi(r.rect.position.x, 0), mini(r.rect.end.x, w)):
				g[y * w + x] = r.id
	if big != null:
		for y2 in range(maxi(big.rect.position.y, 0), mini(big.rect.end.y, L.size.y)):
			for x2 in range(maxi(big.rect.position.x, 0), mini(big.rect.end.x, w)):
				if tent_d(x2, y2) <= 1.0:
					g[y2 * w + x2] = big.id
	return g


## Salle d'une case en tenant compte de l'ovale du chapiteau (cases de la boîte englobante hors
## de l'ovale → salle environnante). Version unitaire (voir room_grid pour toute la grille).
static func room_id_at(L: FloorLayout, c: Vector2i) -> int:
	if L.has_meta(&"cell_rooms"):
		return (L.get_meta(&"cell_rooms") as PackedInt32Array)[c.y * W + c.x] if L.in_bounds(c) else -1
	var r := L.room_at(c)
	if r == null:
		return -1
	if r.tags.size() > 0 and r.tags[0] == "big_top" and tent_d(c.x, c.y) > 1.0:
		var o := room_at_ex(L, c, r)
		return o.id if o != null else -1
	return r.id


static func _validate(L: FloorLayout, mods: Array[Mod]) -> bool:
	if not FloorLayout.is_walkable_tile(L.get_tile(L.player_spawn)):
		return false
	var tiles := L.tiles
	var walk := tiles.count(T.STREET) + tiles.count(T.FLOOR) + tiles.count(T.DOOR)
	# Un seul remplissage, portes verrouillées fermées : tout doit être atteint sauf les salles
	# super_loot (et leur porte verrouillée), qui doivent rester totalement inatteignables.
	var seen := _flood(L, false)
	var n := seen.count(1)
	var sealed := 0
	for m in mods:
		if m.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		for y2 in range(m.inner.position.y, m.inner.end.y):
			for x2 in range(m.inner.position.x, m.inner.end.x):
				var i := y2 * W + x2
				if seen[i] == 1:
					return false
				if tiles[i] == T.FLOOR or tiles[i] == T.DOOR:
					sealed += 1
	for d in L.doors:
		if d.state == DS.LOCKED:
			sealed += 1
	if n + sealed != walk:
		return false
	return L.extraction_cells.size() >= 2


## Remplissage rapide (tableaux compacts) depuis l'apparition : 1 par case atteinte.
static func _flood(L: FloorLayout, through_locked: bool) -> PackedByteArray:
	var tiles := L.tiles
	var seen := PackedByteArray()
	seen.resize(W * H)
	var locked := PackedByteArray()
	if not through_locked:
		locked.resize(W * H)
		for d in L.doors:
			if d.state == DS.LOCKED:
				locked[d.cell.y * W + d.cell.x] = 1
	var q := PackedInt32Array()
	q.resize(W * H)
	var start := L.player_spawn.y * W + L.player_spawn.x
	q[0] = start
	var tail := 1
	var head := 0
	seen[start] = 1
	var nwh := W * H
	while head < tail:
		var i := q[head]
		head += 1
		for k in 4:
			var j: int = i - 1 if k == 0 else (i + 1 if k == 1 else (i - W if k == 2 else i + W))
			if j < 0 or j >= nwh or seen[j] == 1:
				continue
			var t := tiles[j]
			if t == T.VOID or t == T.WALL:
				continue
			if t == T.DOOR and not through_locked and locked[j] == 1:
				continue
			seen[j] = 1
			q[tail] = j
			tail += 1
	return seen


# --- Contrat de rendu ------------------------------------------------------------------

static func _contract(L: FloorLayout, mods: Array[Mod], rng: RandomNumberGenerator) -> void:
	var ml: Array = []
	for m in mods:
		ml.append({"room": m.room.id, "rect": m.rect, "inner": m.inner, "role": String(m.role), "arch": String(m.arch),
			"slot": m.slot, "roof": m.roof, "type": String(m.type), "name": m.name,
			"building": m.building.id if m.building != null else -1, "facade": m.facade,
			"ellipse": m.ellipse, "color": rng.randi_range(0, 3)})
	var rides: Array = []
	rides.append({"kind": WHEEL["kind"], "c": WHEEL["c"], "r": float(WHEEL["r"])})
	for rd: Dictionary in RIDES:
		rides.append({"kind": rd["kind"], "c": rd["c"], "r": float(rd["r"])})
	# Montagnes russes : boucle hors jeu dans la marge (nord, est, sud-est) + section intérieure.
	var loop: Array = [[-4.0, 60.0], [-4.0, 20.0], [0.0, 4.0], [10.0, -3.0], [26.0, -4.0], [40.0, -2.0], [52.0, -5.0],
		[64.0, -3.0], [74.0, 2.0], [75.0, 14.0], [72.0, 30.0], [75.0, 46.0], [73.0, 62.0], [75.0, 80.0], [72.0, 98.0], [74.0, 112.0], [70.0, 122.0]]
	var inner: Array = []
	for c: Vector2i in COASTER_IN:
		inner.append([c.x + 0.5, c.y + 0.5])
	# Arbres morts et lampadaires hors jeu (marge), guirlandes le long de l'allée.
	var trees: Array = []
	for i in 46:
		var side := rng.randi_range(0, 3)
		var p: Vector2
		match side:
			0: p = Vector2(rng.randf_range(-9.0, W + 9.0), rng.randf_range(-10.0, -5.0))
			1: p = Vector2(rng.randf_range(-10.0, -4.5), rng.randf_range(0.0, H + 2.0))
			2: p = Vector2(W + rng.randf_range(4.5, 10.0), rng.randf_range(0.0, H + 2.0))
			_: p = Vector2(rng.randf_range(-9.0, W + 9.0), H + rng.randf_range(1.5, 8.0))
		trees.append([p.x, p.y, rng.randf_range(0.8, 1.4)])
	var paths: Array = []
	for p0: Array in PATHS:
		paths.append({"pts": p0[0], "w": p0[1], "role": String(p0[2])})
	var yards: Array = []
	for y0: Array in YARDS:
		yards.append({"c": y0[0], "r": y0[1], "role": String(y0[2])})
	L.set_meta(&"render_contract", {"kind": "hc_ground", "modules": ml, "rides": rides, "coaster": loop,
		"coaster_in": inner, "tent": {"rect": TENT_RECT, "c": TENT_C, "r": TENT_R}, "plaza": PLAZA,
		"plaza_e": {"c": PLAZA_C, "r": PLAZA_R}, "paths": paths, "yards": yards, "lot": LOT,
		"gate": GATE, "gate_open": GATE_OPEN, "trees": trees})
