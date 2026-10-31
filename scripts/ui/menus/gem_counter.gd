class_name GemCounter
extends PanelContainer
## Compteur de gemmes (pastille encre soulignée, direction D : gemme dessinée + nombre). Se met à jour sur
## Profile.gems_changed (pas de _process). `pressed` : tap (ex. ouvrir l'onglet Gemmes).

signal pressed

var value_label: Label = null
var _shown: int = -1


func _init(font_size: int = 24) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", MenuKit.currency_style(MenuKit.GEM))
	custom_minimum_size = Vector2(0, 60)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var icon := GemIcon.new()
	icon.custom_minimum_size = Vector2(font_size + 10, font_size + 10)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	value_label = MenuKit.label("0", font_size, MenuKit.TEXT, MenuKit.nunito(700), 0)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	tooltip_text = "Gemmes : uniquement pour les skins"


func _ready() -> void:
	Profile.gems_changed.connect(_on_gems)
	refresh(false)


func refresh(animate: bool = true) -> void:
	_on_gems(Profile.gems, animate)


func _on_gems(g: int, animate: bool = true) -> void:
	if value_label == null:
		return
	var old: int = _shown
	_shown = g
	MenuKit.set_amount(value_label, g)
	if animate and old >= 0 and old != g and is_inside_tree():
		pivot_offset = size * 0.5
		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "scale", Vector2.ONE, 0.3).from(Vector2(1.15, 1.15))
		value_label.add_theme_color_override("font_color", MenuKit.GEM if g > old else MenuKit.BAD)
		tw.tween_callback(func() -> void: MenuKit.set_amount(value_label, _shown))


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		accept_event()
		MenuKit.sfx(&"click_soft")
		pressed.emit()
