extends RefCounted
## Structure (sans peuplement) des 4 étages du centre commercial « Galeries Lumière ».
##
## Squelette commun (même grille pour tous les étages, escaliers aux mêmes cases) :
##
##   ┌──────────────────────────────────────────────┐
##   │ boutiques nord (rideaux métalliques au sud)   │
##   │════════ galerie nord ════════════════════════│
##   │║ │ grand bloc ouest │  ATRIUM  │ bloc est │ ║│   ║ = galeries latérales
##   │║ │                  │ fontaine │          │ ║│
##   │════════ galerie sud ═════════════════════════│
##   │ boutiques sud │ hall d'entrée │ boutiques sud │
##   └──────────────────────────────────────────────┘
##
## -1 Parking : grand plateau ouvert (piliers), locaux techniques au nord, rampe de sortie
##    (extraction) à l'ouest ; escaliers vers le hall et la galerie est du rez-de-chaussée.
##  0 Rez-de-chaussée : hall d'entrée (spawn), atrium et fontaine, galeries = couloirs,
##    boutiques = salles derrière des rideaux métalliques, bijouterie verrouillée (super_loot).
##  1 Galerie haute : balcons autour du vide de l'atrium, food court au-dessus du hall,
##    cinéma et salle d'arcade dans les grands blocs, couloir de service vers les toits.
##  2 Toits et bureaux : toit-terrasse, verrière de l'atrium, héliport (extraction), bloc
##    de la direction (bureau du Directeur = boss, salle des coffres = super_loot).
##
## Toutes les salles reçoivent tags[0] = rôle d'ameublement, tags[1] = archétype/« open ».

const Cfg := preload("res://scripts/biomes/mall/mall_config.gd")
const T := FloorLayout.Tile
const DS := FloorLayout.DoorState

const KEY_JEWELRY := &"key_mall_jewelry"
const KEY_OFFICES := &"key_mall_offices"

## Boutiques possibles : [archétype, rôle, noms…].
const SHOPS := [
	[&"clothes", &"shop_clothes", "Boutique Mode & Co", "Prêt-à-porter Élégance", "Atelier Couture"],
	[&"electronics", &"shop_electronics", "Électro Néon", "High-Tech Center"],
	[&"pharmacy", &"shop_pharmacy", "Pharmacie de la Galerie", "Parapharmacie du Lys"],
	[&"toys", &"shop_toys", "Royaume du Jouet", "Le Coffre à Jouets"],
	[&"shoes", &"shop_shoes", "Chausseur Pas-de-Loup", "Talons & Semelles"],
	[&"perfume", &"shop_perfume", "Parfumerie Iris", "Sillage Boutique"],
	[&"books", &"shop_books", "Librairie Le Marque-Page", "Presse & Papiers"],
	[&"sports", &"shop_sports", "Sport Avenue", "Cap Évasion"],
	[&"cafe", &"shop_cafe", "Café des Arcades", "Salon de thé Vermeil"],
	[&"phones", &"shop_electronics", "Mobile Store", "Planète Portable"],
]
## Noms de réserve par archétype, quand les noms de SHOPS sont déjà pris (grands plans) :
## évite « Pharmacie de la Galerie 2 ».
const EXTRA_NAMES := {
	&"clothes": ["Maison Velours", "Fil d'Ariane", "Denim District"],
	&"electronics": ["Circuit Lumière", "Pixel Planète", "Ondes & Cie"],
	&"pharmacy": ["Pharmacie du Square", "Herboristerie Sauge", "Officine Saint-Roch"],
	&"toys": ["Ludothèque Arc-en-Ciel", "Petit Pantin", "Comptoir des Jeux"],
	&"shoes": ["Semelle de Vent", "Cordonnerie Brun", "Basket Factory"],
	&"perfume": ["Ambre & Musc", "L'Essence Rare", "Jardin d'Hespéride"],
	&"books": ["BD Planète", "La Bouquinerie", "Papeterie Encre Bleue"],
	&"sports": ["Grimpe & Glisse", "Le Vestiaire", "Outdoor Horizon"],
	&"cafe": ["Brasserie du Dôme", "Crêperie Bigoudène", "Comptoir Sucré"],
	&"phones": ["Allô Réparation", "Hello Mobile", "Câbles & Coques"],
}


class Skeleton:
	var size: Vector2i
	var sgw: int
	var gw: int
	var dn: int
	var ds: int
	var hm: int
	var aw: int
	var wb_w: int
	var wb_e: int
	var north_row: Rect2i
	var north_gal: Rect2i
	var south_gal: Rect2i
	var south_row: Rect2i
	var west_gal: Rect2i
	var east_gal: Rect2i
	var west_block: Rect2i
	var east_block: Rect2i
	var atrium: Rect2i
	var hall: Rect2i
	var north_slots: Array[Vector2i] = []   ## (x0, largeur)
	var south_slots: Array[Vector2i] = []
	var esc_cells: Array[Vector2i] = []     ## 0 ↔ 1 (escalators)
	var park_cells: Array[Vector2i] = []    ## -1 ↔ 0
	var service_slot: int = -1              ## index dans north_slots (étage 1)
	var service_cell: Vector2i              ## 1 ↔ 2
	var office: Rect2i                      ## bloc de la direction (étage 2, murs compris)
	var supermarket_west: bool = true


# --- Squelette -------------------------------------------------------------------

