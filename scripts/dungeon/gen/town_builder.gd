extends RefCounted
## Rez-de-chaussée (0) d'un village Far West et étage (1) des bâtiments à étage.
##
## Étage 0 : village organique au format portrait (maquette docs/reference/farwest_maquette_carte.png),
## voir build(). Les intérieurs ne sont accessibles que par des portes.
## Étage 1 : uniquement les étages des bâtiments qui en ont (saloon, hôtel),
## même emprise ; le reste de la grille est VOID.
##
## Toutes les salles reçoivent dans `tags[0]` leur rôle d'ameublement
## (ex. "saloon_hall", "street", "backyard") ; tags[1] = archétype ou "outdoor".

const Cfg := preload("res://scripts/dungeon/gen/gen_config.gd")
const Tpl := preload("res://scripts/dungeon/gen/building_templates.gd")
const T := FloorLayout.Tile


## Résultat de la génération de l'étage 0 (structure, sans spawns).
class TownResult:
	var layout: FloorLayout
	## Bâtiments à étage : { building_id, plan (Plan), origin (Vector2i), flip_x, flip_y, transpose }.
	var upper_specs: Array[Dictionary] = []
	## Cases des escaliers descendant vers la mine.
	var mine_stairs: Array[Vector2i] = []


## Grands décors (landmarks, posés sur des cases WALL) : pièce d'atlas → emprise (cases).
## Voir FloorLayout.landmark_spawns. Les pièces « lm_* » sont dans l'atlas des décors Far West.
const LANDMARKS := {
	&"lm_rock_a": Vector2i(2, 2), &"lm_rock_b": Vector2i(3, 2), &"lm_rock_c": Vector2i(3, 3),
	&"lm_rock_d": Vector2i(4, 3), &"lm_rock_e": Vector2i(2, 3), &"lm_mesa": Vector2i(5, 4),
	&"lm_loco": Vector2i(5, 2), &"lm_tender": Vector2i(3, 2), &"lm_boxcar": Vector2i(4, 2),
	&"lm_boxcar_b": Vector2i(4, 2), &"lm_tankcar": Vector2i(4, 2), &"lm_flatcar": Vector2i(4, 2),
	&"lm_caboose": Vector2i(3, 2), &"lm_windmill": Vector2i(2, 2), &"prop_water_tower": Vector2i(2, 2),
	&"lm_well": Vector2i(2, 2),
}
const WAGONS: Array[StringName] = [&"lm_boxcar", &"lm_boxcar_b", &"lm_tankcar", &"lm_boxcar", &"lm_flatcar", &"lm_boxcar_b"]
## Pièces des formations rocheuses par type (la première est la pièce « mère »).
const ROCK_SETS := {
	&"mesa": [&"lm_mesa", &"lm_rock_d", &"lm_rock_c", &"lm_rock_b", &"lm_rock_c", &"lm_rock_e", &"lm_rock_a"],
	&"ledge": [&"lm_rock_d", &"lm_rock_b", &"lm_rock_c", &"lm_rock_b", &"lm_rock_e", &"lm_rock_a"],
	&"scree": [&"lm_rock_a", &"lm_rock_b", &"lm_rock_a", &"lm_rock_e"],
}
const ROCK_HEIGHT := {&"mesa": [3.0, 4.2], &"ledge": [2.0, 2.8], &"scree": [1.0, 1.6]}
const SHACK_NAMES := ["Cabane du trappeur", "Maison abandonnée", "Atelier du forgeron",
	"Bureau du télégraphe", "Maison du croque-mort", "Cabane du prospecteur", "Barbier", "Maison du pasteur",
	"Cabane du charpentier", "Cordonnerie", "Maison du docteur", "Blanchisserie", "Maison de la veuve",
	"Armurier", "Sellerie", "Maison du maréchal-ferrant", "Bureau de l'essayeur", "Pension", "Tonnellerie",
	"Maison du maire", "Bureau de poste", "Fumoir", "Boulangerie", "Maison du juge"]
const SHED_NAMES := ["Appentis", "Remise", "Latrines", "Cabane à outils", "Bûcher", "Poulailler", "Resserre", "Cellier"]
const DIRS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]

## Points d'attraction des bâtiments importants (coordonnées normalisées, avant miroir) :
## y < 0.6 = au nord de la voie ferrée, y > 0.66 = au sud.
const ATTRACT := {
	&"saloon": Vector2(0.7, 0.28), &"bank": Vector2(0.5, 0.11), &"sheriff": Vector2(0.72, 0.47),
	&"hotel": Vector2(0.26, 0.28), &"store": Vector2(0.22, 0.47), &"stable": Vector2(0.3, 0.74),
	&"church": Vector2(0.27, 0.12), &"mine": Vector2(0.78, 0.86),
}
## Groupes de maisons (coordonnées normalisées, avant miroir) : 2 à 3 maisons par groupe.
const HOUSE_GROUPS: Array[Vector2] = [Vector2(0.2, 0.2), Vector2(0.36, 0.1), Vector2(0.72, 0.13), Vector2(0.84, 0.3),
	Vector2(0.18, 0.46), Vector2(0.36, 0.53), Vector2(0.82, 0.55), Vector2(0.52, 0.22), Vector2(0.58, 0.86),
	Vector2(0.72, 0.72), Vector2(0.62, 0.55), Vector2(0.38, 0.4)]


