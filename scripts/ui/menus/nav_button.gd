class_name NavButton
extends Button
## Bouton de la barre de navigation du lobby : pictogramme (MenuGlyph) au-dessus d'un libellé
## court. Fond bleu nuit translucide, liseré or au focus, retours tactiles MenuKit.

var glyph: MenuGlyph = null
var caption: Label = null


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
	glyph = MenuGlyph.new(glyph_kind, accent, 34)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(glyph)
	caption = MenuKit.label(label_text, 14, MenuKit.TEXT, MenuKit.nunito(900), 3)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caption)


func _ready() -> void:
	MenuKit.add_feedback(self, 1.08)
