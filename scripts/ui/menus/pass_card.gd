class_name PassCard
extends Button
## Carte « Pass de combat » du lobby (bas gauche, direction « D », maquette Lobby) : boîte encre
## à coin haut droit coupé et liseré violet à gauche ; vignette du skin phare de la saison
## (prochain skin de personnage premium, même rendu que le lobby) ; à droite « PASS DE COMBAT »
## (petit, violet clair) + pastille « N À RÉCUPÉRER », « PALIER N / 30 » en Anton, barre d'XP et
## prochaine récompense (« Palier N » + icône + valeur). Accent or si le premium est actif.
## Un tap ouvre l'écran du pass. Mise à jour sur BattlePassSystem.changed / Profile.changed.

var thumb: HeroPreview = null
var title_label: Label = null
var tier_label: Label = null
var tier_max_label: Label = null
var xp_bar: ProgressBar = null
var next_icon: BattlePassScreen.RewardIcon = null
## « Palier N » (prochain palier) ; la récompense est dans `next_value`.
var next_label: Label = null
var next_value: Label = null
var claim_pill: PanelContainer = null
var premium_pill: PanelContainer = null
var _bp: BattlePassSystem = null
var _thumb_box: Control = null


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	text = ""
	custom_minimum_size = Vector2(Balance.get_float("menu", "pass_card_width", 420.0),
		Balance.get_float("menu", "pass_card_height", 120.0))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 18
	row.offset_top = 10
	row.offset_right = -20
	row.offset_bottom = -10
	row.add_theme_constant_override("separation", 20)
	add_child(row)
	# Vignette : dégradé violet → encre, skin phare en pied (rogné en bas)
	_thumb_box = ThumbBox.new()
	_thumb_box.custom_minimum_size = Vector2(custom_minimum_size.y * 0.82, 0)
	_thumb_box.clip_contents = true
	_thumb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_thumb_box)
	thumb = HeroPreview.new()
	thumb.name = "Thumb"
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb.offset_top = -10
	thumb.offset_bottom = 30
	thumb.height_ratio = 1.0
	thumb.feet_ratio = 1.0
	_thumb_box.add_child(thumb)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	title_label = MenuKit.label("Pass de combat", 15, MenuKit.GOLD, MenuKit.nunito(600))
	title_label.uppercase = true
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	premium_pill = MenuKit.pill("Premium", Color(MenuKit.COIN.darkened(0.55), 0.95), 12, MenuKit.COIN.lightened(0.3))
	head.add_child(premium_pill)
	claim_pill = MenuKit.pill("", Color(1.0, 0.24, 0.43), 13, MenuKit.TEXT)
	claim_pill.name = "ClaimPill"
	(claim_pill.get_node("Text") as Label).uppercase = true
	head.add_child(claim_pill)
	var tier_row := HBoxContainer.new()
	tier_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tier_row.add_theme_constant_override("separation", 6)
	col.add_child(tier_row)
	tier_label = MenuKit.label("", 34, MenuKit.TEXT, MenuKit.display(), 0)
	tier_row.add_child(tier_label)
	tier_max_label = MenuKit.label("", 20, Color(1, 1, 1, 0.55), MenuKit.display(), 0)
	tier_max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	tier_max_label.offset_bottom = -4
	tier_row.add_child(tier_max_label)
	xp_bar = ProgressBar.new()
	xp_bar.show_percentage = false
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.VIOLET_LIGHT
	xp_bar.add_theme_stylebox_override("background", bg)
	xp_bar.add_theme_stylebox_override("fill", fill)
	col.add_child(xp_bar)
	var next := HBoxContainer.new()
	next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next.add_theme_constant_override("separation", 8)
	col.add_child(next)
	next_label = MenuKit.label("", 18, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	next_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	next.add_child(next_label)
	next_icon = BattlePassScreen.RewardIcon.new()
	next_icon.custom_minimum_size = Vector2(26, 22)
	next.add_child(next_icon)
	next_value = MenuKit.label("", 18, MenuKit.TEXT, MenuKit.nunito(700))
	next_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	next_value.clip_text = true
	next_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	next.add_child(next_value)


## Fond de la vignette : dégradé violet clair → encre (maquette).
class ThumbBox extends Control:
	func _draw() -> void:
		var top := Color(0.73, 0.55, 1.0, 0.45)
		var bot := Color(MenuKit.NIGHT_DEEP, 0.6)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
			PackedColorArray([top, top, bot, bot]))


func _ready() -> void:
	MenuKit.add_feedback(self, 1.02)
	_bp = BattlePassSystem.get_instance()
	if thumb.glow != null:
		thumb.glow.visible = false
	_bp.changed.connect(refresh)
	Profile.changed.connect(refresh)
	refresh()


func _style(premium: bool) -> void:
	var accent: Color = MenuKit.COIN if premium else MenuKit.VIOLET
	var n := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.82), 26.0)
	n.corners = CutBox.CUT_TOP_RIGHT
	n.accent_width = 5.0
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
	tier_label.text = "PALIER %d" % t
	tier_max_label.text = "/ %d" % _bp.max_tier()
	var prog := _bp.tier_progress()
	xp_bar.max_value = maxi(prog.y, 1)
	xp_bar.value = prog.x if prog.y > 0 else 1
	var n := _bp.claimable_count()
	claim_pill.visible = n > 0
	(claim_pill.get_node("Text") as Label).text = "%d à récupérer" % n
	premium_pill.visible = _bp.premium
	_style(_bp.premium)
	var sk := featured_skin(_bp)
	thumb.visible = sk != null
	if sk != null and thumb.skin != sk:
		thumb.set_skin(sk, false)
	# Prochaine récompense : celle du palier suivant (premium si actif, sinon gratuite)
	if t >= _bp.max_tier():
		next_label.text = "Pass terminé"
		next_value.text = ""
		next_icon.visible = false
		return
	var r := _bp.reward(t + 1, BattlePassSystem.PREMIUM if _bp.premium else BattlePassSystem.FREE)
	if r.is_empty():
		r = _bp.reward(t + 1, BattlePassSystem.FREE)
	next_icon.visible = not r.is_empty()
	next_icon.set_reward(r, true)
	next_label.text = "Palier %d" % (t + 1)
	next_value.text = BattlePassSystem.reward_label(r)


## Skin phare de la saison : prochain skin de personnage premium pas encore possédé, sinon le
## dernier skin de personnage du pass.
static func featured_skin(bp: BattlePassSystem) -> SkinData:
	var s := bp.get_season()
	var last: SkinData = null
	for t: int in range(1, s.tiers + 1):
		var r := s.reward(t, BattlePassSystem.PREMIUM)
		if str(r.get("type", "")) != "skin":
			continue
		var sk := SkinData.get_skin(StringName(str(r.get("id", ""))))
		if sk == null or sk.kind != SkinData.KIND_CHARACTER:
			continue
		last = sk
		if t > bp.tier() and not Profile.owns_skin(sk.id):
			return sk
	return last
