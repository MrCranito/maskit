class_name ShopOffers
extends Control
## Onglets « Packs », « Coffres » et « Gemmes » de la boutique (maquettes Packs, ShopChests, Gems,
## direction D) : cartes encre à coin coupé à gauche, bandeau violet en biais à droite avec
## l'offre choisie et son bouton d'action. Gemmes : illustration peinte de chaque pack (CurrencyArt)
## sur une lueur qui monte avec la taille du pack, rubans calculés (« Meilleure offre », « Populaire »),
## bonus en autocollant, prix sur un vrai bouton (choisit la carte, puis achète).
## Toute la logique est dans Store ; cet écran affiche
## et appelle. Les coffres ne se vendent pas : ils se gagnent en jouant (Store.open_chest).

signal changed
## Demande d'aller sur un autre onglet de la boutique (ex. « Gemmes »).
signal open_tab(tab: StringName)

const MODE_GEMS := &"gems"
const MODE_PACKS := &"packs"
const MODE_CHESTS := &"chests"
const MODE_GOLD := &"gold"

var mode: StringName = MODE_GEMS
var selected: int = 0
## Cartes cliquables (packs de gemmes ou packs à contenu), dans l'ordre des offres.
var cards: Array[Button] = []
## Bouton d'action du bandeau (Acheter / Ouvrir).
var action_button: Button = null
## Fenêtre de révélation du dernier coffre ouvert (null si fermée).
var reveal: Control = null
## Dernière fenêtre de confirmation ouverte (tests).
var last_confirm: ConfirmPanel = null
## Dernier résultat de Store.open_chest / purchase_bundle (tests).
var last_result: Dictionary = {}

var _left: Control = null
var _slab: Control = null
var _slab_col: VBoxContainer = null


func _init(p_mode: StringName = MODE_GEMS) -> void:
	mode = p_mode
	name = "Offers"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	if mode == MODE_GEMS:
		selected = maxi(Store.popular_pack(), 0)
	elif mode == MODE_GOLD:
		selected = clampi(int(Balance.get_value("shop", "gold_pack_default", 1)), 0, maxi(Store.gold_packs().size() - 1, 0))
	elif mode == MODE_PACKS:
		selected = 0
		var list := Store.bundles()
		while selected < list.size() - 1 and not Store.bundle_available(list[selected]["id"]):
			selected += 1
	rebuild()


func rebuild() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	cards.clear()
	reveal = null
	var slab_w: float = Balance.get_float("menu", "shop_slab_width", 460.0)
	_slab = MainMenu.LobbySlab.new()
	_slab.name = "Slab"
	(_slab as MainMenu.LobbySlab).cut = Balance.get_float("menu", "shop_slab_cut", 84.0)
	(_slab as MainMenu.LobbySlab).color = Color(MenuKit.VIOLET, Balance.get_float("menu", "lobby_slab_alpha", 0.66))
	_slab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slab.anchor_left = 1.0
	_slab.anchor_right = 1.0
	_slab.anchor_bottom = 1.0
	_slab.offset_left = -slab_w
	add_child(_slab)
	_slab_col = VBoxContainer.new()
	_slab_col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slab_col.offset_left = (_slab as MainMenu.LobbySlab).cut
	_slab_col.offset_right = -24
	_slab_col.offset_top = 18
	_slab_col.offset_bottom = -18
	_slab_col.add_theme_constant_override("separation", 6)
	_slab_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slab.add_child(_slab_col)
	_left = Control.new()
	_left.name = "Left"
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_left.offset_right = -slab_w - 12.0
	add_child(_left)
	match mode:
		MODE_PACKS:
			_build_bundles()
		MODE_CHESTS:
			_build_chests()
		MODE_GOLD:
			_build_gold()
		_:
			_build_gems()
	_fill_slab()


# --- Briques ---------------------------------------------------------------------------

static func _txt(t: String, px: int, col: Color = MenuKit.TEXT, weight: int = 600) -> Label:
	var l := MenuKit.label(t, px, col, MenuKit.nunito(weight))
	return l


static func _big(t: String, px: int, col: Color = MenuKit.TEXT) -> Label:
	return MenuKit.label(t, px, col, MenuKit.display())


static func _kicker(t: String, col: Color = MenuKit.TEXT) -> Label:
	var l := _txt(t, 16, col, 600)
	l.uppercase = true
	return l


## Gemmes avec séparateur des milliers (« 2 200 »).
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## Carte encre à coin haut droit coupé ; la carte choisie a un anneau blanc épais et un fond
## teinté de violet, les autres sont légèrement atténuées (la carte choisie ressort nettement).
func _card(i: int, tint: Color) -> Button:
	var b := Button.new()
	b.name = "Card%d" % i
	b.focus_mode = Control.FOCUS_ALL
	b.clip_contents = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mk := func(bg: Color, ring: float) -> CutBox:
		var c := CutBox.make(bg, 22.0, MenuKit.TEXT if ring > 0.0 else Color(0, 0, 0, 0), ring, 0.0, 0.0)
		c.corners = CutBox.CUT_TOP_RIGHT
		return c
	var on := i == selected
	var bg := Color(MenuKit.NIGHT_DEEP, 0.88).lerp(tint, 0.22)
	if on:
		bg = bg.lerp(Color(MenuKit.VIOLET, 0.92), 0.3)
	var ring := 3.5 if on else 0.0
	b.add_theme_stylebox_override("normal", mk.call(bg, ring))
	b.add_theme_stylebox_override("hover", mk.call(bg.lightened(0.06), ring if on else 1.5))
	b.add_theme_stylebox_override("pressed", mk.call(bg.darkened(0.1), 3.5))
	b.add_theme_stylebox_override("hover_pressed", mk.call(bg.darkened(0.1), 3.5))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), 3.5))
	if not on:
		b.modulate = Color(0.84, 0.84, 0.9)
	b.pressed.connect(func() -> void: select(i))
	MenuKit.add_feedback(b, 1.02)
	cards.append(b)
	return b


