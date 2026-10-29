class_name CraftingScreen
extends Control
## Atelier (scenes/ui/menus/crafting.tscn) : fabrique soins et équipements à partir des objets
## de la réserve (Profile.items) selon les recettes data/recipes/*.tres (RecipeData, RecipeBook).
##  - Puces : Tout · Soins · Équipement.
##  - Liste de recettes : résultat (case de rareté), nom, effet, ingrédients « 2/3 » (vert = assez,
##    rouge = manque), coût en or ; grisée si impossible.
##  - Panneau de détail : résultat, description, quantité en réserve, ingrédients détaillés
##    (groupes « Mécanisme : rouages, circuits… »), coût, « Fabriquer » (+ nombre possible).
## Les objets fabriqués vont dans la réserve ; les soins partent dans le sac au prochain raid
## (Profile.pack_consumables), les équipements rejoignent l'arsenal (emplacement Équipement).

const MAIN_MENU := "res://scenes/ui/menus/main_menu.tscn"
const MERCHANT := "res://scenes/ui/menus/merchant.tscn"

const FILTERS: Array[StringName] = [&"all", &"heal", &"gadget"]
const FILTER_NAMES := {&"all": "Tout", &"heal": "Soins", &"gadget": "Équipement"}

var filter: StringName = &"all"
var selected: RecipeData = null
var rows: Array[Button] = []
var gold_counter: GoldCounter = null
var back_button: Button = null
var craft_button: Button = null
var back_scene: String = MAIN_MENU

var _chips: Dictionary = {}
var _list: VBoxContainer = null
var _scroll: ScrollContainer = null
var _d_style: StyleBoxFlat = null
var _d_icon_holder: Control = null
var _d_name: Label = null
var _d_rarity: PanelContainer = null
var _d_effect: Label = null
var _d_desc: Label = null
var _d_stock: Label = null
var _d_ings: VBoxContainer = null
var _d_cost: Label = null
var _d_possible: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	var bg := MenuBackground.new()
	bg.dim = Balance.get_float("menu", "screen_dim", 0.45) + 0.2
	add_child(bg)
	_build()
	refresh()
	MenuKit.fade_in(self)
	(craft_button if not craft_button.disabled else back_button).grab_focus.call_deferred()


# --- Construction -----------------------------------------------------------------------

func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	back_button = MenuKit.back_button("Menu")
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var tcol := VBoxContainer.new()
	tcol.alignment = BoxContainer.ALIGNMENT_CENTER
	tcol.add_theme_constant_override("separation", -4)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tcol)
	tcol.add_child(MenuKit.title("ATELIER", 38))
	tcol.add_child(MenuKit.label("Fabrique soins et équipements avec les matériaux de ton butin.", 16,
		MenuKit.TEXT_DIM, MenuKit.nunito(800)))
	var shop := MenuKit.button("Marchand", MenuKit.Style.GHOST, 20, Vector2(160, 56))
	MenuKit.tighten(shop)
	shop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shop.pressed.connect(func() -> void:
		MenuKit.sfx(&"click")
		if ResourceLoader.exists(MERCHANT):
			MenuKit.go_to(self, MERCHANT))
	head.add_child(shop)
	gold_counter = GoldCounter.new()
	gold_counter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(gold_counter)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(chips)
	var group := ButtonGroup.new()
	for f: StringName in FILTERS:
		var c := MenuKit.chip(String(FILTER_NAMES[f]), MenuKit.GOLD, group)
		c.button_pressed = f == filter
		c.pressed.connect(func() -> void: set_filter(f))
		chips.add_child(c)
		_chips[f] = c

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)
	var list_panel := PanelContainer.new()
	var lp := MenuKit.panel_style(Color(0.035, 0.05, 0.1, 0.72), Color(1, 1, 1, 0.08), 14, 1, 10)
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

	body.add_child(_build_detail())


