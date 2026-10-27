class_name FogOfWar
extends Node2D
## Brouillard de guerre à 3 états sur la grille d'un FloorLayout.
##   0 = jamais vu (nuit quasi opaque), 1 = exploré hors vue (voilé, désaturé),
##   2 = visible (clair).
## Vue : shadowcasting récursif (8 octants) depuis la case du joueur, rayon
## [fog] view_radius. Opaques : WALL, VOID, porte fermée (via set_door_query).
## Depuis l'extérieur, les cases d'intérieur ne sont visibles qu'à courte portée
## ([fog] outdoor_interior_peek) à travers une porte ouverte ; depuis l'intérieur,
## les murs du bâtiment bloquent naturellement la vue.
## Recalcul uniquement quand le joueur change de case ou après invalidate().
## Rendu : Image RG8 (1 texel = 1 case ; R = visible, G = explorée) → ImageTexture affichée par un Sprite2D
## (échelle TILE_SIZE, filtre linéaire) + shader fog_of_war.gdshader (bords
## lissés, brume animée). Transitions : lerp CPU des seules cases qui changent.
## Masque les nœuds du groupe `fog_hideable` hors des cases visibles (jamais le joueur).
##
## Branchement (raid) :
##   fog.setup(layout); fog.set_door_query(func(c): return porte_ouverte(c))
##   DoorNode.state_changed → fog.invalidate() ; chaque frame : fog.update_from(player.global_position)
##   changement d'étage : etat = fog.get_state() … plus tard fog.set_state(etat)

const SHADER: Shader = preload("res://assets/shaders/fog_of_war.gdshader")
const GROUP_HIDEABLE := &"fog_hideable"
const GROUP_PLAYER := &"player"


## Octants du shadowcasting : (xx, xy, yx, yy).
const OCTANTS: Array[Vector4i] = [
	Vector4i(1, 0, 0, 1), Vector4i(0, 1, 1, 0), Vector4i(0, -1, 1, 0), Vector4i(-1, 0, 0, 1),
	Vector4i(-1, 0, 0, -1), Vector4i(0, -1, -1, 0), Vector4i(0, 1, -1, 0), Vector4i(1, 0, 0, -1),
]

# --- Réglages (balance.cfg [fog]) ---
var view_radius: int = 10
var outdoor_interior_peek: int = 4
var transition_time: float = 0.2
var hide_interval: float = 0.05
var debug_reveal_with_f3: bool = false

var layout: FloorLayout = null
## Durée du dernier recalcul de vue (ms), pour l'overlay de debug / les tests.
var last_compute_ms: float = 0.0

var _w: int = 0
var _h: int = 0
var _opaque: PackedByteArray = PackedByteArray()    ## 1 = bloque la vue
var _indoor: PackedByteArray = PackedByteArray()    ## 1 = case d'intérieur (sol de bâtiment)
var _explored: PackedByteArray = PackedByteArray()  ## 1 = déjà vue
var _visible: PackedByteArray = PackedByteArray()   ## 1 = visible maintenant
var _visible_list: PackedInt32Array = PackedInt32Array()
var _door_cells: Array[Vector2i] = []
var _door_query: Callable = Callable()

var _display: PackedFloat32Array = PackedFloat32Array()  ## (visible, explorée) affichés par case, 0..1
var _target: PackedFloat32Array = PackedFloat32Array()   ## (visible, explorée) cibles par case
var _animating: Dictionary = {}                          ## index → true
var _image: Image = null
var _texture: ImageTexture = null
var _sprite: Sprite2D = null
var _material: ShaderMaterial = null

var _last_cell: Vector2i = Vector2i(-99999, -99999)
var _has_origin: bool = false
var _dirty: bool = true
var _snap_next: bool = true
var _reveal_all: bool = false
var _hide_left: float = 0.0
var _texture_dirty: bool = false

