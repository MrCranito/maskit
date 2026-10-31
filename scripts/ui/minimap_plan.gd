class_name MinimapPlan
extends Node2D
## Plan vectoriel d'un étage sans image pré-rendue (étages −1 / +1 de la station, mine, saloon…),
## pour la mini-carte et la carte plein écran : pièces et rues en aplats, murs en traits nets
## anti-crénelés, portes en barrettes, escaliers en marches. En coordonnées monde (1 case =
## FloorLayout.TILE_SIZE) : la vue le met à l'échelle, il reste net à tous les zooms.
## Performance : la géométrie (rectangles fusionnés, segments de murs fusionnés) est calculée
## UNE fois par étage (MinimapPlan.Geometry, partagée entre mini-carte et carte plein écran) ;
## le nœud n'est dessiné qu'à son entrée dans l'arbre (commandes de dessin gardées par le
## moteur), jamais à chaque image ; aucune Image n'est créée.
## Couleurs et épaisseurs : balance.cfg [minimap] plan_*.

const TS := float(FloorLayout.TILE_SIZE)

## Nombre d'appels à _draw (tests : pas de redessin par image).
var draw_count: int = 0
var geometry: Geometry = null


static func create(geom: Geometry) -> MinimapPlan:
	var p := MinimapPlan.new()
	p.name = "Plan"
	p.geometry = geom
	return p


func _draw() -> void:
	draw_count += 1
	if geometry == null:
		return
	var g := geometry
	var col_street := _color("plan_street", Color(0.15, 0.17, 0.26))
	var col_floor := _color("plan_floor", Color(0.24, 0.25, 0.37))
	var col_wall := _color("plan_wall", Color(0.06, 0.065, 0.11))
	var col_edge := _color("plan_edge", Color(0.86, 0.88, 1.0, 0.7))
	var col_door := _color("plan_door", Color(0.718, 0.608, 1.0))
	var col_stairs := _color("plan_stairs", Color(0.55, 0.85, 1.0))
	var edge_w := Balance.get_float("minimap", "plan_edge_width", 0.12) * TS
	for r: Rect2 in g.street_rects:
		draw_rect(r, col_street)
	for r: Rect2 in g.floor_rects:
		draw_rect(r, col_floor)
	for r: Rect2 in g.wall_rects:
		draw_rect(r, col_wall)
	if g.edges.size() >= 2:
		# Segments prolongés d'une demi-épaisseur : angles des murs fermés (pas d'encoche).
		var ext := PackedVector2Array()
		ext.resize(g.edges.size())
		for i in range(0, g.edges.size() - 1, 2):
			var d := (g.edges[i + 1] - g.edges[i]).normalized() * edge_w * 0.5
			ext[i] = g.edges[i] - d
			ext[i + 1] = g.edges[i + 1] + d
		draw_multiline(ext, col_edge, edge_w, true)
	var door_t := Balance.get_float("minimap", "plan_door_thickness", 0.26) * TS
	for i in g.doors.size():
		var c := g.doors[i]
		var horiz := g.door_horizontal[i] == 1
		var center := (Vector2(c) + Vector2(0.5, 0.5)) * TS
		var half := Vector2(TS * 0.42, door_t * 0.5) if horiz else Vector2(door_t * 0.5, TS * 0.42)
		draw_rect(Rect2(center - half, half * 2.0), col_door)
	# Escaliers : aplat clair + trois marches (traits), plus marqués côté montée.
	for c: Vector2i in g.stairs:
		var r2 := Rect2(Vector2(c) * TS, Vector2(TS, TS)).grow(-TS * 0.08)
		draw_rect(r2, Color(col_stairs, 0.22))
		for k in 3:
			var y := r2.position.y + r2.size.y * (0.25 + 0.25 * k)
			var inset := r2.size.x * (0.12 + 0.08 * k)
			draw_line(Vector2(r2.position.x + inset, y), Vector2(r2.end.x - inset, y), col_stairs, edge_w * 0.9, true)


static func _color(key: String, def: Color) -> Color:
	var v: Variant = Balance.get_value("minimap", key, def)
	return v if v is Color else def


static func is_walkable(t: int) -> bool:
	return t == FloorLayout.Tile.STREET or t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.DOOR \
		or t == FloorLayout.Tile.STAIRS_UP or t == FloorLayout.Tile.STAIRS_DOWN


