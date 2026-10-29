class_name PassCard
extends Button
## Carte « Pass de combat » du lobby (bas gauche, direction « D ») : boîte encre à coins coupés
## avec barre violette à gauche, étoile avec le palier, titre en Anton, barre d'XP, prochaine
## récompense (petite icône + « Palier N · récompense »), pastille « N à récupérer », accent or
## si le premium est actif. Un tap ouvre l'écran du pass.
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
	custom_minimum_size = Vector2(Balance.get_float("menu", "pass_card_width", 420.0), 112)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
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
	title_label = MenuKit.label("PASS DE COMBAT", 22, MenuKit.TEXT, MenuKit.display())
	titles.add_child(title_label)
	tier_label = MenuKit.label("", 13, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	titles.add_child(tier_label)
	# pastille de notification à cheval sur le coin haut droit
	claim_pill = MenuKit.pill("", Color(1.0, 0.24, 0.43), 12, MenuKit.TEXT)
	claim_pill.name = "ClaimPill"
	claim_pill.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	claim_pill.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	claim_pill.offset_right = -10
	claim_pill.offset_top = 10
	add_child(claim_pill)
	premium_pill = MenuKit.pill("Premium", Color(MenuKit.COIN.darkened(0.55), 0.95), 11, MenuKit.COIN.lightened(0.3), Color(MenuKit.COIN, 0.6))
	premium_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(premium_pill)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.custom_minimum_size = Vector2(0, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.VIOLET_LIGHT
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
	next_label = MenuKit.label("", 13, MenuKit.TEXT, MenuKit.nunito(600))
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
	var accent: Color = MenuKit.COIN if premium else MenuKit.VIOLET
	var n := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.82), 16.0)
	n.corners = CutBox.CUT_TOP_RIGHT
	n.accent_width = 4.0
	n.accent_color = accent
	var h := n.duplicate() as CutBox
	h.bg_color = Color(0.09, 0.08, 0.16, 0.9)
	var p := n.duplicate() as CutBox
	p.bg_color = Color(0, 0, 0, 0.9)
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.GOLD
	f.border_width = 2.0
	f.cut = 18.0
	f.corners = CutBox.CUT_TOP_RIGHT
	f.grow = 4.0
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
	tier_label.text = "Palier %d / %d" % [t, _bp.max_tier()]
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
	next_label.text = "Palier %d · %s" % [t + 1, BattlePassSystem.reward_label(r)]
