class_name RoofWalk
extends Node2D
## Toits accessibles par échelle (FloorLayout.ladders, section [roofs] de balance.cfg).
##
## - Chaque échelle : Ladder au pied (rue au sud de la façade) et au sommet (bord sud du toit).
## - Monter : animation (climb_time) du pied au sommet le long de l'échelle, puis le joueur est
##   « sur le toit » : couche roof_player (7) touchée par les tirs ennemis mais ignorée des corps
##   ennemis, portes, escaliers ; il ne heurte que les bords du toit (StaticBody2D couche
##   roof_bounds (8), 4 bandes) ; z d'affichage player_z (au-dessus des toits) ; le toit ne s'efface
##   pas (roof.gd) ; portée de vue + view_bonus ; il ne peut ni entrer dans le bâtiment ni
##   interagir avec le sol (InteractController). Descente uniquement par l'échelle.
## - Géométrie : le toit vu à l'écran est l'emprise du bâtiment décalée vers le nord de
##   égout · tan(inclinaison) cases (rendu pré-calculé : map.json roofs / tilt ; rendu 2D : toit à
##   plat sur l'emprise, décalage nul). Le joueur perché a donc sa position logique là où il est
##   dessiné (tirs, caméra, brouillard cohérents).
## - Bâtiment sous le joueur « fantôme » : ses murs (formes du corps de murs du WorldBuilder et de
##   la couche « emprise rendue » qui recoupent son emprise) passent sur la couche enemies (4) :
##   les ennemis ne le traversent toujours pas, mais leur ligne de vue (couche 1), leurs tirs
##   (1|2|64) et ceux du joueur (groupe roof_ghost ignoré, projectile.gd) passent par-dessus.
##   Brouillard : FogOfWar.set_roof_mode (murs du bâtiment transparents, intérieur caché).
## - Mêlée : Player.take_damage ignore les coups non « à distance » quand il est perché.

signal roof_changed(building_id: int)

const TS := float(FloorLayout.TILE_SIZE)
const LAYER_WORLD := 1
const LAYER_ENEMIES := 4
const LAYER_ROOF_BOUNDS := 128
const GROUP_GHOST := &"roof_ghost"

var layout: FloorLayout = null
var builder: Node = null
var backdrop: Node = null
var fog: Node = null
var climb_time: float = 0.75
var player_z: int = 60
var edge_inset: float = 20.0
var view_bonus: int = 3
var ladder_reach: float = 26.0
var top_inset: float = 34.0
var eave_default: float = 2.0
var current_bid: int = -1
var ladders: Array[Ladder] = []

var _busy: bool = false
var _bounds: StaticBody2D = null
var _ghost: StaticBody2D = null
var _patch: StaticBody2D = null
var _disabled: Array[CollisionShape2D] = []
var _ghost_doors: Array[Node] = []
var _tween: Tween = null


## Crée le gestionnaire et ses échelles (aucune si le plan n'en a pas ou [roofs] enabled=false).
static func create(p_layout: FloorLayout, p_builder: Node, p_backdrop: Node) -> RoofWalk:
	var w := RoofWalk.new()
	w.name = "RoofWalk"
	w.layout = p_layout
	w.builder = p_builder
	w.backdrop = p_backdrop
	w._load_balance()
	if w._enabled():
		w._build_ladders()
	return w


func _enabled() -> bool:
	return bool(_cfg("enabled", true)) and layout != null


func _cfg(key: String, def: Variant) -> Variant:
	var loop := Engine.get_main_loop() as SceneTree
	var b: Node = loop.root.get_node_or_null(^"/root/Balance") if loop != null else null
	return b.call(&"get_value", "roofs", key, def) if b != null else def


func _load_balance() -> void:
	climb_time = float(_cfg("climb_time", climb_time))
	player_z = int(_cfg("player_z", player_z))
	edge_inset = float(_cfg("edge_inset", edge_inset))
	view_bonus = int(_cfg("view_bonus", view_bonus))
	ladder_reach = float(_cfg("ladder_reach", ladder_reach))
	top_inset = float(_cfg("top_inset", top_inset))
	eave_default = float(_cfg("eave_default", eave_default))


func set_fog(f: Node) -> void:
	fog = f


func is_busy() -> bool:
	return _busy


func _building(bid: int) -> FloorLayout.Building:
	if layout == null or bid < 0 or bid >= layout.buildings.size():
		return null
	return layout.buildings[bid]


