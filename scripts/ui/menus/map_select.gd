class_name MapSelect
extends Control
## « Choisis ta carte » (ouvert par « Jouer ») :
##   haut  : retour, titre, puces de filtre par catégorie (Toutes / Événements / Hebdo /
##           Mensuelle / Permanentes) ;
##   centre: toutes les cartes disponibles d'un coup d'œil, en grandes vignettes sur deux
##           rangées défilables horizontalement (l'événement en cours en grand à gauche) ;
##   bas   : panneau compact de la carte choisie (nom, biome, modificateurs en puces
##           vertes/rouges, récompense, minuteur) + gros bouton « Choisir mon arsenal ».
## Sélection au tap (animation), deuxième tap = bouton d'action. Le bouton ouvre l'écran
## d'arsenal de départ (loadout.tscn) après GameState.set_current_map(carte).
## Rotation : MapRotation (inchangée). Minuteurs : Timer 1×/s ; liste reconstruite quand une
## période se termine. Monde absent → « Bientôt », non jouable.

const FILTERS: Array[StringName] = [&"all", &"event", &"weekly", &"monthly", &"permanent"]
const FILTER_TITLES := {
	&"all": "Toutes", &"event": "Événements", &"weekly": "Hebdo",
	&"monthly": "Mensuelle", &"permanent": "Permanentes",
}
const GAP := 12

## Dernière carte sélectionnée / dernier filtre (conservés au retour de l'arsenal).
static var last_selected_id: StringName = &""
static var last_filter: StringName = &"all"

## Scène ouverte par le bouton d'action ("" = aucun changement de scène, pour les tests).
var next_scene: String = MenuKit.LOADOUT_SCENE
var entries: Array[Dictionary] = []
var next_event: Dictionary = {}
var tiles: Array[MapTile] = []
var filter_chips: Dictionary = {}      ## filtre → Button
var current_filter: StringName = &"all"
var selected_entry: Dictionary = {}
var launch_button: Button = null
var back_button: Button = null
var tick_timer: Timer = null

var _background: MenuBackground = null
var _scroll: ScrollContainer = null
var _strip: HBoxContainer = null
var _detail_style: StyleBoxFlat = null
var _d_name: Label = null
var _d_sub: Label = null
var _d_time: Label = null
var _d_mods: HFlowContainer = null
var _d_reward: Label = null
var _d_status: Label = null
var _period_end: int = 0
var _tile_h: float = 0.0
## Rangées de petites vignettes (2 ou 3, choisi pour tout afficher sans défiler si possible).
var rows: int = 2


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	_background = MenuBackground.new()
	_background.dim = Balance.get_float("menu", "screen_dim", 0.45)
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
	root.add_theme_constant_override("separation", GAP)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	back_button = MenuKit.back_button()
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var t := MenuKit.title("Choisis ta carte", 40)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(chips)
	var group := ButtonGroup.new()
	for f: StringName in FILTERS:
		var accent: Color = MenuKit.GOLD if f == &"all" else (MapTile.CATEGORY_BADGE[f][1] as Color)
		var b := MenuKit.chip(String(FILTER_TITLES[f]), accent, group)
		b.toggled.connect(func(on: bool) -> void:
			if on and current_filter != f:
				MenuKit.sfx(&"tick")
				set_filter(f))
		chips.add_child(b)
		filter_chips[f] = b

	_scroll = ScrollContainer.new()
	MenuKit.make_touch_scroll(_scroll)   # glisser au doigt partout (même sur les boutons)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.scroll_deadzone = 14
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_scroll)
	_strip = HBoxContainer.new()
	_strip.add_theme_constant_override("separation", GAP)
	_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_strip)
	_scroll.resized.connect(func() -> void:
		if not is_inside_tree():
			return
		if _best_rows() != rows:
			_fill()
			if not selected_entry.is_empty():
				select_entry(selected_entry, false)
		elif absf(_scroll.size.y - _tile_h) > 1.0:
			_layout_tiles())

	root.add_child(_build_detail())


