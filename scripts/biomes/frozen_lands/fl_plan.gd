extends RefCounted
## Surface (étage 0) des Terres gelées : base militaire abandonnée en CROIX sur un plateau de
## glace entouré d'eau noire et de banquise, façon maquette (docs/reference/cartes_2.png,
## colonne du milieu). Format portrait, symétrie autour de la passerelle centrale nord-sud,
## variations par seed (largeurs, découpe BSP, rôles, extraction, orientation du navire…).
##   - plateau : emprise de la base dilatée de quelques cases, bord déchiqueté (neige STREET) ;
##     au-delà, l'eau (VOID) ; le bord du plateau est une rangée de murs (falaise de glace) ;
##   - nord : passerelle centrale vers une porte de la base, bloc nord de laboratoires et de
##     baraquements de part et d'autre (dont le labo cryogénique scellé = super_loot) ;
##   - centre : cour intérieure carrée autour du LABORATOIRE CIRCULAIRE aux cristaux (salle du
##     boss, ouverte sur les 4 axes), grandes ailes est/ouest (modules vus en coupe) ;
##   - sud : hangars, passerelle vers l'entrée (apparition) par une rampe d'accès ;
##   - 4 postes de garde hexagonaux aux angles, reliés par des galeries couvertes (escaliers
##     vers la neige), dômes d'observation blancs (NO, SE), HÉLIPORT au nord-ouest (extraction),
##     ponton d'évacuation au sud-est (extraction), pont d'accès au sud au-dessus de l'eau
##     (apparition au bout du pont) ;
##   - hors jeu (contrat de rendu) : navire brise-glace pris dans la glace au nord-est, épave de
##     bateau au sud-est, icebergs, crevasses, congères.
## Ne pose aucun spawn (fl_populator.gd). Déterministe, < 15 ms.

const Cfg := preload("res://scripts/biomes/frozen_lands/fl_config.gd")
const T := FloorLayout.Tile

const W := 76
const H := 112
## Passerelle centrale : colonnes SPINE_X0..SPINE_X0+3 (axe x = 38, miroir x' = 75 - x).
const SPINE_X0 := 36
const SPINE_W := 4
## Laboratoire central : centre (coordonnées continues) et rayon du sol.
const LAB_C := Vector2(38.0, 55.0)
const LAB_R := 10.5
## Plateau : centre et demi-axes de la superellipse.
const PLAT_C := Vector2(38.0, 55.0)
## Plateau : dilatation de l'emprise de la base (cases) avec bruit angulaire.
const PLAT_DIL := 9.0
## Pont d'accès sud (rangées, au-dessus de l'eau).
const BRIDGE_Y0 := 97
const BRIDGE_Y1 := 108

const KEY_LAB := &"fl_key_lab"
const KEY_BUNKER := &"fl_key_bunker"
const MIN_ROOM := 6

const ROLE_NAMES := {
	&"crystal_lab": "Laboratoire des cristaux", &"yard": "Cour intérieure", &"walkway": "Passerelle",
	&"gate": "Porte nord", &"heliport": "Héliport", &"dock": "Ponton d'évacuation",
	&"ramp": "Rampe d'accès", &"snow": "Plateau de glace",
	&"lab": "Laboratoire", &"cryo_vault": "Laboratoire cryogénique scellé", &"barracks": "Baraquement",
	&"mess_hall": "Réfectoire", &"infirmary": "Infirmerie", &"armory": "Armurerie du bunker",
	&"bunker": "Bunker", &"command": "Poste de commandement", &"radio": "Salle radio",
	&"storage": "Entrepôt", &"generator": "Salle des générateurs", &"workshop": "Atelier",
	&"hangar": "Hangar", &"garage": "Garage des autoneiges", &"guard_tower": "Poste de garde",
	&"observatory": "Dôme d'observation", &"closet": "Réduit",
}


class Mod:
	var rect: Rect2i                 ## Murs compris
	var inner: Rect2i                ## Sol
	var role: StringName = &""
	var type: StringName = FloorLayout.ROOM_COMBAT
	var name: String = ""
	var slot: String = ""
	var roof: bool = false           ## Module fermé (toit qui s'efface quand on entre)
	var round_c: Vector2 = Vector2.ZERO
	var round_r: float = 0.0         ## > 0 : salle circulaire
	var key: StringName = &""
	var open: bool = false           ## Reliée par des ouvertures (pas de porte)
	var corridor: bool = false
	var outdoor: bool = false
	var arch: StringName = &"fl_bunker"
	var room: FloorLayout.Room = null
	var building: FloorLayout.Building = null
	var unit: int = -1


class Result:
	var layout: FloorLayout
	var mods: Array[Mod] = []


static func mirror_rect(r: Rect2i) -> Rect2i:
	return Rect2i(W - r.end.x, r.position.y, r.size.x, r.size.y)


static func mirror_cell(c: Vector2i) -> Vector2i:
	return Vector2i(W - 1 - c.x, c.y)


static func build(seed_value: int) -> Result:
	var attempts := Cfg.geti("plan_attempts", 12)
	for attempt in attempts:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "fl_plan", attempt])
		var res := _try(rng, attempt >= attempts / 2)
		if res != null:
			return res
	push_error("FrozenLands: plan impossible à générer (seed %d)" % seed_value)
	return null


# --- Plateau ------------------------------------------------------------------------------

## Bruit déterministe [0, 1) d'une case.
static func hash01(x: int, y: int, s: int) -> float:
	var h := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65536.0


