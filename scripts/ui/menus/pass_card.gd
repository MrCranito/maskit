class_name PassCard
extends Button
## Carte « Pass de combat » du lobby (bas gauche, direction « D ») : boîte encre à coin haut droit
## coupé et liseré violet à gauche ; vignette du skin phare de la saison (prochain skin de
## personnage premium, même rendu que le lobby). Retour de Victor (« l'affichage des paliers
## pourrait être mieux ») — hiérarchie en trois niveaux :
##   1. en-tête : « PASS DE COMBAT » (petit, violet clair) + pastille « N À RÉCUPÉRER » (violet
##      plein, halo qui pulse doucement : elle attire l'œil sans le rouge d'alerte) ;
##   2. « PALIER N / 30 » en Anton, puis la barre d'XP du palier et sa légende « x / y XP » ;
##   3. à droite, la prochaine récompense : sa vignette (RewardIcon dans une case à la couleur de
##      la récompense) au-dessus de « Palier N+1 » et de sa valeur.
## Accent or si le premium est actif. Un tap ouvre l'écran du pass. Mise à jour sur
## BattlePassSystem.changed / Profile.changed (pas de _process : la pulsation est un Tween).

var thumb: HeroPreview = null
var title_label: Label = null
var tier_label: Label = null
var tier_max_label: Label = null
var xp_bar: ProgressBar = null
## « 120 / 400 XP » sous la barre (« Pass terminé » au dernier palier).
var xp_label: Label = null
## Case de la prochaine récompense (fond + liseré à sa couleur) et son icône.
var next_tile: PanelContainer = null
var next_icon: BattlePassScreen.RewardIcon = null
## « Palier N » (prochain palier) ; la récompense est dans `next_value`.
var next_label: Label = null
var next_value: Label = null
var claim_pill: PanelContainer = null
var premium_pill: PanelContainer = null
var _bp: BattlePassSystem = null
var _thumb_box: Control = null
var _claim_halo: Panel = null
var _pulse: Tween = null


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	text = ""
	custom_minimum_size = Vector2(Balance.get_float("menu", "pass_card_width", 480.0),
		Balance.get_float("menu", "pass_card_height", 120.0))
	var h: float = custom_minimum_size.y
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 17
	row.offset_top = 0
	row.offset_right = -18
	row.offset_bottom = 0
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	# Vignette : dégradé violet → encre, skin phare en pied (rogné en bas), pleine hauteur
	_thumb_box = ThumbBox.new()
	_thumb_box.name = "ThumbBox"
	_thumb_box.custom_minimum_size = Vector2(h * 0.74, 0)
	_thumb_box.clip_contents = true
	_thumb_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_thumb_box)
	thumb = HeroPreview.new()
	thumb.name = "Thumb"
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb.offset_top = -4
	thumb.offset_bottom = 34
	thumb.height_ratio = 1.0
	thumb.feet_ratio = 1.0
	_thumb_box.add_child(thumb)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 6)
	row.add_child(body)

	# 1. En-tête : titre + pastilles
	var head := HBoxContainer.new()
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	body.add_child(head)
	title_label = MenuKit.label("Pass de combat", 14, MenuKit.GOLD, MenuKit.nunito(700))
	title_label.uppercase = true
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(title_label)
	premium_pill = MenuKit.pill("Premium", Color(MenuKit.COIN.darkened(0.55), 0.95), 12, MenuKit.COIN.lightened(0.3))
	premium_pill.name = "PremiumPill"
	premium_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(premium_pill)
	claim_pill = _claim_pill()
	head.add_child(claim_pill)
	# marge à droite : la pastille ne mord pas sur le coin coupé de la carte
	var bevel := Control.new()
	bevel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bevel.custom_minimum_size.x = 12.0
	head.add_child(bevel)

	# 2. Palier + barre d'XP (à gauche) | 3. prochaine récompense (à droite)
	var main := HBoxContainer.new()
	main.name = "Main"
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_theme_constant_override("separation", 16)
	body.add_child(main)
	var left := VBoxContainer.new()
	left.name = "Progress"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_END
	left.add_theme_constant_override("separation", 4)
	main.add_child(left)
	var tier_row := HBoxContainer.new()
	tier_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tier_row.add_theme_constant_override("separation", 6)
	left.add_child(tier_row)
	tier_label = MenuKit.label("", 34, MenuKit.TEXT, MenuKit.display(), 0)
	tier_row.add_child(tier_label)
	tier_max_label = MenuKit.label("", 20, Color(1, 1, 1, 0.55), MenuKit.display(), 0)
	tier_max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	tier_row.add_child(tier_max_label)
	xp_bar = ProgressBar.new()
	xp_bar.name = "XpBar"
	xp_bar.show_percentage = false
	xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_bar.custom_minimum_size = Vector2(0, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.VIOLET_LIGHT
	xp_bar.add_theme_stylebox_override("background", bg)
	xp_bar.add_theme_stylebox_override("fill", fill)
	left.add_child(xp_bar)
	xp_label = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	xp_label.name = "XpLabel"
	xp_label.clip_text = true
	xp_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(xp_label)

	var next := VBoxContainer.new()
	next.name = "Next"
	next.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next.alignment = BoxContainer.ALIGNMENT_END
	next.add_theme_constant_override("separation", 1)
	next.custom_minimum_size.x = Balance.get_float("menu", "pass_card_next_width", 96.0)
	main.add_child(next)
	var tile_px: float = Balance.get_float("menu", "pass_card_next_tile", 50.0)
	next_tile = PanelContainer.new()
	next_tile.name = "NextTile"
	next_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_tile.custom_minimum_size = Vector2(tile_px, tile_px)
	next_tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	next.add_child(next_tile)
	next_icon = BattlePassScreen.RewardIcon.new()
	next_icon.name = "NextIcon"
	next_tile.add_child(next_icon)
	next_label = MenuKit.label("", 13, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	next_label.name = "NextLabel"
	next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next.add_child(next_label)
	next_value = MenuKit.label("", 15, MenuKit.TEXT, MenuKit.nunito(700))
	next_value.name = "NextValue"
	next_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_value.clip_text = true
	next_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	next_value.custom_minimum_size.x = next.custom_minimum_size.x
	next.add_child(next_value)


## Pastille « N À RÉCUPÉRER » : violet plein à coins biseautés, texte blanc ; derrière, un halo
## violet clair dont l'opacité et la taille pulsent doucement (boucle Tween, arrêtée hors écran).
func _claim_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "ClaimPill"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := CutBox.make(MenuKit.VIOLET, 6.0, Color(MenuKit.GOLD, 0.9), 1.0, 9.0, 2.0)
	p.add_theme_stylebox_override("panel", box)
	_claim_halo = Panel.new()
	_claim_halo.name = "Halo"
	_claim_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claim_halo.show_behind_parent = true
	var hb := CutBox.make(Color(MenuKit.VIOLET_LIGHT, 0.55), 8.0)
	hb.grow = 5.0
	_claim_halo.add_theme_stylebox_override("panel", hb)
	_claim_halo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_claim_halo.modulate.a = 0.0
	p.add_child(_claim_halo)
	var l := MenuKit.label("", 13, MenuKit.TEXT, MenuKit.nunito(800))
	l.name = "Text"
	l.uppercase = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


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


func _exit_tree() -> void:
	_stop_pulse()


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
	(xp_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = MenuKit.COIN if premium else MenuKit.VIOLET_LIGHT


func refresh() -> void:
	if _bp == null:
		return
	var t := _bp.tier()
	var top := _bp.max_tier()
	tier_label.text = "PALIER %d" % t
	tier_max_label.text = "/ %d" % top
	var prog := _bp.tier_progress()
	xp_bar.max_value = maxi(prog.y, 1)
	xp_bar.value = prog.x if prog.y > 0 else 1
	xp_label.text = xp_text(prog)
	var n := _bp.claimable_count()
	claim_pill.visible = n > 0
	(claim_pill.get_node("Text") as Label).text = "%d à récupérer" % n
	_set_pulse(n > 0)
	premium_pill.visible = _bp.premium
	_style(_bp.premium)
	var sk := featured_skin(_bp)
	thumb.visible = sk != null
	if sk != null and thumb.skin != sk:
		thumb.set_skin(sk, false)
	# Prochaine récompense : celle du palier suivant (premium si actif, sinon gratuite)
	if t >= top:
		next_label.text = "Pass terminé"
		next_value.text = ""
		next_icon.visible = false
		_tile_style(MenuKit.TEXT_DIM)
		return
	var r := _bp.reward(t + 1, BattlePassSystem.PREMIUM if _bp.premium else BattlePassSystem.FREE)
	if r.is_empty():
		r = _bp.reward(t + 1, BattlePassSystem.FREE)
	next_icon.visible = not r.is_empty()
	next_icon.set_reward(r, true)
	next_label.text = "Palier %d" % (t + 1)
	next_value.text = BattlePassSystem.reward_label(r)
	_tile_style(BattlePassScreen.RewardIcon.color_of(r) if not r.is_empty() else MenuKit.TEXT_DIM)


## « 120 / 400 XP » (XP du palier en cours) ; « Pass terminé » au dernier palier.
static func xp_text(prog: Vector2i) -> String:
	if prog.y <= 0:
		return "Pass terminé"
	return "%s / %s XP" % [Economy.fmt(prog.x), Economy.fmt(prog.y)]


## Case de la récompense : encre teintée de la couleur de la récompense, liseré à sa couleur.
func _tile_style(c: Color) -> void:
	var box := CutBox.make(Color(c.darkened(0.7), 0.85), 8.0, Color(c, 0.9), 1.5, 3.0, 2.0)
	box.corners = CutBox.CUT_TOP_LEFT | CutBox.CUT_BOTTOM_RIGHT
	next_tile.add_theme_stylebox_override("panel", box)


func _set_pulse(on: bool) -> void:
	if not on:
		_stop_pulse()
		return
	if _pulse != null and _pulse.is_valid():
		return
	if not is_inside_tree():
		return
	var period: float = Balance.get_float("menu", "pass_claim_pulse", 1.6)
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_claim_halo, "modulate:a", 1.0, period * 0.5).from(0.15) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse.tween_property(_claim_halo, "modulate:a", 0.15, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	if _claim_halo != null:
		_claim_halo.modulate.a = 0.0


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
