class_name ArsenalScreen
extends Control
## Écran d'arsenal, un seul composant pour deux usages :
##  - `loadout_mode = true` (scenes/ui/menus/loadout.tscn) : « Arsenal de départ », après le
##    choix de la carte. 3 emplacements en haut, tap sur une arme = ajouter/retirer, rappel
##    « perdues si tu meurs », « Valider et partir » (désactivé sans arme) →
##    Profile.set_loadout(uids), GameState.begin_raid(), raid.tscn (fondu MenuKit).
##  - `loadout_mode = false` (scenes/ui/menus/arsenal.tscn) : consultation de la réserve
##    depuis le menu principal (détail, skin d'arme appliqué en aperçu et changeable).
## Réserve : Profile.get_stash_weapons(), filtrable par catégorie (puces) et triable.

enum Sort { RARITY, DPS, CATEGORY }
const SORT_NAMES := {Sort.RARITY: "Rareté", Sort.DPS: "DPS", Sort.CATEGORY: "Type"}

@export var loadout_mode: bool = true

## Scène lancée par « Valider et partir » ("" = aucun changement de scène, pour les tests).
var raid_scene: String = MenuKit.RAID_SCENE
var stash: Array[Dictionary] = []
var tiles: Array[WeaponTile] = []
var selected_uids: Array[int] = []
var detail_uid: int = -1
var current_filter: StringName = &"all"
var sort_mode: Sort = Sort.RARITY

var validate_button: Button = null
var back_button: Button = null
var sort_button: Button = null
var skin_button: Button = null
var slot_buttons: Array[Button] = []
var filter_chips: Dictionary = {}
var gem_counter: GemCounter = null

var _grid: GridContainer = null
var _grid_scroll: ScrollContainer = null
var _chips_row: HBoxContainer = null
var _slots_row: HBoxContainer = null
var _d_style: StyleBoxFlat = null
var _d_icon: WeaponIcon = null
var _d_name: Label = null
var _d_rarity: PanelContainer = null
var _d_cat: Label = null
var _d_desc: Label = null
var _d_bars: StatBars = null
var _d_skin: Label = null
var _empty_label: Label = null
var _hint: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	var bg := MenuBackground.new()
	bg.dim = Balance.get_float("menu", "screen_dim", 0.45) + 0.1
	add_child(bg)
	stash = Profile.get_stash_weapons()
	if loadout_mode:
		for u: int in Profile.loadout:
			if _entry_of(u).is_empty() == false and selected_uids.size() < Profile.loadout_slots():
				selected_uids.append(u)
	_build()
	_fill_grid()
	var first: int = selected_uids[0] if not selected_uids.is_empty() else (int(stash[0]["uid"]) if not stash.is_empty() else -1)
	show_detail(first, false)
	_refresh_slots(false)
	MenuKit.fade_in(self)
	(validate_button if loadout_mode and not validate_button.disabled else back_button).grab_focus.call_deferred()


# --- Construction -------------------------------------------------------------------

func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)

	# En-tête : retour, titre (+ carte choisie), gemmes
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
	tcol.add_child(MenuKit.title("Arsenal de départ" if loadout_mode else "Arsenal", 38))
	var sub_text: String = "%d arme%s en réserve" % [stash.size(), "s" if stash.size() > 1 else ""]
	var card: MapCard = GameState.current_map as MapCard
	if loadout_mode and card != null:
		sub_text = "%s  ·  %s  ·  %s" % [card.display_name, card.biome_name(), card.difficulty_name()]
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
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(left)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(tools)
	var chips_wrap := Control.new()
	chips_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips_wrap.custom_minimum_size = Vector2(0, 58)
	chips_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tools.add_child(chips_wrap)
	var chips_scroll := ScrollContainer.new()
	chips_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chips_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chips_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	chips_wrap.add_child(chips_scroll)
	# Fondu à droite : indique que la rangée de filtres défile
	var fade := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(MenuKit.NIGHT_DEEP, 0.0))
	g.set_color(1, Color(MenuKit.NIGHT_DEEP, 0.95))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 32
	gt.height = 4
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	fade.offset_left = -48
	chips_wrap.add_child(fade)
	var sb := chips_scroll.get_h_scroll_bar()
	var upd := func() -> void:
		fade.visible = sb.max_value - sb.page > 2.0 and sb.value < sb.max_value - sb.page - 2.0
	sb.value_changed.connect(upd.unbind(1))
	sb.changed.connect(upd)
	_chips_row = HBoxContainer.new()
	_chips_row.add_theme_constant_override("separation", 8)
	_chips_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_scroll.add_child(_chips_row)
	_build_chips()
	sort_button = MenuKit.chip("", MenuKit.GOLD)
	sort_button.toggle_mode = false
	sort_button.pressed.connect(cycle_sort)
	tools.add_child(sort_button)
	_update_sort_text()

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.scroll_deadzone = 14
	left.add_child(_grid_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_scroll.add_child(_grid)
	_grid_scroll.resized.connect(_update_columns)
	_empty_label = MenuKit.label("", 20, MenuKit.TEXT_DIM, MenuKit.nunito(800), 4)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_empty_label)

	body.add_child(_build_detail())


