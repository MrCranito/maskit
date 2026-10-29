class_name BattlePassScreen
extends Control
## Écran du pass de combat (res://scenes/ui/menus/battle_pass.tscn) — « Saison 1 — Dust Creek ».
##  - En-tête : retour, nom de la saison, gemmes.
##  - Bandeau : badge du palier atteint (étoile de shérif), barre d'XP vers le palier suivant,
##    « Tout récupérer (N) », « Débloquer le Premium » (gemmes) ou « Premium actif ».
##  - Gauche : aperçu de la récompense sélectionnée (skin de personnage en pied comme au lobby,
##    skin d'arme sur l'arme + l'arme tenue en jeu, gemmes, or, objet) et son bouton d'action.
##  - Droite : la piste — 30 paliers défilables horizontalement, deux rangées (gratuit en haut,
##    premium en bas) de part et d'autre d'une voie ferrée : une traverse par palier, la voie se
##    dore jusqu'au palier atteint, le palier suivant est mis en avant.
## Une récompense se récupère une seule fois (bouton « Récupérer » de la case ou de l'aperçu).

const TRACK_FREE := &"free"
const TRACK_PREMIUM := &"premium"

## Skin à mettre en avant à l'ouverture (ex. depuis la boutique) ; vidé à l'ouverture.
static var focus_skin_id: StringName = &""

var bp: BattlePassSystem = null
var back_button: Button = null
var gem_counter: GemCounter = null
var premium_button: Button = null
var premium_badge: Control = null
var claim_all_button: Button = null
var tier_label: Label = null
var xp_label: Label = null
var xp_bar: ProgressBar = null
var last_gain_label: Label = null
## Cases de la piste : "free:5" → Button.
var cells: Dictionary = {}
## Boutons « Récupérer » des cases : "free:5" → Button.
var claim_buttons: Dictionary = {}
## Récompense sélectionnée : {tier, track}.
var selected: Dictionary = {}
var detail_button: Button = null
var detail_preview: HeroPreview = null
var detail_icon: WeaponIcon = null
var detail_held: TextureRect = null
var detail_big: Control = null
var track_scroll: ScrollContainer = null
var rail: Control = null

var _modal: ModalPanel = null
var _d_kicker: Label = null
var _d_name: Label = null
var _d_desc: Label = null
var _d_backdrop: TextureRect = null
var _col_w: float = 118.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	bp = BattlePassSystem.get_instance()
	_col_w = Balance.get_float("menu", "pass_column_width", 118.0)
	var bg := MenuBackground.new()
	bg.dim = Balance.get_float("menu", "screen_dim", 0.45) + 0.1
	add_child(bg)
	_build()
	bp.changed.connect(refresh)
	Profile.changed.connect(refresh)
	refresh()
	var focus: Dictionary = bp.find_skin(focus_skin_id) if not String(focus_skin_id).is_empty() else {}
	focus_skin_id = &""
	if focus.is_empty():
		var t: int = clampi(bp.tier() + (0 if bp.claimable_count() > 0 else 1), 1, bp.max_tier())
		focus = {"tier": _first_claimable_tier(t), "track": TRACK_FREE}
		if bp.reward(int(focus["tier"]), TRACK_FREE).is_empty():
			focus["track"] = TRACK_PREMIUM
	select(int(focus["tier"]), StringName(focus["track"]), false)
	scroll_to_tier.call_deferred(int(focus["tier"]))
	MenuKit.fade_in(self)
	back_button.grab_focus.call_deferred()


func _first_claimable_tier(fallback: int) -> int:
	for t: int in range(1, bp.tier() + 1):
		if bp.can_claim(t, TRACK_FREE) or bp.can_claim(t, TRACK_PREMIUM):
			return t
	return fallback


# --- Construction ------------------------------------------------------------------------

