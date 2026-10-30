class_name MainMenu
extends Control
## Menu principal de RaidersGo, direction « D » :
##  - fond vivant : camp de base à la lisière de Dust Creek au coucher du soleil (LobbyScene,
##    rendu Blender en couches + drapeau, feu, fumée, poussière, parallaxe lent) et le héros
##    avec son skin porté (LobbyHero ; tap = Personnages) ; voile sombre à gauche pour la lisibilité ;
##  Disposition = maquette « Lobby » (https://claude.ai/artifact/FTXHPHfN5wZRxSQDW8oaDq), ×1,67 :
##  - barre du haut : logotype RAIDERSGO, niveau de raider (carré violet → Progression),
##    statistiques (raids, extraits, réussite) ; or, gemmes (+ → onglet Gemmes), réglages ;
##    elle s'arrête avant le bandeau ;
##  - gauche : menu texte en Anton (Progression, Arsenal, Inventaire, Atelier, Boutique), blanc
##    atténué, l'entrée active en blanc avec barre violette ; un écran pas encore livré (scène
##    absente) affiche « Bientôt » sans rien ouvrir ;
##  - bas gauche : carte du pass de combat (PassCard → écran du pass) ;
##  - droite : bandeau violet translucide en biais (verre dépoli), pleine hauteur : carte en
##    cours en haut (→ choix des cartes), « DÉPLOYER » (PlayCard → choix des cartes → arsenal de
##    départ → raid) puis Solo / Coop en bas ;
##  - bas centré : version + lien Crédits.
##    L'arsenal emporté n'est plus résumé ici : il se choisit à l'étape 2.
## Animations d'entrée (glissements, fondus), retours tactiles et sons MenuKit, marges de
## sécurité (encoche / barre d'accueil). Aucun _process.

var lobby: LobbyScene = null
var hero: LobbyHero = null
var logo: RaidersLogo = null
var gem_counter: GemCounter = null
var gem_plus: Button = null
var gear_button: Button = null
var credits_top_button: Button = null
## Or (pièces) : Profile.gold (repli : Profile.dollars). `dollar_label` = même label (compatibilité).
var gold_label: Label = null
var dollar_label: Label = null
var stat_values: Dictionary = {}
## Plus affiché au lobby (direction D) : reste null, gardé pour compatibilité.
var loadout_summary: LoadoutSummary = null
var info_banner: InfoBanner = null
var play_button: PlayCard = null
var arsenal_button: NavButton = null
var crafting_button: NavButton = null
var merchant_button: NavButton = null
var shop_button: NavButton = null
## Entrée « Progression » (niveau de raider, déblocages).
var progression_button: NavButton = null
## Carte du pass de combat (bas gauche). Pas d'entrée « Pass » dans le menu : la carte la remplace.
var pass_card: PassCard = null
var coop_button: Button = null
## Emplacement du coéquipier, à droite du héros (repère du décor) : gros « + » (→ coop) tant que
## personne n'a rejoint le salon, puis le coéquipier avec son skin et son pseudo (tap → salon).
var mate_slot: Control = null
var mate_plus: Button = null
var mate_tag: Label = null
var mate_status: Label = null
var _mate_caption: Label = null
## Haut du bandeau : carte en cours (→ choix des cartes).
var map_link: Button = null
var map_name_label: Label = null
var map_sub_label: Label = null
## Compatibilité : Options = bouton réglages, Crédits = bouton étoile de la barre du haut.
var options_button: Button = null
var credits_button: Button = null
## Boutons d'action principaux (Jouer puis la barre de navigation).
var buttons: Array[Button] = []
var ui: Control = null

var _modal: ModalPanel = null
var _top: Control = null
var _nav: Control = null
var _version: Label = null
## Pied de page : état de la sauvegarde cloud (CloudSync), point coloré + libellé.
var cloud_label: Label = null
var _cloud_dot: ColorRect = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	lobby = LobbyScene.new()
	add_child(lobby)
	hero = lobby.hero
	lobby.hero_pressed.connect(func() -> void: _go_shop(&"character"))
	ui = Control.new()
	ui.name = "UI"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	_build()
	_build_mate_slot()
	Profile.changed.connect(_refresh_profile)
	_refresh_profile()
	_connect_session()
	_connect_cloud()
	MenuKit.fade_in(self, 0.45)
	lobby.play_intro()
	_intro.call_deferred()


# --- Construction -------------------------------------------------------------------

## Bandeau violet translucide en biais (bord gauche biseauté) : porte l'info du jour, Coop et DÉPLOYER.
class LobbySlab extends Control:
	var cut: float = 64.0
	var color: Color = Color(MenuKit.VIOLET, 0.62)

	func _draw() -> void:
		draw_colored_polygon(PackedVector2Array([Vector2(cut, 0), Vector2(size.x, 0), size, Vector2(0, size.y)]), color)


