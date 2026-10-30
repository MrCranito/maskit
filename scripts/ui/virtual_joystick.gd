class_name TouchJoystick
extends Control
## Joystick virtuel flottant (paysage, double stick).
## - `side` = &"left" (déplacement, groupe `joystick_move`) ou &"right" (visée + tir,
##   groupe `joystick_aim`). Chaque stick n'accepte que les nouveaux contacts de SA moitié
##   d'écran et suit son propre index de doigt (multi-touch).
## - Flottant : la base apparaît sous le pouce ; au repos, une base fantôme discrète
##   indique l'emplacement. Si le doigt dépasse le rayon, la base suit le doigt.
## - `output` : direction de longueur 0..1, zone morte appliquée (0 tant qu'on est dedans).
## - Actif seulement sur écran tactile, ou si [joystick] force_on_desktop=true.
## Performance : aucun traitement par frame ; redessin uniquement sur événement tactile.

const SIDE_LEFT := &"left"
const SIDE_RIGHT := &"right"
const GROUP_MOVE := &"joystick_move"
const GROUP_AIM := &"joystick_aim"
const SCENE_PATH := "res://scenes/ui/virtual_joystick.tscn"

## Émis quand le stick est saisi / relâché.
signal held_changed(held: bool)

@export var side: StringName = SIDE_LEFT

## Direction courante (longueur 0..1).
var output: Vector2 = Vector2.ZERO

var radius: float = 90.0
var dead_zone: float = 0.15
## Fraction de la hauteur d'écran au-dessus de laquelle un toucher n'active pas le stick (HUD).
var activation_top_ratio: float = 0.25
## Position de repos (fraction de l'écran) de la base fantôme.
var rest_ratio: Vector2 = Vector2(0.14, 0.76)
var ghost_visible: bool = true
var follow_finger: bool = true

var _enabled: bool = false
var _touch_index: int = -1
var _base_pos: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO


## Instancie les deux sticks (gauche puis droit) sous `parent`. Renvoie [gauche, droit]
## (vide si la scène manque).
static func create_pair(parent: Node) -> Array[TouchJoystick]:
	var out: Array[TouchJoystick] = []
	if not ResourceLoader.exists(SCENE_PATH):
		push_warning("TouchJoystick: scène introuvable (%s)." % SCENE_PATH)
		return out
	var scene := load(SCENE_PATH) as PackedScene
	for s: StringName in [SIDE_LEFT, SIDE_RIGHT]:
		var j := scene.instantiate() as TouchJoystick
		if j == null:
			continue
		j.side = s
		j.name = "JoystickMove" if s == SIDE_LEFT else "JoystickAim"
		parent.add_child(j)
		out.append(j)
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Ne bloque jamais les autres UI : on lit les touches dans _input / _unhandled_input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var is_right: bool = side == SIDE_RIGHT
	add_to_group(GROUP_AIM if is_right else GROUP_MOVE)
	if not is_right:
		add_to_group(&"virtual_joystick")  # compatibilité (ancien nom de groupe)
	radius = Balance.get_float("joystick", "radius", 90.0)
	dead_zone = Balance.get_float("joystick", "aim_dead_zone" if is_right else "dead_zone", 0.15)
	activation_top_ratio = Balance.get_float("joystick", "activation_top_ratio", 0.25)
	var rx: float = Balance.get_float("joystick", "right_rest_x" if is_right else "left_rest_x", 0.86 if is_right else 0.14)
	rest_ratio = Vector2(rx, Balance.get_float("joystick", "rest_y", 0.76))
	ghost_visible = bool(Balance.get_value("joystick", "show_rest_ghost", true))
	follow_finger = bool(Balance.get_value("joystick", "follow_finger", true))
	var force: bool = bool(Balance.get_value("joystick", "force_on_desktop", false))
	_enabled = has_real_touchscreen() or force
	visible = _enabled
	set_process(false)
	set_physics_process(false)
	set_process_input(_enabled)
	set_process_unhandled_input(_enabled)
	resized.connect(queue_redraw)


## Vrai écran tactile ? Sur PC, `emulate_touch_from_mouse` fait répondre vrai à
## DisplayServer.is_touchscreen_available() : on ne s'y fie que hors émulation.
static func has_real_touchscreen() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	return DisplayServer.is_touchscreen_available() and not Input.is_emulating_touch_from_mouse()


func is_enabled() -> bool:
	return _enabled


## Active / désactive le stick (option « joysticks sur PC », tests).
func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	set_process_input(on)
	set_process_unhandled_input(on)
	if not on:
		_release()
	queue_redraw()


func is_held() -> bool:
	return _touch_index >= 0


func get_touch_index() -> int:
	return _touch_index


## Centre de la base au repos (coordonnées locales du contrôle).
func get_rest_position() -> Vector2:
	return size * rest_ratio