func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)

	# En-tête
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	back_button = MenuKit.back_button("Menu")
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -6)
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var season := bp.get_season()
	titles.add_child(MenuKit.title(season.display_name if not season.display_name.is_empty() else "Pass de combat", 34))
	var sub := MenuKit.label(_season_subtitle(season), 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	titles.add_child(sub)
	gem_counter = GemCounter.new()
	gem_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_counter.pressed.connect(func() -> void:
		ShopScreen.last_tab = &"gems"
		MenuKit.go_to(self, MenuKit.SHOP_SCENE))
	head.add_child(gem_counter)

	# Bandeau de progression
	root.add_child(_build_status())

	# Corps : aperçu + piste
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	body.add_child(_build_detail())
	body.add_child(_build_track())


func _season_subtitle(season: BattlePassSeason) -> String:
	var t := season.subtitle
	if not season.ends_on.is_empty():
		var parts := season.ends_on.split("-")
		if parts.size() == 3:
			const MONTHS := ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
			var m: int = clampi(int(parts[1]), 1, 12)
			t += ("  ·  " if not t.is_empty() else "") + "Fin le %d %s" % [int(parts[2]), MONTHS[m - 1]]
	return t


func _build_status() -> Control:
	var p := PanelContainer.new()
	var st := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.9), MenuKit.BORDER, 16, 1, 10)
	st.content_margin_left = 12
	st.content_margin_right = 12
	p.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	p.add_child(row)
	var badge := TierBadge.new()
	badge.name = "TierBadge"
	badge.custom_minimum_size = Vector2(64, 64)
	row.add_child(badge)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	col.add_child(line)
	tier_label = MenuKit.label("", 20, MenuKit.TEXT, MenuKit.nunito(1000), 3)
	line.add_child(tier_label)
	last_gain_label = MenuKit.label("", 15, MenuKit.GOOD.lightened(0.2), MenuKit.nunito(900))
	last_gain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last_gain_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(last_gain_label)
	xp_label = MenuKit.label("", 16, MenuKit.TEXT_DIM, MenuKit.nunito(900))
	xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(xp_label)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 16)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(8)
	bg.border_color = Color(1, 1, 1, 0.14)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.GOLD
	fill.set_corner_radius_all(8)
	fill.border_color = MenuKit.GOLD.lightened(0.4)
	fill.border_width_top = 2
	xp_bar.add_theme_stylebox_override("background", bg)
	xp_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(xp_bar)
	claim_all_button = MenuKit.button("Tout récupérer", MenuKit.Style.SECONDARY, 18, Vector2(0, 64))
	MenuKit.tighten(claim_all_button, 16)
	claim_all_button.pressed.connect(claim_all)
	row.add_child(claim_all_button)
	premium_button = MenuKit.button("", MenuKit.Style.PRIMARY, 19, Vector2(0, 64))
	MenuKit.tighten(premium_button, 18)
	premium_button.pressed.connect(ask_premium)
	row.add_child(premium_button)
	premium_badge = MenuKit.pill("Premium actif", Color(MenuKit.GOLD.darkened(0.55), 0.95), 17, MenuKit.GOLD.lightened(0.3), MenuKit.GOLD)
	premium_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(premium_badge)
	return p


