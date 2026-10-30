class_name LobbyWallet
extends HBoxContainer
## Coin haut droit du lobby (direction « D ») : or, gemmes avec leur « + » d'achat, puis la roue
## des réglages, à part. Retour de Victor (« les pièces/gemmes en haut pourraient être mieux ») :
##   - même hauteur pour les trois blocs ([menu] lobby_wallet_height), alignés en haut ;
##   - les compteurs sont les composants partagés GoldCounter / GemCounter (mêmes pastilles encre
##     soulignées, même chiffre, même « ∞ » du mode développeur que la boutique, le pass, l'arsenal) ;
##   - le « + » est un carré violet à angles vifs intégré au bout de la pastille de gemmes (le même
##     « + » plein que l'emplacement de coéquipier), séparé du chiffre par un filet ;
##   - la roue est détachée des monnaies par un écart plus grand ([menu] lobby_wallet_gap).
## Signaux : gems_pressed (compteur ou « + » → onglet Gemmes), gold_pressed, settings_pressed.

signal gems_pressed
signal gold_pressed
signal settings_pressed

var gold_counter: GoldCounter = null
var gem_counter: GemCounter = null
var gem_plus: Button = null
var gear_button: Button = null
var _gem_pill: HBoxContainer = null


func _init() -> void:
	name = "Wallet"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h: float = Balance.get_float("menu", "lobby_wallet_height", 56.0)
	var fs: int = int(Balance.get_value("menu", "lobby_wallet_font", 24))
	add_theme_constant_override("separation", int(Balance.get_value("menu", "lobby_wallet_pill_gap", 10)))
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	gold_counter = GoldCounter.new(fs)
	gold_counter.name = "GoldCounter"
	_shape_counter(gold_counter, MenuKit.COIN, h, 18.0)
	gold_counter.pressed.connect(func() -> void: gold_pressed.emit())
	add_child(gold_counter)

	# Gemmes : pastille + « + » collé à droite, comme un seul bloc souligné cyan
	_gem_pill = HBoxContainer.new()
	_gem_pill.name = "GemPill"
	_gem_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gem_pill.add_theme_constant_override("separation", 0)
	add_child(_gem_pill)
	gem_counter = GemCounter.new(fs)
	gem_counter.name = "GemCounter"
	_shape_counter(gem_counter, MenuKit.GEM, h, 14.0)
	gem_counter.pressed.connect(func() -> void: gems_pressed.emit())
	_gem_pill.add_child(gem_counter)
	gem_plus = _plus_button(h)
	gem_plus.pressed.connect(func() -> void:
		MenuKit.sfx(&"click_soft")
		gems_pressed.emit())
	_gem_pill.add_child(gem_plus)

	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size.x = maxf(0.0, Balance.get_float("menu", "lobby_wallet_gap", 22.0)
		- float(get_theme_constant("separation")))
	add_child(gap)

	gear_button = _gear(h)
	gear_button.pressed.connect(func() -> void: settings_pressed.emit())
	add_child(gear_button)


func _ready() -> void:
	# Bascule du mode développeur : « ∞ » ↔ vrai solde, sans attendre un autre signal.
	DevMode.notifier.changed.connect(_on_dev_mode)


func _exit_tree() -> void:
	if DevMode.notifier.changed.is_connected(_on_dev_mode):
		DevMode.notifier.changed.disconnect(_on_dev_mode)


func _on_dev_mode(_on: bool) -> void:
	gold_counter.refresh(false)
	gem_counter.refresh(false)


