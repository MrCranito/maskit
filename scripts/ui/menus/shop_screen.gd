class_name ShopScreen
extends Control
## Boutique cosmétique : onglets Personnages / (Armes) / Gemmes.
##  - Personnages (planche docs/reference/personnages_skins.jpg) : grand panneau du personnage de
##    base à gauche (aperçu animé), puis cartes verticales des skins (personnage en pied, nom,
##    bandeau de rareté, Acheter / Équiper / Équipé). Skins : SkinData.all_of_kind("character")
##    (data/skins/char_*.tres) ; aperçu = SkinData.preview, sinon planche du skin (HeroPreview).
##  - Armes : skins d'armes, onglet masqué tant que [shop] weapon_skins_enabled = false.
##  - Achat avec confirmation ; prix en gemmes.
##  - Gemmes : packs ([shop] packs) via Store.purchase_pack (paiement SIMULÉ, badge visible).
## Message permanent : « Purement cosmétique : aucun avantage en jeu ».

const ALL_TABS: Array[StringName] = [&"character", &"weapon", &"gems"]
const TAB_TITLES := {&"character": "Personnages", &"weapon": "Armes", &"gems": "Gemmes"}

static var last_tab: StringName = &"character"

## Onglets visibles (l'onglet Armes n'apparaît que si les skins d'armes sont activés).
var tabs: Array[StringName] = []
var current_tab: StringName = &""
var tab_chips: Dictionary = {}
var cards: Array[Control] = []          ## cartes de l'onglet courant (skins ou packs)
var action_buttons: Dictionary = {}     ## skin id → Button
var pack_buttons: Array[Button] = []
var back_button: Button = null
var gem_counter: GemCounter = null
var simulated_badge: Control = null
var _modal: ModalPanel = null
var _scroll: ScrollContainer = null
var _row: GridContainer = null
## Onglet Personnages : panneau de base + grille des skins.
var _chars: HBoxContainer = null
var _char_grid: GridContainer = null
var _char_scroll: ScrollContainer = null
var _base_preview: HeroPreview = null
## Skin de base (char_default) s'il existe.
var base_skin: SkinData = null
var _note: Label = null
## Arme d'exemple pour l'aperçu des skins (première de la catégorie dans le catalogue).
var _sample_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	var bg := MenuBackground.new()
	bg.dim = Balance.get_float("menu", "screen_dim", 0.45) + 0.1
	add_child(bg)
	for t: StringName in ALL_TABS:
		if t != &"weapon" or WeaponSkin.is_enabled():
			tabs.append(t)
	_build()
	show_tab(last_tab if tabs.has(last_tab) else &"character")
	MenuKit.fade_in(self)
	back_button.grab_focus.call_deferred()


func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	back_button = MenuKit.back_button("Menu")
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var t := MenuKit.title("Boutique", 40)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tab_row)
	var group := ButtonGroup.new()
	for tab: StringName in tabs:
		var b := MenuKit.chip(String(TAB_TITLES[tab]), MenuKit.GEM if tab == &"gems" else MenuKit.GOLD, group)
		b.custom_minimum_size = Vector2(150, 58)
		b.add_theme_font_size_override("font_size", 20)
		b.toggled.connect(func(on: bool) -> void:
			if on and current_tab != tab:
				MenuKit.sfx(&"tick")
				show_tab(tab))
		tab_row.add_child(b)
		tab_chips[tab] = b
	gem_counter = GemCounter.new()
	gem_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_counter.pressed.connect(func() -> void: show_tab(&"gems"))
	head.add_child(gem_counter)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 14
	root.add_child(_scroll)
	_row = GridContainer.new()
	_row.add_theme_constant_override("h_separation", 14)
	_row.add_theme_constant_override("v_separation", 14)
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_row)
	_scroll.resized.connect(_update_columns)
	_chars = HBoxContainer.new()
	_chars.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chars.add_theme_constant_override("separation", 14)
	_chars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_chars)

	# Pied : rappel cosmétique + badge paiement simulé
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 14)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(foot)
	var fair := MenuKit.pill("Purement cosmétique : aucun avantage en jeu", Color(MenuKit.NIGHT, 0.92), 17,
		MenuKit.GOOD.lightened(0.3), Color(MenuKit.GOOD, 0.6))
	fair.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(fair)
	_note = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(750), 3)
	_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_note)
	simulated_badge = MenuKit.pill("Paiement simulé (test)", Color(0.5, 0.32, 0.05, 0.95), 15, MenuKit.TEXT,
		Color(1.0, 0.75, 0.3, 0.9))
	simulated_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	simulated_badge.visible = Store.SIMULATED
	foot.add_child(simulated_badge)