static func make_skeleton(seed_value: int) -> Skeleton:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "mall_skeleton"])
	var k := Skeleton.new()
	k.sgw = Cfg.range_i(rng, "mall_side_gallery_width", 3, 3)
	k.gw = Cfg.range_i(rng, "mall_gallery_width", 3, 4)
	k.dn = Cfg.range_i(rng, "mall_shop_depth", 7, 9)
	k.ds = Cfg.range_i(rng, "mall_shop_depth", 7, 9)
	k.hm = Cfg.range_i(rng, "mall_middle_height", 12, 15)
	k.aw = Cfg.range_i(rng, "mall_atrium_width", 12, 16)
	k.wb_w = Cfg.range_i(rng, "mall_block_width", 12, 16)
	k.wb_e = Cfg.range_i(rng, "mall_block_width", 12, 16)
	var W := 8 + 2 * k.sgw + k.wb_w + k.wb_e + k.aw
	var m0 := 3 + k.dn + k.gw
	var m1 := m0 + k.hm
	var H := m1 + k.gw + 1 + k.ds + 2
	k.size = Vector2i(W, H)
	k.north_row = Rect2i(2, 2, W - 4, k.dn)
	k.north_gal = Rect2i(2, 3 + k.dn, W - 4, k.gw)
	k.south_gal = Rect2i(2, m1, W - 4, k.gw)
	k.south_row = Rect2i(2, m1 + k.gw + 1, W - 4, k.ds)
	k.west_gal = Rect2i(2, k.north_gal.position.y, k.sgw, k.south_gal.end.y - k.north_gal.position.y)
	k.east_gal = Rect2i(W - 2 - k.sgw, k.north_gal.position.y, k.sgw, k.west_gal.size.y)
	var ax0 := 4 + k.sgw + k.wb_w
	k.atrium = Rect2i(ax0, m0, k.aw, k.hm)
	k.west_block = Rect2i(3 + k.sgw, m0 + 1, k.wb_w, k.hm - 2)
	k.east_block = Rect2i(ax0 + k.aw + 1, m0 + 1, k.wb_e, k.hm - 2)
	var hw := Cfg.range_i(rng, "mall_hall_width", 8, 10)
	var hx0 := ax0 + k.aw / 2 - hw / 2
	k.hall = Rect2i(hx0, k.south_row.position.y, hw, k.ds)
	k.north_slots = split_band(2, W - 2, rng)
	k.south_slots = split_band(2, hx0 - 1, rng)
	k.south_slots.append_array(split_band(hx0 + hw + 1, W - 2, rng))
	k.supermarket_west = rng.randf() < 0.5
	# Escalators de l'atrium (bords ouest et est, à mi-hauteur).
	var ey := m0 + k.hm / 2
	k.esc_cells = [Vector2i(ax0, ey), Vector2i(ax0 + k.aw - 1, ey)]
	# Escaliers du parking : coin du hall d'entrée + galerie latérale est.
	k.park_cells = [Vector2i(k.hall.end.x - 2, k.south_row.end.y - 1),
		Vector2i(W - 3, k.east_gal.position.y + k.east_gal.size.y / 2 + rng.randi_range(-2, 2))]
	# Couloir de service (étage 1) : une boutique nord, ni aux bouts ni trop étroite.
	var cands: Array[int] = []
	for i in k.north_slots.size():
		if i > 0 and i < k.north_slots.size() - 1 and k.north_slots[i].y >= 4:
			cands.append(i)
	if cands.is_empty():
		cands.append(k.north_slots.size() / 2)
	k.service_slot = cands[rng.randi_range(0, cands.size() - 1)]
	var ss := k.north_slots[k.service_slot]
	var sx := ss.x + 1 if rng.randf() < 0.5 else ss.x + ss.y - 2
	k.service_cell = Vector2i(sx, k.north_row.end.y - 1)
	# Bloc de la direction (étage 2) : couvre le couloir de service.
	var ow := Cfg.range_i(rng, "mall_office_width", 19, 24)
	ow = mini(ow, W - 2)
	var lo := maxi(1, sx - ow + 5)
	var hi := mini(W - 1 - ow, sx - 4)
	var ox0 := rng.randi_range(mini(lo, hi), maxi(lo, hi))
	ox0 = clampi(ox0, 1, W - 1 - ow)
	k.office = Rect2i(ox0, 1, ow, k.dn + 2)
	return k