func _build_detail() -> Control:
	var p := PanelContainer.new()
	_d_style = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.94), MenuKit.BORDER, 16, 2, 16)
	p.add_theme_stylebox_override("panel", _d_style)
	p.custom_minimum_size = Vector2(Balance.get_float("economy", "detail_width", 360.0), 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	_d_icon_holder = Control.new()
	_d_icon_holder.custom_minimum_size = Vector2(96, 92)
	_d_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_d_icon_holder)
	var ncol := VBoxContainer.new()
	ncol.add_theme_constant_override("separation", 3)
	ncol.alignment = BoxContainer.ALIGNMENT_CENTER
	ncol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ncol)
	_d_name = MenuKit.label("", 22, MenuKit.TEXT, MenuKit.nunito(1000), 4)
	_d_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ncol.add_child(_d_name)
	_d_rarity = MenuKit.rarity_band(0, 13, 24, 6)
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).set_corner_radius_all(6)
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 10
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 10
	_d_rarity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ncol.add_child(_d_rarity)
	_d_effect = MenuKit.label("", 15, MenuKit.TEXT, MenuKit.nunito(850))
	ncol.add_child(_d_effect)
	_d_desc = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(650))
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_desc.max_lines_visible = 3
	col.add_child(_d_desc)
	_d_stock = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	col.add_child(_d_stock)
	col.add_child(MenuKit.label("INGRÉDIENTS", 14, MenuKit.TEXT_DIM, MenuKit.nunito(900)))
	_d_ings = VBoxContainer.new()
	_d_ings.add_theme_constant_override("separation", 4)
	_d_ings.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_d_ings)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", -2)
	ccol.alignment = BoxContainer.ALIGNMENT_CENTER
	ccol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ccol)
	_d_cost = MenuKit.label("", 18, GoldCounter.GOLD_COIN, MenuKit.nunito(1000), 3)
	ccol.add_child(_d_cost)
	_d_possible = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	_d_possible.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_possible.max_lines_visible = 2
	ccol.add_child(_d_possible)
	craft_button = MenuKit.button("Fabriquer", MenuKit.Style.PRIMARY, 22, Vector2(190, 68))
	MenuKit.tighten(craft_button)
	craft_button.pressed.connect(craft_selected)
	row.add_child(craft_button)
	return p


# --- Données -----------------------------------------------------------------------------

func recipes() -> Array[RecipeData]:
	var out: Array[RecipeData] = []
	for r: RecipeData in RecipeBook.all():
		if filter == &"all" or r.category == filter:
			out.append(r)
	return out


func refresh() -> void:
	var keep := selected
	for b: Button in rows:
		_list.remove_child(b)
		b.queue_free()
	rows.clear()
	for r: RecipeData in recipes():
		var b := _recipe_row(r)
		_list.add_child(b)
		rows.append(b)
	var list := recipes()
	if keep == null or not list.has(keep):
		keep = null
		for r: RecipeData in list:
			if Profile.can_craft(r.id):
				keep = r
				break
		if keep == null and not list.is_empty():
			keep = list[0]
	select(keep)


func set_filter(f: StringName) -> void:
	if filter == f:
		return
	filter = f
	if _chips.has(f):
		(_chips[f] as Button).set_pressed_no_signal(true)
	MenuKit.sfx(&"click_soft", -6.0)
	refresh()


## Effet du résultat en une ligne (« Soin +20 PV », « Équipement · 3 charges »).
static func effect_text(r: RecipeData) -> String:
	var w := r.get_result_weapon()
	if w != null:
		return "Équipement · %d charge%s" % [w.charges, "s" if w.charges > 1 else ""]
	var it := r.get_result_item()
	if it != null and it.is_usable():
		return "Soin +%d PV" % int(it.heal_amount)
	return LootDB.type_name(it.type) if it != null else ""


func _result_count_text(r: RecipeData) -> String:
	return (" ×%d" % r.result_count) if r.result_count > 1 else ""