# --- Onglets -------------------------------------------------------------------------

func show_tab(tab: StringName) -> void:
	current_tab = tab
	last_tab = tab
	var b: Button = tab_chips.get(tab)
	if b != null and not b.button_pressed:
		b.set_pressed_no_signal(true)
	for holder: Node in [_row, _chars]:
		for c: Node in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
	cards.clear()
	action_buttons.clear()
	pack_buttons.clear()
	_char_grid = null
	_scroll.visible = tab != &"character"
	_chars.visible = tab == &"character"
	match tab:
		&"character":
			_build_characters()
			_note.text = "Les skins changent seulement l'apparence de ton personnage."
		&"gems":
			var packs := Store.packs()
			for i: int in packs.size():
				_add_card(_pack_card(i, packs[i]))
			_note.text = "Les gemmes s'achètent ici ou se gagnent à chaque extraction réussie."
		_:
			var kind: StringName = SkinData.KIND_WEAPON
			for s: SkinData in SkinData.all_of_kind(kind):
				_add_card(_skin_card(s, kind))
			_note.text = "Les skins changent seulement l'apparence." if cards.size() > 1 \
				else "De nouveaux skins arrivent bientôt."
	_scroll.scroll_vertical = 0
	_update_columns()
	# Entrée en cascade (courte)
	for i: int in cards.size():
		var c: Control = cards[i]
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, 0.18).set_delay(0.03 * i)
	_refresh_states()


## Colonnes de la grille selon la largeur ; cartes étirées pour remplir la ligne.
func _update_columns() -> void:
	if _row == null:
		return
	if current_tab == &"character":
		_update_char_columns()
		return
	var w: float = _scroll.size.x if _scroll.size.x > 0.0 else 1200.0
	var cw: float = Balance.get_float("menu", "shop_card_width", 220.0)
	for c: Control in cards:
		cw = maxf(cw, c.get_combined_minimum_size().x)
	_row.columns = maxi(1, floori((w + 14.0) / (cw + 14.0)))
	if current_tab == &"gems":
		_row.columns = maxi(1, mini(_row.columns, cards.size()))
	# Une seule rangée : les cartes occupent toute la hauteur (grands aperçus).
	var one_row: bool = cards.size() <= _row.columns
	_row.size_flags_vertical = Control.SIZE_EXPAND_FILL if one_row else Control.SIZE_FILL
	for c: Control in cards:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL if one_row else Control.SIZE_FILL


func _add_card(c: Control) -> void:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(c)
	cards.append(c)


func _card_panel(rarity: int, glow: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var st := MenuKit.rarity_style(rarity, glow, 18)
	st.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "shop_card_width", 220.0),
		Balance.get_float("menu", "shop_card_height", 268.0))
	return p


# --- Onglet Personnages (planche personnages_skins.jpg) ---------------------------------

static var _crop_cache: Dictionary = {}


## Aperçu recadré sur sa zone utile (les previews ont de grandes marges transparentes) :
## le personnage remplit la carte. Calculé une fois par texture.
static func cropped_preview(t: Texture2D) -> Texture2D:
	if t == null:
		return null
	if _crop_cache.has(t):
		return _crop_cache[t]
	var out: Texture2D = t
	var img := t.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var r := img.get_used_rect()
		if r.size.x > 0 and r.size.y > 0 and r.size != img.get_size():
			var a := AtlasTexture.new()
			a.atlas = t
			a.region = Rect2(r.grow(2)).intersection(Rect2(Vector2.ZERO, img.get_size()))
			out = a
	_crop_cache[t] = out
	return out


