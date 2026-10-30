class_name ShopScreen
extends Control
## Boutique cosmétique : onglets Personnages / Armes / Gemmes.
##  - Personnages (planche docs/reference/personnages_skins.jpg) : panneau d'aperçu à gauche
##    (MÊME rendu que le lobby : pose haute résolution + idle procédurale, HeroPreview), grille de
##    cartes à droite (personnage en pied, nom, bandeau de rareté, Acheter / Équiper / Équipé).
##    Skins vendus = SkinData source « shop ». Les skins du pass de combat n'y sont pas vendus :
##    ils n'apparaissent qu'une fois obtenus (badge « Pass »), sinon « Dans le pass » → écran du pass.
##  - Armes : skins PAR ARME (SkinData weapon_id), cartes triées par arme ; aperçu à gauche sur
##    l'arme (icône + arme tenue en jeu), équiper / retirer.
##  - Gemmes : packs ([shop] packs) via Store.purchase_pack (paiement SIMULÉ, badge visible).
## Message permanent : « Purement cosmétique : aucun avantage en jeu ».

const ALL_TABS: Array[StringName] = [&"character", &"weapon", &"gems"]
const TAB_TITLES := {&"character": "Personnages", &"weapon": "Armes", &"gems": "Gemmes"}

static var last_tab: StringName = &"character"
## Skin à mettre en avant à l'ouverture (ex. clic sur un skin ailleurs) ; vidé à l'ouverture.
static var focus_skin_id: StringName = &""

## Onglets visibles (l'onglet Armes n'apparaît que si les skins d'armes sont activés).
var tabs: Array[StringName] = []
var current_tab: StringName = &""
var tab_chips: Dictionary = {}
var cards: Array[Control] = []          ## cartes de l'onglet courant (skins ou packs)
var action_buttons: Dictionary = {}     ## skin id → Button (carte)
var pack_buttons: Array[Button] = []
var back_button: Button = null
var gem_counter: GemCounter = null
var simulated_badge: Control = null
## Skin sélectionné (panneau d'aperçu).
var selected_skin: SkinData = null
## Panneau d'aperçu : bouton d'action, aperçu du héros, icône d'arme, arme tenue.
var detail_button: Button = null
var detail_preview: HeroPreview = null
var detail_icon: WeaponIcon = null
var detail_held: TextureRect = null
## Skin de base (char_default) s'il existe.
var base_skin: SkinData = null

var _modal: ModalPanel = null
var _scroll: ScrollContainer = null
var _row: GridContainer = null
var _body: HBoxContainer = null
var _detail: PanelContainer = null
var _d_kicker: Label = null
var _d_name: Label = null
var _d_meta: HBoxContainer = null
var _d_desc: Label = null
var _d_backdrop: TextureRect = null
var _note: Label = null


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
	base_skin = SkinData.get_skin(HeroSkin.DEFAULT_SKIN_ID)
	_build()
	var focus := SkinData.get_skin(focus_skin_id) if not String(focus_skin_id).is_empty() else null
	focus_skin_id = &""
	if focus != null:
		last_tab = &"weapon" if focus.kind == SkinData.KIND_WEAPON else &"character"
	show_tab(last_tab if tabs.has(last_tab) else &"character")
	if focus != null:
		select_skin(focus)
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

	_body = HBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 14)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_body)
	_detail = _build_detail()
	_body.add_child(_detail)
	_scroll = ScrollContainer.new()
	MenuKit.make_touch_scroll(_scroll)   # glisser au doigt partout (même sur les boutons)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 14
	_body.add_child(_scroll)
	_row = GridContainer.new()
	_row.add_theme_constant_override("h_separation", 12)
	_row.add_theme_constant_override("v_separation", 12)
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_row)
	_scroll.resized.connect(_update_columns)

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
	_note.clip_text = true
	_note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_note)
	simulated_badge = MenuKit.pill("Paiement simulé (test)", Color(0.5, 0.32, 0.05, 0.95), 15, MenuKit.TEXT,
		Color(1.0, 0.75, 0.3, 0.9))
	simulated_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	simulated_badge.visible = Store.SIMULATED
	foot.add_child(simulated_badge)


