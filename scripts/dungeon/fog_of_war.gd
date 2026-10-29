class_name FogOfWar
extends Node2D
## Brouillard atmosphérique permanent sur la grille d'un FloorLayout.
##
## Rendu : tout l'écran est sous une brume bleu nuit animée ; seule la zone que le
## joueur voit réellement (polygone de visibilité, bloqué par murs et portes
## fermées, atténué par un vignettage circulaire) est nette. Les zones explorées
## hors de vue retombent dans la brume : seul un très léger souvenir du décor
## transparaît ([fog] explored_memory_strength), ennemis et conteneurs y sont cachés.
##
## Logique (inchangée, sert à l'IA / la sauvegarde / les tests) : grille par case
##   0 = jamais vu, 1 = exploré hors vue, 2 = visible,
## calculée par shadowcasting récursif depuis la case du joueur (rayon [fog] view_radius).
## Opaques : WALL, VOID, porte fermée (via set_door_query). Depuis la rue, l'intérieur
## d'un bâtiment n'est visible qu'à courte portée ([fog] outdoor_interior_peek).
##
## Polygone de visibilité : rayons (DDA sur la grille) depuis la position monde
## exacte du joueur vers les coins des murs/portes vus (± epsilon) + un cercle de
## rayons ; un mur touché est révélé sur toute sa case (face 3/4 visible).
## Recalcul quand le joueur a bougé de plus de [fog] move_threshold_px ou après
## invalidate(), au plus [fog] max_updates_per_sec fois par seconde.
##
## Pipeline GPU : le polygone est dessiné (triangles en éventail, plusieurs passes
## décalées additives = bord adouci) dans un SubViewport couvrant toute la carte à
## basse résolution ([fog] mask_px_per_texel), rafraîchi UNIQUEMENT après un
## recalcul (UPDATE_ONCE). Le brouillard est un unique rectangle en espace monde
## (z 80) : il suit donc exactement la caméra (lissage, interpolation) sans décalage.
## Le shader fog_of_war.gdshader échantillonne 4 textures (masque, mémoire
## d'exploration 1 texel/case, bruit ×2), sans boucle.
##
## Branchement (raid) :
##   fog.setup(layout); fog.set_door_query(func(c): return porte_ouverte(c))
##   DoorNode.state_changed → fog.invalidate() ; chaque frame : fog.update_from(player.global_position)
##   changement d'étage : etat = fog.get_state() … plus tard fog.set_state(etat)

const SHADER: Shader = preload("res://assets/shaders/fog_of_war.gdshader")
const NOISE_PATH := "res://assets/textures/fog/fog_noise.png"
const GROUP_HIDEABLE := &"fog_hideable"
const GROUP_PLAYER := &"player"
const TS := float(FloorLayout.TILE_SIZE)
## Marge du rectangle de brouillard autour de la carte (monde, px).
const OUTER_MARGIN := 4096.0
## Décalage angulaire des rayons de part et d'autre d'un coin (rad).
const CORNER_EPS := 0.0009

## Octants du shadowcasting : (xx, xy, yx, yy).
const OCTANTS: Array[Vector4i] = [
	Vector4i(1, 0, 0, 1), Vector4i(0, 1, 1, 0), Vector4i(0, -1, 1, 0), Vector4i(-1, 0, 0, 1),
	Vector4i(-1, 0, 0, -1), Vector4i(0, -1, -1, 0), Vector4i(0, 1, -1, 0), Vector4i(1, 0, 0, -1),
]
## Décalages de flou du masque (unité = edge_feather_px) : centre + 2 anneaux.
const FEATHER_TAPS: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5),
	Vector2(0.71, 0.71), Vector2(-0.71, 0.71), Vector2(0.71, -0.71), Vector2(-0.71, -0.71),
	Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
]

# --- Réglages (balance.cfg [fog]) ---
var view_radius: int = 10
var outdoor_interior_peek: int = 4
## Durée du fondu d'apparition des entités (s).
var transition_time: float = 0.15
var hide_interval: float = 0.05
var debug_reveal_with_f3: bool = false
var max_updates_per_sec: float = 30.0
var move_threshold_px: float = 4.0
var circle_rays: int = 40
var edge_feather_px: float = 22.0
var mask_px_per_texel: float = 8.0
var reveal_roofs: bool = true