## Hauteur, marges et pastille encre soulignée communes aux deux compteurs.
static func _shape_counter(c: PanelContainer, accent: Color, h: float, right: float) -> void:
	var st := MenuKit.currency_style(accent, right)
	st.content_margin_left = 14
	c.add_theme_stylebox_override("panel", st)
	c.custom_minimum_size = Vector2(Balance.get_float("menu", "lobby_wallet_min_width", 104.0), h)
	c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var row := c.get_child(0) as HBoxContainer
	row.add_theme_constant_override("separation", 10)
	var v: Label = c.get(&"value_label")
	v.add_theme_font_override("font", MenuKit.nunito(700))
	v.add_theme_constant_override("outline_size", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## « + » d'achat : carré violet plein à angles vifs (coin bas droit biseauté), même hauteur que la
## pastille, souligné cyan comme elle, « + » plein (PlusMark) ; un filet sombre le sépare du chiffre.
static func _plus_button(h: float) -> Button:
	var b := Button.new()
	b.name = "GemPlus"
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Acheter des gemmes"
	b.custom_minimum_size = Vector2(h, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var mk := func(bg: Color) -> CutBox:
		var c := CutBox.make(bg, h * 0.22, Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
		c.corners = CutBox.CUT_BOTTOM_RIGHT
		c.accent_color = MenuKit.GEM
		return c
	b.add_theme_stylebox_override("normal", mk.call(MenuKit.VIOLET))
	b.add_theme_stylebox_override("hover", mk.call(MenuKit.VIOLET.lightened(0.15)))
	b.add_theme_stylebox_override("pressed", mk.call(MenuKit.VIOLET.darkened(0.2)))
	b.add_theme_stylebox_override("hover_pressed", mk.call(MenuKit.VIOLET.darkened(0.2)))
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.TEXT
	f.border_width = 2.0
	f.cut = h * 0.22
	f.corners = CutBox.CUT_BOTTOM_RIGHT
	f.grow = 3.0
	b.add_theme_stylebox_override("focus", f)
	# filet de séparation + soulignement cyan (continuité avec la pastille de gemmes)
	var deco := Control.new()
	deco.name = "Deco"
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.draw.connect(func() -> void:
		deco.draw_rect(Rect2(0, 0, 2, deco.size.y), Color(MenuKit.NIGHT_DEEP, 0.9))
		deco.draw_rect(Rect2(0, deco.size.y - 4.0, deco.size.x - h * 0.22 + 4.0, 4.0), MenuKit.GEM))
	b.add_child(deco)
	var plus := PlusMark.new()
	plus.name = "Plus"
	plus.thickness = 0.22
	plus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := h * 0.3
	plus.offset_left = inset
	plus.offset_top = inset - 2.0
	plus.offset_right = -inset
	plus.offset_bottom = -inset - 2.0
	b.add_child(plus)
	MenuKit.add_feedback(b, 1.06)
	return b


## Réglages : carré encre à liseré blanc fin, coins haut gauche / bas droit biseautés (comme le
## retour des écrans), roue blanche. Même hauteur que les compteurs.
static func _gear(h: float) -> Button:
	var b := Button.new()
	b.name = "GearButton"
	b.focus_mode = Control.FOCUS_ALL
	b.tooltip_text = "Réglages"
	b.custom_minimum_size = Vector2(h, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var mk := func(bg: Color) -> CutBox:
		var c := CutBox.make(bg, h * 0.22, Color(1, 1, 1, 0.35), 1.0, 0.0, 0.0)
		c.corners = CutBox.CUT_TOP_LEFT | CutBox.CUT_BOTTOM_RIGHT
		return c
	b.add_theme_stylebox_override("normal", mk.call(Color(MenuKit.NIGHT_DEEP, 0.82)))
	b.add_theme_stylebox_override("hover", mk.call(Color(0.12, 0.11, 0.2, 0.9)))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0, 0, 0, 0.9)))
	b.add_theme_stylebox_override("hover_pressed", mk.call(Color(0, 0, 0, 0.9)))
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.TEXT
	f.border_width = 2.0
	f.cut = h * 0.22
	f.corners = CutBox.CUT_TOP_LEFT | CutBox.CUT_BOTTOM_RIGHT
	f.grow = 3.0
	b.add_theme_stylebox_override("focus", f)
	var g := MenuGlyph.new(&"gear", MenuKit.TEXT, h * 0.5)
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["offset_left", "offset_top"]:
		g.set(side, h * 0.24)
	for side: String in ["offset_right", "offset_bottom"]:
		g.set(side, -h * 0.24)
	b.add_child(g)
	MenuKit.add_feedback(b, 1.08)
	return b