# Variables de travail du shadowcasting (évite de les passer à chaque appel).
var _ox: int = 0
var _oy: int = 0
var _r2: int = 0
var _peek2: int = 0
var _restrict_indoor: bool = false
var _new_vis: PackedInt32Array = PackedInt32Array()
var _stamp: PackedInt32Array = PackedInt32Array()  ## Génération du dernier marquage
var _gen: int = 0


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
	_visible_list = PackedInt32Array()
	_stamp = PackedInt32Array()
	_stamp.resize(n)
	_gen = 0
	_display = PackedFloat32Array()
	_display.resize(n * 2)
	_target = PackedFloat32Array()
	_target.resize(n * 2)
	_animating.clear()
	_door_cells.clear()
	for d in layout.doors:
		_door_cells.append(d.cell)
	_build_static_masks()
	_build_sprite()
	_last_cell = Vector2i(-99999, -99999)
	_has_origin = false
	_dirty = true
	_snap_next = true
	_refresh_all_targets(true)


## callable(cell: Vector2i) -> bool : true si la porte de cette case est ouverte.
func set_door_query(callable: Callable) -> void:
	_door_query = callable
	invalidate()


## Force un recalcul au prochain update_from (porte ouverte/fermée, etc.).
func invalidate() -> void:
	_dirty = true


func update_from(world_pos: Vector2) -> void:
	if layout == null:
		return
	var cell := FloorLayout.world_to_cell(world_pos)
	if cell == _last_cell and not _dirty:
		return
	_last_cell = cell
	_has_origin = true
	_dirty = false
	_recompute(cell)


func is_cell_visible(c: Vector2i) -> bool:
	if layout == null or not layout.in_bounds(c):
		return false
	return _reveal_all or _visible[c.y * _w + c.x] == 1


func is_cell_explored(c: Vector2i) -> bool:
	if layout == null or not layout.in_bounds(c):
		return false
	return _reveal_all or _explored[c.y * _w + c.x] == 1


## État d'affichage d'une case : 0 jamais vu, 1 exploré hors vue, 2 visible.
func get_cell_state(c: Vector2i) -> int:
	if is_cell_visible(c):
		return 2
	return 1 if is_cell_explored(c) else 0


func reveal_all(on: bool) -> void:
	if on == _reveal_all:
		return
	_reveal_all = on
	if layout != null:
		_refresh_all_targets(false)
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
	for i in _visible_list:
		_explored[i] = 1
	_refresh_all_targets(true)
	_dirty = true


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


func _apply_shader_params() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"map_cells", Vector2(_w, _h))
	_material.set_shader_parameter(&"unseen_color", _cfg("unseen_color", Color(0.02, 0.03, 0.07, 0.97)))
	_material.set_shader_parameter(&"explored_tint", _cfg("explored_tint", Color(0.05, 0.07, 0.14, 1.0)))
	_material.set_shader_parameter(&"explored_veil", float(_cfg("explored_veil", 0.6)))
	_material.set_shader_parameter(&"edge_softness", float(_cfg("edge_softness", 0.5)))
	_material.set_shader_parameter(&"edge_center", float(_cfg("edge_center", 0.4)))
	_material.set_shader_parameter(&"mist_strength", float(_cfg("mist_strength", 0.12)))
	_material.set_shader_parameter(&"mist_speed", float(_cfg("mist_speed", 0.15)))


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


func _refresh_doors() -> void:
	for c in _door_cells:
		var i := c.y * _w + c.x
		var open := true
		if _door_query.is_valid():
			open = bool(_door_query.call(c))
		else:
			var d := layout.get_door_at(c)
			open = d == null or d.state == FloorLayout.DoorState.OPEN
		_opaque[i] = 0 if open else 1


# --- Calcul de vue --------------------------------------------------------------