## État de construction partagé entre les étapes.
class Ctx:
	var L: FloorLayout
	var rng: RandomNumberGenerator
	var W: int
	var H: int
	var mirror: bool
	## Cases prises par une structure (bâtiment, cour, rocher, wagon, palissade, repère…).
	var occ: PackedByteArray
	## Cases qui doivent rester du sable libre (rues, porches, voie ferrée, clairières).
	var keep: PackedByteArray
	var rail_y: int
	var spur_x: int
	var plaza: Vector2i
	var frontage: Array[Vector2i] = []
	var res: TownResult
	var want_upper: bool
	## Bâtiment → façade (direction vers la rue).
	var facing: Dictionary = {}
	## Emprises des cours / enclos : {rect, inner, role, gate}.
	var yards: Array[Dictionary] = []
	## Bâtiments dont la cour a déjà été tentée.
	var yard_tried: Dictionary = {}

	func i(c: Vector2i) -> int:
		return c.y * W + c.x

	func inb(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H

	func is_occ(c: Vector2i) -> bool:
		return not inb(c) or occ[c.y * W + c.x] == 1

	func is_keep(c: Vector2i) -> bool:
		return inb(c) and keep[c.y * W + c.x] == 1

	## Coordonnées normalisées → case (avec miroir horizontal).
	func at(u: Vector2) -> Vector2i:
		var x := (1.0 - u.x) if mirror else u.x
		return Vector2i(clampi(int(round(x * W)), 2, W - 3), clampi(int(round(u.y * H)), 2, H - 3))


## Rez-de-chaussée : village organique (maquette docs/reference/farwest_maquette_carte.png).
## - format portrait, sable praticable découpé en grandes zones extérieures (salles « outdoor ») ;
## - rues de terre battue sinueuses (FloorLayout.paths) : place centrale avec le puits, grand-rue
##   nord-sud, rue transversale, ruelles ; au sud de la voie, chemin le long de la voie secondaire ;
## - bâtiments orientés vers la rue (porche entre la façade et la rue), en groupes, petites maisons
##   en majorité, 4 à 6 bâtiments importants, appentis collés, cours clôturées, enclos ;
## - voie ferrée horizontale sur toute la largeur et train à l'arrêt (passages entre wagons) ;
## - formations rocheuses massives dans les coins, sur les bords et quelques-unes au milieu ;
## - éolienne et château d'eau dans les coins du nord.
## Connectivité garantie par construction : chaque obstacle hors bâtiment est posé seulement si les
## cases libres de l'anneau qui l'entoure restent d'un seul tenant (voir _ring_ok).
## Apparition au sud (arrivée par la voie secondaire), extraction au nord.
static func build(seed_value: int, world: WorldData) -> TownResult:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "village"])
	var x := Ctx.new()
	x.rng = rng
	x.want_upper = world.floors_max >= 1
	var want_mine := world.floors_min <= -1
	x.W = Cfg.range_i(rng, "village_w_min", "village_w_max", 54, 58)
	x.H = Cfg.range_i(rng, "village_h_min", "village_h_max", 94, 100)
	x.mirror = rng.randf() < 0.5
	var W := x.W
	var H := x.H
	var L := FloorLayout.new(Vector2i(W, H))
	L.floor_index = 0
	x.L = L
	x.res = TownResult.new()
	x.res.layout = L
	x.occ = PackedByteArray()
	x.occ.resize(W * H)
	x.keep = PackedByteArray()
	x.keep.resize(W * H)
	L.fill_rect(Rect2i(1, 1, W - 2, H - 2), T.STREET)
	# Bord de carte : mur invisible (le désert continue hors carte, rendu par le constructeur).
	for xx in W:
		L.set_tile(Vector2i(xx, 0), T.WALL)
		L.set_tile(Vector2i(xx, H - 1), T.WALL)
	for yy in H:
		L.set_tile(Vector2i(0, yy), T.WALL)
		L.set_tile(Vector2i(W - 1, yy), T.WALL)
	_mark(x.occ, W, H, Rect2i(0, 0, W, 1))
	_mark(x.occ, W, H, Rect2i(0, H - 1, W, 1))
	_mark(x.occ, W, H, Rect2i(0, 0, 1, H))
	_mark(x.occ, W, H, Rect2i(W - 1, 0, 1, H))

	x.rail_y = int(round(float(H) * Cfg.getf("village_rail_ratio", 0.63))) + rng.randi_range(-1, 1)
	x.spur_x = x.at(Vector2(0.45 + rng.randf_range(-0.05, 0.05), 0.0)).x
	x.plaza = x.at(Vector2(0.5 + rng.randf_range(-0.04, 0.04), 0.37 + rng.randf_range(-0.03, 0.03)))

	# --- Zones extérieures (salles) : créées d'abord (les portes y sont rattachées) ---------
	var zones := _zones(x)

	# --- Squelette : voie ferrée, rues, place, clairières --------------------------------
	var spawn := Vector2i(x.spur_x + 2, H - 3)
	var ex := x.at(Vector2(0.86, 0.0))
	ex.y = 3
	_skeleton(x, spawn, ex)

	# --- Train à l'arrêt ----------------------------------------------------------------
	_railway(x)

	# --- Puits (place), éolienne et château d'eau (coins du nord) --------------------------
	var wr := Rect2i(x.plaza - Vector2i(1, 1), Vector2i(2, 2))
	_landmark(x, &"lm_well", wr)
	L.landmarks.append({"kind": &"well", "cell": Vector2i(wr.position.x, wr.end.y - 1), "rect": wr})
	for p0 in _cells(wr):
		L.paths.erase(p0)
	var mill := _place_free(x, &"lm_windmill", x.at(Vector2(0.1, 0.05)), 2)
	if mill.size.x > 0:
		L.landmarks.append({"kind": &"windmill", "cell": Vector2i(mill.position.x, mill.end.y - 1), "rect": mill})
	var tower := _place_free(x, &"prop_water_tower", x.at(Vector2(0.92, 0.09)), 2)
	if tower.size.x > 0:
		L.landmarks.append({"kind": &"water_tower", "cell": Vector2i(tower.position.x, tower.end.y - 1), "rect": tower})

	# --- Formations rocheuses des coins et des bords (avant les bâtiments) ------------------
	_edge_rocks(x)

	# --- Bâtiments -----------------------------------------------------------------------
	_frontage(x)
	_buildings(x, world, want_mine)

	# --- Cours clôturées, enclos, palissades le long de la voie ----------------------------
	_yards(x)
	_corrals(x)
	_rail_fences(x)

	# --- Formations rocheuses au milieu (couverts) -------------------------------------------
	_inner_rocks(x)

	# --- Salles des cours / enclos, portes rattachées à la bonne salle extérieure -----------
	for y: Dictionary in x.yards:
		var yr := L.add_room(y["inner"], true, FloorLayout.ROOM_LOOT if rng.randf() < 0.5 else FloorLayout.ROOM_COMBAT,
			"Enclos" if y["role"] == &"corral" else "Cour")
		yr.tags = PackedStringArray([String(y["role"]), "outdoor"])
	for d in L.doors:
		for side: int in 2:
			var rid := d.room_a if side == 0 else d.room_b
			var r := L.get_room(rid)
			if r == null or not r.outdoor:
				continue
			for n: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var o := L.room_at(d.cell + n)
				if o != null and o.outdoor and L.get_tile(d.cell + n) == T.STREET:
					if side == 0:
						d.room_a = o.id
					else:
						d.room_b = o.id
					break

	# Terre battue : uniquement sur des cases praticables (une rue peut buter contre le train).
	for pc: Vector2i in L.paths.keys():
		if L.get_tile(pc) != T.STREET:
			L.paths.erase(pc)

	# --- Spawn et extraction ---------------------------------------------------------------
	L.player_spawn = spawn
	for c2: Vector2i in [ex, ex + Vector2i.RIGHT, ex + Vector2i.DOWN, ex + Vector2i.ONE]:
		L.extraction_cells.append(c2)
	var exr := L.room_at(ex)
	exr.type = FloorLayout.ROOM_EXTRACTION
	exr.tags = PackedStringArray(["town_exit", "outdoor"])
	exr.name = "Relais de la diligence"
	var sp := L.room_at(spawn)
	sp.type = FloorLayout.ROOM_SPAWN
	sp.tags = PackedStringArray(["town_entry", "outdoor"])
	sp.name = "Arrivée de la voie"
	# Seconde extraction possible : bout de la voie ferrée côté opposé à la locomotive.
	if rng.randf() < Cfg.getf("second_extraction_chance", 0.5):
		var cx := W - 4 if not x.mirror else 2
		var cc := Vector2i(cx, x.rail_y + 2)
		var ok := true
		for d2: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
			if L.get_tile(cc + d2) != T.STREET or x.is_occ(cc + d2):
				ok = false
		if ok:
			for d3: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
				L.extraction_cells.append(cc + d3)
			var er := L.room_at(cc)
			if er != null and er.type != FloorLayout.ROOM_SPAWN:
				er.type = FloorLayout.ROOM_EXTRACTION
	return x.res


# --- Grille ------------------------------------------------------------------------------

static func _mark(g: PackedByteArray, W: int, H: int, r: Rect2i) -> void:
	for y in range(maxi(r.position.y, 0), mini(r.end.y, H)):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, W)):
			g[y * W + x] = 1


static func _cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


## Rectangle libre : aucune structure à moins de `margin` cases, rien dans `keep`, dans la carte
## (à `border` cases du bord au moins).
static func _free(x: Ctx, r: Rect2i, margin: int, border: int = 1) -> bool:
	var W := x.W
	var H := x.H
	if r.position.x < border or r.position.y < border or r.end.x > W - border or r.end.y > H - border:
		return false
	var occ := x.occ
	var keep := x.keep
	# Rejet rapide : centre et coins de l'emprise élargie.
	var g := r.grow(margin).intersection(Rect2i(0, 0, W, H))
	var c := r.get_center()
	if occ[c.y * W + c.x] == 1 or keep[c.y * W + c.x] == 1:
		return false
	if occ[g.position.y * W + g.position.x] == 1 or occ[(g.end.y - 1) * W + g.end.x - 1] == 1:
		return false
	# Une seule passe : structure interdite dans l'emprise élargie, rue / abords interdits dedans.
	var x0 := r.position.x
	var x1 := r.end.x
	var y0 := r.position.y
	var y1 := r.end.y
	for y in range(g.position.y, g.end.y):
		var row := y * W
		var inside_y := y >= y0 and y < y1
		for xx in range(g.position.x, g.end.x):
			if occ[row + xx] == 1:
				return false
			if inside_y and xx >= x0 and xx < x1 and keep[row + xx] == 1:
				return false
	return true


## Anneau autour de `r` (ordre circulaire, cases consécutives voisines).
static func _ring(r: Rect2i) -> Array[Vector2i]:
	var g := r.grow(1)
	var ring: Array[Vector2i] = []
	for xx in range(g.position.x, g.end.x):
		ring.append(Vector2i(xx, g.position.y))
	for y in range(g.position.y + 1, g.end.y):
		ring.append(Vector2i(g.end.x - 1, y))
	for x2 in range(g.end.x - 2, g.position.x - 1, -1):
		ring.append(Vector2i(x2, g.end.y - 1))
	for y2 in range(g.end.y - 2, g.position.y, -1):
		ring.append(Vector2i(g.position.x, y2))
	return ring


## Occuper `r` préserve la connexité du sable libre : les cases libres de l'anneau qui l'entoure
## forment un seul arc (on peut toujours contourner l'obstacle).
static func _ring_ok(x: Ctx, r: Rect2i) -> bool:
	var ring := _ring(r)
	var n := ring.size()
	var free := PackedByteArray()
	free.resize(n)
	var any := false
	for k in n:
		var c := ring[k]
		if not x.is_occ(c) and not r.has_point(c):
			free[k] = 1
			any = true
	if not any:
		return false
	var arcs := 0
	for k2 in n:
		if free[k2] == 1 and free[(k2 + n - 1) % n] == 0:
			arcs += 1
	return arcs <= 1


# --- Zones extérieures --------------------------------------------------------------------