## Découpe [x0, x1) en emplacements de boutiques (largeur 5..9) séparés par un mur.
static func split_band(x0: int, x1: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var length := x1 - x0
	if length < 4:
		return out
	var wmin := Cfg.geti("mall_shop_width_min", 5)
	var wmax := Cfg.geti("mall_shop_width_max", 9)
	var n := maxi(1, int(round(float(length + 1) / float((wmin + wmax) / 2 + 1))))
	while n > 1 and (length - (n - 1)) / n < wmin:
		n -= 1
	var total := length - (n - 1)
	var widths: Array[int] = []
	for i in n:
		widths.append(total / n)
	for i in total - (total / n) * n:
		widths[i] += 1
	# Variation : transfert de largeur entre voisines (somme constante).
	for i in n - 1:
		var d := rng.randi_range(-2, 2)
		if widths[i] + d >= wmin and widths[i + 1] - d >= wmin and widths[i] + d <= wmax + 2 and widths[i + 1] - d <= wmax + 2:
			widths[i] += d
			widths[i + 1] -= d
	var x := x0
	for w in widths:
		out.append(Vector2i(x, w))
		x += w + 1
	return out


# --- Aides de construction -----------------------------------------------------

static func _new_floor(k: Skeleton, index: int) -> FloorLayout:
	var L := FloorLayout.new(k.size)
	L.floor_index = index
	return L


static func _room(L: FloorLayout, rect: Rect2i, outdoor: bool, type: StringName, name: String, role: StringName, arch: StringName, building_id: int = -1) -> FloorLayout.Room:
	var r := L.add_room(rect, outdoor, type, name, building_id)
	r.tags = PackedStringArray([String(role), String(arch)])
	return r


static func _stairs(L: FloorLayout, c: Vector2i, up: bool, target: int) -> void:
	L.set_tile(c, T.STAIRS_UP if up else T.STAIRS_DOWN)
	var s := FloorLayout.Stairs.new()
	s.cell = c
	s.up = up
	s.target_floor = target
	s.target_cell = c
	L.stairs.append(s)


static func _pick(a: Array, rng: RandomNumberGenerator) -> Variant:
	return a[rng.randi_range(0, a.size() - 1)]


static func _shop_type(rng: RandomNumberGenerator) -> StringName:
	var w := Cfg.get_dict("mall_shop_type_weights", {"combat": 4.0, "loot": 3.0, "trap": 1.5, "rest": 1.0})
	var keys := w.keys()
	keys.sort()
	var total := 0.0
	for key: Variant in keys:
		total += float(w[key])
	var roll := rng.randf() * total
	for key2: Variant in keys:
		roll -= float(w[key2])
		if roll <= 0.0:
			return StringName(String(key2))
	return FloorLayout.ROOM_COMBAT


## Choisit une boutique (archétype, rôle, nom) en évitant les doublons de nom.
static func _shop_def(rng: RandomNumberGenerator, used: Dictionary) -> Array:
	for attempt in 12:
		var def: Array = _pick(SHOPS, rng)
		var names: Array = def.slice(2)
		var nm: String = _pick(names, rng)
		if not used.has(nm):
			used[nm] = true
			return [def[0], def[1], nm]
	var d2: Array = _pick(SHOPS, rng)
	# Noms de réserve de l'archétype (sans tirage : le plan, et donc le rendu pré-calculé, ne
	# change pas), avant de numéroter en dernier recours.
	for extra: String in d2.slice(2) + (EXTRA_NAMES.get(d2[0], []) as Array):
		if not used.has(extra):
			used[extra] = true
			return [d2[0], d2[1], extra]
	var base: String = d2[2]
	var nm2 := base
	var i := 2
	while used.has(nm2):
		nm2 = "%s %d" % [base, i]
		i += 1
	used[nm2] = true
	return [d2[0], d2[1], nm2]


## Boutique d'une rangée (nord : porte au sud ; sud : porte au nord), avec réserve éventuelle.
## Renvoie l'id de la salle de façade.
static func _row_shop(L: FloorLayout, slot: Vector2i, row: Rect2i, north: bool, gallery_room: int,
		arch: StringName, role: StringName, name: String, type: StringName, rng: RandomNumberGenerator,
		door_state: int, key: StringName = &"", allow_back: bool = true) -> int:
	var inner := Rect2i(slot.x, row.position.y, slot.y, row.size.y)
	var b := L.add_building(arch, name, inner.grow(1))
	L.fill_rect(inner, T.FLOOR)
	var door_y := inner.end.y if north else inner.position.y - 1
	var dx := inner.position.x + rng.randi_range(1, maxi(1, inner.size.x - 2))
	var back_d := 0
	if allow_back and inner.size.y >= 7 and inner.size.x >= 5 and rng.randf() < Cfg.getf("mall_back_room_chance", 0.55):
		back_d = rng.randi_range(2, 3)
	var front := inner
	var back := Rect2i()
	if back_d > 0:
		if north:
			back = Rect2i(inner.position.x, inner.position.y, inner.size.x, back_d)
			front = Rect2i(inner.position.x, inner.position.y + back_d + 1, inner.size.x, inner.size.y - back_d - 1)
			L.fill_rect(Rect2i(inner.position.x, inner.position.y + back_d, inner.size.x, 1), T.WALL)
		else:
			back = Rect2i(inner.position.x, inner.end.y - back_d, inner.size.x, back_d)
			front = Rect2i(inner.position.x, inner.position.y, inner.size.x, inner.size.y - back_d - 1)
			L.fill_rect(Rect2i(inner.position.x, inner.end.y - back_d - 1, inner.size.x, 1), T.WALL)
	var fr := _room(L, front, false, type, name, role, arch, b.id)
	L.add_door(Vector2i(dx, door_y), false, door_state, gallery_room, fr.id, key, b.id)
	if back_d > 0:
		var br := _room(L, back, false, FloorLayout.ROOM_LOOT, "Réserve — %s" % name, &"stockroom", arch, b.id)
		var py := back.end.y if north else back.position.y - 1
		var bx := inner.position.x + rng.randi_range(0, inner.size.x - 1)
		# La porte de réserve ne doit pas faire face à la porte de façade (abords libres).
		if absi(bx - dx) <= 0:
			bx = inner.position.x if dx > inner.position.x + inner.size.x / 2 else inner.end.x - 1
		L.add_door(Vector2i(bx, py), false, DS.CLOSED, fr.id, br.id, &"", b.id)
	return fr.id


static func _door_state(rng: RandomNumberGenerator) -> int:
	return DS.OPEN if rng.randf() < Cfg.getf("mall_shutter_open_chance", 0.3) else DS.CLOSED


# --- Étage 0 : rez-de-chaussée ----------------------------------------------------

static func build_ground(k: Skeleton, seed_value: int) -> FloorLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "mall_ground"])
	var L := _new_floor(k, 0)
	L.fill_rect(Rect2i(1, 1, k.size.x - 2, k.size.y - 2), T.WALL)
	for r: Rect2i in [k.north_gal, k.south_gal, k.west_gal, k.east_gal, k.atrium, k.hall]:
		L.fill_rect(r, T.STREET)
	# Le hall s'ouvre sur la galerie sud (mur de rangée percé sur sa largeur).
	L.fill_rect(Rect2i(k.hall.position.x, k.south_gal.end.y, k.hall.size.x, 1), T.STREET)
	var hall := _room(L, Rect2i(k.hall.position.x, k.south_gal.end.y, k.hall.size.x, k.hall.size.y + 1), true,
		FloorLayout.ROOM_SPAWN, "Hall d'entrée", &"entrance", &"open")
	var atrium := _room(L, k.atrium, true, FloorLayout.ROOM_COMBAT, "Atrium de la fontaine", &"atrium", &"open")
	var gn := _room(L, k.north_gal, true, FloorLayout.ROOM_CORRIDOR, "Galerie des Lumières", &"gallery", &"open")
	var gs := _room(L, k.south_gal, true, FloorLayout.ROOM_CORRIDOR, "Galerie du Couchant", &"gallery", &"open")
	var gw := _room(L, k.west_gal, true, FloorLayout.ROOM_COMBAT, "Allée ouest", &"gallery", &"open")
	var ge := _room(L, k.east_gal, true, FloorLayout.ROOM_COMBAT, "Allée est", &"gallery", &"open")
	var used := {}
	# Bijouterie : une boutique de la rangée nord ou sud (pas au bord du hall).
	var all_slots: Array = []
	for i in k.north_slots.size():
		all_slots.append([true, i])
	for j in k.south_slots.size():
		all_slots.append([false, j])
	var jewel: Array = _pick(all_slots, rng)
	for s: Array in all_slots:
		var north: bool = s[0]
		var slot: Vector2i = (k.north_slots if north else k.south_slots)[int(s[1])]
		var row := k.north_row if north else k.south_row
		var gal := gn.id if north else gs.id
		if s == jewel:
			_row_shop(L, slot, row, north, gal, &"jewelry", &"shop_jewelry", "Bijouterie Éclat d'Or",
				FloorLayout.ROOM_SUPER_LOOT, rng, DS.LOCKED, KEY_JEWELRY, false)
			continue
		var def := _shop_def(rng, used)
		var t := FloorLayout.ROOM_REST if def[1] == &"shop_cafe" else _shop_type(rng)
		_row_shop(L, slot, row, north, gal, def[0], def[1], def[2], t, rng, _door_state(rng))
	# Grands blocs : hypermarché et grand magasin.
	var sm_block := k.west_block if k.supermarket_west else k.east_block
	var dp_block := k.east_block if k.supermarket_west else k.west_block
	_big_store(L, sm_block, k.supermarket_west, gw.id if k.supermarket_west else ge.id, gn.id, gs.id,
		&"supermarket", &"supermarket", "Hypermarché Primeur", "Réserve de l'hypermarché", rng)
	_big_store(L, dp_block, not k.supermarket_west, ge.id if k.supermarket_west else gw.id, gn.id, gs.id,
		&"department", &"shop_clothes", "Grand Magasin Lumière", "Cabines et stock", rng)
	for c in k.esc_cells:
		_stairs(L, c, true, 1)
	for c2 in k.park_cells:
		_stairs(L, c2, false, -1)
	L.player_spawn = Vector2i(k.hall.position.x + k.hall.size.x / 2 - 1, k.hall.end.y - 2)
	var _unused := [hall, atrium]
	return L


