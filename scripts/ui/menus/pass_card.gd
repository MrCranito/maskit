class_name PassCard
extends Button
## Carte « Pass de combat » du lobby (colonne de gauche, sous l'Arsenal de départ) : étoile de
## shérif avec le palier, barre d'XP, prochaine récompense (petite icône + libellé), pastille
## « N à récupérer », liseré et accent or si le premium est actif. Un tap ouvre l'écran du pass.
## Se met à jour sur BattlePassSystem.changed / Profile.changed (aucun _process).

var badge: BattlePassScreen.TierBadge = null
var title_label: Label = null
var tier_label: Label = null
var xp_bar: ProgressBar = null
var next_icon: BattlePassScreen.RewardIcon = null
var next_label: Label = null
var claim_pill: PanelContainer = null
var premium_pill: PanelContainer = null
var _bp: BattlePassSystem = null


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	text = ""
	custom_minimum_size = Vector2(Balance.get_float("menu", "loadout_panel_width", 290.0), 112)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_top = 10
	col.offset_right = -12
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	badge = BattlePassScreen.TierBadge.new()
	badge.custom_minimum_size = Vector2(46, 46)
	head.add_child(badge)
	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", -3)
	head.add_child(titles)
	title_label = MenuKit.label("Pass de combat", 18, MenuKit.TEXT, MenuKit.nunito(900), 3)
	titles.add_child(title_label)
	tier_label = MenuKit.label("", 13, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	titles.add_child(tier_label)
	# pastille de notification à cheval sur le coin haut droit
	claim_pill = MenuKit.pill("", MenuKit.RED, 12, MenuKit.TEXT, Color(1, 1, 1, 0.8))
	claim_pill.name = "ClaimPill"
	claim_pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	claim_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	claim_pill.offset_right = 8
	claim_pill.offset_top = -9
	add_child(claim_pill)
	premium_pill = MenuKit.pill("Premium", Color(MenuKit.GOLD.darkened(0.55), 0.95), 11, MenuKit.GOLD.lightened(0.3), Color(MenuKit.GOLD, 0.6))
	premium_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(premium_pill)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.custom_minimum_size = Vector2(0, 9)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	bg.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.GOLD
	fill.set_corner_radius_all(5)
	xp_bar.add_theme_stylebox_override("background", bg)
	xp_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(xp_bar)
	var next := HBoxContainer.new()
	next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next.add_theme_constant_override("separation", 6)
	col.add_child(next)
	next_icon = BattlePassScreen.RewardIcon.new()
	next_icon.custom_minimum_size = Vector2(30, 24)
	next.add_child(next_icon)
	next_label = MenuKit.label("", 13, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	next_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	next_label.clip_text = true
	next_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	next.add_child(next_label)
	var chev := MenuGlyph.new(&"chevron", MenuKit.TEXT_DIM, 16)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	next.add_child(chev)


func _ready() -> void:
	MenuKit.add_feedback(self, 1.02)
	_bp = BattlePassSystem.get_instance()
	_bp.changed.connect(refresh)
	Profile.changed.connect(refresh)
	refresh()


func _style(premium: bool) -> void:
	var accent: Color = MenuKit.GOLD if premium else MenuKit.BORDER
	var n := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.86), Color(accent, 0.9 if premium else 0.35), 18, 2 if premium else 1, 0)
	if premium:
		n.bg_color = Color(MenuKit.NIGHT, 0.86).lerp(MenuKit.GOLD.darkened(0.6), 0.18)
		n.shadow_color = Color(MenuKit.GOLD, 0.25)
		n.shadow_size = 10
		n.shadow_offset = Vector2.ZERO
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = n.bg_color.lightened(0.06)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = n.bg_color.darkened(0.2)
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = MenuKit.GOLD
	f.set_border_width_all(3)
	f.set_corner_radius_all(21)
	f.set_expand_margin_all(4)
	add_theme_stylebox_override("normal", n)
	add_theme_stylebox_override("hover", h)
	add_theme_stylebox_override("pressed", p)
	add_theme_stylebox_override("hover_pressed", p)
	add_theme_stylebox_override("focus", f)


func refresh() -> void:
	if _bp == null:
		return
	var t := _bp.tier()
	badge.set_tier(t)
	tier_label.text = "Palier %d sur %d" % [t, _bp.max_tier()]
	var prog := _bp.tier_progress()
	xp_bar.max_value = maxi(prog.y, 1)
	xp_bar.value = prog.x if prog.y > 0 else 1
	var n := _bp.claimable_count()
	claim_pill.visible = n > 0
	(claim_pill.get_node("Text") as Label).text = "%d à récupérer" % n
	premium_pill.visible = _bp.premium
	_style(_bp.premium)
	# Prochaine récompense : celle du palier suivant (premium si actif, sinon gratuite)
	if t >= _bp.max_tier():
		next_label.text = "Pass terminé"
		next_icon.visible = false
		return
	var r := _bp.reward(t + 1, BattlePassSystem.PREMIUM if _bp.premium else BattlePassSystem.FREE)
	if r.is_empty():
		r = _bp.reward(t + 1, BattlePassSystem.FREE)
	next_icon.visible = not r.is_empty()
	next_icon.set_reward(r, true)
	next_label.text = "Prochaine : %s" % BattlePassSystem.reward_label(r)
