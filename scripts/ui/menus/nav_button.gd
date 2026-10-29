class_name NavButton
extends Button
## Bouton de la barre de navigation du lobby : pictogramme (MenuGlyph) au-dessus d'un libellé
## court. Fond bleu nuit translucide, liseré or au focus, retours tactiles MenuKit.
## Option : pastille de notification (set_badge) et état « Bientôt » (écran pas encore livré).

var glyph: MenuGlyph = null
var caption: Label = null
## Écran cible absent : le bouton affiche « Bientôt » et n'ouvre rien.
var soon: bool = false
var _badge: PanelContainer = null
var _soon_pill: PanelContainer = null


func _init(label_text: String, glyph_kind: StringName, accent: Color = MenuKit.TEXT) -> void:
	text = ""
	tooltip_text = label_text
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(Balance.get_float("menu", "nav_button_width", 88.0),
		Balance.get_float("menu", "nav_button_height", 74.0))
	var n := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.0), Color(1, 1, 1, 0.0), 14, 0, 4)
	n.shadow_size = 0
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(1, 1, 1, 0.08)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(0, 0, 0, 0.25)
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = MenuKit.GOLD
	f.set_border_width_all(2)
	f.set_corner_radius_all(14)
	add_theme_stylebox_override("normal", n)
	add_theme_stylebox_override("hover", h)
	add_theme_stylebox_override("pressed", p)
	add_theme_stylebox_override("hover_pressed", p)
	add_theme_stylebox_override("focus", f)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	glyph = PassGlyph.new(glyph_kind, accent, 34)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(glyph)
	caption = MenuKit.label(label_text, 14, MenuKit.TEXT, MenuKit.nunito(900), 3)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caption)


func _ready() -> void:
	MenuKit.add_feedback(self, 1.08)


## Pastille rouge (nombre) en haut à droite ; 0 = masquée.
func set_badge(n: int) -> void:
	if _badge == null:
		_badge = MenuKit.pill("", MenuKit.RED, 12, MenuKit.TEXT, Color(1, 1, 1, 0.8))
		_badge.name = "Badge"
		_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_badge.offset_left = -30
		_badge.offset_top = 2
		_badge.offset_right = -6
		add_child(_badge)
	_badge.visible = n > 0
	(_badge.get_node("Text") as Label).text = str(n) if n < 100 else "99+"


## Écran pas encore disponible : pastille « Bientôt », pictogramme atténué.
func set_soon(on: bool) -> void:
	soon = on
	glyph.modulate.a = 0.45 if on else 1.0
	caption.modulate.a = 0.6 if on else 1.0
	if on and _soon_pill == null:
		_soon_pill = MenuKit.pill("Bientôt", Color(MenuKit.NIGHT_DEEP, 0.95), 11, MenuKit.GOLD, Color(MenuKit.GOLD, 0.7))
		_soon_pill.name = "Soon"
		_soon_pill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_soon_pill.offset_left = -28
		_soon_pill.offset_right = 28
		_soon_pill.offset_top = 0
		add_child(_soon_pill)
	if _soon_pill != null:
		_soon_pill.visible = on
