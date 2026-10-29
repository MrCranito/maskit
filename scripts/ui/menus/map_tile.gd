class_name MapTile
extends Button
## Vignette de carte (écran « Choisis ta carte ») : aperçu du biome en pleine vignette,
## badge de catégorie (Événement / Hebdo / Mensuelle / Permanente) avec minuteur, nom et
## pastille de difficulté en bas sur un dégradé. Sélection : liseré à la couleur de la carte
## + lueur + léger agrandissement (Tween). Modes : COMPACT (grille), FEATURED (événement
## en cours, vignette haute). `upcoming` : pas encore commencé (visible, non jouable).
## Monde absent → vignette grisée « Bientôt ». Minuteur rafraîchi de l'extérieur (1×/s).

enum Mode { COMPACT, FEATURED }

## Catégorie → [libellé du badge, couleur].
const CATEGORY_BADGE := {
	&"event": ["Événement", Color(0.86, 0.16, 0.2)],
	&"weekly": ["Hebdo", Color(0.22, 0.5, 0.95)],
	&"monthly": ["Mensuelle", Color(0.86, 0.58, 0.12)],
	&"permanent": ["Permanente", Color(0.3, 0.36, 0.5)],
}

var entry: Dictionary = {}
var card: MapCard = null
var mode: Mode = Mode.COMPACT
var upcoming: bool = false
var selected: bool = false
var time_label: Label = null
var name_label: Label = null
var _time_pill: PanelContainer = null
var _frame: Panel = null
var _ring: Panel = null
var _ring_style: StyleBoxFlat = null
var _sel_tween: Tween = null


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
	var empty := StyleBoxEmpty.new()
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(st, empty)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MenuKit.GOLD
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(2)
	focus.set_expand_margin_all(5)
	add_theme_stylebox_override("focus", focus)
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	if card != null:
		_build()
	MenuKit.add_feedback(self, 1.03)
	_refresh()
	refresh_time(MapRotation.now())


func _build() -> void:
	var accent: Color = card.accent_color
	_frame = Panel.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.bg_color = accent.darkened(0.65)
	fs.set_corner_radius_all(2)
	fs.anti_aliasing = true
	_frame.add_theme_stylebox_override("panel", fs)
	_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(_frame)
	var tex := TextureRect.new()
	tex.texture = card.get_thumbnail()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(tex)
	if card.is_night():
		var night := ColorRect.new()
		night.color = Color(0.04, 0.06, 0.24, 0.5)
		night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		night.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(night)
	_frame.add_child(_gradient(accent))

	# Haut : catégorie (gauche), minuteur (droite)
	var cb: Array = CATEGORY_BADGE.get(card.category, ["", MenuKit.NIGHT])
	var cat_text: String = "Prochain événement" if upcoming else String(cb[0])
	var cat := MenuKit.pill(cat_text, Color(cb[1] as Color, 0.92) if not upcoming else Color(MenuKit.NIGHT_DEEP, 0.9),
		14, MenuKit.TEXT, Color(1, 1, 1, 0.25))
	cat.position = Vector2(10, 10)
	_frame.add_child(cat)
	_time_pill = MenuKit.pill("", Color(MenuKit.NIGHT_DEEP, 0.86), 14, MenuKit.GOLD)
	time_label = _time_pill.get_node(^"Text") as Label
	_time_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_time_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_time_pill.offset_right = -10
	_time_pill.offset_top = 10
	_frame.add_child(_time_pill)
	if upcoming and mode == Mode.COMPACT:
		# Petite vignette : le minuteur passe sous le badge (pas la place sur une ligne).
		_time_pill.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_time_pill.grow_horizontal = Control.GROW_DIRECTION_END
		_time_pill.offset_left = 10
		_time_pill.offset_right = 10
		_time_pill.offset_top = 42
		_time_pill.offset_bottom = 42

	# Bas : nom + difficulté
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_left = 12
	col.offset_right = -12
	col.offset_bottom = -12
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(col)
	var featured: bool = mode == Mode.FEATURED
	var nsize: int = 32 if featured else (20 if card.display_name.length() <= 16 else 17)
	name_label = MenuKit.label(card.display_name, nsize, MenuKit.TEXT, MenuKit.nunito(1000), 5)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	col.add_child(name_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	row.add_child(difficulty_badge(card.difficulty, true))
	if not card.is_available():
		var soon := MenuKit.label("Bientôt", 30, MenuKit.TEXT, MenuKit.nunito(1000), 6)
		soon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		soon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_frame.add_child(soon)

	# Liseré de sélection (au-dessus de tout, hors du clip)
	_ring = Panel.new()
	_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring_style = StyleBoxFlat.new()
	_ring_style.draw_center = false
	_ring_style.set_corner_radius_all(2)
	_ring_style.anti_aliasing = true
	_ring.add_theme_stylebox_override("panel", _ring_style)
	add_child(_ring)


## Dégradé vertical sombre (bas de la vignette) pour la lisibilité du texte.
static func _gradient(accent: Color) -> TextureRect:
	var shade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.03, 0.08, 0.35))
	g.add_point(0.3, Color(0, 0, 0, 0))
	g.add_point(0.55, Color(0.02, 0.03, 0.08, 0.15))
	g.set_color(g.get_point_count() - 1, Color(accent.darkened(0.85), 0.95))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return shade


