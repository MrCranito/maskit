class_name BattlePassScreen
extends Control
## Écran du pass de combat (res://scenes/ui/menus/battle_pass.tscn) — direction « VITRINE + GRILLE ».
##  - Haut : en-tête discret (retour, saison, or, gemmes).
##  - VITRINE : la récompense phare (par défaut le prochain grand skin premium non obtenu) en
##    grand — personnage en pied (même rendu que le lobby : pose haute résolution + idle
##    procédurale) ou arme habillée — sur le décor du camp, rayons à la couleur de rareté ;
##    nom, rareté, « Palier 30 · Premium », et le gros bouton « Débloquer le Premium » (ou un
##    discret « Premium actif »).
##  - Progression : une seule barre (badge du palier, XP, prochaine récompense) et l'unique
##    bouton d'action « Tout récupérer (N) », visible seulement s'il y a quelque chose à prendre.
##  - GRILLE : une colonne par palier (case premium en haut, numéro, case gratuite en bas),
##    cases sobres (icône + petite quantité). États : verrouillé (assombri, cadenas), disponible
##    (contour or qui pulse + pastille), récupéré (coche, atténué), premium non acheté (cadenas
##    doré). Toucher une case l'affiche dans la vitrine ; une case disponible est récupérée
##    (elle « s'ouvre », l'icône vole vers le compteur). Palier courant centré à l'ouverture.
## Animations : un seul Tween en boucle (pulsation) tant qu'une case est disponible ; décor
## et cases dessinés une fois (aucun _process).

const TRACK_FREE := &"free"
const TRACK_PREMIUM := &"premium"

## Skin à mettre en avant à l'ouverture (ex. depuis la boutique) ; vidé à l'ouverture.
static var focus_skin_id: StringName = &""

var bp: BattlePassSystem = null
var back_button: Button = null
var gem_counter: GemCounter = null
var gold_label: Label = null
var premium_button: Button = null
var premium_badge: Control = null
var claim_all_button: Button = null
var equip_button: Button = null
var tier_badge: TierBadge = null
var tier_label: Label = null
var xp_label: Label = null
var next_label: Label = null
var xp_bar: ProgressBar = null
## Cases de la grille : "free:5" / "premium:5" → PassCell.
var cells: Dictionary = {}
## Récompense en vitrine : {tier, track}.
var selected: Dictionary = {}
var detail_preview: HeroPreview = null
var detail_icon: WeaponIcon = null
var detail_big: RewardIcon = null
var track_scroll: ScrollContainer = null
## Pulsation des cases disponibles (0..1), animée par un seul Tween.
var pulse: float = 0.0:
	set(v):
		pulse = v
		for c: PassCell in _pulsing:
			c.set_pulse(v)

var _modal: ModalPanel = null
var _showcase: Control = null
var _backdrop: ShowcaseBackdrop = null
var _s_kicker: Label = null
var _s_name: Label = null
var _s_meta: HBoxContainer = null
var _s_desc: Label = null
var _fx: Control = null
var _pulsing: Array[PassCell] = []
var _numbers: Array[TierNumber] = []
var _pulse_tween: Tween = null
var _col_w: float = 84.0
var _cell: float = 70.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	bp = BattlePassSystem.get_instance()
	_cell = Balance.get_float("battle_pass", "cell_size", 70.0)
	_col_w = _cell + 14.0
	var bg := ColorRect.new()
	bg.color = MenuKit.NIGHT_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build()
	_fx = Control.new()
	_fx.name = "Fx"
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fx)
	bp.changed.connect(refresh)
	Profile.changed.connect(refresh)
	refresh()
	var focus: Dictionary = bp.find_skin(focus_skin_id) if not String(focus_skin_id).is_empty() else {}
	focus_skin_id = &""
	if focus.is_empty():
		focus = featured_reward()
	select(int(focus["tier"]), StringName(focus["track"]), false)
	scroll_to_tier.call_deferred(clampi(bp.tier() + 1, 1, bp.max_tier()))
	MenuKit.fade_in(self)
	back_button.grab_focus.call_deferred()


## Récompense phare par défaut : le prochain skin de personnage premium non obtenu (sinon le
## prochain skin, sinon le dernier palier premium).
func featured_reward() -> Dictionary:
	var s := bp.get_season()
	var fallback: Dictionary = {}
	for pass_i: int in 2:
		for t: int in range(1, s.tiers + 1):
			var r := s.reward(t, TRACK_PREMIUM)
			if str(r.get("type", "")) != "skin" or bp.is_claimed(t, TRACK_PREMIUM):
				continue
			var sk := SkinData.get_skin(StringName(str(r.get("id", ""))))
			if sk == null or Profile.owns_skin(sk.id):
				continue
			if pass_i == 0 and sk.kind == SkinData.KIND_CHARACTER and t > bp.tier():
				return {"tier": t, "track": TRACK_PREMIUM}
			if pass_i == 1 and fallback.is_empty():
				fallback = {"tier": t, "track": TRACK_PREMIUM}
	return fallback if not fallback.is_empty() else {"tier": s.tiers, "track": TRACK_PREMIUM}


