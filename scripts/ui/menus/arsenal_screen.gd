class_name ArsenalScreen
extends Control
## Écran d'arsenal façon planche docs/reference/arsenal.jpg, un seul composant pour deux usages :
##  - `loadout_mode = false` (scenes/ui/menus/arsenal.tscn) : consultation du catalogue complet
##    (WeaponCatalog.all()) en sections par catégorie (pictogramme + titre, WeaponData.CATEGORY_TITLES),
##    cartes horizontales à bandeau de rareté ; modèles possédés avec leur quantité, modèles non
##    possédés grisés + cadenas.
##  - `loadout_mode = true` (scenes/ui/menus/loadout.tscn) : « Arsenal de départ », après le choix
##    de la carte. Mêmes sections avec les seules armes possédées ; 3 emplacements d'armes +
##    1 emplacement d'équipement en haut ; tap = ajouter/retirer ; rappel « perdues si tu meurs » ;
##    « Valider et partir » (désactivé sans arme) → Profile.set_loadout(uids) (armes + gadget),
##    GameState.begin_raid(), raid.tscn (fondu MenuKit).
## Panneau de droite : détail de l'arme touchée (stats en barres).
##  - Consultation : onglets « Collection » / « Armurerie » (agent Économie). Armurerie = achat
##    d'armes en pièces d'or selon WeaponData.unlock_mode (Economy.weapon_status) : prix (shop),
##    « Tue 1 Tireur embusqué pour débloquer (0/1) » (kill), « Légendaire : uniquement en butin »
##    (drop). Compteur d'or (GoldCounter) dans l'en-tête ; « Acheter » dans le panneau de détail.
##  - Arsenal de départ : ligne « Consommables emportés » (soins de la réserve mis dans le sac au
##    lancement, Profile.consumables_preview) + bascule « Soins : oui / non ».

@export var loadout_mode: bool = true
## Consultation : ouvrir directement l'onglet Armurerie.
@export var start_in_shop: bool = false
## Prochaine ouverture de l'écran d'arsenal sur l'onglet Armurerie (bouton du lobby, raccourci).
static var open_shop_next: bool = false

## Scène lancée par « Valider et partir » ("" = aucun changement de scène, pour les tests).
var raid_scene: String = MenuKit.RAID_SCENE
var stash: Array[Dictionary] = []
## Exemplaires possédés par modèle : id → Array[int] (uids).
var owned: Dictionary = {}
var tiles: Array[WeaponTile] = []
## Sections affichées : catégorie → GridContainer.
var sections: Dictionary = {}
## Arsenal de départ en cours : uids (armes + au plus un équipement).
var selected_uids: Array[int] = []
var detail_weapon: WeaponData = null

## Arsenal de départ : « DÉPLOYER » (enregistre l'arsenal et lance le raid).
var validate_button: Button = null
## Arsenal de départ : équiper / retirer l'arme affichée (bandeau de droite).
var equip_button: Button = null
## Arsenal de départ : bandeau violet de droite (fiche de l'arme + DÉPLOYER).
var slab: Control = null
var back_button: Button = null
var skin_button: Button = null
var slot_buttons: Array[Button] = []
var gadget_slot_button: Button = null
var gem_counter: GemCounter = null
var gold_counter: GoldCounter = null
## Onglet Armurerie actif (consultation seulement).
var shop_mode: bool = false
var buy_button: Button = null
var consumables_label: Label = null
var consumables_toggle: Button = null
## Arsenal de départ : clefs de la réserve emportées (ligne visible seulement s'il y en a).
var keys_label: Label = null
var keys_toggle: Button = null
var _tab_collection: Button = null
var _tab_shop: Button = null
var _sub_label: Label = null
var _d_shop: VBoxContainer = null
var _d_shop_text: Label = null
var _d_shop_bar: ProgressBar = null
var _d_shop_hint: Label = null

const MERCHANT_SCENE := "res://scenes/ui/menus/merchant.tscn"

var _scroll: ScrollContainer = null
var _list: VBoxContainer = null
var _slots_row: HBoxContainer = null
var _d_style: StyleBoxFlat = null
var _d_icon: WeaponIcon = null
var _d_name: Label = null
var _d_rarity: PanelContainer = null
var _d_cat: Label = null
var _d_owned: Label = null
var _d_desc: Label = null
var _d_bars: StatBars = null
var _d_skin: Label = null
var _empty_label: Label = null
var _hint: Label = null

static var _silhouette: Shader = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	var bg := MenuBackground.new()
	bg.dim = Balance.get_float("menu", "screen_dim", 0.45) + 0.2
	add_child(bg)
	if not loadout_mode and (start_in_shop or open_shop_next):
		shop_mode = true
	open_shop_next = false
	_read_stash()
	if loadout_mode:
		var nw := 0
		var ng := 0
		for u: int in Profile.loadout:
			var w := _weapon_of_uid(u)
			if w == null:
				continue
			if w.is_gadget() and ng < Profile.gadget_slots():
				ng += 1
				selected_uids.append(u)
			elif not w.is_gadget() and nw < Profile.loadout_slots():
				nw += 1
				selected_uids.append(u)
	_build()
	_fill()
	var first: WeaponData = null
	if not selected_uids.is_empty():
		first = _weapon_of_uid(selected_uids[0])
	elif not tiles.is_empty():
		for t: WeaponTile in tiles:
			if not t.locked:
				first = t.weapon
				break
		if first == null:
			first = tiles[0].weapon
	show_weapon_detail(first, false)
	_refresh_slots(false)
	MenuKit.fade_in(self)
	if not loadout_mode:
		back_button.grab_focus.call_deferred()


func _read_stash() -> void:
	stash = Profile.get_stash_weapons()
	owned.clear()
	for e: Dictionary in stash:
		var id := String((e["data"] as WeaponData).id)
		if not owned.has(id):
			owned[id] = [] as Array[int]
		(owned[id] as Array[int]).append(int(e["uid"]))


func _weapon_of_uid(u: int) -> WeaponData:
	for e: Dictionary in stash:
		if int(e["uid"]) == u:
			return e["data"] as WeaponData
	return null


func owned_count(id: StringName) -> int:
	return (owned.get(String(id), []) as Array).size()


# --- Construction -------------------------------------------------------------------