## Barre des 3 emplacements + rappel + bouton de validation.
func _build_slots_bar() -> Control:
	var p := PanelContainer.new()
	var st := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.92), MenuKit.BORDER, 20, 1, 10)
	st.content_margin_left = 16
	st.content_margin_right = 12
	p.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 10)
	row.add_child(_slots_row)
	for i: int in Profile.loadout_slots():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(Balance.get_float("menu", "loadout_slot_width", 150.0), 84)
		b.pressed.connect(func() -> void: _on_slot_pressed(i))
		MenuKit.add_feedback(b, 1.04)
		_slots_row.add_child(b)
		slot_buttons.append(b)
	var warn := HBoxContainer.new()
	warn.add_theme_constant_override("separation", 10)
	warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(warn)
	var icon := MenuKit.label("!", 26, MenuKit.TEXT, MenuKit.nunito(1000))
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.custom_minimum_size = Vector2(38, 38)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ic := StyleBoxFlat.new()
	ic.bg_color = MenuKit.RED
	ic.set_corner_radius_all(19)
	icon.add_theme_stylebox_override("normal", ic)
	warn.add_child(icon)
	var wcol := VBoxContainer.new()
	wcol.alignment = BoxContainer.ALIGNMENT_CENTER
	wcol.add_theme_constant_override("separation", 0)
	wcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warn.add_child(wcol)
	var w1 := MenuKit.label("Les armes emportées sont perdues si tu meurs.", 17, Color(1.0, 0.72, 0.66), MenuKit.nunito(900))
	w1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wcol.add_child(w1)
	_hint = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(750))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wcol.add_child(_hint)
	validate_button = MenuKit.button("Valider et partir", MenuKit.Style.PRIMARY, 26, Vector2(280, 80))
	validate_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	validate_button.pressed.connect(validate_and_go)
	row.add_child(validate_button)
	return p


func _build_chips() -> void:
	var present: Array[StringName] = []
	for e: Dictionary in stash:
		var c: StringName = (e["data"] as WeaponData).category
		if not present.has(c):
			present.append(c)
	var group := ButtonGroup.new()
	var cats: Array[StringName] = [&"all"]
	for c: StringName in WeaponData.CATEGORIES:
		if present.has(c):
			cats.append(c)
	for c: StringName in cats:
		var txt: String = "Toutes" if c == &"all" else String(WeaponData.CATEGORY_NAMES.get(c, c))
		var b := MenuKit.chip(txt, MenuKit.GOLD, group)
		b.set_pressed_no_signal(c == current_filter)
		b.toggled.connect(func(on: bool) -> void:
			if on:
				MenuKit.sfx(&"tick")
				set_filter(c))
		_chips_row.add_child(b)
		filter_chips[c] = b


func _build_detail() -> Control:
	var p := PanelContainer.new()
	_d_style = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.94), MenuKit.BORDER, 20, 2, 16)
	p.add_theme_stylebox_override("panel", _d_style)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "arsenal_detail_width", 360.0), 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	_d_icon = WeaponIcon.new()
	_d_icon.custom_minimum_size = Vector2(0, 104 if loadout_mode else 130)
	col.add_child(_d_icon)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 10)
	col.add_child(nrow)
	_d_name = MenuKit.label("", 24, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	_d_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_d_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nrow.add_child(_d_name)
	_d_rarity = MenuKit.pill("", MenuKit.NIGHT, 14)
	_d_rarity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(_d_rarity)
	_d_cat = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	col.add_child(_d_cat)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	col.add_child(gap)
	_d_bars = StatBars.new()
	col.add_child(_d_bars)
	_d_desc = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(650))
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_desc.max_lines_visible = 3
	_d_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_d_desc)
	if not loadout_mode:
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