## Bruit lisse (valeur interpolée) pour déformer le bord du plateau.
static func _smooth_noise(x: float, y: float, s: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - float(ix)
	var fy := y - float(iy)
	var a := hash01(ix, iy, s)
	var b := hash01(ix + 1, iy, s)
	var c := hash01(ix, iy + 1, s)
	var d := hash01(ix + 1, iy + 1, s)
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(a, b, u), lerpf(c, d, u), v)


## Masque du plateau de glace : emprise de la base (murs et sols) dilatée de PLAT_DIL cases, bord
## déchiqueté (bruit angulaire par direction, facettes anguleuses : distance de Tchebychev mêlée à
## la distance euclidienne), entaille au nord-est (navire pris dans la banquise) ; le pont d'accès
## sud reste au-dessus de l'eau. Renvoie un PackedByteArray (1 = neige) de W×H.
static func plateau_mask(seed_value: int, ship: Vector2, base: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(W * H)
	# distance au bord de la base (transformée de distance approchée, 2 passes)
	var INF := 9999.0
	var dist := PackedFloat32Array()
	dist.resize(W * H)
	dist.fill(INF)
	var bx0 := W
	var by0 := H
	var bx1 := 0
	var by1 := 0
	for i in W * H:
		if base[i] == 1:
			dist[i] = 0.0
			var xi := i % W
			var yi := i / W
			bx0 = mini(bx0, xi)
			bx1 = maxi(bx1, xi)
			by0 = mini(by0, yi)
			by1 = maxi(by1, yi)
	var band := int(PLAT_DIL) + 4
	var X0 := maxi(bx0 - band, 0)
	var X1 := mini(bx1 + band + 1, W)
	var Y0 := maxi(by0 - band, 0)
	var Y1 := mini(by1 + band + 1, H)
	for y in range(Y0, Y1):
		for x in range(X0, X1):
			var i := y * W + x
			if dist[i] == 0.0:
				continue
			var d := dist[i]
			if x > 0:
				d = minf(d, dist[i - 1] + 1.0)
			if y > 0:
				d = minf(d, dist[i - W] + 1.0)
				if x > 0:
					d = minf(d, dist[i - W - 1] + 1.3)
				if x < W - 1:
					d = minf(d, dist[i - W + 1] + 1.3)
			dist[i] = d
	for y in range(Y1 - 1, Y0 - 1, -1):
		for x in range(X1 - 1, X0 - 1, -1):
			var i := y * W + x
			if dist[i] == 0.0:
				continue
			var d := dist[i]
			if x < W - 1:
				d = minf(d, dist[i + 1] + 1.0)
			if y < H - 1:
				d = minf(d, dist[i + W] + 1.0)
				if x < W - 1:
					d = minf(d, dist[i + W + 1] + 1.3)
				if x > 0:
					d = minf(d, dist[i + W - 1] + 1.3)
			dist[i] = d
	var s := seed_value & 0xFFFF
	for y in range(Y0, Y1):
		for x in range(X0, X1):
			var i := y * W + x
			var d := dist[i]
			if d == 0.0:
				out[i] = 1
				continue
			if d > PLAT_DIL + 2.5:
				continue
			# bruit à facettes : cellules de 5 cases, valeur par cellule → bord anguleux
			var cx := x / 5
			var cy := y / 5
			var n := hash01(cx, cy, s) * 3.0 - 1.5
			var n2 := hash01(x / 2, y / 2, s + 7) * 1.0 - 0.5
			if d + n + n2 > PLAT_DIL or x < 3 or y < 3 or x >= W - 3 or y >= H - 3:
				continue
			var sx := (float(x) + 0.5 - ship.x) / 12.0
			var sy := (float(y) + 0.5 - ship.y) / 7.0
			if sx * sx + sy * sy < 1.0:
				continue
			if y >= BRIDGE_Y0 and absi(x - (SPINE_X0 + SPINE_W / 2)) > 5:
				continue
			out[i] = 1
	return out


# --- Construction --------------------------------------------------------------------------

static func _try(rng: RandomNumberGenerator, simple: bool) -> Result:
	var L := FloorLayout.new(Vector2i(W, H))
	L.floor_index = 0
	var res := Result.new()
	res.layout = L
	var seed_value := rng.seed
	var mods: Array[Mod] = []
	var corridors: Array[Mod] = []
	var ship := Vector2(W - 8.0 + rng.randf_range(-1.5, 1.5), 10.0 + rng.randf_range(-1.0, 1.5))
	# Paramètres symétriques (base compacte : les blocs se touchent par leurs murs).
	var nx0 := rng.randi_range(19, 20)        # bord ouest du bloc nord
	var wx0 := rng.randi_range(7, 8)          # bord ouest des ailes
	var sx0 := rng.randi_range(17, 18)        # bord ouest des hangars sud
	var tower_r := rng.randf_range(3.2, 3.6)
	var ex_pick := rng.randi_range(0, 2)      # 0 : héliport seul, 1 : ponton seul, 2 : les deux
	if Cfg.geti("all_extractions", 0) == 1:
		ex_pick = 2

	# 1. Passerelles et cour (sol intérieur) : la cour entoure le labo, les ailes la touchent.
	var spine_n := _corr(Rect2i(SPINE_X0, 15, SPINE_W, 24), "Passerelle nord", &"walkway", "v")
	var yard := _corr(Rect2i(nx0, 39, W - 2 * nx0, 32), "Cour intérieure", &"yard", "hall")
	var spine_s := _corr(Rect2i(SPINE_X0, 71, SPINE_W, 20), "Passerelle sud", &"walkway", "v")
	# Galeries vers les postes de garde (4 angles) : passerelles horizontales de 2 cases.
	var gx0 := int(ceil(8.5 + tower_r + 0.5))   # premier sol de galerie hors de l'anneau du poste
	var gal_nw := _corr(Rect2i(gx0, 23, SPINE_X0 - 1 - gx0, 2), "Galerie nord-ouest", &"walkway", "h")
	var gal_ne := _corr(Rect2i(SPINE_X0 + SPINE_W + 1, 23, SPINE_X0 - 1 - gx0, 2), "Galerie nord-est", &"walkway", "h")
	var gal_sw := _corr(Rect2i(gx0, 85, SPINE_X0 - 1 - gx0, 2), "Galerie sud-ouest", &"walkway", "h")
	var gal_se := _corr(Rect2i(SPINE_X0 + SPINE_W + 1, 85, SPINE_X0 - 1 - gx0, 2), "Galerie sud-est", &"walkway", "h")
	# Pont d'accès sud (au-dessus de l'eau) : passerelle de 4 cases.
	var bridge := _corr(Rect2i(SPINE_X0, BRIDGE_Y0 + 1, SPINE_W, BRIDGE_Y1 - BRIDGE_Y0 - 1), "Pont d'accès", &"walkway", "v")
	var corrs: Array[Mod] = [spine_n, yard, spine_s, gal_nw, gal_ne, gal_sw, gal_se, bridge]
	for c: Mod in corrs:
		corridors.append(c)
		L.fill_rect(c.rect, T.WALL)
	for c1: Mod in corrs:
		L.fill_rect(c1.inner, T.FLOOR)

	# 2. Modules rectangulaires (murs partagés avec la cour / les passerelles).
	var free: Array[Mod] = []
	for side in 2:
		var sfx := "w" if side == 0 else "e"
		var blocks := [
			[Rect2i(nx0, 14, SPINE_X0 - nx0, 9), "north_" + sfx, 999.0],
			[Rect2i(nx0, 25, SPINE_X0 - nx0, 14), "north_" + sfx, 95.0],
			[Rect2i(wx0, 39, nx0 - wx0, 32), "wing_" + sfx, 115.0],
			[Rect2i(sx0, 71, SPINE_X0 - sx0, 14), "south_" + sfx, 999.0],
		]
		for b: Array in blocks:
			var r: Rect2i = b[0]
			if side == 1:
				r = mirror_rect(r)
			var leaves: Array[Rect2i] = []
			_bsp(r, leaves, rng, 0, float(b[2]) if not simple else 9999.0)
			for lr in leaves:
				var m := _mod(lr, &"", String(b[1]))
				mods.append(m)
				free.append(m)
	# Rampe d'accès (sud) : porte de la base et couloir ouvert vers le pont (apparition au bout).
	var ramp := _mod(Rect2i(SPINE_X0 - 2, 90, SPINE_W + 4, 8), &"ramp", "ramp")
	ramp.open = true
	ramp.type = FloorLayout.ROOM_SPAWN
	ramp.arch = &"fl_gate"
	mods.append(ramp)
	# Porte nord : petit sas au bout de la passerelle nord (ouvert sur la neige).
	var gate := _mod(Rect2i(SPINE_X0 - 2, 10, SPINE_W + 4, 6), &"gate", "gate")
	gate.open = true
	gate.type = FloorLayout.ROOM_CORRIDOR
	mods.append(gate)
	# Modules ronds : laboratoire central, 4 postes de garde hexagonaux aux angles, 2 dômes.
	var lab := _round_mod(LAB_C, LAB_R, &"crystal_lab", "lab")
	lab.open = true
	lab.type = FloorLayout.ROOM_BOSS
	lab.arch = &"fl_lab"
	lab.name = String(ROLE_NAMES[&"crystal_lab"])
	var towers: Array[Mod] = []
	for tc: Array in [[Vector2(8.5, 24.0), "tower_nw", "Poste de garde nord-ouest"], [Vector2(W - 8.5, 24.0), "tower_ne", "Poste de garde nord-est"],
			[Vector2(8.5, 86.0), "tower_sw", "Poste de garde sud-ouest"], [Vector2(W - 8.5, 86.0), "tower_se", "Poste de garde sud-est"]]:
		var tm := _round_mod(tc[0], tower_r, &"guard_tower", tc[1])
		tm.roof = true
		tm.arch = &"fl_tower"
		tm.type = FloorLayout.ROOM_TRAP if rng.randf() < 0.4 else FloorLayout.ROOM_COMBAT
		tm.name = tc[2]
		towers.append(tm)
	var dome_nw := _round_mod(Vector2(24.5, 6.5), 3.3, &"observatory", "dome_nw")
	var dome_se := _round_mod(Vector2(W - 22.5, 91.5), 3.3, &"observatory", "dome_se")
	for dm: Mod in [dome_nw, dome_se]:
		dm.roof = true
		dm.arch = &"fl_dome"
		dm.type = FloorLayout.ROOM_LOOT if rng.randf() < 0.6 else FloorLayout.ROOM_REST
	dome_nw.name = "Dôme d'observation nord-ouest"
	dome_se.name = "Dôme d'observation sud-est"

	# 3. Plateau de glace : emprise de la base (ci-dessus + modules ronds + héliport + ponton)
	#    dilatée ; le pont d'accès reste au-dessus de l'eau.
	var heli := Rect2i(4, 3, 12, 11)
	var dock := Rect2i(W - 32, 89, 10, 7)
	var base := PackedByteArray()
	base.resize(W * H)
	var tl := L.tiles
	for i0 in W * H:
		if tl[i0] != T.VOID:
			base[i0] = 1
	for m0 in mods:
		if m0.round_r <= 0.0:
			continue
		for y0 in range(m0.rect.position.y, m0.rect.end.y):
			for x0 in range(m0.rect.position.x, m0.rect.end.x):
				base[y0 * W + x0] = 1
	for rr: Rect2i in [heli, dock, Rect2i(SPINE_X0 - 3, 6, SPINE_W + 6, 6), Rect2i(W - 34, 84, 18, 13), Rect2i(4, 3, 20, 14)]:
		for y1 in range(rr.position.y, rr.end.y):
			for x1 in range(rr.position.x, rr.end.x):
				base[y1 * W + x1] = 1
	for y3 in range(BRIDGE_Y0 - 2, H):
		for x3 in W:
			if absi(x3 - (SPINE_X0 + SPINE_W / 2)) > 2 or y3 >= BRIDGE_Y0:
				base[y3 * W + x3] = 0
	var pm := plateau_mask(seed_value, ship, base)
	for i2 in W * H:
		if pm[i2] == 1 and tl[i2] == T.VOID:
			tl[i2] = T.STREET
	L.tiles = tl

	# 4. Rôles.
	_assign_roles(free, rng)
	# Labo cryogénique scellé : un des modules du bloc nord (côté tiré au sort).
	var vault_side := rng.randi_range(0, 1)
	var vault: Mod = null
	for m2 in free:
		if m2.slot == ("north_w" if vault_side == 0 else "north_e") and (vault == null or m2.inner.get_area() > vault.inner.get_area()):
			vault = m2
	if vault != null:
		vault.role = &"cryo_vault"
		vault.type = FloorLayout.ROOM_SUPER_LOOT
		vault.key = KEY_LAB
		vault.roof = true
		vault.name = String(ROLE_NAMES[&"cryo_vault"])
	# Armurerie scellée : un module d'aile (bunker fermé).
	if rng.randf() < Cfg.getf("armory_chance", 1.0):
		var cands: Array[Mod] = []
		for m3 in free:
			if m3.slot.begins_with("wing_") and m3.role in [&"storage", &"bunker", &"closet", &"workshop"]:
				cands.append(m3)
		if cands.is_empty():
			for m3b in free:
				if m3b.slot.begins_with("wing_"):
					cands.append(m3b)
		if not cands.is_empty():
			var best: Mod = cands[rng.randi_range(0, cands.size() - 1)]
			best.role = &"armory"
			best.type = FloorLayout.ROOM_SUPER_LOOT
			best.key = KEY_BUNKER
			best.roof = true
			best.name = String(ROLE_NAMES[&"armory"])
	mods.append_array([lab, dome_nw, dome_se])
	mods.append_array(towers)

	# 5. Creusement.
	for m5 in mods:
		if m5.round_r > 0.0:
			continue
		L.fill_rect(m5.rect, T.WALL)
	for m6 in mods:
		if m6.round_r > 0.0:
			continue
		L.fill_rect(m6.inner, T.FLOOR if not m6.outdoor else T.STREET)
	for m7 in mods:
		if m7.round_r <= 0.0:
			continue
		L.fill_rect(m7.rect, T.WALL)
		for y2 in range(m7.inner.position.y, m7.inner.end.y):
			for x2 in range(m7.inner.position.x, m7.inner.end.x):
				if Vector2(x2 + 0.5, y2 + 0.5).distance_to(m7.round_c) <= m7.round_r:
					L.set_tile(Vector2i(x2, y2), T.FLOOR)
	# Ouvertures : labo (4 axes), hangars sud vers la passerelle sud (grande baie), rampe et
	# porte nord vers les passerelles, porte nord vers la neige, rampe vers la neige.
	_lab_openings(L, lab)
	for g0: Mod in [gal_nw, gal_ne, gal_sw, gal_se]:
		var xw := SPINE_X0 - 1 if g0.inner.position.x < W / 2 else SPINE_X0 + SPINE_W
		for yg in range(g0.inner.position.y, g0.inner.end.y):
			L.set_tile(Vector2i(xw, yg), T.FLOOR)
	for x3 in range(SPINE_X0, SPINE_X0 + SPINE_W):
		L.set_tile(Vector2i(x3, 90), T.FLOOR)        # passerelle sud → rampe
		L.set_tile(Vector2i(x3, 15), T.FLOOR)        # porte nord → passerelle nord
		L.set_tile(Vector2i(x3, 39), T.FLOOR)        # passerelle nord → cour
		L.set_tile(Vector2i(x3, 71), T.FLOOR)        # cour → passerelle sud
		L.set_tile(Vector2i(x3, BRIDGE_Y0), T.FLOOR) # rampe → pont
	for x4 in range(SPINE_X0 + 1, SPINE_X0 + SPINE_W - 1):
		L.set_tile(Vector2i(x4, 10), T.STREET)       # porte nord → neige
	# Escaliers extérieurs : chaque galerie s'ouvre sur la neige (côté opposé à la base nord/sud).
	for g2: Mod in [gal_nw, gal_ne, gal_sw, gal_se]:
		# Tronçon hors des blocs (entre le poste de garde et la base) : escaliers de chaque côté.
		var left2 := g2.inner.position.x < W / 2
		var xm := (g2.inner.position.x + nx0) / 2 if left2 else (g2.inner.end.x + W - nx0) / 2
		for ys: int in [g2.rect.position.y, g2.rect.end.y - 1]:
			var beyond := ys - 1 if ys == g2.rect.position.y else ys + 1
			for xx in range(xm - 1, xm + 1):
				if L.get_tile(Vector2i(xx, beyond)) == T.STREET:
					L.set_tile(Vector2i(xx, ys), T.STREET)
	# Rampe : escaliers latéraux vers la neige.
	for xs: int in [ramp.rect.position.x, ramp.rect.end.x - 1]:
		var beyond2 := xs - 1 if xs == ramp.rect.position.x else xs + 1
		for yy3 in range(ramp.inner.position.y + 1, ramp.inner.position.y + 3):
			if L.get_tile(Vector2i(beyond2, yy3)) == T.STREET:
				L.set_tile(Vector2i(xs, yy3), T.STREET)
	# Baies des hangars (modules sud contre la passerelle sud, grande ouverture de 3 cases).
	for m8 in free:
		if not m8.slot.begins_with("south_"):
			continue
		if m8.role != &"hangar" and m8.role != &"garage":
			continue
		var wx := m8.rect.end.x - 1 if m8.slot == "south_w" else m8.rect.position.x
		if wx != SPINE_X0 - 1 and wx != SPINE_X0 + SPINE_W:
			continue
		m8.open = true
		var y0 := m8.inner.position.y + maxi(m8.inner.size.y / 2 - 1, 0)
		for yy in range(y0, mini(y0 + 3, m8.inner.end.y)):
			L.set_tile(Vector2i(wx, yy), T.FLOOR)
	_fence(L)

	# 6. Bâtiments (modules à toit) et salles.
	for m9 in mods:
		if m9.roof:
			m9.building = L.add_building(m9.arch, m9.name, m9.rect)
	for m10 in mods:
		var bid := m10.building.id if m10.building != null else -1
		m10.room = L.add_room(m10.inner, m10.outdoor, m10.type, m10.name, bid)
		m10.room.tags.append(String(m10.role))
		if m10.round_r > 0.0:
			m10.room.tags.append("round")
		if m10.open:
			m10.room.tags.append("open")
	for c2 in corridors:
		c2.room = L.add_room(c2.inner, false, FloorLayout.ROOM_CORRIDOR, c2.name)
		c2.room.tags.append(String(c2.role))
		c2.room.tags.append("corridor")
		c2.room.tags.append(c2.slot)
	# Extérieurs (neige) : héliport, ponton, et le plateau découpé en quatre grandes zones.
	var heli_room := L.add_room(heli, true, FloorLayout.ROOM_EXTRACTION if ex_pick != 1 else FloorLayout.ROOM_LOOT, String(ROLE_NAMES[&"heliport"]))
	heli_room.tags.append("heliport")
	heli_room.tags.append("snow")
	var dock_room := L.add_room(dock, true, FloorLayout.ROOM_EXTRACTION if ex_pick != 0 else FloorLayout.ROOM_LOOT, String(ROLE_NAMES[&"dock"]))
	dock_room.tags.append("dock")
	dock_room.tags.append("snow")
	for z: Array in [[Rect2i(0, 0, W, 39), "Plateau nord"], [Rect2i(0, 39, nx0, 48), "Plateau ouest"],
			[Rect2i(W - nx0, 39, nx0, 48), "Plateau est"], [Rect2i(nx0, 71, W - 2 * nx0, 16), "Esplanade sud"],
			[Rect2i(0, 87, W, H - 87), "Plateau sud"]]:
		var sr := L.add_room(z[0], true, FloorLayout.ROOM_CORRIDOR, z[1])
		sr.tags.append("snow")
		sr.tags.append("outdoor")
	_orphan_cells(L)

	# Îlots de neige séparés de la grande banquise (sans passer par la base) → eau, puis
	# re-clôture : aucune porte ne pourra donner sur un îlot supprimé. Un îlot est gardé s'il
	# touche (4 voisins) un sol « réseau » (passerelles, cour, rampe, porte nord).
	var net := PackedByteArray()
	net.resize(W * H)
	for cm: Mod in corridors:
		for yn in range(cm.inner.position.y, cm.inner.end.y):
			for xn in range(cm.inner.position.x, cm.inner.end.x):
				net[yn * W + xn] = 1
	for om: Mod in [ramp, gate]:
		for yn2 in range(om.inner.position.y, om.inner.end.y):
			for xn2 in range(om.inner.position.x, om.inner.end.x):
				net[yn2 * W + xn2] = 1
	var tl4 := L.tiles
	var label := PackedByteArray()   # 0 non vu, 1 vu
	label.resize(W * H)
	var stack := PackedInt32Array()
	stack.resize(W * H)
	var comp := PackedInt32Array()
	comp.resize(W * H)
	var dropped := false
	for i8 in W * H:
		if tl4[i8] != T.STREET or label[i8] == 1:
			continue
		var top := 0
		var n := 0
		var touches := false
		stack[0] = i8
		top = 1
		label[i8] = 1
		while top > 0:
			top -= 1
			var c := stack[top]
			comp[n] = c
			n += 1
			for o8: int in [c - 1, c + 1, c - W, c + W]:
				if o8 < 0 or o8 >= W * H:
					continue
				var t8 := tl4[o8]
				if t8 == T.STREET and label[o8] == 0:
					label[o8] = 1
					stack[top] = o8
					top += 1
				elif t8 == T.FLOOR and net[o8] == 1:
					touches = true
		if not touches:
			for k8 in n:
				tl4[comp[k8]] = T.VOID
			dropped = true
	if dropped:
		for y6 in range(1, H - 1):
			for x6 in range(1, W - 1):
				var i6 := y6 * W + x6
				if tl4[i6] != T.WALL:
					continue
				var near := false
				for dy6 in range(-1, 2):
					for dx6 in range(-1, 2):
						var t6 := tl4[i6 + dy6 * W + dx6]
						if t6 != T.VOID and t6 != T.WALL:
							near = true
				if not near:
					tl4[i6] = T.VOID
		L.tiles = tl4
		_fence(L)
		_orphan_cells(L)

	# 7. Portes.
	if not _connect(L, mods, rng):
		return null
	# 8. Apparition, extraction.
	L.player_spawn = Vector2i(SPINE_X0 + rng.randi_range(1, 2), bridge.inner.end.y - 2)
	var ex_rooms: Array = []
	if ex_pick != 1:
		ex_rooms.append(heli_room)
	if ex_pick != 0:
		ex_rooms.append(dock_room)
	for er: FloorLayout.Room in ex_rooms:
		# Bloc 2×2 de neige le plus proche du centre de la zone (le bord du plateau peut mordre).
		var ctr := er.rect.get_center()
		var best := Vector2i(-1, -1)
		var bd := 1 << 30
		for y5 in range(er.rect.position.y, er.rect.end.y - 1):
			for x5 in range(er.rect.position.x, er.rect.end.x - 1):
				var ok := true
				for dy in 2:
					for dx in 2:
						if L.get_tile(Vector2i(x5 + dx, y5 + dy)) != T.STREET:
							ok = false
				if not ok:
					continue
				var dd := absi(x5 + 1 - ctr.x) + absi(y5 + 1 - ctr.y)
				if dd < bd:
					bd = dd
					best = Vector2i(x5, y5)
		if best.x < 0:
			continue
		for dy2 in 2:
			for dx2 in 2:
				L.extraction_cells.append(best + Vector2i(dx2, dy2))
	if not _validate(L, mods):
		return null
	res.mods = mods
	_render_contract(L, mods, corridors, rng, ship, heli, dock, ex_pick)
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
	m.name = String(ROLE_NAMES.get(role, String(role)))
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
	m.name = String(ROLE_NAMES.get(role, String(role)))
	return m


## Découpe BSP (murs partagés), modules de MIN_ROOM cases au moins.
static func _bsp(r: Rect2i, out: Array[Rect2i], rng: RandomNumberGenerator, depth: int, target: float) -> void:
	var mn := MIN_ROOM
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


## Rôles des modules découpés : obligatoires d'abord (plus grands modules), puis tirage par zone.
## Bunkers (toit de béton) : command, radio, bunker, armory, generator, storage (parfois) ;
## modules ouverts vus en coupe : lab, barracks, mess_hall, infirmary, workshop.
static func _assign_roles(free: Array[Mod], rng: RandomNumberGenerator) -> void:
	var by_zone := {"north": [], "wing": [], "south": []}
	for m in free:
		var z := m.slot.split("_")[0]
		(by_zone[z] as Array).append(m)
	var cmp := func(a: Mod, b: Mod) -> bool:
		if a.inner.get_area() != b.inner.get_area():
			return a.inner.get_area() > b.inner.get_area()
		return a.rect.position.y * 1000 + a.rect.position.x < b.rect.position.y * 1000 + b.rect.position.x
	for z2: String in by_zone:
		(by_zone[z2] as Array).sort_custom(cmp)
	var req := {"north": [&"lab", &"barracks", &"command"], "wing": [&"barracks", &"lab", &"mess_hall", &"infirmary", &"bunker"],
		"south": [&"hangar", &"garage"]}
	var pools := {
		"north": {&"lab": 2.0, &"barracks": 1.5, &"radio": 1.0, &"storage": 1.0, &"infirmary": 0.6, &"closet": 0.5},
		"wing": {&"barracks": 1.5, &"storage": 1.5, &"workshop": 1.2, &"bunker": 1.2, &"generator": 0.8, &"lab": 0.8, &"radio": 0.5},
		"south": {&"hangar": 1.5, &"garage": 1.0, &"storage": 1.0, &"workshop": 0.8},
	}
	for z3: String in by_zone:
		var lst: Array = by_zone[z3]
		var rq: Array = (req[z3] as Array).duplicate()
		for i in range(rq.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: Variant = rq[i]
			rq[i] = rq[j]
			rq[j] = tmp
		for k in lst.size():
			var m2: Mod = lst[k]
			m2.role = rq[k] if k < rq.size() else _weighted(pools[z3], rng)
	var roofed := {&"command": true, &"radio": true, &"bunker": true, &"generator": true, &"hangar": true, &"garage": true, &"closet": true}
	var tw := Cfg.get_dict("room_type_weights", {"combat": 4.0, "loot": 3.0, "trap": 1.5, "rest": 1.0})
	for m3 in free:
		m3.roof = roofed.has(m3.role) or (m3.role == &"storage" and rng.randf() < 0.5)
		m3.arch = &"fl_hangar" if m3.role in [&"hangar", &"garage"] else &"fl_bunker"
		match m3.role:
			&"closet", &"storage", &"garage":
				m3.type = FloorLayout.ROOM_LOOT if rng.randf() < 0.7 else FloorLayout.ROOM_COMBAT
			&"mess_hall", &"workshop", &"hangar", &"command":
				m3.type = FloorLayout.ROOM_COMBAT
			&"infirmary", &"barracks":
				m3.type = FloorLayout.ROOM_REST if rng.randf() < 0.4 else FloorLayout.ROOM_LOOT
			&"generator":
				m3.type = FloorLayout.ROOM_TRAP if rng.randf() < 0.6 else FloorLayout.ROOM_COMBAT
			_:
				m3.type = StringName(_weighted(tw, rng))
	var by_role := {}
	for m4 in free:
		m4.name = String(ROLE_NAMES.get(m4.role, String(m4.role)))
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


## Ouvertures du laboratoire central : 4 axes (largeur de la passerelle) à travers l'anneau.
static func _lab_openings(L: FloorLayout, d: Mod) -> void:
	var r := d.rect
	for x in range(SPINE_X0, SPINE_X0 + SPINE_W):
		for y in range(r.position.y, r.end.y):
			if Vector2(x + 0.5, y + 0.5).distance_to(d.round_c) > d.round_r and absf(y + 0.5 - d.round_c.y) > 1.0:
				L.set_tile(Vector2i(x, y), T.FLOOR)
	for y2 in range(int(d.round_c.y) - 2, int(d.round_c.y) + 1):
		for x2 in range(r.position.x, r.end.x):
			if Vector2(x2 + 0.5, y2 + 0.5).distance_to(d.round_c) > d.round_r:
				L.set_tile(Vector2i(x2, y2), T.FLOOR)


## Toute case VOID voisine (8) d'une case marchable devient un mur (bord du plateau = falaise) ;
## bord de grille muré.
static func _fence(L: FloorLayout) -> void:
	var tiles := L.tiles
	for y in H:
		for x in W:
			var i := y * W + x
			if (x == 0 or y == 0 or x == W - 1 or y == H - 1) and tiles[i] != T.VOID:
				tiles[i] = T.WALL
	# Cases vides à côté (8) d'une case marchable → mur (lecture sur une copie).
	var src := tiles.duplicate()
	var offs: Array[int] = [-W - 1, -W, -W + 1, -1, 1, W - 1, W, W + 1]
	for y2 in range(1, H - 1):
		var row := y2 * W
		for x2 in range(1, W - 1):
			var i := row + x2
			if src[i] != T.VOID:
				continue
			for o in offs:
				var t := src[i + o]
				if t != T.VOID and t != T.WALL:
					tiles[i] = T.WALL
					break
	L.tiles = tiles


## Cases marchables hors de toute salle : agrandit la salle voisine la plus logique.
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

## Relie chaque module fermé au réseau (neige, cour, passerelles, modules ouverts = unité 0) par
## une porte dans un mur droit. Jamais dans le mur NORD d'un module à toit (le toit, rendu
## incliné vers le nord, la masquerait). Salles scellées : une seule porte verrouillée.
static func _connect(L: FloorLayout, mods: Array[Mod], rng: RandomNumberGenerator) -> bool:
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
				_cand(groups, up, dn, Vector2i(x2, y2), false)
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
			var g := _pick(groups, m4.unit, connected, by_unit, door_cells, stairs, false)
			if g.is_empty():
				continue
			_door(L, m4, g, door_cells, rng, FloorLayout.DoorState.CLOSED, &"")
			connected[m4.unit] = true
			pending.erase(m4)
			progress = true
	if not pending.is_empty():
		if OS.has_environment("FL_DBG"):
			for pm0 in pending:
				print("DBG pending ", pm0.name, " ", pm0.rect)
			var ch := {0: " ", 1: ".", 2: ":", 3: "#", 4: "D", 5: "<", 6: ">"}
			for yq in range(80, 100):
				var line := ""
				for xq in range(40, W):
					line += ch[L.get_tile(Vector2i(xq, yq))]
				print("DBG %3d %s" % [yq, line])
		return false
	for m5 in closed:
		if m5.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		var g2 := _pick(groups, m5.unit, connected, by_unit, door_cells, stairs, false)
		if g2.is_empty():
			if OS.has_environment("FL_DBG"):
				print("DBG vault no door ", m5.name, " ", m5.rect)
			return false
		_door(L, m5, g2, door_cells, rng, FloorLayout.DoorState.LOCKED, m5.key)
	var extra := Cfg.getf("extra_door_chance", 0.35)
	for m6 in closed:
		if m6.type == FloorLayout.ROOM_SUPER_LOOT or rng.randf() >= extra:
			continue
		var g3 := _pick(groups, m6.unit, connected, by_unit, door_cells, stairs, true)
		if not g3.is_empty():
			_door(L, m6, g3, door_cells, rng, FloorLayout.DoorState.CLOSED, &"")
	return true


static func _cand(groups: Dictionary, a: int, b: int, c: Vector2i, vertical: bool) -> void:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not groups.has(key):
		groups[key] = []
	(groups[key] as Array).append([c, vertical])


static func _pick(groups: Dictionary, u: int, connected: Dictionary, by_unit: Dictionary, door_cells: Dictionary, stairs: Dictionary, extra: bool) -> Dictionary:
	var best := {}
	var best_score := -1.0
	var keys: Array = groups.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 1000 + a.y < b.x * 1000 + b.y)
	var mu: Mod = by_unit[u]
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
		if mu.type == FloorLayout.ROOM_SUPER_LOOT and v > 0:
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

static func flood(L: FloorLayout, from: Vector2i, through_locked: bool) -> PackedByteArray:
	var w := L.size.x
	var tiles := L.tiles
	var n := tiles.size()
	# seen : 0 = non vu ; 1 = atteint ; 2 = infranchissable (vide, mur, porte verrouillée).
	var seen := PackedByteArray()
	seen.resize(n)
	for i in n:
		var t := tiles[i]
		if t == T.VOID or t == T.WALL:
			seen[i] = 2
	if not through_locked:
		for d in L.doors:
			if d.state == FloorLayout.DoorState.LOCKED:
				seen[d.cell.y * w + d.cell.x] = 2
	var stack := PackedInt32Array()
	stack.resize(n)
	var top := 0
	var start := from.y * w + from.x
	if seen[start] != 0:
		return seen
	stack[0] = start
	top = 1
	seen[start] = 1
	while top > 0:
		top -= 1
		var i2 := stack[top]
		var j := i2 - 1
		if j >= 0 and seen[j] == 0:
			seen[j] = 1
			stack[top] = j
			top += 1
		j = i2 + 1
		if j < n and seen[j] == 0:
			seen[j] = 1
			stack[top] = j
			top += 1
		j = i2 - w
		if j >= 0 and seen[j] == 0:
			seen[j] = 1
			stack[top] = j
			top += 1
		j = i2 + w
		if j < n and seen[j] == 0:
			seen[j] = 1
			stack[top] = j
			top += 1
	# Valeur de retour : 1 = atteint, sinon 0.
	for k in n:
		if seen[k] == 2:
			seen[k] = 0
	return seen


static func _validate(L: FloorLayout, mods: Array[Mod]) -> bool:
	if not FloorLayout.is_walkable_tile(L.get_tile(L.player_spawn)):
		return false
	var reach := flood(L, L.player_spawn, true)
	var tiles := L.tiles
	var walk := tiles.size() - tiles.count(T.VOID) - tiles.count(T.WALL)
	if reach.count(1) != walk:
		if OS.has_environment("FL_DBG"):
			var n := 0
			for i in tiles.size():
				if reach[i] == 0 and tiles[i] != T.VOID and tiles[i] != T.WALL and n < 6:
					var r := L.room_at(Vector2i(i % W, i / W))
					print("DBG unreachable ", Vector2i(i % W, i / W), " ", r.name if r else "?")
					n += 1
		return false
	var open_reach := flood(L, L.player_spawn, false)
	for m in mods:
		if m.type != FloorLayout.ROOM_SUPER_LOOT:
			continue
		for y in range(m.inner.position.y, m.inner.end.y):
			for x in range(m.inner.position.x, m.inner.end.x):
				if open_reach[y * W + x] != 0:
					return false
	if L.extraction_cells.is_empty():
		return false
	return true


# --- Contrat de rendu (Blender) -----------------------------------------------------------------

## Métadonnée « render_contract » : modules (rect murs compris, rôle, toit, rond), passerelles et
## cour, laboratoire central, héliport, ponton, navire, épave, icebergs, crevasses, congères.
static func _render_contract(L: FloorLayout, mods: Array[Mod], corridors: Array[Mod], rng: RandomNumberGenerator,
		ship: Vector2, heli: Rect2i, dock: Rect2i, ex_pick: int) -> void:
	var ml: Array = []
	for m in mods:
		var e := {"room": m.room.id, "rect": m.rect, "inner": m.inner, "role": String(m.role), "slot": m.slot,
			"roof": m.roof, "open": m.open, "type": String(m.type),
			"building": m.building.id if m.building != null else -1, "arch": String(m.arch)}
		if m.round_r > 0.0:
			e["round"] = [m.round_c.x, m.round_c.y, m.round_r]
		ml.append(e)
	var cl: Array = []
	for c in corridors:
		if c.room == null:
			continue
		cl.append({"room": c.room.id, "inner": c.inner, "role": String(c.role), "slot": c.slot})
	var decor: Array = []
	decor.append({"kind": "ship", "pos": [ship.x, ship.y], "size": 20.0, "rot": rng.randf_range(-42.0, -28.0)})
	decor.append({"kind": "wreck", "pos": [W - 6.5 + rng.randf_range(-1.0, 1.0), 103.0 + rng.randf_range(-1.0, 1.5)], "size": 5.0, "rot": rng.randf_range(10.0, 40.0)})
	# Icebergs dans l'eau (loin du plateau : cases VOID à ≥ 3 cases d'une case non vide).
	# Icebergs : dans l'eau (cases VOID à ≥ 2 cases du plateau), parfois hors grille (la marge du
	# rendu les montre), jamais sous le navire.
	var tries := 0
	var tl2 := L.tiles
	var n_ice := rng.randi_range(6, 9)
	var placed: Array = []
	while placed.size() < n_ice and tries < 600:
		tries += 1
		var p := Vector2i(rng.randi_range(-3, W + 2), rng.randi_range(-3, H + 2))
		var ok := true
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var q := p + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= W or q.y >= H:
					continue
				if tl2[q.y * W + q.x] != T.VOID:
					ok = false
					break
			if not ok:
				break
		if Vector2(p).distance_to(ship) < 14.0:
			ok = false
		for q2: Vector2i in placed:
			if q2.distance_to(p) < 6.0:
				ok = false
		if not ok:
			continue
		placed.append(p)
		decor.append({"kind": "iceberg", "pos": [p.x + 0.5, p.y + 0.5], "size": rng.randf_range(2.5, 5.0), "rot": rng.randf_range(0.0, 360.0)})
	# Crevasses et congères sur la neige (décoratives, hors des abords du jeu).
	var n_cr := rng.randi_range(3, 5)
	tries = 0
	while n_cr > 0 and tries < 300:
		tries += 1
		var p2 := Vector2i(rng.randi_range(3, W - 4), rng.randi_range(3, H - 4))
		if tl2[p2.y * W + p2.x] != T.STREET:
			continue
		var far := true
		for dy2 in range(-2, 3):
			var row2 := (p2.y + dy2) * W + p2.x
			for dx2 in range(-2, 3):
				if tl2[row2 + dx2] != T.STREET:
					far = false
					break
			if not far:
				break
		if far:
			var rr := L.room_at(p2)
			far = rr != null and rr.tags.has("outdoor")
		if not far:
			continue
		n_cr -= 1
		decor.append({"kind": "crevasse", "pos": [p2.x + 0.5, p2.y + 0.5], "size": rng.randf_range(3.0, 6.0), "rot": rng.randf_range(0.0, 180.0)})
	L.set_meta(&"render_contract", {"kind": "fl_base", "modules": ml, "corridors": cl,
		"lab": [LAB_C.x, LAB_C.y, LAB_R], "decor": decor, "spine": [SPINE_X0, SPINE_W],
		"heliport": heli, "dock": dock, "extractions": ex_pick, "ship": [ship.x, ship.y],
		"bridge": [SPINE_X0, BRIDGE_Y0, SPINE_W, BRIDGE_Y1 - BRIDGE_Y0]})