## Skins de personnage hors skin de base, triés par rareté puis prix (ordre de la planche).
func character_skins() -> Array[SkinData]:
	var out: Array[SkinData] = []
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_CHARACTER):
		if s.id == HeroSkin.DEFAULT_SKIN_ID:
			continue
		out.append(s)
	out.sort_custom(func(a: SkinData, b: SkinData) -> bool:
		if a.rarity != b.rarity:
			return a.rarity < b.rarity
		return a.price_gems < b.price_gems if a.price_gems != b.price_gems else String(a.id) < String(b.id))
	return out


func _build_characters() -> void:
	base_skin = SkinData.get_skin(HeroSkin.DEFAULT_SKIN_ID)
	_chars.add_child(_base_panel())
	_char_scroll = ScrollContainer.new()
	_char_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_char_scroll.scroll_deadzone = 14
	_chars.add_child(_char_scroll)
	_char_grid = GridContainer.new()
	_char_grid.add_theme_constant_override("h_separation", 12)
	_char_grid.add_theme_constant_override("v_separation", 12)
	_char_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_char_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_char_scroll.add_child(_char_grid)
	_char_scroll.resized.connect(_update_char_columns)
	var list := character_skins()
	for s: SkinData in list:
		var c := _character_card(s)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_char_grid.add_child(c)
		cards.append(c)
	if list.is_empty():
		var l := MenuKit.label("De nouveaux skins arrivent bientôt.", 20, MenuKit.TEXT_DIM, MenuKit.nunito(800), 3)
		_char_grid.add_child(l)
	_update_char_columns()


## Colonnes de skins : 4 en 1280 px (2 rangées pour 8 skins), plus sur écran large ;
## hauteur des cartes calée pour que deux rangées tiennent sans défiler.
func _update_char_columns() -> void:
	if _char_grid == null or _char_scroll == null:
		return
	var w: float = _char_scroll.size.x if _char_scroll.size.x > 0.0 else 900.0
	var h: float = _char_scroll.size.y if _char_scroll.size.y > 0.0 else 560.0
	var cw: float = Balance.get_float("menu", "skin_card_width", 168.0)
	var cols: int = maxi(1, floori((w + 12.0) / (cw + 12.0)))
	var n: int = maxi(cards.size(), 1)
	# Préférer des rangées équilibrées (8 skins : 4 × 2 plutôt que 5 + 3).
	var rows: int = ceili(n / float(cols))
	cols = ceili(n / float(rows))
	_char_grid.columns = cols
	var ch: float = maxf(Balance.get_float("menu", "skin_card_min_height", 250.0), floorf((h - 12.0 * (rows - 1)) / rows))
	if rows > 2:
		ch = Balance.get_float("menu", "skin_card_min_height", 250.0)
	for c: Control in cards:
		c.custom_minimum_size.y = ch