# --- Construction ------------------------------------------------------------------------

func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)
	root.add_child(_build_header())
	_showcase = _build_showcase()
	root.add_child(_showcase)
	root.add_child(_build_progress())
	root.add_child(_build_grid())


func _build_header() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_button = MenuKit.button("‹  Menu", MenuKit.Style.GHOST, 19, Vector2(124, 52))
	MenuKit.tighten(back_button, 12)
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -4)
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var season := bp.get_season()
	var kicker := MenuKit.label("Pass de combat", 13, MenuKit.GOLD, MenuKit.nunito(900))
	titles.add_child(kicker)
	var t := MenuKit.label(season.display_name, 24, MenuKit.TEXT, MenuKit.nunito(1000), 3)
	titles.add_child(t)
	var end_l := MenuKit.label(_season_end(season), 14, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	end_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(end_l)
	var gold := PanelContainer.new()
	gold.name = "GoldPill"
	var gs := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.9), Color(MenuKit.GOLD, 0.45), 26, 2, 0)
	gs.content_margin_left = 8
	gs.content_margin_right = 16
	gs.shadow_size = 0
	gold.add_theme_stylebox_override("panel", gs)
	gold.custom_minimum_size.y = 48
	gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 6)
	gold.add_child(grow)
	var coin := MenuGlyph.new(&"coin", MenuKit.COIN, 26)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grow.add_child(coin)
	gold_label = MenuKit.label("0", 20, MenuKit.TEXT, MenuKit.nunito(1000), 3)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grow.add_child(gold_label)
	head.add_child(gold)
	gem_counter = GemCounter.new(20)
	gem_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_counter.pressed.connect(func() -> void:
		ShopScreen.last_tab = &"gems"
		MenuKit.go_to(self, MenuKit.SHOP_SCENE))
	head.add_child(gem_counter)
	return head


func _season_end(season: BattlePassSeason) -> String:
	var parts := season.ends_on.split("-")
	if parts.size() != 3:
		return ""
	const MONTHS := ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]
	return "Fin le %d %s" % [int(parts[2]), MONTHS[clampi(int(parts[1]), 1, 12) - 1]]


## Vitrine : décor + rayons, grand visuel à gauche, texte et bouton Premium à droite.
func _build_showcase() -> Control:
	var p := PanelContainer.new()
	p.name = "Showcase"
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size.y = 250
	var st := MenuKit.panel_style(Color(MenuKit.NIGHT, 1.0), Color(1, 1, 1, 0.1), 20, 1, 0)
	st.shadow_size = 0
	p.add_theme_stylebox_override("panel", st)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stack)
	_backdrop = ShowcaseBackdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_backdrop)
	# Visuel (zone gauche, ~42 % de la largeur)
	detail_preview = HeroPreview.new()
	detail_preview.name = "HeroPreview"
	detail_preview.height_ratio = 0.9
	detail_preview.feet_ratio = 0.95
	detail_preview.anchor_right = 0.42
	detail_preview.anchor_bottom = 1.0
	detail_preview.offset_top = 12
	stack.add_child(detail_preview)
	detail_icon = WeaponIcon.new()
	detail_icon.name = "WeaponPreview"
	detail_icon.anchor_left = 0.03
	detail_icon.anchor_right = 0.42
	detail_icon.anchor_top = 0.18
	detail_icon.anchor_bottom = 0.86
	stack.add_child(detail_icon)
	detail_big = RewardIcon.new()
	detail_big.anchor_left = 0.12
	detail_big.anchor_right = 0.32
	detail_big.anchor_top = 0.2
	detail_big.anchor_bottom = 0.8
	stack.add_child(detail_big)
	# Texte + action (zone droite)
	var col := VBoxContainer.new()
	col.anchor_left = 0.45
	col.anchor_right = 1.0
	col.anchor_bottom = 1.0
	col.offset_right = -28
	col.offset_top = 20
	col.offset_bottom = -20
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(col)
	_s_kicker = MenuKit.label("", 15, MenuKit.GOLD, MenuKit.nunito(900))
	col.add_child(_s_kicker)
	_s_name = MenuKit.label("", 44, MenuKit.TEXT, MenuKit.nunito(1000), 6)
	_s_name.clip_text = true
	_s_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_s_name)
	_s_meta = HBoxContainer.new()
	_s_meta.add_theme_constant_override("separation", 8)
	_s_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_s_meta)
	_s_desc = MenuKit.label("", 16, MenuKit.TEXT_DIM, MenuKit.nunito(700))
	_s_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_s_desc.max_lines_visible = 2
	_s_desc.custom_minimum_size = Vector2(0, 46)
	col.add_child(_s_desc)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	col.add_child(gap)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(actions)
	premium_button = _premium_button()
	actions.add_child(premium_button)
	premium_badge = MenuKit.pill("Premium actif", Color(MenuKit.GOLD.darkened(0.6), 0.9), 15, MenuKit.GOLD.lightened(0.25), Color(MenuKit.GOLD, 0.6))
	premium_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(premium_badge)
	equip_button = MenuKit.button("Équiper", MenuKit.Style.SECONDARY, 18, Vector2(140, 56))
	MenuKit.tighten(equip_button, 14)
	equip_button.pressed.connect(_on_equip)
	actions.add_child(equip_button)
	return p