var layout: FloorLayout = null
## Durée du dernier recalcul (ms) : shadowcasting et/ou polygone (debug / tests).
var last_compute_ms: float = 0.0
## Durée du dernier calcul de polygone seul (ms).
var last_polygon_ms: float = 0.0
## Nombre de rayons lancés au dernier calcul de polygone.
var last_ray_count: int = 0

var _w: int = 0
var _h: int = 0
var _opaque: PackedByteArray = PackedByteArray()    ## 1 = bloque la vue
var _indoor: PackedByteArray = PackedByteArray()    ## 1 = case d'intérieur (sol de bâtiment)
var _explored: PackedByteArray = PackedByteArray()  ## 1 = déjà vue
var _visible: PackedByteArray = PackedByteArray()   ## 1 = visible maintenant
var _corner: PackedByteArray = PackedByteArray()    ## (w+1)*(h+1) : 1 = coin de géométrie opaque
var _visible_list: PackedInt32Array = PackedInt32Array()  ## capacité w*h, _vis_count utilisés
var _vis_count: int = 0
var _door_cells: Array[Vector2i] = []
var _door_open: PackedByteArray = PackedByteArray()
var _door_query: Callable = Callable()

# Polygone de visibilité (monde) et buffers réutilisés.
var _poly: PackedVector2Array = PackedVector2Array()
var _poly_origin: Vector2 = Vector2.ZERO
var _ray_angles: PackedFloat32Array = PackedFloat32Array()  ## capacité fixe, _ray_n utilisés
var _ray_n: int = 0
var _ray_keys: PackedInt64Array = PackedInt64Array()
var _fan_points: PackedVector2Array = PackedVector2Array()
var _fan_indices: PackedInt32Array = PackedInt32Array()
var _fan_colors: PackedColorArray = PackedColorArray()
var _roof_rects: Array[Rect2] = []
var _wall_rects: Array[Rect2] = []  ## Rangées de murs / portes fermées en vue (fusionnées)

# Rendu.
var _material: ShaderMaterial = null
var _mask_vp: SubViewport = null
var _mask_drawer: MaskDrawer = null
var _explored_image: Image = null
var _explored_tex: ImageTexture = null
var _explored_dirty: bool = false
var _noise_tex: Texture2D = null

var _last_cell: Vector2i = Vector2i(-99999, -99999)
var _has_origin: bool = false
var _dirty: bool = true
var _poly_dirty: bool = true
var _pending_pos: Vector2 = Vector2.ZERO
var _pending: bool = false
var _last_poly_usec: int = -1000000000
var _reveal_all: bool = false
var _hide_left: float = 0.0
var _fading: Dictionary = {}  ## CanvasItem → progression du fondu (0..1)
var _fade_done: Array = []
var _player_pos: Vector2 = Vector2.ZERO

# Variables de travail du shadowcasting.
var _ox: int = 0
var _oy: int = 0
var _r2: int = 0
var _peek2: int = 0
var _restrict_indoor: bool = false
var _new_vis: PackedInt32Array = PackedInt32Array()
var _new_count: int = 0
var _cast_ms: float = 0.0
var _stamp: PackedInt32Array = PackedInt32Array()  ## Génération du dernier marquage
var _gen: int = 0


## Dessine le polygone de visibilité (+ toits vus) dans le SubViewport du masque.
class MaskDrawer extends Node2D:
	var fog: FogOfWar = null

	func _draw() -> void:
		if fog != null:
			fog._draw_mask(self)


func _init() -> void:
	z_index = 80
	name = "FogOfWar"


func _ready() -> void:
	_load_balance()
	var bus: Node = _autoload(&"EventBus")
	if bus != null and bus.has_signal(&"debug_toggled"):
		bus.connect(&"debug_toggled", _on_debug_toggled)


# --- API publique ---------------------------------------------------------------

