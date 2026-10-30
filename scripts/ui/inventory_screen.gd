class_name InventoryScreen
extends Control
## Écran d'inventaire de raid (bouton sac / action « inventory » : I, Tab), direction D.
## Plein écran dans la zone sûre, trois colonnes lisibles sur téléphone :
##   - Équipement : les 3 armes tenues (arme en main signalée, munitions), l'équipement
##     (charges) et les emplacements rapides (soins, équipements : utilisables depuis le HUD) ;
##   - Sac : grille (cases de rareté, pastilles d'affixes), cases occupées, poids / capacité ;
##   - Objet sélectionné : nom, rareté, type, affixes (AffixBadges), description, fiche, et
##     actions Utiliser / Équiper / Rapide / Jeter (ou Prendre en main, Retirer du rapide).
## Deux façons de ranger, au doigt comme à la souris :
##   - glisser une case du sac vers une arme, l'équipement, un emplacement rapide ou une autre
##     case (déplacement / échange) ; glisser un emplacement rapide vers le sac le libère ;
##   - toucher un objet puis un bouton d'action.
## Le jeu est en pause (ou ralenti, [loot] inventory_time_scale) tant qu'il est ouvert.
## Redessin uniquement sur Inventory.changed, changement d'armes du joueur ou sélection.

signal opened_changed(is_open: bool)

## Sélection hors du sac : arme tenue, équipement, emplacement rapide.
const SEL_BAG := 0
const SEL_HELD := 1
const SEL_GADGET := 2
const SEL_QUICK := 3

const LEFT_W := 292.0
const DETAIL_W := 320.0
const GAP := 14
const SLOT_GAP := 8
const SLOT_MIN := 62.0
const SLOT_MAX := 108.0

var inventory: Inventory = null
## Case du sac sélectionnée (-1 : aucune ou sélection hors du sac).
var selected: int = -1
var sel_kind: int = SEL_BAG
var sel_index: int = -1
var slot_size: float = 88.0

var _slots: Array[InventorySlot] = []
var _held_rows: Array[EquipRow] = []
var _gadget_row: EquipRow = null
var _quick_tiles: Array[InventorySlot] = []
var _quick_box: HBoxContainer = null
var _grid: GridContainer = null
var _weight_bar: ProgressBar = null
var _weight_label: Label = null
var _value_label: Label = null
var _slots_label: Label = null
var _detail_tile: Control = null
var _detail_name: Label = null
var _detail_meta: Label = null
var _detail_rarity: PanelContainer = null
var _detail_rarity_label: Label = null
var _detail_affixes: VBoxContainer = null
var _detail_desc: Label = null
var _facts_grid: GridContainer = null
var _detail_empty: Label = null
var _detail_box: VBoxContainer = null
var _message: Label = null
var _use_btn: Button = null
var _drop_btn: Button = null
var _equip_btn: Button = null
var _quick_btn: Button = null
var _dim: ColorRect = null
var _detail_style: CutBox = null
var _panel: PanelContainer = null
var _bound_player: Node = null
var _saved_time_scale: float = 1.0
var _paused_by_me: bool = false
var _tween: Tween = null


func _ready() -> void:
	name = "InventoryScreen"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	bind(GameState.raid_inventory)
	get_viewport().size_changed.connect(_on_resized)
	_on_resized()


func bind(inv: Inventory) -> void:
	if inventory != null and inventory.changed.is_connected(_refresh):
		inventory.changed.disconnect(_refresh)
	inventory = inv
	if inventory != null:
		inventory.changed.connect(_refresh)
	_rebuild_slots()
	_refresh()


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	if inventory != GameState.raid_inventory:
		bind(GameState.raid_inventory)
	_bind_player()
	visible = true
	_on_resized()
	if sel_kind == SEL_BAG and (selected < 0 or inventory == null or inventory.get_slot(selected).is_empty()):
		_select(SEL_BAG, _first_filled())
	_refresh()
	_apply_pause(true)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.modulate.a = 0.0
	_dim.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, 0.12)
	_tween.tween_property(_dim, "modulate:a", 1.0, 0.12)
	_play(&"panel_open")
	EventBus.inventory_toggled.emit(true)
	opened_changed.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	_apply_pause(false)
	_play(&"panel_close")
	EventBus.inventory_toggled.emit(false)
	opened_changed.emit(false)


func _apply_pause(on: bool) -> void:
	if not is_inside_tree():
		return
	var ts := LootDB.getf("inventory_time_scale", 0.0)
	if on:
		if ts <= 0.0:
			_paused_by_me = not get_tree().paused
			get_tree().paused = true
		else:
			_saved_time_scale = Engine.time_scale
			Engine.time_scale = ts
	else:
		if _paused_by_me:
			get_tree().paused = false
			_paused_by_me = false
		elif ts > 0.0:
			Engine.time_scale = _saved_time_scale


func _exit_tree() -> void:
	if visible:
		_apply_pause(false)


