class_name MerchantScreen
extends Control
## Inventaire (scenes/ui/menus/merchant.tscn, ancien « Marchand ») : réserve d'objets extraits
## (Profile.items) et vente au marchand contre des pièces d'or.
##  - Puces de filtre : Tout · Valeurs · Matériaux · Soins · Clefs · Armes en double.
##  - Grille d'objets (case de rareté + prix unitaire) ; marqueur « atelier » sur les objets qui
##    servent à une recette (RecipeBook.usage_text).
##  - Panneau de détail : nom, rareté, type, quantité, prix unitaire, « Sert à : … », description,
##    boutons « Vendre 1 » et « Tout vendre (×N) » ; armes en double : « Vendre un exemplaire ».
##  - Vente d'un objet Rare ou mieux ([economy] confirm_min_rarity) : fenêtre de confirmation.
##  - Total d'or animé (GoldCounter) + « +N or » qui s'envole à chaque vente.
## Construit en code (charte bleu nuit de MenuKit) ; aucun _process.

const MAIN_MENU := "res://scenes/ui/menus/main_menu.tscn"
const CRAFTING := "res://scenes/ui/menus/crafting.tscn"

const FILTERS: Array[StringName] = [&"all", &"valuable", &"material", &"consumable", &"key", &"weapons"]
const FILTER_NAMES := {
	&"all": "Tout", &"valuable": "Valeurs", &"material": "Matériaux", &"consumable": "Soins",
	&"key": "Clefs", &"weapons": "Armes en double",
}

var filter: StringName = &"all"
## Sélection : id d'objet (filtres objets) ou id d'arme (filtre armes).
var selected_id: StringName = &""
var tiles: Array[Control] = []
var gold_counter: GoldCounter = null
var back_button: Button = null
var sell_one_button: Button = null
var sell_all_button: Button = null
## Dernière fenêtre de confirmation ouverte (tests).
var last_confirm: ConfirmPanel = null
## Destination du bouton retour ("" = aucun changement de scène, tests).
var back_scene: String = MAIN_MENU

var _chips: Dictionary = {}
var _grid: GridContainer = null
var _scroll: ScrollContainer = null
var _empty: Label = null
var _d_panel: PanelContainer = null
var _d_style: StyleBoxFlat = null
var _d_tile: EcoItemTile = null
var _d_name: Label = null
var _d_rarity: PanelContainer = null
var _d_meta: Label = null
var _d_price: Label = null
var _d_use: Label = null
var _d_desc: Label = null
var _d_box: VBoxContainer = null
var _d_none: Label = null
var _total_label: Label = null


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
	back_button.grab_focus.call_deferred()


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
	tcol.add_child(MenuKit.title("INVENTAIRE", 38))
	_total_label = MenuKit.label("", 16, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	tcol.add_child(_total_label)
	var craft := MenuKit.button("Atelier", MenuKit.Style.GHOST, 20, Vector2(150, 56))
	MenuKit.tighten(craft)
	craft.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	craft.pressed.connect(func() -> void:
		MenuKit.sfx(&"click")
		if ResourceLoader.exists(CRAFTING):
			MenuKit.go_to(self, CRAFTING))
	head.add_child(craft)
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
	var lp := MenuKit.panel_style(Color(0.035, 0.05, 0.1, 0.72), Color(1, 1, 1, 0.08), 14, 1, 12)
	list_panel.add_theme_stylebox_override("panel", lp)
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list_panel)
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_panel.add_child(stack)
	_scroll = ScrollContainer.new()
	MenuKit.make_touch_scroll(_scroll)   # glisser au doigt partout (même sur les boutons)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 14
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_grid)
	_scroll.resized.connect(_update_columns)
	_empty = MenuKit.label("", 20, MenuKit.TEXT_DIM, MenuKit.nunito(800), 4)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_empty)

	body.add_child(_build_detail())


