class_name MapTile
extends Button
## Tuile de carte pour la sélection de carte (style des cartes de masque) :
## vignette du biome aux coins arrondis + badges (catégorie, difficulté, temps restant),
## nom, biome, étiquettes de propriétés, récompense indicative.
## Modes : COMPACT (grille), FEATURED (événement mis en avant, large), STRIP (bandeau bas,
## prochain événement). `upcoming` : pas encore commencé (non jouable).
## Monde absent → tuile grisée « Bientôt ».
## Le temps restant est rafraîchi de l'extérieur (refresh_time, 1×/s par la sélection).

enum Mode { COMPACT, FEATURED, STRIP }

const CATEGORY_BADGE := {
	&"event": ["ÉVÉNEMENT", Color(0.85, 0.16, 0.2)],
	&"weekly": ["HEBDO", Color(0.25, 0.5, 0.95)],
	&"monthly": ["MENSUELLE", Color(0.85, 0.6, 0.15)],
	&"permanent": ["PERMANENTE", Color(0.3, 0.36, 0.5)],
}

const FEATURED_KICKER := {
	&"event": "ÉVÉNEMENT EN COURS",
	&"weekly": "CARTE DE LA SEMAINE",
	&"monthly": "CARTE DU MOIS",
	&"permanent": "TOUJOURS DISPONIBLE",
}

var entry: Dictionary = {}
var card: MapCard = null
var mode: Mode = Mode.COMPACT
## Pas encore commencé (prochain événement) : visible mais non jouable.
var upcoming: bool = false
var selected: bool = false
var time_label: Label = null
var _time_pill: PanelContainer = null
var _normal: StyleBoxFlat = null
var _sel: StyleBoxFlat = null


func _init(p_entry: Dictionary = {}, p_mode: Mode = Mode.COMPACT, p_upcoming: bool = false) -> void:
	entry = p_entry
	card = p_entry.get("card") as MapCard
	mode = p_mode
	upcoming = p_upcoming


func is_playable() -> bool:
	return card != null and card.is_available() and not upcoming


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	text = ""
	clip_contents = false
	var accent: Color = card.accent_color if card != null else MenuKit.GOLD
	_normal = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.94), Color(0.85, 0.88, 0.95, 0.28), 18, 1, 10)
	var hover := _normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.1, 0.14, 0.25, 0.96)
	hover.border_color = Color(accent, 0.75)
	_sel = MenuKit.panel_style(Color(0.09, 0.12, 0.22, 0.98), accent.lightened(0.1), 18, 3, 10)
	_sel.shadow_color = Color(accent, 0.45)
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
	MenuKit.add_feedback(self, 1.02 if mode == Mode.FEATURED else 1.03)
	if card != null:
		match mode:
			Mode.FEATURED:
				_build_featured()
			Mode.STRIP:
				_build_strip()
			_:
				_build_compact()
	_refresh()
	refresh_time(MapRotation.now())


# --- Construction ------------------------------------------------------------------

func _build_compact() -> void:
	custom_minimum_size.y = Balance.get_float("maps", "tile_height", 262.0)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 10
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var thumb := _thumb_block(118.0, false)
	col.add_child(thumb)
	var n := MenuKit.label(card.display_name, 20 if card.display_name.length() <= 20 else 17, MenuKit.TEXT, MenuKit.nunito(900))
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size = Vector2(0, 26)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(n)
	col.add_child(MenuKit.label(card.biome_name(), 14, MenuKit.TEXT_DIM, MenuKit.nunito(700)))
	col.add_child(_tags_row(card.get_tags(), 1))
	var reward := MenuKit.label(card.reward_text, 14, MenuKit.GOLD, MenuKit.nunito(800))
	reward.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(reward)