## Vrai bouton de prix en bas d'une carte (Anton, coin coupé) : violet plein sur la carte choisie
## (le toucher achète, comme « Acheter » du bandeau), encre cerclée sinon (le toucher choisit la carte).
## `caption` : petit texte à gauche (ex. « Valeur 2 600 »), vide = prix centré.
func _price_button(card: Control, i: int, price: String, caption: String, on: bool, buy: Callable) -> Button:
	var b := Button.new()
	b.name = "PriceButton"
	b.focus_mode = Control.FOCUS_NONE
	b.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	b.offset_left = 12
	b.offset_right = -12
	b.offset_top = -66
	b.offset_bottom = -12
	var base := MenuKit.VIOLET if on else Color(MenuKit.NIGHT_DEEP, 0.7)
	var mk := func(bg: Color, border: float) -> CutBox:
		var c := CutBox.make(bg, 14.0, Color(1, 1, 1, 0.9) if border > 0.0 else Color(0, 0, 0, 0), border, 14.0, 4.0)
		c.corners = CutBox.CUT_TOP_LEFT
		return c
	b.add_theme_stylebox_override("normal", mk.call(base, 0.0 if on else 1.5))
	b.add_theme_stylebox_override("hover", mk.call(base.lerp(MenuKit.VIOLET_LIGHT, 0.25), 0.0 if on else 1.5))
	b.add_theme_stylebox_override("pressed", mk.call(base.darkened(0.2), 0.0 if on else 1.5))
	b.add_theme_stylebox_override("hover_pressed", mk.call(base.darkened(0.2), 0.0 if on else 1.5))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	b.add_child(row)
	if not caption.is_empty():
		var l := _txt(caption, 15, Color(1, 1, 1, 0.75))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(l)
	var r := _big(price, 28)
	r.name = "Price"
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if caption.is_empty():
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(r)
	b.pressed.connect(func() -> void:
		if i == selected:
			buy.call()
		else:
			select(i))
	MenuKit.add_feedback(b, 1.03)
	card.add_child(b)
	return b


## Étiquette en haut à gauche d'une carte.
static func _tag(card: Control, t: String, bg: Color, fg: Color) -> void:
	var p := PanelContainer.new()
	p.name = "Tag"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.position = Vector2(0, 16)
	card.add_child(p)
	var l := _txt(t, 15, fg, 700)
	l.uppercase = true
	p.add_child(l)


## Bouton encre du bandeau, coin haut gauche coupé (maquettes).
static func _slab_button(t: String, light: bool = false) -> Button:
	var b := Button.new()
	b.name = "Action"
	b.text = t
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(320, 78)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.add_theme_font_override("font", MenuKit.display())
	b.add_theme_font_size_override("font_size", 31)
	var base := MenuKit.TEXT if light else MenuKit.NIGHT_DEEP
	var mk := func(bg: Color) -> CutBox:
		var c := CutBox.make(bg, 16.0, Color(0, 0, 0, 0), 0.0, 20.0, 0.0)
		c.corners = CutBox.CUT_TOP_LEFT
		return c
	b.add_theme_stylebox_override("normal", mk.call(base))
	b.add_theme_stylebox_override("hover", mk.call(base.lerp(MenuKit.VIOLET_LIGHT, 0.15)))
	b.add_theme_stylebox_override("pressed", mk.call(base.darkened(0.2)))
	b.add_theme_stylebox_override("hover_pressed", mk.call(base.darkened(0.2)))
	b.add_theme_stylebox_override("disabled", mk.call(Color(MenuKit.NIGHT_DEEP, 0.4)))
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.TEXT
	f.border_width = 2.0
	f.cut = 18.0
	f.corners = CutBox.CUT_TOP_LEFT
	f.grow = 3.0
	b.add_theme_stylebox_override("focus", f)
	var fg := Color(0.227, 0.122, 0.561) if light else MenuKit.TEXT   # #3A1F8F sur blanc
	for c: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
	MenuKit.add_feedback(b, 1.03)
	return b


func _spacer() -> void:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slab_col.add_child(s)


