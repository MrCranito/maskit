class_name TouchScroller
extends Node
## Défilement au doigt pour un ScrollContainer de menu (MenuKit.make_touch_scroll) :
##  - un glisser qui COMMENCE N'IMPORTE OÙ dans la liste (même sur un bouton ou une carte) fait
##    défiler, avec inertie au lâcher ;
##  - au-delà du seuil (`threshold` px), le bouton touché est « désarmé » (BaseButton remis à zéro
##    par disabled = true/false) : le lâcher ne déclenche PAS de clic ;
##  - un simple tap reste un clic normal.
## Écoute les événements tactiles (InputEventScreenTouch/Drag, doigt 0) dans _input : iPhone en
## natif, PC via `emulate_touch_from_mouse`. Les mouvements d'un glisser sont consommés (le
## défilement natif du ScrollContainer ne s'y ajoute pas). _process seulement pendant l'inertie.

## Distance (px) avant que le geste devienne un défilement.
var threshold: float = 12.0
## Décélération de l'inertie (px/s²) et vitesse minimale (px/s).
var friction: float = 2600.0
var min_speed: float = 40.0

var scroll: ScrollContainer = null
var dragging: bool = false
var _tracking: bool = false
var _start: Vector2 = Vector2.ZERO
var _start_scroll: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _last_t: int = 0
var _velocity: Vector2 = Vector2.ZERO
var _fling: Vector2 = Vector2.ZERO
var _pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	scroll = get_parent() as ScrollContainer
	set_process(false)


func _horizontal() -> bool:
	return scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
		and scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED


func _vertical_ok() -> bool:
	return scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


func _horizontal_ok() -> bool:
	return scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED


func _input(event: InputEvent) -> void:
	if scroll == null or not scroll.is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.index != 0:
			return
		if t.pressed:
			if not scroll.get_global_rect().has_point(t.position) or _blocked(t.position):
				return
			_tracking = true
			dragging = false
			_start = t.position
			_last_pos = t.position
			_last_t = Time.get_ticks_msec()
			_start_scroll = Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
			_pos = _start_scroll
			_velocity = Vector2.ZERO
			set_process(false)
		elif _tracking:
			_tracking = false
			if dragging:
				dragging = false
				_fling = _velocity
				set_process(_fling.length() > min_speed)
	elif event is InputEventScreenDrag and _tracking:
		var d := event as InputEventScreenDrag
		if d.index != 0:
			return
		var delta: Vector2 = d.position - _start
		if not dragging:
			var along: float = absf(delta.x) if _horizontal() else absf(delta.y)
			if along < threshold:
				return
			dragging = true
			_disarm_buttons(_start)
		var now := Time.get_ticks_msec()
		var dt: float = maxf((now - _last_t) / 1000.0, 0.001)
		var inst: Vector2 = -(d.position - _last_pos) / dt
		_velocity = _velocity.lerp(inst, 0.5)
		_last_pos = d.position
		_last_t = now
		_pos = _start_scroll - delta
		_apply()
		scroll.get_viewport().set_input_as_handled()


## Un autre écran modal est-il au-dessus du point ? (on ne défile pas sous une fenêtre)
func _blocked(_p: Vector2) -> bool:
	for m: Node in scroll.get_tree().get_nodes_in_group(&"menu_modals"):
		if (m as CanvasItem).is_visible_in_tree() and not m.is_ancestor_of(scroll):
			return true
	return false


func _apply() -> void:
	if _horizontal_ok():
		scroll.scroll_horizontal = int(_pos.x)
	if _vertical_ok():
		scroll.scroll_vertical = int(_pos.y)
	# bornes réelles (le ScrollContainer borne lui-même)
	_pos = Vector2(scroll.scroll_horizontal if _horizontal_ok() else _pos.x,
		scroll.scroll_vertical if _vertical_ok() else _pos.y)


## Remet à zéro les boutons sous le doigt : leur lâcher ne sera pas un clic.
func _disarm_buttons(p: Vector2) -> void:
	for n: Node in scroll.find_children("*", "BaseButton", true, false):
		var b := n as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.get_global_rect().has_point(p):
			b.disabled = true
			b.disabled = false


func _process(delta: float) -> void:
	_pos += _fling * delta
	var before := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical)
	_apply()
	var sp := _fling.length()
	sp = maxf(sp - friction * delta, 0.0)
	_fling = _fling.normalized() * sp
	if sp < min_speed or Vector2(scroll.scroll_horizontal, scroll.scroll_vertical) == before:
		set_process(false)