func _build() -> void:
	if loadout_mode:
		_build_loadout()
		return
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)

	# En-tête : retour, titre + accroche, gemmes
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	back_button = MenuKit.back_button("Cartes" if loadout_mode else "Menu")
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var tcol := VBoxContainer.new()
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_theme_constant_override("separation", -4)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tcol)
	tcol.add_child(MenuKit.title("ARSENAL DE DÉPART" if loadout_mode else "ARSENAL", 38))
	_sub_label = MenuKit.label("", 16, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	# Le sous-titre ne doit jamais élargir l'en-tête (onglets + compteurs à droite).
	_sub_label.clip_text = true
	_sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tcol.add_child(_sub_label)
	_refresh_subtitle()
	if not loadout_mode:
		# Onglets Collection / Armurerie
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 8)
		tabs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tabs)
		var group := ButtonGroup.new()
		_tab_collection = MenuKit.chip("Collection", MenuKit.GOLD, group)
		_tab_collection.button_pressed = not shop_mode
		_tab_collection.pressed.connect(func() -> void: set_shop_mode(false))
		tabs.add_child(_tab_collection)
		_tab_shop = MenuKit.chip("Armurerie", GoldCounter.GOLD_COIN, group)
		_tab_shop.button_pressed = shop_mode
		_tab_shop.pressed.connect(func() -> void: set_shop_mode(true))
		tabs.add_child(_tab_shop)
		gold_counter = GoldCounter.new()
		gold_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gold_counter.pressed.connect(func() -> void:
			if ResourceLoader.exists(MERCHANT_SCENE):
				MenuKit.go_to(self, MERCHANT_SCENE))
		head.add_child(gold_counter)
	gem_counter = GemCounter.new()
	gem_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_counter.pressed.connect(func() -> void: MenuKit.go_to(self, MenuKit.SHOP_SCENE))
	head.add_child(gem_counter)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	var list_panel := PanelContainer.new()
	var lp := MenuKit.panel_style(Color(0.035, 0.05, 0.1, 0.72), Color(1, 1, 1, 0.08), 14, 1, 12)
	lp.content_margin_right = 6
	list_panel.add_theme_stylebox_override("panel", lp)
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list_panel)
	_scroll = ScrollContainer.new()
	MenuKit.make_touch_scroll(_scroll)   # glisser au doigt partout (même sur les boutons)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 14
	list_panel.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)
	_scroll.resized.connect(_update_columns)

	body.add_child(_build_detail())


# --- Arsenal de départ : disposition de la maquette « Loadout » (direction D, ×1,67) ---------
##  - en-tête : retour carré (→ cartes), « ÉTAPE 2/2 · CARTE » + « ARSENAL DE DÉPART » ;
##  - emplacements (armes puis équipement) en cartes encre à liseré de rareté ;
##  - ligne de risque (rose) : armes perdues si tu meurs + soins emportés (bascule) ;
##  - grille de 4 colonnes des armes possédées (WeaponTile.style_d), triées par rareté ;
##    1er tap = fiche, 2e tap sur l'arme affichée = équiper / retirer ;
##  - à droite, bandeau violet translucide dépoli : catégorie, nom, rareté, stats, bouton
##    « Équiper en 0N » / « Retirer », aide, puis « DÉPLOYER ».