## Panneau bas : infos compactes de la carte choisie + bouton d'action.
func _build_detail() -> Control:
	var panel := PanelContainer.new()
	_detail_style = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.94), MenuKit.BORDER, 20, 2, 14)
	_detail_style.content_margin_left = 20
	panel.add_theme_stylebox_override("panel", _detail_style)
	panel.custom_minimum_size = Vector2(0, Balance.get_float("maps", "detail_height", 132.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 14)
	info.add_child(line1)
	_d_name = MenuKit.title("", 30)
	line1.add_child(_d_name)
	_d_sub = MenuKit.label("", 16, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	_d_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_d_sub.size_flags_vertical = Control.SIZE_FILL
	line1.add_child(_d_sub)
	_d_mods = HFlowContainer.new()
	_d_mods.add_theme_constant_override("h_separation", 6)
	_d_mods.add_theme_constant_override("v_separation", 6)
	info.add_child(_d_mods)
	var line3 := HBoxContainer.new()
	line3.add_theme_constant_override("separation", 18)
	info.add_child(line3)
	_d_reward = MenuKit.label("", 16, MenuKit.GOLD, MenuKit.nunito(900))
	line3.add_child(_d_reward)
	_d_time = MenuKit.label("", 16, MenuKit.TEXT, MenuKit.nunito(900))
	line3.add_child(_d_time)

	var act := VBoxContainer.new()
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override("separation", 4)
	row.add_child(act)
	launch_button = MenuKit.button("Choisir mon arsenal", MenuKit.Style.PRIMARY, 26, Vector2(330, 76))
	launch_button.pressed.connect(launch_selected)
	act.add_child(launch_button)
	_d_status = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	_d_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	act.add_child(_d_status)
	return panel


# --- Rotation et filtre -------------------------------------------------------------

## Recalcule les cartes disponibles (heure UTC) et reconstruit la rangée.
func refresh_rotation() -> void:
	var now: int = MapRotation.now()
	entries = MapRotation.offered_cards(now)
	next_event = {} if MapRotation.is_restricted() else MapRotation.next_event(now)
	_period_end = _compute_period_end(now)
	var keep: Dictionary = _find_entry(last_selected_id)
	if not keep.is_empty():
		selected_entry = keep
	var f: StringName = last_filter if FILTERS.has(last_filter) else &"all"
	current_filter = &""
	set_filter(f)
	if not keep.is_empty() and _tile_for(keep) != null:
		select_entry(keep, false)


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
		if cat == &"all" or e["category"] == cat:
			out.append(e)
	return out


func _find_entry(map_id: StringName) -> Dictionary:
	if map_id == &"":
		return {}
	for e: Dictionary in entries:
		if (e["card"] as MapCard).id == map_id:
			return e
	return {}


## Filtre par catégorie (&"all" = toutes).
func set_filter(f: StringName) -> void:
	if f == current_filter:
		return
	current_filter = f
	last_filter = f
	var b: Button = filter_chips.get(f)
	if b != null and not b.button_pressed:
		b.set_pressed_no_signal(true)
	_fill()
	if selected_entry.is_empty() or _tile_for(selected_entry) == null:
		var first: MapTile = null
		for t: MapTile in tiles:
			if first == null or (t.is_playable() and not first.is_playable()):
				first = t
		if first != null:
			select_entry(first.entry, false)
		else:
			selected_entry = {}
			_show_detail({})
	else:
		select_entry(selected_entry, false)
	_scroll.scroll_horizontal = 0


## Crée les vignettes du filtre courant : événement en cours en grand, puis colonnes de 2.
func _fill() -> void:
	for c: Node in _strip.get_children():
		_strip.remove_child(c)
		c.queue_free()
	tiles.clear()
	var list: Array[Dictionary] = entries_of(current_filter)
	var featured: Dictionary = {}
	var rest: Array[Dictionary] = []
	for e: Dictionary in list:
		if featured.is_empty() and e["category"] == MapCard.CATEGORY_EVENT:
			featured = e
		else:
			rest.append(e)
	var show_next: bool = not next_event.is_empty() and (current_filter == &"all" or current_filter == MapCard.CATEGORY_EVENT)
	if featured.is_empty() and show_next:
		_add_tile(next_event, MapTile.Mode.FEATURED, true, _strip)
	elif not featured.is_empty():
		_add_tile(featured, MapTile.Mode.FEATURED, false, _strip)
		if show_next:
			rest.push_front(next_event)
	rows = _best_rows()
	var col: VBoxContainer = null
	for i: int in rest.size():
		if i % rows == 0:
			col = VBoxContainer.new()
			col.add_theme_constant_override("separation", GAP)
			col.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_strip.add_child(col)
		var e: Dictionary = rest[i]
		_add_tile(e, MapTile.Mode.COMPACT, _same(e, next_event) and int(e["starts_at"]) > MapRotation.now(), col)
	if tiles.is_empty():
		var l := MenuKit.label("Aucune carte dans cette catégorie pour le moment.", 20, MenuKit.TEXT_DIM, MenuKit.nunito(800), 4)
		_strip.add_child(l)
	_layout_tiles()
	var now: int = MapRotation.now()
	for t: MapTile in tiles:
		t.refresh_time(now)
	_wire_focus()


## Nombre de rangées : 2 si tout tient en largeur, sinon 3 (si tout tient), sinon 2 (défilement).
func _best_rows() -> int:
	var n: int = entries_of(current_filter).size() + (1 if not next_event.is_empty() else 0)
	var w: float = _scroll.size.x if _scroll != null and _scroll.size.x > 0.0 else 1200.0
	for r: int in [2, 3]:
		if _strip_width(r, n) <= w + 1.0:
			return r
	return 2


## Largeur totale de la rangée pour `r` rangées et `n` vignettes (dont une mise en avant).
func _strip_width(r: int, n: int) -> float:
	var sz: Array[Vector2] = _tile_sizes(r)
	var cols: int = ceili(maxf(n - 1, 0) / float(r))
	return sz[0].x + cols * (sz[1].x + GAP)


## [taille mise en avant, taille compacte] pour `r` rangées.
func _tile_sizes(r: int) -> Array[Vector2]:
	var h: float = _scroll.size.y if _scroll != null and _scroll.size.y > 0.0 else 420.0
	var th: float = floorf((h - GAP * (r - 1)) / r)
	var tw: float = roundf(th * Balance.get_float("maps", "tile_aspect", 1.32))
	var fw: float = roundf(h * Balance.get_float("maps", "featured_aspect", 0.82))
	return [Vector2(fw, h), Vector2(tw, th)]


## Taille des vignettes d'après la hauteur disponible.
func _layout_tiles() -> void:
	_tile_h = _scroll.size.y
	var sz: Array[Vector2] = _tile_sizes(rows)
	for t: MapTile in tiles:
		t.custom_minimum_size = sz[0] if t.mode == MapTile.Mode.FEATURED else sz[1]


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


static func _same(a: Dictionary, b: Dictionary) -> bool:
	return a.get("card") == b.get("card") and int(a.get("starts_at", 0)) == int(b.get("starts_at", 0))


func _tile_for(e: Dictionary) -> MapTile:
	for t: MapTile in tiles:
		if _same(t.entry, e):
			return t
	return null


## Navigation manette : puces ↔ vignettes ↔ bouton d'action.
func _wire_focus() -> void:
	if tiles.is_empty():
		return
	for f: StringName in FILTERS:
		var b: Button = filter_chips[f]
		b.focus_neighbor_bottom = b.get_path_to(tiles[0])
	launch_button.focus_neighbor_top = launch_button.get_path_to(tiles[0])
	for t: MapTile in tiles:
		t.focus_neighbor_top = t.get_path_to(filter_chips[current_filter]) if t.get_index() == 0 else NodePath()
		t.focus_neighbor_bottom = t.get_path_to(launch_button) if t.get_index() == t.get_parent().get_child_count() - 1 else NodePath()


# --- Détail ---------------------------------------------------------------------------

## Sélectionne une entrée (vignette) et affiche son détail.
func select_entry(e: Dictionary, with_sound: bool = true) -> void:
	selected_entry = e
	var card: MapCard = e.get("card") as MapCard
	if card != null:
		last_selected_id = card.id
	for t: MapTile in tiles:
		t.set_selected(_same(t.entry, e))
	var tile := _tile_for(e)
	if tile != null and is_inside_tree():
		_reveal.call_deferred(tile)
	_show_detail(e)
	if with_sound:
		MenuKit.sfx(&"click_soft", -4.0)


## Fait défiler jusqu'à la vignette (si elle existe encore après une reconstruction).
func _reveal(tile: MapTile) -> void:
	if is_instance_valid(tile) and tile.is_inside_tree() and _scroll.is_ancestor_of(tile):
		_scroll.ensure_control_visible(tile)


func _is_upcoming(e: Dictionary) -> bool:
	return int(e.get("starts_at", 0)) > MapRotation.now()


func _show_detail(e: Dictionary) -> void:
	var card: MapCard = e.get("card") as MapCard
	for c: Node in _d_mods.get_children():
		_d_mods.remove_child(c)
		c.queue_free()
	if card == null:
		_d_name.text = "Aucune carte"
		_d_sub.text = ""
		_d_time.text = ""
		_d_reward.text = ""
		_refresh_launch()
		return
	var accent: Color = card.accent_color
	_detail_style.border_color = Color(accent, 0.85)
	_detail_style.shadow_color = Color(accent, 0.3)
	_background.set_glow_color(accent)
	_d_name.text = card.display_name
	_d_name.add_theme_color_override("font_color", accent.lerp(Color.WHITE, 0.7))
	_d_sub.text = "%s  ·  %s" % [card.biome_name(), card.difficulty_name()]
	_d_sub.add_theme_color_override("font_color", card.difficulty_color().lerp(Color.WHITE, 0.45))
	var mods: Array[Dictionary] = card.describe_modifiers()
	for line: Dictionary in mods:
		_d_mods.add_child(MapTile.modifier_chip(line, 15))
	if mods.is_empty():
		_d_mods.add_child(MenuKit.pill("Règles normales", Color(0.16, 0.2, 0.34, 0.95), 15, MenuKit.TEXT_DIM))
	_d_reward.text = ("Récompense : " + card.reward_text) if card.reward_text != "" else ""
	_d_mods.tooltip_text = card.description
	_refresh_detail_time(MapRotation.now())
	_refresh_launch()
	var pnl := _d_name.get_parent().get_parent() as Control
	if pnl != null and is_inside_tree():
		pnl.modulate.a = 0.4
		create_tween().tween_property(pnl, "modulate:a", 1.0, 0.18)


func _refresh_launch() -> void:
	var card: MapCard = selected_entry.get("card") as MapCard
	launch_button.text = "Choisir mon arsenal"
	if card == null:
		launch_button.disabled = true
		_d_status.text = "Choisis une carte"
	elif not card.is_available():
		launch_button.disabled = true
		_d_status.text = "Bientôt disponible"
	elif _is_upcoming(selected_entry):
		launch_button.disabled = true
		_d_status.text = "Pas encore ouverte"
	elif not MapRotation.is_active(selected_entry, MapRotation.now()):
		launch_button.disabled = true
		_d_status.text = "Terminée"
	else:
		launch_button.disabled = false
		_d_status.text = "Étape suivante : tes armes"


func _refresh_detail_time(now: int) -> void:
	if selected_entry.is_empty():
		_d_time.text = ""
		return
	var t: String = MapTile.time_text(selected_entry, now, _is_upcoming(selected_entry), true)
	_d_time.text = t if t != "Toujours disponible" else ""


# --- Temps réel -----------------------------------------------------------------------

## 1×/s : minuteurs ; reconstruction quand une période se termine.
func _tick() -> void:
	var now: int = MapRotation.now()
	if _period_end > 0 and now >= _period_end:
		refresh_rotation()
		return
	for t: MapTile in tiles:
		t.refresh_time(now)
	_refresh_detail_time(now)


# --- Actions --------------------------------------------------------------------------

## Bouton d'action : fixe la carte (monde, difficulté, seed) puis ouvre l'arsenal de départ.
func launch_selected() -> bool:
	var card: MapCard = selected_entry.get("card") as MapCard
	_refresh_launch()
	if card == null or launch_button.disabled:
		MenuKit.sfx(&"error")
		return false
	GameState.set_current_map(card)
	MenuKit.sfx(&"confirm")
	if next_scene != "":
		MenuKit.go_to(self, next_scene)
	return true


func go_back() -> void:
	MenuKit.sfx(&"back")
	MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()