## Nouveau contact : traité APRÈS l'interface, pour que les boutons (action, sac…)
## gardent leurs touches.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch):
		return
	var t: InputEventScreenTouch = event
	if not t.pressed or _touch_index >= 0:
		return
	var local: Vector2 = _to_local(t.position)
	if not side_accepts(side, local, size, activation_top_ratio):
		return
	_touch_index = t.index
	_base_pos = local
	_knob_pos = local
	_update_output()
	held_changed.emit(true)
	get_viewport().set_input_as_handled()


## Glissés et relâchements du doigt suivi : lus en priorité pour ne jamais les perdre.
func _input(event: InputEvent) -> void:
	if _touch_index < 0:
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if not t.pressed and t.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _touch_index:
			_knob_pos = _to_local(d.position)
			_update_output()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_release()


func _to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _release() -> void:
	if _touch_index < 0 and output == Vector2.ZERO:
		return
	var was_held: bool = _touch_index >= 0
	_touch_index = -1
	output = Vector2.ZERO
	queue_redraw()
	if was_held:
		held_changed.emit(false)


func _update_output() -> void:
	var offset: Vector2 = _knob_pos - _base_pos
	var len: float = offset.length()
	if len > radius:
		var dir: Vector2 = offset / len
		if follow_finger:
			# La base glisse derrière le doigt : le stick ne « décroche » jamais.
			_base_pos = _knob_pos - dir * radius
		else:
			_knob_pos = _base_pos + dir * radius
		offset = dir * radius
	output = compute_output(offset, radius, dead_zone)
	queue_redraw()


## Logique pure : décalage du manche → sortie 0..1, zone morte remappée.
static func compute_output(offset: Vector2, max_radius: float, dz: float) -> Vector2:
	if max_radius <= 0.0:
		return Vector2.ZERO
	var ratio: float = minf(offset.length() / max_radius, 1.0)
	if ratio <= dz:
		return Vector2.ZERO
	var strength: float = (ratio - dz) / maxf(1.0 - dz, 0.0001)
	return offset.normalized() * clampf(strength, 0.0, 1.0)


## Logique pure : un contact en `local` (écran de taille `area`) revient-il au stick `s` ?
## Gauche = moitié gauche, droit = moitié droite, jamais dans la bande du haut (HUD).
static func side_accepts(s: StringName, local: Vector2, area: Vector2, top_ratio: float) -> bool:
	if local.x < 0.0 or local.y < 0.0 or local.x > area.x or local.y > area.y:
		return false
	if local.y < area.y * top_ratio:
		return false
	var left_half: bool = local.x < area.x * 0.5
	return left_half if s == SIDE_LEFT else not left_half


# --- Dessin (uniquement sur changement) ------------------------------------------

func _draw() -> void:
	if not _enabled:
		return
	if is_held():
		_draw_stick(_base_pos, _knob_pos, false)
	elif ghost_visible:
		var rest: Vector2 = get_rest_position()
		_draw_stick(rest, rest, true)


## Maquette Hud (direction D) : déplacement = anneau blanc fin sur encre, manche blanc
## translucide ; visée = disque violet, anneau violet clair, manche blanc avec mire violette.
func _draw_stick(base: Vector2, knob: Vector2, ghost: bool) -> void:
	var a: float = 0.55 if ghost else 1.0
	var is_aim: bool = side == SIDE_RIGHT
	var fill: Color = Color(MenuKit.VIOLET, 0.25) if is_aim else Color(MenuKit.NIGHT_DEEP, 0.2)
	var ring: Color = Color(MenuKit.VIOLET_LIGHT, 0.8) if is_aim else Color(1, 1, 1, 0.3)
	draw_circle(base, radius, Color(fill, fill.a * a), true, -1.0, true)
	draw_arc(base, radius, 0.0, TAU, 56, Color(ring, ring.a * a), 2.0, true)
	# Arc dans la direction poussée.
	if not ghost and output != Vector2.ZERO:
		var ang: float = output.angle()
		var col: Color = MenuKit.VIOLET_LIGHT if is_aim else Color.WHITE
		draw_arc(base, radius - 1.0, ang - 0.5, ang + 0.5, 16, Color(col, 0.35 + 0.55 * output.length()), 5.0, true)
	# Manche.
	var kr: float = radius * 0.44
	draw_circle(knob, kr, Color(1, 1, 1, (0.75 if is_aim else 0.45) * a), true, -1.0, true)
	if is_aim:
		var ic := Color(0.227, 0.122, 0.561, 0.95 * a)   # violet profond #3A1F8F
		draw_arc(knob, kr * 0.46, 0.0, TAU, 24, ic, 2.4, true)
		for i: int in 4:
			var d := Vector2.RIGHT.rotated(i * PI * 0.5)
			draw_line(knob + d * kr * 0.62, knob + d * kr * 0.88, ic, 2.4, true)