## Décalage vers le nord (px monde) du toit du bâtiment `bid` à l'écran.
func lift_px(bid: int) -> float:
	if backdrop == null or not backdrop.has_method("roof_eave"):
		return 0.0
	return float(backdrop.call("roof_eave", bid, eave_default)) * float(backdrop.call("tan_tilt")) * TS


## Toit du bâtiment (monde, tel que dessiné) et zone praticable (bords - edge_inset).
func roof_rect(bid: int) -> Rect2:
	var b := _building(bid)
	if b == null:
		return Rect2()
	var r := Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
	r.position.y -= lift_px(bid)
	return r


func walk_rect(bid: int) -> Rect2:
	return roof_rect(bid).grow(-edge_inset)


func ladder_bottom(e: Dictionary) -> Vector2:
	return FloorLayout.cell_to_world(e["cell"])


func ladder_top(e: Dictionary) -> Vector2:
	var c: Vector2i = e["cell"]
	return Vector2((float(c.x) + 0.5) * TS, roof_rect(int(e["building_id"])).end.y - top_inset)


func _build_ladders() -> void:
	for e: Dictionary in layout.ladders:
		if _building(int(e["building_id"])) == null:
			continue
		var foot := Ladder.make(self, e, false, ladder_bottom(e), ladder_reach)
		foot.draw_ladder = backdrop == null
		foot.draw_to = ladder_top(e)
		var top := Ladder.make(self, e, true, ladder_top(e), ladder_reach)
		add_child(foot)
		add_child(top)
		ladders.append(foot)
		ladders.append(top)


## Montée (`up`) ou descente par l'échelle `ladder` (pied ou sommet).
func climb(ladder: Ladder, up: bool, p: Node = null) -> bool:
	var player := (p if p != null else get_tree().get_first_node_in_group(&"player")) as Node2D
	if player == null or _busy:
		return false
	var e := ladder.entry
	var bid := int(e["building_id"])
	if up == (current_bid >= 0):
		return false
	_busy = true
	player.call("set_climbing", true)
	if up:
		enter_roof(bid, player)  # perché dès le premier barreau (z, mêlée, couches)
	var a := ladder_bottom(e) if up else player.global_position
	var b := ladder_top(e) if up else ladder_bottom(e)
	if not up:
		# Ramène d'abord le joueur au sommet, puis descend.
		a = ladder_top(e)
	player.global_position = a
	player.reset_physics_interpolation()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.tween_property(player, "global_position", b, maxf(climb_time, 0.01))
	_tween.tween_callback(_climb_done.bind(player, bid, up))
	return true


func _climb_done(player: Node2D, bid: int, up: bool) -> void:
	if not up:
		exit_roof(player)
	player.call("set_climbing", false)
	_busy = false


## Fin d'animation immédiate (tests, changement d'étage).
func finish_climb() -> void:
	if _tween != null and _tween.is_valid():
		_tween.custom_step(1000.0)


## État « sur le toit » (appelé en fin de montée ; public pour les tests).
func enter_roof(bid: int, player: Node2D) -> void:
	if current_bid >= 0:
		exit_roof(player)
	current_bid = bid
	player.call("set_roof_state", bid, player_z)
	_make_bounds(walk_rect(bid))
	_ghost_building(bid)
	if fog != null and fog.has_method("set_roof_mode"):
		fog.call("set_roof_mode", _building(bid).rect, view_bonus)
	roof_changed.emit(bid)
	_refresh_banner()


func exit_roof(player: Node2D) -> void:
	if current_bid < 0:
		return
	current_bid = -1
	if player != null and is_instance_valid(player):
		player.call("set_roof_state", -1)
	if _bounds != null:
		_bounds.queue_free()
		_bounds = null
	_unghost()
	if fog != null and fog.has_method("set_roof_mode"):
		fog.call("set_roof_mode", Rect2i(), 0)
	roof_changed.emit(-1)
	_refresh_banner()


## Bandeau du raid (« Toit — <bâtiment> ») : premier ancêtre qui sait le rafraîchir.
func _refresh_banner() -> void:
	var n := get_parent()
	while n != null:
		if n.has_method("_update_banner"):
			n.call("_update_banner", false)
			return
		n = n.get_parent()


