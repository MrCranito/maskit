class_name MaskCard
extends Button
## Carte de masque (style de la planche) : panneau bleu nuit aux coins arrondis,
## portrait, nom en blanc gras, description courte, 4 barres de stats.
## Sélectionnée : liseré + halo à la couleur d'aura. Badge « Porté » sur le masque équipé.

var mask: MaskData = null
var selected: bool = false
var equipped: bool = false
var _badge: Label = null
var _normal: StyleBoxFlat = null
var _sel: StyleBoxFlat = null


func _init(m: MaskData = null) -> void:
	mask = m


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	text = ""
	var w: float = Balance.get_float("menu", "card_width", 210.0)
	var h: float = Balance.get_float("menu", "card_height", 400.0)
	custom_minimum_size = Vector2(0, h)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_meta(&"max_width", w)
	var aura: Color = mask.aura_color if mask != null else MenuKit.RED
	_normal = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.94), Color(0.85, 0.88, 0.95, 0.28), 18, 1, 12)
	var hover := _normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.1, 0.14, 0.25, 0.96)
	hover.border_color = Color(aura, 0.7)
	_sel = MenuKit.panel_style(Color(0.09, 0.12, 0.22, 0.98), aura.lightened(0.15), 18, 3, 12)
	_sel.shadow_color = Color(aura, 0.45)
	_sel.shadow_size = 16
	_sel.shadow_offset = Vector2.ZERO
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MenuKit.GOLD
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(21)
	focus.set_expand_margin_all(5)
	add_theme_stylebox_override("normal", _normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	add_theme_stylebox_override("hover_pressed", hover)
	add_theme_stylebox_override("focus", focus)
	MenuKit.add_feedback(self, 1.03)
	_build()
	_refresh()


func _build() -> void:
	if mask == null:
		return
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_right = -12
	col.offset_top = 12
	col.offset_bottom = -14
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var portrait := TextureRect.new()
	portrait.texture = mask.portrait
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(0, Balance.get_float("menu", "card_portrait", 150.0))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(portrait)
	var n := MenuKit.label(mask.display_name, 23 if mask.display_name.length() <= 10 else 19,
		MenuKit.TEXT, MenuKit.nunito(900))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.custom_minimum_size = Vector2(0, 32)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(n)
	var tag := MenuKit.label(mask.tagline, 15, MenuKit.TEXT_DIM, MenuKit.nunito(700))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(0, 50)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(tag)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 5)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bars)
	for e: Dictionary in mask.get_stat_entries():
		bars.add_child(stat_bar(String(e["label"]), float(e["value"]), mask.aura_color))

	_badge = MenuKit.label("PORTÉ", 13, MenuKit.NIGHT, MenuKit.nunito(1000))
	var bs := StyleBoxFlat.new()
	bs.bg_color = MenuKit.GOLD
	bs.set_corner_radius_all(8)
	bs.content_margin_left = 8
	bs.content_margin_right = 8
	bs.content_margin_top = 1
	bs.content_margin_bottom = 1
	_badge.add_theme_stylebox_override("normal", bs)
	_badge.position = Vector2(10, 10)
	add_child(_badge)


## Ligne « Libellé ▬▬▬▬▬ » : la barre pleine correspond à balance [menu] stat_bar_max.
static func stat_bar(label_text: String, value: float, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var l := MenuKit.label(label_text, 14, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	l.custom_minimum_size = Vector2(58, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = stat_ratio(value)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(0, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.03, 0.07, 0.9)
	bg.set_corner_radius_all(5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color.lerp(Color.WHITE, 0.1)
	if value < 1.0:
		fg.bg_color = color.darkened(0.25)
	fg.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.set_meta(&"mult", value)
	row.add_child(bar)
	return row


## Multiplicateur → remplissage 0..1 (1,0 = milieu de barre environ).
static func stat_ratio(mult: float) -> float:
	var full: float = Balance.get_float("menu", "stat_bar_max", 1.6)
	return clampf(mult / maxf(full, 0.01), 0.05, 1.0)


func set_selected(on: bool) -> void:
	selected = on
	_refresh()


func set_equipped(on: bool) -> void:
	equipped = on
	_refresh()


func _refresh() -> void:
	if _normal == null:
		return
	add_theme_stylebox_override("normal", _sel if selected else _normal)
	if _badge != null:
		_badge.visible = equipped
