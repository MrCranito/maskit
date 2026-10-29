class_name MainMenu
extends Control
## Menu principal de RaidersGo, direction « D » :
##  - fond vivant : camp de base à la lisière de Dust Creek au coucher du soleil (LobbyScene,
##    rendu Blender en couches + drapeau, feu, fumée, poussière, parallaxe lent) et le héros
##    avec son skin porté (LobbyHero ; tap = Personnages) ; voile sombre à gauche pour la lisibilité ;
##  - barre du haut : logo et statistiques (gros chiffres), or, gemmes (+ → onglet Gemmes),
##    boutons Crédits et Réglages ; elle s'arrête avant le bandeau ;
##  - gauche : menu texte en Anton (Arsenal, Inventaire, Atelier, Boutique) ; un écran pas
##    encore livré (scène absente) affiche « Bientôt » sans rien ouvrir ;
##  - bas gauche : carte du pass de combat (PassCard → écran du pass) ;
##  - droite : bandeau violet translucide en biais, pleine hauteur : info du jour (InfoBanner)
##    en haut, bouton Coop puis « DÉPLOYER » (PlayCard → choix des cartes → arsenal de départ → raid).
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
	Profile.changed.connect(_refresh_profile)
	_refresh_profile()
	MenuKit.fade_in(self, 0.45)
	lobby.play_intro()
	_intro.call_deferred()
	play_button.grab_focus.call_deferred()


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

	# Barre du haut (s'arrête avant le bandeau) : logo, statistiques, or, gemmes, crédits, réglages
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 10)
	top.anchor_right = 1.0
	top.offset_left = m.x
	top.offset_top = m.y
	top.offset_right = -slab_w - 12.0
	top.custom_minimum_size.y = 62
	ui.add_child(top)
	_top = top
	var brand := VBoxContainer.new()
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_theme_constant_override("separation", 2)
	top.add_child(brand)
	logo = RaidersLogo.new(int(Balance.get_value("menu", "lobby_logo_size", 32)))
	brand.add_child(logo)
	var stats := HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 16)
	brand.add_child(stats)
	stats.add_child(_stat_chip(&"level", &"star", "niveau"))
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
	var gems := HBoxContainer.new()
	gems.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gems.add_theme_constant_override("separation", -10)
	gems.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(gems)
	gem_counter = GemCounter.new(22)
	gem_counter.pressed.connect(func() -> void: _go_shop(&"gems"))
	gems.add_child(gem_counter)
	gem_plus = _round_button(&"plus", MenuKit.VIOLET, 40)
	gem_plus.tooltip_text = "Acheter des gemmes"
	gem_plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_plus.pressed.connect(func() -> void: _go_shop(&"gems"))
	gems.add_child(gem_plus)
	credits_top_button = _round_button(&"star", Color(MenuKit.NIGHT_DEEP, 0.75), 46)
	credits_top_button.tooltip_text = "Crédits"
	credits_top_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	credits_top_button.pressed.connect(open_credits)
	top.add_child(credits_top_button)
	gear_button = _round_button(&"gear", Color(MenuKit.NIGHT_DEEP, 0.75), 50)
	gear_button.tooltip_text = "Réglages"
	gear_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	gear_button.pressed.connect(open_options)
	top.add_child(gear_button)
	options_button = gear_button
	credits_button = credits_top_button

	# Gauche : menu texte (l'arsenal de départ se choisit à l'étape 2, plus de résumé ici)
	var nav := VBoxContainer.new()
	nav.name = "NavBar"
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_theme_constant_override("separation", 0)
	ui.add_child(nav)
	nav.position = Vector2(m.x - 6.0, m.y + top.get_combined_minimum_size().y + 14.0)
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

	# Dans le bandeau : info du jour en haut, Coop + DÉPLOYER en bas (alignés à droite)
	var inner := VBoxContainer.new()
	inner.name = "SlabContent"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = sl.cut * 0.75
	inner.offset_top = m.y
	inner.offset_right = -m.z
	inner.offset_bottom = -m.w
	inner.add_theme_constant_override("separation", 8)
	sl.add_child(inner)
	info_banner = InfoBanner.new()
	info_banner.name = "InfoBanner"
	info_banner.custom_minimum_size.x = slab_w - sl.cut * 0.75 - m.z
	info_banner.text_label.custom_minimum_size.x = info_banner.custom_minimum_size.x - 54.0
	info_banner.add_theme_stylebox_override("panel", MenuKit.panel_style(Color(MenuKit.NIGHT_DEEP, 0.55), Color(0, 0, 0, 0), 0, 0, 10))
	info_banner.icon.modulate = Color(1, 1, 1)
	info_banner.title_label.add_theme_color_override("font_color", MenuKit.TEXT)
	inner.add_child(info_banner)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(spacer)
	var act := HBoxContainer.new()
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	act.alignment = BoxContainer.ALIGNMENT_END
	act.add_theme_constant_override("separation", 10)
	inner.add_child(act)
	coop_button = _coop_button(64.0)
	coop_button.size_flags_vertical = Control.SIZE_SHRINK_END
	act.add_child(coop_button)
	play_button = PlayCard.new()
	play_button.name = "PlayButton"
	play_button.pressed.connect(_on_play)
	act.add_child(play_button)
	buttons = [play_button, coop_button, pass_card, progression_button, arsenal_button, crafting_button, merchant_button, shop_button]

	# Version (discrète, centrée en bas)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	_version = MenuKit.label("v" + (version if not version.is_empty() else "0.1"), 12,
		Color(MenuKit.TEXT_DIM, 0.45), MenuKit.nunito(500))
	_version.anchor_left = 0.5
	_version.anchor_right = 0.5
	_version.anchor_top = 1.0
	_version.anchor_bottom = 1.0
	_version.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.offset_bottom = -4
	ui.add_child(_version)