func _build_loadout() -> void:
	var m: Vector4 = MenuKit.safe_margins(self)
	m.x = maxf(m.x, Balance.get_float("menu", "lobby_margin_left", 80.0))
	m.w = maxf(m.w, Balance.get_float("menu", "lobby_margin_bottom", 36.0))
	var vp: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var slab_w: float = clampf(vp.x * Balance.get_float("menu", "lobby_slab_ratio", 0.3),
		Balance.get_float("menu", "lobby_slab_min", 370.0), Balance.get_float("menu", "lobby_slab_max", 440.0))

	var sl := MainMenu.LobbySlab.new()
	sl.name = "Slab"
	sl.cut = Balance.get_float("menu", "lobby_slab_cut", 94.0)
	sl.color = Color(MenuKit.VIOLET, Balance.get_float("menu", "lobby_slab_alpha", 0.66))
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.anchor_left = 1.0
	sl.anchor_right = 1.0
	sl.anchor_bottom = 1.0
	sl.offset_left = -slab_w
	add_child(sl)
	MenuKit.frosted(sl)
	slab = sl

	var left := VBoxContainer.new()
	left.name = "Left"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left.offset_left = m.x
	left.offset_top = m.y
	left.offset_right = -slab_w - 24.0
	left.offset_bottom = -m.w * 0.5
	left.add_theme_constant_override("separation", 14)
	add_child(left)

	# En-tête
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 22)
	left.add_child(head)
	back_button = MenuKit.square_back_button("Cartes")
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var tcol := VBoxContainer.new()
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_theme_constant_override("separation", 0)
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tcol)
	_sub_label = MenuKit.label("", 17, MenuKit.VIOLET_LIGHT, MenuKit.nunito(600), 0)
	_sub_label.uppercase = true
	tcol.add_child(_sub_label)
	tcol.add_child(MenuKit.label("ARSENAL DE DÉPART", 40, MenuKit.TEXT, MenuKit.display(), 0))
	_refresh_subtitle()

	# Emplacements
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 7)
	_slots_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_slots_row)
	var avail: float = vp.x - m.x - slab_w - 24.0
	var n_slots: int = Profile.loadout_slots()
	var sw: float = clampf((avail - 7.0 * n_slots) / (n_slots + 0.85),
		Balance.get_float("menu", "loadout_slot_min", 150.0), Balance.get_float("menu", "loadout_slot_max", 260.0))
	for i: int in n_slots:
		var b := _slot_button(sw)
		b.pressed.connect(func() -> void: _on_slot_pressed(i))
		_slots_row.add_child(b)
		slot_buttons.append(b)
	gadget_slot_button = _slot_button(sw * 0.85)
	gadget_slot_button.pressed.connect(_on_gadget_slot_pressed)
	_slots_row.add_child(gadget_slot_button)

	# Ligne de risque + soins emportés
	var risk := HBoxContainer.new()
	risk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	risk.add_theme_constant_override("separation", 14)
	left.add_child(risk)
	var warn := MenuKit.label("▲ Armes emportées perdues si tu meurs", 17, Color(1.0, 0.44, 0.57), MenuKit.nunito(600), 0)
	warn.uppercase = true
	warn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	risk.add_child(warn)
	consumables_label = MenuKit.label("", 17, Color(1, 1, 1, 0.7), MenuKit.nunito(600), 0)
	consumables_label.name = "Consumables"
	consumables_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	consumables_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	consumables_label.clip_text = true
	consumables_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	risk.add_child(consumables_label)
	consumables_toggle = MenuKit.button("Soins : oui", MenuKit.Style.GHOST, 15, Vector2(118, 44))
	MenuKit.tighten(consumables_toggle, 8)
	consumables_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	consumables_toggle.pressed.connect(toggle_consumables)
	risk.add_child(consumables_toggle)
	_refresh_consumables()
	keys_label = MenuKit.label("", 17, MenuKit.GOLD, MenuKit.nunito(600), 0)
	keys_label.name = "Keys"
	keys_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	risk.add_child(keys_label)
	keys_toggle = MenuKit.button("Clefs : non", MenuKit.Style.GHOST, 15, Vector2(118, 44))
	MenuKit.tighten(keys_toggle, 8)
	keys_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	keys_toggle.pressed.connect(toggle_keys)
	risk.add_child(keys_toggle)
	_refresh_keys()

	# Grille des armes
	_scroll = ScrollContainer.new()
	MenuKit.make_touch_scroll(_scroll)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 14
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_list)

	# Bandeau : fiche de l'arme + DÉPLOYER
	var col := VBoxContainer.new()
	col.name = "SlabContent"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = sl.cut
	col.offset_top = maxf(m.y, 36.0)
	col.offset_right = -maxf(m.z, 44.0)
	col.offset_bottom = -maxf(m.w, 40.0)
	col.add_theme_constant_override("separation", 10)
	sl.add_child(col)
	_d_cat = _slab_label(17, MenuKit.nunito(600))
	_d_cat.uppercase = true
	col.add_child(_d_cat)
	_d_name = _slab_label(54, MenuKit.display())
	_d_name.uppercase = true
	_d_name.clip_text = true
	_d_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_d_name.custom_minimum_size.x = slab_w - sl.cut - 44.0
	col.add_child(_d_name)
	_d_rarity = MenuKit.rarity_band(0, 16, 30, 0)
	_d_rarity.size_flags_horizontal = Control.SIZE_SHRINK_END
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 12
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 12
	((_d_rarity.get_node(^"Text") as Label)).uppercase = true
	col.add_child(_d_rarity)
	_d_bars = StatBars.new()
	_d_bars.stacked = true
	_d_bars.custom_minimum_size.x = Balance.get_float("menu", "loadout_detail_width", 300.0)
	_d_bars.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(_d_bars)
	equip_button = Button.new()
	equip_button.name = "EquipButton"
	equip_button.focus_mode = Control.FOCUS_ALL
	equip_button.custom_minimum_size = Vector2(_d_bars.custom_minimum_size.x, 66)
	equip_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	equip_button.add_theme_font_override("font", MenuKit.display())
	equip_button.add_theme_font_size_override("font_size", 27)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		equip_button.add_theme_color_override(k, MenuKit.TEXT)
	equip_button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	var eb := func(bg: Color) -> CutBox:
		var c := CutBox.make(bg, 16.0, Color(0, 0, 0, 0), 0.0, 16.0, 0.0)
		c.corners = CutBox.CUT_TOP_LEFT
		return c
	equip_button.add_theme_stylebox_override("normal", eb.call(MenuKit.NIGHT_DEEP))
	equip_button.add_theme_stylebox_override("hover", eb.call(MenuKit.NIGHT_PANEL))
	equip_button.add_theme_stylebox_override("pressed", eb.call(Color(0, 0, 0, 1)))
	equip_button.add_theme_stylebox_override("hover_pressed", eb.call(Color(0, 0, 0, 1)))
	equip_button.add_theme_stylebox_override("disabled", eb.call(Color(MenuKit.NIGHT_DEEP, 0.55)))
	var ef := CutBox.new()
	ef.draw_center = false
	ef.border_color = MenuKit.TEXT
	ef.border_width = 2.0
	ef.cut = 18.0
	ef.corners = CutBox.CUT_TOP_LEFT
	ef.grow = 4.0
	equip_button.add_theme_stylebox_override("focus", ef)
	equip_button.pressed.connect(_on_equip_pressed)
	MenuKit.add_feedback(equip_button, 1.04)
	col.add_child(equip_button)
	_hint = _slab_label(15, MenuKit.nunito(500))
	_hint.modulate.a = 0.8
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = _d_bars.custom_minimum_size.x
	_hint.size_flags_horizontal = Control.SIZE_SHRINK_END
	col.add_child(_hint)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	validate_button = _deploy_button()
	validate_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	validate_button.pressed.connect(validate_and_go)
	col.add_child(validate_button)
	# Restes de la fiche « consultation » : non affichés ici, gardés pour le code commun
	_d_style = StyleBoxFlat.new()
	_d_icon = WeaponIcon.new()
	_d_owned = Label.new()
	_d_desc = Label.new()
	for c: Control in [_d_icon, _d_owned, _d_desc]:
		c.visible = false
		col.add_child(c)
	_scroll.resized.connect(_update_columns)