## Découpe la carte en zones extérieures : trois colonnes ; au nord trois rangées, la bande de la
## voie ferrée, au sud deux rangées. Les rôles sont fixés plus tard (place, entrée, sortie).
static func _zones(x: Ctx) -> Array[FloorLayout.Room]:
	var L := x.L
	var W := x.W
	var H := x.H
	var ry := x.rail_y
	var xs: Array[int] = [1, W / 3 + x.rng.randi_range(-1, 1), (2 * W) / 3 + x.rng.randi_range(-1, 1), W - 1]
	var north_end := ry - 1
	var ya := 1 + (north_end - 1) / 3 + x.rng.randi_range(-1, 1)
	var yb := 1 + (2 * (north_end - 1)) / 3 + x.rng.randi_range(-1, 1)
	var ys_n: Array[int] = [1, ya, yb, north_end]
	var south_start := ry + 3
	var yc := south_start + (H - 1 - south_start) / 2 + x.rng.randi_range(-1, 1)
	var ys_s: Array[int] = [south_start, yc, H - 1]
	var names_n := [["Collines du nord-ouest", "Haut de la grand-rue", "Château d'eau"],
		["Rue de l'ouest", "Place du puits", "Rue de l'est"],
		["Ruelles de l'ouest", "Bas de la grand-rue", "Ruelles de l'est"]]
	var names_s := [["Dépôt", "Voie secondaire", "Enclos de l'est"], ["Collines du sud-ouest", "Arrivée de la voie", "Collines du sud-est"]]
	var out: Array[FloorLayout.Room] = []
	for row in 3:
		for col in 3:
			var r := Rect2i(xs[col], ys_n[row], xs[col + 1] - xs[col], ys_n[row + 1] - ys_n[row])
			var nm: String = names_n[row][col]
			if x.mirror:
				nm = names_n[row][2 - col]
			var z := L.add_room(r, true, FloorLayout.ROOM_COMBAT, nm)
			z.tags = PackedStringArray(["street" if col == 1 or row == 1 else "desert", "outdoor"])
			out.append(z)
	var rail := L.add_room(Rect2i(1, ry - 1, W - 2, 4), true, FloorLayout.ROOM_COMBAT, "Voie ferrée")
	rail.tags = PackedStringArray(["railway", "outdoor"])
	out.append(rail)
	for row2 in 2:
		for col2 in 3:
			var r2 := Rect2i(xs[col2], ys_s[row2], xs[col2 + 1] - xs[col2], ys_s[row2 + 1] - ys_s[row2])
			var nm2: String = names_s[row2][col2] if not x.mirror else names_s[row2][2 - col2]
			var z2 := L.add_room(r2, true, FloorLayout.ROOM_COMBAT, nm2)
			z2.tags = PackedStringArray(["desert" if row2 == 1 else "street", "outdoor"])
			out.append(z2)
	for z3 in out:
		if z3.tags[0] != "railway" and x.rng.randf() < 0.35:
			z3.type = FloorLayout.ROOM_LOOT
	return out


# --- Rues (terre battue) -----------------------------------------------------------------

## Polyligne sinueuse de `a` à `b` : un point toutes les `step` cases le long de l'axe principal,
## décalage latéral qui varie d'au plus une case entre deux points (borné à ±amp).
static func _wiggle(rng: RandomNumberGenerator, a: Vector2i, b: Vector2i, step: int, amp: int) -> Array[Vector2i]:
	var pts: Array[Vector2i] = [a]
	var horiz := absi(b.x - a.x) >= absi(b.y - a.y)
	var length := absi(b.x - a.x) if horiz else absi(b.y - a.y)
	var n := maxi(1, length / step)
	var off := 0
	for k in range(1, n):
		var t := float(k) / float(n)
		off = clampi(off + rng.randi_range(-1, 1), -amp, amp)
		var p := Vector2(a).lerp(Vector2(b), t)
		var q := Vector2i(int(round(p.x)), int(round(p.y)))
		if horiz:
			q.y += off
		else:
			q.x += off
		pts.append(q)
	pts.append(b)
	return pts


## Trace une rue (pinceau carré de `width` cases) le long d'une polyligne.
static func _road(x: Ctx, pts: Array[Vector2i], width: int) -> void:
	for k in range(pts.size() - 1):
		var a := pts[k]
		var b := pts[k + 1]
		var steps := maxi(absi(b.x - a.x), absi(b.y - a.y))
		for s in steps + 1:
			var t := float(s) / float(maxi(steps, 1))
			var c := Vector2i(int(round(lerpf(a.x, b.x, t))), int(round(lerpf(a.y, b.y, t))))
			_brush(x, c, width)


static func _brush(x: Ctx, c: Vector2i, width: int) -> void:
	var lo := -(width - 1) / 2
	for dy in range(lo, lo + width):
		for dx in range(lo, lo + width):
			var p := c + Vector2i(dx, dy)
			if p.x < 1 or p.y < 1 or p.x > x.W - 2 or p.y > x.H - 2:
				continue
			x.keep[x.i(p)] = 1
			x.L.paths[p] = true


static func _disc(x: Ctx, c: Vector2i, rad: float, as_path: bool) -> void:
	var r := int(ceil(rad))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dy).length() > rad:
				continue
			var p := c + Vector2i(dx, dy)
			if p.x < 1 or p.y < 1 or p.x > x.W - 2 or p.y > x.H - 2:
				continue
			x.keep[x.i(p)] = 1
			if as_path:
				x.L.paths[p] = true


## Squelette du village : bande de la voie ferrée, place du puits, grand-rue, rue transversale,
## rue du nord, ruelles est / ouest, chemin de la voie secondaire, chemin du sud, clairières du
## spawn et de l'extraction (reliées aux rues).
static func _skeleton(x: Ctx, spawn: Vector2i, ex: Vector2i) -> void:
	var rng := x.rng
	var W := x.W
	var H := x.H
	var ry := x.rail_y
	# Bande de la voie : une rangée libre au-dessus et au-dessous du train.
	_mark(x.keep, W, H, Rect2i(1, ry - 1, W - 2, 4))
	x.L.rails.append({"kind": &"main", "points": [Vector2i(0, ry), Vector2i(W - 1, ry)], "width": 2})
	x.L.rails.append({"kind": &"spur", "points": [Vector2i(x.spur_x, ry + 2), Vector2i(x.spur_x, H - 1)], "width": 1})
	# Place du puits.
	_disc(x, x.plaza, float(Cfg.geti("village_plaza_radius", 5)) + rng.randf_range(-0.4, 0.6), true)
	var wn := Cfg.geti("village_road_width", 3)
	var north_y := int(round(H * 0.155)) + rng.randi_range(-1, 1)
	# Grand-rue nord-sud : du nord du village à la voie ferrée, par la place.
	var top := Vector2i(x.plaza.x + rng.randi_range(-2, 2), north_y)
	_road(x, _wiggle(rng, top, x.plaza, 5, 1), wn)
	_road(x, _wiggle(rng, x.plaza, Vector2i(x.plaza.x + rng.randi_range(-3, 3), ry - 1), 5, 2), wn)
	# Rue transversale (ouest-est) un peu au sud de la place.
	var cy := x.plaza.y + rng.randi_range(1, 4)
	var west := Vector2i(4, cy + rng.randi_range(-3, 3))
	var east := Vector2i(W - 5, cy + rng.randi_range(-3, 3))
	_road(x, _wiggle(rng, west, Vector2i(x.plaza.x, cy), 6, 2), wn - 1)
	_road(x, _wiggle(rng, Vector2i(x.plaza.x, cy), east, 6, 2), wn - 1)
	# Rue du nord (devant la rangée nord) et ruelles qui descendent à l'ouest et à l'est.
	var nw := Vector2i(int(W * 0.2), north_y + rng.randi_range(-1, 1))
	var ne := Vector2i(int(W * 0.8), north_y + rng.randi_range(-1, 1))
	_road(x, _wiggle(rng, nw, ne, 6, 1), 2)
	var lane_w := Vector2i(int(W * rng.randf_range(0.15, 0.2)), cy)
	var lane_e := Vector2i(int(W * rng.randf_range(0.8, 0.85)), cy)
	if rng.randf() < 0.5:
		_road(x, _wiggle(rng, nw, lane_w, 6, 1), 2)
		_road(x, _wiggle(rng, lane_e, Vector2i(lane_e.x + rng.randi_range(-2, 2), ry - 1), 6, 1), 2)
	else:
		_road(x, _wiggle(rng, ne, lane_e, 6, 1), 2)
		_road(x, _wiggle(rng, lane_w, Vector2i(lane_w.x + rng.randi_range(-2, 2), ry - 1), 6, 1), 2)
	# Sud : chemin le long de la voie secondaire (jusqu'au bord) et chemin est-ouest.
	_road(x, [Vector2i(x.spur_x, ry + 2), Vector2i(x.spur_x, H - 2)], 3)
	var sy := ry + int((H - ry) * 0.42) + rng.randi_range(-2, 2)
	_road(x, _wiggle(rng, Vector2i(5, sy + rng.randi_range(-2, 2)), Vector2i(x.spur_x, sy), 6, 2), 2)
	_road(x, _wiggle(rng, Vector2i(x.spur_x, sy), Vector2i(W - 6, sy + rng.randi_range(-2, 2)), 6, 2), 2)
	# Clairière du spawn (sur le chemin de la voie secondaire) et de l'extraction (reliée à la rue du nord).
	_mark(x.keep, W, H, Rect2i(spawn.x - 3, spawn.y - 3, 7, 4))
	_mark(x.keep, W, H, Rect2i(ex.x - 2, ex.y - 2, 6, 6))
	var ex_end := ne if absi(ne.x - ex.x) < absi(nw.x - ex.x) else nw
	_road(x, _wiggle(rng, Vector2i(ex.x, ex.y + 2), ex_end, 4, 1), 2)


## Cases de rue en bordure (une voisine hors rue) : points d'accroche des bâtiments.
static func _frontage(x: Ctx) -> void:
	x.frontage.clear()
	var W := x.W
	var occ := x.occ
	var keep := x.keep
	var paths := x.L.paths
	# Balayage de la grille (ordre déterministe, sans tri) : rue dont une voisine est un terrain
	# libre (ni rue, ni structure, ni abord réservé).
	for y in range(1, x.H - 1):
		for xx in range(1, W - 1):
			var p := Vector2i(xx, y)
			if not paths.has(p):
				continue
			for d in DIRS:
				var q: Vector2i = p - d
				var j := q.y * W + q.x
				if occ[j] == 0 and keep[j] == 0 and not paths.has(q):
					x.frontage.append(p)
					break


