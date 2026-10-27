class_name VirtualJoystick
extends Control
## Joystick virtuel flottant : apparaît là où le doigt touche dans la moitié basse
## de l'écran. `output` : direction de longueur 0..1 (zone morte appliquée).
## Actif seulement sur appareil tactile, ou si [joystick] force_on_desktop=true.

## Direction courante (longueur 0..1).
var output: Vector2 = Vector2.ZERO

var radius: float = 110.0
var dead_zone: float = 0.15
## Fraction de la hauteur d'écran à partir de laquelle un toucher active le joystick.
var activation_top_ratio: float = 0.5

var _enabled: bool = false
var _touch_index: int = -1
var _base_pos: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("virtual_joystick")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Ne bloque jamais les autres UI : on lit les touches dans _input.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	radius = Balance.get_float("joystick", "radius", 110.0)
	dead_zone = Balance.get_float("joystick", "dead_zone", 0.15)
	activation_top_ratio = Balance.get_float("joystick", "activation_top_ratio", 0.5)
	var force: bool = bool(Balance.get_value("joystick", "force_on_desktop", false))
	_enabled = DisplayServer.is_touchscreen_available() or force
	visible = _enabled
	set_process_input(_enabled)


func is_held() -> bool:
	return _touch_index >= 0


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		var local: Vector2 = _to_local(t.position)
		if t.pressed and _touch_index < 0 and local.y >= size.y * activation_top_ratio:
			_touch_index = t.index
			_base_pos = local
			_knob_pos = local
			_update_output()
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _touch_index:
			_knob_pos = _to_local(d.position)
			_update_output()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree():
			_release()
		elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
			_release()


func _to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _release() -> void:
	_touch_index = -1
	output = Vector2.ZERO
	queue_redraw()


func _update_output() -> void:
	var offset: Vector2 = _knob_pos - _base_pos
	if offset.length() > radius:
		offset = offset.normalized() * radius
		_knob_pos = _base_pos + offset
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


func _draw() -> void:
	if not is_held():
		return
	draw_circle(_base_pos, radius, Color(0, 0, 0, 0.25))
	draw_arc(_base_pos, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
	draw_circle(_base_pos, radius * dead_zone, Color(1, 1, 1, 0.12))
	draw_circle(_knob_pos, radius * 0.38, Color(1, 1, 1, 0.55))
	draw_arc(_knob_pos, radius * 0.38, 0.0, TAU, 32, Color(0.9, 0.1, 0.1, 0.6), 3.0, true)
