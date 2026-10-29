extends RefCounted
## Aménagement des pièces par gabarits (commun aux quatre biomes), déterministe par seed.
##
## Un gabarit = liste d'étapes (dictionnaires) exécutées dans l'ordre pour une salle :
##   along   : meubles adossés à un mur (dos au mur, orientés vers la salle) ;
##   island  : meubles isolés (grille régulière centrée, allées autour) ;
##   rows    : rangées (bancs d'église, bureaux, rayonnages, sièges) séparées par des allées ;
##   beside  : objet accolé à un meuble déjà posé (chevet, coffre au pied du lit, tonneau…) ;
##   corner  : objets dans les coins ;
##   pillars : piliers (cases de mur isolées : abris pour les combats) ;
##   stalls  : cloisons perpendiculaires à un mur (stalles, cabines, alcôves) ;
##   divider : cloison traversante percée d'ouvertures (guichets, vitrage) ;
##   booth   : petite pièce annexe dans un coin, ouverte d'une case ;
##   decal   : détails au sol non bloquants (tapis, papiers, paille, rails…) ;
##   art     : décors muraux (cadres, affiches, appliques) sur les faces de murs visibles.
## Garanties (testées) : rien de bloquant sur une case réservée (portes, escaliers, spawn,
## extraction et leurs abords) ni sur les allées de circulation (plus court chemin entre les
## entrées de la salle) ; chaque case bloquée préserve la connexité (anneau 3×3 connexe) et
## laisse un voisin libre à chaque conteneur / cachette.
##
## Paramètres communs d'une étape : "n" (int ou [min, max]), "chance" (0..1),
## "min_room" ([largeur, hauteur] minimales de la salle), "tag" (nomme les meubles posés).

const T := FloorLayout.Tile
const TS := 64.0
const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const SIDES := {&"n": Vector2i.UP, &"s": Vector2i.DOWN, &"e": Vector2i.RIGHT, &"w": Vector2i.LEFT}


class Ctx:
	var L: FloorLayout
	var blocked: Dictionary          ## partagé avec le peupleur (cases bloquées)
	var reserved: Dictionary         ## partagé (cases interdites aux objets bloquants)
	var enemy_cells: Dictionary
	var room_of: PackedInt32Array
	## kind → {"block": Vector2 (collision, unités monde), "tall": bool, "flat": bool}
	var defs: Dictionary = {}
	var has_container: Callable      ## kind → bool (conteneurs du monde)
	var occupied: Dictionary = {}    ## cases prises par un décor non bloquant
	var access: Dictionary = {}      ## conteneurs / cachettes : doivent garder un voisin libre
	var lane: Dictionary = {}        ## allées de circulation (évitées par le mobilier mural)
	var gate: Dictionary = {}        ## abords stricts des portes / escaliers (toujours libres)
	var tall_wall: Dictionary = {}   ## cases de mur masquées par un meuble haut
	var furnished: Dictionary = {}   ## room_id → nombre d'éléments posés par le gabarit
	var templates: Dictionary = {}   ## rôle → gabarit ({"steps", "loot", "hide"})
	var rcs: Dictionary = {}         ## room_id → RoomCtx des salles aménagées
	## Grille d'opacité (WALL / VOID = 1), tenue à jour avec les cloisons (accès rapide).
	var opq: PackedByteArray = PackedByteArray()

	func idx(p: Vector2i) -> int:
		return p.y * L.size.x + p.x


class RoomCtx:
	var r: FloorLayout.Room
	var rng: RandomNumberGenerator
	var tags: Dictionary = {}        ## tag → Array de Rect2i
	var entries: Array[Vector2i] = []
	var corners: Array[Vector2i] = []   ## cache de corner_cells (invalidé par les cloisons)
	var corners_ok: bool = false
	var wall_cells: Array[Vector2i] = []  ## cache des cases contre un mur (best_wall_cell)
	var wall_ok: bool = false


static func make_ctx(L: FloorLayout, blocked: Dictionary, reserved: Dictionary, enemy_cells: Dictionary,
		room_of: PackedInt32Array, defs: Dictionary, has_container: Callable) -> Ctx:
	var c := Ctx.new()
	c.L = L
	c.blocked = blocked
	c.reserved = reserved
	c.enemy_cells = enemy_cells
	c.room_of = room_of
	c.defs = defs
	c.has_container = has_container
	c.opq.resize(L.size.x * L.size.y)
	for i in L.tiles.size():
		var t := L.tiles[i]
		c.opq[i] = 1 if t == T.WALL or t == T.VOID else 0
	return c


# --- Intégration dans un peupleur ----------------------------------------------------------
## Usage (après réservations et index des salles, avant conteneurs / cachettes / ennemis) :
##   c.fur = Fur.make_ctx(L, c.blocked, c.reserved, c.enemy_cells, c.room_of, defs, world.has_container)
##   Fur.prepare(c.fur, TEMPLATES, seed_value, "biome")   # aménage les salles intérieures à gabarit
##   … dans _furnish : `if Fur.templated(c.fur, room): return` (déjà aménagée)
##   … conteneurs : Fur.loot(c.fur, room, L.container_spawns, n, pick, firsts, "loot")
##   … cachettes : Fur.loot(c.fur, room, L.hiding_spot_spawns, 1, pick, [kind], "hide")
##   … placement aléatoire restant : Fur.keeps(c.fur, p) au lieu du test d'anneau local, et
##     c.fur.access[p] = true pour chaque conteneur / cachette posé.

## Aménage toutes les salles intérieures dont le rôle (tags[0]) a un gabarit. Les entrées et
## allées de toutes ces salles sont calculées avant tout meuble.
static func prepare(c: Ctx, templates: Dictionary, seed_value: int, salt: String) -> void:
	c.templates = templates
	var order: Array[int] = []
	for room in c.L.rooms:
		if room.tags.is_empty() or not templates.has(StringName(room.tags[0])):
			continue
		if room.outdoor and not bool((templates[StringName(room.tags[0])] as Dictionary).get("outdoor", false)):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, salt, c.L.floor_index, room.id, "layout"])
		c.rcs[room.id] = room_ctx(c, room, rng)
		order.append(room.id)
	for rid in order:
		compute_lanes(c, c.rcs[rid])
	for rid2 in order:
		var rc: RoomCtx = c.rcs[rid2]
		furnish(c, rc, (templates[StringName(rc.r.tags[0])] as Dictionary).get("steps", []))


static func templated(c: Ctx, room: FloorLayout.Room) -> bool:
	return c != null and c.rcs.has(room.id)


## Conteneurs (key "loot") ou cachettes (key "hide") d'une salle aménagée, aux emplacements du
## gabarit. Renvoie le nombre posé.
static func loot(c: Ctx, room: FloorLayout.Room, list: Array[FloorLayout.Spawn], n: int, pick: Callable, firsts: Array, key: String) -> int:
	var rc: RoomCtx = c.rcs[room.id]
	var tpl: Dictionary = c.templates[StringName(room.tags[0])]
	var def_slots: Array = [{"mode": "corner"}] if key == "hide" else []
	return place_loot(c, rc, list, n, pick, tpl.get(key, def_slots), firsts)


# --- Prédicats ----------------------------------------------------------------------