# --- Grille ---------------------------------------------------------------------------

func _sorted_filtered() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in stash:
		if current_filter == &"all" or (e["data"] as WeaponData).category == current_filter:
			out.append(e)
	match sort_mode:
		Sort.DPS:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return (a["data"] as WeaponData).get_dps() > (b["data"] as WeaponData).get_dps())
		Sort.CATEGORY:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var wa: WeaponData = a["data"]
				var wb: WeaponData = b["data"]
				var ca := WeaponData.CATEGORIES.find(wa.category)
				var cb := WeaponData.CATEGORIES.find(wb.category)
				return ca < cb if ca != cb else wa.rarity > wb.rarity)
	return out


func _fill_grid() -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	tiles.clear()
	var list := _sorted_filtered()
	for e: Dictionary in list:
		var t := WeaponTile.new(int(e["uid"]), e["data"] as WeaponData)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.pressed.connect(func() -> void: _on_tile_pressed(t))
		_grid.add_child(t)
		tiles.append(t)
	_update_columns()
	_refresh_tiles()
	if stash.is_empty():
		_empty_label.text = "Ta réserve est vide. Extrais-toi avec des armes pour la remplir."
	elif list.is_empty():
		_empty_label.text = "Aucune arme de ce type."
	else:
		_empty_label.text = ""
	_empty_label.visible = not _empty_label.text.is_empty()


func _update_columns() -> void:
	if _grid == null:
		return
	var w: float = _grid_scroll.size.x if _grid_scroll.size.x > 0.0 else 800.0
	var tw: float = Balance.get_float("menu", "weapon_tile_width", 168.0)
	_grid.columns = maxi(1, floori((w + 12.0) / (tw + 12.0)))


func _refresh_tiles() -> void:
	for t: WeaponTile in tiles:
		t.set_slot(selected_uids.find(t.uid) if loadout_mode else -1)
		t.set_focused_detail(t.uid == detail_uid)


func set_filter(c: StringName) -> void:
	current_filter = c
	_fill_grid()


func cycle_sort() -> void:
	sort_mode = ((int(sort_mode) + 1) % SORT_NAMES.size()) as Sort
	MenuKit.sfx(&"tick")
	_update_sort_text()
	_fill_grid()


func _update_sort_text() -> void:
	if sort_button != null:
		sort_button.text = "Tri : " + String(SORT_NAMES[sort_mode])


func _entry_of(uid: int) -> Dictionary:
	for e: Dictionary in stash:
		if int(e["uid"]) == uid:
			return e
	return {}


func _tile_of(uid: int) -> WeaponTile:
	for t: WeaponTile in tiles:
		if t.uid == uid:
			return t
	return null


# --- Sélection ------------------------------------------------------------------------

func _on_tile_pressed(t: WeaponTile) -> void:
	if loadout_mode:
		toggle_weapon(t.uid)
	else:
		MenuKit.sfx(&"click_soft", -4.0)
	show_detail(t.uid)


## Ajoute ou retire une arme de l'arsenal de départ. Renvoie false si les emplacements sont pleins.
func toggle_weapon(uid: int) -> bool:
	if _entry_of(uid).is_empty():
		return false
	if selected_uids.has(uid):
		selected_uids.erase(uid)
		MenuKit.sfx(&"panel_close", -4.0)
	elif selected_uids.size() >= Profile.loadout_slots():
		MenuKit.sfx(&"error")
		_shake(_slots_row)
		if _hint != null:
			_hint.text = "Emplacements pleins : touche une arme placée pour la retirer."
		return false
	else:
		selected_uids.append(uid)
		MenuKit.sfx(&"item_equip", -4.0)
	_refresh_slots(true)
	_refresh_tiles()
	return true


func _on_slot_pressed(i: int) -> void:
	if i < selected_uids.size():
		var u: int = selected_uids[i]
		show_detail(u, false)
		toggle_weapon(u)


