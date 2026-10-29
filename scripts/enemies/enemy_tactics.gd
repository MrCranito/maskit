class_name EnemyTactics
extends RefCounted
## Tactique des ennemis (logique pure, testable sans scène) :
##  - carte des couverts d'un étage (cases praticables voisines d'un obstacle : mur, rocher,
##    train, chariot, caisse, tonneau…), construite une fois par FloorLayout et mise en cache ;
##  - choix d'un couvert : l'obstacle doit se trouver entre la case et le joueur, à bonne distance
##    du joueur, pas trop loin de l'ennemi, et non réservé par un allié ;
##  - flanquement : côté (-1, 0, +1) attribué selon le rang parmi les ennemis engagés ;
##  - zigzag, déplacement latéral (strafe), points de patrouille (points d'intérêt de la salle).
## Réglages : balance.cfg [enemy_tactics].

const SECTION := "enemy_tactics"


## Carte des couverts d'un étage.
class CoverMap:
	extends RefCounted
	## Centre (monde) de chaque case de couvert.
	var points: PackedVector2Array = PackedVector2Array()
	## Direction (unitaire) de la case vers l'obstacle voisin (moyenne si plusieurs).
	var obstacle_dirs: PackedVector2Array = PackedVector2Array()
	## Obstacles voisins (bits : 1 gauche, 2 droite, 4 haut, 8 bas).
	var masks: PackedByteArray = PackedByteArray()
	## Seau (Vector2i) → PackedInt32Array d'indices, pour les requêtes locales.
	var buckets: Dictionary = {}
	var bucket_size: float = 256.0
	## Indice de couvert → id d'instance de l'ennemi qui l'occupe.
	var claims: Dictionary = {}

	func size() -> int:
		return points.size()

	func add(p: Vector2, obstacle_dir: Vector2, mask: int = 0) -> void:
		var i := points.size()
		points.append(p)
		obstacle_dirs.append(obstacle_dir)
		masks.append(mask)
		var b := Vector2i(floori(p.x / bucket_size), floori(p.y / bucket_size))
		var arr: PackedInt32Array = buckets.get(b, PackedInt32Array())
		arr.append(i)
		buckets[b] = arr

	## Indices des couverts dans le carré de demi-côté `radius` autour de `center`.
	func query(center: Vector2, radius: float, out: PackedInt32Array) -> void:
		out.clear()
		var b0 := Vector2i(floori((center.x - radius) / bucket_size), floori((center.y - radius) / bucket_size))
		var b1 := Vector2i(floori((center.x + radius) / bucket_size), floori((center.y + radius) / bucket_size))
		for bx: int in range(b0.x, b1.x + 1):
			for by: int in range(b0.y, b1.y + 1):
				var arr: Variant = buckets.get(Vector2i(bx, by))
				if arr != null:
					out.append_array(arr as PackedInt32Array)

	func claim(index: int, who: int) -> void:
		release(who)
		if index >= 0:
			claims[index] = who

	func release(who: int) -> void:
		for k: Variant in claims.keys():
			if int(claims[k]) == who:
				claims.erase(k)

	func is_claimed_by_other(index: int, who: int) -> bool:
		return claims.has(index) and int(claims[index]) != who


static var _layout_ref: WeakRef = null
static var _map: CoverMap = null
## Couche d'essai : force une carte de couverts (tests).
static var override_map: CoverMap = null
static var _query_buf: PackedInt32Array = PackedInt32Array()


static func cfg_f(key: String, def: float) -> float:
	return Balance.get_float(SECTION, key, def)


# --- Carte des couverts ------------------------------------------------------------

## Carte de l'étage courant (LootManager.current_layout()), construite au premier appel.
static func current_map() -> CoverMap:
	if override_map != null:
		return override_map
	var layout: FloorLayout = null
	var lm := _loot_manager()
	if lm != null and lm.has_method("current_layout"):
		layout = lm.call("current_layout") as FloorLayout
	if layout == null:
		return null
	if _map != null and _layout_ref != null and _layout_ref.get_ref() == layout:
		return _map
	_map = build_map(layout)
	_layout_ref = weakref(layout)
	return _map


static func _loot_manager() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(^"LootManager") if ml != null else null