# --- Voie ferrée ----------------------------------------------------------------------------

## Rails (détails au sol), voie secondaire et train à l'arrêt : locomotive + tender + wagons,
## 2 ou 3 passages de 2 cases entre les wagons, voie libre aux deux bouts.
static func _railway(x: Ctx) -> void:
	var L := x.L
	var W := x.W
	var H := x.H
	var rng := x.rng
	var ry := x.rail_y
	var rail_room := L.room_at(Vector2i(W / 2, ry))
	var rid := rail_room.id if rail_room != null else -1
	for xx in range(1, W - 1):
		var s := L.add_spawn(L.decor_spawns, Vector2i(xx, ry + 1), &"decal_rail", rid)
		s.offset = Vector2(0.0, 6.0)
		s.scale = 0.9
	for y in range(ry + 2, H - 1):
		var c := Vector2i(x.spur_x, y)
		var r2 := L.room_at(c)
		var s2 := L.add_spawn(L.decor_spawns, c, &"decal_rail", r2.id if r2 != null else -1)
		s2.rot = PI * 0.5
		s2.scale = 0.9
	var cars: Array[StringName] = [&"lm_loco", &"lm_tender"]
	var target := int(float(W) * rng.randf_range(Cfg.getf("village_train_min", 0.55), Cfg.getf("village_train_max", 0.68)))
	var total := 8
	while true:
		var w: StringName = WAGONS[rng.randi_range(0, WAGONS.size() - 1)]
		if total + 4 + 3 > target:
			break
		cars.append(w)
		total += 4
	cars.append(&"lm_caboose")
	total += 3
	var gaps := {}
	var n_gaps := Cfg.range_i(rng, "train_gaps_min", "train_gaps_max", 2, 3)
	var cand: Array[int] = []
	for i in range(2, cars.size()):
		cand.append(i)
	_shuffle(cand, rng)
	for i2 in mini(n_gaps, cand.size()):
		gaps[cand[i2]] = true
		total += 2
	var x0 := clampi((W - total) / 2 + rng.randi_range(-4, 4), 5, maxi(5, W - 5 - total))
	var xx2 := x0
	for i3 in cars.size():
		if gaps.has(i3):
			xx2 += 2
		var fp: Vector2i = LANDMARKS[cars[i3]]
		var r := Rect2i(xx2, ry, fp.x, 2)
		_landmark(x, cars[i3], r)
		L.train.append({"kind": cars[i3], "rect": r})
		xx2 += fp.x


# --- Grands décors ------------------------------------------------------------------------

## Pose un grand décor sur des cases WALL (sprite 2D : landmark_spawns).
static func _landmark(x: Ctx, kind: StringName, r: Rect2i) -> void:
	x.L.fill_rect(r, T.WALL)
	_mark(x.occ, x.W, x.H, r)
	var s := FloorLayout.Spawn.new()
	s.kind = kind
	s.size = r.size
	s.cell = Vector2i(r.position.x + (r.size.x - 1) / 2, r.end.y - 1)
	x.L.landmark_spawns.append(s)


## Pose un grand décor près de `want` (premier emplacement libre en spirale) ; renvoie l'emprise.
static func _place_free(x: Ctx, kind: StringName, want: Vector2i, margin: int) -> Rect2i:
	var fp: Vector2i = LANDMARKS[kind]
	for rad in 8:
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var r := Rect2i(want + Vector2i(dx, dy), fp)
				if _free(x, r, margin, 2) and _ring_ok(x, r):
					_landmark(x, kind, r)
					return r
	return Rect2i()


# --- Bâtiments -------------------------------------------------------------------------------

static func _buildings(x: Ctx, world: WorldData, want_mine: bool) -> void:
	var rng := x.rng
	var required: Array[StringName] = []
	for a: StringName in [&"saloon", &"bank", &"sheriff", &"mine"]:
		if world.has_archetype(a) and (a != &"mine" or want_mine):
			required.append(a)
	var optional: Array[StringName] = []
	for a2: StringName in [&"store", &"hotel", &"stable", &"church"]:
		if world.has_archetype(a2):
			optional.append(a2)
	_shuffle(optional, rng)
	# Bâtiments importants : 4 à 6 (hors entrée de mine).
	var n_major := Cfg.range_i(rng, "village_major_min", "village_major_max", 4, 6)
	var chosen: Array[StringName] = required.duplicate()
	var majors := 0
	for a3 in chosen:
		if a3 != &"mine":
			majors += 1
	while majors < n_major and not optional.is_empty():
		chosen.append(optional.pop_back())
		majors += 1
	var ctx := {"super_budget": Cfg.geti("super_loot_max_per_floor", 2)}
	# Banque d'abord : son coffre-fort scellé passe avant les autres salles scellées.
	chosen.sort_custom(func(a: StringName, b: StringName) -> bool: return a == &"bank" and b != &"bank")
	var plans: Array[Tpl.Plan] = []
	for a5 in chosen:
		plans.append(_build_plan(a5, rng, ctx))
	# Placement : obligatoires d'abord, puis du plus grand au plus petit (les grands ont besoin
	# des îlots libres).
	var porder: Array[int] = []
	for i in plans.size():
		porder.append(i)
	porder.sort_custom(func(a: int, b: int) -> bool:
		var ra := required.has(plans[a].archetype)
		var rb := required.has(plans[b].archetype)
		if ra != rb:
			return ra
		return plans[a].size.x * plans[a].size.y > plans[b].size.x * plans[b].size.y)
	var queue: Array[Tpl.Plan] = []
	for oi in porder:
		queue.append(plans[oi])
	var spare := 2
	while not queue.is_empty():
		var p: Tpl.Plan = queue.pop_front()
		if not _place_major(x, p):
			# Bâtiment optionnel impossible à placer : un autre optionnel, plus petit, le remplace.
			if not required.has(p.archetype) and spare > 0 and not optional.is_empty():
				spare -= 1
				queue.append(_build_plan(optional.pop_back(), rng, ctx))
			else:
				push_warning("Village : %s impossible à placer" % p.archetype)
	# Les allées des portes deviennent aussi des rues (accroches pour les maisons).
	_frontage(x)
	# Petites maisons en groupes (2 à 3 par groupe), appentis collés.
	var n_houses := Cfg.range_i(rng, "village_houses_min", "village_houses_max", 11, 15)
	var groups := HOUSE_GROUPS.duplicate()
	_shuffle(groups, rng)
	var placed := 0
	var gi := 0
	var guard := 0
	while placed < n_houses and guard < groups.size():
		guard += 1
		var g: Vector2 = groups[gi % groups.size()]
		gi += 1
		var per := rng.randi_range(1, 3)
		for k in per:
			if placed >= n_houses or _full(x):
				break
			var hp := _build_plan(&"shack", rng, ctx)
			var jit := Vector2(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.02, 0.02))
			var tgt := x.at(g + jit)
			if _place_building(x, hp, tgt, 8.0) or (k == 0 and _place_building(x, hp, tgt, 18.0)):
				placed += 1
				var b := x.L.buildings[x.L.buildings.size() - 1]
				if rng.randf() < Cfg.getf("village_annex_chance", 0.45):
					_annex(x, b, ctx)
				_yard_for(x, b)
	# Complément : balayage des bords de rue (ordre aléatoire), une maison par emplacement libre,
	# jusqu'au nombre visé (et au moins village_buildings_min bâtiments).
	var want := maxi(n_houses - placed, Cfg.geti("village_buildings_min", 18) - x.L.buildings.size())
	if want > 0:
		_frontage(x)
		var order := x.frontage.duplicate()
		_shuffle(order, rng)
		var hp2 := _build_plan(&"shack", rng, ctx)
		for road: Vector2i in order:
			if want <= 0 or _full(x):
				break
			if x.is_occ(road):
				continue
			for d in _facade_dirs():
				var q := road - d
				if x.L.paths.has(q) or x.is_occ(q) or x.is_keep(q):
					continue
				var o := {}
				for t in 6:
					var oo := _orient(hp2, d, rng, road, t / 2)
					var r: Rect2i = oo["rect"]
					if not _free(x, r, 1, 2) or not _porch_ok(x, r, d):
						continue
					var trail := _door_trails(x, hp2, oo, d, false)
					if trail.is_empty():
						continue
					oo["trail"] = trail
					oo["f"] = d
					o = oo
					break
				if o.is_empty():
					continue
				var nb := _commit_building(x, hp2, o)
				want -= 1
				if rng.randf() < Cfg.getf("village_annex_chance", 0.45) * 0.5:
					_annex(x, nb, ctx)
				_yard_for(x, nb)
				hp2 = _build_plan(&"shack", rng, ctx)
				break
	# Terrains vagues : maisons posées sur les zones libres (grille de points en ordre aléatoire),
	# façade vers une rue atteinte par une allée droite (au plus 8 cases).
	want = maxi(Cfg.geti("village_backlot_houses", 4), Cfg.geti("village_buildings_min", 18) - x.L.buildings.size())
	var pts: Array[Vector2i] = []
	for yy in range(3, x.H - 7, 2):
		for xx in range(3, x.W - 7, 2):
			pts.append(Vector2i(xx, yy))
	_shuffle(pts, rng)
	var hp3 := _build_plan(&"shack", rng, ctx)
	for pt in pts:
		if want <= 0 or _full(x):
			break
		if x.is_occ(pt) or x.is_keep(pt):
			continue
		var dirs2 := _facade_dirs()
		_shuffle(dirs2, rng)
		for d: Vector2i in dirs2:
			var tr := d.x != 0
			var sz := Vector2i(hp3.size.y, hp3.size.x) if tr else hp3.size
			var o := {"rect": Rect2i(pt, sz), "fx": rng.randf() < 0.5, "fy": d == Vector2i.UP, "tr": tr}
			if d == Vector2i.LEFT:
				o["fx"] = true
			if d == Vector2i.RIGHT:
				o["fx"] = false
			if tr:
				o["fy"] = rng.randf() < 0.5
			if d == Vector2i.DOWN:
				o["fy"] = false
			var r: Rect2i = o["rect"]
			if not _free(x, r, 1, 2) or not _porch_ok(x, r, d):
				continue
			var trail := _lanes(x, hp3, o, d, Cfg.geti("village_lane_max", 18))
			if trail.is_empty():
				continue
			o["trail"] = trail
			o["f"] = d
			var nb := _commit_building(x, hp3, o)
			want -= 1
			_yard_for(x, nb)
			hp3 = _build_plan(&"shack", rng, ctx)
			break
	# Dernier recours (carte trop vide) : petites cabanes 5×5 sur les lots restants, allée longue.
	var tries2 := 0
	while x.L.buildings.size() < Cfg.geti("village_buildings_min", 18) and tries2 < pts.size():
		var pt2: Vector2i = pts[tries2]
		tries2 += 1
		if x.is_occ(pt2) or x.is_keep(pt2):
			continue
		var hp4 := Tpl.build(&"shed", rng, ctx, "village_size_cabin_")
		hp4.archetype = &"shack"
		hp4.rooms[0].role = &"shack"
		hp4.rooms[0].name = "Cabane"
		for d4: Vector2i in _facade_dirs(true):
			var o4 := {"rect": Rect2i(pt2, hp4.size), "fx": false, "fy": d4 == Vector2i.UP, "tr": false}
			var r4: Rect2i = o4["rect"]
			if not _free(x, r4, 1, 2) or not _porch_ok(x, r4, d4):
				continue
			var lane4 := _lanes(x, hp4, o4, d4, 30)
			if lane4.is_empty():
				continue
			o4["trail"] = lane4
			o4["f"] = d4
			_commit_building(x, hp4, o4)
			break
	# Appentis des grands bâtiments (écurie, magasin) et quelques maisons supplémentaires.
	for b2 in x.L.buildings.duplicate():
		if (b2.archetype == &"stable" or b2.archetype == &"store") and rng.randf() < 0.7:
			_annex(x, b2, ctx)