## Panneau d'aperçu (gauche) : nom, rareté, provenance, grand aperçu, description, action.
func _build_detail() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "Detail"
	var st := MenuKit.panel_style(Color(0.06, 0.08, 0.14, 0.96), Color(1, 1, 1, 0.16), 14, 1, 0)
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "base_panel_width", 300.0), 0)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(stack)
	_d_backdrop = MenuKit.rarity_backdrop(0)
	stack.add_child(_d_backdrop)
	detail_preview = HeroPreview.new()
	detail_preview.name = "HeroPreview"
	detail_preview.height_ratio = Balance.get_float("menu", "shop_hero_ratio", 0.84)
	detail_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_preview.offset_top = 104
	detail_preview.offset_bottom = -150
	stack.add_child(detail_preview)
	detail_icon = WeaponIcon.new()
	detail_icon.name = "WeaponPreview"
	detail_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_icon.offset_left = 18
	detail_icon.offset_right = -18
	detail_icon.offset_top = 120
	detail_icon.offset_bottom = -250
	stack.add_child(detail_icon)
	detail_held = TextureRect.new()
	detail_held.name = "HeldPreview"
	detail_held.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_held.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_held.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	detail_held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_held.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	detail_held.offset_left = 60
	detail_held.offset_right = -60
	detail_held.offset_top = -238
	detail_held.offset_bottom = -168
	stack.add_child(detail_held)
	var head := VBoxContainer.new()
	head.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 16
	head.offset_right = -16
	head.offset_top = 14
	head.add_theme_constant_override("separation", 2)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(head)
	_d_kicker = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(900))
	head.add_child(_d_kicker)
	_d_name = MenuKit.label("", 26, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	_d_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_d_name.clip_text = true
	head.add_child(_d_name)
	_d_meta = HBoxContainer.new()
	_d_meta.add_theme_constant_override("separation", 6)
	_d_meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_d_meta)
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 14
	foot.offset_right = -14
	foot.offset_bottom = -14
	foot.add_theme_constant_override("separation", 8)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(foot)
	_d_desc = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(700))
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_desc.max_lines_visible = 3
	_d_desc.custom_minimum_size = Vector2(0, 58)
	_d_desc.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	foot.add_child(_d_desc)
	detail_button = MenuKit.button("", MenuKit.Style.SECONDARY, 20, Vector2(0, 64))
	MenuKit.tighten(detail_button, 10)
	detail_button.pressed.connect(func() -> void:
		if selected_skin != null or current_tab == &"character":
			_on_skin_action(selected_skin.id if selected_skin != null else &""))
	foot.add_child(detail_button)
	return p


# --- Onglets -------------------------------------------------------------------------

func show_tab(tab: StringName) -> void:
	current_tab = tab
	last_tab = tab
	var b: Button = tab_chips.get(tab)
	if b != null and not b.button_pressed:
		b.set_pressed_no_signal(true)
	for c: Node in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	cards.clear()
	action_buttons.clear()
	pack_buttons.clear()
	_detail.visible = tab != &"gems"
	match tab:
		&"character":
			for s: SkinData in character_skins_with_base():
				_add_card(_character_card(s))
			_note.text = "Les skins changent seulement l'apparence. D'autres sont dans le pass de combat."
			select_skin(HeroSkin.current() if HeroSkin.current() != null else base_skin, false)
		&"gems":
			var packs := Store.packs()
			for i: int in packs.size():
				_add_card(_pack_card(i, packs[i]))
			_note.text = "Les gemmes s'achètent ici ou se gagnent à chaque extraction réussie."
		_:
			var list := weapon_skins()
			for s: SkinData in list:
				_add_card(_weapon_card(s))
			_note.text = "Un skin habille une arme précise. D'autres sont dans le pass de combat."
			select_skin(list[0] if not list.is_empty() else null, false)
	_scroll.scroll_vertical = 0
	_update_columns()
	# Entrée en cascade (courte)
	for i: int in cards.size():
		var c: Control = cards[i]
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, 0.18).set_delay(0.025 * i)
	_refresh_states()