func _build_detail() -> Control:
	var p := PanelContainer.new()
	p.name = "Detail"
	p.add_theme_stylebox_override("panel", MenuKit.panel_style(Color(0.06, 0.08, 0.14, 0.96), Color(1, 1, 1, 0.16), 14, 1, 0))
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "pass_detail_width", 268.0), 0)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stack)
	_d_backdrop = MenuKit.rarity_backdrop(0)
	stack.add_child(_d_backdrop)
	detail_preview = HeroPreview.new()
	detail_preview.height_ratio = 0.86
	detail_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_preview.offset_top = 86
	detail_preview.offset_bottom = -138
	stack.add_child(detail_preview)
	detail_icon = WeaponIcon.new()
	detail_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_icon.offset_left = 14
	detail_icon.offset_right = -14
	detail_icon.offset_top = 96
	detail_icon.offset_bottom = -232
	stack.add_child(detail_icon)
	detail_held = TextureRect.new()
	detail_held.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_held.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_held.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	detail_held.offset_left = 50
	detail_held.offset_right = -50
	detail_held.offset_top = -222
	detail_held.offset_bottom = -156
	stack.add_child(detail_held)
	detail_big = RewardIcon.new()
	detail_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_big.offset_left = 50
	detail_big.offset_right = -50
	detail_big.offset_top = 110
	detail_big.offset_bottom = -170
	stack.add_child(detail_big)
	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 14
	head.offset_right = -14
	head.offset_top = 12
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	_d_kicker = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(900))
	head.add_child(_d_kicker)
	_d_name = MenuKit.label("", 24, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	_d_name.clip_text = true
	_d_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(_d_name)
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 12
	foot.offset_right = -12
	foot.offset_bottom = -12
	foot.add_theme_constant_override("separation", 8)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(foot)
	_d_desc = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(700))
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_desc.max_lines_visible = 3
	_d_desc.custom_minimum_size = Vector2(0, 56)
	_d_desc.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	foot.add_child(_d_desc)
	detail_button = MenuKit.button("", MenuKit.Style.PRIMARY, 20, Vector2(0, 62))
	MenuKit.tighten(detail_button, 10)
	detail_button.pressed.connect(_on_detail_action)
	foot.add_child(detail_button)
	return p


func _build_track() -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := MenuKit.panel_style(Color(MenuKit.NIGHT_DEEP, 0.72), Color(1, 1, 1, 0.12), 14, 1, 0)
	p.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	p.add_child(row)
	# Libellés des pistes (fixes)
	var labels := VBoxContainer.new()
	labels.custom_minimum_size = Vector2(42, 0)
	labels.add_theme_constant_override("separation", 0)
	row.add_child(labels)
	labels.add_child(_track_label("Gratuit", MenuKit.TEXT_DIM))
	var mid := Control.new()
	mid.custom_minimum_size = Vector2(0, 44)
	labels.add_child(mid)
	labels.add_child(_track_label("Premium", MenuKit.GOLD))
	track_scroll = ScrollContainer.new()
	track_scroll.name = "Track"
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	track_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	track_scroll.scroll_deadzone = 12
	row.add_child(track_scroll)
	var cols := VBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 0)
	track_scroll.add_child(cols)
	var free_row := HBoxContainer.new()
	free_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	free_row.add_theme_constant_override("separation", 0)
	cols.add_child(free_row)
	rail = RailStrip.new()
	rail.name = "Rail"
	rail.custom_minimum_size = Vector2(_col_w * bp.max_tier() + 16.0, 44)
	cols.add_child(rail)
	# piste premium sur un fond doré discret
	var prem_bg := PanelContainer.new()
	prem_bg.name = "PremiumRow"
	prem_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(MenuKit.GOLD, 0.07)
	ps.border_color = Color(MenuKit.GOLD, 0.22)
	ps.border_width_top = 1
	ps.corner_radius_bottom_left = 12
	ps.corner_radius_bottom_right = 12
	prem_bg.add_theme_stylebox_override("panel", ps)
	cols.add_child(prem_bg)
	var prem_row := HBoxContainer.new()
	prem_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prem_row.add_theme_constant_override("separation", 0)
	prem_bg.add_child(prem_row)
	for t: int in range(1, bp.max_tier() + 1):
		free_row.add_child(_cell(t, TRACK_FREE))
		prem_row.add_child(_cell(t, TRACK_PREMIUM))
	for r: HBoxContainer in [free_row, prem_row]:
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(16, 0)
		r.add_child(pad)
	return p


func _track_label(txt: String, col: Color) -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(42, 0)
	var l := MenuKit.label(txt, 15, col, MenuKit.nunito(1000), 3)
	l.rotation = -PI / 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	c.resized.connect(func() -> void:
		l.size = Vector2(c.size.y, c.size.x)
		l.position = Vector2(0, c.size.y))
	return c