## Côtés de façade autorisés. Rendu pré-calculé (caméra inclinée vers le nord) : seule la façade
## SUD est visible ; une porte au nord est cachée sous le toit projeté, une porte est / ouest est
## vue par la tranche (sous le débord du toit). [generator] village_facade_south_only = true →
## toutes les portes extérieures sont sur la façade sud. `ns` : variante nord / sud seulement.
static func _facade_dirs(ns: bool = false) -> Array[Vector2i]:
	if Cfg.geti("village_facade_south_only", 1) != 0:
		return [Vector2i.DOWN]
	if ns:
		return [Vector2i.DOWN, Vector2i.UP]
	return DIRS.duplicate()


## Bâtiment important : près de son point d'attraction, puis plus loin, puis balayage complet.
static func _place_major(x: Ctx, p: Tpl.Plan) -> bool:
	var target := x.at(ATTRACT.get(p.archetype, Vector2(0.5, 0.3)))
	return _place_building(x, p, target, 14.0) or _place_building(x, p, target, 30.0) or _scan_place(x, p, target)


## Plafond du nombre de bâtiments atteint.
static func _full(x: Ctx) -> bool:
	return x.L.buildings.size() >= Cfg.geti("village_buildings_max", 24)


## Pose un bâtiment face à une rue, au plus près de `target` (rayon de recherche `radius`).
## La façade (ligne des portes) donne sur un porche d'une case, puis 0 à 1 case de sable, puis la
## rue. Écart d'au moins une case avec toute autre structure.
static func _place_building(x: Ctx, p: Tpl.Plan, target: Vector2i, radius: float) -> bool:
	var rng := x.rng
	var cands: Array[Vector2i] = []
	var r2 := int(radius * radius)
	for f in x.frontage:
		var dx := f.x - target.x
		var dy := f.y - target.y
		if dx * dx + dy * dy <= r2:
			cands.append(f)
	if cands.is_empty():
		return false
	var best := {}
	var best_score := -1e9
	var tries := Cfg.geti("village_building_tries", 40)
	for t in tries:
		var road: Vector2i = cands[rng.randi_range(0, cands.size() - 1)]
		var dirs: Array[Vector2i] = []
		for d in _facade_dirs():
			# Bâtiments à plusieurs pièces : façade au nord ou au sud seulement (gabarits d'ameublement).
			if d.x != 0 and p.rooms.size() > 1:
				continue
			var q := road - d
			if not x.L.paths.has(q) and not x.is_occ(q) and not x.is_keep(q):
				dirs.append(d)
		if dirs.is_empty():
			continue
		var f: Vector2i = dirs[rng.randi_range(0, dirs.size() - 1)]
		var setback := rng.randi_range(0, 2) if rng.randf() < 0.5 else 0
		var o := _orient(p, f, rng, road, setback)
		var r: Rect2i = o["rect"]
		if not _free(x, r, 1, 2):
			continue
		if not _porch_ok(x, r, f):
			continue
		var trail := _door_trails(x, p, o, f, false)
		if trail.is_empty():
			continue
		var c := Vector2(r.get_center())
		var score := -c.distance_to(Vector2(target)) + rng.randf() * 3.0
		# Groupes : bonus si un autre bâtiment est tout près (ruelle d'1 à 3 cases).
		var near := 0
		for b in x.L.buildings:
			var gap := _gap(r, b.rect)
			if gap >= 1 and gap <= 2:
				near += 1
		score += minf(float(near), 2.0) * 4.0
		if score > best_score:
			best_score = score
			best = o
			best["trail"] = trail
			best["f"] = f
	if best.is_empty():
		return false
	_commit_building(x, p, best)
	return true


## Allées des portes de façade d'une maison de terrain vague : plus court chemin (4-voisinage, sur
## le sable libre, hors emprise) de la case devant chaque porte jusqu'à une rue, au plus `maxd`
## cases. Renvoie les cases des allées, ou [] si une porte n'atteint aucune rue.
static func _lanes(x: Ctx, p: Tpl.Plan, o: Dictionary, f: Vector2i, maxd: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r: Rect2i = o["rect"]
	for d in p.doors:
		if d.a != Tpl.OUTSIDE and d.b != Tpl.OUTSIDE:
			continue
		var start := tf_cell(d.cell, p.size, o["fx"], o["fy"], o["tr"]) + r.position + f
		if x.is_occ(start):
			return []
		var prev := {start: start}
		var frontier: Array[Vector2i] = [start]
		var goal := Vector2i(-1, -1)
		var depth := 0
		while not frontier.is_empty() and depth <= maxd and goal.x < 0:
			var nxt: Array[Vector2i] = []
			for c in frontier:
				if x.L.paths.has(c):
					goal = c
					break
				for dd in DIRS:
					var n := c + dd
					if prev.has(n) or x.is_occ(n) or r.has_point(n):
						continue
					prev[n] = c
					nxt.append(n)
			frontier = nxt
			depth += 1
		if goal.x < 0:
			return []
		var c2: Vector2i = prev[goal]
		while true:
			out.append(c2)
			if c2 == start:
				break
			c2 = prev[c2]
	return out


## Placement exhaustif (bâtiments importants dont le placement guidé a échoué) : 1) chaque case de
## rue, façade nord ou sud, recul 0 à 2 ; 2) toute position libre (pas de 2), façade nord ou sud,
## allée de terre jusqu'à la rue la plus proche. Le plus près de `target` d'abord.
static func _scan_place(x: Ctx, p: Tpl.Plan, target: Vector2i) -> bool:
	_frontage(x)
	var roads := x.frontage.duplicate()
	roads.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - target).length_squared() < (b - target).length_squared())
	for road: Vector2i in roads:
		for d: Vector2i in _facade_dirs(true):
			if x.is_occ(road - d) or x.is_keep(road - d) or x.L.paths.has(road - d):
				continue
			for sb in 3:
				var o := _orient(p, d, x.rng, road, sb)
				var r: Rect2i = o["rect"]
				if not _free(x, r, 1, 2) or not _porch_ok(x, r, d):
					continue
				var trail := _door_trails(x, p, o, d, false)
				if trail.is_empty():
					continue
				o["trail"] = trail
				o["f"] = d
				_commit_building(x, p, o)
				return true
	var pts: Array[Vector2i] = []
	for yy in range(2, x.H - p.size.y - 1, 2):
		for xx in range(2, x.W - p.size.x - 1, 2):
			pts.append(Vector2i(xx, yy))
	pts.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - target).length_squared() < (b - target).length_squared())
	for pt in pts:
		for d2: Vector2i in _facade_dirs(true):
			var o2 := {"rect": Rect2i(pt, p.size), "fx": false, "fy": d2 == Vector2i.UP, "tr": false}
			var r2: Rect2i = o2["rect"]
			if not _free(x, r2, 1, 2) or not _porch_ok(x, r2, d2):
				continue
			var lane := _lanes(x, p, o2, d2, 40)
			if lane.is_empty():
				continue
			o2["trail"] = lane
			o2["f"] = d2
			_commit_building(x, p, o2)
			return true
	return false