## Grand panneau du personnage de base (aperçu animé qui tourne).
func _base_panel() -> Control:
	var p := PanelContainer.new()
	var st := MenuKit.panel_style(Color(0.06, 0.08, 0.14, 0.96), Color(1, 1, 1, 0.16), 14, 1, 0)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "base_panel_width", 300.0), 0)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stack)
	stack.add_child(MenuKit.rarity_backdrop(0))
	_base_preview = HeroPreview.new(false)
	_base_preview.height_ratio = Balance.get_float("menu", "base_preview_ratio", 1.35)
	_base_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_base_preview.offset_top = 100
	_base_preview.offset_bottom = -110
	stack.add_child(_base_preview)
	_base_preview.set_skin(base_skin)
	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 14
	head.add_theme_constant_override("separation", 0)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	head.add_child(MenuKit.label("PERSONNAGE DE BASE", 15, MenuKit.TEXT_DIM, MenuKit.nunito(900)))
	var nm := MenuKit.label(base_skin.display_name if base_skin != null else "Soldat standard", 26,
		MenuKit.TEXT, MenuKit.nunito(1000), 4)
	head.add_child(nm)
	var d := MenuKit.label(base_skin.description if base_skin != null and not base_skin.description.is_empty()
		else "Un équipement polyvalent pour toutes les situations.", 14, MenuKit.TEXT_DIM, MenuKit.nunito(700))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.max_lines_visible = 2
	head.add_child(d)
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 14
	foot.offset_right = -14
	foot.offset_bottom = -14
	foot.add_theme_constant_override("separation", 8)
	stack.add_child(foot)
	var band := MenuKit.rarity_band(0, 15, 28)
	(band.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(6)
	foot.add_child(band)
	var b := MenuKit.button("", MenuKit.Style.SECONDARY, 20, Vector2(0, 64))
	MenuKit.tighten(b, 10)
	foot.add_child(b)
	var id: StringName = base_skin.id if base_skin != null else &""
	b.pressed.connect(func() -> void: _on_skin_action(id))
	action_buttons[id] = b
	b.set_meta(&"skin_id", String(id))
	return p


## Carte verticale d'un skin de personnage : personnage en pied sur fond teinté de rareté,
## nom en capitales, bandeau de rareté, bouton d'action.
func _character_card(s: SkinData) -> Control:
	var rc: Color = MenuKit.rarity_color(s.rarity)
	var p := PanelContainer.new()
	var st := MenuKit.panel_style(Color(0.06, 0.08, 0.14, 0.97), Color(rc, 0.85), 10, 2, 0)
	st.shadow_offset = Vector2.ZERO
	st.shadow_color = Color(rc, 0.4 if s.rarity >= 3 else 0.15)
	st.shadow_size = 10 if s.rarity >= 3 else 4
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "skin_card_width", 168.0), 250)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stack)
	stack.add_child(MenuKit.rarity_backdrop(s.rarity))
	var bottom_h: float = 104.0
	if s.preview != null:
		var tr := TextureRect.new()
		tr.name = "Preview"
		tr.texture = cropped_preview(s.preview)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_top = 18
		tr.offset_left = 14
		tr.offset_right = -14
		tr.offset_bottom = -bottom_h - 6
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(tr)
	else:
		var hp := HeroPreview.new(false)
		hp.name = "Preview"
		hp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hp.offset_top = 8
		hp.offset_bottom = -bottom_h
		stack.add_child(hp)
		hp.set_skin(s)
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 10
	foot.offset_right = -10
	foot.offset_bottom = -10
	foot.add_theme_constant_override("separation", 4)
	stack.add_child(foot)
	var n := MenuKit.label(s.display_name.to_upper(), 16, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(n)
	var band := MenuKit.rarity_band(s.rarity, 14, 24)
	(band.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(5)
	foot.add_child(band)
	var b := MenuKit.button("", MenuKit.Style.SECONDARY, 17, Vector2(0, 46))
	MenuKit.tighten(b, 6)
	b.custom_minimum_size.x = 0
	foot.add_child(b)
	b.pressed.connect(func() -> void: _on_skin_action(s.id))
	action_buttons[s.id] = b
	b.set_meta(&"skin_id", String(s.id))
	return p


## Carte d'un skin d'arme (onglet Armes, si activé).
func _skin_card(s: SkinData, kind: StringName) -> Control:
	var rarity: int = s.rarity if s != null else 0
	var p := _card_panel(rarity, s != null and rarity >= 3)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	var stage := Panel.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(0, 110)
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(MenuKit.NIGHT_DEEP, 0.7)
	ss.set_corner_radius_all(12)
	stage.add_theme_stylebox_override("panel", ss)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	col.add_child(stage)
	if kind == SkinData.KIND_CHARACTER:
		var hp := HeroPreview.new(false)
		hp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.add_child(hp)
		hp.set_skin(s)
	else:
		var ic := WeaponIcon.new()
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 10
		ic.offset_right = -10
		stage.add_child(ic)
		ic.set_weapon(_sample_weapon(s.weapon_category), s, false)
	var n := MenuKit.label(s.display_name if s != null else "Tenue d'origine", 19, MenuKit.TEXT, MenuKit.nunito(1000), 3)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	col.add_child(n)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	col.add_child(meta)
	var rc: Color = MenuKit.rarity_color(rarity)
	meta.add_child(MenuKit.pill(MenuKit.rarity_name(rarity), rc.darkened(0.35), 13))
	if kind == SkinData.KIND_WEAPON:
		var cat: String = "Toutes les armes" if s.weapon_category == SkinData.ANY_CATEGORY \
			else String(WeaponData.CATEGORY_NAMES.get(s.weapon_category, s.weapon_category))
		var cl := MenuKit.label(cat, 14, MenuKit.TEXT_DIM, MenuKit.nunito(800))
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cl.clip_text = true
		cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		meta.add_child(cl)
	var b := MenuKit.button("", MenuKit.Style.SECONDARY, 20, Vector2(0, 64))
	MenuKit.tighten(b, 10)
	b.custom_minimum_size.x = 0
	col.add_child(b)
	var id: StringName = s.id if s != null else &""
	b.pressed.connect(func() -> void: _on_skin_action(id))
	action_buttons[id] = b
	b.set_meta(&"skin_id", String(id))
	return p


func _pack_card(i: int, pack: Dictionary) -> Control:
	var p := _card_panel(mini(i + 1, 4), i >= 2)
	p.custom_minimum_size.y = Balance.get_float("menu", "shop_pack_height", 340.0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(col)
	var stage := HBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", -26)
	col.add_child(stage)
	for k: int in mini(i + 1, 4):
		var g := GemIcon.new()
		g.custom_minimum_size = Vector2(76, 76) if k == 0 else Vector2(60, 60)
		g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stage.add_child(g)
	var n := MenuKit.label("%d gemmes" % int(pack["gems"]), 28, MenuKit.GEM.lightened(0.4), MenuKit.nunito(1000), 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	var b := MenuKit.button(String(pack["price"]), MenuKit.Style.PRIMARY, 24, Vector2(0, 68))
	col.add_child(b)
	b.pressed.connect(func() -> void: buy_pack(i))
	pack_buttons.append(b)
	return p


## Arme d'exemple pour l'aperçu d'un skin d'arme.
func _sample_weapon(cat: StringName) -> WeaponData:
	if _sample_cache.has(cat):
		return _sample_cache[cat]
	var best: WeaponData = null
	for w: WeaponData in WeaponCatalog.all():
		if cat == SkinData.ANY_CATEGORY or w.category == cat:
			if best == null or w.rarity > best.rarity:
				best = w
	if best == null:
		best = WeaponData.new()
		best.category = cat if cat != SkinData.ANY_CATEGORY else WeaponData.CAT_RIFLE
	_sample_cache[cat] = best
	return best


# --- États et achats ------------------------------------------------------------------

## État d'un skin : "buy", "equip", "equipped".
func skin_state(s: SkinData) -> String:
	if s == null or s.id == HeroSkin.DEFAULT_SKIN_ID:
		var cur := String(Profile.skin_character)
		return "equipped" if cur.is_empty() or cur == String(HeroSkin.DEFAULT_SKIN_ID) else "equip"
	if not Profile.owns_skin(s.id):
		return "buy"
	if s.kind == SkinData.KIND_CHARACTER:
		return "equipped" if Profile.skin_character == s.id else "equip"
	return "equipped" if str(Profile.skin_weapons.get(String(s.weapon_category), "")) == String(s.id) else "equip"


func _refresh_states() -> void:
	for id: StringName in action_buttons:
		var b: Button = action_buttons[id]
		var sid: String = str(b.get_meta(&"skin_id", ""))
		var s: SkinData = SkinData.get_skin(StringName(sid)) if not sid.is_empty() else null
		match skin_state(s):
			"buy":
				b.text = "%d  gemmes" % s.price_gems if s.price_gems > 0 else "Obtenir"
				b.disabled = false
				b.modulate = Color.WHITE if Profile.gems >= s.price_gems else Color(1, 1, 1, 0.65)
				_style_action(b, MenuKit.Style.PRIMARY)
			"equip":
				b.text = "Équiper"
				b.disabled = false
				b.modulate = Color.WHITE
				_style_action(b, MenuKit.Style.SECONDARY)
			_:
				b.text = "Équipé"
				b.disabled = true
				b.modulate = Color.WHITE
				_style_action(b, MenuKit.Style.GHOST)


func _style_action(b: Button, style: MenuKit.Style) -> void:
	if int(b.get_meta(&"style", -1)) == int(style):
		return
	b.set_meta(&"style", int(style))
	var ref := MenuKit.button("", style, 20, Vector2.ZERO)
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, ref.get_theme_stylebox(st))
	ref.free()
	MenuKit.tighten(b, 10)


func _on_skin_action(id: StringName) -> void:
	var s: SkinData = SkinData.get_skin(id) if not String(id).is_empty() else null
	if s != null and s.kind == SkinData.KIND_CHARACTER and _base_preview != null and is_instance_valid(_base_preview):
		_base_preview.set_skin(s)  # aperçu en grand du skin touché
	match skin_state(s):
		"buy":
			ask_buy(s)
		"equip":
			equip(s)


## Ouvre la confirmation d'achat (ou explique qu'il manque des gemmes).
func ask_buy(s: SkinData) -> ModalPanel:
	if s == null:
		return null
	if Profile.gems < s.price_gems:
		var missing: int = s.price_gems - Profile.gems
		var m := ConfirmPanel.new("Pas assez de gemmes",
			"Il te manque %d gemmes pour « %s ». Gagne-en en t'extrayant, ou prends un pack." % [missing, s.display_name],
			"Voir les gemmes")
		m.confirmed.connect(func() -> void: show_tab(&"gems"))
		MenuKit.sfx(&"error")
		return _open_modal(m)
	var m2 := ConfirmPanel.new("Acheter ce skin ?",
		"« %s » pour %d gemmes.\nPurement cosmétique : aucun avantage en jeu." % [s.display_name, s.price_gems],
		"Acheter")
	m2.confirmed.connect(func() -> void: buy(s))
	return _open_modal(m2)


## Achète (sans confirmation) puis équipe. Renvoie false si impossible.
func buy(s: SkinData) -> bool:
	if s == null or not Profile.buy_skin(s.id):
		MenuKit.sfx(&"error")
		return false
	MenuKit.sfx(&"coin_spend")
	equip(s)
	return true


func equip(s: SkinData) -> bool:
	var ok: bool
	if s == null or s.id == HeroSkin.DEFAULT_SKIN_ID:
		ok = Profile.equip_character_skin(&"")
	elif s.kind == SkinData.KIND_CHARACTER:
		ok = Profile.equip_character_skin(s.id)
	else:
		ok = Profile.equip_weapon_skin(s.id)
	if ok:
		MenuKit.sfx(&"item_equip", -2.0)
		var b: Button = action_buttons.get(s.id if s != null else &"")
		if b != null and b.is_inside_tree():
			var card := b.get_parent().get_parent().get_parent() as Control
			if current_tab != &"character":
				card = b.get_parent().get_parent() as Control
			card.pivot_offset = card.size * 0.5
			create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
				.tween_property(card, "scale", Vector2.ONE, 0.3).from(Vector2(1.06, 1.06))
	_refresh_states()
	return ok


## Achat d'un pack de gemmes (paiement simulé).
func buy_pack(i: int) -> bool:
	var ok := Store.purchase_pack(i)
	MenuKit.sfx(&"gold_pickup" if ok else &"error")
	_refresh_states()
	return ok


func _open_modal(m: ModalPanel) -> ModalPanel:
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = m
	add_child(m)
	return m


func go_back() -> void:
	MenuKit.sfx(&"back")
	MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not is_instance_valid(_modal):
		get_viewport().set_input_as_handled()
		go_back()