## Case d'une récompense (palier, piste) : icône, libellé, état (verrouillée, à récupérer, récupérée).
func _cell(t: int, track: StringName) -> Control:
	var key := "%s:%d" % [track, t]
	var holder := MarginContainer.new()
	holder.custom_minimum_size = Vector2(_col_w, 0)
	holder.add_theme_constant_override("margin_left", 5)
	holder.add_theme_constant_override("margin_right", 5)
	holder.add_theme_constant_override("margin_top", 10 if track == TRACK_FREE else 4)
	holder.add_theme_constant_override("margin_bottom", 4 if track == TRACK_FREE else 10)
	var r := bp.reward(t, track)
	var b := Button.new()
	b.name = "Cell_%s" % key.replace(":", "_")
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.text = ""
	b.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	b.set_meta(&"tier", t)
	b.set_meta(&"track", track)
	holder.add_child(b)
	cells[key] = b
	if r.is_empty():
		b.disabled = true
		b.add_theme_stylebox_override("disabled", MenuKit.panel_style(Color(0, 0, 0, 0.12), Color(1, 1, 1, 0.05), 12, 1, 0))
		return holder
	b.pressed.connect(func() -> void:
		MenuKit.sfx(&"tick")
		select(t, track))
	MenuKit.add_feedback(b, 1.03)
	var ic := RewardIcon.new()
	ic.name = "Icon"
	ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 8
	ic.offset_right = -8
	ic.offset_top = 10
	ic.offset_bottom = -58
	b.add_child(ic)
	ic.set_reward(r)
	var name_l := MenuKit.label(BattlePassSystem.reward_label(r), 13, MenuKit.TEXT, MenuKit.nunito(900), 3)
	name_l.name = "Label"
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_left = 4
	name_l.offset_right = -4
	name_l.offset_top = -56
	name_l.offset_bottom = -38
	b.add_child(name_l)
	# État : bouton Récupérer, coche, cadenas
	var claim := MenuKit.button("Récupérer", MenuKit.Style.PRIMARY, 13, Vector2(0, 30))
	claim.name = "Claim"
	MenuKit.tighten(claim, 4)
	claim.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	claim.offset_left = 6
	claim.offset_right = -6
	claim.offset_top = -36
	claim.offset_bottom = -6
	claim.pressed.connect(func() -> void: claim_reward(t, track))
	b.add_child(claim)
	claim_buttons[key] = claim
	var mark := PassGlyph.new(&"check", MenuKit.GOOD, 26)
	mark.name = "Check"
	mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	mark.offset_left = -14
	mark.offset_right = 14
	mark.offset_top = -34
	mark.offset_bottom = -6
	b.add_child(mark)
	var lock := PassGlyph.new(&"lock", MenuKit.GOLD, 22)
	lock.name = "Lock"
	lock.position = Vector2(6, 6)
	lock.size = Vector2(22, 22)
	b.add_child(lock)
	return holder


# --- États ---------------------------------------------------------------------------------

func refresh() -> void:
	if tier_label == null:
		return
	var t := bp.tier()
	var prog := bp.tier_progress()
	if t >= bp.max_tier():
		tier_label.text = "Palier %d — pass terminé !" % t
		xp_label.text = "%d XP" % bp.xp
		xp_bar.max_value = 1
		xp_bar.value = 1
	else:
		tier_label.text = "Palier %d" % t if t > 0 else "Aucun palier"
		xp_label.text = "%d / %d XP vers le palier %d" % [prog.x, prog.y, t + 1]
		xp_bar.max_value = maxi(prog.y, 1)
		xp_bar.value = prog.x
	var g: Dictionary = bp.last_gain
	last_gain_label.text = ("Dernier raid : +%d XP" % int(g.get("xp", 0))) if int(g.get("xp", 0)) > 0 else ""
	(find_child("TierBadge", true, false) as TierBadge).set_tier(t)
	var n := bp.claimable_count()
	claim_all_button.text = "Tout récupérer (%d)" % n if n > 0 else "Tout récupérer"
	claim_all_button.disabled = n == 0
	premium_button.visible = not bp.premium
	premium_badge.visible = bp.premium
	premium_button.text = "Débloquer le Premium · %d gemmes" % BattlePassSystem.premium_price()
	(rail as RailStrip).setup(bp.max_tier(), t, _col_w)
	for key: String in cells:
		_refresh_cell(key)
	_refresh_detail()