## Événement mis en avant : grande vignette à gauche, infos et compte à rebours à droite.
func _build_featured() -> void:
	custom_minimum_size.y = Balance.get_float("maps", "tile_height", 262.0) + 40.0
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -14
	row.offset_top = 12
	row.offset_bottom = -12
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var thumb := _thumb_block(0.0, true)
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.size_flags_stretch_ratio = 1.15
	row.add_child(thumb)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var kicker_text: String = "PROCHAIN ÉVÉNEMENT" if upcoming else String(FEATURED_KICKER.get(card.category, ""))
	var kicker_color: Color = MenuKit.TEXT_DIM if upcoming else (CATEGORY_BADGE.get(card.category, ["", MenuKit.GOLD])[1] as Color).lightened(0.35)
	var kicker := MenuKit.label(kicker_text, 15, kicker_color, MenuKit.nunito(1000))
	col.add_child(kicker)
	var n := MenuKit.title(card.display_name, 34, card.accent_color.lerp(Color.WHITE, 0.55))
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(n)
	var sub := HBoxContainer.new()
	sub.add_theme_constant_override("separation", 10)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(difficulty_badge(card.difficulty, false))
	var biome := MenuKit.label(card.biome_name(), 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	biome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.add_child(biome)
	col.add_child(sub)
	var desc := MenuKit.label(card.description, 15, MenuKit.TEXT_DIM, MenuKit.nunito(650))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.max_lines_visible = 3
	col.add_child(desc)
	col.add_child(_tags_row(card.get_tags(), 1))
	time_label = MenuKit.label("", 28, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	col.add_child(time_label)
	var reward := MenuKit.label("Récompense : " + card.reward_text, 15, MenuKit.GOLD, MenuKit.nunito(800))
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(reward)


## Bandeau « prochain événement » : mini vignette, nom, difficulté, compte à rebours.
func _build_strip() -> void:
	custom_minimum_size.y = 92.0
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -16
	row.offset_top = 10
	row.offset_bottom = -10
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var thumb := _thumb_block(0.0, false)
	thumb.custom_minimum_size = Vector2(128, 0)
	row.add_child(thumb)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	col.add_child(MenuKit.label("PROCHAIN ÉVÉNEMENT" if upcoming else "ÉVÉNEMENT", 13, MenuKit.TEXT_DIM, MenuKit.nunito(1000)))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	var n := MenuKit.label(card.display_name, 22, MenuKit.TEXT, MenuKit.nunito(900))
	line.add_child(n)
	var db := difficulty_badge(card.difficulty, true)
	db.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(db)
	col.add_child(MenuKit.label(" · ".join(card.get_tags()), 14, MenuKit.TEXT_DIM, MenuKit.nunito(700)))
	time_label = MenuKit.label("", 22, MenuKit.GOLD, MenuKit.nunito(1000), 4)
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(time_label)


## Vignette aux coins arrondis (clip) + badges superposés.
func _thumb_block(height: float, big: bool) -> Control:
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.custom_minimum_size = Vector2(0, height)
	var fs := StyleBoxFlat.new()
	fs.bg_color = card.accent_color.darkened(0.6)
	fs.set_corner_radius_all(12)
	fs.anti_aliasing = true
	frame.add_theme_stylebox_override("panel", fs)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var tex := TextureRect.new()
	tex.texture = card.get_thumbnail()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tex)
	if card.is_night():
		var night := ColorRect.new()
		night.color = Color(0.05, 0.07, 0.25, 0.45)
		night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		night.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(night)
	# Dégradé bas pour la lisibilité des badges
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_color(1, Color(0.02, 0.03, 0.08, 0.75))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.35)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(shade)
	# Difficulté (haut droite) ; la catégorie est donnée par l'onglet.
	if mode == Mode.COMPACT:
		var diff := difficulty_badge(card.difficulty, true)
		diff.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		diff.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		diff.offset_right = -8
		diff.offset_top = 8
		frame.add_child(diff)
		# Temps restant (bas gauche)
		_time_pill = pill("", Color(MenuKit.NIGHT_DEEP, 0.85), 13)
		time_label = _time_pill.get_child(0) as Label
		_time_pill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_time_pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_time_pill.offset_left = 8
		_time_pill.offset_bottom = -8
		frame.add_child(_time_pill)
	if not card.is_available():
		var soon := MenuKit.label("BIENTÔT", 30 if big else 22, MenuKit.TEXT, MenuKit.RYE, 6)
		soon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		soon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(soon)
	return frame