# --- Petits éléments réutilisables ---------------------------------------------------

## Pastille arrondie avec texte (compatibilité ; voir MenuKit.pill).
static func pill(txt: String, bg: Color, font_size: int = 13, border: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	return MenuKit.pill(txt, bg, font_size, MenuKit.TEXT, border)


## Puce de modificateur : verte (favorable) ou rouge (défavorable).
static func modifier_chip(line: Dictionary, font_size: int = 15) -> PanelContainer:
	var good: bool = bool(line.get("good", true))
	var c: Color = MenuKit.GOOD if good else MenuKit.BAD
	var p := MenuKit.pill(("▲ " if good else "▼ ") + String(line.get("short", "")), Color(c.darkened(0.62), 0.92),
		font_size, c.lightened(0.45), Color(c, 0.7))
	return p


## Badge de difficulté : nom + 5 pastilles (remplies jusqu'au niveau), couleur du niveau.
## (Utilisé aussi par le bandeau de raid, scripts/dungeon/raid.gd.)
static func difficulty_badge(level: int, compact: bool) -> PanelContainer:
	var lv: int = clampi(level, 0, MapCard.DIFFICULTY_NAMES.size() - 1)
	var c: Color = MapCard.DIFFICULTY_COLORS[lv]
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.name = "DifficultyBadge"
	var s := StyleBoxFlat.new()
	s.bg_color = c.darkened(0.5)
	s.border_color = c.lightened(0.25)
	s.set_border_width_all(2)
	s.set_corner_radius_all(2)
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
	var l := MenuKit.label(MapCard.DIFFICULTY_NAMES[lv], 14 if compact else 16, MenuKit.TEXT, MenuKit.nunito(1000))
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
	var changed: bool = on != selected
	selected = on
	_refresh()
	if changed and is_inside_tree():
		if _sel_tween != null and _sel_tween.is_valid():
			_sel_tween.kill()
		_sel_tween = null
		if on:
			_sel_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_sel_tween.tween_property(self, "scale", Vector2.ONE, 0.28).from(Vector2(0.94, 0.94))
		else:
			scale = Vector2.ONE


func _refresh() -> void:
	if card == null or _ring_style == null:
		return
	var accent: Color = card.accent_color
	if selected:
		_ring_style.border_color = MenuKit.VIOLET_LIGHT
		_ring_style.set_border_width_all(4)
		_ring_style.shadow_color = Color(MenuKit.VIOLET, 0.55)
		_ring_style.shadow_size = 18
	else:
		_ring_style.border_color = Color(1, 1, 1, 0.16)
		_ring_style.set_border_width_all(1)
		_ring_style.shadow_color = Color(0, 0, 0.05, 0.45)
		_ring_style.shadow_size = 6
	_ring_style.shadow_offset = Vector2.ZERO
	_ring.queue_redraw()
	var dimmed: bool = not card.is_available() or upcoming
	_frame.modulate = Color(0.6, 0.62, 0.7) if dimmed else Color.WHITE


## Texte du temps restant (« 01:23:45 », « Dans 05:12:00 », « 3 j 4 h »).
static func time_text(e: Dictionary, now: int, p_upcoming: bool = false, long_form: bool = false) -> String:
	var end: int = int(e.get("ends_at", 0))
	if p_upcoming:
		return ("Commence dans " if long_form else "Dans ") + MapRotation.format_hms(int(e.get("starts_at", 0)) - now)
	if end <= 0:
		return "Toujours disponible" if long_form else ""
	var left: int = maxi(end - now, 0)
	var cat: StringName = e.get("category", &"")
	if cat == MapCard.CATEGORY_EVENT or left < 86400:
		return ("Fin dans " if long_form else "") + MapRotation.format_hms(left)
	return ("Reste " if long_form else "") + MapRotation.format_short(left)


func refresh_time(now: int) -> void:
	if time_label == null or card == null:
		return
	var t: String = time_text(entry, now, upcoming, false)
	time_label.text = t
	_time_pill.visible = not t.is_empty()
