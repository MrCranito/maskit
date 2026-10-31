class_name OnlineSwitch
extends PanelContainer
## Petit interrupteur « EN LIGNE / HORS LIGNE » sous DÉPLOYER (lobby, direction « D ») : deux
## segments dans un boîtier encre translucide à coins biseautés ; le segment actif est une
## pastille violette pleine, l'autre reste en blanc atténué. Point vert / gris devant le libellé
## actif. Lit et écrit OnlineMode (réglage du profil) ; `locked` (salon coop ouvert) empêche de
## passer hors ligne. Hauteur du boîtier : [menu] online_switch_height (46 px, segments 38 px).

signal changed(online: bool)
## Tap sur un segment refusé (verrouillé) : le lobby affiche pourquoi.
signal refused

var online_button: Button = null
var offline_button: Button = null
var locked: bool = false:
	set(v):
		locked = v
		_refresh()


func _init() -> void:
	name = "OnlineSwitch"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h: float = Balance.get_float("menu", "online_switch_height", 46.0)
	var box := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.72), 12.0, Color(1, 1, 1, 0.18), 1.0, 4.0, 4.0)
	box.corners = CutBox.CUT_TOP_LEFT | CutBox.CUT_BOTTOM_RIGHT
	add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	var group := ButtonGroup.new()
	online_button = _segment("En ligne", h - 8.0, group)
	online_button.name = "OnlineButton"
	online_button.pressed.connect(func() -> void: _choose(true))
	row.add_child(online_button)
	offline_button = _segment("Hors ligne", h - 8.0, group)
	offline_button.name = "OfflineButton"
	offline_button.pressed.connect(func() -> void: _choose(false))
	row.add_child(offline_button)


func _ready() -> void:
	OnlineMode.notifier.changed.connect(_on_mode)
	_refresh()


func _exit_tree() -> void:
	if OnlineMode.notifier.changed.is_connected(_on_mode):
		OnlineMode.notifier.changed.disconnect(_on_mode)


func is_online() -> bool:
	return OnlineMode.is_online()


func _choose(on: bool) -> void:
	if on == OnlineMode.is_online():
		_refresh()
		return
	if locked and not on:
		MenuKit.sfx(&"error")
		_refresh()
		refused.emit()
		return
	MenuKit.sfx(&"click_soft")
	OnlineMode.set_online(on)


func _on_mode(on: bool) -> void:
	_refresh()
	changed.emit(on)


func _refresh() -> void:
	if online_button == null:
		return
	var on := OnlineMode.is_online()
	online_button.set_pressed_no_signal(on)
	offline_button.set_pressed_no_signal(not on)
	offline_button.modulate.a = 0.45 if locked and on else 1.0
	for b: Button in [online_button, offline_button]:
		(b.get_node("Dot") as Control).queue_redraw()


## Segment : texte en capitales (Space Grotesk), pastille violette pleine une fois actif, point
## d'état (vert en ligne, gris hors ligne) dessiné à gauche du libellé.
func _segment(txt: String, h: float, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, h)
	b.text = txt.to_upper()
	b.add_theme_font_override("font", MenuKit.nunito(700))
	b.add_theme_font_size_override("font_size", int(Balance.get_value("menu", "online_switch_font", 15)))
	var pad: float = 14.0
	var off := CutBox.make(Color(0, 0, 0, 0), 8.0, Color(0, 0, 0, 0), 0.0, pad, 0.0)
	off.content_margin_left = pad + 14.0
	var hov := off.duplicate() as CutBox
	hov.bg_color = Color(1, 1, 1, 0.08)
	var on := off.duplicate() as CutBox
	on.bg_color = MenuKit.VIOLET
	on.corners = CutBox.CUT_TOP_LEFT | CutBox.CUT_BOTTOM_RIGHT
	var focus := CutBox.new()
	focus.draw_center = false
	focus.border_color = MenuKit.TEXT
	focus.border_width = 2.0
	focus.cut = 8.0
	focus.grow = 2.0
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	b.add_theme_color_override("font_hover_color", MenuKit.TEXT)
	for k: String in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, MenuKit.TEXT)
	var dot := Control.new()
	dot.name = "Dot"
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	dot.offset_left = pad - 2.0
	dot.offset_right = pad + 8.0
	var is_online_seg := txt == "En ligne"
	dot.draw.connect(func() -> void:
		var active := b.button_pressed
		var c := (MenuKit.GOOD if is_online_seg else Color(1, 1, 1, 0.75)) if active else Color(1, 1, 1, 0.3)
		dot.draw_circle(Vector2(5.0, dot.size.y * 0.5), 4.0, c, true, -1.0, true))
	b.add_child(dot)
	b.toggled.connect(func(_p: bool) -> void: dot.queue_redraw())
	return b