func _refresh_cell(key: String) -> void:
	var b: Button = cells[key]
	var t: int = int(b.get_meta(&"tier"))
	var track: StringName = b.get_meta(&"track")
	var r := bp.reward(t, track)
	if r.is_empty():
		return
	var reached: bool = t <= bp.tier()
	var claimed: bool = bp.is_claimed(t, track)
	var claimable: bool = bp.can_claim(t, track)
	var locked_premium: bool = track == TRACK_PREMIUM and not bp.premium
	var next_tier: bool = t == bp.tier() + 1
	var rc: Color = reward_color(r)
	var base_bg := Color(0.08, 0.11, 0.2, 0.95).lerp(rc.darkened(0.45), 0.22 if reached else 0.1)
	var st := MenuKit.panel_style(base_bg, Color(rc, 0.9 if reached else 0.45), 12, 2, 0)
	st.shadow_offset = Vector2.ZERO
	st.shadow_size = 0
	if claimable:
		st.border_color = MenuKit.GOLD
		st.set_border_width_all(3)
		st.shadow_color = Color(MenuKit.GOLD, 0.45)
		st.shadow_size = 8
	elif next_tier:
		st.border_color = Color(1, 1, 1, 0.85)
		st.set_border_width_all(3)
	var sel := st.duplicate() as StyleBoxFlat
	sel.bg_color = base_bg.lightened(0.12)
	sel.border_color = MenuKit.GOLD.lightened(0.3)
	sel.set_border_width_all(3)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", sel if b.button_pressed else st)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = MenuKit.GOLD
	f.set_border_width_all(2)
	f.set_corner_radius_all(14)
	f.set_expand_margin_all(2)
	b.add_theme_stylebox_override("focus", f)
	var dim: float = 1.0 if (reached and not claimed) else (0.55 if claimed else 0.7)
	(b.get_node("Icon") as Control).modulate = Color(1, 1, 1, dim)
	(b.get_node("Label") as Control).modulate = Color(1, 1, 1, 0.75 + 0.25 * dim)
	(b.get_node("Claim") as Control).visible = claimable
	(b.get_node("Check") as Control).visible = claimed
	(b.get_node("Lock") as Control).visible = locked_premium


## Couleur d'une récompense : rareté du skin, cyan des gemmes, or, rareté de l'objet.
static func reward_color(r: Dictionary) -> Color:
	match str(r.get("type", "")):
		"gems":
			return MenuKit.GEM
		"gold":
			return MenuKit.GOLD
		"skin":
			var s := SkinData.get_skin(StringName(str(r.get("id", ""))))
			return MenuKit.rarity_color(s.rarity if s != null else 0)
		"item":
			var it := RewardIcon.item_of(r)
			return MenuKit.rarity_color(it.rarity if it != null else 0)
	return MenuKit.TEXT_DIM


# --- Sélection et aperçu --------------------------------------------------------------------

func select(t: int, track: StringName, animate: bool = true) -> void:
	selected = {"tier": t, "track": track}
	for key: String in cells:
		var b: Button = cells[key]
		b.set_pressed_no_signal(key == "%s:%d" % [track, t])
		_refresh_cell(key)
	_refresh_detail(animate)


func get_selected_reward() -> Dictionary:
	if selected.is_empty():
		return {}
	return bp.reward(int(selected["tier"]), StringName(selected["track"]))


