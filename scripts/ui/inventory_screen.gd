class_name InventoryScreen
extends Control
## Écran d'inventaire de raid (bouton sac / touche I / Tab). Paysage 1280×720 :
## grille à gauche (cases 92 px), détail de l'objet sélectionné à droite
## (nom couleur de rareté, type, description, valeur, poids ; armes : catégorie, dégâts,
## cadence, chargeur, DPS), boutons « Utiliser » (consommables), « Équiper » (armes :
## échange avec l'arme de l'emplacement courant du joueur), « Jeter », « Trier », « Fermer ».
## Le jeu est mis en pause (ou ralenti, [loot] inventory_time_scale) tant qu'il est ouvert.
## Redessin uniquement sur Inventory.changed / sélection.

signal opened_changed(is_open: bool)

const SLOT_SIZE := 92.0
const SLOT_GAP := 10

var inventory: Inventory = null
var selected: int = -1

var _slots: Array[InventorySlot] = []
var _grid: GridContainer = null
var _weight_bar: ProgressBar = null
var _weight_label: Label = null
var _value_label: Label = null
var _slots_label: Label = null
var _detail_icon: TextureRect = null
var _detail_tile: Panel = null
var _detail_name: Label = null
var _detail_meta: Label = null
var _detail_rarity: PanelContainer = null
var _detail_rarity_label: Label = null
var _detail_desc: Label = null
var _facts_grid: GridContainer = null
var _detail_empty: Label = null
var _detail_box: VBoxContainer = null
var _use_btn: Button = null
var _drop_btn: Button = null
var _equip_btn: Button = null
var _dim: ColorRect = null
var _panel: PanelContainer = null
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
	visible = true
	if selected < 0 or inventory == null or inventory.get_slot(selected).is_empty():
		selected = _first_filled()
	_refresh()
	_apply_pause(true)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.scale = Vector2(0.94, 0.94)
	_panel.modulate.a = 0.0
	_dim.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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