func _slab_label(px: int, font: Font) -> Label:
	var l := MenuKit.label("", px, MenuKit.TEXT, font, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


## « DÉPLOYER » en Anton, sans fond (comme au lobby) ; atténué tant qu'aucune arme n'est choisie.
func _deploy_button() -> Button:
	var b := Button.new()
	b.name = "DeployButton"
	b.text = "DÉPLOYER"
	b.focus_mode = Control.FOCUS_ALL
	var fs: int = int(Balance.get_value("menu", "deploy_font_size", 84))
	b.add_theme_font_override("font", MenuKit.display())
	b.add_theme_font_size_override("font_size", fs)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, MenuKit.TEXT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	var hov := CutBox.make(Color(1, 1, 1, 0.1), 14.0, Color(0, 0, 0, 0), 0.0, 6.0, 0.0)
	for k: String in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(k, CutBox.make(Color(0, 0, 0, 0), 14.0, Color(0, 0, 0, 0), 0.0, 6.0, 0.0))
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("hover_pressed", hov)
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = Color(MenuKit.TEXT, 0.5)
	f.border_width = 1.5
	f.cut = 14.0
	f.grow = 2.0
	b.add_theme_stylebox_override("focus", f)
	MenuKit.add_feedback(b, 1.03)
	return b


## Bouton du bandeau : retire l'arme affichée si elle est placée, sinon l'équipe.
func _on_equip_pressed() -> void:
	if detail_weapon != null:
		toggle_model(detail_weapon)
		_refresh_equip_button()


func _refresh_equip_button() -> void:
	if equip_button == null:
		return
	var w := detail_weapon
	var placed := false
	if w != null:
		for u: int in (owned.get(String(w.id), []) as Array):
			if selected_uids.has(u):
				placed = true
	equip_button.disabled = w == null
	if w == null:
		equip_button.text = "ÉQUIPER"
	elif placed:
		equip_button.text = "RETIRER"
	elif w.is_gadget():
		equip_button.text = "ÉQUIPER EN GADGET"
	elif selected_weapon_count() >= Profile.loadout_slots():
		equip_button.text = "EMPLACEMENTS PLEINS"
	else:
		equip_button.text = "ÉQUIPER EN %02d" % (selected_weapon_count() + 1)


func _slot_button(w: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(w, Balance.get_float("menu", "loadout_slot_height", 100.0))
	b.clip_contents = true
	MenuKit.add_feedback(b, 1.04)
	return b


func _build_detail() -> Control:
	var p := PanelContainer.new()
	_d_style = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.94), MenuKit.BORDER, 16, 2, 16)
	p.add_theme_stylebox_override("panel", _d_style)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "arsenal_detail_width", 340.0), 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	_d_icon = WeaponIcon.new()
	_d_icon.custom_minimum_size = Vector2(0, 96 if loadout_mode else 124)
	col.add_child(_d_icon)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 10)
	col.add_child(nrow)
	_d_name = MenuKit.label("", 24, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	_d_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_name.clip_text = true
	_d_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nrow.add_child(_d_name)
	_d_rarity = MenuKit.rarity_band(0, 14, 26, 6)
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(6)
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 10
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 10
	_d_rarity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(_d_rarity)
	var crow := HBoxContainer.new()
	col.add_child(crow)
	_d_cat = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	_d_cat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(_d_cat)
	_d_owned = MenuKit.label("", 15, MenuKit.TEXT, MenuKit.nunito(900))
	crow.add_child(_d_owned)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	col.add_child(gap)
	_d_bars = StatBars.new()
	col.add_child(_d_bars)
	_d_desc = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(650))
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_desc.max_lines_visible = 4
	_d_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_d_desc)
	if not loadout_mode:
		_d_shop = VBoxContainer.new()
		_d_shop.name = "ShopBox"
		_d_shop.add_theme_constant_override("separation", 6)
		col.add_child(_d_shop)
		_d_shop_text = MenuKit.label("", 16, MenuKit.TEXT, MenuKit.nunito(900))
		_d_shop_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_d_shop.add_child(_d_shop_text)
		_d_shop_bar = ProgressBar.new()
		_d_shop_bar.show_percentage = false
		_d_shop_bar.custom_minimum_size = Vector2(0, 12)
		var bb := StyleBoxFlat.new()
		bb.bg_color = Color(0.02, 0.03, 0.08, 0.9)
		bb.set_corner_radius_all(6)
		var bf := StyleBoxFlat.new()
		bf.bg_color = MenuKit.BAD
		bf.set_corner_radius_all(6)
		_d_shop_bar.add_theme_stylebox_override("background", bb)
		_d_shop_bar.add_theme_stylebox_override("fill", bf)
		_d_shop.add_child(_d_shop_bar)
		_d_shop_hint = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(800))
		_d_shop_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_d_shop.add_child(_d_shop_hint)
		buy_button = MenuKit.button("Acheter", MenuKit.Style.PRIMARY, 22, Vector2(0, 64))
		MenuKit.tighten(buy_button)
		buy_button.pressed.connect(buy_selected)
		_d_shop.add_child(buy_button)
	# Skins d'armes : seulement quand ils sont activés ([shop] weapon_skins_enabled).
	if not loadout_mode and WeaponSkin.is_enabled():
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 10)
		col.add_child(srow)
		_d_skin = MenuKit.label("", 15, MenuKit.TEXT, MenuKit.nunito(800))
		_d_skin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_d_skin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		srow.add_child(_d_skin)
		skin_button = MenuKit.button("Changer", MenuKit.Style.SECONDARY, 18, Vector2(130, 64))
		MenuKit.tighten(skin_button)
		skin_button.pressed.connect(cycle_skin)
		srow.add_child(skin_button)
	return p


func _refresh_subtitle() -> void:
	if _sub_label == null:
		return
	var card: MapCard = GameState.current_map as MapCard
	if loadout_mode:
		_sub_label.text = ("Étape 2/2 · %s" % card.display_name) if card != null else "Étape 2/2"
	elif shop_mode:
		_sub_label.text = "Achète des armes avec ton or. Légendaires : butin uniquement."
	else:
		_sub_label.text = "Un large choix d'armes pour ton style de jeu.  %d / %d modèles débloqués" % [
			owned.size(), WeaponCatalog.all().size()]


## Bascule Collection / Armurerie (consultation).
func set_shop_mode(on: bool) -> void:
	if loadout_mode or shop_mode == on:
		return
	shop_mode = on
	if _tab_shop != null:
		_tab_shop.set_pressed_no_signal(on)
		_tab_collection.set_pressed_no_signal(not on)
	MenuKit.sfx(&"click_soft", -4.0)
	_refresh_subtitle()
	_fill()
	show_weapon_detail(detail_weapon, false)


# --- Sections -------------------------------------------------------------------------

## Modèles à afficher pour une catégorie (catalogue complet en consultation, possédés sinon),
## triés par rareté croissante (comme la planche).
func _models_of(cat: StringName) -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	if loadout_mode:
		var seen := {}
		for e: Dictionary in stash:
			var w: WeaponData = e["data"]
			if w.category == cat and not seen.has(w.id):
				seen[w.id] = true
				out.append(w)
	else:
		for w: WeaponData in WeaponCatalog.all():
			if w.category == cat:
				out.append(w)
	out.sort_custom(func(a: WeaponData, b: WeaponData) -> bool:
		return a.rarity < b.rarity if a.rarity != b.rarity else String(a.id) < String(b.id))
	return out