func _refresh_detail(animate: bool = false) -> void:
	if detail_button == null or selected.is_empty():
		return
	var t: int = int(selected["tier"])
	var track: StringName = selected["track"]
	var r := get_selected_reward()
	var type := str(r.get("type", ""))
	var skin: SkinData = SkinData.get_skin(StringName(str(r.get("id", "")))) if type == "skin" else null
	var is_char: bool = skin != null and skin.kind == SkinData.KIND_CHARACTER
	var is_wsk: bool = skin != null and skin.kind == SkinData.KIND_WEAPON
	detail_preview.visible = is_char
	detail_icon.visible = is_wsk
	detail_held.visible = is_wsk
	detail_big.visible = not is_char and not is_wsk
	var bd := MenuKit.rarity_backdrop(skin.rarity if skin != null else 0)
	_d_backdrop.texture = bd.texture
	bd.free()
	_d_kicker.text = "Palier %d · %s" % [t, "Premium" if track == TRACK_PREMIUM else "Gratuit"]
	_d_name.text = BattlePassSystem.reward_label(r) if not r.is_empty() else "—"
	if is_char:
		detail_preview.set_skin(skin, animate)
		_d_desc.text = skin.description
	elif is_wsk:
		var w := ShopScreen.weapon_of(skin)
		_d_name.text = skin.display_name
		_d_desc.text = "Skin %s pour %s. %s" % [MenuKit.rarity_name(skin.rarity).to_lower(), w.display_name if w != null else "l'arme", skin.description]
		detail_icon.set_weapon(w, skin, false)
		detail_held.remove_meta(WeaponSkin.META_BASE_TEX)
		detail_held.texture = ShopScreen._held_texture(w)
		WeaponSkin.apply(detail_held, skin, w.id if w != null else &"", false)
	else:
		(detail_big as RewardIcon).set_reward(r)
		match type:
			"gems":
				_d_desc.text = "Les gemmes servent aux skins de la boutique."
			"gold":
				_d_desc.text = "Des pièces d'or pour le marchand et l'atelier."
			"item":
				var it := RewardIcon.item_of(r)
				_d_desc.text = it.description if it != null else ""
			_:
				_d_desc.text = ""
	# Bouton d'action
	var b := detail_button
	b.disabled = false
	if bp.can_claim(t, track):
		b.text = "Récupérer"
	elif bp.is_claimed(t, track):
		if skin != null and Profile.owns_skin(skin.id):
			var equipped: bool = Profile.skin_character == skin.id if is_char else WeaponSkin.is_equipped(skin)
			b.text = "Équipé" if equipped else "Équiper"
			b.disabled = equipped
		else:
			b.text = "Récupéré"
			b.disabled = true
	elif track == TRACK_PREMIUM and not bp.premium:
		b.text = "Débloquer le Premium"
	else:
		b.text = "Palier %d requis" % t
		b.disabled = true


func _on_detail_action() -> void:
	if selected.is_empty():
		return
	var t: int = int(selected["tier"])
	var track: StringName = selected["track"]
	if bp.can_claim(t, track):
		claim_reward(t, track)
		return
	if track == TRACK_PREMIUM and not bp.premium:
		ask_premium()
		return
	var r := get_selected_reward()
	var skin: SkinData = SkinData.get_skin(StringName(str(r.get("id", "")))) if str(r.get("type", "")) == "skin" else null
	if skin != null and Profile.owns_skin(skin.id):
		if skin.kind == SkinData.KIND_CHARACTER:
			Profile.equip_character_skin(skin.id)
		else:
			WeaponSkin.equip(skin.id)
		MenuKit.sfx(&"item_equip", -2.0)
		refresh()


func scroll_to_tier(t: int) -> void:
	if track_scroll == null:
		return
	var x: float = (t - 1) * _col_w - track_scroll.size.x * 0.5 + _col_w * 0.5
	track_scroll.scroll_horizontal = int(maxf(x, 0.0))


# --- Actions ---------------------------------------------------------------------------------