# --- Construction ------------------------------------------------------------------

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = InventoryStyle.DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", InventoryStyle.panel(22, 22))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_panel.add_child(root)

	# --- En-tête : titre, poids, valeur, trier, fermer ---
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	var bag_icon := TextureRect.new()
	bag_icon.texture = LootVisuals.load_icon("res://assets/third_party/icons/item_backpack.svg")
	bag_icon.custom_minimum_size = Vector2(40, 40)
	bag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bag_icon.modulate = InventoryStyle.GOLD
	header.add_child(bag_icon)
	var title := InventoryStyle.title("Sacoche du raid", 32)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var wbox := VBoxContainer.new()
	wbox.add_theme_constant_override("separation", 2)
	wbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(wbox)
	_weight_label = InventoryStyle.label("", 15, InventoryStyle.TEXT_SECONDARY, 700)
	wbox.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(190, 12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = InventoryStyle.NIGHT_BLUE_DEEP
	bg.set_corner_radius_all(6)
	bg.border_color = Color(InventoryStyle.BORDER_LIGHT, 0.25)
	bg.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = InventoryStyle.GOLD
	fill.set_corner_radius_all(6)
	_weight_bar.add_theme_stylebox_override("background", bg)
	_weight_bar.add_theme_stylebox_override("fill", fill)
	wbox.add_child(_weight_bar)

	_value_label = InventoryStyle.label("", 22, InventoryStyle.GOLD, 800)
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_value_label.custom_minimum_size = Vector2(110, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_value_label)

	var sort_btn := InventoryStyle.button("Trier", InventoryStyle.NIGHT_BLUE_LIGHT, 18, Vector2(96, 50))
	sort_btn.pressed.connect(func() -> void:
		if inventory != null:
			inventory.sort()
			selected = _first_filled()
			_refresh()
			_play(&"click_soft"))
	header.add_child(sort_btn)
	var close_btn := InventoryStyle.button("✕", InventoryStyle.NIGHT_BLUE_LIGHT, 22, Vector2(56, 50))
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	# --- Corps : grille | détail ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)

	var grid_box := PanelContainer.new()
	grid_box.add_theme_stylebox_override("panel", InventoryStyle.inset(16, 14))
	body.add_child(grid_box)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 8)
	grid_box.add_child(gv)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", SLOT_GAP)
	_grid.add_theme_constant_override("v_separation", SLOT_GAP)
	gv.add_child(_grid)
	_slots_label = InventoryStyle.label("", 14, InventoryStyle.TEXT_SECONDARY, 600)
	gv.add_child(_slots_label)

	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", InventoryStyle.inset(16, 18))
	detail.custom_minimum_size = Vector2(340, 0)
	body.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	detail.add_child(dv)

	_detail_empty = InventoryStyle.label("Touchez un objet pour voir son détail.", 17, InventoryStyle.TEXT_SECONDARY, 600)
	_detail_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_empty.custom_minimum_size = Vector2(300, 0)
	dv.add_child(_detail_empty)

	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 8)
	_detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(_detail_box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_detail_box.add_child(top)
	_detail_tile = Panel.new()
	_detail_tile.custom_minimum_size = Vector2(96, 96)
	_detail_tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_tile.draw.connect(_draw_detail_tile)
	top.add_child(_detail_tile)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(names)
	_detail_name = InventoryStyle.label("", 23, Color.WHITE, 800)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name.custom_minimum_size = Vector2(190, 0)
	names.add_child(_detail_name)
	_detail_meta = InventoryStyle.label("", 15, InventoryStyle.TEXT_SECONDARY, 700)
	names.add_child(_detail_meta)
	_detail_rarity = PanelContainer.new()
	_detail_rarity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_detail_rarity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(_detail_rarity)
	_detail_rarity_label = InventoryStyle.label("", 14, InventoryStyle.NIGHT_BLUE_DEEP, 800)
	_detail_rarity.add_child(_detail_rarity_label)
	_detail_desc = InventoryStyle.label("", 17, InventoryStyle.TEXT, 500)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(300, 60)
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(_detail_desc)
	# Fiche : valeur / poids / pile, en lignes alignées sur fond légèrement éclairci.
	var facts := PanelContainer.new()
	var fst := StyleBoxFlat.new()
	fst.bg_color = InventoryStyle.NIGHT_BLUE_LIGHT
	fst.set_corner_radius_all(12)
	fst.set_content_margin_all(12)
	facts.add_theme_stylebox_override("panel", fst)
	_detail_box.add_child(facts)
	_facts_grid = GridContainer.new()
	_facts_grid.columns = 2
	_facts_grid.add_theme_constant_override("h_separation", 18)
	_facts_grid.add_theme_constant_override("v_separation", 4)
	facts.add_child(_facts_grid)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	dv.add_child(actions)
	_use_btn = InventoryStyle.button("Utiliser", Color(0.25, 0.55, 0.36), 19, Vector2(0, 56))
	_use_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_use_btn.pressed.connect(_use_selected)
	actions.add_child(_use_btn)
	_equip_btn = InventoryStyle.button("Équiper", InventoryStyle.GOLD, 19, Vector2(0, 56))
	_equip_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_btn.pressed.connect(_equip_selected)
	actions.add_child(_equip_btn)
	_drop_btn = InventoryStyle.button("Jeter", InventoryStyle.DANGER, 19, Vector2(0, 56))
	_drop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop_btn.pressed.connect(_drop_selected)
	actions.add_child(_drop_btn)


func _rebuild_slots() -> void:
	for s: InventorySlot in _slots:
		s.queue_free()
	_slots.clear()
	if inventory == null or _grid == null:
		return
	_grid.columns = inventory.columns
	for i in inventory.capacity():
		var s := InventorySlot.new(i, SLOT_SIZE)
		s.clicked.connect(_on_slot_clicked)
		_grid.add_child(s)
		_slots.append(s)


func _on_slot_clicked(i: int) -> void:
	if inventory == null or inventory.get_slot(i).is_empty():
		return
	selected = i
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
	if _slots.size() != inventory.capacity():
		_rebuild_slots()
	if selected >= 0 and inventory.get_slot(selected).is_empty():
		selected = _first_filled()
	for i in _slots.size():
		var s := inventory.get_slot(i)
		_slots[i].set_content(s.get("item") as ItemData, int(s.get("count", 0)), i == selected)
	var w := inventory.total_weight()
	_weight_bar.max_value = inventory.max_weight
	_weight_bar.value = w
	var heavy := w >= inventory.max_weight * 0.85
	(_weight_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = InventoryStyle.DANGER if heavy else InventoryStyle.GOLD
	_weight_label.text = "Poids  %.1f / %.0f kg" % [w, inventory.max_weight]
	_value_label.text = "%d $" % inventory.total_value()
	_slots_label.text = "%d / %d cases occupées" % [inventory.used_slots(), inventory.capacity()]
	_refresh_detail()


func _refresh_detail() -> void:
	var s := inventory.get_slot(selected) if inventory != null else {}
	var has := not s.is_empty()
	_detail_box.visible = has
	_detail_empty.visible = not has
	_use_btn.visible = has
	_drop_btn.visible = has
	_equip_btn.visible = false
	if not has:
		_detail_empty.text = "Votre sacoche est vide.\nFouillez caisses, coffres et cadavres pour la remplir." if inventory.is_empty() else "Touchez un objet pour voir son détail."
		return
	var it: ItemData = s["item"]
	var n := int(s["count"])
	_detail_name.text = it.display_name
	_detail_name.label_settings.font_color = LootDB.rarity_color(it.rarity).lightened(0.15)
	var rc := LootDB.rarity_color(it.rarity)
	var wd: WeaponData = it.get_weapon() if it.is_weapon() else null
	_detail_meta.text = (("Équipement" if wd.is_gadget() else "Arme · %s" % wd.get_category_name())) if wd != null else LootDB.type_name(it.type)
	_detail_rarity_label.text = LootDB.rarity_name(it.rarity).to_upper()
	var rst := StyleBoxFlat.new()
	rst.bg_color = rc
	rst.set_corner_radius_all(8)
	rst.content_margin_left = 8
	rst.content_margin_right = 8
	rst.content_margin_top = 1
	rst.content_margin_bottom = 2
	_detail_rarity.add_theme_stylebox_override("panel", rst)
	_detail_desc.text = it.description
	# Valeur = or estimé au marchand (Economy) ; matériaux : recettes de l'atelier qui les utilisent.
	var price := Economy.item_sell_price(it)
	if wd != null:
		_set_facts(affix_facts(wd) + weapon_facts(wd) + [["Valeur", "≈ %d or" % price], ["Poids", "%s kg" % String.num(it.weight, 2)]])
	else:
		var uses := RecipeBook.usage_text(it.id)
		_set_facts([
			["Valeur", "≈ %d or" % price + ("   ×%d = %d or" % [n, price * n] if n > 1 else "")],
			["Poids", "%s kg" % String.num(it.weight * n, 2)],
			["Pile", "%d / %d" % [n, it.stack_max]],
		] + ([["Soin", "+%d PV" % int(it.heal_amount)]] if it.is_usable() else [])
		+ ([["Artisanat", uses]] if not uses.is_empty() else []))
	_use_btn.visible = it.is_usable()
	_equip_btn.visible = wd != null
	_drop_btn.text = "Jeter" if n <= 1 else "Jeter 1"
	_detail_tile.queue_redraw()


func _set_facts(rows: Array) -> void:
	for ch: Node in _facts_grid.get_children():
		_facts_grid.remove_child(ch)
		ch.queue_free()
	for r: Array in rows:
		# 3e élément facultatif : couleur du libellé (affixes).
		var kc: Color = r[2] if r.size() >= 3 and r[2] is Color else InventoryStyle.TEXT_SECONDARY
		_facts_grid.add_child(InventoryStyle.label(String(r[0]), 16, kc, 800 if r.size() >= 3 else 700))
		var v := InventoryStyle.label(String(r[1]), 16, InventoryStyle.GOLD if r[0] == "Valeur" else InventoryStyle.TEXT, 800)
		if String(r[1]).length() > 24:
			v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.custom_minimum_size = Vector2(190, 0)
		_facts_grid.add_child(v)


func _draw_detail_tile() -> void:
	var s := inventory.get_slot(selected) if inventory != null else {}
	if s.is_empty():
		return
	InventoryStyle.draw_item_tile(_detail_tile, Rect2(Vector2.ZERO, _detail_tile.size), s["item"], int(s["count"]), false, LootVisuals.text_font(800))


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


## Équipe l'arme sélectionnée dans l'emplacement courant du joueur : l'objet quitte le sac,
## l'arme remplacée y revient. Sac plein (l'arme remplacée ne rentrerait pas) : message, rien.
## Renvoie true si l'échange a eu lieu.
func _equip_selected() -> bool:
	var it := get_selected_item()
	var p: Node = GameState.player
	if it == null or not it.is_weapon() or p == null or not is_instance_valid(p):
		return false
	# Exemplaire avec ses affixes ; l'arme remplacée revient dans le sac avec les siens (weapon_item).
	var w := it.get_weapon()
	if w == null:
		return false
	# Équipement → emplacement d'équipement ; arme → emplacement d'arme courant.
	var method: StringName = &"equip_gadget" if w.is_gadget() else &"equip_into_current_slot"
	if not p.has_method(method):
		_flash_message("Impossible d'équiper cet objet pour l'instant.")
		return false
	var current: WeaponData = null
	if w.is_gadget():
		current = p.call(&"get_gadget") as WeaponData if p.has_method(&"get_gadget") else null
	else:
		current = p.get("weapon") as WeaponData
	var slot_idx := selected
	var removed := inventory.remove_at(slot_idx, 1)
	if removed.is_empty():
		return false
	# Vérifie la place pour l'objet remplacé AVANT l'échange (le sac a libéré une case).
	var back_item: ItemData = null
	var slot_empty := false if w.is_gadget() else _current_slot_empty(p)
	if current != null and not slot_empty:
		back_item = LootDB.weapon_item(current)
		if back_item != null and not inventory.can_add(back_item, 1):
			# Remet l'objet exactement dans sa case (pas de nouvelle vérification de poids).
			inventory.slots[slot_idx] = removed
			inventory.changed.emit()
			_flash_message("Sac plein : libère de la place pour ranger l'objet actuel.")
			_play(&"error")
			return false
	var replaced: Variant = p.call(method, w)
	if replaced is WeaponData:
		var bi := LootDB.weapon_item(replaced as WeaponData)
		if bi != null:
			inventory.add_item(bi, 1)
	_play(&"click")
	_refresh()
	return true


static func _current_slot_empty(p: Node) -> bool:
	if not p.has_method("get_weapons"):
		return false
	var list: Variant = p.call("get_weapons")
	var idx: Variant = p.get("current_slot")
	if list is Array and idx is int:
		var arr: Array = list
		return int(idx) >= arr.size() or arr[int(idx)] == null
	return false


func _flash_message(text: String) -> void:
	_detail_empty.visible = false
	var lbl := _detail_desc
	lbl.text = text
	lbl.label_settings.font_color = InventoryStyle.DANGER.lightened(0.25)
	get_tree().create_timer(1.8, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(lbl):
			lbl.label_settings.font_color = InventoryStyle.TEXT
			_refresh_detail())


func get_selected_item() -> ItemData:
	return inventory.get_slot(selected).get("item") as ItemData if inventory != null else null


func _drop_selected() -> void:
	if inventory == null or inventory.get_slot(selected).is_empty():
		return
	inventory.remove_at(selected, 1)
	_play(&"click")


func _use_selected() -> void:
	var it := get_selected_item()
	var p: Node = GameState.player
	if it == null or not it.is_usable() or p == null or not is_instance_valid(p):
		return
	if p.has_method("heal"):
		p.call("heal", it.heal_amount)
	inventory.remove_at(selected, 1)
	_play(&"heal")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_I or k == KEY_TAB:
			toggle()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()


func _play(sfx: StringName) -> void:
	var am := get_tree().root.get_node_or_null(^"AudioManager") if is_inside_tree() else null
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx)