var slab: Control = null


func _build() -> void:
	var m: Vector4 = MenuKit.safe_margins(self)
	# marges de la maquette (48 et 22 px ×1,67), jamais sous les marges de sécurité
	m.x = maxf(m.x, Balance.get_float("menu", "lobby_margin_left", 80.0))
	m.w = maxf(m.w, Balance.get_float("menu", "lobby_margin_bottom", 36.0))
	var vp: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var slab_w: float = clampf(vp.x * Balance.get_float("menu", "lobby_slab_ratio", 0.3),
		Balance.get_float("menu", "lobby_slab_min", 370.0), Balance.get_float("menu", "lobby_slab_max", 440.0))

	# Voile à gauche : lisibilité du menu texte sur le décor
	var g := Gradient.new()
	g.set_color(0, Color(MenuKit.NIGHT_DEEP, 0.88))
	g.set_color(1, Color(MenuKit.NIGHT_DEEP, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 64
	gt.height = 4
	var veil := TextureRect.new()
	veil.name = "Veil"
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.anchor_right = 0.55
	veil.anchor_bottom = 1.0
	ui.add_child(veil)

	# Droite : bandeau violet translucide pleine hauteur
	var sl := LobbySlab.new()
	sl.name = "Slab"
	sl.cut = Balance.get_float("menu", "lobby_slab_cut", 64.0)
	sl.color = Color(MenuKit.VIOLET, Balance.get_float("menu", "lobby_slab_alpha", 0.62))
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.anchor_left = 1.0
	sl.anchor_right = 1.0
	sl.anchor_bottom = 1.0
	sl.offset_left = -slab_w
	ui.add_child(sl)
	MenuKit.frosted(sl)
	slab = sl

	# Repères d'angle violets (haut gauche, bas gauche) et trame de lignes très discrète
	var deco := LobbyDeco.new()
	deco.name = "Deco"
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(deco)
	ui.move_child(deco, 1)

	# Barre du haut (s'arrête avant le bandeau) : logotype + niveau, statistiques ; or, gemmes, réglages
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 10)
	top.anchor_right = 1.0
	top.offset_left = m.x
	top.offset_top = m.y
	top.offset_right = -slab_w - 20.0
	top.custom_minimum_size.y = 62
	ui.add_child(top)
	_top = top
	var brand := VBoxContainer.new()
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_theme_constant_override("separation", 8)
	top.add_child(brand)
	var brand_row := HBoxContainer.new()
	brand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_row.add_theme_constant_override("separation", 22)
	brand.add_child(brand_row)
	logo = RaidersLogo.wordmark(int(Balance.get_value("menu", "lobby_wordmark_size", 46)))
	brand_row.add_child(logo)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.2)
	sep.custom_minimum_size = Vector2(2, 46)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_row.add_child(sep)
	brand_row.add_child(_level_badge())
	var stats := HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 22)
	brand.add_child(stats)
	stats.add_child(_stat_chip(&"raids", &"target", "raids"))
	stats.add_child(_stat_chip(&"extractions", &"exit", "extraits"))
	stats.add_child(_stat_chip(&"rate", &"percent", "réussite"))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(fill)
	var gold := _gold_pill()
	gold.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(gold)
	top.add_child(_gem_pill())
	gear_button = _round_button(&"gear", Color(MenuKit.NIGHT_DEEP, 0.6), 66)
	gear_button.tooltip_text = "Réglages"
	gear_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	gear_button.pressed.connect(open_options)
	top.add_child(gear_button)
	options_button = gear_button

	# Gauche : menu texte (l'arsenal de départ se choisit à l'étape 2, plus de résumé ici)
	var nav := VBoxContainer.new()
	nav.name = "NavBar"
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_theme_constant_override("separation", 0)
	ui.add_child(nav)
	nav.position = Vector2(m.x, m.y + top.get_combined_minimum_size().y + 10.0)
	_nav = nav
	arsenal_button = NavButton.new("Arsenal", &"rifle", MenuKit.GOLD)
	merchant_button = NavButton.new("Inventaire", &"chest", MenuKit.GOLD)
	crafting_button = NavButton.new("Atelier", &"anvil", MenuKit.TEXT)
	shop_button = NavButton.new("Boutique", &"bag", MenuKit.GEM)
	progression_button = NavButton.new("Progression", &"star", MenuKit.GOLD)
	for b: NavButton in [progression_button, arsenal_button, merchant_button, crafting_button, shop_button]:
		nav.add_child(b)
	arsenal_button.pressed.connect(_on_arsenal)
	crafting_button.pressed.connect(func() -> void: _go_optional(crafting_button, MenuKit.CRAFTING_SCENE))
	merchant_button.pressed.connect(func() -> void: _go_optional(merchant_button, MenuKit.MERCHANT_SCENE))
	shop_button.pressed.connect(func() -> void: _go_shop(&""))
	progression_button.pressed.connect(func() -> void: _go_optional(progression_button, MenuKit.PROGRESSION_SCENE))
	crafting_button.set_soon(not scene_exists(MenuKit.CRAFTING_SCENE))
	merchant_button.set_soon(not scene_exists(MenuKit.MERCHANT_SCENE))

	# Bas gauche : carte du pass de combat
	pass_card = PassCard.new()
	pass_card.name = "PassCard"
	pass_card.anchor_top = 1.0
	pass_card.anchor_bottom = 1.0
	pass_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	pass_card.offset_left = m.x
	pass_card.offset_bottom = -m.w
	pass_card.offset_top = -m.w - pass_card.custom_minimum_size.y
	pass_card.offset_right = m.x + pass_card.custom_minimum_size.x
	pass_card.pressed.connect(func() -> void: _go_optional(pass_card, MenuKit.BATTLE_PASS_SCENE))
	ui.add_child(pass_card)

	# Dans le bandeau : carte en cours en haut (→ choix des cartes), DÉPLOYER puis Solo / Coop en bas
	var inner := VBoxContainer.new()
	inner.name = "SlabContent"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 16.0   # le bas du bandeau est pleine largeur : DÉPLOYER peut mordre sur le biais
	inner.offset_top = m.y + 10.0
	inner.offset_right = -maxf(m.z, 44.0)
	inner.offset_bottom = -maxf(m.w, 40.0)
	inner.add_theme_constant_override("separation", 14)
	sl.add_child(inner)
	map_link = _map_link()
	map_link.size_flags_horizontal = Control.SIZE_SHRINK_END
	inner.add_child(map_link)
	# Info ponctuelle (« Bientôt disponible ») : masquée hors message
	info_banner = InfoBanner.new()
	info_banner.name = "InfoBanner"
	info_banner.visible = false
	info_banner.custom_minimum_size.x = slab_w - sl.cut - maxf(m.z, 44.0)
	info_banner.text_label.custom_minimum_size.x = info_banner.custom_minimum_size.x - 54.0
	info_banner.add_theme_stylebox_override("panel", MenuKit.panel_style(Color(MenuKit.NIGHT_DEEP, 0.7), Color(0, 0, 0, 0), 0, 0, 10))
	info_banner.icon.modulate = Color(1, 1, 1)
	info_banner.title_label.add_theme_color_override("font_color", MenuKit.TEXT)
	inner.add_child(info_banner)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(spacer)
	play_button = PlayCard.new()
	play_button.name = "PlayButton"
	play_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	play_button.pressed.connect(_on_play)
	inner.add_child(play_button)
	var modes := HBoxContainer.new()
	modes.name = "Modes"
	modes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modes.alignment = BoxContainer.ALIGNMENT_END
	modes.add_theme_constant_override("separation", 10)
	inner.add_child(modes)
	modes.add_child(_solo_chip())
	coop_button = _coop_button(52.0)
	modes.add_child(coop_button)
	buttons = [play_button, coop_button, pass_card, progression_button, arsenal_button, crafting_button, merchant_button, shop_button]

	# Bas, centré : version + lien Crédits (discrets)
	var foot := HBoxContainer.new()
	foot.name = "Footer"
	foot.add_theme_constant_override("separation", 14)
	foot.anchor_left = 0.5
	foot.anchor_right = 0.5
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_bottom = -2
	ui.add_child(foot)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	_version = MenuKit.label("v" + (version if not version.is_empty() else "0.1"), 13,
		Color(1, 1, 1, 0.4), MenuKit.nunito(500))
	_version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_version)
	credits_button = Button.new()
	credits_button.name = "CreditsButton"
	credits_button.text = "Crédits"
	credits_button.flat = true
	credits_button.focus_mode = Control.FOCUS_ALL
	credits_button.custom_minimum_size = Vector2(0, 32)
	credits_button.add_theme_font_override("font", MenuKit.nunito(600))
	credits_button.add_theme_font_size_override("font_size", 13)
	for k: String in ["font_color", "font_focus_color"]:
		credits_button.add_theme_color_override(k, Color(1, 1, 1, 0.5))
	credits_button.add_theme_color_override("font_hover_color", MenuKit.TEXT)
	credits_button.pressed.connect(open_credits)
	foot.add_child(credits_button)
	credits_top_button = credits_button
	var cloud := HBoxContainer.new()
	cloud.name = "CloudStatus"
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cloud.add_theme_constant_override("separation", 6)
	foot.add_child(cloud)
	_cloud_dot = ColorRect.new()
	_cloud_dot.custom_minimum_size = Vector2(8, 8)
	_cloud_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cloud_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cloud.add_child(_cloud_dot)
	cloud_label = MenuKit.label("", 13, Color(1, 1, 1, 0.4), MenuKit.nunito(500))
	cloud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cloud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cloud.add_child(cloud_label)


