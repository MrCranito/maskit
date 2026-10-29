class_name NavButton
extends Button
## Entrée du menu texte du lobby (direction « D ») : libellé en Anton capitales, aligné à gauche,
## blanc atténué au repos ; au survol / focus, blanc plein + barre violette à gauche (maquette).
## Retours tactiles MenuKit. Le pictogramme reste
## disponible (`glyph`) mais n'est pas affiché.
## Option : pastille de notification (set_badge) et état « Bientôt » (écran pas encore livré).

const IDLE := Color(1, 1, 1, 0.55)

var glyph: MenuGlyph = null
var caption: Label = null
## Écran cible absent : le bouton affiche « Bientôt » et n'ouvre rien.
var soon: bool = false
var _bar: ColorRect = null
var _badge: PanelContainer = null
var _soon_pill: PanelContainer = null


func _init(label_text: String, glyph_kind: StringName, accent: Color = MenuKit.TEXT) -> void:
	text = ""
	tooltip_text = label_text
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(Balance.get_float("menu", "nav_row_width", 280.0),
		Balance.get_float("menu", "nav_row_height", 64.0))
	var n := StyleBoxEmpty.new()
	add_theme_stylebox_override("normal", n)
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover_pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_bar = ColorRect.new()
	_bar.color = MenuKit.VIOLET
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.anchor_bottom = 1.0
	_bar.offset_left = 0
	_bar.offset_right = 5
	_bar.offset_top = 15
	_bar.offset_bottom = -15
	_bar.visible = false
	add_child(_bar)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 17
	add_child(row)
	glyph = PassGlyph.new(glyph_kind, accent, 26)
	glyph.visible = false
	row.add_child(glyph)
	caption = MenuKit.label(label_text, int(Balance.get_value("menu", "nav_font_size", 48)), IDLE, MenuKit.display())
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.size_flags_vertical = Control.SIZE_FILL
	row.add_child(caption)
	# le texte du libellé reste en casse d'origine (tests, lecteurs) ; l'affichage passe en capitales
	caption.uppercase = true


func _ready() -> void:
	MenuKit.add_feedback(self, 1.03)
	for sig: Signal in [mouse_entered, focus_entered]:
		sig.connect(func() -> void: _set_active(true))
	for sig: Signal in [mouse_exited, focus_exited]:
		sig.connect(func() -> void: _set_active(has_focus() or is_hovered()))


func _set_active(on: bool) -> void:
	_bar.visible = on
	caption.add_theme_color_override("font_color", MenuKit.TEXT if on else IDLE)


## Pastille (nombre) à droite du libellé ; 0 = masquée.
func set_badge(n: int) -> void:
	if _badge == null:
		_badge = MenuKit.pill("", Color(1.0, 0.24, 0.43), 12, MenuKit.TEXT)
		_badge.name = "Badge"
		_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_badge.offset_left = -34
		_badge.offset_top = 10
		_badge.offset_right = -6
		add_child(_badge)
	_badge.visible = n > 0
	(_badge.get_node("Text") as Label).text = str(n) if n < 100 else "99+"


## Écran pas encore disponible : libellé atténué et pastille « Bientôt » à droite.
func set_soon(on: bool) -> void:
	soon = on
	caption.modulate.a = 0.45 if on else 1.0
	if on and _soon_pill == null:
		_soon_pill = MenuKit.pill("Bientôt", Color(MenuKit.NIGHT_DEEP, 0.9), 11, MenuKit.TEXT_DIM, Color(1, 1, 1, 0.25))
		_soon_pill.name = "Soon"
		_soon_pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		_soon_pill.offset_left = -76
		_soon_pill.offset_right = -8
		_soon_pill.offset_top = -11
		_soon_pill.offset_bottom = 11
		add_child(_soon_pill)
	if _soon_pill != null:
		_soon_pill.visible = on