func setup(p_layout: FloorLayout) -> void:
	_load_balance()
	layout = p_layout
	_w = layout.size.x
	_h = layout.size.y
	var n := _w * _h
	_opaque = PackedByteArray()
	_opaque.resize(n)
	_indoor = PackedByteArray()
	_indoor.resize(n)
	_explored = PackedByteArray()
	_explored.resize(n)
	_visible = PackedByteArray()
	_visible.resize(n)
	_corner = PackedByteArray()
	_corner.resize((_w + 1) * (_h + 1))
	_visible_list = PackedInt32Array()
	_visible_list.resize(n)
	_new_vis = PackedInt32Array()
	_new_vis.resize(n)
	_vis_count = 0
	_new_count = 0
	_stamp = PackedInt32Array()
	_stamp.resize(n)
	_gen = 0
	_door_cells.clear()
	for d in layout.doors:
		_door_cells.append(d.cell)
	_door_open = PackedByteArray()
	_door_open.resize(_door_cells.size())
	_door_open.fill(255)
	_poly.clear()
	_fading.clear()
	_build_static_masks()
	_build_corners()
	_build_render()
	_last_cell = Vector2i(-99999, -99999)
	_has_origin = false
	_dirty = true
	_poly_dirty = true
	_pending = false
	queue_redraw()


## callable(cell: Vector2i) -> bool : true si la porte de cette case est ouverte.
func set_door_query(callable: Callable) -> void:
	_door_query = callable
	invalidate()


## Force un recalcul au prochain update_from (porte ouverte/fermée, etc.).
func invalidate() -> void:
	_dirty = true
	_poly_dirty = true


func update_from(world_pos: Vector2) -> void:
	if layout == null:
		return
	_player_pos = world_pos
	if _material != null:
		_material.set_shader_parameter(&"player_pos", world_pos)
	var cell := FloorLayout.world_to_cell(world_pos)
	var forced := _dirty or not _has_origin
	if cell != _last_cell or _dirty:
		_last_cell = cell
		_has_origin = true
		_dirty = false
		_recompute(cell)
	if forced or _poly_dirty:
		_poly_dirty = false
		_pending = false
		_compute_polygon(world_pos)
		return
	var moved := world_pos.distance_squared_to(_poly_origin) > move_threshold_px * move_threshold_px
	if not moved:
		_pending = false
		return
	# Téléportation (> 2 cases) : immédiat ; sinon cadence limitée.
	if world_pos.distance_squared_to(_poly_origin) > 4.0 * TS * TS or _poly_interval_elapsed():
		_pending = false
		_compute_polygon(world_pos)
	else:
		_pending = true
		_pending_pos = world_pos


func is_cell_visible(c: Vector2i) -> bool:
	if layout == null or not layout.in_bounds(c):
		return false
	return _reveal_all or _visible[c.y * _w + c.x] == 1


func is_cell_explored(c: Vector2i) -> bool:
	if layout == null or not layout.in_bounds(c):
		return false
	return _reveal_all or _explored[c.y * _w + c.x] == 1


## État logique d'une case : 0 jamais vu, 1 exploré hors vue, 2 visible.
func get_cell_state(c: Vector2i) -> int:
	if is_cell_visible(c):
		return 2
	return 1 if is_cell_explored(c) else 0


## Vrai si le point monde est dans le champ de vision (polygone + rayon de vue).
func is_world_point_visible(p: Vector2) -> bool:
	if _reveal_all:
		return true
	if _poly.size() < 3:
		return false
	var r := float(view_radius) * TS
	if p.distance_squared_to(_poly_origin) > r * r:
		return false
	return Geometry2D.is_point_in_polygon(p, _poly)


## Polygone de visibilité courant (monde). Ne pas modifier.
func get_visibility_polygon() -> PackedVector2Array:
	return _poly


func reveal_all(on: bool) -> void:
	if on == _reveal_all:
		return
	_reveal_all = on
	if _material != null:
		_material.set_shader_parameter(&"reveal", 1.0 if on else 0.0)
	_hide_left = 0.0


func is_revealing_all() -> bool:
	return _reveal_all


## Mémoire d'exploration de l'étage (1 octet par case : 1 = explorée).
func get_state() -> PackedByteArray:
	return _explored.duplicate()


func set_state(state: PackedByteArray) -> void:
	if layout == null:
		return
	if state.size() != _w * _h:
		push_warning("FogOfWar: état ignoré (taille %d, attendu %d)." % [state.size(), _w * _h])
		return
	for i in state.size():
		_explored[i] = 1 if state[i] != 0 else 0
	for k in _vis_count:
		_explored[_visible_list[k]] = 1
	_rebuild_explored_image()
	invalidate()


# --- Réglages -------------------------------------------------------------------

func _autoload(n: StringName) -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null(NodePath(String(n)))


func _cfg(key: String, default: Variant) -> Variant:
	var bal: Node = _autoload(&"Balance")
	if bal == null:
		return default
	return bal.call(&"get_value", "fog", key, default)