## Catégories affichées : celles de WeaponData.CATEGORIES, puis d'éventuelles autres.
func _categories() -> Array[StringName]:
	var out: Array[StringName] = []
	for c: StringName in WeaponData.CATEGORIES:
		out.append(c)
	var extra: Array[WeaponData] = []
	if not loadout_mode:
		extra = WeaponCatalog.all()
	else:
		for e: Dictionary in stash:
			extra.append(e["data"] as WeaponData)
	for w: WeaponData in extra:
		if not out.has(w.category):
			out.append(w.category)
	return out


func _fill() -> void:
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	tiles.clear()
	sections.clear()
	if loadout_mode:
		_fill_loadout()
		return
	for cat: StringName in _categories():
		var models := _models_of(cat)
		if models.is_empty():
			continue
		_list.add_child(_section_header(cat, models[0]))
		var grid := GridContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(grid)
		sections[cat] = grid
		for w: WeaponData in models:
			var ids: Array[int] = []
			ids.assign(owned.get(String(w.id), []))
			var t := WeaponTile.new(w, ids, ids.is_empty() and not shop_mode)
			if shop_mode:
				t.set_shop_status(Profile.weapon_shop_status(w.id))
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			t.pressed.connect(func() -> void: _on_tile_pressed(t))
			grid.add_child(t)
			tiles.append(t)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 4)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_list.add_child(pad)
	if tiles.is_empty():
		_empty_label = MenuKit.label("Ta réserve est vide. Extrais-toi avec des armes pour la remplir.",
			20, MenuKit.TEXT_DIM, MenuKit.nunito(800), 4)
		_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(_empty_label)
	_update_columns()
	_refresh_tiles()


## Arsenal de départ : une seule grille (cartes « D »), armes possédées triées par rareté
## décroissante puis catégorie ; les équipements à la fin.
func _fill_loadout() -> void:
	var models: Array[WeaponData] = []
	for cat: StringName in _categories():
		models.append_array(_models_of(cat))
	models.sort_custom(func(a: WeaponData, b: WeaponData) -> bool:
		if a.is_gadget() != b.is_gadget():
			return not a.is_gadget()
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		return String(a.id) < String(b.id))
	var grid := GridContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.columns = int(Balance.get_value("menu", "loadout_columns", 4))
	_list.add_child(grid)
	sections[&"all"] = grid
	for w: WeaponData in models:
		var ids: Array[int] = []
		ids.assign(owned.get(String(w.id), []))
		var t := WeaponTile.new(w, ids, false)
		t.style_d = true
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.pressed.connect(func() -> void: _on_tile_pressed(t))
		grid.add_child(t)
		tiles.append(t)
	if tiles.is_empty():
		_empty_label = MenuKit.label("Ta réserve est vide. Extrais-toi avec des armes pour la remplir.",
			20, MenuKit.TEXT_DIM, MenuKit.nunito(600), 0)
		_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(_empty_label)
	_refresh_tiles()


## Titre de section : pictogramme blanc (silhouette de la première arme) + titre en capitales.
func _section_header(cat: StringName, sample: WeaponData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = WeaponIcon.texture_for(sample)
	if cat == WeaponData.CAT_GADGET:
		var ic := SectionGlyph.new()
		ic.custom_minimum_size = Vector2(54, 30)
		row.add_child(ic)
	elif tex == null:
		# Catégorie sans sprite (revolver, fusil à pompe…) : silhouette dessinée de la catégorie.
		var wi := WeaponIcon.new(sample)
		wi.silhouette = true
		wi.use_equipped_skin = false
		wi.custom_minimum_size = Vector2(54, 30)
		row.add_child(wi)
	else:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(54, 30)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.material = _silhouette_material()
		row.add_child(tr)
	var title := String(WeaponData.CATEGORY_TITLES.get(cat, WeaponData.CATEGORY_NAMES.get(cat, String(cat))))
	var l := MenuKit.label(title.to_upper(), 22, MenuKit.TEXT, MenuKit.nunito(1000), 3)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.1)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row


static func _silhouette_material() -> ShaderMaterial:
	if _silhouette == null:
		_silhouette = Shader.new()
		_silhouette.code = "shader_type canvas_item;\nvoid fragment() {\n\tCOLOR = vec4(0.95, 0.96, 1.0, texture(TEXTURE, UV).a * COLOR.a);\n}\n"
	var m := ShaderMaterial.new()
	m.shader = _silhouette
	return m


func _update_columns() -> void:
	if _scroll == null or loadout_mode:
		return
	var w: float = (_scroll.size.x if _scroll.size.x > 0.0 else 800.0) - 10.0
	var cw: float = Balance.get_float("menu", "weapon_card_width", 176.0)
	var cols: int = clampi(floori((w + 10.0) / (cw + 10.0)), 1, int(Balance.get_value("menu", "arsenal_max_columns", 5)))
	# Pas plus de colonnes que la plus grande section : les cartes s'étirent sur toute la largeur.
	var biggest := 1
	for g: GridContainer in sections.values():
		biggest = maxi(biggest, g.get_child_count())
	cols = mini(cols, biggest)
	for g: GridContainer in sections.values():
		g.columns = cols


func _refresh_tiles() -> void:
	var nw := 0
	var slot_of := {}
	for u: int in selected_uids:
		var w := _weapon_of_uid(u)
		if w == null:
			continue
		slot_of[u] = 0 if w.is_gadget() else nw
		if not w.is_gadget():
			nw += 1
	for t: WeaponTile in tiles:
		var s := -1
		if loadout_mode:
			for u: int in t.uids:
				if slot_of.has(u):
					s = int(slot_of[u])
		t.set_slot(s)
		t.set_focused_detail(detail_weapon != null and t.weapon == detail_weapon)


func _tile_of(w: WeaponData) -> WeaponTile:
	for t: WeaponTile in tiles:
		if t.weapon == w:
			return t
	return null


# --- Sélection ------------------------------------------------------------------------

