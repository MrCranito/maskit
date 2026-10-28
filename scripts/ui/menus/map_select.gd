class_name MapSelect
extends Control
## Sélection de la carte (ouverte par « Jouer ») : onglets Événements (mis en avant,
## compte à rebours en direct), Hebdomadaires, Mensuelle, Toujours disponibles.
## Une tuile par carte disponible (MapRotation.available_cards) ; sélection → panneau de
## détail (description, propriétés, récompense, masque porté + « Changer de masque »)
## → « Partir en raid » : GameState.set_current_map(carte) (monde, difficulté, seed) puis
## res://scenes/dungeon/raid.tscn. Monde absent → carte grisée « Bientôt », non jouable.
## Les comptes à rebours sont rafraîchis 1×/s par un Timer (pas de _process) ; la liste
## est reconstruite quand une période se termine (fin d'événement, nouvelle semaine…).

const TABS: Array[StringName] = [&"event", &"weekly", &"monthly", &"permanent"]
const TAB_TITLES := {
	&"event": "Événements",
	&"weekly": "Hebdomadaires",
	&"monthly": "Mensuelle",
	&"permanent": "Toujours disponibles",
}

const GRID_GAP := 14

## Dernière carte sélectionnée (conservée au retour de la sélection du masque).
static var last_selected_id: StringName = &""
## Dernier onglet ouvert.
static var last_tab: StringName = &""

## Scène lancée par « Partir en raid » ("" = aucun changement de scène, pour les tests).
var raid_scene: String = MenuKit.RAID_SCENE
var entries: Array[Dictionary] = []
var next_event: Dictionary = {}
var tiles: Array[MapTile] = []
var tab_buttons: Dictionary = {}       ## catégorie → Button
var current_tab: StringName = &"event"
var selected_entry: Dictionary = {}
var launch_button: Button = null
var back_button: Button = null
var change_mask_button: Button = null
var tick_timer: Timer = null

var _background: MenuBackground = null
var _content: VBoxContainer = null
var _scroll: ScrollContainer = null
var _next_label: Label = null
var _tab_subs: Dictionary = {}         ## catégorie → Label (ligne secondaire de l'onglet)
var _detail_style: StyleBoxFlat = null
var _d_thumb: TextureRect = null
var _d_thumb_frame: Panel = null
var _d_soon: Label = null
var _d_badge_holder: Control = null
var _d_name: Label = null
var _d_sub: Label = null
var _d_time: Label = null
var _d_desc: Label = null
var _d_props: VBoxContainer = null
var _d_reward: Label = null
var _period_end: int = 0               ## prochaine échéance qui change la rotation
var _columns: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	_background = MenuBackground.new()
	_background.dim = Balance.get_float("menu", "mask_select_dim", 0.35)
	add_child(_background)
	_build()
	tick_timer = Timer.new()
	tick_timer.wait_time = 1.0
	tick_timer.autostart = true
	tick_timer.timeout.connect(_tick)
	add_child(tick_timer)
	refresh_rotation()
	MenuKit.fade_in(self)


# --- Construction -------------------------------------------------------------------

func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	back_button = MenuKit.button("‹  Retour", MenuKit.Style.GHOST, 22, Vector2(160, 56))
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var t := MenuKit.title("Choisis ta carte", 46)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	_next_label = MenuKit.label("", 17, MenuKit.TEXT_DIM, MenuKit.nunito(800), 4)
	_next_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_next_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)

	# Gauche : onglets + contenu
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(left)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(tabs)
	var group := ButtonGroup.new()
	for cat: StringName in TABS:
		var b := _tab_button(cat, group)
		tabs.add_child(b)
		tab_buttons[cat] = b
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_content)
	# Nombre de colonnes selon la largeur (1280 → 3, 1600 → 4) : reconstruit si besoin.
	_scroll.resized.connect(func() -> void:
		if is_inside_tree() and _grid_columns() != _columns:
			_fill_tab.call_deferred())

	body.add_child(_build_detail())