## Colonnes de la grille selon la largeur ; hauteur des cartes calée pour remplir l'écran.
func _update_columns() -> void:
	if _row == null:
		return
	# Largeur disponible calculée depuis l'écran (pas depuis la grille, qui pousserait sinon
	# le conteneur hors de l'écran quand elle a trop de colonnes).
	var m: Vector4 = MenuKit.safe_margins(self)
	var w: float = get_viewport_rect().size.x - m.x - m.z
	if _detail.visible:
		w -= _detail.custom_minimum_size.x + 14.0
	w -= 10.0   # barre de défilement verticale
	var h: float = _scroll.size.y if _scroll.size.y > 0.0 else 540.0
	var n: int = maxi(cards.size(), 1)
	match current_tab:
		&"character":
			var cw: float = Balance.get_float("menu", "skin_card_width", 168.0)
			var cols: int = maxi(1, floori((w + 12.0) / (cw + 12.0)))
			var rows: int = ceili(n / float(cols))
			cols = ceili(n / float(rows))
			_row.columns = cols
			var ch: float = floorf((h - 12.0 * (rows - 1)) / rows) if rows <= 2 else Balance.get_float("menu", "skin_card_min_height", 250.0)
			for c: Control in cards:
				c.custom_minimum_size.y = maxf(ch, Balance.get_float("menu", "skin_card_min_height", 250.0))
		&"weapon":
			var cw2: float = Balance.get_float("menu", "weapon_skin_card_width", 190.0)
			_row.columns = maxi(1, floori((w + 12.0) / (cw2 + 12.0)))
			for c: Control in cards:
				c.custom_minimum_size.y = Balance.get_float("menu", "weapon_skin_card_height", 226.0)
		_:
			var cw3: float = Balance.get_float("menu", "shop_card_width", 220.0)
			_row.columns = maxi(1, mini(floori((w + 14.0) / (cw3 + 14.0)), n))
			for c: Control in cards:
				c.custom_minimum_size.y = maxf(h, Balance.get_float("menu", "shop_pack_height", 340.0))


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


# --- Listes de skins ------------------------------------------------------------------

## Skins de personnage proposés (hors skin de base) : ceux de la boutique + ceux du pass déjà
## obtenus ; triés par rareté puis prix (ordre de la planche).
func character_skins() -> Array[SkinData]:
	var out: Array[SkinData] = []
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_CHARACTER):
		if s.id == HeroSkin.DEFAULT_SKIN_ID:
			continue
		if s.is_in_shop() or (s.is_pass() and Profile.owns_skin(s.id)):
			out.append(s)
	out.sort_custom(_by_rarity)
	return out


## Skin de base en tête, puis character_skins().
func character_skins_with_base() -> Array[SkinData]:
	var out: Array[SkinData] = []
	if base_skin != null:
		out.append(base_skin)
	out.append_array(character_skins())
	return out


## Skins d'armes proposés : boutique + pass déjà obtenus, triés par arme (ordre des catégories,
## rareté de l'arme) puis par rareté du skin.
func weapon_skins() -> Array[SkinData]:
	var out: Array[SkinData] = []
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_WEAPON):
		if s.is_in_shop() or (s.is_pass() and Profile.owns_skin(s.id)):
			out.append(s)
	out.sort_custom(func(a: SkinData, b: SkinData) -> bool:
		var ka := _weapon_sort_key(a)
		var kb := _weapon_sort_key(b)
		if ka != kb:
			return ka < kb
		return a.rarity < b.rarity if a.rarity != b.rarity else String(a.id) < String(b.id))
	return out


static func _weapon_sort_key(s: SkinData) -> int:
	var w := WeaponCatalog.get_weapon(s.weapon_id)
	var cat := WeaponData.CATEGORIES.find(w.category if w != null else s.weapon_category)
	return cat * 10 + (w.rarity if w != null else 0)


static func _by_rarity(a: SkinData, b: SkinData) -> bool:
	if a.rarity != b.rarity:
		return a.rarity < b.rarity
	return a.price_gems < b.price_gems if a.price_gems != b.price_gems else String(a.id) < String(b.id)


## Arme d'un skin d'arme (arme précise, sinon la meilleure de sa catégorie).
static func weapon_of(s: SkinData) -> WeaponData:
	if s == null:
		return null
	var w := WeaponCatalog.get_weapon(s.weapon_id) if not String(s.weapon_id).is_empty() else null
	if w != null:
		return w
	var best: WeaponData = null
	for c: WeaponData in WeaponCatalog.all():
		if (s.weapon_category == SkinData.ANY_CATEGORY or c.category == s.weapon_category) and not c.is_gadget():
			if best == null or c.rarity > best.rarity:
				best = c
	return best


# --- Cartes ---------------------------------------------------------------------------