## Affiche le détail d'une arme (stats en barres, rareté).
func show_detail(uid: int, with_anim: bool = true) -> void:
	detail_uid = uid
	var e := _entry_of(uid)
	var w: WeaponData = e.get("data") as WeaponData
	_refresh_tiles()
	if w == null:
		_d_name.text = "Aucune arme"
		_d_cat.text = ""
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
	(_d_rarity.get_node(^"Text") as Label).text = w.get_rarity_name()
	var rs := _d_rarity.get_theme_stylebox("panel") as StyleBoxFlat
	rs.bg_color = rc.darkened(0.3)
	_d_cat.text = "%s%s" % [w.get_category_name(), ("  ·  explosif" if w.is_explosive() else "")]
	_d_bars.show_weapon(w, rc.lightened(0.15))
	_d_desc.text = w.description
	_refresh_skin_row()
	if with_anim and is_inside_tree():
		_d_icon.pivot_offset = _d_icon.size * 0.5
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(_d_icon, "scale", Vector2.ONE, 0.25).from(Vector2(0.85, 0.85))


func _refresh_slots(animate: bool) -> void:
	if not loadout_mode:
		return
	for i: int in slot_buttons.size():
		var b: Button = slot_buttons[i]
		for c: Node in b.get_children():
			b.remove_child(c)
			c.queue_free()
		var filled: bool = i < selected_uids.size()
		var w: WeaponData = (_entry_of(selected_uids[i]).get("data") as WeaponData) if filled else null
		var st: StyleBoxFlat
		if w != null:
			st = MenuKit.rarity_style(w.rarity, false, 14)
		else:
			st = MenuKit.panel_style(Color(MenuKit.NIGHT_DEEP, 0.6), Color(1, 1, 1, 0.28), 14, 2, 6)
			st.shadow_size = 0
			st.border_blend = false
		var hov := st.duplicate() as StyleBoxFlat
		hov.bg_color = st.bg_color.lightened(0.08)
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", hov)
		b.add_theme_stylebox_override("pressed", hov)
		b.add_theme_stylebox_override("hover_pressed", hov)
		b.text = ""
		b.tooltip_text = "Retirer" if filled else "Emplacement libre"
		var num := MenuKit.label(str(i + 1), 14, Color(MenuKit.TEXT_DIM, 0.9), MenuKit.nunito(1000))
		num.position = Vector2(9, 4)
		b.add_child(num)
		if w != null:
			var ic := WeaponIcon.new(w)
			ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			ic.offset_left = 18
			ic.offset_right = -10
			ic.offset_top = 6
			ic.offset_bottom = -22
			b.add_child(ic)
			var n := MenuKit.label(w.display_name, 13, MenuKit.TEXT, MenuKit.nunito(900), 3)
			n.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			n.offset_top = -22
			n.offset_bottom = -4
			n.offset_left = 6
			n.offset_right = -6
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			n.clip_text = true
			n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.add_child(n)
			if animate and i == selected_uids.size() - 1 and b.is_inside_tree():
				b.pivot_offset = b.size * 0.5
				create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
					.tween_property(b, "scale", Vector2.ONE, 0.25).from(Vector2(1.12, 1.12))
		else:
			var plus := MenuKit.label("+", 34, Color(1, 1, 1, 0.3), MenuKit.nunito(900))
			plus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			b.add_child(plus)
	validate_button.disabled = selected_uids.is_empty()
	if _hint != null:
		var n_sel: int = selected_uids.size()
		_hint.text = "Touche une arme pour l'emporter (1 à %d)." % Profile.loadout_slots() if n_sel == 0 \
			else "%d / %d emplacements · touche une arme placée pour la retirer." % [n_sel, Profile.loadout_slots()]


func _shake(c: Control) -> void:
	if c == null or not c.is_inside_tree():
		return
	var x: float = c.position.x
	var tw := create_tween()
	for k: int in 4:
		tw.tween_property(c, "position:x", x + (8.0 if k % 2 == 0 else -8.0), 0.04)
	tw.tween_property(c, "position:x", x, 0.04)


# --- Skins (consultation) -------------------------------------------------------------

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
	var w: WeaponData = _entry_of(detail_uid).get("data") as WeaponData
	var cur: SkinData = Profile.get_weapon_skin(w.category) if w != null else null
	var list := applicable_skins(w)
	_d_skin.text = "Skin : " + (cur.display_name if cur != null else "d'origine")
	if list.size() <= 1:
		_d_skin.text += "\nAchète des skins à la boutique."
	skin_button.disabled = list.size() <= 1


## Passe au skin possédé suivant pour la catégorie de l'arme affichée (aperçu immédiat).
func cycle_skin() -> void:
	var w: WeaponData = _entry_of(detail_uid).get("data") as WeaponData
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

## « Valider et partir » : enregistre l'arsenal, lance le raid côté profil, charge le raid.
func validate_and_go() -> bool:
	if not loadout_mode or selected_uids.is_empty():
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