## Onglet : titre + ligne secondaire (compte à rebours / nombre de cartes).
func _tab_button(cat: StringName, group: ButtonGroup) -> Button:
	var b := MenuKit.button("", MenuKit.Style.GHOST, 18, Vector2(0, 62))
	b.toggle_mode = true
	b.button_group = group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent: Color = (MapTile.CATEGORY_BADGE[cat][1] as Color)
	var on := MenuKit.panel_style(accent.darkened(0.45), accent.lightened(0.3), 16, 2, 8)
	on.shadow_color = Color(accent, 0.45)
	on.shadow_size = 10
	on.shadow_offset = Vector2.ZERO
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var title := MenuKit.label(String(TAB_TITLES[cat]), 18, MenuKit.TEXT, MenuKit.nunito(900), 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := MenuKit.label("", 13, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	_tab_subs[cat] = sub
	b.custom_minimum_size.x = title.get_minimum_size().x + 28.0
	b.toggled.connect(func(pressed: bool) -> void:
		if pressed and current_tab != cat:
			MenuKit.sfx(&"tick")
			show_tab(cat))
	return b


func _build_detail() -> Control:
	var panel := PanelContainer.new()
	_detail_style = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.92), MenuKit.BORDER, 22, 2, 14)
	panel.add_theme_stylebox_override("panel", _detail_style)
	panel.custom_minimum_size = Vector2(Balance.get_float("maps", "detail_width", 380.0), 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	_d_thumb_frame = Panel.new()
	_d_thumb_frame.custom_minimum_size = Vector2(0, 128)
	var fs := StyleBoxFlat.new()
	fs.bg_color = MenuKit.NIGHT_DEEP
	fs.set_corner_radius_all(14)
	fs.anti_aliasing = true
	_d_thumb_frame.add_theme_stylebox_override("panel", fs)
	_d_thumb_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	col.add_child(_d_thumb_frame)
	_d_thumb = TextureRect.new()
	_d_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_d_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_d_thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_d_thumb_frame.add_child(_d_thumb)
	_d_soon = MenuKit.label("BIENTÔT", 30, MenuKit.TEXT, MenuKit.RYE, 6)
	_d_soon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_d_soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_d_soon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_d_thumb_frame.add_child(_d_soon)
	_d_badge_holder = Control.new()
	_d_badge_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_d_badge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d_thumb_frame.add_child(_d_badge_holder)

	_d_name = MenuKit.title("", 30)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_d_name)
	_d_sub = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	col.add_child(_d_sub)
	_d_time = MenuKit.label("", 17, MenuKit.GOLD, MenuKit.nunito(1000))
	col.add_child(_d_time)
	_d_desc = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(650))
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_d_desc)

	var props_scroll := ScrollContainer.new()
	props_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	props_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	props_scroll.custom_minimum_size = Vector2(0, 40)
	col.add_child(props_scroll)
	_d_props = VBoxContainer.new()
	_d_props.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_props.add_theme_constant_override("separation", 3)
	props_scroll.add_child(_d_props)

	_d_reward = MenuKit.label("", 16, MenuKit.GOLD, MenuKit.nunito(900))
	_d_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_d_reward)
	col.add_child(_build_mask_row())
	launch_button = MenuKit.button("Partir en raid", MenuKit.Style.PRIMARY, 28, Vector2(0, 68))
	launch_button.pressed.connect(launch_selected)
	col.add_child(launch_button)
	return panel


