class_name MainMenu
extends Control
## Menu principal de RaidersGo, façon lobby de jeu d'action mobile :
##  - fond vivant : camp de base à la lisière de Dust Creek au coucher du soleil (LobbyScene,
##    rendu Blender en couches + drapeau, feu, fumée, poussière, parallaxe lent) et le héros
##    avec son skin porté (LobbyHero ; tap = Personnages) ;
##  - barre du haut : logo, statistiques (raids, extractions, taux), or (pièces), gemmes (+ → onglet
##    Gemmes), boutons Crédits et Réglages ;
##  - gauche, sous la barre du haut : résumé de l'arsenal de départ (LoadoutSummary → arsenal) ;
##  - droite, au-dessus de JOUER : bandeau d'info (événement, rotation, astuces) ;
##  - gauche, sous l'arsenal : carte du pass de combat (PassCard → écran du pass) ;
##  - bas gauche : barre de navigation (Arsenal, Atelier, Inventaire, Boutique) ; un écran
##    pas encore livré (scène absente) affiche « Bientôt » sans rien ouvrir ;
##  - bas droite : bouton « Coop » puis grand bouton « JOUER » ambre (PlayCard → choix
##    des cartes → arsenal de départ → raid).
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
var loadout_summary: LoadoutSummary = null
var info_banner: InfoBanner = null
var play_button: PlayCard = null
var arsenal_button: NavButton = null
var crafting_button: NavButton = null
var merchant_button: NavButton = null
var shop_button: NavButton = null
## Carte du pass de combat (colonne de gauche). L'entrée « Pass » de la barre de navigation est
## retirée : la carte, plus visible, la remplace (moins d'entrées = barre plus lisible).
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
var _left: VBoxContainer = null
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

