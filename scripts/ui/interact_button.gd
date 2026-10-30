class_name InteractButton
extends Control
## Bouton tactile « action » (bas droite, au-dessus du stick de visée) : grand
## disque bleu nuit cerclé d'or, icône + libellé court (« Fouiller », « Se cacher »,
## « Sortir », « Ouvrir »). Visible seulement quand une cible est à portée
## (EventBus.interact_target_changed). Maintenir = fouiller (anneau de progression).
## Touches : lues dans _input (avant les joysticks, qui prennent les nouveaux
## contacts en _unhandled_input) ; souris PC : clic gauche. Redessin seulement
## quand l'état change (libellé, appui, progression de fouille).

signal pressed_action
signal released_action

const NIGHT_BLUE := Color(0.071, 0.102, 0.18, 0.94)
const NIGHT_BLUE_PRESSED := Color(0.13, 0.17, 0.28, 0.98)
const GOLD := Color(0.95, 0.76, 0.38)
const BORDER_LIGHT := Color(0.85, 0.88, 0.95, 0.9)
const ICONS := {
	"search": "res://assets/third_party/icons/item_magnifier.svg",
	"open": "res://assets/third_party/icons/container_chest_open.svg",
	"hide": "res://assets/third_party/icons/world_saloon_doors.svg",
	"exit": "res://assets/third_party/icons/world_exit_door.svg",
}

## Rayon du disque (px écran).
@export var radius: float = 58.0

var controller: InteractController = null
var _label_text: String = ""
var _icon: Texture2D = null
var _touch_index: int = -1
var _mouse_down: bool = false
var _progress: float = 0.0
var _label: Label = null
var _tween: Tween = null
var _suppressed: bool = false
var _has_target: bool = false


func _ready() -> void:
	name = "InteractButton"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(radius * 2.0 + 8.0, radius * 2.0 + 8.0)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	visible = false
	set_process(false)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.label_settings = LootVisuals.label_settings(LootVisuals.text_font(800), 17, Color.WHITE, 5)
	_label.size = Vector2(size.x + 40.0, 26.0)
	_label.position = Vector2(-20.0, size.y * 0.5 + 12.0)
	add_child(_label)
	EventBus.interact_target_changed.connect(_on_target_changed)
	EventBus.search_progress.connect(_on_search_progress)


## Ancre en bas à droite, au-dessus du stick droit (position relative au viewport).
func place_above_right_stick(viewport_size: Vector2, rest_x: float, rest_y: float, stick_radius: float) -> void:
	# Relevé ([hud] action_button_lift) pour laisser la place au bouton Recharger du HUD compact.
	var c := Vector2(viewport_size.x * rest_x, viewport_size.y * rest_y - stick_radius - radius - 26.0
		- Balance.get_float("hud", "action_button_lift", 40.0))
	position = c - size * 0.5


func _on_target_changed(target: Node) -> void:
	if target == null or not is_instance_valid(target):
		_has_target = false
		_set_shown(false)
		return
	_label_text = String(target.call("get_interact_label")) if target.has_method("get_interact_label") else "Action"
	var icon_key := String(target.call("get_interact_icon")) if target.has_method("get_interact_icon") else "search"
	_icon = LootVisuals.load_icon(String(ICONS.get(icon_key, ICONS["search"])))
	_label.text = _label_text
	_progress = 0.0
	_has_target = not _label_text.is_empty()
	_set_shown(_has_target and not _suppressed)
	queue_redraw()


func _on_search_progress(_target: Node2D, ratio: float) -> void:
	if not visible:
		return
	_progress = ratio
	queue_redraw()


func _set_shown(on: bool) -> void:
	if on == visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if on:
		visible = true
		scale = Vector2(0.6, 0.6)
		modulate.a = 0.0
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	else:
		_release_all()
		visible = false


## Masqué tant qu'une fenêtre le recouvre (butin, inventaire).
func set_suppressed(on: bool) -> void:
	_suppressed = on
	_set_shown(_has_target and not on)


func get_label_text() -> String:
	return _label_text if visible else ""


func is_pressed() -> bool:
	return _touch_index >= 0 or _mouse_down


func _hit(screen_pos: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	return local.distance_to(size * 0.5) <= radius + 10.0


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed and _touch_index < 0 and _hit(t.position):
			_touch_index = t.index
			_do_press()
			get_viewport().set_input_as_handled()
		elif not t.pressed and t.index == _touch_index:
			_touch_index = -1
			_do_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed and not _mouse_down and _hit(mb.position):
			_mouse_down = true
			_do_press()
			get_viewport().set_input_as_handled()
		elif not mb.pressed and _mouse_down:
			_mouse_down = false
			_do_release()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
		get_viewport().set_input_as_handled()


func _do_press() -> void:
	queue_redraw()
	pressed_action.emit()
	if controller != null:
		controller.press()


func _do_release() -> void:
	queue_redraw()
	released_action.emit()
	if controller != null:
		controller.release()


func _release_all() -> void:
	if is_pressed():
		_touch_index = -1
		_mouse_down = false
		_do_release()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_all()


func _draw() -> void:
	var c := size * 0.5
	var pressed := is_pressed()
	var r := radius * (0.94 if pressed else 1.0)
	# Ombre portée bleu nuit.
	draw_circle(c + Vector2(0, 4), r + 2.0, Color(0.02, 0.03, 0.07, 0.45))
	draw_circle(c, r, NIGHT_BLUE_PRESSED if pressed else NIGHT_BLUE)
	draw_arc(c, r - 1.0, 0.0, TAU, 64, BORDER_LIGHT, 1.5, true)
	draw_arc(c, r - 6.0, 0.0, TAU, 64, Color(GOLD, 0.55), 2.0, true)
	if _progress > 0.0:
		draw_arc(c, r - 6.0, -PI * 0.5, -PI * 0.5 + TAU * _progress, 64, GOLD, 7.0, true)
	if _icon != null:
		var s := r * 1.0
		draw_texture_rect(_icon, Rect2(c - Vector2(s, s) * 0.5 + Vector2(0, -2), Vector2(s, s)), false, Color(1.0, 0.95, 0.85))