## Masque porté + « Changer de masque ».
func _build_mask_row() -> Control:
	var mask: MaskData = GameState.get_selected_mask()
	var p := MenuKit.panel(Color(0.05, 0.07, 0.14, 0.85), 14, 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(44, 44)
	portrait.texture = mask.portrait if mask != null else null
	row.add_child(portrait)
	var txt := VBoxContainer.new()
	txt.alignment = BoxContainer.ALIGNMENT_CENTER
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.add_theme_constant_override("separation", -3)
	row.add_child(txt)
	txt.add_child(MenuKit.label("Masque porté", 13, MenuKit.TEXT_DIM, MenuKit.nunito(700)))
	txt.add_child(MenuKit.label(mask.display_name if mask != null else "-", 20,
		mask.aura_color.lightened(0.25) if mask != null else MenuKit.TEXT, MenuKit.nunito(900)))
	change_mask_button = MenuKit.button("Changer", MenuKit.Style.SECONDARY, 17, Vector2(118, 46))
	change_mask_button.add_theme_constant_override("outline_size", 2)
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := change_mask_button.get_theme_stylebox(st).duplicate() as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			change_mask_button.add_theme_stylebox_override(st, sb)
	change_mask_button.pressed.connect(open_mask_select)
	row.add_child(change_mask_button)
	return p


# --- Rotation et onglets --------------------------------------------------------------

## Recalcule les cartes disponibles (heure UTC) et reconstruit l'onglet courant.
func refresh_rotation() -> void:
	var now: int = MapRotation.now()
	entries = MapRotation.available_cards(now)
	next_event = MapRotation.next_event(now)
	_period_end = _compute_period_end(now)
	var tab: StringName = last_tab
	if tab == &"" or not TABS.has(tab):
		tab = &"event"
	# Sélection conservée si la carte est toujours disponible.
	var keep: Dictionary = _find_entry(last_selected_id)
	if not keep.is_empty():
		tab = keep["category"]
	current_tab = &""
	show_tab(tab)
	if not keep.is_empty():
		select_entry(keep, false)
	_update_tab_subs(now)
	_update_next_label(now)


func _compute_period_end(now: int) -> int:
	var t: int = int(next_event.get("starts_at", 0)) if not next_event.is_empty() else 0
	for e: Dictionary in entries:
		var end: int = int(e["ends_at"])
		if end > now and (t <= 0 or end < t):
			t = end
	return t


func entries_of(cat: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in entries:
		if e["category"] == cat:
			out.append(e)
	return out


func _find_entry(map_id: StringName) -> Dictionary:
	if map_id == &"":
		return {}
	for e: Dictionary in entries:
		if (e["card"] as MapCard).id == map_id:
			return e
	return {}


func show_tab(cat: StringName) -> void:
	if cat == current_tab:
		return
	current_tab = cat
	last_tab = cat
	var b: Button = tab_buttons.get(cat)
	if b != null and not b.button_pressed:
		b.set_pressed_no_signal(true)
	_fill_tab()
	# Sélection par défaut : première carte jouable de l'onglet.
	if selected_entry.is_empty() or selected_entry["category"] != cat or _tile_for(selected_entry) == null:
		var first: MapTile = null
		for t: MapTile in tiles:
			if first == null or (t.is_playable() and not first.is_playable()):
				first = t
		if first != null:
			select_entry(first.entry, false)
		else:
			_show_detail({})


## Remplit la zone de contenu avec les tuiles de l'onglet courant.
func _fill_tab() -> void:
	if _content == null:
		return
	for c: Node in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	tiles.clear()
	var now: int = MapRotation.now()
	var list: Array[Dictionary] = entries_of(current_tab)
	if current_tab == MapCard.CATEGORY_EVENT:
		if not list.is_empty():
			_add_tile(list[0], MapTile.Mode.FEATURED, false, _content)
		if not next_event.is_empty():
			_add_tile(next_event, MapTile.Mode.FEATURED if list.is_empty() else MapTile.Mode.STRIP, true, _content)
		_content.add_child(_note(_event_rule_text()))
	elif current_tab == MapCard.CATEGORY_MONTHLY and not list.is_empty():
		for e: Dictionary in list:
			_add_tile(e, MapTile.Mode.FEATURED, false, _content)
		_content.add_child(_note("Nouvelle carte le 1er de chaque mois, 00:00 UTC."))
	else:
		var grid := GridContainer.new()
		grid.columns = _grid_columns()
		_columns = grid.columns
		grid.add_theme_constant_override("h_separation", GRID_GAP)
		grid.add_theme_constant_override("v_separation", GRID_GAP)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(grid)
		for e: Dictionary in list:
			var t := _add_tile(e, MapTile.Mode.COMPACT, false, grid)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Cases vides pour garder la largeur des tuiles quand il y en a peu.
		for i: int in maxi(0, grid.columns - list.size()):
			var filler := Control.new()
			filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(filler)
		if list.is_empty():
			_content.add_child(_note("Aucune carte pour le moment."))
		match current_tab:
			MapCard.CATEGORY_WEEKLY:
				_content.add_child(_note("Nouvelles cartes chaque lundi à 00:00 UTC."))
			MapCard.CATEGORY_MONTHLY:
				_content.add_child(_note("Nouvelle carte le 1er de chaque mois, 00:00 UTC."))
	for t: MapTile in tiles:
		t.set_selected(not selected_entry.is_empty() and _same(t.entry, selected_entry))
		t.refresh_time(now)
	_wire_focus()


func _grid_columns() -> int:
	var avail: float = _scroll.size.x if _scroll != null and _scroll.size.x > 0.0 else 800.0
	var min_w: float = Balance.get_float("maps", "tile_min_width", 250.0)
	return maxi(1, floori((avail + GRID_GAP) / (min_w + GRID_GAP)))


func _add_tile(e: Dictionary, mode: MapTile.Mode, upcoming: bool, parent: Node) -> MapTile:
	var t := MapTile.new(e, mode, upcoming)
	t.pressed.connect(func() -> void:
		if not selected_entry.is_empty() and _same(selected_entry, t.entry):
			if t.is_playable():
				launch_button.grab_focus()
		else:
			select_entry(t.entry))
	parent.add_child(t)
	tiles.append(t)
	return t


func _note(txt: String) -> Label:
	var l := MenuKit.label(txt, 15, MenuKit.TEXT_DIM, MenuKit.nunito(700), 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _event_rule_text() -> String:
	var period: float = Balance.get_float("maps", "event_period_hours", 6.0)
	var dur: float = Balance.get_float("maps", "event_duration_hours", 2.0)
	var off: float = Balance.get_float("maps", "event_offset_hours", 0.0)
	# Horaires affichés en heure locale (la rotation, elle, est calculée en UTC).
	var bias_min: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var mins: Array[int] = []
	var h: float = fmod(off, period)
	while h < 24.0 and mins.size() < 12:
		mins.append(posmod(roundi(h * 60.0) + bias_min, 24 * 60))
		h += period
	mins.sort()
	var hours := PackedStringArray()
	for m: int in mins:
		hours.append("%02d:%02d" % [m / 60, m % 60])
	var listing: String = ", ".join(hours.slice(0, hours.size() - 1)) + " et " + hours[hours.size() - 1] \
		if hours.size() > 1 else ", ".join(hours)
	return "Chaque jour, un événement de %s h commence à %s (heure locale)." % [MapCard._fmt_mult(dur), listing]


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("card") == b.get("card") and int(a.get("starts_at", 0)) == int(b.get("starts_at", 0))


func _tile_for(e: Dictionary) -> MapTile:
	for t: MapTile in tiles:
		if _same(t.entry, e):
			return t
	return null


## Navigation manette : onglets ↔ tuiles ↔ bouton de lancement.
func _wire_focus() -> void:
	var first_tab: Button = tab_buttons[TABS[0]]
	back_button.focus_neighbor_bottom = back_button.get_path_to(first_tab)
	for cat: StringName in TABS:
		var b: Button = tab_buttons[cat]
		b.focus_neighbor_top = b.get_path_to(back_button)
		if not tiles.is_empty():
			b.focus_neighbor_bottom = b.get_path_to(tiles[0])
	for t: MapTile in tiles:
		t.focus_neighbor_right = t.get_path_to(launch_button) if t == tiles[tiles.size() - 1] else NodePath()
	if not tiles.is_empty():
		launch_button.focus_neighbor_left = launch_button.get_path_to(tiles[0])


# --- Détail ---------------------------------------------------------------------------

## Sélectionne une entrée (tuile) et affiche son détail.
func select_entry(e: Dictionary, with_sound: bool = true) -> void:
	selected_entry = e
	var card: MapCard = e.get("card") as MapCard
	if card != null:
		last_selected_id = card.id
	for t: MapTile in tiles:
		t.set_selected(_same(t.entry, e))
	_show_detail(e)
	if with_sound:
		MenuKit.sfx(&"click_soft", -4.0)


func _is_upcoming(e: Dictionary) -> bool:
	return int(e.get("starts_at", 0)) > MapRotation.now()


func _show_detail(e: Dictionary) -> void:
	var card: MapCard = e.get("card") as MapCard
	for holder: Node in [_d_badge_holder, _d_props]:
		for c: Node in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	if card == null:
		_d_name.text = "Aucune carte"
		_d_sub.text = ""
		_d_time.text = ""
		_d_desc.text = ""
		_d_reward.text = ""
		_d_thumb.texture = null
		_d_soon.visible = false
		launch_button.disabled = true
		return
	var accent: Color = card.accent_color
	_detail_style.border_color = Color(accent, 0.8)
	_detail_style.shadow_color = Color(accent, 0.3)
	_background.set_glow_color(accent)
	_d_thumb.texture = card.get_thumbnail()
	_d_thumb.modulate = Color(0.55, 0.6, 0.95) if card.is_night() else Color.WHITE
	_d_soon.visible = not card.is_available()
	var badge := MapTile.difficulty_badge(card.difficulty, false)
	badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.offset_right = -8
	badge.offset_top = 8
	_d_badge_holder.add_child(badge)
	var cb: Array = MapTile.CATEGORY_BADGE.get(card.category, ["", MenuKit.NIGHT])
	var cat := MapTile.pill(String(cb[0]), cb[1] as Color, 13)
	cat.position = Vector2(8, 8)
	_d_badge_holder.add_child(cat)
	_d_name.text = card.display_name
	_d_name.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.6))
	_d_name.add_theme_font_size_override("font_size", 30 if card.display_name.length() <= 18 else 25)
	_d_sub.text = "%s  ·  %s" % [card.biome_name(), card.category_name()]
	_d_desc.text = card.description
	for line: Dictionary in card.describe_modifiers():
		_d_props.add_child(_prop_line(String(line["text"]), bool(line["good"])))
	if _d_props.get_child_count() == 0:
		_d_props.add_child(_prop_line("Règles normales", true))
	_d_reward.text = "Récompense : " + card.reward_text if card.reward_text != "" else ""
	_refresh_detail_time(MapRotation.now())
	_refresh_launch()


## Ligne de propriété : pastille verte (favorable) ou rouge (défavorable) + texte.
func _prop_line(txt: String, good: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(9, 9)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.45, 0.9, 0.5) if good else Color(1.0, 0.42, 0.38)
	ds.set_corner_radius_all(5)
	ds.anti_aliasing = true
	dot.add_theme_stylebox_override("panel", ds)
	row.add_child(dot)
	var l := MenuKit.label(txt, 15, MenuKit.TEXT, MenuKit.nunito(750))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


func _refresh_launch() -> void:
	var card: MapCard = selected_entry.get("card") as MapCard
	if card == null:
		launch_button.disabled = true
		return
	if not card.is_available():
		launch_button.disabled = true
		launch_button.text = "Bientôt"
	elif _is_upcoming(selected_entry):
		launch_button.disabled = true
		launch_button.text = "Pas encore ouvert"
	elif not MapRotation.is_active(selected_entry, MapRotation.now()):
		launch_button.disabled = true
		launch_button.text = "Terminé"
	else:
		launch_button.disabled = false
		launch_button.text = "Partir en raid"


func _refresh_detail_time(now: int) -> void:
	if selected_entry.is_empty():
		_d_time.text = ""
		return
	_d_time.text = MapTile.time_text(selected_entry, now, _is_upcoming(selected_entry), true)


# --- Temps réel -----------------------------------------------------------------------

## 1×/s : comptes à rebours ; reconstruction quand une période se termine.
func _tick() -> void:
	var now: int = MapRotation.now()
	if _period_end > 0 and now >= _period_end:
		refresh_rotation()
		return
	for t: MapTile in tiles:
		t.refresh_time(now)
	_refresh_detail_time(now)
	_update_tab_subs(now)
	_update_next_label(now)


func _update_tab_subs(now: int) -> void:
	for cat: StringName in TABS:
		var l: Label = _tab_subs.get(cat)
		if l == null:
			continue
		var list: Array[Dictionary] = entries_of(cat)
		match cat:
			MapCard.CATEGORY_EVENT:
				if not list.is_empty():
					l.text = "En cours · " + MapRotation.format_hms(MapRotation.time_left(list[0], now))
					l.add_theme_color_override("font_color", Color(1.0, 0.62, 0.55))
				elif not next_event.is_empty():
					l.text = "Dans " + MapRotation.format_short(int(next_event["starts_at"]) - now)
					l.add_theme_color_override("font_color", MenuKit.TEXT_DIM)
			MapCard.CATEGORY_PERMANENT:
				l.text = "%d cartes" % list.size()
			_:
				l.text = ("Reste " + MapRotation.format_short(MapRotation.time_left(list[0], now))) if not list.is_empty() else "-"


func _update_next_label(now: int) -> void:
	if next_event.is_empty():
		_next_label.text = ""
		return
	_next_label.text = "Prochain événement dans %s" % MapRotation.format_short(int(next_event["starts_at"]) - now)


# --- Actions --------------------------------------------------------------------------

## « Partir en raid » : fixe la carte (monde, difficulté, seed) et lance le raid.
func launch_selected() -> bool:
	var card: MapCard = selected_entry.get("card") as MapCard
	_refresh_launch()
	if card == null or launch_button.disabled:
		return false
	GameState.set_current_map(card)
	MenuKit.sfx(&"confirm_big")
	MenuKit.vibrate(40)
	if raid_scene != "":
		MenuKit.go_to(self, raid_scene, Balance.get_float("menu", "fade_time", 0.3) * 1.5)
	return true


func open_mask_select() -> void:
	MenuKit.sfx(&"click")
	MaskSelect.return_scene = MenuKit.MAP_SELECT_SCENE
	MenuKit.go_to(self, MenuKit.MASK_SELECT_SCENE)


func go_back() -> void:
	MenuKit.sfx(&"back")
	MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()