## Récupère une récompense (une seule fois).
func claim_reward(t: int, track: StringName) -> bool:
	if not bp.claim(t, track):
		MenuKit.sfx(&"error")
		return false
	MenuKit.sfx(&"coin_spend" if str(bp.reward(t, track).get("type", "")) == "skin" else &"gold_pickup")
	_pop(cells.get("%s:%d" % [track, t]))
	if selected.is_empty() or int(selected["tier"]) != t or selected["track"] != track:
		select(t, track)
	refresh()
	return true


func claim_all() -> int:
	var n := bp.claim_all()
	if n > 0:
		MenuKit.sfx(&"gold_pickup")
		for key: String in cells:
			_pop(cells[key])
	refresh()
	return n


func _pop(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(c, "scale", Vector2.ONE, 0.3).from(Vector2(1.08, 1.08))


## Confirmation d'achat du Premium (ou manque de gemmes → boutique, onglet Gemmes).
func ask_premium() -> ModalPanel:
	if bp.premium:
		return null
	var price := BattlePassSystem.premium_price()
	if Profile.gems < price:
		var m := ConfirmPanel.new("Pas assez de gemmes",
			"Le Premium coûte %d gemmes : il t'en manque %d. Gagne-en en t'extrayant ou prends un pack." % [price, price - Profile.gems],
			"Voir les gemmes")
		m.confirmed.connect(func() -> void:
			ShopScreen.last_tab = &"gems"
			MenuKit.go_to(self, MenuKit.SHOP_SCENE))
		MenuKit.sfx(&"error")
		return _open_modal(m)
	var m2 := ConfirmPanel.new("Débloquer le Premium ?",
		"%d gemmes : skins exclusifs (personnages et armes), gemmes et or sur la piste premium.\nLes paliers déjà atteints deviennent récupérables. Purement cosmétique." % price,
		"Débloquer")
	m2.confirmed.connect(buy_premium)
	return _open_modal(m2)


func buy_premium() -> bool:
	var ok := bp.buy_premium()
	MenuKit.sfx(&"coin_spend" if ok else &"error")
	refresh()
	return ok


func _open_modal(m: ModalPanel) -> ModalPanel:
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = m
	add_child(m)
	return m


func go_back() -> void:
	MenuKit.sfx(&"back")
	MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not is_instance_valid(_modal):
		get_viewport().set_input_as_handled()
		go_back()


# --- Composants dessinés ---------------------------------------------------------------------

## Icône d'une récompense : skin de personnage (pose en pied), skin d'arme (arme habillée),
## gemmes, or, objet. Statique.
class RewardIcon extends Control:
	var reward: Dictionary = {}
	var _child: Control = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	static func item_of(r: Dictionary) -> ItemData:
		var p := "res://data/items/%s.tres" % str(r.get("id", ""))
		return load(p) as ItemData if ResourceLoader.exists(p) else null

	func set_reward(r: Dictionary) -> void:
		reward = r
		if _child != null:
			_child.queue_free()
			_child = null
		var type := str(r.get("type", ""))
		var c: Control = null
		match type:
			"skin":
				var s := SkinData.get_skin(StringName(str(r.get("id", ""))))
				if s != null and s.kind == SkinData.KIND_CHARACTER:
					var tr := TextureRect.new()
					tr.texture = ShopScreen.cropped_preview(ShopScreen.pose_texture(s))
					tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					c = tr
				elif s != null:
					var ic := WeaponIcon.new()
					c = ic
					ic.set_weapon(ShopScreen.weapon_of(s), s, false)
			"gems":
				var g := GemIcon.new()
				c = g
			"gold":
				c = MenuGlyph.new(&"coin", MenuKit.GOLD, 32)
			"item":
				var it := item_of(r)
				var tr2 := TextureRect.new()
				tr2.texture = it.icon if it != null else null
				tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				c = tr2
		if c == null:
			return
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.custom_minimum_size = Vector2.ZERO
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if type == "gems" or type == "gold" or type == "item":
			# pictogrammes carrés : un peu plus petits que les visuels de skins
			c.anchor_left = 0.18
			c.anchor_right = 0.82
			c.anchor_top = 0.1
			c.anchor_bottom = 0.9
		add_child(c)
		_child = c


## Badge du palier atteint : étoile de shérif dorée avec le numéro.
class TierBadge extends Control:
	var tier: int = 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func set_tier(t: int) -> void:
		if t != tier:
			tier = t
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r: float = minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array()
		for i: int in 12:
			var a: float = -PI / 2 + TAU * i / 12.0
			var rr: float = r if i % 2 == 0 else r * 0.62
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		var ink := PackedVector2Array(pts)
		ink.append(pts[0])
		draw_colored_polygon(pts, MenuKit.GOLD.darkened(0.1))
		draw_polyline(ink, Color(0.04, 0.03, 0.09, 0.9), 3.0, true)
		for i: int in 6:
			var a2: float = -PI / 2 + TAU * i / 6.0
			draw_circle(c + Vector2(cos(a2), sin(a2)) * r * 0.92, r * 0.1, MenuKit.GOLD.lightened(0.35))
		draw_circle(c, r * 0.5, MenuKit.NIGHT)
		var f: Font = MenuKit.nunito(1000)
		var fs: int = int(r * 0.62)
		var txt := str(tier)
		var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, c + Vector2(-tw * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MenuKit.TEXT)


## Voie ferrée de la piste : deux rails, une traverse par palier (numéro), rails dorés jusqu'au
## palier atteint, locomotive-étoile au palier suivant. Redessinée seulement si l'état change.
class RailStrip extends Control:
	var tiers: int = 30
	var reached: int = 0
	var col_w: float = 118.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func setup(p_tiers: int, p_reached: int, p_col_w: float) -> void:
		if p_tiers == tiers and p_reached == reached and is_equal_approx(p_col_w, col_w):
			return
		tiers = p_tiers
		reached = p_reached
		col_w = p_col_w
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var y1: float = h * 0.3
		var y2: float = h * 0.7
		var gold_x: float = col_w * clampf(reached, 0, tiers)
		var steel := Color(0.55, 0.58, 0.66, 0.9)
		var wood := Color(0.36, 0.22, 0.14)
		var f: Font = MenuKit.nunito(1000)
		# traverses
		for t: int in range(1, tiers + 1):
			var cx: float = col_w * (t - 0.5)
			var on: bool = t <= reached
			var next: bool = t == reached + 1
			var w: float = 34.0 if not next else 40.0
			var rect := Rect2(cx - w * 0.5, 2, w, h - 4)
			draw_rect(rect.grow(1.5), Color(0.04, 0.03, 0.09, 0.9))
			draw_rect(rect, wood.lightened(0.15) if on else wood.darkened(0.25))
			if next:
				draw_rect(rect.grow(2.5), Color(1, 1, 1, 0.9), false, 2.0)
		# rails : acier, puis or jusqu'au palier atteint
		for y: float in [y1, y2]:
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.04, 0.03, 0.09, 0.9), 6.0)
			draw_line(Vector2(0, y), Vector2(size.x, y), steel, 3.0)
			if gold_x > 0.0:
				draw_line(Vector2(0, y), Vector2(gold_x, y), MenuKit.GOLD, 3.5)
		# numéros des paliers
		for t2: int in range(1, tiers + 1):
			var cx2: float = col_w * (t2 - 0.5)
			var txt := str(t2)
			var fs: int = 17 if t2 == reached + 1 else 15
			var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var col: Color = MenuKit.GOLD.lightened(0.3) if t2 <= reached else (MenuKit.TEXT if t2 == reached + 1 else MenuKit.TEXT_DIM)
			draw_string_outline(f, Vector2(cx2 - tw * 0.5, h * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.04, 0.03, 0.09, 0.95))
			draw_string(f, Vector2(cx2 - tw * 0.5, h * 0.5 + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