func _bind_player() -> void:
	var p: Node = GameState.player
	if p == _bound_player:
		return
	if is_instance_valid(_bound_player) and _bound_player.has_signal(&"weapons_changed"):
		if _bound_player.is_connected(&"weapons_changed", _refresh):
			_bound_player.disconnect(&"weapons_changed", _refresh)
		if _bound_player.has_signal(&"gadget_changed") and _bound_player.is_connected(&"gadget_changed", _refresh_gadget_signal):
			_bound_player.disconnect(&"gadget_changed", _refresh_gadget_signal)
	_bound_player = p
	if is_instance_valid(p):
		if p.has_signal(&"weapons_changed"):
			p.connect(&"weapons_changed", _refresh)
		if p.has_signal(&"gadget_changed"):
			p.connect(&"gadget_changed", _refresh_gadget_signal)


func _refresh_gadget_signal(_a: Variant = null) -> void:
	_refresh()


# --- Construction ------------------------------------------------------------------

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(InventoryStyle.DIM, 0.78)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	var pst := CutBox.make(Color(MenuKit.NIGHT, 0.94), 18.0, Color(1, 1, 1, 0.14), 1.0, 16.0, 12.0)
	_panel.add_theme_stylebox_override("panel", pst)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)

	# --- En-tête : titre, poids, valeur, trier, fermer ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	var band := Control.new()
	band.name = "TitleBand"
	band.custom_minimum_size = Vector2(250, 50)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bag_tex := LootVisuals.load_icon("res://assets/third_party/icons/item_backpack.svg")
	band.draw.connect(func() -> void:
		var h := band.size.y
		var w := band.size.x
		band.draw_colored_polygon(PackedVector2Array([Vector2(-16, 0), Vector2(w, 0), Vector2(w - 22, h), Vector2(-16, h)]), Color(MenuKit.VIOLET, 0.88))
		band.draw_colored_polygon(PackedVector2Array([Vector2(w + 6, 0), Vector2(w + 16, 0), Vector2(w - 6, h), Vector2(w - 16, h)]), Color(MenuKit.GOLD, 0.7))
		if bag_tex != null:
			band.draw_texture_rect(bag_tex, Rect2(Vector2(2, 7), Vector2(36, 36)), false, Color.WHITE)
		band.draw_string(MenuKit.display(), Vector2(48, h - 11), "INVENTAIRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.WHITE))
	header.add_child(band)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var wbox := VBoxContainer.new()
	wbox.add_theme_constant_override("separation", 3)
	wbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(wbox)
	_weight_label = InventoryStyle.label("", 14, InventoryStyle.TEXT_SECONDARY, 700)
	wbox.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(200, 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.GOLD
	_weight_bar.add_theme_stylebox_override("background", bg)
	_weight_bar.add_theme_stylebox_override("fill", fill)
	wbox.add_child(_weight_bar)
	_value_label = InventoryStyle.label("", 20, MenuKit.GOLD, 800)
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_value_label.custom_minimum_size = Vector2(96, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_value_label)
	var sort_btn := InventoryStyle.button("Trier", InventoryStyle.NIGHT_BLUE_LIGHT, 17, Vector2(92, 48))
	sort_btn.pressed.connect(func() -> void:
		if inventory != null:
			inventory.sort()
			_select(SEL_BAG, _first_filled())
			_play(&"click_soft"))
	header.add_child(sort_btn)
	var close_btn := InventoryStyle.button("✕", InventoryStyle.NIGHT_BLUE_LIGHT, 22, Vector2(56, 48))
	close_btn.name = "CloseButton"
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# --- Corps : équipement | sac | détail ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", GAP)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.name = "Equipment"
	left.custom_minimum_size = Vector2(LEFT_W, 0)
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	left.add_child(_section("Armes tenues"))
	for i in WeaponHud.SLOT_COUNT:
		var row := EquipRow.new()
		row.index = i
		row.custom_minimum_size = Vector2(LEFT_W, 58)
		row.clicked.connect(func(idx: int) -> void: _select(SEL_HELD, idx))
		row.accepts = _accepts_weapon
		row.dropped.connect(_on_drop_held)
		left.add_child(row)
		_held_rows.append(row)
	var gsec := _section("Équipement")
	left.add_child(gsec)
	_gadget_row = EquipRow.new()
	_gadget_row.gadget = true
	_gadget_row.custom_minimum_size = Vector2(LEFT_W, 52)
	_gadget_row.clicked.connect(func(_i: int) -> void: _select(SEL_GADGET, 0))
	_gadget_row.accepts = _accepts_gadget
	_gadget_row.dropped.connect(_on_drop_gadget)
	left.add_child(_gadget_row)
	left.add_child(_section("Emplacements rapides"))
	_quick_box = HBoxContainer.new()
	_quick_box.add_theme_constant_override("separation", 10)
	left.add_child(_quick_box)
	var qhint := InventoryStyle.label("Utilisables d'un toucher en raid (touches 4, 5).", 13, InventoryStyle.TEXT_SECONDARY, 500)
	qhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	qhint.custom_minimum_size = Vector2(LEFT_W, 0)
	left.add_child(qhint)

	var mid := VBoxContainer.new()
	mid.name = "Bag"
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	body.add_child(mid)
	var mh := HBoxContainer.new()
	mid.add_child(mh)
	mh.add_child(_section("Sac"))
	var msp := Control.new()
	msp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(msp)
	_slots_label = InventoryStyle.label("", 14, InventoryStyle.TEXT_SECONDARY, 600)
	mh.add_child(_slots_label)
	var gc := HBoxContainer.new()
	gc.alignment = BoxContainer.ALIGNMENT_CENTER
	gc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(gc)
	var gsp := Control.new()
	gsp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	gc.add_child(_grid)
	var help := InventoryStyle.label("Glisse un objet vers une arme, l'équipement ou un emplacement rapide. Toucher = détails.", 13, InventoryStyle.TEXT_SECONDARY, 500)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.custom_minimum_size = Vector2(200, 0)
	mid.add_child(gsp)
	mid.add_child(help)

	var detail := PanelContainer.new()
	detail.name = "Detail"
	_detail_style = CutBox.make(Color(1, 1, 1, 0.04), 12.0, Color(0, 0, 0, 0), 1.0, 14.0, 12.0)
	_detail_style.corners = CutBox.CUT_TOP_RIGHT | CutBox.CUT_BOTTOM_LEFT
	detail.add_theme_stylebox_override("panel", _detail_style)
	detail.custom_minimum_size = Vector2(DETAIL_W, 0)
	body.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	detail.add_child(dv)
	_detail_empty = InventoryStyle.label("Touchez un objet pour voir son détail.", 16, InventoryStyle.TEXT_SECONDARY, 600)
	_detail_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_empty.custom_minimum_size = Vector2(DETAIL_W - 30, 0)
	_detail_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(_detail_empty)

	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 6)
	_detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(_detail_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	_detail_box.add_child(top)
	_detail_tile = Control.new()
	_detail_tile.custom_minimum_size = Vector2(84, 84)
	_detail_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_tile.draw.connect(_draw_detail_tile)
	top.add_child(_detail_tile)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 3)
	top.add_child(names)
	_detail_name = InventoryStyle.label("", 21, Color.WHITE, 800)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name.custom_minimum_size = Vector2(190, 0)
	names.add_child(_detail_name)
	_detail_meta = InventoryStyle.label("", 14, InventoryStyle.TEXT_SECONDARY, 700)
	names.add_child(_detail_meta)
	_detail_rarity = PanelContainer.new()
	_detail_rarity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_detail_rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(_detail_rarity)
	_detail_rarity_label = InventoryStyle.label("", 13, InventoryStyle.NIGHT_BLUE_DEEP, 800)
	_detail_rarity.add_child(_detail_rarity_label)
	# Partie défilante (affixes, description, fiche) : les actions restent toujours visibles.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_box.add_child(scroll)
	MenuKit.make_touch_scroll(scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 8)
	scroll.add_child(sv)
	_detail_affixes = VBoxContainer.new()
	sv.add_child(_detail_affixes)
	_detail_desc = InventoryStyle.label("", 15, InventoryStyle.TEXT, 500)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(DETAIL_W - 44, 0)
	sv.add_child(_detail_desc)
	var facts := PanelContainer.new()
	facts.add_theme_stylebox_override("panel", CutBox.make(Color(1, 1, 1, 0.05), 8.0, Color(0, 0, 0, 0), 0.0, 12.0, 8.0))
	sv.add_child(facts)
	_facts_grid = GridContainer.new()
	_facts_grid.columns = 2
	_facts_grid.add_theme_constant_override("h_separation", 16)
	_facts_grid.add_theme_constant_override("v_separation", 3)
	facts.add_child(_facts_grid)

	_message = InventoryStyle.label("", 14, InventoryStyle.DANGER.lightened(0.3), 700)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(DETAIL_W - 30, 0)
	_message.visible = false
	dv.add_child(_message)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	dv.add_child(actions)
	_use_btn = _action_button("Utiliser", MenuKit.VIOLET, _use_selected)
	actions.add_child(_use_btn)
	_equip_btn = _action_button("Équiper", MenuKit.VIOLET, _on_equip_pressed)
	actions.add_child(_equip_btn)
	_quick_btn = _action_button("Rapide", InventoryStyle.NIGHT_BLUE_LIGHT, _on_quick_pressed)
	actions.add_child(_quick_btn)
	_drop_btn = _action_button("Jeter", InventoryStyle.DANGER, _drop_selected)
	actions.add_child(_drop_btn)


func _section(text: String) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 7)
	var bar := ColorRect.new()
	bar.color = MenuKit.VIOLET
	bar.custom_minimum_size = Vector2(4, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	row.add_child(InventoryStyle.label(text.to_upper(), 13, Color(1, 1, 1, 0.7), 700))
	return row


func _action_button(text: String, color: Color, cb: Callable) -> Button:
	var b := InventoryStyle.button(text, color, 17, Vector2(0, 50))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: cb.call())
	return b


## Panneau dans la zone sûre ; taille des cases du sac calculée pour tenir en hauteur et largeur.
func _on_resized() -> void:
	if not is_inside_tree():
		return
	apply_layout(get_viewport_rect().size, HudSafeArea.margins(self))


func apply_layout(vp: Vector2, safe: Vector4) -> void:
	var m := Vector4(maxf(safe.x, 12.0), maxf(safe.y, 10.0), maxf(safe.z, 12.0), maxf(safe.w, 10.0))
	_panel.position = Vector2(m.x, m.y)
	_panel.size = vp - Vector2(m.x + m.z, m.y + m.w)
	slot_size = compute_slot_size(_panel.size, inventory.columns if inventory != null else 6, inventory.rows if inventory != null else 4)
	for s: InventorySlot in _slots:
		s.custom_minimum_size = Vector2(slot_size, slot_size)
	var qs := clampf(slot_size * 0.9, 64.0, 84.0)
	for q: InventorySlot in _quick_tiles:
		q.custom_minimum_size = Vector2(qs, qs)


## Logique pure : côté d'une case du sac pour un panneau `panel_size` (en-tête, marges,
## colonnes équipement et détail déduites), borné à [SLOT_MIN, SLOT_MAX].
static func compute_slot_size(panel_size: Vector2, cols: int, rows: int) -> float:
	var inner := panel_size - Vector2(32.0, 24.0)
	var avail_w := inner.x - LEFT_W - DETAIL_W - GAP * 2.0
	var avail_h := inner.y - 58.0 - 10.0 - 24.0 - 44.0
	var by_w := (avail_w - SLOT_GAP * (cols - 1)) / float(maxi(cols, 1))
	var by_h := (avail_h - SLOT_GAP * (rows - 1)) / float(maxi(rows, 1))
	return clampf(floorf(minf(by_w, by_h)), SLOT_MIN, SLOT_MAX)


func _rebuild_slots() -> void:
	for s: InventorySlot in _slots:
		s.queue_free()
	_slots.clear()
	for q: InventorySlot in _quick_tiles:
		q.queue_free()
	_quick_tiles.clear()
	if inventory == null or _grid == null:
		return
	_grid.columns = inventory.columns
	for i in inventory.capacity():
		var s := InventorySlot.new(i, slot_size)
		s.draggable = true
		s.accepts = _accepts_bag
		s.clicked.connect(func(idx: int) -> void: _select(SEL_BAG, idx))
		s.dropped.connect(_on_drop_bag)
		_grid.add_child(s)
		_slots.append(s)
	for i in inventory.quick_count():
		var q := QuickTile.new(i, 80.0)
		q.accepts = _accepts_quick
		q.clicked.connect(func(idx: int) -> void: _select(SEL_QUICK, idx))
		q.dropped.connect(_on_drop_quick)
		_quick_box.add_child(q)
		_quick_tiles.append(q)
	if is_inside_tree():
		_on_resized()


func _select(kind: int, i: int) -> void:
	sel_kind = kind
	sel_index = i
	selected = i if kind == SEL_BAG else -1
	_message.visible = false
	if i >= 0:
		_play(&"click_soft")
	_refresh()


func _first_filled() -> int:
	if inventory == null:
		return -1
	for i in inventory.capacity():
		if not inventory.get_slot(i).is_empty():
			return i
	return -1


# --- Mise à jour (sur signal uniquement) ----------------------------------------------

func _refresh() -> void:
	if inventory == null:
		return
	if _slots.size() != inventory.capacity() or _quick_tiles.size() != inventory.quick_count():
		_rebuild_slots()
	if sel_kind == SEL_BAG and selected >= 0 and inventory.get_slot(selected).is_empty():
		selected = _first_filled()
		sel_index = selected
	for i in _slots.size():
		var s := inventory.get_slot(i)
		_slots[i].set_content(s.get("item") as ItemData, int(s.get("count", 0)), sel_kind == SEL_BAG and i == selected)
	for i in _quick_tiles.size():
		_quick_tiles[i].set_content(inventory.quick_item(i), inventory.quick_amount(i), sel_kind == SEL_QUICK and i == sel_index)
	_refresh_equipment()
	var w := inventory.total_weight()
	_weight_bar.max_value = inventory.max_weight
	_weight_bar.value = w
	var heavy := w >= inventory.max_weight * 0.85
	(_weight_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = InventoryStyle.DANGER if heavy else MenuKit.GOLD
	_weight_label.text = "Poids  %.1f / %.0f kg" % [w, inventory.max_weight]
	_value_label.text = "%d $" % inventory.total_value()
	_slots_label.text = "%d / %d cases" % [inventory.used_slots(), inventory.capacity()]
	_refresh_detail()


func _refresh_equipment() -> void:
	var p: Node = GameState.player
	var weapons := WeaponHud.read_weapons(p)
	var cur := -1
	if is_instance_valid(p) and p.get("current_slot") is int:
		cur = int(p.get("current_slot"))
	var ammo := int(p.call(&"get_ammo")) if is_instance_valid(p) and p.has_method(&"get_ammo") else -1
	for i in _held_rows.size():
		var w: WeaponData = weapons[i] if i < weapons.size() else null
		_held_rows[i].set_state(w, i == cur, ammo if i == cur else -2, sel_kind == SEL_HELD and sel_index == i)
	var g := _player_gadget()
	var charges := int(p.call(&"get_gadget_charges")) if g != null and is_instance_valid(p) and p.has_method(&"get_gadget_charges") else (g.charges if g != null else 0)
	_gadget_row.set_state(g, false, charges, sel_kind == SEL_GADGET)


static func _player_gadget() -> WeaponData:
	var p: Node = GameState.player
	if is_instance_valid(p) and p.has_method(&"get_gadget"):
		return p.call(&"get_gadget") as WeaponData
	return null


## Arme ou équipement sélectionné hors du sac (null sinon).
func _selected_weapon() -> WeaponData:
	if sel_kind == SEL_HELD:
		var ws := WeaponHud.read_weapons(GameState.player)
		return ws[sel_index] if sel_index >= 0 and sel_index < ws.size() else null
	if sel_kind == SEL_GADGET:
		return _player_gadget()
	return null


func _refresh_detail() -> void:
	var it: ItemData = null
	var n := 1
	var wd: WeaponData = null
	if sel_kind == SEL_BAG:
		var s := inventory.get_slot(selected)
		if not s.is_empty():
			it = s["item"]
			n = int(s["count"])
	elif sel_kind == SEL_QUICK:
		it = inventory.quick_item(sel_index)
		n = inventory.quick_amount(sel_index)
	else:
		wd = _selected_weapon()
		if wd != null:
			it = LootDB.weapon_item(wd)
	var has := it != null
	_detail_box.visible = has
	_detail_empty.visible = not has
	for b: Button in [_use_btn, _equip_btn, _quick_btn, _drop_btn]:
		b.visible = false
	if not has:
		_detail_style.bg_color = Color(1, 1, 1, 0.04)
		_detail_style.border_color = Color(0, 0, 0, 0)
		if sel_kind == SEL_QUICK:
			_detail_empty.text = "Emplacement rapide libre.\nGlissez-y un soin ou un équipement depuis le sac, ou touchez l'objet puis « Rapide »."
		elif sel_kind == SEL_HELD:
			_detail_empty.text = "Emplacement d'arme libre.\nGlissez-y une arme du sac."
		elif inventory.is_empty():
			_detail_empty.text = "Votre sac est vide.\nFouillez caisses, coffres et cadavres pour le remplir."
		else:
			_detail_empty.text = "Touchez un objet pour voir son détail."
		_detail_tile.queue_redraw()
		return
	if wd == null and it.is_weapon():
		wd = it.get_weapon()
	var rc := LootDB.rarity_color(it.rarity)
	_detail_style.bg_color = Color(rc, 0.08)
	_detail_style.border_color = Color(rc, 0.55)
	_detail_name.text = it.display_name
	_detail_name.label_settings.font_color = rc.lightened(0.2)
	_detail_meta.text = (("Équipement" if wd.is_gadget() else "Arme · %s" % wd.get_category_name())) if wd != null else LootDB.type_name(it.type)
	_detail_rarity_label.text = LootDB.rarity_name(it.rarity).to_upper()
	_detail_rarity.add_theme_stylebox_override("panel", CutBox.make(rc, 5.0, Color(0, 0, 0, 0), 0.0, 8.0, 1.0))
	for ch: Node in _detail_affixes.get_children():
		ch.queue_free()
	var ax: Array = wd.rolled_affixes if wd != null else []
	if not ax.is_empty():
		_detail_affixes.add_child(AffixBadges.details(ax, 14))
	_detail_affixes.visible = not ax.is_empty()
	_detail_desc.text = it.description
	var price := Economy.item_sell_price(it)
	if wd != null:
		_set_facts(weapon_facts(wd) + [["Valeur", "≈ %d or" % price], ["Poids", "%s kg" % String.num(it.weight, 2)]])
	else:
		var uses := RecipeBook.usage_text(it.id)
		_set_facts([
			["Valeur", "≈ %d or" % price + ("   ×%d = %d or" % [n, price * n] if n > 1 else "")],
			["Poids", "%s kg" % String.num(it.weight * n, 2)],
			["Pile", "%d / %d" % [n, it.stack_max]],
		] + ([["Soin", "+%d PV" % int(it.heal_amount)]] if it.is_usable() else [])
		+ ([["Artisanat", uses]] if not uses.is_empty() else []))
	match sel_kind:
		SEL_BAG:
			_use_btn.visible = it.is_usable()
			_equip_btn.visible = wd != null
			_equip_btn.text = "Équiper"
			_quick_btn.visible = Inventory.can_quick(it)
			_quick_btn.text = "Retirer rapide" if inventory.quick_index_of(it) >= 0 else "Rapide"
			_drop_btn.visible = true
			_drop_btn.text = "Jeter" if n <= 1 else "Jeter 1"
		SEL_QUICK:
			_use_btn.visible = it.is_usable() and n > 0
			_equip_btn.visible = wd != null and n > 0
			_equip_btn.text = "Équiper"
			_quick_btn.visible = true
			_quick_btn.text = "Retirer rapide"
		SEL_HELD:
			var cur: Variant = GameState.player.get("current_slot") if is_instance_valid(GameState.player) else null
			_equip_btn.visible = not (cur is int and int(cur) == sel_index)
			_equip_btn.text = "Prendre en main"
	_detail_tile.queue_redraw()


func _set_facts(rows: Array) -> void:
	for ch: Node in _facts_grid.get_children():
		_facts_grid.remove_child(ch)
		ch.queue_free()
	for r: Array in rows:
		_facts_grid.add_child(InventoryStyle.label(String(r[0]), 14, InventoryStyle.TEXT_SECONDARY, 700))
		var v := InventoryStyle.label(String(r[1]), 14, MenuKit.GOLD if r[0] == "Valeur" else InventoryStyle.TEXT, 800)
		if String(r[1]).length() > 22:
			v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.custom_minimum_size = Vector2(170, 0)
		_facts_grid.add_child(v)


func _draw_detail_tile() -> void:
	var it: ItemData = null
	var n := 1
	if sel_kind == SEL_BAG:
		var s := inventory.get_slot(selected) if inventory != null else {}
		if not s.is_empty():
			it = s["item"]
			n = int(s["count"])
	elif sel_kind == SEL_QUICK:
		it = inventory.quick_item(sel_index)
		n = inventory.quick_amount(sel_index)
	else:
		var w := _selected_weapon()
		it = LootDB.weapon_item(w) if w != null else null
	if it == null:
		return
	InventoryStyle.draw_item_tile(_detail_tile, Rect2(Vector2.ZERO, _detail_tile.size), it, n, false, LootVisuals.text_font(800))


## Lignes de fiche des affixes tirés d'un exemplaire : [nom, effet court, couleur de l'affixe].
static func affix_facts(w: WeaponData) -> Array:
	var rows: Array = []
	if w == null:
		return rows
	for a: AffixData in w.get_affix_list():
		rows.append([a.display_name, a.effect_text(), a.color])
	return rows


## Lignes de fiche d'une arme : dégâts, cadence, chargeur, DPS (+ explosion, perforation).
static func weapon_facts(w: WeaponData) -> Array:
	if w.is_gadget():
		return gadget_facts(w)
	var dmg := String.num(w.damage, 0) + ("  ×%d" % w.projectile_count if w.projectile_count > 1 else "")
	var rows: Array = [
		["Dégâts", dmg],
		["Cadence", "%s tirs/s%s" % [String.num(w.fire_rate, 1), "  (auto)" if w.automatic else ""]],
		["Chargeur", ("%d · %s s" % [w.magazine_size, String.num(w.reload_time, 1)]) if w.magazine_size > 0 else "illimité"],
		["DPS", String.num(w.get_dps(), 0)],
	]
	if w.is_explosive():
		rows.append(["Explosion", "%d (rayon %d)" % [int(w.explosion_damage), int(w.explosion_radius)]])
	if w.pierce > 0:
		rows.append(["Perforation", "+%d cible%s" % [w.pierce, "s" if w.pierce > 1 else ""]])
	return rows


## Fiche d'un équipement : charges, effet, portée, délai, durée.
static func gadget_facts(w: WeaponData) -> Array:
	var rows: Array = [["Charges", "×%d" % w.charges]]
	if w.is_explosive():
		rows.append(["Explosion", "%d (rayon %d)" % [int(w.explosion_damage), int(w.explosion_radius)]])
	elif w.effect_radius > 0.0:
		rows.append(["Rayon", "%d" % int(w.effect_radius)])
	if w.damage > 0.0 and w.fire_rate > 0.0 and not w.is_explosive():
		rows.append(["Tir", "%d × %s/s" % [int(w.damage), String.num(w.fire_rate, 1)]])
	if w.throw_range > 0.0:
		rows.append(["Portée", "%d" % int(w.throw_range)])
	if w.fuse_time > 0.0:
		rows.append(["Délai", "%s s" % String.num(w.fuse_time, 1)])
	if w.effect_duration > 0.0 and w.gadget_kind != WeaponData.GADGET_MINE:
		rows.append(["Durée", "%s s" % String.num(w.effect_duration, 0)])
	return rows


# --- Actions ------------------------------------------------------------------------

func get_selected_item() -> ItemData:
	if inventory == null:
		return null
	if sel_kind == SEL_QUICK:
		return inventory.quick_item(sel_index)
	return inventory.get_slot(selected).get("item") as ItemData if sel_kind == SEL_BAG else null


## Case du sac visée par les actions (sélection du sac, ou exemplaire d'un emplacement rapide).
func _action_slot() -> int:
	if inventory == null:
		return -1
	if sel_kind == SEL_BAG:
		return selected
	if sel_kind == SEL_QUICK and sel_index >= 0 and sel_index < inventory.quick_count():
		return inventory.find_slot(inventory.quick[sel_index])
	return -1


func _on_equip_pressed() -> void:
	if sel_kind == SEL_HELD:
		var p: Node = GameState.player
		if is_instance_valid(p) and p.has_method(&"switch_to"):
			p.call(&"switch_to", sel_index)
			_play(&"click_soft")
			_refresh()
		return
	_equip_selected()


## Équipe l'arme sélectionnée dans l'emplacement courant du joueur (équipement → emplacement
## d'équipement) : l'objet quitte le sac, l'arme remplacée y revient. Sac plein : message, rien.
## Renvoie true si l'échange a eu lieu.
func _equip_selected(weapon_slot: int = -1) -> bool:
	var at := _action_slot()
	if at < 0:
		return false
	var msg := ItemUse.equip_slot(inventory, at, GameState.player, weapon_slot)
	if not msg.is_empty():
		_flash_message(msg)
		return false
	_play(&"click")
	_refresh()
	return true


func _use_selected() -> void:
	var at := _action_slot()
	if at < 0:
		return
	var msg := ItemUse.use_slot(inventory, at, GameState.player)
	if not msg.is_empty():
		_flash_message(msg)
		return
	_play(&"heal")


func _drop_selected() -> void:
	if inventory == null or sel_kind != SEL_BAG or inventory.get_slot(selected).is_empty():
		return
	inventory.remove_at(selected, 1)
	_play(&"click")


## « Rapide » : premier emplacement libre (sinon le premier) ; « Retirer rapide » : le libère.
func _on_quick_pressed() -> void:
	if inventory == null:
		return
	if sel_kind == SEL_QUICK:
		inventory.clear_quick(sel_index)
		_play(&"click_soft")
		return
	var it := get_selected_item()
	if it == null:
		return
	var q := inventory.quick_index_of(it)
	if q >= 0:
		inventory.clear_quick(q)
	else:
		var free := inventory.quick.find("")
		inventory.assign_quick(free if free >= 0 else 0, it)
	_play(&"click_soft")


func _flash_message(text: String) -> void:
	_message.text = text
	_message.visible = true
	_play(&"error")
	get_tree().create_timer(2.2, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(_message) and _message.text == text:
			_message.visible = false)


# --- Glisser-déposer ----------------------------------------------------------------

func _drag_item(data: Dictionary) -> ItemData:
	if inventory == null:
		return null
	match String(data.get("from", "")):
		"bag":
			return inventory.get_slot(int(data.get("index", -1))).get("item") as ItemData
		"quick":
			return inventory.quick_item(int(data.get("index", -1)))
	return null


func _accepts_bag(data: Dictionary) -> bool:
	return String(data.get("from", "")) in ["bag", "quick"]


func _accepts_quick(data: Dictionary) -> bool:
	return Inventory.can_quick(_drag_item(data))


func _accepts_weapon(data: Dictionary) -> bool:
	var it := _drag_item(data)
	return String(data.get("from", "")) == "bag" and it != null and it.is_weapon() and not WeaponCatalog.get_weapon(it.weapon_id).is_gadget()


func _accepts_gadget(data: Dictionary) -> bool:
	var it := _drag_item(data)
	return String(data.get("from", "")) == "bag" and it != null and it.is_weapon() and WeaponCatalog.get_weapon(it.weapon_id).is_gadget()


func _on_drop_bag(to: int, data: Dictionary) -> void:
	var from := int(data.get("index", -1))
	if String(data.get("from", "")) == "quick":
		inventory.clear_quick(from)
	elif inventory.move_slot(from, to):
		_select(SEL_BAG, to)
	_play(&"click_soft")


func _on_drop_quick(to: int, data: Dictionary) -> void:
	var it := _drag_item(data)
	if String(data.get("from", "")) == "quick":
		var other := inventory.quick[to]
		inventory.quick[to] = inventory.quick[int(data.get("index", -1))]
		inventory.quick[int(data.get("index", -1))] = other
		inventory.changed.emit()
	elif inventory.assign_quick(to, it):
		_select(SEL_QUICK, to)
	_play(&"click_soft")


func _on_drop_held(slot: int, data: Dictionary) -> void:
	_select(SEL_BAG, int(data.get("index", -1)))
	if _equip_selected(slot):
		_select(SEL_HELD, slot)


func _on_drop_gadget(_i: int, data: Dictionary) -> void:
	_select(SEL_BAG, int(data.get("index", -1)))
	if _equip_selected():
		_select(SEL_GADGET, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory") and not (event is InputEventKey and (event as InputEventKey).echo):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _play(sfx: StringName) -> void:
	ItemUse.play(self, sfx)


# =====================================================================================

## Ligne d'équipement : arme tenue (emplacement 1 à 3) ou équipement. Dépôt d'une arme /
## d'un équipement depuis le sac.
class EquipRow extends Control:
	signal clicked(index: int)
	signal dropped(index: int, data: Dictionary)

	var index: int = 0
	var gadget: bool = false
	var weapon: WeaponData = null
	var in_hand: bool = false
	## Munitions (arme en main) ou charges (équipement) ; -2 = non affiché.
	var ammo: int = -2
	var selected: bool = false
	var accepts: Callable = Callable()
	var _hover: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE

	func set_state(w: WeaponData, hand: bool, p_ammo: int, sel: bool) -> void:
		weapon = w
		in_hand = hand
		ammo = p_ammo
		selected = sel
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(index)
			accept_event()

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		var ok: bool = data is Dictionary and accepts.is_valid() and bool(accepts.call(data))
		if ok != _hover:
			_hover = ok
			queue_redraw()
		return ok

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_hover = false
		queue_redraw()
		dropped.emit(index, data as Dictionary)

	func _notification(what: int) -> void:
		if (what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT) and _hover:
			_hover = false
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rc: Color = weapon.get_rarity_color() if weapon != null else Color(1, 1, 1, 0.2)
		var bg := CutBox.make(Color(MenuKit.VIOLET, 0.35) if in_hand else Color(1, 1, 1, 0.06 if weapon != null else 0.03), 10.0,
			MenuKit.GOLD if selected or _hover else Color(1, 1, 1, 0.0 if weapon != null else 0.18), 2.0 if selected or _hover else 1.0)
		if weapon != null:
			bg.accent_width = 4.0
			bg.accent_color = rc
		draw_style_box(bg, r)
		var f := LootVisuals.text_font(700)
		var tag := "É" if gadget else str(index + 1)
		draw_string(MenuKit.display(), Vector2(14, size.y * 0.5 + 9), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1, 1, 1, 0.5))
		if weapon == null:
			var t := "Vide : glissez un équipement" if gadget else "Vide : glissez une arme"
			draw_string(f, Vector2(44, size.y * 0.5 + 5), t, HORIZONTAL_ALIGNMENT_LEFT, size.x - 52, 14, Color(1, 1, 1, 0.45))
			return
		LootVisuals.draw_weapon(self, Rect2(Vector2(40, 7), Vector2(84, size.y - 14)), weapon)
		var x := 134.0
		draw_string(f, Vector2(x, size.y * 0.5 - 3), weapon.display_name, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8, 15, Color.WHITE)
		var sub := ""
		if gadget:
			sub = "×%d charges" % maxi(ammo, 0)
		elif in_hand:
			sub = "En main" + ("  ·  %d / %d" % [maxi(ammo, 0), weapon.magazine_size] if ammo >= 0 and weapon.magazine_size > 0 else "")
		else:
			sub = weapon.get_category_name()
		draw_string(f, Vector2(x, size.y * 0.5 + 15), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 8, 13,
			MenuKit.GOLD if in_hand else Color(1, 1, 1, 0.6))


## Emplacement rapide de l'écran d'inventaire : case du sac (même dessin), glissable vers une
## autre case rapide (échange) ou vers le sac (libère l'emplacement).
class QuickTile extends InventorySlot:
	func _get_drag_data(_at: Vector2) -> Variant:
		if item == null:
			return null
		set_drag_preview(InventorySlot.make_preview(item, count, size.x))
		return {"from": "quick", "index": index, "item": item}

	func _draw() -> void:
		if item == null:
			var bg := CutBox.make(Color(1, 1, 1, 0.03), 8.0, Color(1, 1, 1, 0.22), 1.0)
			draw_style_box(bg, Rect2(Vector2.ZERO, size))
			var f := LootVisuals.text_font(700)
			var t := "+"
			var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
			draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + 10), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 1, 1, 0.4))
		else:
			InventoryStyle.draw_item_tile(self, Rect2(Vector2.ZERO, size), item, maxi(count, 0), selected, LootVisuals.text_font(800))
			if count <= 0:
				draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
		var kf := LootVisuals.text_font(800)
		var key := str(4 + index)
		draw_string_outline(kf, Vector2(7, 17), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, MenuKit.NIGHT_DEEP)
		draw_string(kf, Vector2(7, 17), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
		if _drop_hover:
			draw_style_box(CutBox.make(Color(MenuKit.VIOLET, 0.25), 6.0, MenuKit.GOLD, 2.0), Rect2(Vector2.ZERO, size))