## Grand magasin d'un bloc central : salle principale + arrière (réserve/cabines),
## porte sur la galerie latérale et porte sur la galerie nord ou sud.
static func _big_store(L: FloorLayout, B: Rect2i, west: bool, side_gal: int, gn: int, gs: int,
		arch: StringName, role: StringName, name: String, back_name: String, rng: RandomNumberGenerator) -> void:
	var b := L.add_building(arch, name, B.grow(1))
	L.fill_rect(B, T.FLOOR)
	var bw := rng.randi_range(3, 4)
	# Arrière côté atrium (est pour le bloc ouest).
	var main := Rect2i(B.position.x, B.position.y, B.size.x - bw - 1, B.size.y) if west \
		else Rect2i(B.position.x + bw + 1, B.position.y, B.size.x - bw - 1, B.size.y)
	var back := Rect2i(B.end.x - bw, B.position.y, bw, B.size.y) if west \
		else Rect2i(B.position.x, B.position.y, bw, B.size.y)
	var px := B.end.x - bw - 1 if west else B.position.x + bw
	L.fill_rect(Rect2i(px, B.position.y, 1, B.size.y), T.WALL)
	var mr := _room(L, main, false, FloorLayout.ROOM_COMBAT, name, role, arch, b.id)
	var br := _room(L, back, false, FloorLayout.ROOM_LOOT, back_name, &"stockroom", arch, b.id)
	# Porte latérale (mur vertical côté galerie latérale).
	var side_x := B.position.x - 1 if west else B.end.x
	var sy := B.position.y + rng.randi_range(1, B.size.y - 2)
	L.add_door(Vector2i(side_x, sy), true, _door_state(rng), side_gal, mr.id, &"", b.id)
	# Porte sur une galerie principale (rideau métallique).
	var north := rng.randf() < 0.5
	var gy := B.position.y - 1 if north else B.end.y
	var gx := main.position.x + rng.randi_range(1, main.size.x - 2)
	L.add_door(Vector2i(gx, gy), false, _door_state(rng), gn if north else gs, mr.id, &"", b.id)
	# Porte de l'arrière (cloison verticale), loin des coins.
	var by := B.position.y + rng.randi_range(1, B.size.y - 2)
	if absi(by - sy) <= 1:
		by = B.position.y + (B.size.y - 2 if sy < B.position.y + B.size.y / 2 else 1)
	L.add_door(Vector2i(px, by), true, DS.CLOSED, mr.id, br.id, &"", b.id)