func _right(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_horizontal = Control.SIZE_SHRINK_END
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		l.custom_minimum_size.x = 320
	_slab_col.add_child(l)
	return l


func select(i: int) -> void:
	if i == selected:
		return
	selected = i
	MenuKit.sfx(&"tick")
	rebuild()


# --- Gemmes ----------------------------------------------------------------------------

## Skin de boutique le plus cher payable avec `g` gemmes (null si aucun).
static func best_affordable(g: int) -> SkinData:
	var best: SkinData = null
	for k: StringName in [SkinData.KIND_CHARACTER, SkinData.KIND_WEAPON]:
		for s: SkinData in SkinData.shop_skins(k):
			if s.price_gems > 0 and s.price_gems <= g and (best == null or s.price_gems > best.price_gems):
				best = s
	return best


static func _euros(price: String) -> float:
	return price.replace(",", ".").replace("€", "").strip_edges().to_float()


## Gain en % de gemmes par euro par rapport au plus petit pack (0 pour le premier).
static func pack_bonus_pct(i: int) -> int:
	var packs := Store.packs()
	if i <= 0 or i >= packs.size():
		return 0
	var base := float(packs[0]["gems"]) / maxf(_euros(packs[0]["price"]), 0.01)
	var mine := float(packs[i]["gems"]) / maxf(_euros(packs[i]["price"]), 0.01)
	return roundi((mine / base - 1.0) * 100.0)


## Ruban d'une offre de gemmes : « Meilleure offre » sur le meilleur rapport gemmes / euro,
## « Populaire » sur le pack choisi d'office (balance.cfg), "" sinon. Calculé, jamais en dur.
static func pack_ribbon(i: int) -> String:
	if i < 0:
		return ""
	if i == Store.best_value_pack():
		return "Meilleure offre"
	if i == Store.popular_pack():
		return "Populaire"
	return ""


## Couleur de la lueur d'un pack : cyan des gemmes pour les petits, or pour les gros (bourse, coffre).
static func pack_glow_color(i: int) -> Color:
	var n := Store.packs().size()
	var t := clampf(float(i) / maxf(1.0, n - 1.0), 0.0, 1.0)
	return MenuKit.GEM.lerp(MenuKit.COIN, smoothstep(0.35, 0.75, t))


## Illustration d'un pack (image peinte, sinon une gemme dessinée).
static func pack_art(i: int) -> Control:
	var tex := CurrencyArt.pack(i)
	if tex == null:
		var g := GemIcon.new()
		g.name = "Art"
		return g
	var t := TextureRect.new()
	t.name = "Art"
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _build_gems() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(col)
	if Store.first_bonus_available():
		var ban := PanelContainer.new()
		ban.name = "WelcomeBanner"
		ban.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := CutBox.make(Color(MenuKit.COIN, 0.16), 0.0, Color(0, 0, 0, 0), 0.0, 16.0, 4.0)
		st.accent_width = 5.0
		st.accent_color = MenuKit.COIN
		ban.add_theme_stylebox_override("panel", st)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ban.add_child(row)
		var x2 := _big("×%d" % Store.first_bonus_multiplier(), 30, MenuKit.COIN)
		x2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(x2)
		var k := _kicker("Premier achat", MenuKit.COIN)
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(k)
		var d := _kicker("Gemmes doublées sur le pack de ton choix · une seule fois")
		d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.clip_text = true
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(d)
		col.add_child(ban)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	var packs := Store.packs()
	var art_ratio := clampf(Balance.get_float("menu", "shop_gem_art_ratio", 0.5), 0.2, 0.7)
	var glow_range: Variant = Balance.get_value("menu", "shop_gem_glow", [0.18, 0.62])
	var g0 := float(glow_range[0]) if glow_range is Array else 0.18
	var g1 := float(glow_range[1]) if glow_range is Array else 0.62
	var first := Store.first_bonus_available()
	for i: int in packs.size():
		var p: Dictionary = packs[i]
		var t := clampf(float(i) / maxf(1.0, packs.size() - 1.0), 0.0, 1.0)
		var on := i == selected
		var card := _card(i, MenuKit.GEM.lerp(MenuKit.VIOLET, t))
		grid.add_child(card)
		# Lueur (et rayons pour les gros packs) qui monte avec la taille du pack, puis l'illustration.
		var glow := PackGlow.new()
		glow.name = "Glow"
		glow.color = pack_glow_color(i)
		glow.strength = lerpf(g0, g1, t) * (1.25 if on else 1.0)
		glow.rays = 0 if i == 0 else 10 + 2 * i
		glow.anchor_right = 1.0
		glow.anchor_bottom = art_ratio + 0.08
		card.add_child(glow)
		var art := pack_art(i)
		art.anchor_left = 0.05
		art.anchor_right = 0.95
		art.anchor_top = 0.05
		art.anchor_bottom = art_ratio + 0.05
		card.add_child(art)
		var ribbon := pack_ribbon(i)
		if not ribbon.is_empty():
			_ribbon(card, ribbon, MenuKit.COIN if i == Store.best_value_pack() else MenuKit.VIOLET)
		var pct := pack_bonus_pct(i)
		if pct > 0:
			_bonus_sticker(card, pct, not ribbon.is_empty())
		var info := VBoxContainer.new()
		info.name = "Info"
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.anchor_top = art_ratio + 0.04
		info.anchor_right = 1.0
		info.anchor_bottom = 1.0
		info.offset_bottom = -72
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_theme_constant_override("separation", -4)
		card.add_child(info)
		var n := _big(fmt(int(p["gems"])), 52)
		n.name = "Amount"
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(n)
		card.resized.connect(func() -> void:
			n.add_theme_font_size_override("font_size", int(clampf(card.size.x * 0.21, 32.0, 60.0))))
		var u := _kicker("Gemmes", Color(1, 1, 1, 0.65))
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(u)
		if first:
			var extra := Store.pack_gems_now(i) - int(p["gems"])
			var bl := _txt("+%s offertes" % fmt(extra), 16, MenuKit.COIN, 700)
			bl.name = "FirstBonus"
			bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			info.add_child(bl)
		_price_button(card, i, str(p["price"]), "", on, func() -> void: ask_pack(i))


## Ruban en haut d'une carte (« Meilleure offre », « Populaire ») ; s'arrête avant le coin coupé.
func _ribbon(card: Control, t: String, bg: Color) -> void:
	var p := PanelContainer.new()
	p.name = "Ribbon"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := CutBox.make(bg, 12.0, Color(0, 0, 0, 0), 0.0, 12.0, 3.0)
	st.corners = CutBox.CUT_BOTTOM_RIGHT
	p.add_theme_stylebox_override("panel", st)
	p.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	p.offset_right = -26
	card.add_child(p)
	var dark := bg.get_luminance() > 0.55
	var l := _txt(t, 15, Color(0.07, 0.04, 0.14) if dark else MenuKit.TEXT, 700)
	l.uppercase = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p.add_child(l)
	# Cartes étroites (1280 x 720) : le texte rétrécit pour tenir en entier plutôt que d'être tronqué.
	card.resized.connect(func() -> void:
		var room := card.size.x - 26.0 - 24.0
		var px := 15
		while px > 11 and MenuKit.nunito(700).get_string_size(t.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > room:
			px -= 1
		l.add_theme_font_size_override("font_size", px))


## Pastille « +24 % » penchée, posée sur l'illustration comme un autocollant (sous le ruban s'il y en a un).
func _bonus_sticker(card: Control, pct: int, below_ribbon: bool) -> void:
	var p := PanelContainer.new()
	p.name = "Bonus"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := CutBox.make(MenuKit.COIN, 8.0, Color(0.07, 0.04, 0.14, 0.9), 2.0, 8.0, 0.0)
	st.corners = CutBox.CUT_TOP_LEFT | CutBox.CUT_BOTTOM_RIGHT
	p.add_theme_stylebox_override("panel", st)
	p.position = Vector2(8, 46 if below_ribbon else 14)
	p.rotation_degrees = -6.0
	card.add_child(p)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", -6)
	p.add_child(v)
	var n := _big("+%d %%" % pct, 24, Color(0.07, 0.04, 0.14))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	var l := _txt("de gemmes", 12, Color(0.07, 0.04, 0.14, 0.8), 700)
	l.uppercase = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)


func _fill_gems_slab() -> void:
	var packs := Store.packs()
	if packs.is_empty():
		return
	var i := clampi(selected, 0, packs.size() - 1)
	var first := Store.first_bonus_available()
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.alignment = BoxContainer.ALIGNMENT_END
	head.add_theme_constant_override("separation", 10)
	var ribbon := pack_ribbon(i)
	if not ribbon.is_empty():
		head.add_child(MenuKit.pill(ribbon, MenuKit.COIN if i == Store.best_value_pack() else MenuKit.TEXT, 14,
			Color(0.07, 0.04, 0.14) if i == Store.best_value_pack() else Color(0.227, 0.122, 0.561)))
	head.add_child(_kicker("Ton premier pack" if first else "Pack choisi"))
	_slab_col.add_child(head)
	# Grande illustration du pack choisi : prend toute la place libre du bandeau (plus de vide) ;
	# le nombre de gemmes est posé sur son bas, à droite.
	var stage := Control.new()
	stage.name = "SlabArt"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(0, 120)
	_slab_col.add_child(stage)
	var glow := PackGlow.new()
	glow.color = pack_glow_color(i).lerp(MenuKit.TEXT, 0.2)
	glow.strength = 0.5
	glow.rays = 14
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_bottom = -40
	stage.add_child(glow)
	var art := pack_art(i)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_bottom = -52
	stage.add_child(art)
	var amount := MenuKit.label(fmt(Store.pack_gems_now(i)), 84, MenuKit.TEXT, MenuKit.display(), 10)
	amount.name = "Amount"
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	amount.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	amount.grow_vertical = Control.GROW_DIRECTION_BEGIN
	amount.offset_bottom = 8
	stage.add_child(amount)
	if first:
		var row := HBoxContainer.new()
		row.name = "FirstBonus"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 10)
		row.add_child(_kicker("Gemmes"))
		row.add_child(MenuKit.pill("×%d premier achat · %s au lieu de %s" % [Store.first_bonus_multiplier(),
			fmt(Store.pack_gems_now(i)), fmt(int(packs[i]["gems"]))], MenuKit.COIN, 14, Color(0.07, 0.04, 0.14)))
		_slab_col.add_child(row)
	else:
		_right(_kicker("Gemmes"))
	var pct := pack_bonus_pct(i)
	if pct > 0:
		var pill := MenuKit.pill("+%d %% par rapport au petit pack" % pct, MenuKit.TEXT, 15, Color(0.227, 0.122, 0.561))
		pill.size_flags_horizontal = Control.SIZE_SHRINK_END
		_slab_col.add_child(pill)
	var best := best_affordable(Store.pack_gems_now(i))
	if best != null:
		_right(_kicker("De quoi t'offrir"))
		_skin_row(best)
	else:
		var l := _txt("Ce pack complète un solde : le skin le moins cher coûte plus.", 16)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_right(l)
	action_button = _slab_button("Acheter · %s" % packs[i]["price"])
	action_button.pressed.connect(func() -> void: ask_pack(selected))
	_slab_col.add_child(action_button)
	_right(_kicker("Aucun avantage en jeu"))