## Bords du toit : 4 bandes (couche roof_bounds) autour de la zone praticable.
func _make_bounds(r: Rect2) -> void:
	if _bounds != null:
		_bounds.queue_free()
	_bounds = StaticBody2D.new()
	_bounds.name = "RoofBounds"
	_bounds.collision_layer = LAYER_ROOF_BOUNDS
	_bounds.collision_mask = 0
	var t := 64.0
	for band: Rect2 in [Rect2(r.position.x - t, r.position.y - t, r.size.x + 2.0 * t, t),
			Rect2(r.position.x - t, r.end.y, r.size.x + 2.0 * t, t),
			Rect2(r.position.x - t, r.position.y, t, r.size.y),
			Rect2(r.end.x, r.position.y, t, r.size.y)]:
		_add_rect(_bounds, band)
	add_child(_bounds)


static func _add_rect(body: StaticBody2D, r: Rect2) -> void:
	if r.size.x <= 0.5 or r.size.y <= 0.5:
		return
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.get_center()
	body.add_child(cs)


## Rectangle moins un rectangle intérieur : jusqu'à 4 morceaux.
static func subtract_rect(r: Rect2, cut: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var c := r.intersection(cut)
	if c.size.x <= 0.0 or c.size.y <= 0.0:
		out.append(r)
		return out
	if c.position.y > r.position.y:
		out.append(Rect2(r.position.x, r.position.y, r.size.x, c.position.y - r.position.y))
	if c.end.y < r.end.y:
		out.append(Rect2(r.position.x, c.end.y, r.size.x, r.end.y - c.end.y))
	if c.position.x > r.position.x:
		out.append(Rect2(r.position.x, c.position.y, c.position.x - r.position.x, c.size.y))
	if c.end.x < r.end.x:
		out.append(Rect2(c.end.x, c.position.y, r.end.x - c.end.x, c.size.y))
	return out


func _bodies_to_ghost() -> Array[StaticBody2D]:
	var out: Array[StaticBody2D] = []
	if builder != null and builder.has_method("get_wall_body"):
		var wb: StaticBody2D = builder.call("get_wall_body")
		if wb != null:
			out.append(wb)
	if backdrop != null:
		var cb: Variant = backdrop.get("collision_body")
		if cb is StaticBody2D:
			out.append(cb)
	return out


## Murs du bâtiment sous le joueur → couche enemies (voir en-tête).
func _ghost_building(bid: int) -> void:
	_unghost()
	var b := _building(bid)
	if b == null:
		return
	var foot := Rect2(Vector2(b.rect.position) * TS, Vector2(b.rect.size) * TS)
	_ghost = StaticBody2D.new()
	_ghost.name = "RoofGhostWalls"
	_ghost.collision_layer = LAYER_ENEMIES
	_ghost.collision_mask = 0
	_ghost.add_to_group(GROUP_GHOST)
	_patch = StaticBody2D.new()
	_patch.name = "RoofGhostPatch"
	_patch.collision_layer = LAYER_WORLD
	_patch.collision_mask = 0
	for body in _bodies_to_ghost():
		var inv := body.global_transform
		for ch: Node in body.get_children():
			var cs := ch as CollisionShape2D
			if cs == null or cs.disabled or not (cs.shape is RectangleShape2D):
				continue
			var sz := (cs.shape as RectangleShape2D).size
			var r := Rect2(inv * cs.position - sz * 0.5, sz)
			if not r.intersects(foot):
				continue
			cs.set_deferred("disabled", true)
			_disabled.append(cs)
			_add_rect(_ghost, r.intersection(foot))
			for rest in subtract_rect(r, foot):
				_add_rect(_patch, rest)
	add_child(_ghost)
	add_child(_patch)
	# Portes du bâtiment : les tirs du joueur passent (groupe roof_ghost).
	var doors: Array = builder.call("get_doors") if builder != null and builder.has_method("get_doors") else []
	for d: Node in doors:
		var c: Variant = d.get("cell")
		if c is Vector2i and b.rect.has_point(c) and not d.is_in_group(GROUP_GHOST):
			d.add_to_group(GROUP_GHOST)
			_ghost_doors.append(d)


func _unghost() -> void:
	for cs in _disabled:
		if is_instance_valid(cs):
			cs.set_deferred("disabled", false)
	_disabled.clear()
	for n: Node in [_ghost, _patch]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_ghost = null
	_patch = null
	for d in _ghost_doors:
		if is_instance_valid(d):
			d.remove_from_group(GROUP_GHOST)
	_ghost_doors.clear()


func _exit_tree() -> void:
	_unghost()


## Debug F3 : zones de toit praticables et échelles.
func debug_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var seen := {}
	for l in ladders:
		var bid := l.building_id()
		if not seen.has(bid):
			seen[bid] = true
			out.append(walk_rect(bid))
	return out