func _on_tile_pressed(t: WeaponTile) -> void:
	# Arsenal de départ : 1er tap = fiche, 2e tap sur l'arme affichée = équiper / retirer.
	if loadout_mode and not t.locked and detail_weapon == t.weapon:
		toggle_model(t.weapon)
		_refresh_equip_button()
		return
	MenuKit.sfx(&"click_soft", -4.0)
	show_weapon_detail(t.weapon)


func selected_weapon_count() -> int:
	var n := 0
	for u: int in selected_uids:
		var w := _weapon_of_uid(u)
		if w != null and not w.is_gadget():
			n += 1
	return n


func selected_gadget_uid() -> int:
	for u: int in selected_uids:
		var w := _weapon_of_uid(u)
		if w != null and w.is_gadget():
			return u
	return -1


## Ajoute ou retire un modèle de l'arsenal de départ (un exemplaire). Un équipement remplace
## l'équipement déjà choisi. Renvoie false si les emplacements d'armes sont pleins.
func toggle_model(w: WeaponData) -> bool:
	var ids: Array = owned.get(String(w.id), [])
	if ids.is_empty():
		return false
	for u: int in ids:
		if selected_uids.has(u):
			selected_uids.erase(u)
			MenuKit.sfx(&"panel_close", -4.0)
			_after_change()
			return true
	if w.is_gadget():
		var g := selected_gadget_uid()
		if g >= 0:
			selected_uids.erase(g)
	elif selected_weapon_count() >= Profile.loadout_slots():
		MenuKit.sfx(&"error")
		_shake(_slots_row)
		if _hint != null:
			_hint.text = "Emplacements pleins : touche une arme placée pour la retirer."
		return false
	selected_uids.append(int(ids[0]))
	MenuKit.sfx(&"item_equip", -4.0)
	_after_change()
	return true


## Compatibilité : bascule l'arme d'un exemplaire précis.
func toggle_weapon(uid: int) -> bool:
	var w := _weapon_of_uid(uid)
	return toggle_model(w) if w != null else false


func _after_change() -> void:
	_refresh_slots(true)
	_refresh_tiles()
	_refresh_equip_button()


func _on_slot_pressed(i: int) -> void:
	var k := 0
	for u: int in selected_uids:
		var w := _weapon_of_uid(u)
		if w != null and not w.is_gadget():
			if k == i:
				show_weapon_detail(w, false)
				toggle_model(w)
				return
			k += 1


func _on_gadget_slot_pressed() -> void:
	var g := selected_gadget_uid()
	if g >= 0:
		var w := _weapon_of_uid(g)
		show_weapon_detail(w, false)
		toggle_model(w)
	elif sections.has(WeaponData.CAT_GADGET):
		# Emplacement vide : fait défiler jusqu'à la section « Autres ».
		_scroll.ensure_control_visible(sections[WeaponData.CAT_GADGET])
	else:
		for t: WeaponTile in tiles:
			if t.weapon.is_gadget():
				_scroll.ensure_control_visible(t)
				show_weapon_detail(t.weapon)
				break


## Compatibilité : détail d'un exemplaire.
func show_detail(uid: int, with_anim: bool = true) -> void:
	show_weapon_detail(_weapon_of_uid(uid), with_anim)


## Affiche le détail d'un modèle (stats en barres, rareté, quantité possédée).
func show_weapon_detail(w: WeaponData, with_anim: bool = true) -> void:
	detail_weapon = w
	_refresh_tiles()
	if w == null:
		_d_name.text = "Aucune arme"
		_d_cat.text = ""
		_d_owned.text = ""
		_d_desc.text = ""
		_d_rarity.visible = false
		_d_icon.set_weapon(null)
		_d_bars.show_weapon(null)
		_refresh_equip_button()
		if skin_button != null:
			skin_button.disabled = true
		_refresh_shop_box(null)
		return
	var rc: Color = MenuKit.rarity_color(w.rarity)
	_d_style.border_color = Color(rc, 0.85)
	_d_style.shadow_color = Color(rc, 0.35 if w.rarity >= 3 else 0.15)
	_d_style.shadow_size = 14
	_d_style.shadow_offset = Vector2.ZERO
	_d_icon.set_weapon(w)
	_d_name.text = w.display_name
	_d_rarity.visible = true
	(_d_rarity.get_node(^"Text") as Label).text = MenuKit.rarity_name(w.rarity)
	(_d_rarity.get_node(^"Text") as Label).add_theme_color_override("font_color",
		Color(0.16, 0.1, 0.02) if w.rarity >= 4 else MenuKit.TEXT)
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = rc if loadout_mode else rc.darkened(0.1)
	if loadout_mode:
		(_d_rarity.get_node(^"Text") as Label).add_theme_color_override("font_color", Color(0.07, 0.04, 0.14))
		_refresh_equip_button()
	_d_cat.text = String(WeaponData.CATEGORY_NAMES.get(w.category, "Arme")) + ("  ·  explosif" if w.is_explosive() else "")
	var n := owned_count(w.id)
	_d_owned.text = ("Possédée ×%d" % n) if n > 0 else "Non possédée"
	_d_owned.add_theme_color_override("font_color", MenuKit.TEXT if n > 0 else MenuKit.TEXT_DIM)
	_d_bars.show_weapon(w, MenuKit.TEXT if loadout_mode else rc.lightened(0.15))
	if shop_mode:
		_d_desc.text = w.description
	else:
		_d_desc.text = w.description if n > 0 or loadout_mode \
			else (w.description + ("\n" if not w.description.is_empty() else "") + _how_to_get(w))
	_refresh_shop_box(w)
	_refresh_skin_row()
	if with_anim and is_inside_tree():
		_d_icon.pivot_offset = _d_icon.size * 0.5
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(_d_icon, "scale", Vector2.ONE, 0.25).from(Vector2(0.85, 0.85))


func _refresh_slots(animate: bool) -> void:
	if not loadout_mode:
		return
	var weapons: Array[WeaponData] = []
	var gadget: WeaponData = null
	for u: int in selected_uids:
		var w := _weapon_of_uid(u)
		if w == null:
			continue
		if w.is_gadget():
			gadget = w
		else:
			weapons.append(w)
	for i: int in slot_buttons.size():
		_fill_slot(slot_buttons[i], weapons[i] if i < weapons.size() else null, "%02d" % (i + 1),
			animate and i == weapons.size() - 1)
	_fill_slot(gadget_slot_button, gadget, "GADGET", false)
	validate_button.disabled = weapons.is_empty()
	if _hint != null:
		_hint.text = ("Touche une arme puis Équiper (1 à %d armes + 1 gadget)." % Profile.loadout_slots()) \
			if weapons.is_empty() else ("%d / %d armes · %s. Touche un emplacement pour le vider." % [
				weapons.size(), Profile.loadout_slots(), gadget.display_name if gadget != null else "sans gadget"])