# --- Étage 1 : galerie haute --------------------------------------------------------

static func build_upper(k: Skeleton, seed_value: int) -> FloorLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "mall_upper"])
	var L := _new_floor(k, 1)
	L.fill_rect(Rect2i(1, 1, k.size.x - 2, k.size.y - 2), T.WALL)
	for r: Rect2i in [k.north_gal, k.south_gal, k.west_gal, k.east_gal, k.atrium, k.hall]:
		L.fill_rect(r, T.STREET)
	L.fill_rect(Rect2i(k.hall.position.x, k.south_gal.end.y, k.hall.size.x, 1), T.STREET)
	# Vide de l'atrium : balcons de 2 cases sur les côtés, 1 case au nord et au sud.
	var hole := Rect2i(k.atrium.position.x + 2, k.atrium.position.y + 1, k.atrium.size.x - 4, k.atrium.size.y - 2)
	L.fill_rect(hole, T.VOID)
	var fc_type := FloorLayout.ROOM_REST if rng.randf() < 0.5 else FloorLayout.ROOM_COMBAT
	_room(L, Rect2i(k.hall.position.x, k.south_gal.end.y, k.hall.size.x, k.hall.size.y + 1), true,
		fc_type, "Food court", &"food_court", &"open")
	_room(L, k.atrium, true, FloorLayout.ROOM_COMBAT, "Balcons de l'atrium", &"balcony", &"open")
	var gn := _room(L, k.north_gal, true, FloorLayout.ROOM_CORRIDOR, "Coursive nord", &"balcony", &"open")
	var gs := _room(L, k.south_gal, true, FloorLayout.ROOM_CORRIDOR, "Coursive sud", &"balcony", &"open")
	var gw := _room(L, k.west_gal, true, FloorLayout.ROOM_CORRIDOR, "Passerelle ouest", &"balcony", &"open")
	var ge := _room(L, k.east_gal, true, FloorLayout.ROOM_CORRIDOR, "Passerelle est", &"balcony", &"open")
	var used := {}
	for i in k.north_slots.size():
		var slot := k.north_slots[i]
		if i == k.service_slot:
			_service_room(L, k, slot, gn.id, rng)
			continue
		var def := _shop_def(rng, used)
		var t := FloorLayout.ROOM_REST if def[1] == &"shop_cafe" else _shop_type(rng)
		_row_shop(L, slot, k.north_row, true, gn.id, def[0], def[1], def[2], t, rng, _door_state(rng))
	for j in k.south_slots.size():
		var def2 := _shop_def(rng, used)
		var t2 := FloorLayout.ROOM_REST if def2[1] == &"shop_cafe" else _shop_type(rng)
		_row_shop(L, k.south_slots[j], k.south_row, false, gs.id, def2[0], def2[1], def2[2], t2, rng, _door_state(rng))
	var cine_west := rng.randf() < 0.5
	_cinema(L, k.west_block if cine_west else k.east_block, cine_west, gw.id if cine_west else ge.id, rng)
	_arcade(L, k.east_block if cine_west else k.west_block, not cine_west, ge.id if cine_west else gw.id, gn.id, gs.id, rng)
	for c in k.esc_cells:
		_stairs(L, c, false, 0)
	_stairs(L, k.service_cell, true, 2)
	L.player_spawn = k.esc_cells[0] + Vector2i.DOWN
	return L


static func _service_room(L: FloorLayout, k: Skeleton, slot: Vector2i, gal: int, rng: RandomNumberGenerator) -> void:
	var inner := Rect2i(slot.x, k.north_row.position.y, slot.y, k.north_row.size.y)
	var b := L.add_building(&"service", "Couloir de service", inner.grow(1))
	L.fill_rect(inner, T.FLOOR)
	var r := _room(L, inner, false, FloorLayout.ROOM_LOOT, "Couloir de service", &"service", &"service", b.id)
	# Porte loin de l'escalier (au moins 2 cases).
	var cands: Array[int] = []
	for x in range(inner.position.x, inner.end.x):
		if absi(x - k.service_cell.x) >= 2:
			cands.append(x)
	var dx: int = cands[rng.randi_range(0, cands.size() - 1)] if not cands.is_empty() else inner.position.x
	L.add_door(Vector2i(dx, inner.end.y), false, DS.CLOSED, gal, r.id, &"", b.id)