## Étiquettes de propriétés (puces), sur `rows` lignes au plus (le surplus est coupé).
static func _tags_row(tags: PackedStringArray, rows: int) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.clip_contents = true
	holder.custom_minimum_size = Vector2(0, 24 * rows + 4 * (rows - 1))
	var flow := HFlowContainer.new()
	flow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 4)
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(flow)
	for t: String in tags:
		flow.add_child(pill(t, Color(0.16, 0.2, 0.34, 0.95), 13, Color(0.85, 0.88, 0.95, 0.3)))
	return holder


# --- Petits éléments réutilisables ---------------------------------------------------

## Pastille arrondie avec texte.
static func pill(txt: String, bg: Color, font_size: int = 13, border: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(9)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 1
	s.content_margin_bottom = 2
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.anti_aliasing = true
	p.add_theme_stylebox_override("panel", s)
	p.add_child(MenuKit.label(txt, font_size, MenuKit.TEXT, MenuKit.nunito(900)))
	return p


## Badge de difficulté : nom + 5 pastilles (remplies jusqu'au niveau), couleur du niveau.
static func difficulty_badge(level: int, compact: bool) -> PanelContainer:
	var lv: int = clampi(level, 0, MapCard.DIFFICULTY_NAMES.size() - 1)
	var c: Color = MapCard.DIFFICULTY_COLORS[lv]
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.name = "DifficultyBadge"
	var s := StyleBoxFlat.new()
	s.bg_color = c.darkened(0.45)
	s.border_color = c.lightened(0.25)
	s.set_border_width_all(2)
	s.set_corner_radius_all(10)
	s.content_margin_left = 8
	s.content_margin_right = 9
	s.content_margin_top = 2
	s.content_margin_bottom = 3
	s.anti_aliasing = true
	p.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var l := MenuKit.label(MapCard.DIFFICULTY_NAMES[lv], 13 if compact else 15, MenuKit.TEXT, MenuKit.nunito(1000))
	l.name = "Name"
	row.add_child(l)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(pips)
	var d: float = 7.0 if compact else 9.0
	for i: int in MapCard.DIFFICULTY_NAMES.size():
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.custom_minimum_size = Vector2(d, d)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ds := StyleBoxFlat.new()
		ds.bg_color = c.lightened(0.35) if i <= lv else Color(0, 0, 0, 0.35)
		ds.set_corner_radius_all(int(d))
		ds.anti_aliasing = true
		dot.add_theme_stylebox_override("panel", ds)
		pips.add_child(dot)
	return p


# --- État ----------------------------------------------------------------------------

func set_selected(on: bool) -> void:
	selected = on
	_refresh()


func _refresh() -> void:
	if _normal == null:
		return
	add_theme_stylebox_override("normal", _sel if selected else _normal)
	var dimmed: bool = card == null or not card.is_available() or upcoming
	self_modulate = Color.WHITE
	modulate = Color(0.62, 0.64, 0.7, 1.0) if dimmed else Color.WHITE


## Texte du temps restant (« Fin dans 01:23:45 », « Commence dans … », « Reste 3 j 4 h »).
static func time_text(e: Dictionary, now: int, upcoming: bool = false, long_form: bool = false) -> String:
	var end: int = int(e.get("ends_at", 0))
	if upcoming:
		return "Commence dans " + MapRotation.format_hms(int(e.get("starts_at", 0)) - now)
	if end <= 0:
		return "Toujours disponible"
	var left: int = maxi(end - now, 0)
	var cat: StringName = e.get("category", &"")
	if cat == MapCard.CATEGORY_EVENT or left < 86400:
		return ("Fin dans " if long_form or cat == MapCard.CATEGORY_EVENT else "") + MapRotation.format_hms(left)
	return ("Reste " if long_form else "") + MapRotation.format_short(left)


func refresh_time(now: int) -> void:
	if time_label == null or card == null:
		return
	time_label.text = time_text(entry, now, upcoming, mode == Mode.FEATURED)
	if _time_pill != null:
		_time_pill.visible = int(entry.get("ends_at", 0)) > 0 or upcoming