## Géométrie vectorielle d'un étage, calculée une fois (O(cases)).
class Geometry extends RefCounted:
	var size: Vector2i = Vector2i.ZERO
	var street_rects: Array[Rect2] = []
	var floor_rects: Array[Rect2] = []
	var wall_rects: Array[Rect2] = []
	## Segments de murs (paires de points, monde), fusionnés le long des lignes de la grille.
	var edges: PackedVector2Array = PackedVector2Array()
	var doors: Array[Vector2i] = []
	var door_horizontal: PackedByteArray = PackedByteArray()
	var stairs: Array[Vector2i] = []

	static func build(l: FloorLayout) -> Geometry:
		var g := Geometry.new()
		g.size = l.size
		g.street_rects = _merged_rects(l, 1)
		g.floor_rects = _merged_rects(l, 2)
		g.wall_rects = _merged_rects(l, 3)
		g._build_edges(l)
		for y in l.size.y:
			for x in l.size.x:
				var c := Vector2i(x, y)
				var t := l.get_tile(c)
				if t == FloorLayout.Tile.DOOR:
					g.doors.append(c)
					var wl := not MinimapPlan.is_walkable(l.get_tile(c + Vector2i.LEFT))
					var wr := not MinimapPlan.is_walkable(l.get_tile(c + Vector2i.RIGHT))
					var wu := not MinimapPlan.is_walkable(l.get_tile(c + Vector2i.UP))
					var wd := not MinimapPlan.is_walkable(l.get_tile(c + Vector2i.DOWN))
					# Barrette dans l'axe du mur : mur horizontal si murs à gauche et à droite.
					g.door_horizontal.append(0 if (wu and wd and not (wl and wr)) else 1)
				elif t == FloorLayout.Tile.STAIRS_UP or t == FloorLayout.Tile.STAIRS_DOWN:
					g.stairs.append(c)
		return g

	## Classe d'aplat d'une case : 1 rue, 2 intérieur (portes, escaliers compris), 3 mur, 0 rien.
	static func cls(t: int) -> int:
		match t:
			FloorLayout.Tile.STREET:
				return 1
			FloorLayout.Tile.FLOOR, FloorLayout.Tile.DOOR, FloorLayout.Tile.STAIRS_UP, FloorLayout.Tile.STAIRS_DOWN:
				return 2
			FloorLayout.Tile.WALL:
				return 3
		return 0

	## Rectangles d'une classe : segments par rangée, prolongés vers le bas s'ils sont identiques.
	static func _merged_rects(l: FloorLayout, want: int) -> Array[Rect2]:
		var out: Array[Rect2] = []
		var open := {}  # Vector2i(x0, x1) → indice dans out (rect encore extensible)
		for y in l.size.y:
			var next := {}
			var x := 0
			while x < l.size.x:
				if cls(l.get_tile(Vector2i(x, y))) != want:
					x += 1
					continue
				var x0 := x
				while x < l.size.x and cls(l.get_tile(Vector2i(x, y))) == want:
					x += 1
				var key := Vector2i(x0, x)
				if open.has(key):
					var i: int = open[key]
					out[i].size.y += TS
					next[key] = i
				else:
					out.append(Rect2(Vector2(x0, y) * TS, Vector2(x - x0, 1) * TS))
					next[key] = out.size() - 1
			open = next
		return out

	## Bords praticable / mur (ou vide) : segments unitaires fusionnés en longues lignes.
	func _build_edges(l: FloorLayout) -> void:
		edges = PackedVector2Array()
		# Horizontaux : lignes y = 0..h, côté haut (+0) ou bas (+1) d'une case praticable.
		for y in l.size.y + 1:
			for side in 2:
				var run := -1
				for x in l.size.x + 1:
					var on := false
					if x < l.size.x:
						var a := Vector2i(x, y - 1 + side)  # case praticable candidate
						var b := Vector2i(x, y - side)       # voisine de l'autre côté
						on = l.in_bounds(a) and MinimapPlan.is_walkable(l.get_tile(a)) \
							and not (l.in_bounds(b) and MinimapPlan.is_walkable(l.get_tile(b)))
					if on and run < 0:
						run = x
					elif not on and run >= 0:
						edges.append(Vector2(run, y) * TS)
						edges.append(Vector2(x, y) * TS)
						run = -1
		# Verticaux : lignes x = 0..w.
		for x in l.size.x + 1:
			for side in 2:
				var run := -1
				for y in l.size.y + 1:
					var on := false
					if y < l.size.y:
						var a := Vector2i(x - 1 + side, y)
						var b := Vector2i(x - side, y)
						on = l.in_bounds(a) and MinimapPlan.is_walkable(l.get_tile(a)) \
							and not (l.in_bounds(b) and MinimapPlan.is_walkable(l.get_tile(b)))
					if on and run < 0:
						run = y
					elif not on and run >= 0:
						edges.append(Vector2(x, run) * TS)
						edges.append(Vector2(x, y) * TS)
						run = -1