func _build() -> void:
	var m: Vector4 = MenuKit.safe_margins(self)
	var gap: float = 14.0

	# Barre du haut
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 12)
	top.anchor_right = 1.0
	top.offset_left = m.x
	top.offset_top = m.y
	top.offset_right = -m.z
	top.custom_minimum_size.y = 62
	ui.add_child(top)
	_top = top
	logo = RaidersLogo.new(int(Balance.get_value("menu", "lobby_logo_size", 32)))
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(logo)
	var stats := HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_theme_constant_override("separation", 6)
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(stats)
	stats.add_child(_stat_chip(&"raids", &"target", "Raids"))
	stats.add_child(_stat_chip(&"extractions", &"exit", "Extractions"))
	stats.add_child(_stat_chip(&"rate", &"percent", "Réussite"))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(fill)
	top.add_child(_gold_pill())
	var gems := HBoxContainer.new()
	gems.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gems.add_theme_constant_override("separation", -10)
	gems.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(gems)
	gem_counter = GemCounter.new(22)
	gem_counter.pressed.connect(func() -> void: _go_shop(&"gems"))
	gems.add_child(gem_counter)
	gem_plus = _round_button(&"plus", MenuKit.GEM.darkened(0.45), 40)
	gem_plus.tooltip_text = "Acheter des gemmes"
	gem_plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_plus.pressed.connect(func() -> void: _go_shop(&"gems"))
	gems.add_child(gem_plus)
	credits_top_button = _round_button(&"star", Color(MenuKit.NIGHT, 0.9), 46)
	credits_top_button.tooltip_text = "Crédits"
	credits_top_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	credits_top_button.pressed.connect(open_credits)
	top.add_child(credits_top_button)
	gear_button = _round_button(&"gear", Color(MenuKit.NIGHT, 0.9), 54)
	gear_button.tooltip_text = "Réglages"
	gear_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear_button.pressed.connect(open_options)
	top.add_child(gear_button)
	options_button = gear_button
	credits_button = credits_top_button

	# Gauche : arsenal de départ
	# Gauche : arsenal de départ (compact) puis carte du pass de combat, en colonne
	_left = VBoxContainer.new()
	_left.name = "LeftColumn"
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_theme_constant_override("separation", 12)
	# un peu plus bas que la barre du haut, pour qu'il respire ([menu] loadout_panel_drop)
	_left.position = Vector2(m.x, m.y + 62 + gap + Balance.get_float("menu", "loadout_panel_drop", 22.0))
	ui.add_child(_left)
	loadout_summary = LoadoutSummary.new()
	loadout_summary.name = "LoadoutSummary"
	loadout_summary.pressed.connect(_on_arsenal)
	_left.add_child(loadout_summary)
	pass_card = PassCard.new()
	pass_card.name = "PassCard"
	pass_card.pressed.connect(func() -> void: _go_optional(pass_card, MenuKit.BATTLE_PASS_SCENE))
	_left.add_child(pass_card)

	# Droite, au-dessus de JOUER : bandeau d'information (le haut droit reste au drapeau du camp)
	info_banner = InfoBanner.new()
	info_banner.name = "InfoBanner"
	info_banner.anchor_left = 1.0
	info_banner.anchor_right = 1.0
	info_banner.anchor_top = 1.0
	info_banner.anchor_bottom = 1.0
	info_banner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var play_h: float = 124.0
	info_banner.offset_right = -m.z
	var play_w: float = 340.0 + 12.0 + Balance.get_float("menu", "coop_button_width", 112.0)
	info_banner.offset_left = -m.z - play_w
	info_banner.offset_bottom = -m.w - play_h - 12.0
	info_banner.offset_top = info_banner.offset_bottom - info_banner.custom_minimum_size.y
	ui.add_child(info_banner)

	# Bas droite : JOUER
	play_button = PlayCard.new()
	play_button.name = "PlayButton"
	play_button.anchor_left = 1.0
	play_button.anchor_top = 1.0
	play_button.anchor_right = 1.0
	play_button.anchor_bottom = 1.0
	play_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	play_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	play_button.offset_right = -m.z
	play_button.offset_bottom = -m.w
	play_button.offset_left = -m.z - play_button.custom_minimum_size.x
	play_button.offset_top = -m.w - play_button.custom_minimum_size.y
	play_button.pressed.connect(_on_play)
	ui.add_child(play_button)

	# Bas droite, à gauche de JOUER : Coop (scène de l'agent Coop ; « Bientôt » si absente)
	coop_button = _coop_button(play_button.custom_minimum_size.y)
	coop_button.anchor_left = 1.0
	coop_button.anchor_top = 1.0
	coop_button.anchor_right = 1.0
	coop_button.anchor_bottom = 1.0
	coop_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	coop_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	coop_button.offset_right = play_button.offset_left - 12.0
	coop_button.offset_left = coop_button.offset_right - coop_button.custom_minimum_size.x
	coop_button.offset_bottom = -m.w
	coop_button.offset_top = -m.w - coop_button.custom_minimum_size.y
	ui.add_child(coop_button)

	# Bas gauche : navigation
	var nav := PanelContainer.new()
	nav.name = "NavBar"
	var ns := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.82), MenuKit.BORDER, 20, 1, 6)
	nav.add_theme_stylebox_override("panel", ns)
	nav.anchor_top = 1.0
	nav.anchor_bottom = 1.0
	nav.grow_vertical = Control.GROW_DIRECTION_BEGIN
	nav.offset_left = m.x
	nav.offset_bottom = -m.w
	ui.add_child(nav)
	_nav = nav
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	nav.add_child(row)
	arsenal_button = NavButton.new("Arsenal", &"rifle", MenuKit.GOLD)
	crafting_button = NavButton.new("Atelier", &"anvil", MenuKit.TEXT)
	merchant_button = NavButton.new("Inventaire", &"chest", MenuKit.GOLD)
	shop_button = NavButton.new("Boutique", &"bag", MenuKit.GEM)
	for b: NavButton in [arsenal_button, crafting_button, merchant_button, shop_button]:
		row.add_child(b)
	merchant_button.custom_minimum_size.x += 12
	arsenal_button.pressed.connect(_on_arsenal)
	crafting_button.pressed.connect(func() -> void: _go_optional(crafting_button, MenuKit.CRAFTING_SCENE))
	merchant_button.pressed.connect(func() -> void: _go_optional(merchant_button, MenuKit.MERCHANT_SCENE))
	shop_button.pressed.connect(func() -> void: _go_shop(&""))
	crafting_button.set_soon(not scene_exists(MenuKit.CRAFTING_SCENE))
	merchant_button.set_soon(not scene_exists(MenuKit.MERCHANT_SCENE))
	buttons = [play_button, coop_button, pass_card, arsenal_button, crafting_button, merchant_button, shop_button]
	nav.offset_top = -m.w - nav.get_combined_minimum_size().y

	# Version (discrète, centrée en bas)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	_version = MenuKit.label("v" + (version if not version.is_empty() else "0.1"), 12,
		Color(MenuKit.TEXT_DIM, 0.45), MenuKit.nunito(700))
	_version.anchor_left = 0.5
	_version.anchor_right = 0.5
	_version.anchor_top = 1.0
	_version.anchor_bottom = 1.0
	_version.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_version.offset_bottom = -4
	ui.add_child(_version)


