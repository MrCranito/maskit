class_name ShopScreen
extends Control
## Boutique cosmétique : onglets Personnages / Armes / Gemmes.
##  - Skins (SkinData.all_of_kind) : aperçu (héros : HeroPreview ; arme : icône + WeaponSkin),
##    rareté, prix en gemmes, états Acheter / Équiper / Équipé ; confirmation d'achat.
##  - Gemmes : packs ([shop] packs) via Store.purchase_pack (paiement SIMULÉ, badge visible).
## Message permanent : « Purement cosmétique : aucun avantage en jeu ».

const TABS: Array[StringName] = [&"character", &"weapon", &"gems"]
const TAB_TITLES := {&"character": "Personnages", &"weapon": "Armes", &"gems": "Gemmes"}

static var last_tab: StringName = &"character"

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
	_build()
	show_tab(last_tab if TABS.has(last_tab) else &"character")
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
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tabs)
	var group := ButtonGroup.new()
	for tab: StringName in TABS:
		var b := MenuKit.chip(String(TAB_TITLES[tab]), MenuKit.GEM if tab == &"gems" else MenuKit.GOLD, group)
		b.custom_minimum_size = Vector2(150, 58)
		b.add_theme_font_size_override("font_size", 20)
		b.toggled.connect(func(on: bool) -> void:
			if on and current_tab != tab:
				MenuKit.sfx(&"tick")
				show_tab(tab))
		tabs.add_child(b)
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
	for c: Node in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	cards.clear()
	action_buttons.clear()
	pack_buttons.clear()
	match tab:
		&"gems":
			var packs := Store.packs()
			for i: int in packs.size():
				_add_card(_pack_card(i, packs[i]))
			_note.text = "Les gemmes s'achètent ici ou se gagnent à chaque extraction réussie."
		_:
			var kind: StringName = SkinData.KIND_CHARACTER if tab == &"character" else SkinData.KIND_WEAPON
			if tab == &"character":
				_add_card(_skin_card(null, kind))
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


## Carte d'un skin (null = apparence d'origine du héros).
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
	if s == null:
		return "equipped" if String(Profile.skin_character).is_empty() else "equip"
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
				b.text = "%d  gemmes" % s.price_gems
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
	if s == null:
		ok = Profile.equip_character_skin(&"")
	elif s.kind == SkinData.KIND_CHARACTER:
		ok = Profile.equip_character_skin(s.id)
	else:
		ok = Profile.equip_weapon_skin(s.id)
	if ok:
		MenuKit.sfx(&"item_equip", -2.0)
		var b: Button = action_buttons.get(s.id if s != null else &"")
		if b != null and b.is_inside_tree():
			var card := b.get_parent().get_parent() as Control
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
