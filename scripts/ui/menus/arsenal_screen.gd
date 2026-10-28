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

@export var loadout_mode: bool = true

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

var validate_button: Button = null
var back_button: Button = null
var skin_button: Button = null
var slot_buttons: Array[Button] = []
var gadget_slot_button: Button = null
var gem_counter: GemCounter = null

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
	(validate_button if loadout_mode and not validate_button.disabled else back_button).grab_focus.call_deferred()


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
	var sub_text: String
	var card: MapCard = GameState.current_map as MapCard
	if loadout_mode:
		sub_text = "%s  ·  %s  ·  %s" % [card.display_name, card.biome_name(), card.difficulty_name()] \
			if card != null else "Choisis tes armes pour le raid."
	else:
		var n_models := 0
		for id: String in owned:
			n_models += 1
		sub_text = "Un large choix d'armes pour ton style de jeu.  %d / %d modèles débloqués" % [
			n_models, WeaponCatalog.all().size()]
	tcol.add_child(MenuKit.label(sub_text, 16, MenuKit.TEXT_DIM, MenuKit.nunito(800)))
	gem_counter = GemCounter.new()
	gem_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem_counter.pressed.connect(func() -> void: MenuKit.go_to(self, MenuKit.SHOP_SCENE))
	head.add_child(gem_counter)

	if loadout_mode:
		root.add_child(_build_slots_bar())

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


## Barre : 3 emplacements d'armes + 1 d'équipement, rappel, bouton de validation.
func _build_slots_bar() -> Control:
	var p := PanelContainer.new()
	var st := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.92), MenuKit.BORDER, 16, 1, 8)
	st.content_margin_left = 12
	st.content_margin_right = 10
	p.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 8)
	row.add_child(_slots_row)
	var sw: float = Balance.get_float("menu", "loadout_slot_width", 132.0)
	for i: int in Profile.loadout_slots():
		var b := _slot_button(sw)
		b.pressed.connect(func() -> void: _on_slot_pressed(i))
		_slots_row.add_child(b)
		slot_buttons.append(b)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.15)
	sep.custom_minimum_size = Vector2(2, 0)
	_slots_row.add_child(sep)
	gadget_slot_button = _slot_button(sw)
	gadget_slot_button.pressed.connect(_on_gadget_slot_pressed)
	_slots_row.add_child(gadget_slot_button)

	var wcol := VBoxContainer.new()
	wcol.alignment = BoxContainer.ALIGNMENT_CENTER
	wcol.add_theme_constant_override("separation", 0)
	wcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wcol)
	var w1 := MenuKit.label("Les armes emportées sont perdues si tu meurs.", 16, Color(1.0, 0.72, 0.66), MenuKit.nunito(900))
	w1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wcol.add_child(w1)
	_hint = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(750))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wcol.add_child(_hint)
	validate_button = MenuKit.button("Valider et partir", MenuKit.Style.PRIMARY, 24, Vector2(240, 76))
	MenuKit.tighten(validate_button, 16)
	validate_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	validate_button.pressed.connect(validate_and_go)
	row.add_child(validate_button)
	return p