func _stat_chip(key: StringName, glyph: StringName, caption: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := MenuKit.panel_style(Color(MenuKit.NIGHT_DEEP, 0.62), Color(1, 1, 1, 0.12), 12, 1, 0)
	s.content_margin_left = 8
	s.content_margin_right = 12
	s.content_margin_top = 3
	s.content_margin_bottom = 4
	s.shadow_size = 0
	p.add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	var g := MenuGlyph.new(glyph, MenuKit.TEXT, 24)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", -5)
	row.add_child(col)
	var v := MenuKit.label("0", 18, MenuKit.TEXT, MenuKit.nunito(1000), 3)
	col.add_child(v)
	col.add_child(MenuKit.label(caption, 11, MenuKit.TEXT_DIM, MenuKit.nunito(800)))
	stat_values[key] = v
	return p


## Bouton « Coop » (à gauche de JOUER) : pictogramme duo + libellé ; « Bientôt » si la scène manque.
func _coop_button(h: float) -> Button:
	var b := Button.new()
	b.name = "CoopButton"
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Jouer en coopération"
	b.custom_minimum_size = Vector2(Balance.get_float("menu", "coop_button_width", 112.0), h)
	# même forme que JOUER, version secondaire (bleu nuit, liseré de la couleur d'action)
	var st: Dictionary = PlayCard.secondary_styles()
	b.add_theme_stylebox_override("normal", st["normal"])
	b.add_theme_stylebox_override("hover", st["hover"])
	b.add_theme_stylebox_override("pressed", st["pressed"])
	b.add_theme_stylebox_override("hover_pressed", st["pressed"])
	b.add_theme_stylebox_override("focus", st["focus"])
	var accent: Color = PlayCard.palette()["base"]
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_bottom = -PlayCard.DEPTH
	b.add_child(col)
	b.button_down.connect(func() -> void: col.position.y = PlayCard.DEPTH - 2)
	b.button_up.connect(func() -> void: col.position.y = 0)
	var g := PassGlyph.new(&"duo", accent, 44)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(g)
	var l := MenuKit.label("Coop", 20, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	var soon := not scene_exists(MenuKit.COOP_SCENE)
	b.set_meta(&"soon", soon)
	if soon:
		g.modulate.a = 0.45
		var pill := MenuKit.pill("Bientôt", Color(MenuKit.NIGHT_DEEP, 0.95), 12, MenuKit.GOLD, Color(MenuKit.GOLD, 0.7))
		pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(pill)
	b.pressed.connect(func() -> void: _go_optional(b, MenuKit.COOP_SCENE))
	MenuKit.add_feedback(b, 1.05)
	return b


func _gold_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.tooltip_text = "Or : vends ton butin au marchand"
	var s := MenuKit.panel_style(Color(MenuKit.NIGHT_DEEP, 0.88), Color(MenuKit.GOLD, 0.5), 30, 2, 0)
	s.content_margin_left = 8
	s.content_margin_right = 18
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.shadow_size = 4
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(0, 52)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	var g := MenuGlyph.new(&"coin", MenuKit.GOLD, 30)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(g)
	gold_label = MenuKit.label("0", 22, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(gold_label)
	dollar_label = gold_label
	return p


func _round_button(glyph: StringName, bg: Color, px: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(px, px)
	var n := MenuKit.panel_style(bg, Color(1, 1, 1, 0.35), int(px * 0.5), 2, 0)
	n.shadow_size = 4
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = bg.lightened(0.15)
	var pr := n.duplicate() as StyleBoxFlat
	pr.bg_color = bg.darkened(0.2)
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = MenuKit.GOLD
	f.set_border_width_all(3)
	f.set_corner_radius_all(int(px * 0.5) + 3)
	f.set_expand_margin_all(3)
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
	var blocks: Array = [[_top, Vector2(0, -90), 0.15], [_left, Vector2(-340, 0), 0.3],
		[info_banner, Vector2(380, 0), 0.38], [_nav, Vector2(0, 120), 0.45], [coop_button, Vector2(0, 170), 0.5],
		[play_button, Vector2(460, 0), 0.55]]
	for b: Array in blocks:
		var c: Control = b[0]
		var final_pos: Vector2 = c.position
		c.position = final_pos + (b[1] as Vector2)
		c.modulate.a = 0.0
		var tw := c.create_tween().set_parallel()
		tw.tween_property(c, "position", final_pos, 0.55).set_delay(b[2]) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "modulate:a", 1.0, 0.35).set_delay(b[2])
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