static func opaque(c: Ctx, p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= c.L.size.x or p.y >= c.L.size.y:
		return true
	return c.opq[p.y * c.L.size.x + p.x] == 1


static func passable(c: Ctx, p: Vector2i) -> bool:
	return FloorLayout.is_walkable_tile(c.L.get_tile(p)) and not c.blocked.has(p)


## Case utilisable par un objet de la salle (bloquant ou non).
static func usable(c: Ctx, rc: RoomCtx, p: Vector2i, allow_lane: bool = false) -> bool:
	var w := c.L.size.x
	if p.x < 0 or p.y < 0 or p.x >= w or p.y >= c.L.size.y:
		return false
	var i := p.y * w + p.x
	if c.room_of[i] != rc.r.id:
		return false
	var t := c.L.tiles[i]
	if t != T.FLOOR and t != T.STREET:
		return false
	if c.blocked.has(p) or c.reserved.has(p) or c.enemy_cells.has(p) or c.occupied.has(p) or c.gate.has(p):
		return false
	return allow_lane or not c.lane.has(p)


## Anneau 3×3 autour d'une case, dans l'ordre (dx, dy) ; deux cases de l'anneau sont voisines
## (4-voisinage) si elles diffèrent d'une unité sur un seul axe.
const RING: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
## Table précalculée : masque des cases praticables de l'anneau (8 bits) → connexes entre elles.
static var _ring_ok: PackedByteArray = PackedByteArray()


static func _ring_table() -> PackedByteArray:
	if not _ring_ok.is_empty():
		return _ring_ok
	_ring_ok.resize(256)
	for m in 256:
		var first := -1
		for i in 8:
			if m & (1 << i):
				first = i
				break
		if first < 0:
			_ring_ok[m] = 0
			continue
		var seen := 1 << first
		var stack: Array[int] = [first]
		while not stack.is_empty():
			var i2: int = stack.pop_back()
			for j in 8:
				if (m & (1 << j)) == 0 or (seen & (1 << j)) != 0:
					continue
				var d := RING[i2] - RING[j]
				if absi(d.x) + absi(d.y) == 1:
					seen |= 1 << j
					stack.append(j)
		_ring_ok[m] = 1 if seen == m else 0
	return _ring_ok


## Bloquer p préserve la connexité locale (anneau 3×3) et l'accès aux conteneurs voisins.
## (Version déroulée : appelée des milliers de fois par étage.)
static func keeps(c: Ctx, p: Vector2i) -> bool:
	var L := c.L
	var w := L.size.x
	var h := L.size.y
	var tiles := L.tiles
	var blocked := c.blocked
	var m := 0
	var bit := 1
	for dy in range(-1, 2):
		var y := p.y + dy
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var x := p.x + dx
			if x >= 0 and y >= 0 and x < w and y < h:
				var t := tiles[y * w + x]
				if (t == T.STREET or t == T.FLOOR or t == T.DOOR or t == T.STAIRS_UP or t == T.STAIRS_DOWN) \
						and not blocked.has(Vector2i(x, y)):
					m |= bit
			bit <<= 1
	if _ring_table()[m] == 0:
		return false
	if not c.access.is_empty():
		for d2 in DIRS:
			var a := p + d2
			if c.access.has(a) and not _has_free_neighbor(c, a, p):
				return false
	return true


static func _has_free_neighbor(c: Ctx, a: Vector2i, except: Vector2i) -> bool:
	for d in DIRS:
		var n := a + d
		if n != except and passable(c, n):
			return true
	return false


## Bloque les cases dans l'ordre ; annule tout si l'une casse la connexité.
static func commit(c: Ctx, cells: Array[Vector2i]) -> bool:
	if cells.size() > 1:
		return _commit_rect(c, cells)
	var done: Array[Vector2i] = []
	for p in cells:
		if not keeps(c, p):
			for q in done:
				c.blocked.erase(q)
			return false
		c.blocked[p] = true
		done.append(p)
	return true


## Bloc de plusieurs cases (rectangle) : les cases praticables de l'anneau qui l'entoure
## restent connexes entre elles en passant par l'anneau (équivalent du test 3×3 pour un
## objet d'une case), et chaque conteneur voisin garde un accès.
static func _commit_rect(c: Ctx, cells: Array[Vector2i]) -> bool:
	var lo := cells[0]
	var hi := cells[0]
	for p in cells:
		lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
		hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
	var r := Rect2i(lo, hi - lo + Vector2i.ONE)
	var inside := {}
	for p0 in cells:
		inside[p0] = true
	# Anneau (ordre circulaire) autour du rectangle.
	var g := r.grow(1)
	var ring: Array[Vector2i] = []
	for x in range(g.position.x, g.end.x):
		ring.append(Vector2i(x, g.position.y))
	for y in range(g.position.y + 1, g.end.y):
		ring.append(Vector2i(g.end.x - 1, y))
	for x2 in range(g.end.x - 2, g.position.x - 1, -1):
		ring.append(Vector2i(x2, g.end.y - 1))
	for y2 in range(g.end.y - 2, g.position.y, -1):
		ring.append(Vector2i(g.position.x, y2))
	var free := {}
	for q in ring:
		if passable(c, q):
			free[q] = true
	if free.is_empty():
		return false
	# Composantes de l'anneau en 4-voisinage (restreint à l'anneau).
	var start: Vector2i = free.keys()[0]
	var seen := {start: true}
	var stack: Array[Vector2i] = [start]
	while not stack.is_empty():
		var q2: Vector2i = stack.pop_back()
		for d in DIRS:
			var n := q2 + d
			if free.has(n) and not seen.has(n):
				seen[n] = true
				stack.append(n)
	if seen.size() != free.size():
		return false
	for p1 in cells:
		c.blocked[p1] = true
	# Accès des conteneurs voisins.
	for q3 in ring:
		if c.access.has(q3) and not _has_free_neighbor(c, q3, Vector2i(-99999, -99999)):
			for p2 in cells:
				c.blocked.erase(p2)
			return false
	return true


static func rect_cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out


## Emprise libre ; `pad` : anneau autour sans autre objet (les murs sont tolérés).
static func fits(c: Ctx, rc: RoomCtx, r: Rect2i, pad: int = 0, allow_lane: bool = false) -> bool:
	# Version déroulée de usable() sur l'emprise (appelée très souvent).
	var L := c.L
	var w := L.size.x
	if r.position.x < 0 or r.position.y < 0 or r.end.x > w or r.end.y > L.size.y:
		return false
	var rid := rc.r.id
	var tiles := L.tiles
	var room_of := c.room_of
	var blocked := c.blocked
	var reserved := c.reserved
	var enemy := c.enemy_cells
	var occ := c.occupied
	var gate := c.gate
	var lane := c.lane
	for y0 in range(r.position.y, r.end.y):
		for x0 in range(r.position.x, r.end.x):
			var i := y0 * w + x0
			if room_of[i] != rid:
				return false
			var t := tiles[i]
			if t != T.FLOOR and t != T.STREET:
				return false
			var p := Vector2i(x0, y0)
			if blocked.has(p) or reserved.has(p) or enemy.has(p) or occ.has(p) or gate.has(p):
				return false
			if not allow_lane and lane.has(p):
				return false
	if pad > 0:
		var g := r.grow(pad)
		for y in range(g.position.y, g.end.y):
			for x in range(g.position.x, g.end.x):
				var q := Vector2i(x, y)
				if r.has_point(q):
					continue
				if blocked.has(q) or occ.has(q):
					return false
	return true


## Emprise touchant le mur `side` sur toute sa longueur.
static func against(c: Ctx, r: Rect2i, side: StringName) -> bool:
	match side:
		&"n":
			for x in range(r.position.x, r.end.x):
				if not opaque(c, Vector2i(x, r.position.y - 1)):
					return false
		&"s":
			for x in range(r.position.x, r.end.x):
				if not opaque(c, Vector2i(x, r.end.y)):
					return false
		&"e":
			for y in range(r.position.y, r.end.y):
				if not opaque(c, Vector2i(r.end.x, y)):
					return false
		&"w":
			for y in range(r.position.y, r.end.y):
				if not opaque(c, Vector2i(r.position.x - 1, y)):
					return false
	return true


# --- Définitions de décors ------------------------------------------------------------

static func def_of(c: Ctx, kind: StringName) -> Dictionary:
	return c.defs.get(kind, {})


static func known(c: Ctx, kind: StringName) -> bool:
	return c.defs.has(kind)


static func block_of(c: Ctx, kind: StringName) -> Vector2:
	return def_of(c, kind).get("block", Vector2(40, 16))


## Emprise (cases) d'un décor : déduite de sa collision, ou "fp" de sa définition.
static func footprint(c: Ctx, kind: StringName) -> Vector2i:
	var d := def_of(c, kind)
	if d.has("fp"):
		return d["fp"]
	var b: Vector2 = d.get("block", Vector2(40, 16))
	return Vector2i(maxi(1, ceili((b.x - 8.0) / TS)), maxi(1, ceili((b.y - 8.0) / TS)))


static func is_blocking(c: Ctx, kind: StringName) -> bool:
	return block_of(c, kind) != Vector2.ZERO


## Point d'appui (monde) d'un décor posé dans l'emprise `r`, adossé au mur `side`
## (&"" = centré). La collision (rectangle `block` posé au-dessus du point d'appui, ou centré
## sur lui si "centered") touche le mur à `gap` près.
static func anchor_pos(c: Ctx, kind: StringName, r: Rect2i, side: StringName) -> Vector2:
	var d := def_of(c, kind)
	var b := block_of(c, kind)
	if b == Vector2.ZERO:
		b = d.get("visual", Vector2(28, 16))
	var gap := float(d.get("gap", 3.0))
	var ctr := (Vector2(r.position) + Vector2(r.size) * 0.5) * TS
	match side:
		&"n":
			ctr.y = float(r.position.y) * TS + gap + b.y * 0.5
		&"s":
			ctr.y = float(r.end.y) * TS - gap - b.y * 0.5
		&"e":
			ctr.x = float(r.end.x) * TS - gap - b.x * 0.5
		&"w":
			ctr.x = float(r.position.x) * TS + gap + b.x * 0.5
	ctr += d.get("nudge", Vector2.ZERO)
	# La collision reste dans l'emprise logique (cases réservées au meuble) : le décalage
	# visuel (nudge) et l'adossement ne doivent jamais empiéter sur une case voisine (allée).
	var area := Rect2(Vector2(r.position) * TS, Vector2(r.size) * TS).grow(-1.0)
	var half := b * 0.5
	if half.x * 2.0 <= area.size.x:
		ctr.x = clampf(ctr.x, area.position.x + half.x, area.end.x - half.x)
	else:
		ctr.x = area.get_center().x
	if half.y * 2.0 <= area.size.y:
		ctr.y = clampf(ctr.y, area.position.y + half.y, area.end.y - half.y)
	else:
		ctr.y = area.get_center().y
	return ctr if bool(d.get("centered", false)) else ctr + Vector2(0.0, b.y * 0.5)


## Position standard d'un spawn (centre de case + 0,25 case vers le bas).
static func standard_pos(cell: Vector2i) -> Vector2:
	return FloorLayout.cell_to_world(cell) + Vector2(0.0, TS * 0.25)


# --- Émission -------------------------------------------------------------------------

static func place_prop(c: Ctx, rc: RoomCtx, kind: StringName, r: Rect2i, side: StringName, tag: String = "", allow_lane: bool = false) -> bool:
	if not fits(c, rc, r, 0, allow_lane):
		return false
	var cells := rect_cells(r)
	# Même un petit décor traversable (bougeoir, seau) compte comme occupant sa case pour la
	# connectivité : les tests (et les autres modules) traitent tout prop_spawn comme bloquant.
	if not commit(c, cells):
		return false
	var s := FloorLayout.Spawn.new()
	s.kind = kind
	s.room_id = rc.r.id
	s.size = r.size
	s.cell = Vector2i(r.position.x + (r.size.x - 1) / 2, r.end.y - 1)
	s.offset = anchor_pos(c, kind, r, side) - standard_pos(s.cell)
	c.L.prop_spawns.append(s)
	if tag != "":
		if not rc.tags.has(tag):
			rc.tags[tag] = []
		(rc.tags[tag] as Array).append(r)
	if not rc.tags.has("_all"):
		rc.tags["_all"] = []
	(rc.tags["_all"] as Array).append(r)
	if side == &"n" and bool(def_of(c, kind).get("tall", false)):
		for x in range(r.position.x, r.end.x):
			c.tall_wall[Vector2i(x, r.position.y - 1)] = true
	c.furnished[rc.r.id] = int(c.furnished.get(rc.r.id, 0)) + 1
	return true


static func place_container(c: Ctx, rc: RoomCtx, list: Array[FloorLayout.Spawn], kind: StringName, p: Vector2i) -> bool:
	if not usable(c, rc, p):
		return false
	# Le conteneur lui-même doit garder un accès.
	var free := false
	for d in DIRS:
		if passable(c, p + d) and p + d != p:
			free = true
	if not free or not keeps(c, p):
		return false
	c.blocked[p] = true
	# Après blocage : au moins un voisin praticable.
	if not _has_free_neighbor(c, p, p):
		c.blocked.erase(p)
		return false
	c.access[p] = true
	c.L.add_spawn(list, p, kind, rc.r.id)
	c.furnished[rc.r.id] = int(c.furnished.get(rc.r.id, 0)) + 1
	return true


static func add_decal(c: Ctx, rc: RoomCtx, piece: StringName, cell: Vector2i, offset: Vector2 = Vector2.ZERO, rot: float = 0.0, flip: bool = false, scale: float = 1.0) -> void:
	var s := FloorLayout.Spawn.new()
	s.scale = scale
	s.kind = piece
	s.cell = cell
	s.room_id = rc.r.id
	s.offset = offset
	s.rot = rot
	s.flip = flip
	c.L.decor_spawns.append(s)


## Transforme des cases en murs (cloison) si la connexité est préservée ; tout ou rien.
static func place_walls(c: Ctx, rc: RoomCtx, cells: Array[Vector2i]) -> bool:
	for p in cells:
		if not usable(c, rc, p):
			return false
	if not commit(c, cells):
		return false
	for p2 in cells:
		c.blocked.erase(p2)
		c.L.set_tile(p2, T.WALL)
		c.opq[c.idx(p2)] = 1
		c.L.partition_cells[p2] = true
	rc.corners_ok = false
	rc.wall_ok = false
	c.furnished[rc.r.id] = int(c.furnished.get(rc.r.id, 0)) + 1
	return true


# --- Salle ------------------------------------------------------------------------------

static func room_ctx(c: Ctx, room: FloorLayout.Room, rng: RandomNumberGenerator) -> RoomCtx:
	var rc := RoomCtx.new()
	rc.r = room
	rc.rng = rng
	_compute_entries(c, rc)
	return rc


## Entrées de la salle (case intérieure devant chaque porte / escalier).
static func _compute_entries(c: Ctx, rc: RoomCtx) -> void:
	var L := c.L
	var id := rc.r.id
	var gates: Array[Vector2i] = []
	for d in L.doors:
		if d.room_a == id or d.room_b == id:
			gates.append(d.cell)
	for s in L.stairs:
		if rc.r.rect.grow(1).has_point(s.cell):
			gates.append(s.cell)
	for g in gates:
		for dir in DIRS:
			var e := g + dir
			if L.in_bounds(e) and c.room_of[c.idx(e)] == id and FloorLayout.is_walkable_tile(L.get_tile(e)) \
					and L.get_tile(e) != T.DOOR:
				if not rc.entries.has(e):
					rc.entries.append(e)
				# Abord : deux cases dans l'axe de la porte.
				var e2 := e + dir
				if L.in_bounds(e2) and c.room_of[c.idx(e2)] == id:
					c.gate[e2] = true
				c.gate[e] = true


## Allées : chemins les moins coûteux de la première entrée vers chacune des autres ; longer
## un mur coûte cher (les murs restent libres pour le mobilier, les allées passent au milieu).
static func compute_lanes(c: Ctx, rc: RoomCtx) -> void:
	if rc.entries.size() < 2:
		return
	var id := rc.r.id
	var R := rc.r.rect
	var W := R.size.x
	var H := R.size.y
	# Tableaux locaux sur l'emprise de la salle : coût (1, ou 4 contre un mur, -1 = interdit).
	var cost := PackedInt32Array()
	cost.resize(W * H)
	for y in H:
		for x in W:
			var p := Vector2i(R.position.x + x, R.position.y + y)
			if c.room_of[c.idx(p)] != id or not passable(c, p):
				cost[y * W + x] = -1
				continue
			var w := 1
			for d2 in DIRS:
				if opaque(c, p + d2):
					w = 4
					break
			cost[y * W + x] = w
	var dist := PackedInt32Array()
	dist.resize(W * H)
	dist.fill(1 << 29)
	var prev := PackedInt32Array()
	prev.resize(W * H)
	prev.fill(-1)
	var s0 := rc.entries[0] - R.position
	if s0.x < 0 or s0.y < 0 or s0.x >= W or s0.y >= H:
		return
	var si := s0.y * W + s0.x
	dist[si] = 0
	# Dijkstra à seaux (poids 1 ou 4).
	var buckets: Array = [PackedInt32Array([si])]
	var k := 0
	var offs: Array[Vector2i] = DIRS
	while k < buckets.size():
		var bucket: PackedInt32Array = buckets[k]
		var bi := 0
		while bi < bucket.size():
			var i := bucket[bi]
			bi += 1
			if dist[i] != k:
				continue
			var px := i % W
			var py := i / W
			for d in offs:
				var nx := px + d.x
				var ny := py + d.y
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var ni := ny * W + nx
				var cw := cost[ni]
				if cw < 0:
					continue
				var nd := k + cw
				if dist[ni] <= nd:
					continue
				dist[ni] = nd
				prev[ni] = i
				while buckets.size() <= nd:
					buckets.append(PackedInt32Array())
				var bk: PackedInt32Array = buckets[nd]
				bk.append(ni)
				buckets[nd] = bk
		k += 1
	for e_i in range(1, rc.entries.size()):
		var e := rc.entries[e_i] - R.position
		if e.x < 0 or e.y < 0 or e.x >= W or e.y >= H:
			continue
		var cur := e.y * W + e.x
		if prev[cur] < 0 and cur != si:
			continue
		while cur != si and cur >= 0:
			c.lane[R.position + Vector2i(cur % W, cur / W)] = true
			cur = prev[cur]
		c.lane[rc.entries[0]] = true


## Applique le gabarit `steps` à la salle.
static func furnish(c: Ctx, rc: RoomCtx, steps: Array) -> void:
	for st: Dictionary in steps:
		if st.has("chance") and rc.rng.randf() >= float(st["chance"]):
			continue
		if st.has("min_room"):
			var mr: Array = st["min_room"]
			if rc.r.rect.size.x < int(mr[0]) or rc.r.rect.size.y < int(mr[1]):
				continue
		if st.has("unless") and rc.tags.has(String(st["unless"])):
			continue
		if st.has("max_room"):
			var xr: Array = st["max_room"]
			if rc.r.rect.size.x > int(xr[0]) or rc.r.rect.size.y > int(xr[1]):
				continue
		match String(st.get("op", "")):
			"along":
				_op_along(c, rc, st)
			"island":
				_op_island(c, rc, st)
			"rows":
				_op_rows(c, rc, st)
			"beside":
				_op_beside(c, rc, st)
			"corner":
				_op_corner(c, rc, st)
			"pillars":
				_op_pillars(c, rc, st)
			"stalls":
				_op_stalls(c, rc, st)
			"divider":
				_op_divider(c, rc, st)
			"booth":
				_op_booth(c, rc, st)
			"decal":
				_op_decal(c, rc, st)
			"art":
				_op_art(c, rc, st)
			"fill":
				_op_fill(c, rc, st)
			"grid":
				_op_grid(c, rc, st)


static func _count(rc: RoomCtx, st: Dictionary, def: int = 1) -> int:
	var v: Variant = st.get("n", def)
	if v is Array:
		return rc.rng.randi_range(int(v[0]), int(v[1]))
	return int(v)


static func _sides(rc: RoomCtx, st: Dictionary) -> Array[StringName]:
	var s := String(st.get("side", "n"))
	var out: Array[StringName] = []
	match s:
		"any":
			out = [&"n", &"e", &"w", &"s"]
		"ew":
			out = [&"e", &"w"]
			if rc.rng.randf() < 0.5:
				out.reverse()
		"new":
			out = [&"n", &"e", &"w"]
		"ns":
			out = [&"n", &"s"]
		_:
			for ch in s:
				out.append(StringName(ch))
	return out


## Kind à utiliser contre le mur `side` (variantes « _e » / « _w » si connues).
static func _kind_for_side(c: Ctx, st: Dictionary, side: StringName) -> StringName:
	var kinds: Dictionary = st.get("kinds", {})
	if kinds.has(String(side)):
		return StringName(kinds[String(side)])
	var k: StringName = st.get("kind", &"")
	if side == &"e" or side == &"w":
		var v := StringName(String(k) + "_" + String(side))
		if known(c, v):
			return v
	return k


static func _pick(rc: RoomCtx, v: Variant) -> StringName:
	if v is Array:
		var a: Array = v
		return StringName(a[rc.rng.randi_range(0, a.size() - 1)])
	return StringName(v)


# --- along ---------------------------------------------------------------------------------
## kind | kinds{side: kind}, side ("n", "ew", "new", "any"…), n, where ("center", "ends", "end",
## "opposite"+of, "near"+of, "spread", "any"), pad, tag, lane (true : allées autorisées, non bloquant).

static func _op_along(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var n := _count(rc, st)
	if n <= 0:
		return
	var where := String(st.get("where", "any"))
	var tag := String(st.get("tag", ""))
	var pad := int(st.get("pad", 0))
	var end_dir := -1.0 if rc.rng.randf() < 0.5 else 1.0
	var placed := 0
	var R := rc.r.rect
	var ctr := Vector2(R.position) + Vector2(R.size) * 0.5
	for side in _sides(rc, st):
		if placed >= n:
			break
		var kind := _pick(rc, _kind_for_side(c, st, side)) if not (st.get("kind") is Array) else _pick(rc, st["kind"])
		if not known(c, kind):
			continue
		var fp := footprint(c, kind)
		var cands: Array[Rect2i] = []
		# Bande le long du mur demandé (les meubles adossés ne peuvent être qu'à cet endroit).
		var ys := range(R.position.y, R.end.y - fp.y + 1)
		var xs := range(R.position.x, R.end.x - fp.x + 1)
		match side:
			&"n":
				ys = [R.position.y]
			&"s":
				ys = [R.end.y - fp.y]
			&"w":
				xs = [R.position.x]
			&"e":
				xs = [R.end.x - fp.x]
		for y in ys:
			for x in xs:
				var r := Rect2i(x, y, fp.x, fp.y)
				if against(c, r, side) and fits(c, rc, r, pad):
					cands.append(r)
		if cands.is_empty():
			continue
		var keyed: Array = []
		for r2 in cands:
			var cc := Vector2(r2.position) + Vector2(r2.size) * 0.5
			var along_axis := cc.x if side == &"n" or side == &"s" else cc.y
			var mid := ctr.x if side == &"n" or side == &"s" else ctr.y
			var half := (R.size.x if side == &"n" or side == &"s" else R.size.y) * 0.5
			var score := rc.rng.randf() * 0.01
			match where:
				"center":
					score += absf(along_axis - mid)
				"ends":
					score += half - absf(along_axis - mid)
				"end":
					score += -(along_axis - mid) * end_dir
				"opposite", "near":
					var ref := _tag_center(rc, String(st.get("of", "")))
					if ref.x > -9000.0:
						var dist := cc.distance_to(ref)
						score += -dist if where == "opposite" else dist
				"spread":
					score += 0.0
				_:
					score += rc.rng.randf()
			keyed.append([score, r2])
		keyed.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		if where == "spread":
			placed += _spread(c, rc, keyed, n - placed, kind, side, tag, side == &"n" or side == &"s", int(st.get("every", 2)))
			continue
		for e: Array in keyed:
			if placed >= n:
				break
			var rr: Rect2i = e[1]
			if place_prop(c, rc, kind, rr, side, tag):
				placed += 1
				if st.has("kinds_seq"):
					kind = _pick(rc, st["kinds_seq"])
					if not known(c, kind) or footprint(c, kind) != fp:
						break


## Répartition régulière le long du mur (cibles équidistantes).
static func _spread(c: Ctx, rc: RoomCtx, keyed: Array, n: int, kind: StringName, side: StringName, tag: String, horiz: bool, every: int) -> int:
	var R := rc.r.rect
	var lo := float(R.position.x if horiz else R.position.y)
	var hi := float(R.end.x if horiz else R.end.y)
	# Positions le long du mur (calculées une fois).
	var pos: Array = []
	for e: Array in keyed:
		var r: Rect2i = e[1]
		pos.append(float(r.position.x) + float(r.size.x) * 0.5 if horiz else float(r.position.y) + float(r.size.y) * 0.5)
	var dead := PackedByteArray()
	dead.resize(keyed.size())
	var placed := 0
	var used: Array[float] = []
	for k in n:
		var target := lerpf(lo, hi, (float(k) + 0.5) / float(n))
		# Candidat valide le plus proche de la cible (recherche linéaire, sans tri).
		while true:
			var best := -1
			var bd := 1e9
			for i in keyed.size():
				if dead[i] == 1:
					continue
				var ok := true
				for u in used:
					if absf(u - float(pos[i])) < float(every):
						ok = false
						break
				if not ok:
					continue
				var d := absf(float(pos[i]) - target)
				if d < bd:
					bd = d
					best = i
			if best < 0:
				break
			dead[best] = 1
			if place_prop(c, rc, kind, keyed[best][1], side, tag):
				placed += 1
				used.append(float(pos[best]))
				break
	return placed


static func _tag_center(rc: RoomCtx, tag: String) -> Vector2:
	if not rc.tags.has(tag) or (rc.tags[tag] as Array).is_empty():
		return Vector2(-9999, -9999)
	var r: Rect2i = (rc.tags[tag] as Array)[0]
	return Vector2(r.position) + Vector2(r.size) * 0.5


# --- island ---------------------------------------------------------------------------------
## kind, n, spacing (cases libres entre deux îlots, 1), margin (distance aux murs, 1),
## where ("center", "north", "spread", "end"), tag.

static func _op_island(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var n := _count(rc, st)
	var kind := _pick(rc, st.get("kind", &""))
	if n <= 0 or not known(c, kind):
		return
	var fp := footprint(c, kind)
	var sp := int(st.get("spacing", 1))
	var margin := int(st.get("margin", 1))
	var where := String(st.get("where", "center"))
	var tag := String(st.get("tag", ""))
	var R := rc.r.rect
	var inner := R.grow(-margin)
	if inner.size.x < fp.x or inner.size.y < fp.y:
		return
	# Toutes les positions possibles, triées : centre d'abord (ou nord / un bout / hasard),
	# avec un léger alignement sur une grille de pas (fp + sp) pour des rangées régulières.
	var ctr := Vector2(R.position) + Vector2(R.size) * 0.5
	var end_dir := -1.0 if rc.rng.randf() < 0.5 else 1.0
	var step := fp + Vector2i(sp, sp)
	var cands: Array = []
	for y in range(inner.position.y, inner.end.y - fp.y + 1):
		for x in range(inner.position.x, inner.end.x - fp.x + 1):
			var r := Rect2i(x, y, fp.x, fp.y)
			var cc := Vector2(r.position) + Vector2(r.size) * 0.5
			var grid := 0.0 if (x - inner.position.x) % step.x == 0 and (y - inner.position.y) % step.y == 0 else 0.6
			var score := cc.distance_to(ctr) * 0.25 + grid + rc.rng.randf() * 0.3
			match where:
				"north":
					score = float(r.position.y) * 4.0 + absf(cc.x - ctr.x) * 0.2 + grid
				"end":
					score = -(cc.x - ctr.x) * end_dir + absf(cc.y - ctr.y) * 0.3 + grid
				"spread":
					score = grid + rc.rng.randf() * 2.0
			cands.append([score, r])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var placed := 0
	for e: Array in cands:
		if placed >= n:
			break
		var rr: Rect2i = e[1]
		if not _clear_of_walls(c, rr, margin):
			continue
		if fits(c, rc, rr, sp, true) and place_prop(c, rc, kind, rr, &"", tag, true):
			placed += 1


static func _clear_of_walls(c: Ctx, r: Rect2i, margin: int) -> bool:
	if margin <= 0:
		return true
	var g := r.grow(margin)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			if opaque(c, Vector2i(x, y)):
				return false
	return true


# --- rows -------------------------------------------------------------------------------------
## kind, axis ("x" : rangées horizontales ; "y" : colonnes), gap (entre deux objets d'une rangée, 0),
## row_gap (allée entre rangées, 1), margin [g, h, d, b], aisle (allée centrale, 0), max, tag.

static func _op_rows(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var kind := _pick(rc, st.get("kind", &""))
	if not known(c, kind):
		return
	var fp := footprint(c, kind)
	var horiz := String(st.get("axis", "x")) == "x"
	var gap := int(st.get("gap", 0))
	var row_gap := int(st.get("row_gap", 1))
	var aisle := int(st.get("aisle", 0))
	var mx := int(st.get("max", 99))
	var tag := String(st.get("tag", ""))
	var m: Array = st.get("margin", [1, 1, 1, 1])
	var R := rc.r.rect
	var U := Rect2i(R.position.x + int(m[0]), R.position.y + int(m[1]),
		R.size.x - int(m[0]) - int(m[2]), R.size.y - int(m[1]) - int(m[3]))
	if U.size.x < fp.x or U.size.y < fp.y:
		return
	# En repère local (a = le long d'une rangée, b = d'une rangée à l'autre).
	var la := U.size.x if horiz else U.size.y
	var lb := U.size.y if horiz else U.size.x
	var fa := fp.x if horiz else fp.y
	var fb := fp.y if horiz else fp.x
	var rows_n := (lb + row_gap) / (fb + row_gap)
	var b0 := (lb - (rows_n * (fb + row_gap) - row_gap)) / 2
	if bool(st.get("from_start", false)):
		b0 = 0
	var placed := 0
	for j in rows_n:
		var b := b0 + j * (fb + row_gap)
		var slots: Array[int] = []
		if aisle > 0:
			var mid := la / 2
			var left_end := mid - aisle / 2
			var right_start := left_end + aisle
			var a := left_end - fa
			while a >= 0:
				slots.append(a)
				a -= fa + gap
			var a2 := right_start
			while a2 + fa <= la:
				slots.append(a2)
				a2 += fa + gap
		else:
			var k := (la + gap) / (fa + gap)
			var a0 := (la - (k * (fa + gap) - gap)) / 2
			for i in k:
				slots.append(a0 + i * (fa + gap))
		for a3 in slots:
			if placed >= mx:
				return
			var r := Rect2i(U.position.x + a3, U.position.y + b, fp.x, fp.y) if horiz \
				else Rect2i(U.position.x + b, U.position.y + a3, fp.x, fp.y)
			# Les rangées définissent elles-mêmes leurs allées : seules les abords de portes
			# (gate) et la connexité (keeps) les contraignent.
			if place_prop(c, rc, kind, r, StringName(st.get("face", "")), tag, true):
				placed += 1


# --- beside -----------------------------------------------------------------------------------
## kind, of (tag), rel ("left", "right", "sides", "below", "above", "foot"), per, side (offset),
## cont (true : conteneur posé dans container_spawns / hiding_spot_spawns).

static func _op_beside(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var of := String(st.get("of", ""))
	if not rc.tags.has(of):
		return
	var per := _count(rc, st, 1)
	var rel := String(st.get("rel", "sides"))
	var side := StringName(st.get("side", ""))
	var tag := String(st.get("tag", ""))
	for A: Rect2i in (rc.tags[of] as Array).duplicate():
		var kind := _pick(rc, st.get("kind", &""))
		if not known(c, kind):
			return
		var fp := footprint(c, kind)
		var cands: Array[Rect2i] = []
		var lr := [Rect2i(A.position.x - fp.x, A.position.y, fp.x, fp.y), Rect2i(A.end.x, A.position.y, fp.x, fp.y)]
		if rc.rng.randf() < 0.5:
			lr.reverse()
		match rel:
			"left":
				cands = [Rect2i(A.position.x - fp.x, A.position.y, fp.x, fp.y)]
			"right":
				cands = [Rect2i(A.end.x, A.position.y, fp.x, fp.y)]
			"sides":
				for q: Rect2i in lr:
					cands.append(q)
			"below", "foot":
				cands = [Rect2i(A.position.x + (A.size.x - fp.x) / 2, A.end.y, fp.x, fp.y)]
				for dx in range(0, A.size.x - fp.x + 1):
					var q2 := Rect2i(A.position.x + dx, A.end.y, fp.x, fp.y)
					if not cands.has(q2):
						cands.append(q2)
			"above":
				cands = [Rect2i(A.position.x + (A.size.x - fp.x) / 2, A.position.y - fp.y, fp.x, fp.y)]
			"bottom_sides":
				for q3: Rect2i in lr:
					cands.append(Rect2i(q3.position.x, A.end.y - fp.y, fp.x, fp.y))
		var k := 0
		for r in cands:
			if k >= per:
				break
			var sd := side
			if side == &"auto":
				sd = &"n" if against(c, r, &"n") else (&"e" if against(c, r, &"e") else (&"w" if against(c, r, &"w") else &""))
			if place_prop(c, rc, kind, r, sd, tag):
				k += 1


# --- corner ------------------------------------------------------------------------------------

static func corner_cells(c: Ctx, rc: RoomCtx) -> Array[Vector2i]:
	if rc.corners_ok:
		return rc.corners.duplicate()
	var out: Array[Vector2i] = []
	var R := rc.r.rect
	var w := c.L.size.x
	var opq := c.opq
	# Les cases de la salle ne touchent jamais le bord de la grille (murs autour).
	for y in range(maxi(R.position.y, 1), mini(R.end.y, c.L.size.y - 1)):
		for x in range(maxi(R.position.x, 1), mini(R.end.x, w - 1)):
			var i := y * w + x
			if (opq[i - w] == 1 or opq[i + w] == 1) and (opq[i - 1] == 1 or opq[i + 1] == 1):
				out.append(Vector2i(x, y))
	rc.corners = out
	rc.corners_ok = true
	return out.duplicate()


static func _op_corner(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var n := _count(rc, st)
	var cells := corner_cells(c, rc)
	_shuffle(cells, rc.rng)
	# Coins nord d'abord (les objets y masquent moins l'action) ; tri stable par insertion.
	var north: Array[Vector2i] = []
	var south: Array[Vector2i] = []
	var mid_y := rc.r.rect.position.y + rc.r.rect.size.y / 2
	for q in cells:
		if q.y < mid_y:
			north.append(q)
		else:
			south.append(q)
	cells = north + south
	var placed := 0
	for p in cells:
		if placed >= n:
			return
		var kind := _pick(rc, st.get("kind", &""))
		if not known(c, kind) or footprint(c, kind) != Vector2i.ONE:
			continue
		var side: StringName = &"n" if opaque(c, p + Vector2i.UP) else &"s"
		if bool(def_of(c, kind).get("tall", false)) and side == &"s":
			continue
		if place_prop(c, rc, kind, Rect2i(p, Vector2i.ONE), side, String(st.get("tag", ""))):
			placed += 1


# --- Cloisons ------------------------------------------------------------------------------------

## Piliers : cases de mur isolées, disposées symétriquement (abris).
static func _op_pillars(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var n := _count(rc, st, 2)
	var R := rc.r.rect
	var ctr := R.position + R.size / 2
	var ax := maxi(2, R.size.x / 4)
	var ay := maxi(2, R.size.y / 4)
	var pts: Array[Vector2i] = []
	match n:
		1:
			pts = [ctr]
		2:
			if R.size.x >= R.size.y:
				pts = [ctr + Vector2i(-ax, 0), ctr + Vector2i(ax, 0)]
			else:
				pts = [ctr + Vector2i(0, -ay), ctr + Vector2i(0, ay)]
		_:
			pts = [ctr + Vector2i(-ax, -ay), ctr + Vector2i(ax, -ay), ctr + Vector2i(-ax, ay), ctr + Vector2i(ax, ay)]
	for p in pts:
		if not _clear_of_walls(c, Rect2i(p, Vector2i.ONE), 1):
			continue
		if fits(c, rc, Rect2i(p, Vector2i.ONE), 1):
			place_walls(c, rc, [p])


## Stalles : cloisons perpendiculaires au mur `side` ("n" / "s"), longueur `len`, espacées de
## `spacing` cases libres, à partir d'un bout de la salle. Chaque cloison est tout ou rien.
static func _op_stalls(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var R := rc.r.rect
	var side := StringName(st.get("side", "n"))
	var ln := int(st.get("len", 2))
	if st.has("len_rel"):
		ln = maxi(1, R.size.y - int(st["len_rel"]))
	var sp := int(st.get("spacing", 2))
	var mx := _count(rc, st, 9)
	var start := R.position.x + int(st.get("first", sp))
	var placed := 0
	var x := start
	while x < R.end.x - 1 and placed < mx:
		var cells: Array[Vector2i] = []
		for k in ln:
			var y := R.position.y + k if side == &"n" else R.end.y - 1 - k
			cells.append(Vector2i(x, y))
		var ok := against(c, Rect2i(cells[0], Vector2i.ONE), side)
		if ok and place_walls(c, rc, cells):
			placed += 1
			x += sp + 1
		else:
			x += 1


## Cloison traversante horizontale à mi-hauteur, percée d'ouvertures (les allées restent
## toujours ouvertes). `fill` : décor posé dans la cloison (comptoir de guichet) au lieu du mur.
static func _op_divider(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var R := rc.r.rect
	if R.size.y < 4:
		return
	var y := R.position.y + int(st.get("row", (R.size.y - 1) / 2))
	var fill := StringName(st.get("fill", ""))
	var openings := int(st.get("openings", 1))
	var cols: Array[int] = []
	for x in range(R.position.x, R.end.x):
		cols.append(x)
	# Ouvertures supplémentaires (hors allées) : au centre puis aux tiers.
	var forced := {}
	var mid := R.position.x + R.size.x / 2
	var cands_open: Array[int] = [mid, R.position.x + R.size.x / 4, R.position.x + 3 * R.size.x / 4]
	var lane_open := 0
	for x2 in cols:
		if c.lane.has(Vector2i(x2, y)):
			lane_open += 1
	for i in maxi(0, openings - lane_open):
		if i < cands_open.size():
			forced[cands_open[i]] = true
	var x := R.position.x
	var pieces := 0
	while x < R.end.x:
		var p := Vector2i(x, y)
		if forced.has(x) or not usable(c, rc, p):
			x += 1
			continue
		# Comptoir : emprise de `fill` si elle tient entre deux cases de mur.
		if fill != &"" and known(c, fill) and pieces % 2 == 1:
			var fp := footprint(c, fill)
			var r := Rect2i(x, y - fp.y + 1, fp.x, fp.y)
			var free := true
			for xx in range(x, x + fp.x):
				if forced.has(xx):
					free = false
			if free and place_prop(c, rc, fill, r, &"", String(st.get("tag", ""))):
				x += fp.x
				pieces += 1
				continue
		if place_walls(c, rc, [p]):
			pieces += 1
		x += 1


## Petite pièce annexe (intérieur w×h) dans un coin, fermée par deux cloisons en L avec une
## ouverture d'une case. "fill" : décor posé au fond de l'annexe ; tag "booth" = intérieur.
static func _op_booth(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var R := rc.r.rect
	var bw := int(st.get("w", 2))
	var bh := int(st.get("h", 2))
	if R.size.x < bw + 4 or R.size.y < bh + 3:
		return
	var corners: Array = [[R.position.x, true], [R.end.x - bw, false]]
	if rc.rng.randf() < 0.5:
		corners.reverse()
	for co: Array in corners:
		var x0: int = co[0]
		var west: bool = co[1]
		var inner := Rect2i(x0, R.position.y, bw, bh)
		var wx := x0 + bw if west else x0 - 1
		var walls: Array[Vector2i] = []
		for yy in range(R.position.y, R.position.y + bh + 1):
			walls.append(Vector2i(wx, yy))
		var row := R.position.y + bh
		var xs: Array[int] = []
		for xx in range(x0, x0 + bw):
			xs.append(xx)
		# Ouverture : case de la rangée la plus proche du centre de la salle.
		var open_x := xs[xs.size() - 1] if west else xs[0]
		for xx2 in xs:
			if xx2 != open_x:
				walls.append(Vector2i(xx2, row))
		var ok := true
		for p in rect_cells(inner):
			if not usable(c, rc, p):
				ok = false
		if not ok:
			continue
		if place_walls(c, rc, walls):
			if not rc.tags.has("booth"):
				rc.tags["booth"] = []
			(rc.tags["booth"] as Array).append(inner)
			var fill := _pick(rc, st.get("fill", &""))
			if fill != &"" and known(c, fill):
				var fr := Rect2i(x0 if west else x0 + bw - 1, R.position.y, 1, 1)
				place_prop(c, rc, fill, fr, &"n", "booth_fill")
			return


# --- grid -------------------------------------------------------------------------------------
## Remplit le CENTRE de la salle par un groupe répété en grille régulière centrée :
## kind (ou liste : alternance par nœud), spacing (allée entre groupes, 2), margin (distance aux
## murs, 2), pad (anneau libre autour de chaque groupe, 1), ratio (occupation cible de la salle,
## 0.22), max, tag. Les nœuds sont pris du centre vers l'extérieur ; un nœud occupé (pilier,
## îlot) est sauté. Les allées logiques (lanes) peuvent être couvertes : la connexité reste
## garantie par commit/keeps et l'anneau libre.

## [cases praticables de la salle (cloisons comprises), cases occupées].
static func room_occupancy(c: Ctx, rc: RoomCtx) -> Array[int]:
	var R := rc.r.rect
	var w := c.L.size.x
	var tot := 0
	var occ := 0
	for y in range(R.position.y, R.end.y):
		for x in range(R.position.x, R.end.x):
			var i := y * w + x
			if c.room_of[i] != rc.r.id:
				continue
			var p := Vector2i(x, y)
			if c.L.partition_cells.has(p):
				tot += 1
				occ += 1
			elif FloorLayout.is_walkable_tile(c.L.tiles[i]):
				tot += 1
				if c.blocked.has(p) or c.occupied.has(p):
					occ += 1
	return [tot, occ]


static func _op_grid(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var kinds: Array = st["kind"] if st.get("kind") is Array else [st.get("kind", &"")]
	var kind0 := StringName(kinds[0])
	if not known(c, kind0):
		return
	var fp := footprint(c, kind0)
	# Salle trop étroite pour le groupe : variante plus petite ("alt", ex. tabouret, bac).
	if st.has("alt") and (rc.r.rect.size.x < fp.x + 4 or rc.r.rect.size.y < fp.y + 4):
		var alt := StringName(st["alt"])
		if known(c, alt):
			kind0 = alt
			kinds = [alt]
			fp = footprint(c, alt)
	var sp := int(st.get("spacing", 2))
	var margin := int(st.get("margin", 2))
	var pad := int(st.get("pad", 1))
	var ratio := float(st.get("ratio", 0.22))
	var mx := int(st.get("max", 99))
	var tag := String(st.get("tag", "grid"))
	var R := rc.r.rect
	var inner := R.grow(-margin)
	# Salle étroite : marge réduite (au moins une case le long des murs).
	if inner.size.x < fp.x + 2 or inner.size.y < fp.y + 2:
		inner = R.grow(-1)
	if inner.size.x < fp.x or inner.size.y < fp.y:
		return
	var step := fp + Vector2i(sp, sp)
	# Densité cible mesurée sur la zone CENTRALE (inner) : les meubles muraux ne consomment
	# pas le budget du centre.
	var tot := 0
	var occ0 := 0
	var wq := c.L.size.x
	for yq in range(inner.position.y, inner.end.y):
		for xq in range(inner.position.x, inner.end.x):
			var iq := yq * wq + xq
			if c.room_of[iq] != rc.r.id:
				continue
			var pq := Vector2i(xq, yq)
			if c.L.partition_cells.has(pq):
				tot += 1
				occ0 += 1
			elif FloorLayout.is_walkable_tile(c.L.tiles[iq]):
				tot += 1
				if c.blocked.has(pq) or c.occupied.has(pq):
					occ0 += 1
	var budget := int(round(ratio * float(tot))) - occ0
	if budget <= 0:
		return
	# Plusieurs alignements de grille possibles (déphasages) : on garde celui qui accueille le
	# plus de groupes (essai sans rien poser), puis on pose du centre vers l'extérieur.
	var ctr := Vector2(R.position) + Vector2(R.size) * 0.5
	var best: Array = []
	for phy in mini(step.y, 2):
		for phx in mini(step.x, 2):
			var nodes: Array = []
			var y := inner.position.y + phy
			while y + fp.y <= inner.end.y:
				var x := inner.position.x + phx
				while x + fp.x <= inner.end.x:
					var r := Rect2i(x, y, fp.x, fp.y)
					if fits(c, rc, r, pad, true):
						nodes.append(r)
					x += step.x
				y += step.y
			if nodes.size() > best.size():
				best = nodes
	var keyed: Array = []
	for r2: Rect2i in best:
		keyed.append([(Vector2(r2.position) + Vector2(fp) * 0.5).distance_to(ctr), r2])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var placed := 0
	var used := 0
	for e: Array in keyed:
		if placed >= mx or used >= budget:
			return
		var rr: Rect2i = e[1]
		var kind := StringName(kinds[(rr.position.x / step.x + rr.position.y / step.y) % kinds.size()])
		if not known(c, kind) or footprint(c, kind) != fp:
			kind = kind0
		if fits(c, rc, rr, pad, true) and place_prop(c, rc, kind, rr, &"", tag, true):
			placed += 1
			used += fp.x * fp.y


# --- fill ---------------------------------------------------------------------------------------
## Densifie la salle jusqu'à `ratio` de cases occupées : petits meubles d'une case (kinds) contre
## les murs, de préférence à côté d'un meuble existant (groupes), jamais sur les allées.
## max : nombre maximal d'ajouts ; south (bool, défaut true) : autorise le mur sud.

static func occupancy(c: Ctx, rc: RoomCtx) -> float:
	var tot := 0
	var occ := 0
	for p in rect_cells(rc.r.rect):
		var t := c.L.get_tile(p)
		if c.room_of[c.idx(p)] != rc.r.id or not FloorLayout.is_walkable_tile(t):
			if c.L.partition_cells.has(p):
				occ += 1
				tot += 1
			continue
		tot += 1
		if c.blocked.has(p) or c.occupied.has(p):
			occ += 1
	return float(occ) / maxf(1.0, float(tot))


static func _op_fill(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var ratio := float(st.get("ratio", 0.14))
	var mx := int(st.get("max", 8))
	var south := bool(st.get("south", true))
	var kinds: Array = st.get("kinds", [])
	# Occupation calculée une fois, puis mise à jour à chaque ajout (une case par objet).
	var tot := 0
	var occ := 0
	for p0 in rect_cells(rc.r.rect):
		if c.room_of[c.idx(p0)] != rc.r.id:
			continue
		var t0 := c.L.get_tile(p0)
		if c.L.partition_cells.has(p0):
			tot += 1
			occ += 1
		elif FloorLayout.is_walkable_tile(t0):
			tot += 1
			if c.blocked.has(p0) or c.occupied.has(p0):
				occ += 1
	var want := int(ceil(ratio * float(tot))) - occ
	var n := mini(mx, want)
	if n <= 0:
		return
	var cands := _wall_candidates(c, rc, south)
	var ci := 0
	var k := 0
	while k < n and ci < cands.size():
		var p: Vector2i = cands[ci]
		ci += 1
		if not usable(c, rc, p) or not keeps(c, p):
			continue
		var kind := _pick(rc, kinds)
		if not known(c, kind) or footprint(c, kind) != Vector2i.ONE:
			k += 1
			continue
		var side: StringName = &"n" if opaque(c, p + Vector2i.UP) else (&"w" if opaque(c, p + Vector2i.LEFT) else (&"e" if opaque(c, p + Vector2i.RIGHT) else &"s"))
		if place_prop(c, rc, kind, Rect2i(p, Vector2i.ONE), side, String(st.get("tag", "fill"))):
			k += 1


# --- Décors au sol ---------------------------------------------------------------------------
## piece (ou liste), mode : "center", "under"+of, "near"+of, "scatter", "aisle", "lane", "entry",
## "rails" ; n, jitter (unités monde), rot (radians ou "auto"), min_room.

static func _op_decal(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var mode := String(st.get("mode", "center"))
	var n := _count(rc, st)
	var R := rc.r.rect
	var jit := float(st.get("jitter", 0.0))
	match mode:
		"center":
			var ctr := (Vector2(R.position) + Vector2(R.size) * 0.5) * TS
			var cell := Vector2i(int(ctr.x / TS), int(ctr.y / TS))
			add_decal(c, rc, _pick(rc, st["piece"]), cell, ctr - FloorLayout.cell_to_world(cell), _rot(rc, st), false, float(st.get("scale", 1.0)))
		"under":
			var of := String(st.get("of", ""))
			if not rc.tags.has(of):
				return
			var k := 0
			for A: Rect2i in rc.tags[of]:
				if k >= n:
					break
				var shift_v: Vector2 = st.get("shift", Vector2.ZERO)
				var cw := (Vector2(A.position) + Vector2(A.size) * 0.5) * TS + shift_v
				var cell2 := Vector2i(int(cw.x / TS), int(cw.y / TS))
				add_decal(c, rc, _pick(rc, st["piece"]), cell2, cw - FloorLayout.cell_to_world(cell2), _rot(rc, st), false, float(st.get("scale", 1.0)))
				k += 1
		"near":
			var of2 := String(st.get("of", ""))
			if not rc.tags.has(of2):
				return
			for A2: Rect2i in rc.tags[of2]:
				var ring: Array[Vector2i] = []
				var g := A2.grow(1)
				for p in rect_cells(g):
					if not A2.has_point(p) and c.room_of[c.idx(p)] == rc.r.id and not c.blocked.has(p) \
							and FloorLayout.is_walkable_tile(c.L.get_tile(p)):
						ring.append(p)
				_shuffle(ring, rc.rng)
				for i in mini(n, ring.size()):
					add_decal(c, rc, _pick(rc, st["piece"]), ring[i], _jit(rc, jit), _rot(rc, st), rc.rng.randf() < 0.5)
		"scatter":
			var cells: Array[Vector2i] = []
			for p2 in rect_cells(R):
				if c.room_of[c.idx(p2)] == rc.r.id and c.L.get_tile(p2) == c.L.get_tile(R.get_center()) \
						and not c.blocked.has(p2) and FloorLayout.is_walkable_tile(c.L.get_tile(p2)):
					cells.append(p2)
			_shuffle(cells, rc.rng)
			for i2 in mini(n, cells.size()):
				add_decal(c, rc, _pick(rc, st["piece"]), cells[i2], _jit(rc, jit), _rot(rc, st), rc.rng.randf() < 0.5)
		"aisle":
			# Chemin de tapis le long de l'axe long, au centre de la salle.
			var horiz := R.size.x > R.size.y
			if bool(st.get("vertical", false)):
				horiz = false
			var fixed := R.position.y + R.size.y / 2 if horiz else R.position.x + R.size.x / 2
			var odd := (R.size.y if horiz else R.size.x) % 2 == 0
			var shift := Vector2(0, -TS * 0.5) if horiz and odd else (Vector2(-TS * 0.5, 0) if odd else Vector2.ZERO)
			var a0 := (R.position.x if horiz else R.position.y) + int(st.get("skip_start", 0))
			var a1 := (R.end.x if horiz else R.end.y) - int(st.get("skip_end", 0))
			for a in range(a0, a1):
				var p3 := Vector2i(a, fixed) if horiz else Vector2i(fixed, a)
				if c.blocked.has(p3) or not FloorLayout.is_walkable_tile(c.L.get_tile(p3)):
					continue
				add_decal(c, rc, _pick(rc, st["piece"]), p3, shift, PI * 0.5 if horiz else 0.0)
		"lane":
			for p4: Vector2i in c.lane:
				if c.room_of[c.idx(p4)] == rc.r.id:
					add_decal(c, rc, _pick(rc, st["piece"]), p4, Vector2.ZERO, _rot(rc, st))
		"entry":
			for e in rc.entries:
				add_decal(c, rc, _pick(rc, st["piece"]), e, Vector2.ZERO, 0.0)
		"rails":
			_rails(c, rc, st)


static func _rot(rc: RoomCtx, st: Dictionary) -> float:
	var v: Variant = st.get("rot", 0.0)
	if v is String and v == "random":
		return rc.rng.randf() * TAU
	if v is String and v == "quarter":
		return float(rc.rng.randi_range(0, 3)) * PI * 0.5
	return float(v)


static func _jit(rc: RoomCtx, j: float) -> Vector2:
	if j <= 0.0:
		return Vector2.ZERO
	return Vector2(rc.rng.randf_range(-j, j), rc.rng.randf_range(-j, j))


## Rails : chemin entre les entrées (ou du centre vers l'entrée), segments orientés.
static func _rails(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	var piece := StringName(st.get("piece", "prop_rail_track"))
	var R := rc.r.rect
	var horiz := R.size.x >= R.size.y
	var fixed := R.position.y + R.size.y / 2 if horiz else R.position.x + R.size.x / 2
	var a0 := R.position.x if horiz else R.position.y
	var a1 := R.end.x if horiz else R.end.y
	for a in range(a0, a1):
		var p := Vector2i(a, fixed) if horiz else Vector2i(fixed, a)
		if c.blocked.has(p) or not FloorLayout.is_walkable_tile(c.L.get_tile(p)) or c.room_of[c.idx(p)] != rc.r.id:
			continue
		add_decal(c, rc, piece, p, Vector2.ZERO, 0.0 if horiz else PI * 0.5)
	if not rc.tags.has("rails"):
		rc.tags["rails"] = []
	(rc.tags["rails"] as Array).append(Rect2i(Vector2i(a0, fixed), Vector2i(a1 - a0, 1)) if horiz else Rect2i(Vector2i(fixed, a0), Vector2i(1, a1 - a0)))


# --- Décors muraux ------------------------------------------------------------------------------

## Faces de murs visibles de la salle (mur dont la case au sud est dans la salle), hors abords
## de portes / escaliers et hors murs masqués par un meuble haut.
static func wall_faces(c: Ctx, rc: RoomCtx, near_gates: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var R := rc.r.rect.grow(1)
	# Une face visible est au-dessus d'une case de la salle : seules les rangées de murs du
	# pourtour et des cloisons sont candidates (on parcourt les cases de la salle).
	for y in range(R.position.y, R.end.y - 1):
		for x in range(R.position.x, R.end.x):
			var w := Vector2i(x, y)
			if c.L.get_tile(w) != T.WALL:
				continue
			var s := w + Vector2i.DOWN
			if not c.L.in_bounds(s) or c.room_of[c.idx(s)] != rc.r.id:
				continue
			var ts := c.L.get_tile(s)
			if ts != T.FLOOR and ts != T.STREET:
				continue
			if c.tall_wall.has(w) or c.L.wall_decor_cells.has(w):
				continue
			var near_gate := false
			for dx in range(-1, 2):
				var tt := c.L.get_tile(w + Vector2i(dx, 0))
				var tb := c.L.get_tile(w + Vector2i(dx, 1))
				if tt == T.DOOR or tb == T.STAIRS_UP or tb == T.STAIRS_DOWN or tb == T.DOOR:
					near_gate = true
			if near_gates or not near_gate:
				out.append(w)
	return out


## pieces (liste), density (part des faces décorées, 0.35), max, above (tag : une pièce
## centrée au-dessus de chaque meuble tagué, "above_piece").
static func _op_art(c: Ctx, rc: RoomCtx, st: Dictionary) -> void:
	if st.has("behind"):
		# Murs qui séparent cette salle d'une salle de rôle donné (barreaux des cellules) : la
		# face visible est celle du côté sud du mur, quelle que soit la salle qui s'y trouve.
		var role := String(st["behind"])
		var R := rc.r.rect.grow(1)
		for x in range(R.position.x, R.end.x):
			for y in [R.position.y, R.end.y - 1]:
				var w := Vector2i(x, y)
				if c.L.get_tile(w) != T.WALL:
					continue
				var up := w + Vector2i.UP
				var dn := w + Vector2i.DOWN
				if not c.L.in_bounds(up) or not c.L.in_bounds(dn) or not FloorLayout.is_walkable_tile(c.L.get_tile(dn)):
					continue
				var ra := c.room_of[c.idx(up)]
				var rb := c.room_of[c.idx(dn)]
				var other := rb if ra == rc.r.id else (ra if rb == rc.r.id else -1)
				var orr := c.L.get_room(other) if other >= 0 else null
				if orr != null and orr.tags.size() > 0 and orr.tags[0] == role:
					c.L.wall_decor_cells[w] = StringName(st["piece"])
		return
	if st.has("above"):
		var of := String(st["above"])
		if rc.tags.has(of):
			for A: Rect2i in rc.tags[of]:
				var w := Vector2i(A.position.x + (A.size.x - 1) / 2, A.position.y - 1)
				if c.L.get_tile(w) == T.WALL and not c.L.wall_decor_cells.has(w):
					c.L.wall_decor_cells[w] = _pick(rc, st["piece"])
		return
	var faces := wall_faces(c, rc)
	var dens := float(st.get("density", 0.35))
	var mx := int(st.get("max", 99))
	var pieces: Array = st.get("pieces", [])
	if pieces.is_empty():
		return
	var placed := 0
	var last := Vector2i(-99, -99)
	var k := rc.rng.randi_range(0, pieces.size() - 1)
	for w2 in faces:
		if placed >= mx:
			return
		if w2.y == last.y and absi(w2.x - last.x) < 2:
			continue
		if rc.rng.randf() >= dens:
			continue
		c.L.wall_decor_cells[w2] = StringName(pieces[k % pieces.size()])
		k += 1 + (1 if rc.rng.randf() < 0.3 else 0)
		last = w2
		placed += 1


# --- Butin : conteneurs et cachettes --------------------------------------------------------------

## Pose `n` conteneurs : d'abord aux emplacements du gabarit (slots), puis contre un mur à côté
## d'un meuble (ou dans un coin). `pick` : Callable() → kind (tirage pondéré du peupleur).
## Slots : {"mode": "beside", "of": tag, "rel": "foot"|"sides"|"below", "kinds": [...]},
## {"mode": "corner"}, {"mode": "in", "of": tag}, {"mode": "along", "side": "n"}.
static func place_loot(c: Ctx, rc: RoomCtx, list: Array[FloorLayout.Spawn], n: int, pick: Callable, slots: Array = [], first_kinds: Array = []) -> int:
	var placed := 0
	var used_slots := 0
	for sl: Dictionary in slots:
		if placed >= n:
			break
		var kind := StringName(first_kinds[placed]) if placed < first_kinds.size() else StringName(pick.call())
		if sl.has("kinds"):
			var ks: Array = []
			for k2: Variant in sl["kinds"]:
				if c.has_container.call(StringName(k2)):
					ks.append(k2)
			if not ks.is_empty() and placed >= first_kinds.size():
				kind = StringName(ks[rc.rng.randi_range(0, ks.size() - 1)])
		for p in _slot_cells(c, rc, sl):
			if place_container(c, rc, list, kind, p):
				placed += 1
				used_slots += 1
				break
	while placed < n:
		var kind2 := StringName(first_kinds[placed]) if placed < first_kinds.size() else StringName(pick.call())
		var p2 := best_wall_cell(c, rc)
		if p2.x < 0 or not place_container(c, rc, list, kind2, p2):
			break
		placed += 1
	return placed


static func _slot_cells(c: Ctx, rc: RoomCtx, sl: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match String(sl.get("mode", "")):
		"beside":
			var of := String(sl.get("of", ""))
			if not rc.tags.has(of):
				return out
			for A: Rect2i in rc.tags[of]:
				match String(sl.get("rel", "sides")):
					"foot", "below":
						for dx in A.size.x:
							out.append(Vector2i(A.position.x + dx, A.end.y))
					"sides":
						out.append(Vector2i(A.position.x - 1, A.end.y - 1))
						out.append(Vector2i(A.end.x, A.end.y - 1))
					"above":
						out.append(Vector2i(A.position.x + A.size.x / 2, A.position.y - 1))
		"corner":
			out = corner_cells(c, rc)
			_shuffle(out, rc.rng)
		"in":
			var of2 := String(sl.get("of", ""))
			if rc.tags.has(of2):
				for A2: Rect2i in rc.tags[of2]:
					for p in rect_cells(A2):
						out.append(p)
		"along":
			var side := StringName(sl.get("side", "n"))
			for p2 in rect_cells(rc.r.rect):
				if opaque(c, p2 + SIDES[side]):
					out.append(p2)
			_shuffle(out, rc.rng)
	return out


## Meilleure case contre un mur pour un objet d'une case : à côté d'un meuble ou d'une cloison
## (+4), dans un coin (+2), contre le mur nord (+1) ; hasard pour départager.
## Cases libres contre un mur, triées par intérêt : à côté d'un meuble ou d'une cloison (+4),
## dans un coin (+2), contre le mur nord (+1), loin d'un conteneur (-5 par voisin), hasard.
static func _wall_candidates(c: Ctx, rc: RoomCtx, south: bool = true) -> Array[Vector2i]:
	if not rc.wall_ok:
		rc.wall_cells.clear()
		var R := rc.r.rect
		var w0 := c.L.size.x
		var opq := c.opq
		for y in range(maxi(R.position.y, 1), mini(R.end.y, c.L.size.y - 1)):
			for x in range(maxi(R.position.x, 1), mini(R.end.x, w0 - 1)):
				var i0 := y * w0 + x
				if opq[i0 - 1] == 1 or opq[i0 + 1] == 1 or opq[i0 - w0] == 1 or opq[i0 + w0] == 1:
					rc.wall_cells.append(Vector2i(x, y))
		rc.wall_ok = true
	var scored: Array = []
	for p in rc.wall_cells:
		if not usable(c, rc, p):
			continue
		var walls := 0
		var furn := 0
		var cont := 0
		for d in DIRS:
			if opaque(c, p + d):
				walls += 1
				if c.L.partition_cells.has(p + d):
					furn += 1
			elif c.access.has(p + d):
				cont += 1
			elif c.blocked.has(p + d):
				furn += 1
		if walls == 0:
			continue
		if not south and walls == 1 and opaque(c, p + Vector2i.DOWN):
			continue
		var s := rc.rng.randf()
		s += 4.0 if furn > 0 else 0.0
		s -= 5.0 * float(cont)
		s += 2.0 if walls >= 2 else 0.0
		s += 1.0 if opaque(c, p + Vector2i.UP) else 0.0
		s -= 1.5 if opaque(c, p + Vector2i.DOWN) and not opaque(c, p + Vector2i.UP) else 0.0
		scored.append([s, p])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
	var out: Array[Vector2i] = []
	for e: Array in scored:
		out.append(e[1])
	return out


## Meilleure case contre un mur pour un objet d'une case (voir _wall_candidates).
static func best_wall_cell(c: Ctx, rc: RoomCtx, south: bool = true) -> Vector2i:
	for p in _wall_candidates(c, rc, south):
		# Évite les cases sans issue une fois bloquées.
		if keeps(c, p):
			return p
	return Vector2i(-1, -1)


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t