## Ligne « skin » du bandeau : liseré de rareté, nom, prix.
func _skin_row(s: SkinData, value_text: String = "") -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.35), 0.0, Color(0, 0, 0, 0), 0.0, 14.0, 8.0)
	st.accent_width = 5.0
	st.accent_color = MenuKit.rarity_color(s.rarity)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(320, 52)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var kind := "Skin" if s.kind == SkinData.KIND_CHARACTER else _weapon_name(s)
	var n := _txt("%s %s" % [kind, s.display_name], 17, MenuKit.TEXT, 600)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(n)
	row.add_child(_txt(value_text if not value_text.is_empty() else fmt(s.price_gems), 17, Color(1, 1, 1, 0.75)))
	_slab_col.add_child(p)


## « Spetsnaz » pour un personnage, « P9 Carbone » pour un skin d'arme.
static func skin_title(s: SkinData) -> String:
	return s.display_name if s.kind == SkinData.KIND_CHARACTER else "%s %s" % [_weapon_name(s), s.display_name]


static func _weapon_name(s: SkinData) -> String:
	var w := ShopScreen.weapon_of(s)
	return w.display_name if w != null else "Arme"


# --- Confirmations d'achat ----------------------------------------------------------------

## Fenêtre de confirmation par-dessus la boutique (ShopScreen._open_modal), `on_ok` si confirmé.
func _confirm(title: String, message: String, ok_text: String, on_ok: Callable) -> ConfirmPanel:
	var m := ConfirmPanel.new(title, message, ok_text)
	m.confirmed.connect(on_ok)
	last_confirm = m
	var n: Node = get_parent()
	while n != null and not (n is ShopScreen):
		n = n.get_parent()
	if n is ShopScreen:
		(n as ShopScreen)._open_modal(m)
	else:
		add_child(m)
	MenuKit.sfx(&"tick")
	return m