## Décor fixe de la maquette : repères d'angle violets à gauche + trame de lignes horizontales.
class LobbyDeco extends Control:
	## Couleur des repères d'angle (rose sur l'écran de mort).
	var accent: Color = MenuKit.VIOLET

	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		for y: int in range(0, int(size.y), 3):
			draw_line(Vector2(0, y + 0.5), Vector2(size.x, y + 0.5), Color(1, 1, 1, 0.03), 1.0)
		var k := 33.0
		var x := 30.0
		var c := accent
		draw_polyline(PackedVector2Array([Vector2(x, 20 + k), Vector2(x, 20), Vector2(x + k, 20)]), c, 3.0)
		var by := size.y - 20.0
		draw_polyline(PackedVector2Array([Vector2(x, by - k), Vector2(x, by), Vector2(x + k, by)]), c, 3.0)


## Niveau de raider : carré violet à coins coupés (chiffre en Anton) + « Niveau » ; tap → Progression.
func _level_badge() -> Button:
	var b := Button.new()
	b.name = "LevelBadge"
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Niveau de raider"
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for k: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	b.add_child(row)
	var sq := PanelContainer.new()
	sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := CutBox.make(MenuKit.VIOLET, 12.0, Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
	box.corners = CutBox.CUT_TOP_LEFT | CutBox.CUT_BOTTOM_RIGHT
	sq.add_theme_stylebox_override("panel", box)
	sq.custom_minimum_size = Vector2(54, 54)
	row.add_child(sq)
	var v := MenuKit.label("1", 28, MenuKit.TEXT, MenuKit.display(), 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sq.add_child(v)
	stat_values[&"level"] = v
	var cap := MenuKit.label("Niveau", 24, MenuKit.TEXT, MenuKit.nunito(700))
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	b.custom_minimum_size = Vector2(54 + 12 + cap.get_minimum_size().x, 54)
	b.pressed.connect(func() -> void: _go_optional(b, MenuKit.PROGRESSION_SCENE))
	MenuKit.add_feedback(b, 1.04)
	return b


## Haut du bandeau : carte en cours (capitales espacées) ; tap → choix des cartes. La ligne
## « difficulté · changer » est masquée (retour de Victor : elle encombrait le coin).
func _map_link() -> Button:
	var b := Button.new()
	b.name = "MapLink"
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Changer de carte"
	for k: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	map_name_label = MenuKit.label("", 18, MenuKit.TEXT, MenuKit.nunito(600), 0)
	map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	map_name_label.uppercase = true
	map_name_label.add_theme_constant_override("outline_size", 0)
	col.add_child(map_name_label)
	map_sub_label = MenuKit.label("", 18, Color(1, 1, 1, 0.75), MenuKit.nunito(600), 0)
	map_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	map_sub_label.uppercase = true
	map_sub_label.visible = false
	col.add_child(map_sub_label)
	b.pressed.connect(_on_play)
	MenuKit.add_feedback(b, 1.03)
	return b


## Mode en cours (Solo) : pastille encre pleine à coin coupé, à gauche de Coop.
func _solo_chip() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "SoloChip"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := CutBox.make(MenuKit.NIGHT_DEEP, 13.0, Color(0, 0, 0, 0), 0.0, 18.0, 0.0)
	box.corners = CutBox.CUT_TOP_LEFT
	p.add_theme_stylebox_override("panel", box)
	p.custom_minimum_size = Vector2(0, 52)
	var l := MenuKit.label("Solo", 18, MenuKit.TEXT, MenuKit.nunito(600), 0)
	l.uppercase = true
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Statistique du profil : gros chiffre (Anton) + libellé discret en minuscules.
func _stat_chip(key: StringName, _glyph: StringName, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 7)
	var v := MenuKit.label("0", 30, MenuKit.GOLD if key == &"rate" else MenuKit.TEXT, MenuKit.display(), 0)
	row.add_child(v)
	var c := MenuKit.label(caption, 18, Color(1, 1, 1, 0.6), MenuKit.nunito(600), 0)
	c.size_flags_vertical = Control.SIZE_SHRINK_END
	c.offset_bottom = -3
	row.add_child(c)
	stat_values[key] = v
	return row


## Bouton « Coop » (sous DÉPLOYER, à droite de Solo) : contour blanc à coin coupé, libellé en
## capitales ; « Bientôt » (atténué) si la scène manque.
func _coop_button(h: float) -> Button:
	var b := Button.new()
	b.name = "CoopButton"
	b.text = "COOP"
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Jouer en coopération"
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_override("font", MenuKit.nunito(600))
	b.add_theme_font_size_override("font_size", 18)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, MenuKit.TEXT)
	var mk := func(bg: Color) -> CutBox:
		var c := CutBox.make(bg, 13.0, Color(1, 1, 1, 0.95), 2.0, 18.0, 0.0)
		c.corners = CutBox.CUT_TOP_LEFT
		return c
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.TEXT
	f.border_width = 2.0
	f.cut = 15.0
	f.corners = CutBox.CUT_TOP_LEFT
	f.grow = 4.0
	b.add_theme_stylebox_override("normal", mk.call(Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", mk.call(Color(1, 1, 1, 0.14)))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0, 0, 0, 0.25)))
	b.add_theme_stylebox_override("hover_pressed", mk.call(Color(0, 0, 0, 0.25)))
	b.add_theme_stylebox_override("focus", f)
	var soon := not scene_exists(MenuKit.COOP_SCENE)
	b.set_meta(&"soon", soon)
	if soon:
		b.modulate.a = 0.6
	b.pressed.connect(func() -> void: _go_optional(b, MenuKit.COOP_SCENE))
	MenuKit.add_feedback(b, 1.05)
	return b


## Or : pastille encre soulignée de la couleur de la pièce (maquette : Space Grotesk gras).
func _gold_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.tooltip_text = "Or : vends ton butin au marchand"
	p.add_theme_stylebox_override("panel", MenuKit.currency_style(MenuKit.COIN, 16))
	p.custom_minimum_size = Vector2(0, 66)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	var g := MenuGlyph.new(&"coin", MenuKit.COIN, 30)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	gold_label = MenuKit.label("0", 25, MenuKit.TEXT, MenuKit.nunito(700), 0)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(gold_label)
	dollar_label = gold_label
	return p


## Gemmes : même pastille soulignée cyan, compteur (tap → onglet Gemmes) + bouton « + » violet.
func _gem_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "GemPill"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.add_theme_stylebox_override("panel", MenuKit.currency_style(MenuKit.GEM, 6))
	p.custom_minimum_size = Vector2(0, 66)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	gem_counter = GemCounter.new(25)
	gem_counter.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	gem_counter.value_label.add_theme_font_override("font", MenuKit.nunito(700))
	gem_counter.value_label.add_theme_constant_override("outline_size", 0)
	gem_counter.custom_minimum_size = Vector2.ZERO
	gem_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_counter.pressed.connect(func() -> void: _go_shop(&"gems"))
	row.add_child(gem_counter)
	gem_plus = _round_button(&"plus", MenuKit.VIOLET, 52)
	gem_plus.tooltip_text = "Acheter des gemmes"
	gem_plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_plus.pressed.connect(func() -> void: _go_shop(&"gems"))
	row.add_child(gem_plus)
	return p


## Petit bouton carré à coins coupés avec pictogramme (réglages, crédits, +).
func _round_button(glyph: StringName, bg: Color, px: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(px, px)
	var edge := Color(1, 1, 1, 0.35) if bg.a < 0.9 else Color(0, 0, 0, 0)
	var n := CutBox.make(bg, px * 0.22, edge, 1.0, 0.0, 0.0)
	var h := CutBox.make(bg.lightened(0.15), px * 0.22, edge, 1.0, 0.0, 0.0)
	var pr := CutBox.make(bg.darkened(0.2), px * 0.22, edge, 1.0, 0.0, 0.0)
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.GOLD
	f.border_width = 2.0
	f.cut = px * 0.22
	f.grow = 3.0
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("focus", f)
	var g := MenuGlyph.new(glyph, MenuKit.TEXT, px * 0.56)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	g.offset_left = px * 0.22
	g.offset_top = px * 0.22
	g.offset_right = -px * 0.22
	g.offset_bottom = -px * 0.22
	b.add_child(g)
	MenuKit.add_feedback(b, 1.08)
	return b


# --- Données ------------------------------------------------------------------------

func _refresh_profile() -> void:
	var st: Dictionary = Profile.stats
	var raids: int = int(st.get("raids", 0))
	var ext: int = int(st.get("extractions", 0))
	(stat_values[&"level"] as Label).text = str(Profile.raider_level())
	(stat_values[&"raids"] as Label).text = str(raids)
	(stat_values[&"extractions"] as Label).text = str(ext)
	(stat_values[&"rate"] as Label).text = ("%d %%" % roundi(100.0 * ext / raids)) if raids > 0 else "–"
	gold_label.text = DevMode.SYMBOL if DevMode.is_unlimited() else format_thousands(gold_amount())
	var card := PlayCard.displayed_card()
	map_name_label.text = card.display_name if card != null else "Choisir une carte"
	map_sub_label.text = ("%s · Changer ›" % card.difficulty_name()) if card != null else "Changer ›"
	map_link.custom_minimum_size = map_name_label.get_minimum_size()


func _connect_cloud() -> void:
	var cs: Node = get_node_or_null(^"/root/CloudSync")
	if cs == null:
		_refresh_cloud(&"disabled")
		return
	cs.connect(&"status_changed", _refresh_cloud)
	cs.connect(&"conflict_detected", _on_cloud_conflict)
	_refresh_cloud(cs.get("status"))
	# Conflit détecté avant l'arrivée sur le menu (ex. pendant le splash) : on le présente maintenant.
	if bool(cs.call("has_conflict")):
		var r: Dictionary = cs.get("pending_remote")
		_on_cloud_conflict(_describe_local_save(cs), _describe_remote_save(cs, r))


static func _describe_local_save(cs: Node) -> Dictionary:
	var sm: Node = cs.get_node_or_null(^"/root/SaveManager")
	var data: Dictionary = (sm.get("data") as Dictionary) if sm != null else {}
	return cs.call("describe_save", cs.call("payload_of", data))


static func _describe_remote_save(cs: Node, r: Dictionary) -> Dictionary:
	return cs.call("describe_save", r.get("save", {}), str(r.get("updated_at", "")), str(r.get("device", "")))


func _refresh_cloud(status: StringName) -> void:
	if cloud_label == null:
		return
	var cs: Node = get_node_or_null(^"/root/CloudSync")
	cloud_label.get_parent().visible = status != &"disabled"
	cloud_label.text = str(cs.call("status_label", status)) if cs != null else ""
	var c := Color(1, 1, 1, 0.35)
	match status:
		&"synced":
			c = Color(0.45, 0.9, 0.55)
		&"syncing":
			c = MenuKit.GOLD
		&"conflict":
			c = Color(1.0, 0.55, 0.25)
	_cloud_dot.color = c


func _on_cloud_conflict(local_info: Dictionary, remote_info: Dictionary) -> void:
	if is_instance_valid(_modal) and _modal is CloudConflictPanel:
		return
	_open_modal(CloudConflictPanel.new(local_info, remote_info), play_button)


## Or du joueur : Profile.gold (économie), sinon l'ancien compteur Profile.dollars.
static func gold_amount() -> int:
	return int(Profile.get("gold")) if &"gold" in Profile else int(Profile.dollars)


## La scène existe-t-elle ? (écrans livrés en parallèle par d'autres modules)
static func scene_exists(path: String) -> bool:
	return ResourceLoader.exists(path)


## « 12 345 » (espace fine insécable entre les milliers).
static func format_thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# --- Animations ---------------------------------------------------------------------

func _intro() -> void:
	# Chaque bloc glisse depuis son bord, en cascade ; le héros apparaît avec le zoom du décor.
	var blocks: Array = [[_top, Vector2(0, -90), 0.15], [_nav, Vector2(-340, 0), 0.3],
		[slab, Vector2(460, 0), 0.25], [pass_card, Vector2(0, 160), 0.45]]
	# On anime les décalages (offsets) et non la position : un bloc ancré à droite ou en bas
	# reste collé à son bord même si l'écran change de taille pendant l'animation.
	for b: Array in blocks:
		var c: Control = b[0]
		var d: Vector2 = b[1]
		for side: String in ["offset_left", "offset_right"]:
			var f: float = c.get(side)
			c.set(side, f + d.x)
			c.create_tween().tween_property(c, side, f, 0.55).set_delay(b[2]) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		for side: String in ["offset_top", "offset_bottom"]:
			var f: float = c.get(side)
			c.set(side, f + d.y)
			c.create_tween().tween_property(c, side, f, 0.55).set_delay(b[2]) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		c.modulate.a = 0.0
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.35).set_delay(b[2])
	if hero != null:
		hero.modulate.a = 0.0
		hero.create_tween().tween_property(hero, "modulate:a", 1.0, 0.6).set_delay(0.2)
	if mate_slot != null:
		mate_slot.modulate.a = 0.0
		mate_slot.create_tween().tween_property(mate_slot, "modulate:a", 1.0, 0.6).set_delay(0.35)


# --- Navigation ---------------------------------------------------------------------

func _on_play() -> void:
	MenuKit.sfx(&"confirm")
	# Dans un salon coop : DÉPLOYER ramène au salon (raid à deux), jamais en solo par erreur.
	MenuKit.go_to(self, MenuKit.COOP_SCENE if in_coop_room() else MenuKit.MAP_SELECT_SCENE)


## Un salon coop est ouvert (retour au menu sans le quitter) ?
static func in_coop_room() -> bool:
	var s := NetSession.current()
	return s != null and s.in_room()


func _on_arsenal() -> void:
	MenuKit.sfx(&"click")
	MenuKit.go_to(self, MenuKit.ARSENAL_SCENE)


## Écran d'un autre module : « Bientôt » (message) tant que la scène n'existe pas.
func _go_optional(b: Control, path: String) -> void:
	if not scene_exists(path):
		MenuKit.sfx(&"error")
		if b != null:
			b.pivot_offset = b.size * 0.5
			var tw := b.create_tween()
			tw.tween_property(b, "rotation", 0.05, 0.05)
			tw.tween_property(b, "rotation", -0.05, 0.08)
			tw.tween_property(b, "rotation", 0.0, 0.05)
		if info_banner != null:
			info_banner.visible = true
			info_banner.show_message("Bientôt disponible")
			get_tree().create_timer(2.5).timeout.connect(func() -> void:
				if is_instance_valid(info_banner):
					info_banner.visible = false)
		return
	MenuKit.sfx(&"click")
	MenuKit.go_to(self, path)


func _go_shop(tab: StringName) -> void:
	MenuKit.sfx(&"click")
	if tab != &"":
		ShopScreen.last_tab = tab
	MenuKit.go_to(self, MenuKit.SHOP_SCENE)


func open_options() -> ModalPanel:
	MenuKit.sfx(&"click")
	return _open_modal(OptionsPanel.new(), options_button)


func open_credits() -> ModalPanel:
	MenuKit.sfx(&"click")
	return _open_modal(CreditsPanel.new(), credits_button)


func _open_modal(m: ModalPanel, return_focus: Control) -> ModalPanel:
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = m
	add_child(m)
	m.closed.connect(func() -> void:
		if is_instance_valid(return_focus):
			return_focus.grab_focus())
	return m


# --- Coéquipier (coop) ----------------------------------------------------------------

## Emplacement posé dans le décor (repère de l'image : suit le zoom et le cadrage du lobby).
func _build_mate_slot() -> void:
	if lobby == null or lobby.hero == null:
		return
	var feet: Vector2 = lobby.mate_feet()
	var h: float = lobby.mate_height()
	var w: float = h * 0.5
	var slot := Control.new()
	slot.name = "MateSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.position = feet - Vector2(w * 0.5, h)
	slot.size = Vector2(w, h)
	lobby.add_overlay_control(slot)
	mate_slot = slot
	# Gros « + » encre à bordure violette, à hauteur de poitrine (cible tactile ~110 px à l'écran).
	var px: float = Balance.get_float("menu", "lobby_mate_plus_size", 150.0)
	var b := Button.new()
	b.name = "MatePlus"
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Jouer en coop"
	b.custom_minimum_size = Vector2(px, px)
	b.size = Vector2(px, px)
	b.position = Vector2((w - px) * 0.5, h * 0.42 - px * 0.5)
	b.add_theme_stylebox_override("normal", CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.72), px * 0.2, MenuKit.VIOLET, 3.0, 0.0, 0.0))
	b.add_theme_stylebox_override("hover", CutBox.make(Color(MenuKit.VIOLET, 0.55), px * 0.2, MenuKit.GOLD, 3.0, 0.0, 0.0))
	b.add_theme_stylebox_override("pressed", CutBox.make(Color(MenuKit.VIOLET, 0.8), px * 0.2, MenuKit.GOLD, 3.0, 0.0, 0.0))
	b.add_theme_stylebox_override("hover_pressed", CutBox.make(Color(MenuKit.VIOLET, 0.8), px * 0.2, MenuKit.GOLD, 3.0, 0.0, 0.0))
	var f := CutBox.make(Color(0, 0, 0, 0), px * 0.2, MenuKit.TEXT, 3.0, 0.0, 0.0)
	f.grow = 4.0
	b.add_theme_stylebox_override("focus", f)
	var g := MenuGlyph.new(&"plus", MenuKit.TEXT, px * 0.5)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["offset_left", "offset_top"]:
		g.set(side, px * 0.25)
	for side: String in ["offset_right", "offset_bottom"]:
		g.set(side, -px * 0.25)
	b.add_child(g)
	b.pressed.connect(_on_mate_pressed)
	MenuKit.add_feedback(b, 1.06)
	slot.add_child(b)
	mate_plus = b
	var cap := MenuKit.label("Coéquipier", 30, MenuKit.TEXT, MenuKit.display(), 0)
	cap.name = "MateCaption"
	cap.uppercase = true
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_shadow_color", Color(0, 0, 0.03, 0.8))
	cap.add_theme_constant_override("shadow_offset_y", 3)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.position = Vector2(-w * 0.5, b.position.y + px + 10.0)
	cap.size = Vector2(w * 2.0, 40)
	slot.add_child(cap)
	_mate_caption = cap
	# Coéquipier présent : pseudo + état au-dessus de sa tête ; toute la silhouette est cliquable.
	var hit := Button.new()
	hit.name = "MateHit"
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.tooltip_text = "Salon coop"
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for k: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		hit.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(_on_mate_pressed)
	hit.visible = false
	slot.add_child(hit)
	var tag_box := VBoxContainer.new()
	tag_box.name = "MateTag"
	tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_theme_constant_override("separation", 2)
	tag_box.position = Vector2(-w * 0.5, -h * 0.02)
	tag_box.size = Vector2(w * 2.0, 70)
	slot.add_child(tag_box)
	var tag_panel := PanelContainer.new()
	tag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tb := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.82), 12.0, Color(0, 0, 0, 0), 0.0, 16.0, 4.0)
	tb.accent_width = 5.0
	tb.accent_color = MenuKit.VIOLET
	tag_panel.add_theme_stylebox_override("panel", tb)
	tag_box.add_child(tag_panel)
	mate_tag = MenuKit.label("", 30, MenuKit.TEXT, MenuKit.display(), 0)
	mate_tag.uppercase = true
	tag_panel.add_child(mate_tag)
	mate_status = MenuKit.label("", 22, Color(1, 1, 1, 0.8), MenuKit.nunito(700), 0)
	mate_status.uppercase = true
	mate_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mate_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0.03, 0.85))
	mate_status.add_theme_constant_override("shadow_offset_y", 2)
	tag_box.add_child(mate_status)
	_refresh_mate()