## Construit la carte des couverts : cases praticables (FLOOR/STREET) voisines (4-connexité)
## d'une case obstacle (WALL, VOID, décor ou conteneur qui bloque).
static func build_map(layout: FloorLayout) -> CoverMap:
	var m := CoverMap.new()
	if layout == null:
		return m
	var blocked := {}
	for sp: FloorLayout.Spawn in layout.prop_spawns:
		if _prop_blocks(sp.kind):
			for c: Vector2i in FloorLayout.spawn_cells(sp):
				blocked[c] = true
	for sp2: FloorLayout.Spawn in layout.container_spawns:
		for c2: Vector2i in FloorLayout.spawn_cells(sp2):
			blocked[c2] = true
	var dirs: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for y: int in layout.size.y:
		for x: int in layout.size.x:
			var c3 := Vector2i(x, y)
			var t := layout.get_tile(c3)
			if not (t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET) or blocked.has(c3):
				continue
			var acc := Vector2.ZERO
			var n := 0
			var mask := 0
			for k: int in dirs.size():
				var q := c3 + dirs[k]
				if _is_obstacle(layout, q, blocked):
					acc += Vector2(dirs[k])
					n += 1
					mask |= 1 << k
			if n == 0 or n >= 3:
				continue  # pas d'obstacle, ou cul-de-sac (piège)
			m.add(FloorLayout.cell_to_world(c3), acc.normalized() if acc.length_squared() > 0.01 else Vector2(dirs[0]), mask)
	return m


static func _is_obstacle(layout: FloorLayout, c: Vector2i, blocked: Dictionary) -> bool:
	if blocked.has(c):
		return true
	if not layout.in_bounds(c):
		return false
	var t := layout.get_tile(c)
	return t == FloorLayout.Tile.WALL or t == FloorLayout.Tile.VOID


static func _prop_blocks(kind: StringName) -> bool:
	if WorldProp.DEFS.has(kind):
		var d: Dictionary = WorldProp.DEFS[kind]
		return d.get("block", Vector2.ZERO) != Vector2.ZERO
	return true


## Meilleur couvert pour un ennemi en `from` face à `threat` (indice dans `map`, ou -1) :
##  - l'obstacle est du côté de la menace (dot(obstacle_dir, vers la menace) ≥ cover_min_dot) ;
##  - distance à la menace dans [min_d, max_d] ; trajet depuis `from` ≤ max_travel ;
##  - non réservé par un autre ennemi ; score = trajet court + distance idéale.
static func find_cover(map: CoverMap, from: Vector2, threat: Vector2, min_d: float, max_d: float,
		max_travel: float, who: int = 0) -> int:
	var out := PackedInt32Array()
	find_covers(map, from, threat, min_d, max_d, max_travel, who, 1, out)
	return out[0] if not out.is_empty() else -1


const _DIRS4: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]


## Alignement (produit scalaire) du meilleur obstacle voisin de la case `i` avec `dir`.
static func cover_alignment(map: CoverMap, i: int, dir: Vector2) -> float:
	var mask := int(map.masks[i]) if i < map.masks.size() else 0
	if mask == 0:
		return map.obstacle_dirs[i].dot(dir)
	var best := -1.0
	for k: int in 4:
		if mask & (1 << k):
			best = maxf(best, _DIRS4[k].dot(dir))
	return best


## Les `count` meilleurs couverts (indices, meilleur d'abord) dans `out`. Voir find_cover.
static func find_covers(map: CoverMap, from: Vector2, threat: Vector2, min_d: float, max_d: float,
		max_travel: float, who: int, count: int, out: PackedInt32Array) -> void:
	out.clear()
	if map == null or map.size() == 0:
		return
	var min_dot := cfg_f("cover_min_dot", 0.75)
	map.query(from, max_travel, _query_buf)
	var scores := PackedFloat32Array()
	var ideal := (min_d + max_d) * 0.5
	for i: int in _query_buf:
		var p := map.points[i]
		var travel := from.distance_to(p)
		if travel > max_travel:
			continue
		var to_threat := threat - p
		var dt := to_threat.length()
		if dt < min_d or dt > max_d or dt < 1.0:
			continue
		if cover_alignment(map, i, to_threat / dt) < min_dot:
			continue
		if map.is_claimed_by_other(i, who):
			continue
		# Pas de couvert qui oblige à passer devant le joueur (trajet dirigé vers la menace).
		var score := travel + absf(dt - ideal) * 0.5
		if travel > 40.0 and (p - from).normalized().dot((threat - from).normalized()) > 0.85 \
				and from.distance_to(threat) < dt + travel * 0.5:
			score += 400.0
		# Insertion triée (count est petit).
		var k := out.size()
		while k > 0 and scores[k - 1] > score:
			k -= 1
		if k < count:
			out.insert(k, i)
			scores.insert(k, score)
			if out.size() > count:
				out.resize(count)
				scores.resize(count)


# --- Flanquement, zigzag, strafe ---------------------------------------------------------