## Statistique du profil : gros chiffre (Anton) + libellé discret en minuscules.
func _stat_chip(key: StringName, _glyph: StringName, caption: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 5)
	var v := MenuKit.label("0", 20, MenuKit.GOLD if key == &"rate" or key == &"level" else MenuKit.TEXT, MenuKit.display())
	row.add_child(v)
	var c := MenuKit.label(caption, 12, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	c.size_flags_vertical = Control.SIZE_SHRINK_END
	c.offset_bottom = -3
	row.add_child(c)
	stat_values[key] = v
	return row


## Bouton « Coop » (à gauche de DÉPLOYER, dans le bandeau) : contour blanc à coins coupés,
## pictogramme duo + libellé ; « Bientôt » si la scène manque.
func _coop_button(h: float) -> Button:
	var b := Button.new()
	b.name = "CoopButton"
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Jouer en coopération"
	b.custom_minimum_size = Vector2(h, h)
	var n := CutBox.make(Color(0, 0, 0, 0), 10.0, Color(1, 1, 1, 0.9), 2.0, 0.0, 0.0)
	var hv := CutBox.make(Color(1, 1, 1, 0.12), 10.0, Color(1, 1, 1, 1.0), 2.0, 0.0, 0.0)
	var pr := CutBox.make(Color(0, 0, 0, 0.25), 10.0, Color(1, 1, 1, 0.9), 2.0, 0.0, 0.0)
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.TEXT
	f.border_width = 2.0
	f.cut = 12.0
	f.grow = 4.0
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("focus", f)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(col)
	var g := PassGlyph.new(&"duo", MenuKit.TEXT, 30)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(g)
	var l := MenuKit.label("COOP", 15, MenuKit.TEXT, MenuKit.display())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	var soon := not scene_exists(MenuKit.COOP_SCENE)
	b.set_meta(&"soon", soon)
	if soon:
		g.modulate.a = 0.45
		l.modulate.a = 0.6
	b.pressed.connect(func() -> void: _go_optional(b, MenuKit.COOP_SCENE))
	MenuKit.add_feedback(b, 1.05)
	return b


## Or : pastille encre soulignée de la couleur de la pièce.
func _gold_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.tooltip_text = "Or : vends ton butin au marchand"
	var s := MenuKit.panel_style(Color(MenuKit.NIGHT_DEEP, 0.82), Color(0, 0, 0, 0), 0, 0, 0)
	s.border_color = MenuKit.COIN
	s.border_width_bottom = 3
	s.content_margin_left = 10
	s.content_margin_right = 16
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_size = 0
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(0, 50)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	var g := MenuGlyph.new(&"coin", MenuKit.COIN, 28)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	gold_label = MenuKit.label("0", 22, MenuKit.TEXT, MenuKit.display())
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(gold_label)
	dollar_label = gold_label
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
	gold_label.text = format_thousands(gold_amount())


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


# --- Navigation ---------------------------------------------------------------------

func _on_play() -> void:
	MenuKit.sfx(&"confirm")
	MenuKit.go_to(self, MenuKit.MAP_SELECT_SCENE)


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
		if info_banner != null and info_banner.has_method("show_message"):
			info_banner.call("show_message", "Bientôt disponible")
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