## Pack de gemmes : confirmation (prix, gemmes créditées), puis achat.
func ask_pack(i: int) -> ConfirmPanel:
	var packs := Store.packs()
	if i < 0 or i >= packs.size():
		return null
	return _confirm("Acheter ce pack ?", "%s gemmes pour %s.\nPaiement simulé (test)." % [
		fmt(Store.pack_gems_now(i)), str(packs[i]["price"])], "Acheter", func() -> void: buy_pack(i))


## Pack à contenu : confirmation, puis achat.
func ask_bundle(id: StringName) -> ConfirmPanel:
	for b: Dictionary in Store.bundles():
		if StringName(str(b["id"])) == id:
			return _confirm("Acheter ce pack ?", "Pack « %s » pour %s.\nPaiement simulé (test)." % [
				str(b["name"]), str(b["price"])], "Acheter", func() -> void: buy_bundle(id))
	return null


## Pack d'or : confirmation (ou « pas assez de gemmes » → onglet Gemmes), puis achat.
func ask_gold_pack(i: int) -> ConfirmPanel:
	var list := Store.gold_packs()
	if i < 0 or i >= list.size():
		return null
	var cost := int(list[i]["gems"])
	if not Profile.can_afford(&"gems", cost):
		MenuKit.sfx(&"error")
		return _confirm("Pas assez de gemmes", "Il te manque %s gemmes pour ce pack d'or." % fmt(cost - Profile.gems),
			"Voir les gemmes", func() -> void: open_tab.emit(&"gems"))
	return _confirm("Acheter de l'or ?", "%s pièces d'or pour %s gemmes." % [fmt(int(list[i]["gold"])), fmt(cost)],
		"Acheter", func() -> void: buy_gold_pack(i))


func buy_pack(i: int) -> bool:
	var ok := Store.purchase_pack(i)
	MenuKit.sfx(&"gold_pickup" if ok else &"error")
	if ok:
		changed.emit()
		rebuild()
	return ok


# --- Or contre gemmes -------------------------------------------------------------------

## Cartes des packs d'or : pile de pièces qui grossit, montant, prix en gemmes.
func _build_gold() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(col)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	var list := Store.gold_packs()
	var art_ratio := clampf(Balance.get_float("menu", "shop_gem_art_ratio", 0.5), 0.2, 0.7)
	for i: int in list.size():
		var p: Dictionary = list[i]
		var t := clampf(float(i) / maxf(1.0, list.size() - 1.0), 0.0, 1.0)
		var on := i == selected
		var card := _card(i, MenuKit.COIN.lerp(MenuKit.VIOLET, 0.35 * t))
		grid.add_child(card)
		var glow := PackGlow.new()
		glow.name = "Glow"
		glow.color = MenuKit.COIN
		glow.strength = lerpf(0.16, 0.5, t) * (1.25 if on else 1.0)
		glow.rays = 0 if i == 0 else 10 + 2 * i
		glow.anchor_right = 1.0
		glow.anchor_bottom = art_ratio + 0.08
		card.add_child(glow)
		var art := GoldPile.new()
		art.name = "Art"
		art.coins = gold_pile_size(i)
		art.anchor_left = 0.08
		art.anchor_right = 0.92
		art.anchor_top = 0.08
		art.anchor_bottom = art_ratio + 0.04
		card.add_child(art)
		var info := VBoxContainer.new()
		info.name = "Info"
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.anchor_top = art_ratio + 0.04
		info.anchor_right = 1.0
		info.anchor_bottom = 1.0
		info.offset_bottom = -72
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.add_theme_constant_override("separation", -4)
		card.add_child(info)
		var n := _big(fmt(int(p["gold"])), 52, MenuKit.COIN)
		n.name = "Amount"
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(n)
		card.resized.connect(func() -> void:
			n.add_theme_font_size_override("font_size", int(clampf(card.size.x * 0.21, 32.0, 60.0))))
		var u := _kicker("Pièces d'or", Color(1, 1, 1, 0.65))
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(u)
		_price_button(card, i, "%s gemmes" % fmt(int(p["gems"])), "", on, func() -> void: ask_gold_pack(i))


## Nombre de pièces dessinées pour le pack `i` (pile qui grossit).
static func gold_pile_size(i: int) -> int:
	return [1, 3, 6, 10][clampi(i, 0, 3)] if i < 4 else 10 + 2 * (i - 3)


## Arme de l'armurerie la plus chère qu'un montant d'or permet d'acheter (null si aucune).
static func best_weapon_for(gold: int) -> WeaponData:
	var best: WeaponData = null
	for w: WeaponData in WeaponCatalog.all():
		if w.is_gadget() or w.unlock_mode != WeaponData.UNLOCK_SHOP or w.price_gold <= 0 or w.price_gold > gold:
			continue
		if best == null or w.price_gold > best.price_gold:
			best = w
	return best