## Côté de flanquement d'après le rang `index` parmi `count` ennemis engagés :
## le premier attaque de face (0), puis alternance +1 / -1.
static func flank_side(index: int, count: int) -> int:
	if count <= 1 or index <= 0:
		return 0
	return 1 if index % 2 == 1 else -1


## Point de contournement : autour du joueur, à `dist`, décalé de side × angle depuis l'axe
## joueur → ennemi.
static func flank_point(self_pos: Vector2, player_pos: Vector2, side: int, dist: float, angle_deg: float) -> Vector2:
	var axis := self_pos - player_pos
	if axis.length_squared() < 1.0:
		axis = Vector2.RIGHT
	return player_pos + axis.normalized().rotated(deg_to_rad(angle_deg) * float(side)) * dist


## Décalage latéral (px) du zigzag à l'instant t.
static func zigzag_offset(t: float, period: float, amplitude: float) -> float:
	if amplitude <= 0.0 or period <= 0.0:
		return 0.0
	# Triangle (changements de cap nets, plus lisibles qu'une sinusoïde).
	var ph := fposmod(t / period, 1.0)
	return amplitude * (4.0 * absf(ph - 0.5) - 1.0)


## Facteur latéral du zigzag (±, relatif à la direction d'avance) à l'instant t, pour une
## course à `speed` px/s : alterne nettement de côté toutes les demi-périodes.
static func zigzag_lateral(t: float, period: float, amplitude: float, speed: float) -> float:
	if amplitude <= 0.0 or period <= 0.0:
		return 0.0
	var ph := fposmod(t / period, 1.0)
	return (1.0 if ph < 0.5 else -1.0) * clampf(4.0 * amplitude / period / maxf(speed, 1.0), 0.0, 1.2)


## Direction de course en zigzag vers `target` (unitaire).
static func zigzag_dir(self_pos: Vector2, target: Vector2, t: float, period: float, amplitude: float) -> Vector2:
	var to := target - self_pos
	var d := to.length()
	if d < 1.0:
		return Vector2.ZERO
	var fwd := to / d
	if amplitude <= 0.0 or d < amplitude * 1.2:
		return fwd
	# Pente du triangle : ±4A/P par période, ramenée à une vitesse latérale relative.
	var ph := fposmod(t / period, 1.0)
	var lat := (1.0 if ph < 0.5 else -1.0) * clampf(4.0 * amplitude / maxf(period, 0.05) / 260.0, 0.0, 1.2)
	return (fwd + Vector2(-fwd.y, fwd.x) * lat).normalized()


## Point de déplacement latéral (tourne autour du joueur à distance constante).
static func strafe_point(self_pos: Vector2, player_pos: Vector2, side: int, step: float) -> Vector2:
	var axis := self_pos - player_pos
	if axis.length_squared() < 1.0:
		axis = Vector2.RIGHT
	var r := axis.length()
	var ang := step / maxf(r, 1.0) * float(side if side != 0 else 1)
	return player_pos + axis.rotated(ang)


## Point de recul (s'éloigne du joueur de `dist`).
static func retreat_point(self_pos: Vector2, player_pos: Vector2, dist: float) -> Vector2:
	var away := self_pos - player_pos
	if away.length_squared() < 1.0:
		away = Vector2.DOWN
	return self_pos + away.normalized() * dist


# --- Patrouille ----------------------------------------------------------------------

## Points d'intérêt de patrouille autour de `spawn` : cases de couvert (près des obstacles,
## décors, portes) de la même salle, à moins de `radius`. Repli : points sur un cercle.
static func patrol_points(spawn: Vector2, radius: float, count: int, rng: RandomNumberGenerator,
		map: CoverMap = null, room_rect: Rect2 = Rect2()) -> PackedVector2Array:
	var out := PackedVector2Array()
	if radius <= 0.0 or count <= 0:
		return out
	if map != null and map.size() > 0:
		map.query(spawn, radius, _query_buf)
		var cand := PackedVector2Array()
		for i: int in _query_buf:
			var p := map.points[i]
			if p.distance_to(spawn) <= radius and p.distance_to(spawn) > 40.0 \
					and (room_rect.size == Vector2.ZERO or room_rect.has_point(p)):
				cand.append(p)
		while out.size() < count and not cand.is_empty():
			var k := rng.randi_range(0, cand.size() - 1)
			out.append(cand[k])
			cand.remove_at(k)
	while out.size() < count:
		var a := rng.randf() * TAU
		out.append(spawn + Vector2.from_angle(a) * radius * sqrt(rng.randf_range(0.25, 1.0)))
	return out
