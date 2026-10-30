class_name ShopOffers
extends Control
## Onglets « Packs », « Coffres » et « Gemmes » de la boutique (maquettes Packs, ShopChests, Gems,
## direction D) : cartes encre à coin coupé à gauche, bandeau violet en biais à droite avec
## l'offre choisie et son bouton d'action. Toute la logique est dans Store ; cet écran affiche
## et appelle. Les coffres ne se vendent pas : ils se gagnent en jouant (Store.open_chest).

signal changed
## Demande d'aller sur un autre onglet de la boutique (ex. « Gemmes »).
signal open_tab(tab: StringName)

const MODE_GEMS := &"gems"
const MODE_PACKS := &"packs"
const MODE_CHESTS := &"chests"

var mode: StringName = MODE_GEMS
var selected: int = 0
## Cartes cliquables (packs de gemmes ou packs à contenu), dans l'ordre des offres.
var cards: Array[Button] = []
## Bouton d'action du bandeau (Acheter / Ouvrir).
var action_button: Button = null
## Fenêtre de révélation du dernier coffre ouvert (null si fermée).
var reveal: Control = null
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
		selected = mini(2, Store.packs().size() - 1)
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


## Carte encre à coin haut droit coupé ; anneau blanc quand elle est choisie.
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
	b.add_theme_stylebox_override("normal", mk.call(bg, 2.5 if on else 0.0))
	b.add_theme_stylebox_override("hover", mk.call(bg.lightened(0.06), 2.5 if on else 1.0))
	b.add_theme_stylebox_override("pressed", mk.call(bg.darkened(0.1), 2.5))
	b.add_theme_stylebox_override("hover_pressed", mk.call(bg.darkened(0.1), 2.5))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), 2.5))
	b.pressed.connect(func() -> void: select(i))
	MenuKit.add_feedback(b, 1.02)
	cards.append(b)
	return b


## Bandeau de prix en bas d'une carte : « libellé ……… prix » (violet si la carte est choisie).
func _price_strip(card: Control, left: String, right: String, on: bool) -> void:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := CutBox.make(MenuKit.VIOLET if on else Color(1, 1, 1, 0.1), 12.0, Color(0, 0, 0, 0), 0.0, 14.0, 4.0)
	st.corners = CutBox.CUT_TOP_LEFT
	p.add_theme_stylebox_override("panel", st)
	p.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	p.offset_left = 12
	p.offset_right = -12
	p.offset_top = -62
	p.offset_bottom = -12
	card.add_child(p)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var l := _txt(left, 15, Color(1, 1, 1, 0.75))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var r := _txt(right, 22, MenuKit.TEXT, 700)
	r.name = "Price"
	r.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if left.is_empty():
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(r)


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
		var st := CutBox.make(Color(MenuKit.VIOLET, 0.35), 0.0, Color(0, 0, 0, 0), 0.0, 16.0, 10.0)
		st.accent_width = 4.0
		st.accent_color = MenuKit.GOLD
		ban.add_theme_stylebox_override("panel", st)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ban.add_child(row)
		row.add_child(_kicker("Premier achat", MenuKit.GOLD))
		row.add_child(_kicker("Gemmes doublées sur le pack de ton choix · une seule fois"))
		col.add_child(ban)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	var packs := Store.packs()
	var cheapest := 1 << 30
	for k: StringName in [SkinData.KIND_CHARACTER, SkinData.KIND_WEAPON]:
		for s: SkinData in SkinData.shop_skins(k):
			if s.price_gems > 0:
				cheapest = mini(cheapest, s.price_gems)
	for i: int in packs.size():
		var p: Dictionary = packs[i]
		var card := _card(i, MenuKit.GEM.lerp(MenuKit.VIOLET, clampf(i / 3.0, 0.0, 1.0)))
		grid.add_child(card)
		var c := VBoxContainer.new()
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.offset_top = 30
		c.offset_bottom = -74
		c.add_theme_constant_override("separation", 2)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(c)
		var gems_row := HBoxContainer.new()
		gems_row.alignment = BoxContainer.ALIGNMENT_CENTER
		gems_row.add_theme_constant_override("separation", -10)
		gems_row.custom_minimum_size.y = 96
		gems_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(gems_row)
		for k: int in mini(i + 1, 4):
			var g := GemIcon.new()
			var px := 56.0 - k * 6.0
			g.custom_minimum_size = Vector2(px, px)
			g.size_flags_vertical = Control.SIZE_SHRINK_END
			gems_row.add_child(g)
		var n := _big(fmt(int(p["gems"])), 56)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(n)
		var u := _kicker("Gemmes", Color(1, 1, 1, 0.65))
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(u)
		var now := Store.pack_gems_now(i)
		var best := best_affordable(now)
		var buys := "Complète un solde" if now < cheapest or best == null else "De quoi prendre %s" % skin_title(best)
		var bl := _txt(buys, 16, MenuKit.GOLD if best != null and now >= cheapest else Color(1, 1, 1, 0.5))
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(bl)
		var pct := pack_bonus_pct(i)
		if pct > 0:
			_tag(card, "+%d %%" % pct, MenuKit.GOLD, Color(0.07, 0.04, 0.14))
		_price_strip(card, "", str(p["price"]), i == selected)


func _fill_gems_slab() -> void:
	var packs := Store.packs()
	if packs.is_empty():
		return
	var i := clampi(selected, 0, packs.size() - 1)
	var first := Store.first_bonus_available()
	_right(_kicker("Ton premier pack" if first else "Pack choisi"))
	_right(_big(fmt(Store.pack_gems_now(i)), 96)).name = "Amount"
	_right(_kicker("Gemmes · doublées" if first else "Gemmes"))
	var pct := pack_bonus_pct(i)
	if pct > 0:
		var pill := MenuKit.pill("+%d %% par rapport au petit pack" % pct, MenuKit.TEXT, 16, Color(0.227, 0.122, 0.561))
		pill.size_flags_horizontal = Control.SIZE_SHRINK_END
		_slab_col.add_child(pill)
	var best := best_affordable(Store.pack_gems_now(i))
	if best != null:
		_right(_kicker("De quoi t'offrir"))
		_skin_row(best)
	else:
		var l := _txt("Ce pack complète un solde : le skin le moins cher coûte plus.", 17)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_right(l)
	_spacer()
	action_button = _slab_button("Acheter · %s" % packs[i]["price"])
	action_button.pressed.connect(func() -> void: buy_pack(selected))
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


func buy_pack(i: int) -> bool:
	var ok := Store.purchase_pack(i)
	MenuKit.sfx(&"gold_pickup" if ok else &"error")
	if ok:
		changed.emit()
		rebuild()
	return ok


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
		_price_strip(card, "Valeur %s" % fmt(Store.bundle_value(b)), str(b["price"]), i == selected)
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
	action_button.pressed.connect(func() -> void: buy_bundle(b["id"]))
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