func _fill_gold_slab() -> void:
	var list := Store.gold_packs()
	if list.is_empty():
		return
	var i := clampi(selected, 0, list.size() - 1)
	var p: Dictionary = list[i]
	_right(_kicker("Or pour l'armurerie"))
	var stage := Control.new()
	stage.name = "SlabArt"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(0, 120)
	_slab_col.add_child(stage)
	var glow := PackGlow.new()
	glow.color = MenuKit.COIN
	glow.strength = 0.5
	glow.rays = 14
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_bottom = -40
	stage.add_child(glow)
	var art := GoldPile.new()
	art.coins = gold_pile_size(i)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_bottom = -52
	stage.add_child(art)
	var amount := MenuKit.label(fmt(int(p["gold"])), 84, MenuKit.COIN, MenuKit.display(), 10)
	amount.name = "Amount"
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	amount.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	amount.grow_vertical = Control.GROW_DIRECTION_BEGIN
	amount.offset_bottom = 8
	stage.add_child(amount)
	_right(_kicker("Pièces d'or"))
	var w := best_weapon_for(int(p["gold"]))
	if w != null:
		_right(_kicker("De quoi acheter"))
		var row := _txt("%s · %s (%s or)" % [w.display_name, w.get_rarity_name(), fmt(w.price_gold)], 17, MenuKit.TEXT, 600)
		row.name = "WeaponHint"
		_right(row)
	_right(_txt("Ton solde : %s gemmes" % (DevMode.SYMBOL if DevMode.is_unlimited() else fmt(Profile.gems)), 16, Color(1, 1, 1, 0.75)))
	action_button = _slab_button("Acheter · %s gemmes" % fmt(int(p["gems"])))
	action_button.pressed.connect(func() -> void: ask_gold_pack(selected))
	_slab_col.add_child(action_button)


func buy_gold_pack(i: int) -> bool:
	var ok := Store.purchase_gold_pack(i)
	MenuKit.sfx(&"coin_spend" if ok else &"error")
	if ok:
		changed.emit()
		rebuild()
	return ok


## Pile de pièces d'or (CurrencyArt.coin, repli : disque doré) : `coins` pièces en pyramide.
class GoldPile extends Control:
	var coins: int = 1:
		set(v):
			coins = maxi(v, 1)
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var tex := CurrencyArt.coin()
		# Rangées de bas en haut : 4, 3, 2, 1 pièces au plus (pyramide), on remplit jusqu'à `coins`.
		var rows: Array[int] = []
		var left := coins
		var width := 1
		while width * (width + 1) / 2 < coins:
			width += 1
		for r in range(width, 0, -1):
			var n := mini(r, left)
			if n <= 0:
				break
			rows.append(n)
			left -= n
		var s := minf(size.x / float(width) * 0.95, size.y / (0.62 * rows.size() + 0.5))
		var base_y := size.y - s * 0.5
		for ri in rows.size():
			var n: int = rows[ri]
			var y := base_y - ri * s * 0.62
			var x0 := size.x * 0.5 - (n - 1) * s * 0.5
			for k in n:
				var c := Vector2(x0 + k * s, y)
				var r := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
				if tex != null:
					draw_texture_rect(tex, r, false)
				else:
					draw_circle(c, s * 0.45, MenuKit.COIN)


# --- Packs à contenu -------------------------------------------------------------------

func _build_bundles() -> void:
	var grid := HBoxContainer.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.add_theme_constant_override("separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(grid)
	var list := Store.bundles()
	for i: int in list.size():
		var b: Dictionary = list[i]
		var top := _top_skin(b)
		var rc := MenuKit.rarity_color(top.rarity if top != null else 2)
		var card := _card(i, rc)
		grid.add_child(card)
		var hero := _first_of_kind(b, SkinData.KIND_CHARACTER)
		if hero != null:
			var t := TextureRect.new()
			t.name = "Hero"
			t.texture = ShopScreen.cropped_preview(ShopScreen.pose_texture(hero))
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			t.offset_top = 30
			t.offset_bottom = -190
			card.add_child(t)
		var wsk := _first_of_kind(b, SkinData.KIND_WEAPON)
		if wsk != null:
			var ic := WeaponIcon.new()
			ic.name = "Weapon"
			ic.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			ic.offset_left = -170
			ic.offset_top = -270
			ic.offset_right = -8
			ic.offset_bottom = -190
			card.add_child(ic)
			ic.set_weapon(ShopScreen.weapon_of(wsk), wsk, false)
		var avail := Store.bundle_available(b["id"])
		if bool(b["once"]):
			_tag(card, "Une seule fois" if avail else "Déjà pris", MenuKit.GOLD, Color(0.07, 0.04, 0.14))
		elif top != null:
			_tag(card, MenuKit.rarity_name(top.rarity), rc, Color(0.08, 0.05, 0.0))
		var foot := VBoxContainer.new()
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		foot.offset_left = 16
		foot.offset_right = -16
		foot.offset_top = -184
		foot.offset_bottom = -72
		foot.alignment = BoxContainer.ALIGNMENT_END
		foot.add_theme_constant_override("separation", 2)
		card.add_child(foot)
		var nm := _big(String(b["name"]).to_upper(), 40)
		foot.add_child(nm)
		var names: Array[String] = []
		for id: StringName in b["skins"]:
			var s := SkinData.get_skin(id)
			names.append(s.display_name if s.kind == SkinData.KIND_CHARACTER else "%s %s" % [_weapon_name(s), s.display_name])
		if int(b["gems"]) > 0:
			names.append("%s gemmes" % fmt(int(b["gems"])))
		var ct := _txt(" · ".join(names), 15, Color(1, 1, 1, 0.8))
		ct.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ct.max_lines_visible = 2
		foot.add_child(ct)
		var bid: StringName = b["id"]
		_price_button(card, i, str(b["price"]), "Valeur %s" % fmt(Store.bundle_value(b)), i == selected,
			func() -> void: ask_bundle(bid))
		if not avail:
			card.modulate = Color(1, 1, 1, 0.55)


static func _first_of_kind(b: Dictionary, k: StringName) -> SkinData:
	for id: StringName in b["skins"]:
		var s := SkinData.get_skin(id)
		if s.kind == k:
			return s
	return null


static func _top_skin(b: Dictionary) -> SkinData:
	var top: SkinData = null
	for id: StringName in b["skins"]:
		var s := SkinData.get_skin(id)
		if top == null or s.rarity > top.rarity:
			top = s
	return top


func _fill_bundles_slab() -> void:
	var list := Store.bundles()
	if list.is_empty():
		return
	var b: Dictionary = list[clampi(selected, 0, list.size() - 1)]
	_right(_kicker("Pack de bienvenue" if bool(b["once"]) else "Pack"))
	_right(_big(String(b["name"]).to_upper(), 72))
	for id: StringName in b["skins"]:
		var s := SkinData.get_skin(id)
		_skin_row(s, "Possédé · remboursé" if Profile.owns_skin(id) else "")
	if int(b["gems"]) > 0:
		var p := PanelContainer.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.35), 0.0, Color(0, 0, 0, 0), 0.0, 14.0, 8.0)
		st.accent_width = 5.0
		st.accent_color = MenuKit.GEM
		p.add_theme_stylebox_override("panel", st)
		p.custom_minimum_size = Vector2(320, 52)
		p.size_flags_horizontal = Control.SIZE_SHRINK_END
		p.add_child(_txt("%s gemmes" % fmt(int(b["gems"])), 17))
		_slab_col.add_child(p)
	var v := Store.bundle_value(b)
	_right(_kicker("Valeur %s gemmes" % fmt(v)))
	if int(b["ref_gems"]) > 0:
		var pill := MenuKit.pill("+%d %% vs %s gemmes au même prix" % [roundi((float(v) / int(b["ref_gems"]) - 1.0) * 100.0), fmt(int(b["ref_gems"]))],
			MenuKit.TEXT, 15, Color(0.227, 0.122, 0.561))
		pill.size_flags_horizontal = Control.SIZE_SHRINK_END
		_slab_col.add_child(pill)
	_spacer()
	var avail := Store.bundle_available(b["id"])
	action_button = _slab_button("Acheter · %s" % b["price"] if avail else "Déjà acheté")
	action_button.disabled = not avail
	action_button.pressed.connect(func() -> void: ask_bundle(b["id"]))
	_slab_col.add_child(action_button)
	_right(_kicker("Aucun avantage en jeu"))