func _on_mate_pressed() -> void:
	_go_optional(mate_plus, MenuKit.COOP_SCENE)


## État du coéquipier : « + » seul, salon sans coéquipier, ou coéquipier affiché.
func _refresh_mate() -> void:
	if mate_slot == null:
		return
	var s := NetSession.current()
	var room := s != null and s.in_room()
	var has_mate := room and s.peer_present
	var hit := mate_slot.get_node("MateHit") as Control
	var tag := mate_slot.get_node("MateTag") as Control
	mate_plus.visible = not has_mate
	_mate_caption.visible = not has_mate
	hit.visible = has_mate
	tag.visible = has_mate
	if room and not has_mate:
		_mate_caption.text = "Salon %s" % LobbyCode.pretty(s.room_code)
	else:
		_mate_caption.text = "Coéquipier"
	if not has_mate:
		lobby.set_mate(null, false)
		return
	var info: Dictionary = s.peer_info
	var skin := SkinData.get_skin(StringName(String(info.get("skin", ""))))
	lobby.set_mate(skin, true)
	var nm := String(info.get("name", s.peer_name))
	mate_tag.text = nm if nm != "" else "Coéquipier"
	mate_status.text = CoopLobby.status_text(info, s.peer_connected, s.peer_where())


## La session réseau survit aux écrans : nos connexions sont retirées en sortant (_exit_tree).
func _connect_session() -> void:
	var s := NetSession.current()
	if s == null:
		return
	for sig: Signal in [s.peer_joined, s.peer_left, s.room_closed, s.lobby_message, s.peer_lost]:
		sig.connect(_on_session_event.unbind(1))
	s.peer_back.connect(_on_session_event)
	s.status_changed.connect(_on_session_event.unbind(1))


func _on_session_event() -> void:
	_refresh_mate.call_deferred()


func _exit_tree() -> void:
	var s := NetSession.current()
	if s == null:
		return
	for sig: Dictionary in s.get_signal_list():
		var sname := StringName(sig["name"])
		for c: Dictionary in s.get_signal_connection_list(sname):
			var cb: Callable = c["callable"]
			if cb.get_object() == self:
				s.disconnect(sname, cb)


## Libellé lisible d'un bouton du menu (les boutons dessinés n'ont pas de `text`).
static func button_label(b: Button) -> String:
	if b is NavButton:
		return (b as NavButton).caption.text
	if b is PassCard:
		return "Pass"
	if b.name == "CoopButton":
		return "Coop"
	if b is PlayCard:
		return (b as PlayCard).title_label.text
	return b.text


func _unhandled_input(event: InputEvent) -> void:
	# Aucun bouton focalisé (clic dans le vide) : la manette/le clavier reprend sur « Jouer ».
	if is_instance_valid(_modal):
		return
	if (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")
			or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right")) \
			and get_viewport().gui_get_focus_owner() == null:
		play_button.grab_focus()
		get_viewport().set_input_as_handled()