func _load_balance() -> void:
	view_radius = int(_cfg("view_radius", view_radius))
	outdoor_interior_peek = int(_cfg("outdoor_interior_peek", outdoor_interior_peek))
	transition_time = float(_cfg("transition_time", transition_time))
	hide_interval = float(_cfg("hide_interval", hide_interval))
	debug_reveal_with_f3 = bool(_cfg("debug_reveal_with_f3", debug_reveal_with_f3))
	max_updates_per_sec = maxf(float(_cfg("max_updates_per_sec", max_updates_per_sec)), 1.0)
	move_threshold_px = float(_cfg("move_threshold_px", move_threshold_px))
	circle_rays = maxi(int(_cfg("circle_rays", circle_rays)), 8)
	edge_feather_px = float(_cfg("edge_feather_px", edge_feather_px))
	mask_px_per_texel = maxf(float(_cfg("mask_px_per_texel", mask_px_per_texel)), 1.0)
	reveal_roofs = bool(_cfg("reveal_roofs", reveal_roofs))


func _apply_shader_params() -> void:
	if _material == null:
		return
	var m := _material
	m.set_shader_parameter(&"map_size_px", Vector2(_w, _h) * TS)
	m.set_shader_parameter(&"view_radius_px", float(view_radius) * TS)
	m.set_shader_parameter(&"fog_color", _cfg("fog_color", Color(0.035, 0.05, 0.11, 1.0)))
	m.set_shader_parameter(&"mist_color", _cfg("mist_color", Color(0.2, 0.25, 0.42, 1.0)))
	m.set_shader_parameter(&"unseen_alpha", float(_cfg("unseen_alpha", 0.985)))
	m.set_shader_parameter(&"memory_strength", float(_cfg("explored_memory_strength", 0.12)))
	m.set_shader_parameter(&"mist_density", float(_cfg("mist_density", 0.55)))
	m.set_shader_parameter(&"mist_scale", float(_cfg("mist_scale", 900.0)))
	m.set_shader_parameter(&"mist_speed", float(_cfg("mist_speed", 14.0)))
	m.set_shader_parameter(&"edge_softness", float(_cfg("edge_softness", 0.22)))
	m.set_shader_parameter(&"edge_noise", float(_cfg("edge_noise", 0.35)))
	m.set_shader_parameter(&"vignette_start", float(_cfg("vignette_start", 0.55)))
	m.set_shader_parameter(&"penumbra_color", _cfg("penumbra_color", Color(0.06, 0.08, 0.2, 1.0)))
	m.set_shader_parameter(&"visible_haze", float(_cfg("visible_haze", 0.12)))
	m.set_shader_parameter(&"reveal", 1.0 if _reveal_all else 0.0)
	m.set_shader_parameter(&"player_pos", _player_pos)


func _on_debug_toggled(enabled: bool) -> void:
	if debug_reveal_with_f3:
		reveal_all(enabled)


# --- Grilles statiques ----------------------------------------------------------

func _build_static_masks() -> void:
	var T := FloorLayout.Tile
	for y in _h:
		for x in _w:
			var i := y * _w + x
			var t: int = layout.tiles[i]
			_opaque[i] = 1 if FloorLayout.is_opaque_tile(t) else 0
			# Intérieur : plancher / escaliers ; une rue n'est jamais un intérieur.
			_indoor[i] = 1 if (t == T.FLOOR or t == T.STAIRS_UP or t == T.STAIRS_DOWN) else 0
	# Tout ce qui est strictement dans l'enceinte d'un bâtiment (cloisons, portes
	# internes) est intérieur ; seuls les murs d'enceinte restent visibles de la rue.
	for b in layout.buildings:
		var inner := b.rect.grow(-1)
		for y in range(maxi(inner.position.y, 0), mini(inner.end.y, _h)):
			for x in range(maxi(inner.position.x, 0), mini(inner.end.x, _w)):
				var i := y * _w + x
				if layout.tiles[i] != T.STREET and layout.tiles[i] != T.VOID:
					_indoor[i] = 1
	# Les salles déclarées intérieures complètent (sols exotiques éventuels).
	for r in layout.rooms:
		if r.outdoor:
			continue
		for y in range(maxi(r.rect.position.y, 0), mini(r.rect.end.y, _h)):
			for x in range(maxi(r.rect.position.x, 0), mini(r.rect.end.x, _w)):
				var i := y * _w + x
				var t: int = layout.tiles[i]
				if t != T.WALL and t != T.VOID and t != T.DOOR and t != T.STREET:
					_indoor[i] = 1