## Cinéma : hall côté galerie latérale, deux salles derrière (nord et sud).
static func _cinema(L: FloorLayout, B: Rect2i, west: bool, side_gal: int, rng: RandomNumberGenerator) -> void:
	var b := L.add_building(&"cinema", "Cinéma Le Grand Rex", B.grow(1))
	L.fill_rect(B, T.FLOOR)
	var lw := rng.randi_range(4, 5)
	var lobby := Rect2i(B.position.x, B.position.y, lw, B.size.y) if west else Rect2i(B.end.x - lw, B.position.y, lw, B.size.y)
	var px := lobby.end.x if west else lobby.position.x - 1
	L.fill_rect(Rect2i(px, B.position.y, 1, B.size.y), T.WALL)
	var rest_x := px + 1 if west else B.position.x
	var rest_w := B.end.x - rest_x if west else px - B.position.x
	var h1 := (B.size.y - 1) / 2
	var s1 := Rect2i(rest_x, B.position.y, rest_w, h1)
	var s2 := Rect2i(rest_x, B.position.y + h1 + 1, rest_w, B.size.y - h1 - 1)
	L.fill_rect(Rect2i(rest_x, B.position.y + h1, rest_w, 1), T.WALL)
	var lr := _room(L, lobby, false, FloorLayout.ROOM_COMBAT, "Hall du cinéma", &"cinema_lobby", &"cinema", b.id)
	var r1 := _room(L, s1, false, _shop_type(rng), "Salle 1", &"cinema_hall", &"cinema", b.id)
	var r2 := _room(L, s2, false, FloorLayout.ROOM_TRAP, "Salle 2", &"cinema_hall", &"cinema", b.id)
	var side_x := B.position.x - 1 if west else B.end.x
	var sy := B.position.y + B.size.y / 2 + rng.randi_range(-1, 1)
	L.add_door(Vector2i(side_x, sy), true, DS.CLOSED, side_gal, lr.id, &"", b.id)
	L.add_door(Vector2i(px, s1.position.y + s1.size.y / 2), true, DS.CLOSED, lr.id, r1.id, &"", b.id)
	L.add_door(Vector2i(px, s2.position.y + s2.size.y / 2), true, DS.CLOSED, lr.id, r2.id, &"", b.id)


## Salle d'arcade + bureau du gérant.
static func _arcade(L: FloorLayout, B: Rect2i, west: bool, side_gal: int, gn: int, gs: int, rng: RandomNumberGenerator) -> void:
	var b := L.add_building(&"arcade", "Salle d'arcade Pixel", B.grow(1))
	L.fill_rect(B, T.FLOOR)
	var ow := rng.randi_range(4, 5)
	var oh := rng.randi_range(4, B.size.y - 4)
	var north := rng.randf() < 0.5
	# Bureau dans le coin côté atrium.
	var ox := B.end.x - ow if west else B.position.x
	var office := Rect2i(ox, B.position.y if north else B.end.y - oh, ow, oh)
	var wall_x := office.position.x - 1 if west else office.end.x
	var wall_y := office.end.y if north else office.position.y - 1
	L.fill_rect(Rect2i(wall_x, office.position.y, 1, office.size.y), T.WALL)
	L.fill_rect(Rect2i(mini(wall_x, office.position.x), wall_y, ow + 1, 1), T.WALL)
	var main := _room(L, B, false, FloorLayout.ROOM_COMBAT, "Salle d'arcade Pixel", &"arcade", &"arcade", b.id)
	var off := _room(L, office, false, FloorLayout.ROOM_LOOT, "Bureau du gérant", &"office", &"arcade", b.id)
	var side_x := B.position.x - 1 if west else B.end.x
	var sy := B.position.y + B.size.y / 2 + (2 if north else -2)
	sy = clampi(sy, B.position.y + 1, B.end.y - 2)
	L.add_door(Vector2i(side_x, sy), true, _door_state(rng), side_gal, main.id, &"", b.id)
	# Porte du bureau : dans la cloison horizontale, côté salle.
	var dx := office.position.x + office.size.x / 2
	L.add_door(Vector2i(dx, wall_y), false, DS.CLOSED, main.id, off.id, &"", b.id)
	# Seconde entrée sur la galerie opposée au bureau.
	var gy := B.end.y if north else B.position.y - 1
	var gx := B.position.x + B.size.x / 2 + rng.randi_range(-2, 2)
	gx = clampi(gx, B.position.x + 1, B.end.x - 2)
	if absi(gx - dx) < 2:
		gx = clampi(dx + (3 if west else -3), B.position.x + 1, B.end.x - 2)
	L.add_door(Vector2i(gx, gy), false, _door_state(rng), gs if north else gn, main.id, &"", b.id)


# --- Étage 2 : toits et bureaux -----------------------------------------------------

