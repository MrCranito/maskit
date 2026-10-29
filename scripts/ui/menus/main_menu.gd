class_name MainMenu
extends Control
## Menu principal de RaidersGo, façon lobby de jeu d'action mobile :
##  - fond vivant : camp de base à la lisière de Dust Creek au coucher du soleil (LobbyScene,
##    rendu Blender en couches + drapeau, feu, fumée, poussière, parallaxe lent) et le héros
##    avec son skin porté (LobbyHero ; tap = Personnages) ;
##  - barre du haut : logo, statistiques (raids, extractions, taux), dollars, gemmes (+ → onglet
##    Gemmes), bouton réglages ;
##  - gauche : résumé de l'arsenal de départ (LoadoutSummary → écran d'arsenal) ;
##  - droite, au-dessus de JOUER : bandeau d'info (événement, rotation, astuces) ;
##  - bas gauche : barre de navigation (Arsenal, Personnages, Boutique, Options, Crédits) ;
##  - bas droite : grand bouton « JOUER » avec la carte (PlayCard → choix des cartes →
##    arsenal de départ → raid).
## Animations d'entrée (glissements, fondus), retours tactiles et sons MenuKit, marges de
## sécurité (encoche / barre d'accueil). Aucun _process.

var lobby: LobbyScene = null
var hero: LobbyHero = null
var logo: RaidersLogo = null
var gem_counter: GemCounter = null
var gem_plus: Button = null
var gear_button: Button = null
var dollar_label: Label = null
var stat_values: Dictionary = {}
var loadout_summary: LoadoutSummary = null
var info_banner: InfoBanner = null
var play_button: PlayCard = null
var arsenal_button: NavButton = null
var characters_button: NavButton = null
var shop_button: NavButton = null
var options_button: NavButton = null
var credits_button: NavButton = null
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
	top.add_child(_dollar_pill())
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
	gear_button = _round_button(&"gear", Color(MenuKit.NIGHT, 0.9), 54)
	gear_button.tooltip_text = "Réglages"
	gear_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear_button.pressed.connect(open_options)
	top.add_child(gear_button)

	# Gauche : arsenal de départ
	loadout_summary = LoadoutSummary.new()
	loadout_summary.name = "LoadoutSummary"
	loadout_summary.position = Vector2(m.x, m.y + 62 + gap)
	loadout_summary.pressed.connect(_on_arsenal)
	ui.add_child(loadout_summary)

	# Droite, au-dessus de JOUER : bandeau d'information (le haut droit reste au drapeau du camp)
	info_banner = InfoBanner.new()
	info_banner.name = "InfoBanner"
	info_banner.anchor_left = 1.0
	info_banner.anchor_right = 1.0
	info_banner.anchor_top = 1.0
	info_banner.anchor_bottom = 1.0
	info_banner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var play_h: float = Balance.get_float("menu", "play_card_height", 148.0)
	info_banner.offset_right = -m.z
	info_banner.offset_left = -m.z - Balance.get_float("menu", "play_card_width", 420.0)
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
	characters_button = NavButton.new("Personnages", &"helmet", MenuKit.TEXT)
	shop_button = NavButton.new("Boutique", &"bag", MenuKit.GEM)
	options_button = NavButton.new("Options", &"gear", MenuKit.TEXT_DIM)
	credits_button = NavButton.new("Crédits", &"star", MenuKit.GOLD)
	for b: NavButton in [arsenal_button, characters_button, shop_button, options_button, credits_button]:
		row.add_child(b)
	characters_button.custom_minimum_size.x += 18
	arsenal_button.pressed.connect(_on_arsenal)
	characters_button.pressed.connect(func() -> void: _go_shop(&"character"))
	shop_button.pressed.connect(func() -> void: _go_shop(&""))
	options_button.pressed.connect(open_options)
	credits_button.pressed.connect(open_credits)
	buttons = [play_button, arsenal_button, characters_button, shop_button, options_button, credits_button]
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


func _dollar_pill() -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.tooltip_text = "Dollars : valeur du butin extrait"
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
	dollar_label = MenuKit.label("0", 22, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	dollar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(dollar_label)
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
	dollar_label.text = format_thousands(Profile.dollars)


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
	var blocks: Array = [[_top, Vector2(0, -90), 0.15], [loadout_summary, Vector2(-340, 0), 0.3],
		[info_banner, Vector2(380, 0), 0.38], [_nav, Vector2(0, 120), 0.45], [play_button, Vector2(460, 0), 0.55]]
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