func _recipe_row(r: RecipeData) -> Button:
	var ok := Profile.can_craft(r.id)
	var b := Button.new()
	b.text = ""
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 98)
	b.set_meta(&"recipe_id", r.id)
	var rc: Color = MenuKit.rarity_color(r.result_rarity())
	var st := MenuKit.panel_style(Color(0.07, 0.09, 0.15, 0.97), Color(rc, 0.75 if ok else 0.3), 12, 2, 0)
	b.set_meta(&"base_border", st.border_color)
	st.shadow_size = 0
	var hov := st.duplicate() as StyleBoxFlat
	hov.bg_color = st.bg_color.lightened(0.06)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("hover_pressed", hov)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MenuKit.GOLD
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(14)
	focus.set_expand_margin_all(3)
	b.add_theme_stylebox_override("focus", focus)
	MenuKit.add_feedback(b, 1.01)
	b.pressed.connect(func() -> void:
		MenuKit.sfx(&"click_soft", -4.0)
		select(r))

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -12
	row.offset_top = 6
	row.offset_bottom = -6
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var res := _result_view(r, Vector2(84, 84))
	row.add_child(res)
	var ncol := VBoxContainer.new()
	ncol.alignment = BoxContainer.ALIGNMENT_CENTER
	ncol.add_theme_constant_override("separation", 0)
	ncol.custom_minimum_size = Vector2(170, 0)
	ncol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ncol)
	var nm := MenuKit.label(r.result_name() + _result_count_text(r), 20, rc.lightened(0.25) if ok else MenuKit.TEXT, MenuKit.nunito(1000), 3)
	ncol.add_child(nm)
	ncol.add_child(MenuKit.label(effect_text(r), 14, MenuKit.TEXT_DIM, MenuKit.nunito(800)))
	if r.gold_cost > 0:
		ncol.add_child(MenuKit.label("%s or" % Economy.fmt(r.gold_cost), 15,
			GoldCounter.GOLD_COIN if Profile.gold >= r.gold_cost else MenuKit.BAD, MenuKit.nunito(1000), 3))
	var ings := HBoxContainer.new()
	ings.add_theme_constant_override("separation", 6)
	ings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ings.alignment = BoxContainer.ALIGNMENT_END
	ings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ings)
	for k: Variant in r.ingredients:
		var key := str(k)
		var need := int(r.ingredients[k])
		var have := RecipeBook.available(key, Profile.items)
		var t := EcoItemTile.new(RecipeBook.key_item(key, Profile.items), 0, "%d/%d" % [mini(have, 99), need])
		t.caption_color = MenuKit.GOOD if have >= need else MenuKit.BAD
		t.dimmed = have < need
		t.custom_minimum_size = Vector2(62, 82)
		t.focus_mode = Control.FOCUS_NONE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.tooltip_text = RecipeBook.key_name(key)
		ings.add_child(t)
	if not ok:
		row.modulate = Color(1, 1, 1, 0.72)
	return b


## Vue du résultat : icône d'arme (équipement) ou case d'objet.
func _result_view(r: RecipeData, sz: Vector2) -> Control:
	var w := r.get_result_weapon()
	if w != null:
		var holder := Panel.new()
		holder.custom_minimum_size = sz
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hs := MenuKit.rarity_style(w.rarity, false, 12)
		holder.add_theme_stylebox_override("panel", hs)
		holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		holder.add_child(MenuKit.rarity_backdrop(w.rarity))
		var ic := WeaponIcon.new(w)
		ic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Les icônes d'équipement (256×128) ont beaucoup de vide : zoom, rogné par le cadre.
		var zoom := sz.x * 0.45
		ic.offset_left = -zoom
		ic.offset_right = zoom
		ic.offset_top = -sz.y * 0.1
		ic.offset_bottom = sz.y * 0.1
		holder.add_child(ic)
		return holder
	var t := EcoItemTile.new(r.get_result_item(), r.result_count, "")
	t.custom_minimum_size = sz
	t.focus_mode = Control.FOCUS_NONE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Quantité du résultat déjà en réserve.
static func stock_of(r: RecipeData) -> int:
	if r.is_weapon_result():
		return Profile.weapon_count(r.result_weapon_id)
	return Profile.item_count(r.result_item_id)