static func build_roof(k: Skeleton, seed_value: int) -> FloorLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "mall_roof"])
	var L := _new_floor(k, 2)
	var W := k.size.x
	var H := k.size.y
	L.fill_rect(Rect2i(1, 1, W - 2, H - 2), T.WALL)
	var roof := Rect2i(2, 2, W - 4, H - 4)
	L.fill_rect(roof, T.STREET)
	# Verrière de l'atrium (infranchissable).
	L.fill_rect(k.atrium, T.VOID)
	# Bloc de la direction.
	var O := k.office
	L.fill_rect(O, T.WALL)
	var half := Rect2i(2, 2, (W - 4) / 2, H - 4)
	_room(L, half, true, FloorLayout.ROOM_COMBAT, "Toit-terrasse ouest", &"roof", &"open")
	_room(L, Rect2i(half.end.x, 2, W - 2 - half.end.x, H - 4), true, FloorLayout.ROOM_COMBAT, "Toit-terrasse est", &"roof", &"open")
	# Héliport (extraction) : coin sud, du côté opposé au bureau.
	var hw := 8
	var hh := mini(7, k.south_row.size.y + 1)
	var west_pad := O.get_center().x > W / 2
	var hx := 2 if west_pad else W - 2 - hw
	var heli := Rect2i(hx, H - 2 - hh, hw, hh)
	_room(L, heli, true, FloorLayout.ROOM_EXTRACTION, "Héliport", &"helipad", &"open")
	var hc := heli.get_center()
	for c: Vector2i in [hc + Vector2i(-1, -1), hc + Vector2i(0, -1), hc + Vector2i(-1, 0), hc]:
		L.extraction_cells.append(c)
	_offices(L, k, rng)
	_stairs(L, k.service_cell, false, 1)
	L.player_spawn = k.service_cell + Vector2i.LEFT
	if L.get_tile(L.player_spawn) != T.FLOOR:
		L.player_spawn = k.service_cell + Vector2i.RIGHT
	return L


static func _offices(L: FloorLayout, k: Skeleton, rng: RandomNumberGenerator) -> void:
	var O := k.office
	var b := L.add_building(&"offices", "Direction des Galeries", O)
	var ix0 := O.position.x + 1
	var ix1 := O.end.x - 1
	var y_cor := O.end.y - 3            # couloir : 2 rangées au-dessus du mur sud
	var y_part := y_cor - 1            # cloison bureaux / couloir
	var band := Rect2i(ix0, O.position.y + 1, ix1 - ix0, y_part - (O.position.y + 1))
	var cor := Rect2i(ix0, y_cor, ix1 - ix0, 2)
	L.fill_rect(cor, T.FLOOR)
	var cr := _room(L, cor, false, FloorLayout.ROOM_CORRIDOR, "Couloir de la direction", &"office_corridor", &"offices", b.id)
	# Largeurs : coffres, directeur, puis 1-2 bureaux.
	var vw := rng.randi_range(3, 4)
	var dw := rng.randi_range(6, 8)
	var rest := band.size.x - vw - dw - 2
	var offices: Array[int] = []
	if rest >= 9:
		var a := rng.randi_range(4, rest - 5)
		offices = [a, rest - a - 1]
	else:
		offices = [rest]
	var vault_west := rng.randf() < 0.5
	var order: Array = []   # [rôle, largeur]
	if vault_west:
		order = [[&"vault", vw], [&"director", dw]]
		for w in offices:
			order.append([&"office", w])
	else:
		for w2 in offices:
			order.append([&"office", w2])
		order.append([&"director", dw])
		order.append([&"vault", vw])
	var x := ix0
	var ids := {}
	var rects := {}
	var office_names := ["Secrétariat", "Bureau comptable", "Salle de réunion"]
	var oi := 0
	for e: Array in order:
		var role: StringName = e[0]
		var w3: int = e[1]
		var rr := Rect2i(x, band.position.y, w3, band.size.y)
		L.fill_rect(rr, T.FLOOR)
		var room: FloorLayout.Room
		match role:
			&"vault":
				room = _room(L, rr, false, FloorLayout.ROOM_SUPER_LOOT, "Salle des coffres", &"vault", &"offices", b.id)
			&"director":
				room = _room(L, rr, false, FloorLayout.ROOM_BOSS, "Bureau du Directeur", &"director", &"offices", b.id)
			_:
				room = _room(L, rr, false, FloorLayout.ROOM_LOOT if oi == 0 else _shop_type(rng), office_names[oi % office_names.size()], &"office", &"offices", b.id)
				oi += 1
		ids[x] = room.id
		rects[x] = [role, rr, room.id]
		x += w3 + 1
	# Portes : bureaux et directeur sur le couloir ; coffres depuis le bureau du Directeur.
	var dir_room := -1
	var dir_rect := Rect2i()
	var vault_room := -1
	var vault_rect := Rect2i()
	for key: Variant in rects:
		var e2: Array = rects[key]
		var role2: StringName = e2[0]
		var rr2: Rect2i = e2[1]
		if role2 == &"vault":
			vault_room = e2[2]
			vault_rect = rr2
			continue
		if role2 == &"director":
			dir_room = e2[2]
			dir_rect = rr2
		var dx := rr2.position.x + rng.randi_range(1, maxi(1, rr2.size.x - 2))
		if absi(dx - k.service_cell.x) <= 1:
			dx = rr2.position.x if k.service_cell.x > rr2.get_center().x else rr2.end.x - 1
		L.add_door(Vector2i(dx, y_part), false, DS.CLOSED, cr.id, e2[2], &"", b.id)
	var vx := vault_rect.end.x if vault_west else vault_rect.position.x - 1
	var vy := band.position.y + band.size.y / 2
	L.add_door(Vector2i(vx, vy), true, DS.LOCKED, dir_room, vault_room, KEY_OFFICES, b.id)
	# Entrées depuis le toit (porte vitrée dans le mur sud), loin de l'escalier.
	var roof_room := L.room_at(Vector2i(cor.position.x, O.end.y))
	var rid := roof_room.id if roof_room != null else -1
	var cands: Array[int] = []
	for xx in range(cor.position.x + 1, cor.end.x - 1):
		if absi(xx - k.service_cell.x) >= 3:
			cands.append(xx)
	var n_doors := 2 if cands.size() > 8 and rng.randf() < 0.6 else 1
	var placed: Array[int] = []
	for i in n_doors:
		if cands.is_empty():
			break
		var dx2: int = cands[rng.randi_range(0, cands.size() - 1)]
		var ok := true
		for p in placed:
			if absi(p - dx2) < 4:
				ok = false
		if not ok:
			continue
		placed.append(dx2)
		var rr3 := L.room_at(Vector2i(dx2, O.end.y))
		L.add_door(Vector2i(dx2, O.end.y - 1), false, DS.CLOSED, rr3.id if rr3 != null else rid, cr.id, &"", b.id)
	var _u := [ids, dir_rect]