## Gros bouton doré « Débloquer le Premium — 950 » + gemme.
func _premium_button() -> Button:
	var b := Button.new()
	b.name = "PremiumButton"
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 64)
	var gold := Color(0.96, 0.72, 0.22)
	var n := MenuKit.panel_style(gold, gold.lightened(0.45), 16, 2, 0)
	n.border_width_bottom = 6
	n.border_color = gold.darkened(0.45)
	n.shadow_color = Color(gold, 0.35)
	n.shadow_size = 14
	n.shadow_offset = Vector2.ZERO
	n.content_margin_left = 22
	n.content_margin_right = 22
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = gold.lightened(0.12)
	var pr := n.duplicate() as StyleBoxFlat
	pr.bg_color = gold.darkened(0.08)
	pr.border_width_bottom = 2
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = MenuKit.TEXT
	f.set_border_width_all(3)
	f.set_corner_radius_all(19)
	f.set_expand_margin_all(3)
	for k: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(k, {"normal": n, "hover": h, "pressed": pr, "hover_pressed": pr, "focus": f}[k])
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_bottom = -4
	b.add_child(row)
	var l := MenuKit.label("Débloquer le Premium — %d" % BattlePassSystem.premium_price(), 21, Color(0.2, 0.11, 0.02), MenuKit.nunito(1000))
	l.name = "Text"
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var g := GemIcon.new()
	g.custom_minimum_size = Vector2(28, 28)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	var font: Font = MenuKit.nunito(1000)
	b.custom_minimum_size.x = font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x + 28 + 10 + 56
	b.pressed.connect(ask_premium)
	MenuKit.add_feedback(b, 1.04)
	return b