func _is_opaque_xy(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return 1
	return _opaque[y * _w + x]


## Un sommet de grille est un « coin » si les 4 cases qui l'entourent ne forment
## ni un bloc uniforme ni un bord droit (1 ou 3 opaques, ou 2 en diagonale).
func _update_corner(vx: int, vy: int) -> void:
	if vx < 0 or vy < 0 or vx > _w or vy > _h:
		return
	var a := _is_opaque_xy(vx - 1, vy - 1)
	var b := _is_opaque_xy(vx, vy - 1)
	var c := _is_opaque_xy(vx - 1, vy)
	var d := _is_opaque_xy(vx, vy)
	var s := a + b + c + d
	var corner := s == 1 or s == 3 or (s == 2 and a == d)
	_corner[vy * (_w + 1) + vx] = 1 if corner else 0


func _build_corners() -> void:
	for vy in _h + 1:
		for vx in _w + 1:
			_update_corner(vx, vy)


## Met à jour l'opacité des portes ; ne recalcule les coins que des portes changées.
func _refresh_doors() -> void:
	for k in _door_cells.size():
		var c := _door_cells[k]
		var i := c.y * _w + c.x
		var open := true
		if _door_query.is_valid():
			open = bool(_door_query.call(c))
		else:
			var d := layout.get_door_at(c)
			open = d == null or d.state == FloorLayout.DoorState.OPEN
		var v := 1 if open else 0
		if _door_open[k] == v:
			continue
		_door_open[k] = v
		_opaque[i] = 0 if open else 1
		for dy in 2:
			for dx in 2:
				_update_corner(c.x + dx, c.y + dy)


# --- Calcul de vue logique (par case) ---------------------------------------------

func _recompute(origin: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	_refresh_doors()
	_new_count = 0
	_gen += 1
	if layout.in_bounds(origin):
		_ox = origin.x
		_oy = origin.y
		_r2 = view_radius * view_radius + view_radius  # cercle un peu arrondi
		_peek2 = outdoor_interior_peek * outdoor_interior_peek + outdoor_interior_peek
		# Joueur dehors (rue) : les intérieurs ne sont visibles qu'à courte portée.
		var oi := _oy * _w + _ox
		_restrict_indoor = _indoor[oi] == 0 and layout.tiles[oi] != FloorLayout.Tile.DOOR
		_mark(_ox, _oy, 0)
		for o in OCTANTS:
			_cast(1, 1.0, 0.0, o.x, o.y, o.z, o.w)
	for k in _vis_count:
		var j := _visible_list[k]
		if _stamp[j] != _gen:  # n'est plus visible
			_visible[j] = 0
	for k in _new_count:
		var i := _new_vis[k]
		_visible[i] = 1
		if _explored[i] == 0:
			_explored[i] = 1
			if _explored_image != null:
				_explored_image.set_pixel(i % _w, i / _w, Color(1, 1, 1))
				_explored_dirty = true
	# Échange des buffers (pas d'allocation).
	var tmp := _visible_list
	_visible_list = _new_vis
	_new_vis = tmp
	_vis_count = _new_count
	_hide_left = 0.0
	_cast_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	last_compute_ms = _cast_ms


func _mark(x: int, y: int, d2: int) -> void:
	var i := y * _w + x
	if _stamp[i] == _gen:
		return  # déjà marquée (axes et diagonales partagés entre octants)
	if _restrict_indoor and _indoor[i] == 1 and d2 > _peek2:
		return
	_stamp[i] = _gen
	_new_vis[_new_count] = i
	_new_count += 1


## Shadowcasting récursif (Björn Bergström), un octant.
func _cast(row: int, start: float, end: float, xx: int, xy: int, yx: int, yy: int) -> void:
	if start < end:
		return
	var new_start := 0.0
	var radius := view_radius
	for j in range(row, radius + 1):
		var dx := -j - 1
		var dy := -j
		var blocked := false
		while dx <= 0:
			dx += 1
			var X := _ox + dx * xx + dy * xy
			var Y := _oy + dx * yx + dy * yy
			var l_slope := (dx - 0.5) / (dy + 0.5)
			var r_slope := (dx + 0.5) / (dy - 0.5)
			if start < r_slope:
				continue
			elif end > l_slope:
				break
			var inside := X >= 0 and Y >= 0 and X < _w and Y < _h
			var d2 := dx * dx + dy * dy
			if inside and d2 <= _r2:
				_mark(X, Y, d2)
			var opaque := (not inside) or _opaque[Y * _w + X] == 1
			if blocked:
				if opaque:
					new_start = r_slope
					continue
				blocked = false
				start = new_start
			elif opaque and j < radius:
				blocked = true
				_cast(j + 1, start, l_slope, xx, xy, yx, yy)
				new_start = r_slope
		if blocked:
			break


# --- Polygone de visibilité ------------------------------------------------------

func _poly_interval_elapsed() -> bool:
	return Time.get_ticks_usec() - _last_poly_usec >= int(1000000.0 / max_updates_per_sec)


func _compute_polygon(origin: Vector2) -> void:
	var t0 := Time.get_ticks_usec()
	_last_poly_usec = t0
	_poly_origin = origin
	_ray_n = 0
	var R := (float(view_radius) + 1.0) * TS
	var r_cells := view_radius + 2
	var oc := FloorLayout.world_to_cell(origin)
	var ox := origin.x
	var oy := origin.y
	var R2 := R * R
	# Rayons vers les coins des murs / portes vus (filtrés par la vue par case).
	var w1 := _w + 1
	for vy in range(maxi(oc.y - r_cells, 0), mini(oc.y + r_cells + 1, _h) + 1):
		var row := vy * w1
		for vx in range(maxi(oc.x - r_cells, 0), mini(oc.x + r_cells + 1, _w) + 1):
			if _corner[row + vx] == 0:
				continue
			if not (_stamped(vx - 1, vy - 1) or _stamped(vx, vy - 1) or _stamped(vx - 1, vy) or _stamped(vx, vy)):
				continue
			var ddx := float(vx) * TS - ox
			var ddy := float(vy) * TS - oy
			if ddx * ddx + ddy * ddy > R2:
				continue
			var a := atan2(ddy, ddx)
			_push_ray(a - CORNER_EPS)
			_push_ray(a + CORNER_EPS)
	for k in circle_rays:
		_push_ray(-PI + TAU * float(k) / float(circle_rays))
	# Tri par angle (clé entière = angle quantifié << 16 | index).
	var n := _ray_n
	if _ray_keys.size() != n:
		_ray_keys.resize(n)
	for k in n:
		_ray_keys[k] = (int((_ray_angles[k] + PI + 0.01) * 1000000.0) << 16) | k
	_ray_keys.sort()
	if _poly.size() != n:
		_poly.resize(n)
	for k in n:
		var idx := int(_ray_keys[k] & 65535)
		var a2 := _ray_angles[idx]
		_poly[k] = _cast_ray(ox, oy, cos(a2), sin(a2), R)
	last_ray_count = n
	_collect_walls(oc)
	_collect_roofs(oc)
	last_polygon_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	last_compute_ms = _cast_ms + last_polygon_ms
	_request_mask_redraw()


func _push_ray(a: float) -> void:
	if _ray_n >= _ray_angles.size():
		_ray_angles.resize(maxi(_ray_angles.size() * 2, 256))
	_ray_angles[_ray_n] = a
	_ray_n += 1


func _stamped(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return false
	return _stamp[y * _w + x] == _gen


## DDA (Amanatides & Woo) depuis (ox, oy) dans la direction (dx, dy) normalisée.
## S'arrête à l'entrée du premier mur / porte fermée (les cases de mur vues sont
## ajoutées entières au masque par _collect_walls).
func _cast_ray(ox: float, oy: float, dx: float, dy: float, max_len: float) -> Vector2:
	var px := ox / TS
	var py := oy / TS
	var cx := floori(px)
	var cy := floori(py)
	var lim := max_len / TS
	var peek := float(outdoor_interior_peek) + 0.5
	var step_x := 1 if dx > 0.0 else -1
	var step_y := 1 if dy > 0.0 else -1
	var tdx := absf(1.0 / dx) if absf(dx) > 0.000001 else 1e30
	var tdy := absf(1.0 / dy) if absf(dy) > 0.000001 else 1e30
	var tmx := ((float(cx + 1) - px) if dx > 0.0 else (px - float(cx))) * tdx
	var tmy := ((float(cy + 1) - py) if dy > 0.0 else (py - float(cy))) * tdy
	var t := 0.0
	while true:
		if tmx < tmy:
			t = tmx
			tmx += tdx
			cx += step_x
		else:
			t = tmy
			tmy += tdy
			cy += step_y
		if t >= lim:
			t = lim
			break
		if cx < 0 or cy < 0 or cx >= _w or cy >= _h:
			break
		var i := cy * _w + cx
		if _opaque[i] == 1:
			break  # arrêt sur la face du mur ; la case est ajoutée par _collect_walls
		if _restrict_indoor and _indoor[i] == 1 and t > peek:
			break
	return Vector2(ox + dx * t * TS, oy + dy * t * TS)


## Cases opaques vues (shadowcasting) fusionnées par rangées horizontales : la face
## 3/4 d'un mur en vue est révélée entière, sans crénelage le long des rayons.
func _collect_walls(oc: Vector2i) -> void:
	_wall_rects.clear()
	var r := view_radius + 1
	for y in range(maxi(oc.y - r, 0), mini(oc.y + r + 1, _h)):
		var run := -1
		for x in range(maxi(oc.x - r, 0), mini(oc.x + r + 1, _w) + 1):
			var on := x < _w and _stamp[y * _w + x] == _gen and _opaque[y * _w + x] == 1
			if on and run < 0:
				run = x
			elif not on and run >= 0:
				_wall_rects.append(Rect2(float(run) * TS, float(y) * TS, float(x - run) * TS, TS))
				run = -1


## Toits des bâtiments dont un mur d'enceinte est en vue (joueur dehors) : on
## voit le toit depuis la rue, il est donc révélé dans le masque (pas les entités).
func _collect_roofs(oc: Vector2i) -> void:
	_roof_rects.clear()
	if not reveal_roofs or not _restrict_indoor:
		return
	var reach := view_radius + 2
	var view := Rect2i(oc - Vector2i(reach, reach), Vector2i(reach * 2 + 1, reach * 2 + 1))
	for b in layout.buildings:
		var r := b.rect
		if not r.intersects(view) or r.has_point(oc):
			continue
		var seen := false
		for x in range(r.position.x, r.end.x):
			if _stamped(x, r.position.y) or _stamped(x, r.end.y - 1):
				seen = true
				break
		if not seen:
			for y in range(r.position.y, r.end.y):
				if _stamped(r.position.x, y) or _stamped(r.end.x - 1, y):
					seen = true
					break
		if seen:
			_roof_rects.append(Rect2(Vector2(r.position) * TS, Vector2(r.size) * TS).grow(-6.0))


# --- Rendu ----------------------------------------------------------------------

func _build_render() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		material = _material
	if _noise_tex == null and ResourceLoader.exists(NOISE_PATH):
		_noise_tex = load(NOISE_PATH) as Texture2D
	# Masque de visibilité : SubViewport couvrant toute la carte, basse résolution.
	var map_px := Vector2(_w, _h) * TS
	var ppt := maxf(mask_px_per_texel, ceilf(maxf(map_px.x, map_px.y) / 2048.0))
	var vp_size := Vector2i(maxi(int(ceilf(map_px.x / ppt)), 1), maxi(int(ceilf(map_px.y / ppt)), 1))
	if _mask_vp == null:
		_mask_vp = SubViewport.new()
		_mask_vp.name = "FogMask"
		_mask_vp.disable_3d = true
		_mask_vp.transparent_bg = true
		_mask_vp.msaa_2d = Viewport.MSAA_DISABLED
		_mask_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_mask_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_mask_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		add_child(_mask_vp)
		_mask_drawer = MaskDrawer.new()
		_mask_drawer.name = "MaskDrawer"
		_mask_drawer.fog = self
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_mask_drawer.material = add
		_mask_vp.add_child(_mask_drawer)
	_mask_vp.size = vp_size
	_mask_drawer.scale = Vector2(float(vp_size.x) / map_px.x, float(vp_size.y) / map_px.y)
	# Mémoire d'exploration : 1 texel par case (filtre linéaire = bords doux).
	_rebuild_explored_image()
	_material.set_shader_parameter(&"vis_mask", _mask_vp.get_texture())
	_material.set_shader_parameter(&"explored_map", _explored_tex)
	_material.set_shader_parameter(&"mist_noise", _noise_tex)
	_apply_shader_params()
	_request_mask_redraw()


func _rebuild_explored_image() -> void:
	if _w <= 0 or _h <= 0:
		return
	_explored_image = Image.create_empty(_w, _h, false, Image.FORMAT_L8)
	for i in _w * _h:
		if _explored[i] == 1:
			_explored_image.set_pixel(i % _w, i / _w, Color(1, 1, 1))
	if _explored_tex == null or Vector2i(_explored_tex.get_size()) != Vector2i(_w, _h):
		_explored_tex = ImageTexture.create_from_image(_explored_image)
		if _material != null:
			_material.set_shader_parameter(&"explored_map", _explored_tex)
	else:
		_explored_tex.update(_explored_image)
	_explored_dirty = false


func _request_mask_redraw() -> void:
	if _mask_drawer == null:
		return
	_mask_drawer.queue_redraw()
	_mask_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Rectangle du brouillard : la carte + une grande marge (tout l'écran est couvert).
func _draw() -> void:
	if layout == null:
		return
	var r := Rect2(Vector2.ZERO, Vector2(_w, _h) * TS).grow(OUTER_MARGIN)
	draw_rect(r, Color.WHITE)


## Appelé par MaskDrawer._draw : polygone en éventail, plusieurs passes décalées
## en mélange additif (somme = 1 au cœur) → bord adouci d'environ edge_feather_px.
func _draw_mask(ci: Node2D) -> void:
	var n := _poly.size()
	if n < 3:
		return
	var taps := FEATHER_TAPS.size()
	var col := Color(1.0, 1.0, 1.0, 1.0 / float(taps))
	if _fan_points.size() != n + 1:
		_fan_points.resize(n + 1)
		_fan_colors.resize(n + 1)
		_fan_colors.fill(col)
		_fan_indices.resize(n * 3)
		for k in n:
			_fan_indices[k * 3] = 0
			_fan_indices[k * 3 + 1] = k + 1
			_fan_indices[k * 3 + 2] = (k + 1) % n + 1
	_fan_points[0] = _poly_origin
	for k in n:
		_fan_points[k + 1] = _poly[k]
	var rid := ci.get_canvas_item()
	for tap in FEATHER_TAPS:
		var off := tap * edge_feather_px
		ci.draw_set_transform(off)
		RenderingServer.canvas_item_add_triangle_array(rid, _fan_indices, _fan_points, _fan_colors)
		for rr in _wall_rects:
			ci.draw_rect(rr, col)
		for rr in _roof_rects:
			ci.draw_rect(rr, col)
	ci.draw_set_transform(Vector2.ZERO)


func _process(delta: float) -> void:
	if layout == null:
		return
	if _pending and _poly_interval_elapsed():
		_pending = false
		_compute_polygon(_pending_pos)
	if _explored_dirty and _explored_tex != null:
		_explored_tex.update(_explored_image)
		_explored_dirty = false
	if not _fading.is_empty():
		_update_fades(delta)
	_hide_left -= delta
	if _hide_left <= 0.0:
		_hide_left = hide_interval
		update_hideables()


# --- Entités cachées ---------------------------------------------------------------

## Cache / réaffiche les nœuds du groupe fog_hideable selon le champ de vision
## (point dans le polygone de visibilité et dans le rayon de vue). Jamais le joueur.
func update_hideables() -> void:
	if not is_inside_tree() or layout == null:
		return
	for n in get_tree().get_nodes_in_group(GROUP_HIDEABLE):
		var ci := n as CanvasItem
		if ci == null or ci.is_in_group(GROUP_PLAYER):
			continue
		var show := false
		if n is Node2D:
			show = is_world_point_visible((n as Node2D).global_position)
		if ci.visible == show:
			continue
		ci.visible = show
		if show and transition_time > 0.0 and ci.modulate.a >= 0.99:
			ci.modulate.a = 0.0
			_fading[ci] = 0.0
		elif not show and _fading.has(ci):
			_fading.erase(ci)
			ci.modulate.a = 1.0


func _update_fades(delta: float) -> void:
	var step := delta / maxf(transition_time, 0.001)
	_fade_done.clear()
	for key: Variant in _fading:
		if not is_instance_valid(key):
			_fade_done.append(key)
			continue
		var ci := key as CanvasItem
		var v: float = minf(float(_fading[key]) + step, 1.0)
		_fading[ci] = v
		ci.modulate.a = v
		if v >= 1.0:
			_fade_done.append(ci)
	for ci in _fade_done:
		_fading.erase(ci)