# --- Étage -1 : parking ---------------------------------------------------------------

static func build_parking(k: Skeleton, seed_value: int) -> FloorLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "mall_parking"])
	var L := _new_floor(k, -1)
	var W := k.size.x
	var H := k.size.y
	L.fill_rect(Rect2i(1, 1, W - 2, H - 2), T.WALL)
	var P := Rect2i(2, 2, W - 4, H - 4)
	L.fill_rect(P, T.STREET)
	# Zones (salles ouvertes) : trois allées.
	var zw := P.size.x / 3
	var zone_types := [FloorLayout.ROOM_COMBAT, FloorLayout.ROOM_TRAP, FloorLayout.ROOM_LOOT]
	var zone_names := ["Parking — allée A", "Parking — allée B", "Parking — allée C"]
	for i in 3:
		var zx := P.position.x + i * zw
		var w := zw if i < 2 else P.end.x - zx
		_room(L, Rect2i(zx, P.position.y, w, P.size.y), true, zone_types[(i + rng.randi_range(0, 2)) % 3], zone_names[i], &"parking", &"open")
	# Rampe de sortie (extraction) à l'ouest.
	var ym := P.position.y + P.size.y / 2 + rng.randi_range(-3, 3)
	var ramp := Rect2i(2, ym - 3, 6, 7)
	_room(L, ramp, true, FloorLayout.ROOM_EXTRACTION, "Rampe de sortie", &"ramp", &"open")
	for c: Vector2i in [Vector2i(3, ym - 1), Vector2i(4, ym - 1), Vector2i(3, ym), Vector2i(4, ym)]:
		L.extraction_cells.append(c)
	# Locaux de service le long du mur nord.
	var specs := [
		[&"technical", "Local technique", Vector2i(6, 8), Vector2i(4, 5), FloorLayout.ROOM_LOOT],
		[&"security", "Poste de sécurité", Vector2i(5, 6), Vector2i(4, 4), FloorLayout.ROOM_COMBAT],
		[&"trash", "Local poubelles", Vector2i(4, 5), Vector2i(3, 4), FloorLayout.ROOM_TRAP],
	]
	var x := 9 + rng.randi_range(0, 3)
	var forbidden: Array[Rect2i] = [ramp.grow(2)]
	for c2 in k.park_cells:
		forbidden.append(Rect2i(c2 - Vector2i(2, 2), Vector2i(5, 5)))
	var rooms_rects: Array[Rect2i] = []
	for s: Array in specs:
		var wr: Vector2i = s[2]
		var dr: Vector2i = s[3]
		var w2 := rng.randi_range(wr.x, wr.y)
		var d := rng.randi_range(dr.x, dr.y)
		var br := Rect2i(x, 1, w2 + 2, d + 2)
		if br.end.x > W - 6:
			break
		var clash := false
		for f in forbidden:
			if f.intersects(br.grow(1)):
				clash = true
		if not clash:
			L.fill_rect(br, T.WALL)
			var inner := br.grow(-1)
			L.fill_rect(inner, T.FLOOR)
			var b := L.add_building(s[0], s[1], br)
			var r := _room(L, inner, false, s[4], s[1], s[0], s[0], b.id)
			var dx := inner.position.x + rng.randi_range(1, maxi(1, inner.size.x - 2))
			var out := L.room_at(Vector2i(dx, br.end.y))
			L.add_door(Vector2i(dx, br.end.y - 1), false, DS.CLOSED, out.id if out != null else -1, r.id, &"", b.id)
			rooms_rects.append(br)
		x += w2 + 2 + rng.randi_range(3, 7)
	for c3 in k.park_cells:
		_stairs(L, c3, true, 0)
	# Piliers : grille régulière, à distance des escaliers, portes, locaux et rampe.
	var avoid: Array[Rect2i] = [ramp.grow(1)]
	for rr in rooms_rects:
		avoid.append(rr.grow(2))
	for c4 in k.park_cells:
		avoid.append(Rect2i(c4 - Vector2i(2, 2), Vector2i(5, 5)))
	var step_x := Cfg.geti("mall_pillar_step_x", 6)
	var step_y := Cfg.geti("mall_pillar_step_y", 5)
	var ox := rng.randi_range(4, 5)
	var oy := rng.randi_range(4, 5)
	for py in range(oy, H - 4, step_y):
		for px in range(ox, W - 4, step_x):
			var p := Vector2i(px, py)
			var bad := false
			for a in avoid:
				if a.has_point(p):
					bad = true
					break
			if not bad and L.get_tile(p) == T.STREET:
				L.set_tile(p, T.WALL)
	L.player_spawn = k.park_cells[0] + Vector2i.UP
	return L