## Barre de progression unique + bouton global « Tout récupérer ».
func _build_progress() -> Control:
	var row := HBoxContainer.new()
	row.name = "Progress"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tier_badge = TierBadge.new()
	tier_badge.name = "TierBadge"
	tier_badge.custom_minimum_size = Vector2(56, 56)
	row.add_child(tier_badge)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	tier_label = MenuKit.label("", 19, MenuKit.TEXT, MenuKit.nunito(1000), 3)
	line.add_child(tier_label)
	xp_label = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(900))
	xp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(xp_label)
	next_label = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	next_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	next_label.clip_text = true
	next_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(next_label)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.custom_minimum_size = Vector2(0, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.GOLD
	fill.set_corner_radius_all(6)
	xp_bar.add_theme_stylebox_override("background", bg)
	xp_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(xp_bar)
	claim_all_button = MenuKit.button("Tout récupérer", MenuKit.Style.PRIMARY, 18, Vector2(0, 56))
	MenuKit.tighten(claim_all_button, 18)
	claim_all_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim_all_button.pressed.connect(claim_all)
	row.add_child(claim_all_button)
	return row


## Grille : libellés fixes à gauche, colonnes défilables (premium / numéro / gratuit).
func _build_grid() -> Control:
	var row := HBoxContainer.new()
	row.name = "Grid"
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = _cell * 2 + 28 + 26
	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", 0)
	labels.custom_minimum_size.x = 64
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(labels)
	labels.add_child(_row_label("Premium", MenuKit.GOLD, &"ticket"))
	var mid := Control.new()
	mid.custom_minimum_size.y = 26
	labels.add_child(mid)
	labels.add_child(_row_label("Gratuit", MenuKit.TEXT_DIM, &""))
	track_scroll = ScrollContainer.new()
	MenuKit.make_touch_scroll(track_scroll)   # glisser au doigt partout (même sur les boutons)
	track_scroll.name = "Track"
	track_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	track_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	track_scroll.scroll_deadzone = 10
	row.add_child(track_scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_scroll.add_child(cols)
	for t: int in range(1, bp.max_tier() + 1):
		var c := VBoxContainer.new()
		c.name = "Tier%d" % t
		c.custom_minimum_size.x = _col_w
		c.add_theme_constant_override("separation", 0)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cols.add_child(c)
		c.add_child(_cell_holder(t, TRACK_PREMIUM))
		var num := TierNumber.new()
		num.name = "Num"
		_numbers.append(num)
		num.tier = t
		num.custom_minimum_size = Vector2(_col_w, 26)
		c.add_child(num)
		c.add_child(_cell_holder(t, TRACK_FREE))
	return row


func _row_label(txt: String, col: Color, glyph: StringName) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.y = _cell + 14
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if glyph != &"":
		var g := PassGlyph.new(glyph, col, 26)
		g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(g)
	var l := MenuKit.label(txt, 13, col, MenuKit.nunito(1000))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


func _cell_holder(t: int, track: StringName) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(_col_w, _cell + 14)   # marge : lueur et pastille non rognées
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := PassCell.new()
	c.setup(t, track, bp.reward(t, track), _cell)
	c.pressed.connect(func() -> void: _on_cell(c))
	holder.add_child(c)
	cells["%s:%d" % [track, t]] = c
	return holder


# --- États ---------------------------------------------------------------------------------

func refresh() -> void:
	if tier_label == null:
		return
	var t := bp.tier()
	var prog := bp.tier_progress()
	tier_badge.set_tier(t)
	if t >= bp.max_tier():
		tier_label.text = "Pass terminé"
		xp_label.text = "%d XP" % bp.xp
		xp_bar.max_value = 1
		xp_bar.value = 1
		next_label.text = ""
	else:
		tier_label.text = "Palier %d" % t
		xp_label.text = "%d / %d XP" % [prog.x, prog.y]
		xp_bar.max_value = maxi(prog.y, 1)
		xp_bar.value = prog.x
		var nr := bp.reward(t + 1, TRACK_PREMIUM if bp.premium else TRACK_FREE)
		if nr.is_empty():
			nr = bp.reward(t + 1, TRACK_FREE)
		next_label.text = "Prochaine récompense : %s" % BattlePassSystem.reward_label(nr) if not nr.is_empty() else ""
	var n := bp.claimable_count()
	claim_all_button.visible = n > 0
	claim_all_button.text = "Tout récupérer (%d)" % n
	premium_button.visible = not bp.premium
	premium_badge.visible = bp.premium
	gold_label.text = MainMenu.format_thousands(MainMenu.gold_amount())
	for num: TierNumber in _numbers:
		num.set_reached(num.tier <= t, num.tier == t + 1)
	_pulsing.clear()
	for key: String in cells:
		var c: PassCell = cells[key]
		c.apply_state(bp, t)
		if c.state == PassCell.AVAILABLE:
			_pulsing.append(c)
	_update_pulse()
	_refresh_showcase()


func _update_pulse() -> void:
	if _pulsing.is_empty():
		if _pulse_tween != null and _pulse_tween.is_valid():
			_pulse_tween.kill()
		_pulse_tween = null
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		pulse = pulse
		return
	_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "pulse", 1.0, 0.8).from(0.0)
	_pulse_tween.tween_property(self, "pulse", 0.0, 0.8)


# --- Vitrine ---------------------------------------------------------------------------------

func select(t: int, track: StringName, animate: bool = true) -> void:
	selected = {"tier": t, "track": track}
	for key: String in cells:
		(cells[key] as PassCell).set_selected(key == "%s:%d" % [track, t])
	_refresh_showcase(animate)


func get_selected_reward() -> Dictionary:
	if selected.is_empty():
		return {}
	return bp.reward(int(selected["tier"]), StringName(selected["track"]))


func _selected_skin() -> SkinData:
	var r := get_selected_reward()
	return SkinData.get_skin(StringName(str(r.get("id", "")))) if str(r.get("type", "")) == "skin" else null


func _refresh_showcase(animate: bool = false) -> void:
	if _s_name == null or selected.is_empty():
		return
	var t: int = int(selected["tier"])
	var track: StringName = selected["track"]
	var r := get_selected_reward()
	var type := str(r.get("type", ""))
	var skin := _selected_skin()
	var is_char: bool = skin != null and skin.kind == SkinData.KIND_CHARACTER
	var is_wsk: bool = skin != null and skin.kind == SkinData.KIND_WEAPON
	detail_preview.visible = is_char
	detail_icon.visible = is_wsk
	detail_big.visible = not is_char and not is_wsk
	var col: Color = RewardIcon.color_of(r)
	_backdrop.set_accent(col, skin != null and skin.rarity >= 3)
	_s_kicker.text = "Palier %d · %s" % [t, "Premium" if track == TRACK_PREMIUM else "Gratuit"]
	_s_kicker.add_theme_color_override("font_color", MenuKit.GOLD if track == TRACK_PREMIUM else MenuKit.TEXT_DIM)
	for c: Node in _s_meta.get_children():
		c.queue_free()
	if is_char or is_wsk:
		_s_name.text = skin.display_name
		var rc := MenuKit.rarity_color(skin.rarity)
		_s_meta.add_child(MenuKit.pill(MenuKit.rarity_name(skin.rarity), rc.darkened(0.3), 14, MenuKit.TEXT if skin.rarity < 4 else Color(0.16, 0.1, 0.02)))
		var w := ShopScreen.weapon_of(skin) if is_wsk else null
		_s_meta.add_child(MenuKit.pill("Skin d'arme · %s" % w.display_name if w != null else "Skin de personnage",
			Color(1, 1, 1, 0.08), 14, MenuKit.TEXT_DIM))
		_s_desc.text = skin.description
		if is_char:
			detail_preview.set_skin(skin, animate)
		else:
			detail_icon.set_weapon(w, skin, false)
	else:
		_s_name.text = BattlePassSystem.reward_label(r) if not r.is_empty() else "—"
		detail_big.set_reward(r)
		match type:
			"gems":
				_s_desc.text = "Les gemmes servent aux skins de la boutique."
			"gold":
				_s_desc.text = "Des pièces d'or pour le marchand et l'atelier."
			"item":
				var it := RewardIcon.item_of(r)
				_s_desc.text = it.description if it != null else ""
			_:
				_s_desc.text = ""
	_s_meta.add_child(_state_pill(t, track))
	# Équiper : seulement pour un skin obtenu
	var owned: bool = skin != null and Profile.owns_skin(skin.id)
	equip_button.visible = owned
	if owned:
		var eq: bool = Profile.skin_character == skin.id if is_char else WeaponSkin.is_equipped(skin)
		equip_button.text = "Équipé" if eq else "Équiper"
		equip_button.disabled = eq
	if animate:
		var target: Control = detail_preview if is_char else (detail_icon if is_wsk else detail_big)
		target.pivot_offset = target.size * Vector2(0.5, 0.9)
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(target, "scale", Vector2.ONE, 0.32).from(Vector2(0.92, 0.92))


func _state_pill(t: int, track: StringName) -> Control:
	if bp.is_claimed(t, track):
		return MenuKit.pill("Obtenu", Color(MenuKit.GOOD.darkened(0.6), 0.9), 14, MenuKit.GOOD.lightened(0.3))
	if bp.can_claim(t, track):
		return MenuKit.pill("Disponible", Color(MenuKit.GOLD.darkened(0.55), 0.95), 14, MenuKit.GOLD.lightened(0.3))
	if track == TRACK_PREMIUM and not bp.premium:
		return MenuKit.pill("Premium requis", Color(1, 1, 1, 0.08), 14, MenuKit.GOLD)
	return MenuKit.pill("Palier %d requis" % t, Color(1, 1, 1, 0.08), 14, MenuKit.TEXT_DIM)


func _on_equip() -> void:
	var skin := _selected_skin()
	if skin == null or not Profile.owns_skin(skin.id):
		return
	if skin.kind == SkinData.KIND_CHARACTER:
		Profile.equip_character_skin(skin.id)
	else:
		WeaponSkin.equip(skin.id)
	MenuKit.sfx(&"item_equip", -2.0)
	refresh()


func scroll_to_tier(t: int) -> void:
	if track_scroll == null:
		return
	var x: float = (t - 0.5) * _col_w - track_scroll.size.x * 0.5
	track_scroll.scroll_horizontal = int(maxf(x, 0.0))


# --- Actions ---------------------------------------------------------------------------------

func _on_cell(c: PassCell) -> void:
	select(c.tier, c.track)
	if c.state == PassCell.AVAILABLE:
		claim_reward(c.tier, c.track)
	else:
		MenuKit.sfx(&"tick")


## Récupère une récompense (une seule fois) : la case s'ouvre, l'icône vole vers le compteur.
func claim_reward(t: int, track: StringName) -> bool:
	var r := bp.reward(t, track)
	if not bp.claim(t, track):
		MenuKit.sfx(&"error")
		return false
	MenuKit.sfx(&"coin_spend" if str(r.get("type", "")) == "skin" else &"gold_pickup")
	var c: PassCell = cells.get("%s:%d" % [track, t])
	if c != null:
		c.play_open()
		_fly(c, r)
	refresh()
	return true


func claim_all() -> int:
	var avail: Array[PassCell] = []
	for key: String in cells:
		var c: PassCell = cells[key]
		if c.state == PassCell.AVAILABLE:
			avail.append(c)
	var n := bp.claim_all()
	if n > 0:
		MenuKit.sfx(&"gold_pickup")
		for i: int in avail.size():
			var c2: PassCell = avail[i]
			c2.play_open(0.03 * i)
			if i < 8:
				_fly(c2, c2.reward, 0.05 * i)
	refresh()
	return n


## Petite icône qui vole de la case vers le compteur (gemmes, or) ou vers la vitrine.
func _fly(from: Control, r: Dictionary, delay: float = 0.0) -> void:
	if _fx == null or not from.is_inside_tree():
		return
	var ic := RewardIcon.new()
	ic.size = Vector2(_cell, _cell) * 0.7
	_fx.add_child(ic)
	ic.set_reward(r)
	var start: Vector2 = from.get_global_rect().get_center() - ic.size * 0.5 - _fx.get_global_rect().position
	var target_node: Control = _showcase
	match str(r.get("type", "")):
		"gems":
			target_node = gem_counter
		"gold":
			target_node = gold_label
	var end: Vector2 = target_node.get_global_rect().get_center() - ic.size * 0.5 - _fx.get_global_rect().position
	ic.position = start
	ic.pivot_offset = ic.size * 0.5
	var mid := (start + end) * 0.5 + Vector2(0, -90)
	var tw := ic.create_tween()
	tw.tween_interval(delay)
	tw.tween_method(func(k: float) -> void:
		ic.position = start.lerp(mid, k).lerp(mid.lerp(end, k), k)
		ic.scale = Vector2.ONE * lerpf(1.25, 0.5, k), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(ic, "modulate:a", 0.0, 0.12)
	tw.tween_callback(ic.queue_free)


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
		"%d gemmes : skins exclusifs (personnages et armes), gemmes et or.\nLes paliers déjà atteints deviennent récupérables. Purement cosmétique." % price,
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


# --- Composants ----------------------------------------------------------------------------

## Case d'une récompense dans la grille : icône + petite quantité ; états dessinés (aucun texte
## long). Les skins ont un cadre de rareté plus marqué.
class PassCell extends Button:
	const EMPTY := 0
	const LOCKED := 1
	const PREMIUM_LOCKED := 2
	const AVAILABLE := 3
	const CLAIMED := 4
	var tier: int = 0
	var track: StringName = &""
	var reward: Dictionary = {}
	var state: int = EMPTY
	var featured: bool = false
	var icon_view: RewardIcon = null
	var amount_label: Label = null
	var lock: PassGlyph = null
	var check: PassGlyph = null
	var dot: Panel = null
	var glow: Panel = null
	var _selected: bool = false
	var _accent: Color = Color.WHITE

	func setup(t: int, tr: StringName, r: Dictionary, px: float) -> void:
		tier = t
		track = tr
		reward = r
		name = "Cell_%s_%d" % [tr, t]
		text = ""
		focus_mode = Control.FOCUS_ALL
		custom_minimum_size = Vector2(px, px)
		clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
		_accent = RewardIcon.color_of(r)
		featured = str(r.get("type", "")) == "skin"
		if r.is_empty():
			disabled = true
			var e := StyleBoxFlat.new()
			e.bg_color = Color(1, 1, 1, 0.025)
			e.set_corner_radius_all(14)
			add_theme_stylebox_override("disabled", e)
			return
		glow = Panel.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var gs := StyleBoxFlat.new()
		gs.draw_center = false
		gs.border_color = MenuKit.GOLD
		gs.set_border_width_all(3)
		gs.set_corner_radius_all(16)
		gs.set_expand_margin_all(3)
		gs.shadow_color = Color(MenuKit.GOLD, 0.55)
		gs.shadow_size = 10
		glow.add_theme_stylebox_override("panel", gs)
		glow.visible = false
		add_child(glow)
		icon_view = RewardIcon.new()
		icon_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var pad: float = px * (0.08 if featured else 0.16)
		icon_view.offset_left = pad
		icon_view.offset_top = pad
		icon_view.offset_right = -pad
		icon_view.offset_bottom = -pad
		add_child(icon_view)
		icon_view.set_reward(r, true)
		var n := int(r.get("amount", 0))
		if str(r.get("type", "")) != "skin" and n > 1:
			amount_label = MenuKit.label(_short(n), 13, MenuKit.TEXT, MenuKit.nunito(1000), 4)
			amount_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			amount_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			amount_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
			amount_label.offset_right = -5
			amount_label.offset_bottom = -1
			amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			add_child(amount_label)
		lock = PassGlyph.new(&"lock", MenuKit.GOLD if tr == &"premium" else MenuKit.TEXT_DIM, 18)
		lock.position = Vector2(4, 4)
		lock.size = Vector2(18, 18)
		add_child(lock)
		check = PassGlyph.new(&"check", MenuKit.GOOD, 30)
		check.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		check.offset_left = -15
		check.offset_top = -15
		check.offset_right = 15
		check.offset_bottom = 15
		add_child(check)
		dot = Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ds := StyleBoxFlat.new()
		ds.bg_color = MenuKit.GOLD
		ds.set_corner_radius_all(7)
		ds.border_color = MenuKit.NIGHT_DEEP
		ds.set_border_width_all(2)
		dot.add_theme_stylebox_override("panel", ds)
		dot.size = Vector2(14, 14)
		dot.position = Vector2(px - 10, -4)
		add_child(dot)
		MenuKit.add_feedback(self, 1.06)

	static func _short(n: int) -> String:
		return "%dk" % (n / 1000) if n >= 1000 and n % 1000 == 0 else ("%.1fk" % (n / 1000.0) if n >= 1000 else str(n))

	func apply_state(bp: BattlePassSystem, reached_tier: int) -> void:
		if reward.is_empty():
			return
		if bp.is_claimed(tier, track):
			state = CLAIMED
		elif bp.can_claim(tier, track):
			state = AVAILABLE
		elif track == &"premium" and not bp.premium:
			state = PREMIUM_LOCKED
		else:
			state = LOCKED
		var reached: bool = tier <= reached_tier
		lock.visible = state == PREMIUM_LOCKED or (state == LOCKED and not reached)
		check.visible = state == CLAIMED
		dot.visible = state == AVAILABLE
		glow.visible = state == AVAILABLE
		var a: float = 1.0
		match state:
			CLAIMED:
				a = 0.32
			LOCKED, PREMIUM_LOCKED:
				a = 0.55 if not featured else 0.8
		icon_view.modulate = Color(1, 1, 1, a)
		if amount_label != null:
			amount_label.modulate.a = 0.5 if state == CLAIMED else 1.0
		_restyle()

	func set_selected(on: bool) -> void:
		if on == _selected:
			return
		_selected = on
		if not reward.is_empty():
			_restyle()

	func set_pulse(v: float) -> void:
		if glow != null and glow.visible:
			glow.modulate.a = 0.35 + 0.65 * v

	func _restyle() -> void:
		var bg := Color(0.1, 0.13, 0.22)
		var border := Color(1, 1, 1, 0.1)
		var bw := 1
		if featured:
			bg = bg.lerp(_accent.darkened(0.55), 0.35)
			border = Color(_accent, 0.85)
			bw = 2
		if state == CLAIMED:
			bg = bg.darkened(0.35)
			border = Color(border, border.a * 0.4)
		if _selected:
			border = Color(1, 1, 1, 0.95)
			bw = 3
		var st := StyleBoxFlat.new()
		st.bg_color = bg
		st.border_color = border
		st.set_border_width_all(bw)
		st.set_corner_radius_all(14)
		st.anti_aliasing = true
		var hv := st.duplicate() as StyleBoxFlat
		hv.bg_color = bg.lightened(0.08)
		var f := StyleBoxFlat.new()
		f.draw_center = false
		f.border_color = MenuKit.GOLD.lightened(0.3)
		f.set_border_width_all(2)
		f.set_corner_radius_all(16)
		f.set_expand_margin_all(2)
		add_theme_stylebox_override("normal", st)
		add_theme_stylebox_override("hover", hv)
		add_theme_stylebox_override("pressed", hv)
		add_theme_stylebox_override("hover_pressed", hv)
		add_theme_stylebox_override("focus", f)

	## La case « s'ouvre » : éclat doré, rebond.
	func play_open(delay: float = 0.0) -> void:
		pivot_offset = size * 0.5
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(self, "scale", Vector2(1.18, 1.18), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var flash := Panel.new()
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var fs := StyleBoxFlat.new()
		fs.bg_color = Color(1.0, 0.86, 0.5, 0.85)
		fs.set_corner_radius_all(14)
		flash.add_theme_stylebox_override("panel", fs)
		flash.modulate.a = 0.0
		add_child(flash)
		var t2 := flash.create_tween()
		t2.tween_interval(delay)
		t2.tween_property(flash, "modulate:a", 1.0, 0.06)
		t2.tween_property(flash, "modulate:a", 0.0, 0.35)
		t2.tween_callback(flash.queue_free)


## Numéro du palier entre les deux cases (fin trait de piste derrière).
## Ligne de piste dorée jusqu'au palier atteint ; palier suivant dans une pastille claire.
class TierNumber extends Control:
	var tier: int = 0
	var reached: bool = false
	var next: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_reached(r: bool, n: bool) -> void:
		if r == reached and n == next:
			return
		reached = r
		next = n
		queue_redraw()

	func _draw() -> void:
		var f: Font = MenuKit.nunito(1000)
		var fs: int = 15
		var txt := str(tier)
		var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var y: float = size.y * 0.5
		var line_col := Color(MenuKit.GOLD, 0.7) if reached else Color(1, 1, 1, 0.08)
		draw_line(Vector2(0, y), Vector2(size.x * 0.5 - tw * 0.5 - 9, y), line_col, 3.0)
		draw_line(Vector2(size.x * 0.5 + tw * 0.5 + 9, y), Vector2(size.x, y), line_col, 3.0)
		var col := MenuKit.GOLD if reached else MenuKit.TEXT_DIM
		if next:
			var pill := Rect2(size.x * 0.5 - tw * 0.5 - 9, y - 12, tw + 18, 24)
			var sb := StyleBoxFlat.new()
			sb.bg_color = MenuKit.TEXT
			sb.set_corner_radius_all(12)
			draw_style_box(sb, pill)
			col = MenuKit.NIGHT_DEEP
		draw_string(f, Vector2(size.x * 0.5 - tw * 0.5, y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Décor de la vitrine : le camp de Dust Creek (rendu du lobby) assombri, rayons et halo à la
## couleur de la récompense, fondu vers le texte. Redessiné seulement si la couleur change.
class ShowcaseBackdrop extends Control:
	const BACK_PATH := "res://assets/ui/menu/lobby/back.jpg"
	const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")
	var accent: Color = MenuKit.GOLD
	var strong: bool = false
	var _back: Texture2D = null
	var _shade: GradientTexture2D = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_back = load(BACK_PATH) as Texture2D if ResourceLoader.exists(BACK_PATH) else null
		var g := Gradient.new()
		g.set_color(0, Color(MenuKit.NIGHT, 0.15))
		g.add_point(0.42, Color(MenuKit.NIGHT, 0.55))
		g.set_color(g.get_point_count() - 1, Color(MenuKit.NIGHT, 0.95))
		_shade = GradientTexture2D.new()
		_shade.gradient = g
		_shade.width = 64
		_shade.height = 4
		resized.connect(queue_redraw)

	func set_accent(c: Color, p_strong: bool) -> void:
		if c.is_equal_approx(accent) and p_strong == strong:
			return
		accent = c
		strong = p_strong
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if _back != null:
			# « cover » cadré sur le bas du camp (sol + feu), assombri
			var ts := _back.get_size()
			var k: float = maxf(size.x / ts.x, size.y / ts.y) * 1.05
			var src := Rect2(Vector2.ZERO, size / k)
			src.position = Vector2((ts.x - src.size.x) * 0.38, (ts.y - src.size.y) * 0.62)
			draw_texture_rect_region(_back, r, src, Color(0.42, 0.4, 0.5))
		# rayons depuis le visuel
		var c := Vector2(size.x * 0.22, size.y * 0.62)
		var n: int = 16
		var reach: float = size.length()
		for i: int in n:
			var a0: float = TAU * i / n
			var a1: float = a0 + TAU / n * 0.45
			var pts := PackedVector2Array([c, c + Vector2.from_angle(a0) * reach, c + Vector2.from_angle(a1) * reach])
			draw_colored_polygon(pts, Color(accent, 0.07 if strong else 0.045))
		var gw: float = size.y * (1.9 if strong else 1.5)
		draw_texture_rect(GLOW, Rect2(c - Vector2(gw, gw) * 0.5, Vector2(gw, gw)), false, Color(accent, 0.55 if strong else 0.35))
		# sol : ombre douce sous le visuel
		draw_texture_rect(GLOW, Rect2(Vector2(size.x * 0.22 - size.y * 0.5, size.y * 0.86), Vector2(size.y, size.y * 0.18)), false, Color(0, 0, 0.05, 0.5))
		# fondu vers la zone de texte (droite) + bas
		draw_texture_rect(_shade, r, false)


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

	## Couleur d'une récompense : rareté du skin, cyan des gemmes, or, rareté de l'objet.
	static func color_of(r: Dictionary) -> Color:
		match str(r.get("type", "")):
			"gems":
				return MenuKit.GEM
			"gold":
				return MenuKit.GOLD
			"skin":
				var s := SkinData.get_skin(StringName(str(r.get("id", ""))))
				return MenuKit.rarity_color(s.rarity if s != null else 0)
			"item":
				var it := item_of(r)
				return MenuKit.rarity_color(it.rarity if it != null else 0)
		return MenuKit.TEXT_DIM

	## `compact` : case de grille (buste du personnage plutôt qu'en pied).
	func set_reward(r: Dictionary, compact: bool = false) -> void:
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
					var tex := ShopScreen.cropped_preview(ShopScreen.pose_texture(s))
					if compact and tex is AtlasTexture:
						# buste : moitié haute du personnage
						var a := (tex as AtlasTexture).duplicate() as AtlasTexture
						a.region = Rect2(a.region.position, Vector2(a.region.size.x, a.region.size.y * 0.58))
						tex = a
					tr.texture = tex
					tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
					c = tr
				elif s != null:
					var ic := WeaponIcon.new()
					c = ic
					ic.set_weapon(ShopScreen.weapon_of(s), s, false)
			"gems":
				c = GemIcon.new()
			"gold":
				c = MenuGlyph.new(&"coin", MenuKit.COIN, 32)
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
			c.anchor_left = 0.12
			c.anchor_right = 0.88
			c.anchor_top = 0.12
			c.anchor_bottom = 0.88
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