func select(r: RecipeData) -> void:
	selected = r
	for b: Button in rows:
		var on: bool = r != null and b.get_meta(&"recipe_id") == r.id
		for sn: String in ["normal", "hover", "pressed", "hover_pressed"]:
			var st := b.get_theme_stylebox(sn) as StyleBoxFlat
			if st != null:
				st.set_border_width_all(3 if on else 2)
				st.border_color = MenuKit.GOLD if on else (b.get_meta(&"base_border") as Color)
	for c: Node in _d_icon_holder.get_children():
		_d_icon_holder.remove_child(c)
		c.queue_free()
	for c2: Node in _d_ings.get_children():
		_d_ings.remove_child(c2)
		c2.queue_free()
	if r == null:
		_d_name.text = "Aucune recette"
		craft_button.disabled = true
		return
	var rar := r.result_rarity()
	var rc: Color = MenuKit.rarity_color(rar)
	_d_style.border_color = Color(rc, 0.85)
	_d_style.shadow_color = Color(rc, 0.35 if rar >= 3 else 0.15)
	_d_style.shadow_offset = Vector2.ZERO
	var view := _result_view(r, Vector2(96, 92))
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_d_icon_holder.add_child(view)
	_d_name.text = r.result_name() + _result_count_text(r)
	(_d_rarity.get_node(^"Text") as Label).text = MenuKit.rarity_name(rar)
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = rc.darkened(0.1)
	_d_effect.text = effect_text(r)
	_d_desc.text = r.description
	var n := stock_of(r)
	_d_stock.text = ("En réserve : %d" % n) + ("  ·  part dans le sac au prochain raid" if not r.is_weapon_result() else "  ·  emplacement Équipement")
	for k: Variant in r.ingredients:
		_d_ings.add_child(_ingredient_line(str(k), int(r.ingredients[k])))
	_d_cost.text = ("Coût : %s or" % Economy.fmt(r.gold_cost)) if r.gold_cost > 0 else "Sans frais"
	_d_cost.add_theme_color_override("font_color", GoldCounter.GOLD_COIN if Profile.gold >= r.gold_cost else MenuKit.BAD)
	var can := RecipeBook.max_crafts(r, Profile.items, Profile.gold)
	_d_possible.text = ("Possible ×%d" % can) if can > 0 else _missing_text(r)
	craft_button.disabled = can <= 0


func _missing_text(r: RecipeData) -> String:
	var miss := RecipeBook.missing(r, Profile.items)
	if not miss.is_empty():
		var parts: PackedStringArray = []
		for k: Variant in miss:
			parts.append("%d %s" % [int(miss[k]), RecipeBook.key_name(str(k)).to_lower()])
		return "Manque : " + ", ".join(parts)
	if Profile.gold < r.gold_cost:
		return "Il te manque %s or" % Economy.fmt(r.gold_cost - Profile.gold)
	return ""


func _ingredient_line(key: String, need: int) -> Control:
	var have := RecipeBook.available(key, Profile.items)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var t := EcoItemTile.new(RecipeBook.key_item(key, Profile.items), 0, "")
	t.custom_minimum_size = Vector2(40, 40)
	t.focus_mode = Control.FOCUS_NONE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -3)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(MenuKit.label(RecipeBook.key_name(key), 16, MenuKit.TEXT, MenuKit.nunito(850)))
	if RecipeBook.is_group(key):
		var hint := MenuKit.label(RecipeBook.group_hint(key), 12, MenuKit.TEXT_DIM, MenuKit.nunito(700))
		hint.clip_text = true
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hint.custom_minimum_size = Vector2(150, 0)
		col.add_child(hint)
	h.add_child(MenuKit.label("%d / %d" % [have, need], 17, MenuKit.GOOD if have >= need else MenuKit.BAD, MenuKit.nunito(1000), 3))
	return h


# --- Fabrication ---------------------------------------------------------------------------

## Fabrique la recette sélectionnée (true si réussi).
func craft_selected() -> bool:
	if selected == null or not Profile.craft(selected.id):
		MenuKit.sfx(&"error")
		return false
	MenuKit.sfx(&"item_equip")
	MenuKit.vibrate(30)
	var done := selected
	refresh()
	select(done)
	if _d_icon_holder.is_inside_tree():
		_d_icon_holder.pivot_offset = _d_icon_holder.size * 0.5
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(_d_icon_holder, "scale", Vector2.ONE, 0.3).from(Vector2(1.25, 1.25))
	return true


func go_back() -> void:
	MenuKit.sfx(&"back")
	if back_scene != "":
		MenuKit.go_to(self, back_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()