func buy_bundle(id: StringName) -> bool:
	var r := Store.purchase_bundle(id)
	last_result = r
	MenuKit.sfx(&"gold_pickup" if not r.is_empty() else &"error")
	if r.is_empty():
		return false
	changed.emit()
	rebuild()
	return true


# --- Coffres ---------------------------------------------------------------------------

func _build_chests() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 40)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(row)
	# Coffre, nom, garantie
	var a := VBoxContainer.new()
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	a.add_theme_constant_override("separation", 6)
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(a)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.add_child(stage)
	var glow := ChestGlow.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(glow)
	var img := TextureRect.new()
	img.name = "Chest"
	var path := BiomeAssets.find_sprite("chest", BiomeAssets.FALLBACK_CONTAINERS_DIR)
	img.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.offset_left = 40
	img.offset_right = -40
	img.offset_top = 40
	img.offset_bottom = -20
	stage.add_child(img)
	a.add_child(_big("COFFRE DU DÉSERT", 50))
	a.add_child(_kicker("1 skin par coffre · personnages et armes de la boutique", Color(1, 1, 1, 0.7)))
	var pity := Store.chest_pity()
	var hd := HBoxContainer.new()
	hd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.add_child(hd)
	var g := _kicker("Épique ou mieux garanti")
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hd.add_child(g)
	hd.add_child(_kicker("%d / %d" % [Profile.chest_pity_count, pity], MenuKit.GOLD))
	var cells := HBoxContainer.new()
	cells.name = "PityCells"
	cells.add_theme_constant_override("separation", 5)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.add_child(cells)
	for i in pity:
		var c := ColorRect.new()
		c.custom_minimum_size = Vector2(0, 13)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.color = MenuKit.GOLD if i < Profile.chest_pity_count else Color(1, 1, 1, 0.15)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cells.add_child(c)
	# Taux affichés
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_theme_constant_override("separation", 10)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(b)
	b.add_child(_kicker("Taux par coffre", MenuKit.GOLD))
	for e: Array in Store.chest_odds():
		var r := int(e[0])
		var p := PanelContainer.new()
		p.name = "Odds%d" % r
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.75), 0.0, Color(0, 0, 0, 0), 0.0, 16.0, 6.0)
		st.accent_width = 5.0
		st.accent_color = MenuKit.rarity_color(r)
		p.add_theme_stylebox_override("panel", st)
		p.custom_minimum_size.y = 70
		b.add_child(p)
		var l := HBoxContainer.new()
		l.add_theme_constant_override("separation", 16)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(l)
		var pct := _big("%s %%" % str(snappedf(float(e[1]) * 100.0, 0.1)).trim_suffix(".0"), 36)
		pct.custom_minimum_size.x = 96
		pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_child(pct)
		var t := VBoxContainer.new()
		t.alignment = BoxContainer.ALIGNMENT_CENTER
		t.add_theme_constant_override("separation", 0)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_child(t)
		var rn := _txt(MenuKit.rarity_name(r), 18, MenuKit.rarity_color(r), 700)
		rn.uppercase = true
		t.add_child(rn)
		t.add_child(_txt("%d skins" % Store.chest_pool(r).size(), 16, Color(1, 1, 1, 0.6)))
	var note := _txt("Les coffres ne s'achètent pas : ils se gagnent en jouant. Skin déjà possédé : %d %% de son prix remboursé en gemmes. Aucun avantage en jeu."
		% roundi(float(Balance.get_value("chests", "duplicate_refund", 0.5)) * 100.0), 16, Color(1, 1, 1, 0.65))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(note)