static var _crop_cache: Dictionary = {}


## Aperçu recadré sur sa zone utile (les poses ont de grandes marges transparentes) :
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
			a.region = Rect2(r.grow(4)).intersection(Rect2(Vector2.ZERO, img.get_size()))
			out = a
	_crop_cache[t] = out
	return out


## Pose haute résolution du lobby pour ce skin (repli : aperçu de la planche).
static func pose_texture(s: SkinData) -> Texture2D:
	var p := LobbyHero.DIR + LobbyHero.sheet_for(s) + ".png"
	if ResourceLoader.exists(p):
		return load(p) as Texture2D
	return HeroSkin.preview_for(s)


## Carte « bouton » : un tap sélectionne le skin (aperçu à gauche).
func _selectable(s: SkinData, rc: Color, radius: int) -> Button:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_ALL
	card.text = ""
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var st := MenuKit.panel_style(Color(0.06, 0.08, 0.14, 0.97), Color(rc, 0.85), radius, 2, 0)
	st.shadow_offset = Vector2.ZERO
	st.shadow_color = Color(rc, 0.4 if s.rarity >= 3 else 0.15)
	st.shadow_size = 10 if s.rarity >= 3 else 4
	var hv := st.duplicate() as StyleBoxFlat
	hv.border_color = rc.lightened(0.35)
	var sel := st.duplicate() as StyleBoxFlat
	sel.border_color = MenuKit.GOLD
	sel.set_border_width_all(3)
	card.add_theme_stylebox_override("normal", st)
	card.add_theme_stylebox_override("hover", hv)
	card.add_theme_stylebox_override("pressed", sel)
	card.add_theme_stylebox_override("hover_pressed", sel)
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = MenuKit.GOLD
	f.set_border_width_all(3)
	f.set_corner_radius_all(radius + 2)
	f.set_expand_margin_all(2)
	card.add_theme_stylebox_override("focus", f)
	card.toggle_mode = true
	card.set_meta(&"skin_id", String(s.id))
	card.pressed.connect(func() -> void:
		MenuKit.sfx(&"tick")
		select_skin(s))
	MenuKit.add_feedback(card, 1.02)
	return card


## Carte verticale d'un skin de personnage : personnage en pied sur fond teinté de rareté,
## nom en capitales, bandeau de rareté, bouton d'action.
func _character_card(s: SkinData) -> Control:
	var rc: Color = MenuKit.rarity_color(s.rarity)
	var p := _selectable(s, rc, 10)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "skin_card_width", 168.0), 250)
	p.add_child(MenuKit.rarity_backdrop(s.rarity))
	var bottom_h: float = 104.0
	var tr := TextureRect.new()
	tr.name = "Preview"
	tr.texture = cropped_preview(pose_texture(s))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_top = 14
	tr.offset_left = 10
	tr.offset_right = -10
	tr.offset_bottom = -bottom_h - 4
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	if s.is_pass():
		p.add_child(_corner_badge("Pass", MenuKit.GOLD))
	_card_foot(p, s, s.display_name.to_upper(), "")
	return p


## Carte d'un skin d'arme : l'arme habillée, nom du skin, arme, bandeau de rareté, action.
func _weapon_card(s: SkinData) -> Control:
	var rc: Color = MenuKit.rarity_color(s.rarity)
	var p := _selectable(s, rc, 12)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "weapon_skin_card_width", 190.0), 226)
	p.add_child(MenuKit.rarity_backdrop(s.rarity))
	var ic := WeaponIcon.new()
	ic.name = "Preview"
	ic.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	ic.offset_left = 12
	ic.offset_right = -12
	ic.offset_top = 14
	ic.offset_bottom = 96
	p.add_child(ic)
	ic.set_weapon(weapon_of(s), s, false)
	if s.is_pass():
		p.add_child(_corner_badge("Pass", MenuKit.GOLD))
	var w := weapon_of(s)
	_card_foot(p, s, s.display_name, w.display_name if w != null else "")
	return p


func _corner_badge(txt: String, col: Color) -> Control:
	var b := MenuKit.pill(txt, Color(col.darkened(0.55), 0.95), 12, col.lightened(0.3), Color(col, 0.8))
	b.name = "SourceBadge"
	b.position = Vector2(8, 8)
	return b