func _slot_button(w: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(w, 80)
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
			var t := WeaponTile.new(w, ids, ids.is_empty())
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


## Titre de section : pictogramme blanc (silhouette de la première arme) + titre en capitales.
func _section_header(cat: StringName, sample: WeaponData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = WeaponIcon.texture_for(sample)
	if cat == WeaponData.CAT_GADGET or tex == null:
		var ic := SectionGlyph.new()
		ic.custom_minimum_size = Vector2(54, 30)
		row.add_child(ic)
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
	if _scroll == null:
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
	if loadout_mode and not t.locked:
		toggle_model(t.weapon)
	else:
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
		if skin_button != null:
			skin_button.disabled = true
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
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = rc.darkened(0.1)
	_d_cat.text = String(WeaponData.CATEGORY_NAMES.get(w.category, "Arme")) + ("  ·  explosif" if w.is_explosive() else "")
	var n := owned_count(w.id)
	_d_owned.text = ("Possédée ×%d" % n) if n > 0 else "Non possédée"
	_d_owned.add_theme_color_override("font_color", MenuKit.TEXT if n > 0 else MenuKit.TEXT_DIM)
	_d_bars.show_weapon(w, rc.lightened(0.15))
	_d_desc.text = w.description if n > 0 or loadout_mode \
		else (w.description + ("\n" if not w.description.is_empty() else "") + "Trouve-la en raid pour la débloquer.")
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
		_fill_slot(slot_buttons[i], weapons[i] if i < weapons.size() else null, str(i + 1),
			animate and i == weapons.size() - 1)
	_fill_slot(gadget_slot_button, gadget, "Équipement", false)
	validate_button.disabled = weapons.is_empty()
	if _hint != null:
		_hint.text = ("Touche une arme pour l'emporter (1 à %d) et un équipement." % Profile.loadout_slots()) \
			if weapons.is_empty() else ("%d / %d armes · %s · touche un emplacement pour le vider." % [
				weapons.size(), Profile.loadout_slots(), gadget.display_name if gadget != null else "sans équipement"])


func _fill_slot(b: Button, w: WeaponData, tag: String, animate: bool) -> void:
	for c: Node in b.get_children():
		b.remove_child(c)
		c.queue_free()
	var st: StyleBoxFlat
	if w != null:
		var rc: Color = MenuKit.rarity_color(w.rarity)
		st = MenuKit.panel_style(Color(0.07, 0.09, 0.15, 0.97), Color(rc, 0.9), 8, 2, 0)
		st.shadow_color = Color(rc, 0.35)
		st.shadow_size = 6
		st.shadow_offset = Vector2.ZERO
	else:
		st = MenuKit.panel_style(Color(MenuKit.NIGHT_DEEP, 0.6), Color(1, 1, 1, 0.25), 8, 2, 0)
		st.shadow_size = 0
	var hov := st.duplicate() as StyleBoxFlat
	hov.bg_color = st.bg_color.lightened(0.08)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("hover_pressed", hov)
	b.text = ""
	b.tooltip_text = "Retirer" if w != null else "Emplacement libre"
	if w != null:
		var bd := MenuKit.rarity_backdrop(w.rarity)
		b.add_child(bd)
		var ic := WeaponIcon.new(w)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 10
		ic.offset_right = -10
		ic.offset_top = 16
		ic.offset_bottom = -22
		b.add_child(ic)
		var band := MenuKit.rarity_band(w.rarity, 12, 20)
		band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		band.offset_top = -20
		(band.get_node(^"Text") as Label).text = w.display_name
		(band.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_bottom_left = 7
		(band.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_bottom_right = 7
		b.add_child(band)
		if animate and b.is_inside_tree():
			b.pivot_offset = b.size * 0.5
			create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
				.tween_property(b, "scale", Vector2.ONE, 0.25).from(Vector2(1.12, 1.12))
	else:
		var plus := MenuKit.label("+", 30, Color(1, 1, 1, 0.3), MenuKit.nunito(900))
		plus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(plus)
	var num := MenuKit.label(tag, 12, Color(MenuKit.TEXT_DIM, 0.95), MenuKit.nunito(1000), 3)
	num.position = Vector2(7, 2)
	b.add_child(num)


func _shake(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	var x: float = c.position.x
	var tw := create_tween()
	for k: int in 4:
		tw.tween_property(c, "position:x", x + (8.0 if k % 2 == 0 else -8.0), 0.04)
	tw.tween_property(c, "position:x", x, 0.04)


# --- Skins (consultation, si activés) -----------------------------------------------------

## Skins possédés applicables à l'arme affichée ; null en tête = apparence d'origine.
func applicable_skins(w: WeaponData) -> Array[SkinData]:
	var out: Array[SkinData] = [null]
	if w == null:
		return out
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_WEAPON):
		if s.applies_to(w.category) and Profile.owns_skin(s.id):
			out.append(s)
	return out


func _refresh_skin_row() -> void:
	if _d_skin == null:
		return
	var w: WeaponData = detail_weapon
	var cur: SkinData = Profile.get_weapon_skin(w.category) if w != null else null
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
	var cur: SkinData = Profile.get_weapon_skin(w.category)
	var idx: int = list.find(cur)
	var nxt: SkinData = list[(idx + 1) % list.size()]
	if nxt == null:
		Profile.equip_weapon_skin(&"", w.category)
		if cur != null and cur.weapon_category == SkinData.ANY_CATEGORY:
			Profile.equip_weapon_skin(&"", SkinData.ANY_CATEGORY)
	else:
		Profile.equip_weapon_skin(nxt.id)
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