## Écart (cases libres) entre deux rectangles (0 = collés, négatif = chevauchement).
static func _gap(a: Rect2i, b: Rect2i) -> int:
	var dx := maxi(b.position.x - a.end.x, a.position.x - b.end.x)
	var dy := maxi(b.position.y - a.end.y, a.position.y - b.end.y)
	return maxi(dx, dy)


## Orientation d'un plan (façade locale en bas) pour une façade tournée vers `f`, porche devant
## la case de rue `road` (décalé de `setback`).
static func _orient(p: Tpl.Plan, f: Vector2i, rng: RandomNumberGenerator, road: Vector2i, setback: int) -> Dictionary:
	var tr := f.x != 0
	var size := Vector2i(p.size.y, p.size.x) if tr else p.size
	var fx := false
	var fy := false
	match f:
		Vector2i.DOWN:
			fx = rng.randf() < 0.5
		Vector2i.UP:
			fy = true
			fx = rng.randf() < 0.5
		Vector2i.RIGHT:
			fy = rng.randf() < 0.5
		_:
			fx = true
			fy = rng.randf() < 0.5
	var facade := road - f * (2 + setback)
	var pos := Vector2i.ZERO
	if f.y != 0:
		pos.x = road.x - rng.randi_range(1, maxi(1, size.x - 2))
		pos.y = facade.y - size.y + 1 if f.y > 0 else facade.y
	else:
		pos.y = road.y - rng.randi_range(1, maxi(1, size.y - 2))
		pos.x = facade.x - size.x + 1 if f.x > 0 else facade.x
	return {"rect": Rect2i(pos, size), "fx": fx, "fy": fy, "tr": tr}


## Porche : la rangée (ou colonne) devant la façade est libre de toute structure.
static func _porch_ok(x: Ctx, r: Rect2i, f: Vector2i) -> bool:
	for c in _porch_cells(r, f):
		if x.is_occ(c):
			return false
	return true