func _card_foot(p: Control, s: SkinData, title: String, sub: String) -> void:
	var foot := VBoxContainer.new()
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.offset_left = 10
	foot.offset_right = -10
	foot.offset_bottom = -10
	foot.add_theme_constant_override("separation", 4)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(foot)
	var n := MenuKit.label(title, 15, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	foot.add_child(n)
	if not sub.is_empty():
		var sl := MenuKit.label(sub, 13, MenuKit.TEXT_DIM, MenuKit.nunito(800))
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.clip_text = true
		foot.add_child(sl)
	var band := MenuKit.rarity_band(s.rarity, 14, 24)
	(band.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(5)
	foot.add_child(band)
	var b := MenuKit.button("", MenuKit.Style.SECONDARY, 17, Vector2(0, 46))
	MenuKit.tighten(b, 6)
	b.custom_minimum_size.x = 0
	foot.add_child(b)
	b.pressed.connect(func() -> void:
		select_skin(s)
		_on_skin_action(s.id))
	action_buttons[s.id] = b
	b.set_meta(&"skin_id", String(s.id))


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


# --- Sélection (panneau d'aperçu) -------------------------------------------------------

## Met ce skin en avant dans le panneau de gauche (personnage en pied ou arme habillée).
func select_skin(s: SkinData, animate: bool = true) -> void:
	selected_skin = s
	var is_char: bool = current_tab == &"character"
	detail_preview.visible = is_char
	detail_icon.visible = not is_char
	detail_held.visible = not is_char
	var r: int = s.rarity if s != null else 0
	var bd := MenuKit.rarity_backdrop(r)
	_d_backdrop.texture = bd.texture
	bd.free()
	for c: Node in _d_meta.get_children():
		c.queue_free()
	if is_char:
		_d_kicker.text = "Personnage de base" if s == null or s.id == HeroSkin.DEFAULT_SKIN_ID else "Skin de personnage"
		_d_name.text = s.display_name if s != null else "Soldat standard"
		_d_desc.text = s.description if s != null and not s.description.is_empty() \
			else "Un équipement polyvalent pour toutes les situations."
		detail_preview.set_skin(s, animate)
	else:
		var w := weapon_of(s)
		_d_kicker.text = ("Skin · %s" % w.display_name) if w != null else "Skin d'arme"
		_d_name.text = s.display_name if s != null else "Aucun skin"
		_d_desc.text = s.description if s != null else "De nouveaux skins arrivent bientôt."
		detail_icon.set_weapon(w, s, false)
		detail_held.remove_meta(WeaponSkin.META_BASE_TEX)
		detail_held.texture = _held_texture(w)
		WeaponSkin.apply(detail_held, s, w.id if w != null else &"", false)
		if animate:
			detail_icon.pivot_offset = detail_icon.size * 0.5
			create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
				.tween_property(detail_icon, "scale", Vector2.ONE, 0.28).from(Vector2(0.9, 0.9))
	var rc := MenuKit.rarity_color(r)
	_d_meta.add_child(MenuKit.pill(MenuKit.rarity_name(r), rc.darkened(0.35), 13))
	if s != null and s.is_pass():
		_d_meta.add_child(MenuKit.pill("Pass de combat", Color(MenuKit.GOLD.darkened(0.55), 0.95), 13, MenuKit.GOLD.lightened(0.3)))
	elif s != null and s.is_in_shop() and not Profile.owns_skin(s.id):
		_d_meta.add_child(MenuKit.pill("%d gemmes" % s.price_gems, Color(MenuKit.GEM.darkened(0.6), 0.95), 13, MenuKit.GEM.lightened(0.3)))
	for c: Control in cards:
		if c is Button:
			(c as Button).set_pressed_no_signal(s != null and str(c.get_meta(&"skin_id", "")) == String(s.id))
	_refresh_states()


## Sprite de l'arme tenue en jeu (assets/sprites/weapons/<id>.png), pour l'aperçu « en jeu ».
static func _held_texture(w: WeaponData) -> Texture2D:
	if w == null:
		return null
	var p := "res://assets/sprites/weapons/%s.png" % w.get_sprite_id()
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


# --- États et achats ------------------------------------------------------------------

## État d'un skin : "buy", "equip", "equipped", "pass" (skin du pass pas encore obtenu).
func skin_state(s: SkinData) -> String:
	if s == null or s.id == HeroSkin.DEFAULT_SKIN_ID:
		var cur := String(Profile.skin_character)
		return "equipped" if cur.is_empty() or cur == String(HeroSkin.DEFAULT_SKIN_ID) else "equip"
	if not Profile.owns_skin(s.id):
		return "pass" if s.is_pass() else "buy"
	if s.kind == SkinData.KIND_CHARACTER:
		return "equipped" if Profile.skin_character == s.id else "equip"
	return "equipped" if WeaponSkin.is_equipped(s) else "equip"


func _refresh_states() -> void:
	for id: StringName in action_buttons:
		_refresh_button(action_buttons[id] as Button, SkinData.get_skin(id) if not String(id).is_empty() else null)
	if detail_button != null:
		_refresh_button(detail_button, selected_skin)
		detail_button.visible = current_tab != &"gems" and (selected_skin != null or current_tab == &"character")


func _refresh_button(b: Button, s: SkinData) -> void:
	match skin_state(s):
		"buy":
			b.text = "%d  gemmes" % s.price_gems if s.price_gems > 0 else "Obtenir"
			b.disabled = false
			b.modulate = Color.WHITE if Profile.can_afford(&"gems", s.price_gems) else Color(1, 1, 1, 0.65)
			_style_action(b, MenuKit.Style.PRIMARY)
		"pass":
			b.text = "Dans le pass"
			b.disabled = false
			b.modulate = Color.WHITE
			_style_action(b, MenuKit.Style.SECONDARY)
		"equip":
			b.text = "Équiper"
			b.disabled = false
			b.modulate = Color.WHITE
			_style_action(b, MenuKit.Style.SECONDARY)
		_:
			var weapon: bool = s != null and s.kind == SkinData.KIND_WEAPON
			b.text = "Retirer" if weapon else "Équipé"
			b.disabled = not weapon
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
	match skin_state(s):
		"buy":
			ask_buy(s)
		"pass":
			open_pass(s)
		"equip":
			equip(s)
		"equipped":
			if s != null and s.kind == SkinData.KIND_WEAPON:
				unequip_weapon(s)


## Skin du pass pas encore obtenu : explique où le trouver, puis ouvre l'écran du pass.
func open_pass(s: SkinData) -> ModalPanel:
	var where := BattlePassSystem.get_instance().find_skin(s.id) if s != null else {}
	var msg := "« %s » s'obtient dans le pass de combat" % (s.display_name if s != null else "")
	if not where.is_empty():
		msg += " (palier %d, piste %s)" % [int(where["tier"]), "premium" if where["track"] == BattlePassSystem.PREMIUM else "gratuite"]
	var m := ConfirmPanel.new("Dans le pass", msg + ".", "Voir le pass")
	m.confirmed.connect(func() -> void:
		BattlePassScreen.focus_skin_id = s.id if s != null else &""
		MenuKit.go_to(self, MenuKit.BATTLE_PASS_SCENE))
	return _open_modal(m)


## Ouvre la confirmation d'achat (ou explique qu'il manque des gemmes).
func ask_buy(s: SkinData) -> ModalPanel:
	if s == null:
		return null
	if s.is_pass():
		return open_pass(s)
	if not Profile.can_afford(&"gems", s.price_gems):
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


## Achète (sans confirmation) puis équipe. Renvoie false si impossible (skin du pass compris).
func buy(s: SkinData) -> bool:
	if s == null or not s.is_in_shop() or not Profile.buy_skin(s.id):
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
		ok = WeaponSkin.equip(s.id)
	if ok:
		MenuKit.sfx(&"item_equip", -2.0)
		_pop_card(s)
	_refresh_states()
	return ok


func unequip_weapon(s: SkinData) -> void:
	if s == null:
		return
	WeaponSkin.unequip(s.weapon_id)
	MenuKit.sfx(&"click")
	_refresh_states()


func _pop_card(s: SkinData) -> void:
	var b: Button = action_buttons.get(s.id if s != null else (base_skin.id if base_skin != null else &""))
	if b == null or not b.is_inside_tree():
		return
	var card: Control = b
	while card != null and not cards.has(card):
		card = card.get_parent() as Control
	if card == null:
		return
	card.pivot_offset = card.size * 0.5
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(card, "scale", Vector2.ONE, 0.3).from(Vector2(1.05, 1.05))


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
