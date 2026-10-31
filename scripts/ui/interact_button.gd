class_name InteractButton
extends Control
## Bouton tactile « action » (bas droite, au-dessus du stick de visée), direction D : disque
## encre, halo violet qui respire pour attirer l'œil, icône blanche et libellé en Anton sur
## une étiquette biseautée (« FOUILLER », « SE CACHER », « SORTIR », « OUVRIR »).
## Visible seulement quand une cible est à portée (EventBus.interact_target_changed) :
## apparition en ressort, disparition en fondu. Maintenir = fouiller : anneau violet épais qui
## se remplit avec une tête lumineuse, disque qui se teinte ; fouille terminée ou objet
## ramassé (EventBus.item_picked_up) : onde de choc et icône de l'objet qui jaillit du bouton
## à la couleur de sa rareté.
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
## Animations (s) : respiration du halo, onde de choc, objet qui jaillit.
var _t: float = 0.0
var _burst: float = 0.0
var _pop: float = 0.0
var _pop_icon: Texture2D = null
var _pop_tint: Color = Color.WHITE
var _pop_color: Color = Color.WHITE
var _hiding: bool = false


func _ready() -> void:
	name = "InteractButton"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(radius * 2.0 + 8.0, radius * 2.0 + 8.0)
	size = custom_minimum_size
	pivot_offset = size * 0.5
	visible = false
	set_process(false)
	# Libellé (dessiné en Anton sous le disque) ; le Label reste pour l'API get_label_text / tests.
	_label = Label.new()
	_label.visible = false
	add_child(_label)
	EventBus.interact_target_changed.connect(_on_target_changed)
	EventBus.search_progress.connect(_on_search_progress)
	EventBus.item_picked_up.connect(_on_item_picked_up)


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
	if ratio >= 1.0 and _progress < 1.0:
		_burst = 1.0
	_progress = ratio
	queue_redraw()


## Objet ramassé pendant que le bouton est visible : il jaillit du bouton, couleur de rareté.
func _on_item_picked_up(item: Resource, _count: int) -> void:
	var it := item as ItemData
	if it == null or not visible:
		return
	_pop_icon = LootVisuals.item_icon(it)
	_pop_tint = LootVisuals.item_tint(it)
	_pop_color = LootDB.rarity_color(it.rarity)
	_pop = 1.0
	_burst = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	_burst = maxf(_burst - delta * 2.6, 0.0)
	_pop = maxf(_pop - delta * 1.4, 0.0)
	queue_redraw()


func _set_shown(on: bool) -> void:
	if on == (visible and not _hiding):
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if on:
		_hiding = false
		visible = true
		set_process(true)
		scale = Vector2(0.5, 0.5)
		rotation = -0.25
		modulate.a = 0.0
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "rotation", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "modulate:a", 1.0, 0.14)
	else:
		_release_all()
		# Fondu rapide (le bouton n'est plus touchable dès maintenant : _hiding).
		_hiding = true
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(self, "scale", Vector2(0.8, 0.8), 0.14).set_ease(Tween.EASE_IN)
		_tween.tween_property(self, "modulate:a", 0.0, 0.14)
		_tween.chain().tween_callback(func() -> void:
			visible = false
			_hiding = false
			set_process(false))


## Masqué tant qu'une fenêtre le recouvre (butin, inventaire).
func set_suppressed(on: bool) -> void:
	_suppressed = on
	_set_shown(_has_target and not on)


func get_label_text() -> String:
	return _label_text if visible and not _hiding else ""


func is_pressed() -> bool:
	return _touch_index >= 0 or _mouse_down


func _hit(screen_pos: Vector2) -> bool:
	var local := get_global_transform_with_canvas().affine_inverse() * screen_pos
	return local.distance_to(size * 0.5) <= radius + 10.0


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _hiding:
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
	var violet := MenuKit.VIOLET
	var light := MenuKit.GOLD
	# Halo violet qui respire (attire l'œil sans clignoter).
	var breath := 0.5 + 0.5 * sin(_t * 3.2)
	for k in 3:
		draw_circle(c, r + 4.0 + k * 4.0 + breath * 3.0, Color(violet, (0.10 - k * 0.03) * (0.6 + breath * 0.4)))
	# Onde de choc (fouille terminée, objet ramassé).
	if _burst > 0.0:
		var e := 1.0 - _burst
		draw_arc(c, r + 6.0 + e * 46.0, 0.0, TAU, 64, Color(light, _burst * 0.9), 3.0 + _burst * 4.0, true)
	# Disque encre, teinté de violet à mesure que la fouille avance.
	draw_circle(c + Vector2(0, 4), r + 1.0, Color(0, 0, 0, 0.35))
	draw_circle(c, r, Color(MenuKit.NIGHT_DEEP, 0.86).lerp(Color(violet, 0.9), clampf(_progress * 0.55 + (0.35 if pressed else 0.0), 0.0, 1.0)))
	draw_arc(c, r - 1.0, 0.0, TAU, 64, Color(1, 1, 1, 0.28), 1.5, true)
	# Anneau de progression : piste, arc épais violet clair, tête lumineuse.
	var rr := r - 8.0
	draw_arc(c, rr, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 6.0, true)
	if _progress > 0.0:
		var a1 := -PI * 0.5 + TAU * clampf(_progress, 0.0, 1.0)
		draw_arc(c, rr, -PI * 0.5, a1, 64, light, 7.0, true)
		var head := c + Vector2.from_angle(a1) * rr
		draw_circle(head, 7.0, Color(1, 1, 1, 0.35))
		draw_circle(head, 4.5, Color.WHITE)
	# Icône blanche (légèrement agrandie pendant l'appui).
	if _icon != null:
		var s := r * (1.0 if pressed else 0.92)
		draw_texture_rect(_icon, Rect2(c - Vector2(s, s) * 0.5 + Vector2(0, -3), Vector2(s, s)), false, Color.WHITE)
	# Étiquette biseautée sous le disque : libellé en Anton capitales.
	if not _label_text.is_empty():
		var f: Font = MenuKit.display()
		var txt := _label_text.to_upper()
		var fs := 18
		var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(Vector2(c.x - tw * 0.5 - 12.0, c.y + r - 6.0), Vector2(tw + 24.0, 26.0))
		var st := CutBox.make(Color(violet, 0.92) if pressed or _progress > 0.0 else Color(MenuKit.NIGHT_DEEP, 0.9), 7.0)
		draw_style_box(st, box)
		draw_string(f, Vector2(box.position.x + 12.0, box.position.y + 20.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# Objet qui jaillit du bouton (monte, grossit puis s'efface), auréole de rareté.
	if _pop > 0.0 and _pop_icon != null:
		var e2 := 1.0 - _pop
		var pc := c + Vector2(0, -r * 0.2 - e2 * (r + 40.0))
		var ps := r * (0.8 + 0.5 * minf(e2 * 3.0, 1.0))
		var al := minf(_pop * 2.5, 1.0)
		draw_circle(pc, ps * 0.62, Color(_pop_color, 0.35 * al))
		draw_texture_rect(_pop_icon, Rect2(pc - Vector2(ps, ps) * 0.5, Vector2(ps, ps)), false, Color(_pop_tint, al))