static func _porch_cells(r: Rect2i, f: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if f.y != 0:
		var y := r.end.y if f.y > 0 else r.position.y - 1
		for xx in range(r.position.x, r.end.x):
			out.append(Vector2i(xx, y))
	else:
		var x2 := r.end.x if f.x > 0 else r.position.x - 1
		for y2 in range(r.position.y, r.end.y):
			out.append(Vector2i(x2, y2))
	return out


## Chemins des portes de façade vers la rue : depuis chaque porte, tout droit (direction `f`)
## jusqu'à une case de rue (ou, pour une annexe, une case déjà réservée) en au plus 4 cases
## libres. Renvoie les cases traversées, ou [] si une porte n'atteint rien.
static func _door_trails(x: Ctx, p: Tpl.Plan, o: Dictionary, f: Vector2i, annex: bool, reach: int = 5) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r: Rect2i = o["rect"]
	for d in p.doors:
		if d.a != Tpl.OUTSIDE and d.b != Tpl.OUTSIDE:
			continue
		var dc := tf_cell(d.cell, p.size, o["fx"], o["fy"], o["tr"]) + r.position
		var c := dc + f
		var hit := false
		for k in reach:
			if x.is_occ(c):
				break
			if x.L.paths.has(c) or (annex and x.is_keep(c) and k > 0):
				hit = true
				break
			out.append(c)
			c += f
		if not hit:
			return []
	if out.is_empty():
		out.append(r.position)  # jamais vide si valide (la case n'est pas utilisée)
	return out


static func _commit_building(x: Ctx, p: Tpl.Plan, o: Dictionary) -> FloorLayout.Building:
	var r: Rect2i = o["rect"]
	var f: Vector2i = o["f"]
	var b := _stamp_building(x, p, r.position, o["fx"], o["fy"], o["tr"], f)
	_mark(x.occ, x.W, x.H, r)
	for c in _porch_cells(r, f):
		if x.inb(c):
			x.keep[x.i(c)] = 1
	var trail: Array[Vector2i] = o["trail"]
	for c2 in trail:
		if r.has_point(c2):
			continue
		x.keep[x.i(c2)] = 1
		if not _porch_cells(r, f).has(c2):
			x.L.paths[c2] = true
	return b


## Appentis / remise / latrines collés au flanc d'un bâtiment, façade du même côté, en retrait.
static func _annex(x: Ctx, host: FloorLayout.Building, ctx: Dictionary) -> void:
	if _full(x):
		return
	var rng := x.rng
	var f: Vector2i = x.facing.get(host.id, Vector2i.DOWN)
	var p := _build_plan(&"shed", rng, ctx)
	var hr := host.rect
	var sides: Array = [1, -1] if rng.randf() < 0.5 else [-1, 1]
	for side: int in sides:
		for back: int in [0, 1, 2]:
			var o := _orient(p, f, rng, Vector2i.ZERO, 0)
			var sz: Vector2i = (o["rect"] as Rect2i).size
			var pos := Vector2i.ZERO
			if f.y != 0:
				pos.x = hr.end.x if side > 0 else hr.position.x - sz.x
				pos.y = (hr.end.y - sz.y - back) if f.y > 0 else (hr.position.y + back)
			else:
				pos.y = hr.end.y if side > 0 else hr.position.y - sz.y
				pos.x = (hr.end.x - sz.x - back) if f.x > 0 else (hr.position.x + back)
			var r := Rect2i(pos, sz)
			o["rect"] = r
			if not _free_beside(x, r, hr):
				continue
			if not _porch_ok(x, r, f):
				continue
			var trail := _door_trails(x, p, o, f, true)
			if trail.is_empty():
				continue
			o["trail"] = trail
			o["f"] = f
			_commit_building(x, p, o)
			return


## Rectangle libre, collé au bâtiment `host` (seule structure tolérée à moins d'une case).
static func _free_beside(x: Ctx, r: Rect2i, host: Rect2i) -> bool:
	if r.position.x < 2 or r.position.y < 2 or r.end.x > x.W - 2 or r.end.y > x.H - 2:
		return false
	for c in _cells(r):
		if x.is_occ(c) or x.is_keep(c):
			return false
	for c2 in _cells(r.grow(1)):
		if x.is_occ(c2) and not host.has_point(c2):
			return false
	return true


# --- Cours et enclos ------------------------------------------------------------------------

## Cours clôturées derrière certains bâtiments (palissade sur trois côtés, portail de 2 cases).
static func _yards(x: Ctx) -> void:
	for b in x.L.buildings:
		if not x.yard_tried.has(b.id):
			_yard_for(x, b)


## Tente une cour derrière le bâtiment `b` (une seule fois par bâtiment).
static func _yard_for(x: Ctx, b: FloorLayout.Building) -> void:
	var rng := x.rng
	x.yard_tried[b.id] = true
	var a := b.archetype
	if a == &"shed" or a == &"mine":
		return
	var chance := Cfg.getf("village_yard_chance", 0.45)
	if a == &"stable" or a == &"store":
		chance = 0.9
	elif a != &"shack":
		chance *= 0.5
	if rng.randf() >= chance:
		return
	var f: Vector2i = x.facing.get(b.id, Vector2i.DOWN)
	# Arrière d'abord, puis les flancs (dans un ordre tiré au sort).
	var sides: Array[Vector2i] = [-f, Vector2i(f.y, f.x), Vector2i(-f.y, -f.x)]
	if rng.randf() < 0.5:
		sides = [-f, Vector2i(-f.y, -f.x), Vector2i(f.y, f.x)]
	var br := b.rect
	for back in sides:
		for depth in range(rng.randi_range(5, 7), 2, -1):
			for ext: int in [2, 1, 0]:
				var e1 := mini(ext, rng.randi_range(0, 2))
				var e2 := mini(ext, rng.randi_range(0, 2))
				var R: Rect2i
				if back.y != 0:
					var y0 := br.position.y - depth if back.y < 0 else br.end.y
					R = Rect2i(br.position.x - e1, y0, br.size.x + e1 + e2, depth)
				else:
					var x0 := br.position.x - depth if back.x < 0 else br.end.x
					R = Rect2i(x0, br.position.y - e1, depth, br.size.y + e1 + e2)
				if _try_yard(x, R, br, back, &"backyard"):
					return


## Enclos à chevaux isolés (palissade fermée, portail de 2 cases), surtout au sud et près de l'écurie.
static func _corrals(x: Ctx) -> void:
	var rng := x.rng
	var n := Cfg.range_i(rng, "village_corrals_min", "village_corrals_max", 1, 3)
	var targets: Array[Vector2i] = []
	for b in x.L.buildings:
		if b.archetype == &"stable":
			targets.append(Vector2i(b.rect.get_center()))
	targets.append(x.at(Vector2(0.82, 0.74)))
	targets.append(x.at(Vector2(0.15, 0.7)))
	targets.append(x.at(Vector2(0.85, 0.4)))
	var made := 0
	for t in targets:
		if made >= n:
			break
		for k in 40:
			var w := rng.randi_range(6, 9)
			var h := rng.randi_range(5, 7)
			var c := t + Vector2i(rng.randi_range(-9, 9), rng.randi_range(-7, 7))
			var R := Rect2i(c - Vector2i(w / 2, h / 2), Vector2i(w, h))
			if _try_yard(x, R, Rect2i(), Vector2i.ZERO, &"corral"):
				made += 1
				break


## Pose une cour (contre le bâtiment `host`, côté `back`) ou un enclos isolé (`host` vide).
static func _try_yard(x: Ctx, R: Rect2i, host: Rect2i, back: Vector2i, role: StringName) -> bool:
	if R.position.x < 2 or R.position.y < 2 or R.end.x > x.W - 2 or R.end.y > x.H - 2:
		return false
	for c in _cells(R):
		if x.is_occ(c) or x.is_keep(c):
			return false
	for c2 in _cells(R.grow(1)):
		if x.is_occ(c2) and not host.has_point(c2):
			return false
	if not _ring_ok(x, R if host.size.x == 0 else R.merge(host)):
		return false
	# Palissade : périmètre de R, sauf les cases collées au mur du bâtiment.
	var per := _perimeter(R)
	var fence: Array[bool] = []
	for c3 in per:
		var against := host.size.x > 0 and host.has_point(c3 - back)
		fence.append(not against)
	# Portail : 2 cases au milieu du côté opposé au bâtiment (ou d'un côté libre).
	var gate_ok := false
	var sides: Array = [back, Vector2i(back.y, back.x), Vector2i(-back.y, -back.x)] if back != Vector2i.ZERO \
		else [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]
	var gate: Array[Vector2i] = []
	for s: Vector2i in sides:
		gate = _gate_cells(R, s, x.rng)
		var ok := true
		for g in gate:
			var out: Vector2i = g + s
			if x.is_occ(out) or x.is_occ(out + s):
				ok = false
		if ok:
			gate_ok = true
			for g2 in gate:
				x.keep[x.i(g2 + s)] = 1
			break
	if not gate_ok:
		return false
	var polys: Array = []
	var cur: Array[Vector2i] = []
	for k in per.size():
		var c4 := per[k]
		if fence[k] and not gate.has(c4):
			cur.append(c4)
			x.L.set_tile(c4, T.WALL)
		elif not cur.is_empty():
			polys.append(cur)
			cur = []
	if not cur.is_empty():
		# Raccorde la fin du périmètre au début (périmètre circulaire).
		if not polys.is_empty() and fence[0] and not gate.has(per[0]):
			var first: Array[Vector2i] = polys[0]
			cur.append_array(first)
			polys[0] = cur
		else:
			polys.append(cur)
	for pl: Array[Vector2i] in polys:
		x.L.fences.append(pl)
	_mark(x.occ, x.W, x.H, R)
	x.yards.append({"rect": R, "inner": R.grow(-1) if host.size.x == 0 else _yard_inner(R, back), "role": role, "gate": gate})
	return true


static func _yard_inner(R: Rect2i, back: Vector2i) -> Rect2i:
	# Côté du bâtiment : la rangée contre le mur fait partie de la cour.
	var r := R.grow(-1)
	match back:
		Vector2i.UP:
			r = Rect2i(r.position.x, r.position.y, r.size.x, r.size.y + 1)
		Vector2i.DOWN:
			r = Rect2i(r.position.x, r.position.y - 1, r.size.x, r.size.y + 1)
		Vector2i.LEFT:
			r = Rect2i(r.position.x, r.position.y, r.size.x + 1, r.size.y)
		Vector2i.RIGHT:
			r = Rect2i(r.position.x - 1, r.position.y, r.size.x + 1, r.size.y)
	return r


## Périmètre d'un rectangle dans l'ordre (sens horaire depuis le coin haut-gauche).
static func _perimeter(R: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for xx in range(R.position.x, R.end.x):
		out.append(Vector2i(xx, R.position.y))
	for y in range(R.position.y + 1, R.end.y):
		out.append(Vector2i(R.end.x - 1, y))
	for x2 in range(R.end.x - 2, R.position.x - 1, -1):
		out.append(Vector2i(x2, R.end.y - 1))
	for y2 in range(R.end.y - 2, R.position.y, -1):
		out.append(Vector2i(R.position.x, y2))
	return out


static func _gate_cells(R: Rect2i, side: Vector2i, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if side.y != 0:
		var y := R.end.y - 1 if side.y > 0 else R.position.y
		var gx := rng.randi_range(R.position.x + 1, maxi(R.position.x + 1, R.end.x - 3))
		out.append(Vector2i(gx, y))
		out.append(Vector2i(gx + 1, y))
	else:
		var xx := R.end.x - 1 if side.x > 0 else R.position.x
		var gy := rng.randi_range(R.position.y + 1, maxi(R.position.y + 1, R.end.y - 3))
		out.append(Vector2i(xx, gy))
		out.append(Vector2i(xx, gy + 1))
	return out


## Tronçons de palissade le long de la voie ferrée (côté nord), avec des trouées.
static func _rail_fences(x: Ctx) -> void:
	var rng := x.rng
	var y := x.rail_y - 3
	var n := Cfg.range_i(rng, "village_rail_fences_min", "village_rail_fences_max", 2, 4)
	for k in n:
		for t in 12:
			var length := rng.randi_range(4, 8)
			var x0 := rng.randi_range(3, x.W - 4 - length)
			var r := Rect2i(x0, y, length, 1)
			if not _free(x, r, 1, 2) or not _ring_ok(x, r):
				continue
			var pl: Array[Vector2i] = []
			for c in _cells(r):
				x.L.set_tile(c, T.WALL)
				pl.append(c)
			_mark(x.occ, x.W, x.H, r)
			x.L.fences.append(pl)
			break


# --- Rochers -----------------------------------------------------------------------------------

## Formations rocheuses massives : grosses dans les quatre coins, d'autres le long des bords,
## 2 à 4 au milieu (couverts). Une formation = grappe de pièces de rocher accolées.
static func _edge_rocks(x: Ctx) -> void:
	var rng := x.rng
	var W := x.W
	var H := x.H
	var corners: Array[Vector2i] = [Vector2i(1, 1), Vector2i(W - 2, 1), Vector2i(1, H - 2), Vector2i(W - 2, H - 2)]
	for c in corners:
		var kind: StringName = &"mesa" if c.y > H / 2 or rng.randf() < 0.6 else &"ledge"
		_formation(x, c, kind, rng.randi_range(6, 9), true)
	# Bords : un amas tous les 8 à 16 cases.
	for side in 4:
		var horiz := side < 2
		var length := W if horiz else H
		var a := rng.randi_range(6, 12)
		while a < length - 6:
			var c2: Vector2i
			match side:
				0: c2 = Vector2i(a, 1)
				1: c2 = Vector2i(a, H - 2)
				2: c2 = Vector2i(1, a)
				_: c2 = Vector2i(W - 2, a)
			var roll := rng.randf()
			var kind2: StringName = &"ledge" if roll < 0.45 else (&"scree" if roll < 0.75 else &"mesa")
			var n := rng.randi_range(3, 5) if kind2 != &"scree" else rng.randi_range(2, 3)
			if rng.randf() < Cfg.getf("village_edge_rock_chance", 0.75):
				_formation(x, c2, kind2, n, true)
			a += rng.randi_range(10, 18)


## 2 à 4 formations au milieu (couverts), loin des rues et de la voie ferrée.
static func _inner_rocks(x: Ctx) -> void:
	var rng := x.rng
	var W := x.W
	var H := x.H
	var n_in := Cfg.range_i(rng, "village_inner_rocks_min", "village_inner_rocks_max", 2, 4)
	var made := 0
	for t in 80:
		if made >= n_in:
			break
		var c3 := Vector2i(rng.randi_range(6, W - 7), rng.randi_range(6, H - 7))
		if x.is_keep(c3) or x.is_occ(c3) or absi(c3.y - x.rail_y) < 5:
			continue
		var kind3: StringName = &"mesa" if rng.randf() < 0.4 else &"ledge"
		if _formation(x, c3, kind3, rng.randi_range(2, 4), false) > 0:
			made += 1


## Construit une formation autour de `seed_cell` ; renvoie le nombre de pièces posées.
## `edge` : la formation peut toucher le bord de carte (sinon : 2 cases de marge partout).
static func _formation(x: Ctx, seed_cell: Vector2i, kind: StringName, n: int, edge: bool) -> int:
	var rng := x.rng
	var pset: Array = ROCK_SETS[kind]
	var pieces: Array[Rect2i] = []
	var kinds: Array[StringName] = []
	var cells: Array[Vector2i] = []
	for k in n * 4:
		if pieces.size() >= n:
			break
		var pk: StringName = pset[0] if pieces.is_empty() else pset[rng.randi_range(1, pset.size() - 1)]
		var fp: Vector2i = LANDMARKS[pk]
		var r: Rect2i
		if pieces.is_empty():
			r = Rect2i(seed_cell - fp / 2, fp)
			if edge:
				r.position.x = clampi(r.position.x, 1, x.W - 1 - fp.x)
				r.position.y = clampi(r.position.y, 1, x.H - 1 - fp.y)
		else:
			var base := pieces[rng.randi_range(0, pieces.size() - 1)]
			var d := DIRS[rng.randi_range(0, 3)]
			var pos := base.position
			match d:
				Vector2i.RIGHT: pos = Vector2i(base.end.x, base.position.y + rng.randi_range(-fp.y + 1, base.size.y - 1))
				Vector2i.LEFT: pos = Vector2i(base.position.x - fp.x, base.position.y + rng.randi_range(-fp.y + 1, base.size.y - 1))
				Vector2i.DOWN: pos = Vector2i(base.position.x + rng.randi_range(-fp.x + 1, base.size.x - 1), base.end.y)
				_: pos = Vector2i(base.position.x + rng.randi_range(-fp.x + 1, base.size.x - 1), base.position.y - fp.y)
			if kind == &"scree":
				pos += d
			r = Rect2i(pos, fp)
		if not _rock_fits(x, r, edge, pieces):
			continue
		_landmark(x, pk, r)
		pieces.append(r)
		kinds.append(pk)
		for c in _cells(r):
			cells.append(c)
	if pieces.is_empty():
		return 0
	var hr: Array = ROCK_HEIGHT[kind]
	x.L.rock_formations.append({"cells": cells, "height": snappedf(rng.randf_range(float(hr[0]), float(hr[1])), 0.1), "kind": kind})
	return pieces.size()


## Pièce de rocher posable : dans la carte, hors rues / porches, à une case au moins des autres
## structures (sauf sa propre formation et le bord de carte), connexité préservée.
static func _rock_fits(x: Ctx, r: Rect2i, edge: bool, own: Array[Rect2i]) -> bool:
	var lo := 1 if edge else 3
	if r.position.x < lo or r.position.y < lo or r.end.x > x.W - lo or r.end.y > x.H - lo:
		return false
	for c in _cells(r):
		if x.is_occ(c) or x.is_keep(c):
			return false
	var mg := 1 if edge else 2
	for c2 in _cells(r.grow(mg)):
		if not x.inb(c2) or not x.is_occ(c2):
			continue
		if c2.x == 0 or c2.y == 0 or c2.x == x.W - 1 or c2.y == x.H - 1:
			continue
		var mine := false
		for o in own:
			if o.has_point(c2):
				mine = true
				break
		if not mine:
			return false
	return _ring_ok(x, r)


# --- Plans et tampons -----------------------------------------------------------------------

static func _build_plan(a: StringName, rng: RandomNumberGenerator, ctx: Dictionary) -> Tpl.Plan:
	for attempt in 12:
		var budget := int(ctx["super_budget"])
		var p := Tpl.build(a, rng, ctx, "village_size_")
		if _plan_ok(p):
			return p
		ctx["super_budget"] = budget
	# Repli : magasin (toujours valide).
	return Tpl.build(&"store", rng, ctx, "village_size_")


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


## Styles de toit (contrat rendu) : maisons variées, bâtiments importants typés.
static func _roof_style(a: StringName, rng: RandomNumberGenerator) -> StringName:
	match a:
		&"saloon":
			return &"red"
		&"hotel", &"church":
			return &"shingle"
		&"bank", &"store":
			return &"tin_blue"
		&"sheriff":
			return &"tin_rust"
		&"stable", &"mine", &"shed":
			return &"plank" if rng.randf() < 0.7 else &"tin_rust"
	var pool: Array[StringName] = [&"tin_blue", &"tin_blue", &"tin_blue", &"tin_rust", &"tin_rust", &"shingle", &"shingle", &"plank", &"red"]
	return pool[rng.randi_range(0, pool.size() - 1)]


## Applique un plan sur la grille (transposition, retournements), crée bâtiment, salles,
## portes et escaliers. `f` = côté de la façade (rue).
static func _stamp_building(x: Ctx, p: Tpl.Plan, origin: Vector2i, flip_x: bool, flip_y: bool, tr: bool, f: Vector2i) -> FloorLayout.Building:
	var L := x.L
	var rng := x.rng
	var res := x.res
	var size := Vector2i(p.size.y, p.size.x) if tr else p.size
	var b := L.add_building(p.archetype, "", Rect2i(origin, size))
	b.name = _building_name(p.archetype, rng, res)
	b.roof_style = _roof_style(p.archetype, rng)
	b.stories = 2 if p.has_upper else 1
	b.porch_side = f
	x.facing[b.id] = f
	L.carve_walled_rect(b.rect, T.WALL)
	var ids: Array[int] = []
	for pr in p.rooms:
		var gr := tf_rect(pr.rect, p.size, flip_x, flip_y, tr)
		gr.position += origin
		L.fill_rect(gr, T.FLOOR)
		var t := pr.type if pr.type != &"" else _pick_room_type(rng)
		var room := L.add_room(gr, false, t, pr.name, b.id)
		room.tags = PackedStringArray([String(pr.role), String(p.archetype)])
		ids.append(room.id)
	for d in p.doors:
		var c := tf_cell(d.cell, p.size, flip_x, flip_y, tr) + origin
		var ra := ids[d.a] if d.a != Tpl.OUTSIDE else _outdoor_room_at(L, c, f)
		var rb := ids[d.b] if d.b != Tpl.OUTSIDE else _outdoor_room_at(L, c, f)
		L.add_door(c, d.vertical != tr, d.state, ra, rb, d.key_id, b.id)
	for i in p.stairs.size():
		var up := p.stairs_up[i]
		if up and not x.want_upper:
			continue
		var sc := tf_cell(p.stairs[i], p.size, flip_x, flip_y, tr) + origin
		L.set_tile(sc, T.STAIRS_UP if up else T.STAIRS_DOWN)
		var st := FloorLayout.Stairs.new()
		st.cell = sc
		st.up = up
		st.target_floor = 1 if up else -1
		st.target_cell = sc
		L.stairs.append(st)
		if not up:
			res.mine_stairs.append(sc)
	if p.has_upper and x.want_upper:
		res.upper_specs.append({"building_id": b.id, "plan": p, "origin": origin, "flip_x": flip_x, "flip_y": flip_y, "transpose": tr})
	return b


## Salle extérieure devant une porte de façade.
static func _outdoor_room_at(L: FloorLayout, door_cell: Vector2i, f: Vector2i) -> int:
	var r := L.room_at(door_cell + f)
	return r.id if r != null else -1


## Repère local d'un plan → grille : transposition (x ↔ y) puis retournements.
static func tf_cell(c: Vector2i, size: Vector2i, fx: bool, fy: bool, tr: bool = false) -> Vector2i:
	var q := Vector2i(c.y, c.x) if tr else c
	var s := Vector2i(size.y, size.x) if tr else size
	return Vector2i(s.x - 1 - q.x if fx else q.x, s.y - 1 - q.y if fy else q.y)


static func tf_rect(r: Rect2i, size: Vector2i, fx: bool, fy: bool, tr: bool = false) -> Rect2i:
	var rr := Rect2i(r.position.y, r.position.x, r.size.y, r.size.x) if tr else r
	var s := Vector2i(size.y, size.x) if tr else size
	var xx := s.x - rr.end.x if fx else rr.position.x
	var y := s.y - rr.end.y if fy else rr.position.y
	return Rect2i(xx, y, rr.size.x, rr.size.y)


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
	var used: Array[String] = []
	for bb in res.layout.buildings:
		used.append(bb.name)
	if a == &"shack" or a == &"shed":
		var src: Array = SHACK_NAMES if a == &"shack" else SHED_NAMES
		var free_names: Array = []
		for nm: String in src:
			if not used.has(nm):
				free_names.append(nm)
		name = String(free_names[rng.randi_range(0, free_names.size() - 1)]) if not free_names.is_empty() else String(src[0])
	if _names_cache.has(a):
		var world_names: Variant = _names_cache[a]
		if a != &"shack" and world_names is PackedStringArray and (world_names as PackedStringArray).size() > 0:
			var arr: PackedStringArray = world_names
			name = arr[rng.randi_range(0, arr.size() - 1)]
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
		var tr: bool = spec.get("transpose", false)
		var gb := G.buildings[int(spec["building_id"])]
		var b := L.add_building(gb.archetype, gb.name, gb.rect)
		b.roof_style = gb.roof_style
		b.stories = gb.stories
		b.porch_side = gb.porch_side
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
			var xx := 1
			for j in k:
				var rr := Rect2i(xx, band.position.y, ws[j], band.size.y)
				xx += ws[j] + 1
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
			var gr := tf_rect(pr.rect, plan.size, fx, fy, tr)
			gr.position += origin
			L.fill_rect(gr, T.FLOOR)
			var t := pr.type if pr.type != &"" else _pick_room_type(rng)
			var room := L.add_room(gr, false, t, pr.name, b.id)
			room.tags = PackedStringArray([String(pr.role), String(gb.archetype)])
			ids.append(room.id)
		for d in plan.doors:
			var c := tf_cell(d.cell, plan.size, fx, fy, tr) + origin
			L.add_door(c, d.vertical != tr, d.state, ids[d.a], ids[d.b], d.key_id, b.id)
		for s2 in up_stairs:
			var sc := tf_cell(s2, p.size, fx, fy, tr) + origin
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

static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


static func _pick(a: Array, rng: RandomNumberGenerator) -> Variant:
	return a[rng.randi_range(0, a.size() - 1)]