func _fill_chests_slab() -> void:
	_right(_kicker("Coffres gratuits"))
	_right(_big(str(Profile.free_chests), 96)).name = "Count"
	var every := Store.chest_every()
	var l := _txt("1 coffre offert toutes les %d extractions réussies." % every, 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_right(l)
	_right(_kicker("Prochain : %d / %d extractions" % [Profile.chest_progress, every], MenuKit.TEXT))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = every
	bar.value = Profile.chest_progress
	bar.custom_minimum_size = Vector2(320, 10)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_END
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(MenuKit.NIGHT_DEEP, 0.35)
	var fg := StyleBoxFlat.new()
	fg.bg_color = MenuKit.TEXT
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slab_col.add_child(bar)
	_spacer()
	var has := Profile.free_chests > 0
	action_button = _slab_button("Ouvrir" if has else "Aucun coffre", has)
	action_button.disabled = not has
	action_button.pressed.connect(func() -> void: open_chest())
	_slab_col.add_child(action_button)
	_right(_kicker("Jamais vendus"))


## Ouvre un coffre gratuit et affiche le skin obtenu. Renvoie le résultat de Store.open_chest.
func open_chest(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := Store.open_chest(rng)
	last_result = r
	if r.is_empty():
		MenuKit.sfx(&"error")
		return r
	MenuKit.sfx(&"gold_pickup")
	changed.emit()
	rebuild()
	_show_reveal(r)
	return r


func _show_reveal(r: Dictionary) -> void:
	var s: SkinData = r["skin"]
	var rc := MenuKit.rarity_color(s.rarity)
	var veil := ColorRect.new()
	veil.name = "Reveal"
	veil.color = Color(MenuKit.NIGHT_DEEP, 0.9)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(veil)
	reveal = veil
	var glow := ChestGlow.new()
	glow.color = rc
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_bottom = -200
	veil.add_child(glow)
	if s.kind == SkinData.KIND_CHARACTER:
		var t := TextureRect.new()
		t.texture = ShopScreen.cropped_preview(ShopScreen.pose_texture(s))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t.offset_top = 10
		t.offset_bottom = -210
		veil.add_child(t)
	else:
		var ic := WeaponIcon.new()
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 200
		ic.offset_right = -200
		ic.offset_top = 60
		ic.offset_bottom = -220
		veil.add_child(ic)
		ic.set_weapon(ShopScreen.weapon_of(s), s, false)
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_top = -200
	foot.offset_bottom = -16
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 4)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.add_child(foot)
	var k := _kicker(MenuKit.rarity_name(s.rarity), rc)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(k)
	var title := skin_title(s)
	var n := _big(title.to_upper(), 56)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(n)
	var sub := "Déjà possédé · +%d gemmes" % int(r["refunded"]) if bool(r["duplicate"]) else "Nouveau skin"
	var sl := _kicker(sub, Color(1, 1, 1, 0.75))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(sl)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(btns)
	if not bool(r["duplicate"]):
		var eq := MenuKit.button("Équiper", MenuKit.Style.PRIMARY, 24, Vector2(220, 64))
		eq.name = "Equip"
		eq.pressed.connect(func() -> void:
			if s.kind == SkinData.KIND_CHARACTER:
				Profile.equip_character_skin(s.id)
			else:
				WeaponSkin.equip(s.id)
			MenuKit.sfx(&"item_equip", -2.0)
			close_reveal())
		btns.add_child(eq)
	var ok := MenuKit.button("Fermer", MenuKit.Style.SECONDARY, 24, Vector2(220, 64))
	ok.name = "Close"
	ok.pressed.connect(close_reveal)
	btns.add_child(ok)
	veil.modulate.a = 0.0
	create_tween().tween_property(veil, "modulate:a", 1.0, 0.2)
	ok.grab_focus.call_deferred()


func close_reveal() -> void:
	if is_instance_valid(reveal):
		reveal.queue_free()
	reveal = null


func _fill_slab() -> void:
	match mode:
		MODE_PACKS:
			_fill_bundles_slab()
		MODE_CHESTS:
			_fill_chests_slab()
		MODE_GOLD:
			_fill_gold_slab()
		_:
			_fill_gems_slab()


## Halo radial (coffre, révélation).
class ChestGlow extends Control:
	var color: Color = Color(0.725, 0.549, 1.0)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		for i in 12:
			var k := 1.0 - i / 12.0
			draw_circle(c, r * k, Color(color, 0.05 + 0.03 * (1.0 - k)))


## Lueur radiale (et rayons pour les gros packs) derrière l'illustration d'un pack de gemmes. Statique.
class PackGlow extends Control:
	var color: Color = MenuKit.GEM
	## Alpha de la lueur au centre (0-1).
	var strength: float = 0.3
	## Nombre de rayons (0 = aucun).
	var rays: int = 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.58
		if rays > 0:
			var far := size.length()
			var half := PI / float(rays) * 0.42
			for k in rays:
				var a := TAU * float(k) / float(rays) - PI * 0.5
				draw_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - half) * far, c + Vector2.from_angle(a + half) * far]),
					PackedColorArray([Color(color, strength * 0.3), Color(color, 0.0), Color(color, 0.0)]))
		for i in 14:
			var k := 1.0 - float(i) / 14.0
			draw_circle(c, r * k, Color(color, strength * 0.09 * (1.0 - k * 0.6)), true, -1.0, true)