func _build_detail() -> Control:
	_d_panel = PanelContainer.new()
	_d_style = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.94), MenuKit.BORDER, 16, 2, 16)
	_d_panel.add_theme_stylebox_override("panel", _d_style)
	_d_panel.custom_minimum_size = Vector2(Balance.get_float("economy", "detail_width", 360.0), 0)
	var outer := VBoxContainer.new()
	_d_panel.add_child(outer)
	_d_none = MenuKit.label("Touche un objet pour le vendre.", 18, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	_d_none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_d_none.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_d_none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outer.add_child(_d_none)
	_d_box = VBoxContainer.new()
	_d_box.add_theme_constant_override("separation", 6)
	_d_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_d_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_d_box.add_child(top)
	_d_tile = EcoItemTile.new()
	_d_tile.focus_mode = Control.FOCUS_NONE
	_d_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_d_tile)
	var ncol := VBoxContainer.new()
	ncol.add_theme_constant_override("separation", 4)
	ncol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ncol.alignment = BoxContainer.ALIGNMENT_CENTER
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
	_d_meta = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	ncol.add_child(_d_meta)
	_d_price = MenuKit.label("", 20, GoldCounter.GOLD_COIN, MenuKit.nunito(1000), 3)
	_d_box.add_child(_d_price)
	_d_use = MenuKit.label("", 15, MenuKit.GOLD, MenuKit.nunito(850))
	_d_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_box.add_child(_d_use)
	_d_desc = MenuKit.label("", 14, MenuKit.TEXT_DIM, MenuKit.nunito(650))
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_d_desc.max_lines_visible = 4
	_d_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_d_box.add_child(_d_desc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_d_box.add_child(row)
	sell_one_button = MenuKit.button("Vendre 1", MenuKit.Style.SECONDARY, 20, Vector2(130, 66))
	MenuKit.tighten(sell_one_button)
	sell_one_button.pressed.connect(func() -> void: request_sell(1))
	row.add_child(sell_one_button)
	sell_all_button = MenuKit.button("Tout vendre", MenuKit.Style.PRIMARY, 20, Vector2(170, 66))
	MenuKit.tighten(sell_all_button)
	sell_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_all_button.pressed.connect(func() -> void: request_sell(-1))
	row.add_child(sell_all_button)
	return _d_panel


# --- Données ----------------------------------------------------------------------------

## Entrées visibles pour le filtre : [{id, item: ItemData, count, weapon: WeaponData|null}].
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if filter == &"weapons":
		var seen := {}
		for e: Dictionary in Profile.get_stash_weapons():
			var w: WeaponData = e["data"]
			if seen.has(w.id):
				continue
			seen[w.id] = true
			var n := Profile.weapon_count(w.id)
			if n > 1 and not w.permanent:
				out.append({"id": w.id, "item": LootDB.weapon_item(w), "count": n - 1, "weapon": w})
		return out
	for e: Dictionary in Profile.get_stash_items():
		var it: ItemData = e["item"]
		if filter == &"all" or it.type == filter or (filter == &"consumable" and it.type == ItemData.TYPE_CONSUMABLE):
			out.append({"id": it.id, "item": it, "count": int(e["count"]), "weapon": null})
	return out


## Prix unitaire de l'entrée sélectionnée.
func unit_price(e: Dictionary) -> int:
	var w: WeaponData = e.get("weapon")
	return Economy.weapon_sell_price(w) if w != null else Economy.item_sell_price(e["item"] as ItemData)


func _entry(id: StringName) -> Dictionary:
	for e: Dictionary in entries():
		if e["id"] == id:
			return e
	return {}


func refresh() -> void:
	var list := entries()
	for t: Control in tiles:
		_grid.remove_child(t)
		t.queue_free()
	tiles.clear()
	for e: Dictionary in list:
		var it: ItemData = e["item"]
		var t := EcoItemTile.new(it, int(e["count"]) if e.get("weapon") == null else int(e["count"]) + 1,
			"%s or" % Economy.fmt(unit_price(e)))
		t.caption_color = GoldCounter.GOLD_COIN
		t.craft_mark = e.get("weapon") == null and not RecipeBook.recipes_using(it.id).is_empty()
		t.set_meta(&"entry_id", e["id"])
		var id: StringName = e["id"]
		t.pressed.connect(func() -> void:
			MenuKit.sfx(&"click_soft", -4.0)
			select(id))
		_grid.add_child(t)
		tiles.append(t)
	_empty.visible = list.is_empty()
	_empty.text = "Rien à vendre ici." if filter != &"weapons" else \
		"Aucune arme en double : le marchand ne rachète que les exemplaires en trop."
	if Profile.items.is_empty() and filter != &"weapons":
		_empty.text = "Ta réserve est vide.\nExtrais-toi avec du butin pour le revendre ici."
	_update_columns()
	if selected_id == &"" or _entry(selected_id).is_empty():
		selected_id = list[0]["id"] if not list.is_empty() else &""
	_refresh_detail()
	_refresh_total()


func _refresh_total() -> void:
	var n := 0
	var v := 0
	for e: Dictionary in Profile.get_stash_items():
		n += int(e["count"])
		v += Economy.item_sell_price(e["item"] as ItemData) * int(e["count"])
	_total_label.text = "Vends ton butin contre des pièces d'or.  Réserve : %d objet%s · ≈ %s or" % [
		n, "s" if n > 1 else "", Economy.fmt(v)]


func _update_columns() -> void:
	if _scroll == null:
		return
	var w: float = (_scroll.size.x if _scroll.size.x > 0.0 else 760.0) - 10.0
	var side: float = Balance.get_float("economy", "tile_size", 92.0) + 10.0
	_grid.columns = maxi(1, floori((w + 10.0) / side))


func set_filter(f: StringName) -> void:
	if filter == f:
		return
	filter = f
	if _chips.has(f):
		(_chips[f] as Button).set_pressed_no_signal(true)
	MenuKit.sfx(&"click_soft", -6.0)
	selected_id = &""
	refresh()


func select(id: StringName) -> void:
	selected_id = id
	_refresh_detail()


func _refresh_detail() -> void:
	var e := _entry(selected_id)
	for t: Control in tiles:
		(t as EcoItemTile).set_selected(t.get_meta(&"entry_id") == selected_id)
	_d_box.visible = not e.is_empty()
	_d_none.visible = e.is_empty()
	if e.is_empty():
		_d_style.border_color = MenuKit.BORDER
		return
	var it: ItemData = e["item"]
	var w: WeaponData = e.get("weapon")
	var n := int(e["count"])
	var rc: Color = LootDB.rarity_color(it.rarity)
	_d_style.border_color = Color(rc, 0.85)
	_d_style.shadow_color = Color(rc, 0.35 if it.rarity >= 3 else 0.15)
	_d_style.shadow_offset = Vector2.ZERO
	_d_tile.set_data(it, n if w == null else n + 1, "")
	_d_name.text = it.display_name
	_d_name.add_theme_color_override("font_color", rc.lightened(0.2))
	(_d_rarity.get_node(^"Text") as Label).text = LootDB.rarity_name(it.rarity)
	(_d_rarity.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = rc.darkened(0.15)
	var price := unit_price(e)
	if w != null:
		_d_meta.text = "%s · %d exemplaires (1 gardé)" % [w.get_category_name(), n + 1]
		_d_price.text = "%s or l'exemplaire" % Economy.fmt(price)
		_d_use.text = ""
		_d_desc.text = w.description
		sell_one_button.text = "Vendre 1"
		sell_all_button.text = "Vendre ×%d · %s or" % [n, Economy.fmt(price * n)]
	else:
		_d_meta.text = "%s · en réserve ×%d" % [LootDB.type_name(it.type), n]
		_d_price.text = "%s or / unité" % Economy.fmt(price)
		var uses := RecipeBook.usage_text(it.id)
		_d_use.text = ("Sert à l'atelier : " + uses) if not uses.is_empty() else ""
		_d_desc.text = it.description
		sell_one_button.text = "Vendre 1"
		sell_all_button.text = ("Tout vendre ×%d · %s or" % [n, Economy.fmt(price * n)]) if n > 1 \
			else ("Vendre · %s or" % Economy.fmt(price))
	_d_use.visible = not _d_use.text.is_empty()
	sell_one_button.visible = n > 1
	sell_all_button.disabled = n <= 0


# --- Vente -----------------------------------------------------------------------------

## Demande de vente de `count` unités (-1 = tout) de la sélection. Rare ou mieux : confirmation
## (renvoie false, la vente se fera à la validation). Sinon vend tout de suite (true si vendu).
func request_sell(count: int) -> bool:
	var e := _entry(selected_id)
	if e.is_empty():
		return false
	var it: ItemData = e["item"]
	var n := int(e["count"]) if count < 0 else mini(count, int(e["count"]))
	if n <= 0:
		return false
	if Economy.needs_confirmation(it.rarity):
		var total := unit_price(e) * n
		var msg := "Vendre %s%s pour %s pièces d'or ?" % [it.display_name, (" ×%d" % n) if n > 1 else "", Economy.fmt(total)]
		if not RecipeBook.usage_text(it.id).is_empty():
			msg += "\nIl sert à l'atelier : %s." % RecipeBook.usage_text(it.id)
		last_confirm = ConfirmPanel.new("Vendre ?", msg, "Vendre", false)
		var id := selected_id
		last_confirm.confirmed.connect(func() -> void: sell_now(id, n))
		add_child(last_confirm)
		return false
	return sell_now(selected_id, n) > 0


## Vend tout de suite `n` unités de l'entrée `id` (filtre courant). Renvoie l'or gagné.
func sell_now(id: StringName, n: int) -> int:
	var e := _entry(id)
	if e.is_empty() or n <= 0:
		return 0
	var gained := 0
	var w: WeaponData = e.get("weapon")
	if w != null:
		for _k in n:
			var uid := Profile.spare_weapon_uid(w.id)
			if uid < 0:
				break
			gained += Profile.sell_weapon(uid)
	else:
		gained = Profile.sell_item(id, n)
	if gained <= 0:
		MenuKit.sfx(&"error")
		return 0
	MenuKit.sfx(&"coin_pickup")
	MenuKit.vibrate(25)
	_fly_gain(gained)
	refresh()
	return gained


## « +N or » qui monte depuis le bouton de vente vers le compteur.
func _fly_gain(g: int) -> void:
	if not is_inside_tree():
		return
	var l := MenuKit.label("+%s or" % Economy.fmt(g), 30, GoldCounter.GOLD_COIN, MenuKit.nunito(1000), 5)
	l.top_level = true
	add_child(l)
	var from := sell_all_button.get_global_rect().get_center() if sell_all_button.is_inside_tree() else size * 0.5
	l.global_position = from - Vector2(60, 30)
	var to := gold_counter.get_global_rect().get_center() - Vector2(40, 10)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position", to, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25).set_delay(0.55)
	tw.chain().tween_callback(l.queue_free)


func go_back() -> void:
	MenuKit.sfx(&"back")
	if back_scene != "":
		MenuKit.go_to(self, back_scene)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()