func _recompute(origin: Vector2i) -> void:
	var t0 := Time.get_ticks_usec()
	_refresh_doors()
	_new_vis = PackedInt32Array()
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
	# Différence avec l'ancienne vue (_stamp == _gen ⇔ visible maintenant).
	var snap := _snap_next
	_snap_next = false
	for i in _visible_list:
		if _stamp[i] != _gen:  # n'est plus visible
			_visible[i] = 0
			_set_target(i, snap)
	for i in _new_vis:
		if _visible[i] == 0 or _explored[i] == 0:
			_visible[i] = 1
			_explored[i] = 1
			_set_target(i, snap)
	_visible_list = _new_vis
	_hide_left = 0.0
	last_compute_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _mark(x: int, y: int, d2: int) -> void:
	var i := y * _w + x
	if _stamp[i] == _gen:
		return  # déjà marquée (axes et diagonales partagés entre octants)
	if _restrict_indoor and _indoor[i] == 1 and d2 > _peek2:
		return
	_stamp[i] = _gen
	_new_vis.append(i)


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


# --- Rendu ----------------------------------------------------------------------

func _build_sprite() -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "FogSprite"
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_sprite.material = _material
		add_child(_sprite)
	_image = Image.create_empty(maxi(_w, 1), maxi(_h, 1), false, Image.FORMAT_RG8)
	_image.fill(Color(0, 0, 0))
	_texture = ImageTexture.create_from_image(_image)
	_sprite.texture = _texture
	_sprite.scale = Vector2(FloorLayout.TILE_SIZE, FloorLayout.TILE_SIZE)
	_sprite.position = Vector2.ZERO
	_apply_shader_params()


## Cible d'une case : x = visible (R), y = explorée (G).
func _target_of(i: int) -> Vector2:
	if _reveal_all or _visible[i] == 1:
		return Vector2(1.0, 1.0)
	return Vector2(0.0, 1.0 if _explored[i] == 1 else 0.0)


func _set_target(i: int, snap: bool) -> void:
	var t := _target_of(i)
	_target[i * 2] = t.x
	_target[i * 2 + 1] = t.y
	if snap or transition_time <= 0.0:
		_display[i * 2] = t.x
		_display[i * 2 + 1] = t.y
		_write_pixel(i)
		_animating.erase(i)
	elif _display[i * 2] != t.x or _display[i * 2 + 1] != t.y:
		_animating[i] = true


func _refresh_all_targets(snap: bool) -> void:
	for i in _w * _h:
		_set_target(i, snap)


func _write_pixel(i: int) -> void:
	if _image == null:
		return
	_image.set_pixel(i % _w, i / _w, Color(_display[i * 2], _display[i * 2 + 1], 0.0))
	_texture_dirty = true


func _process(delta: float) -> void:
	if layout == null:
		return
	if not _animating.is_empty():
		var step := delta / maxf(transition_time, 0.001)
		var done: PackedInt32Array = PackedInt32Array()
		for k: int in _animating:
			var r := move_toward(_display[k * 2], _target[k * 2], step)
			var g := move_toward(_display[k * 2 + 1], _target[k * 2 + 1], step)
			_display[k * 2] = r
			_display[k * 2 + 1] = g
			_write_pixel(k)
			if r == _target[k * 2] and g == _target[k * 2 + 1]:
				done.append(k)
		for k in done:
			_animating.erase(k)
	if _texture_dirty and _texture != null:
		_texture.update(_image)
		_texture_dirty = false
	_hide_left -= delta
	if _hide_left <= 0.0:
		_hide_left = hide_interval
		update_hideables()


## Cache / réaffiche les nœuds du groupe fog_hideable selon la visibilité de leur case.
func update_hideables() -> void:
	if not is_inside_tree() or layout == null:
		return
	for n in get_tree().get_nodes_in_group(GROUP_HIDEABLE):
		var ci := n as CanvasItem
		if ci == null or ci.is_in_group(GROUP_PLAYER):
			continue
		var c := FloorLayout.world_to_cell((n as Node2D).global_position) if n is Node2D else Vector2i(-1, -1)
		var show := is_cell_visible(c)
		if ci.visible != show:
			ci.visible = show