## Emplacement « D » : carte encre à coin haut droit coupé, liseré gauche à la couleur de rareté
## (blanc atténué si vide), numéro « 01 » en haut à gauche, icône + nom (« + LIBRE » si vide).
func _fill_slot(b: Button, w: WeaponData, tag: String, animate: bool) -> void:
	for c: Node in b.get_children():
		b.remove_child(c)
		c.queue_free()
	var accent: Color = MenuKit.rarity_color(w.rarity) if w != null else Color(1, 1, 1, 0.25)
	var mk := func(bg: Color) -> CutBox:
		var c := CutBox.make(bg, 20.0, Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
		c.corners = CutBox.CUT_TOP_RIGHT
		c.accent_width = 5.0
		c.accent_color = accent
		return c
	b.add_theme_stylebox_override("normal", mk.call(Color(MenuKit.NIGHT_DEEP, 0.82)))
	b.add_theme_stylebox_override("hover", mk.call(Color(MenuKit.NIGHT_PANEL, 0.9)))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0, 0, 0, 0.9)))
	b.add_theme_stylebox_override("hover_pressed", mk.call(Color(0, 0, 0, 0.9)))
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.TEXT
	f.border_width = 2.0
	f.cut = 22.0
	f.corners = CutBox.CUT_TOP_RIGHT
	f.grow = 3.0
	b.add_theme_stylebox_override("focus", f)
	b.text = ""
	b.tooltip_text = "Retirer" if w != null else "Emplacement libre"
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16
	row.offset_right = -12
	row.offset_top = 22
	row.offset_bottom = -6
	row.add_theme_constant_override("separation", 12)
	b.add_child(row)
	if w != null:
		var ic := WeaponIcon.new(w)
		ic.custom_minimum_size = Vector2(minf(b.custom_minimum_size.x * 0.42, 110.0), 0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
	var name_l := MenuKit.label(w.display_name if w != null else "+ libre", 17,
		MenuKit.TEXT if w != null else Color(1, 1, 1, 0.55), MenuKit.nunito(600), 0)
	name_l.uppercase = true
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_l)
	var num := MenuKit.label(tag, 15, Color(1, 1, 1, 0.5), MenuKit.nunito(600), 0)
	num.position = Vector2(14, 6)
	b.add_child(num)
	if w != null and animate and b.is_inside_tree():
		b.pivot_offset = b.size * 0.5
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(b, "scale", Vector2.ONE, 0.25).from(Vector2(1.08, 1.08))


func _shake(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	var x: float = c.position.x
	var tw := create_tween()
	for k: int in 4:
		tw.tween_property(c, "position:x", x + (8.0 if k % 2 == 0 else -8.0), 0.04)
	tw.tween_property(c, "position:x", x, 0.04)


# --- Armurerie (consultation) ---------------------------------------------------------------

## Comment obtenir un modèle non possédé (onglet Collection).
func _how_to_get(w: WeaponData) -> String:
	var st := Profile.weapon_shop_status(w.id)
	match st.get("state"):
		Economy.STATE_BUYABLE:
			return "En vente à l'armurerie : %s or." % Economy.fmt(int(st["price"]))
		Economy.STATE_LOCKED:
			return str(st["text"]) + ", puis achète-la à l'armurerie."
	return "Trouve-la en raid : jamais en vente."


func _refresh_shop_box(w: WeaponData) -> void:
	if _d_shop == null:
		return
	_d_shop.visible = shop_mode and w != null
	_d_desc.max_lines_visible = 2 if shop_mode else 4
	# Armurerie : panneau plus compact (icône réduite, pas de ligne de skin).
	_d_icon.custom_minimum_size.y = 80.0 if shop_mode else 124.0
	if _d_skin != null:
		(_d_skin.get_parent() as Control).visible = not shop_mode
	if not _d_shop.visible:
		return
	var st := Profile.weapon_shop_status(w.id)
	var state: StringName = st["state"]
	var price := int(st["price"])
	_d_shop_bar.visible = state == Economy.STATE_LOCKED
	match state:
		Economy.STATE_BUYABLE:
			_d_shop_text.text = ("Prix : %s or" % Economy.fmt(price)) + (
				("   ·   " + str(st["text"])) if st["mode"] == WeaponData.UNLOCK_KILL else "")
			_d_shop_text.add_theme_color_override("font_color", GoldCounter.GOLD_COIN)
			buy_button.visible = true
			buy_button.disabled = not Profile.can_afford(&"gold", price)
			buy_button.text = "Acheter · %s or" % Economy.fmt(price)
			_d_shop_hint.text = ("Il te manque %s or : vends ton butin au marchand." % Economy.fmt(price - Profile.gold)) \
				if not Profile.can_afford(&"gold", price) else ("Tu en as ×%d." % owned_count(w.id) if owned_count(w.id) > 0 else "")
		Economy.STATE_LOCKED:
			_d_shop_text.text = str(st["text"])
			_d_shop_text.add_theme_color_override("font_color", Color(1.0, 0.62, 0.56))
			_d_shop_bar.max_value = float(maxi(int(st["needed"]), 1))
			_d_shop_bar.value = float(st["kills"])
			buy_button.visible = true
			buy_button.disabled = true
			buy_button.text = "%s or" % Economy.fmt(price)
			_d_shop_hint.text = "Les victimes comptent même si tu meurs."
		_:
			_d_shop_text.text = str(st["text"])
			_d_shop_text.add_theme_color_override("font_color", MenuKit.rarity_color(4).lightened(0.2))
			buy_button.visible = false
			_d_shop_hint.text = "Fouille coffres, coffres-forts et élites pour la trouver."


## Achète l'arme affichée (onglet Armurerie). Renvoie true si achetée.
func buy_selected() -> bool:
	var w := detail_weapon
	if w == null or not shop_mode:
		return false
	if not Profile.buy_weapon(w.id):
		MenuKit.sfx(&"error")
		_shake(buy_button)
		return false
	MenuKit.sfx(&"confirm_big")
	MenuKit.vibrate(40)
	_read_stash()
	var t := _tile_of(w)
	if t != null:
		var ids: Array[int] = []
		ids.assign(owned.get(String(w.id), []))
		t.set_uids(ids)
		t.pivot_offset = t.size * 0.5
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(t, "scale", Vector2.ONE, 0.3).from(Vector2(1.15, 1.15))
	for t2: WeaponTile in tiles:
		t2.set_shop_status(Profile.weapon_shop_status(t2.weapon.id))
	show_weapon_detail(w, false)
	return true


# --- Consommables emportés (arsenal de départ) ------------------------------------------------

func _refresh_consumables() -> void:
	if consumables_label == null:
		return
	var parts: PackedStringArray = []
	for e: Dictionary in Profile.consumables_preview():
		parts.append("%s ×%d" % [(e["item"] as ItemData).display_name, int(e["count"])])
	if loadout_mode:
		consumables_label.text = ("· Soins : " + (", ".join(parts) if not parts.is_empty() else "aucun en réserve")) \
			if Profile.pack_consumables else "· Soins : aucun (désactivés)"
	elif not Profile.pack_consumables:
		consumables_label.text = "Consommables emportés : aucun (désactivé)"
	elif parts.is_empty():
		consumables_label.text = "Consommables emportés : aucun soin en réserve (fabrique-en à l'atelier)"
	else:
		consumables_label.text = "Consommables emportés : " + ", ".join(parts)
	consumables_toggle.text = "Soins : oui" if Profile.pack_consumables else "Soins : non"


## Ligne « Clefs » : nombre de clefs en réserve et choix de les emporter (masquée sans clef).
func _refresh_keys() -> void:
	if keys_label == null:
		return
	var keys: Array[Dictionary] = Profile.keys_in_reserve()
	var n := 0
	for e: Dictionary in keys:
		n += int(e["count"])
	keys_label.visible = n > 0
	keys_toggle.visible = n > 0
	keys_label.text = "· %d clef%s en réserve" % [n, "s" if n > 1 else ""]
	keys_toggle.text = "Clefs : oui" if Profile.pack_keys else "Clefs : non"
	var names: PackedStringArray = []
	for e: Dictionary in keys:
		names.append((e["item"] as ItemData).display_name)
	keys_label.tooltip_text = ", ".join(names)


func toggle_keys() -> void:
	Profile.set_pack_keys(not Profile.pack_keys)
	MenuKit.sfx(&"click_soft", -4.0)
	_refresh_keys()


func toggle_consumables() -> void:
	Profile.set_pack_consumables(not Profile.pack_consumables)
	MenuKit.sfx(&"click_soft", -4.0)
	_refresh_consumables()


# --- Skins (consultation, si activés) -----------------------------------------------------

## Skins possédés applicables à l'arme affichée ; null en tête = apparence d'origine.
func applicable_skins(w: WeaponData) -> Array[SkinData]:
	var out: Array[SkinData] = [null]
	if w == null:
		return out
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_WEAPON):
		if s.applies_to(w.category, w.id) and Profile.owns_skin(s.id):
			out.append(s)
	return out


