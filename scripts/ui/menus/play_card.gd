class_name PlayCard
extends Button
## Grand bouton « JOUER » du lobby (bas droite) : vignette de la carte sélectionnée, nom,
## difficulté (pastille colorée), catégorie ; flèche « lecture ». Mène au choix des cartes.
## Carte affichée : GameState.current_map, sinon la première carte proposée par la rotation.

var card: MapCard = null
var title_label: Label = null
var map_label: Label = null
var diff_pill: PanelContainer = null
var cat_label: Label = null
var thumb: TextureRect = null
var _glint: ColorRect = null


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(Balance.get_float("menu", "play_card_width", 420.0),
		Balance.get_float("menu", "play_card_height", 148.0))
	clip_contents = false
	text = ""
	var r: int = 22
	var normal := MenuKit._button_box(MenuKit.RED, Color(1.0, 0.62, 0.5, 0.95), 7, r)
	normal.shadow_color = Color(0.4, 0.02, 0.05, 0.45)
	normal.shadow_size = 14
	normal.shadow_offset = Vector2(0, 5)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = MenuKit.RED.lightened(0.12)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = MenuKit.RED.darkened(0.18)
	pressed.border_width_bottom = 3
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MenuKit.GOLD
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(r + 4)
	focus.set_expand_margin_all(5)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("hover_pressed", pressed)
	add_theme_stylebox_override("focus", focus)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_top = 12
	row.offset_right = -14
	row.offset_bottom = -16
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	# vignette arrondie (panneau sombre + texture)
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := MenuKit.panel_style(MenuKit.NIGHT_DEEP, Color(1, 0.85, 0.75, 0.6), 14, 2, 3)
	fs.shadow_size = 0
	frame.add_theme_stylebox_override("panel", fs)
	frame.custom_minimum_size = Vector2(custom_minimum_size.y * 0.95, 0)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	row.add_child(frame)
	thumb = TextureRect.new()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(thumb)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	title_label = MenuKit.label("JOUER", 46, MenuKit.TEXT, RaidersLogo.slant_font(), 7)
	title_label.add_theme_color_override("font_outline_color", Color(0.3, 0.02, 0.05, 0.9))
	title_label.add_theme_color_override("font_shadow_color", Color(0.25, 0.0, 0.03, 0.7))
	title_label.add_theme_constant_override("shadow_offset_y", 4)
	top.add_child(title_label)
	var play := MenuGlyph.new(&"play", MenuKit.TEXT, 34)
	play.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(play)
	map_label = MenuKit.label("", 21, MenuKit.TEXT, MenuKit.nunito(900), 3)
	map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_label.add_theme_color_override("font_outline_color", Color(0.25, 0.0, 0.04, 0.7))
	col.add_child(map_label)
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", 8)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(info)
	diff_pill = MenuKit.pill("", MenuKit.NIGHT_DEEP, 14)
	info.add_child(diff_pill)
	cat_label = MenuKit.label("", 15, Color(1, 0.88, 0.82), MenuKit.nunito(800))
	cat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.add_child(cat_label)
	# reflet qui balaie le bouton de temps en temps (attire l'œil sur l'action principale)
	_glint = ColorRect.new()
	_glint.color = Color(1, 1, 1, 0.16)
	_glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glint.size = Vector2(46, custom_minimum_size.y * 1.6)
	_glint.rotation = 0.38
	_glint.position = Vector2(-120, -30)
	clip_contents = true
	add_child(_glint)


func _ready() -> void:
	MenuKit.add_feedback(self, 1.03)
	refresh()
	var tw := create_tween().set_loops()
	tw.tween_interval(Balance.get_float("menu", "play_glint_interval", 4.5))
	tw.tween_property(_glint, "position:x", custom_minimum_size.x + 80.0, 0.7).from(-120.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Carte affichée : celle choisie (GameState.current_map), sinon la première de la rotation.
static func displayed_card() -> MapCard:
	var c: MapCard = GameState.current_map as MapCard
	if c != null:
		return c
	var offered := MapRotation.offered_cards(MapRotation.now())
	for e: Dictionary in offered:
		if e.get("card") is MapCard:
			return e["card"] as MapCard
	return null


func refresh() -> void:
	card = displayed_card()
	if card == null:
		map_label.text = "Choisir une carte"
		diff_pill.visible = false
		cat_label.text = ""
		return
	map_label.text = card.display_name
	thumb.texture = card.get_thumbnail()
	var dc: Color = card.difficulty_color()
	var pill_style := diff_pill.get_theme_stylebox("panel") as StyleBoxFlat
	pill_style.bg_color = dc.darkened(0.25)
	pill_style.border_color = dc.lightened(0.35)
	pill_style.set_border_width_all(1)
	(diff_pill.get_node("Text") as Label).text = card.difficulty_name()
	diff_pill.visible = true
	cat_label.text = card.category_name()