func _refresh_skin_row() -> void:
	if _d_skin == null:
		return
	var w: WeaponData = detail_weapon
	var cur: SkinData = WeaponSkin.equipped_for(w) if w != null else null
	var list := applicable_skins(w)
	_d_skin.text = "Skin : " + (cur.display_name if cur != null else "d'origine")
	if list.size() <= 1:
		_d_skin.text += "\nAchète des skins à la boutique."
	skin_button.disabled = list.size() <= 1


## Passe au skin possédé suivant pour la catégorie de l'arme affichée (aperçu immédiat).
func cycle_skin() -> void:
	var w: WeaponData = detail_weapon
	if w == null:
		return
	var list := applicable_skins(w)
	var cur: SkinData = WeaponSkin.equipped_for(w)
	var idx: int = list.find(cur)
	var nxt: SkinData = list[(idx + 1) % list.size()]
	if nxt == null:
		# Retour à l'apparence d'origine : skin propre à l'arme, de catégorie et universel retirés.
		WeaponSkin.unequip(w.id)
		if cur != null and String(cur.weapon_id).is_empty():
			Profile.equip_weapon_skin(&"", cur.weapon_category)
	else:
		WeaponSkin.equip(nxt.id)
	MenuKit.sfx(&"item_equip", -4.0)
	_d_icon.refresh()
	for t: WeaponTile in tiles:
		t.refresh_skin()
	_refresh_skin_row()


# --- Actions --------------------------------------------------------------------------

## « Valider et partir » : enregistre l'arsenal (armes + équipement), lance le raid, charge le raid.
func validate_and_go() -> bool:
	if not loadout_mode or selected_weapon_count() == 0:
		MenuKit.sfx(&"error")
		return false
	Profile.set_loadout(selected_uids)
	if not Profile.can_start_raid():
		return false
	GameState.begin_raid()
	MenuKit.sfx(&"confirm_big")
	MenuKit.vibrate(40)
	if raid_scene != "":
		MenuKit.go_to(self, raid_scene, Balance.get_float("menu", "fade_time", 0.3) * 1.5)
	return true


func go_back() -> void:
	MenuKit.sfx(&"back")
	if loadout_mode:
		# Le choix en cours est gardé pour le prochain passage (sans lancer de raid).
		Profile.set_loadout(selected_uids)
	MenuKit.go_to(self, MenuKit.MAP_SELECT_SCENE if loadout_mode else MenuKit.MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()


## Pictogramme de la section « Autres » : grenade stylisée dans un cercle de visée.
class SectionGlyph extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var c := Vector2(s * 0.55, size.y * 0.5)
		var col := Color(0.95, 0.96, 1.0)
		draw_arc(c, s * 0.42, 0, TAU, 24, col, maxf(2.0, s * 0.08), true)
		draw_circle(c + Vector2(0, s * 0.05), s * 0.2, col)
		draw_rect(Rect2(c + Vector2(-s * 0.08, -s * 0.28), Vector2(s * 0.16, s * 0.12)), col)
