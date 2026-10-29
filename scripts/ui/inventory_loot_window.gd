class_name InventoryLootWindow
extends Control
## Fenêtre de butin d'un conteneur ouvert (EventBus.container_opened) : panneau bleu
## nuit à droite de l'écran (le joueur reste visible), une ligne par objet (icône,
## nom couleur de rareté, quantité, bouton « Prendre »), bouton « Tout prendre ».
## Se ferme quand le conteneur est vidé, quand on s'éloigne (cible d'interaction
## perdue) ou via ✕. Le jeu continue (pas de pause) : la fouille reste risquée.
## Reconstruite seulement quand le contenu change.

const ROW_HEIGHT := 70.0

## Ouverture / fermeture (l'InventoryHud masque alors le bouton action, couvert par la fenêtre).
signal visibility_changed_for_action(open: bool)

var container: LootContainer = null
var inventory: Inventory = null

var _panel: PanelContainer = null
var _title: Label = null
var _subtitle: Label = null
var _list: VBoxContainer = null
var _scroll: ScrollContainer = null
var _take_all: Button = null
var _full_label: Label = null
var _tween: Tween = null


func _ready() -> void:
	name = "LootWindow"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	EventBus.container_opened.connect(_on_container_opened)
	EventBus.interact_target_changed.connect(_on_target_changed)
	EventBus.floor_changed.connect(func(_i: int) -> void: close())
	get_viewport().size_changed.connect(_place_safe)
	_place_safe()


## Haut droite sous le sac, dans la zone sûre (encoche / coins arrondis).
func _place_safe() -> void:
	if _panel == null or not is_inside_tree():
		return
	var m := HudSafeArea.margins(self)
	_panel.offset_right = -m.z
	_panel.offset_left = -m.z - 430
	_panel.offset_top = m.y + 92.0
	_panel.offset_bottom = m.y + 92.0


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", InventoryStyle.panel(20, 18))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.custom_minimum_size = Vector2(430, 0)
	# Ancré à droite, centré verticalement (au-dessus du stick droit, sous le sac).
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -16
	_panel.offset_left = -16 - 430
	_panel.offset_top = 108
	_panel.offset_bottom = 108
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 0)
	head.add_child(names)
	_title = InventoryStyle.title("", 28)
	names.add_child(_title)
	_subtitle = InventoryStyle.label("", 15, InventoryStyle.TEXT_SECONDARY, 700)
	names.add_child(_subtitle)
	var close_btn := InventoryStyle.button("✕", InventoryStyle.NIGHT_BLUE_LIGHT, 22, Vector2(54, 50))
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var sep := ColorRect.new()
	sep.color = Color(InventoryStyle.GOLD, 0.35)
	sep.custom_minimum_size = Vector2(0, 2)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sep)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_full_label = InventoryStyle.label("Sacoche pleine ou trop lourde !", 16, Color(1.0, 0.55, 0.45), 800)
	_full_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_full_label.visible = false
	v.add_child(_full_label)

	_take_all = InventoryStyle.button("Tout prendre", InventoryStyle.GOLD, 21, Vector2(0, 60))
	_take_all.pressed.connect(_on_take_all)
	v.add_child(_take_all)


func is_open() -> bool:
	return visible


func _on_container_opened(c: Node2D, _entries: Array) -> void:
	if not (c is LootContainer):
		return
	open_for(c as LootContainer, GameState.raid_inventory)


func open_for(c: LootContainer, inv: Inventory) -> void:
	container = c
	inventory = inv
	_full_label.visible = false
	visibility_changed_for_action.emit(true)
	_rebuild()
	if not visible:
		visible = true
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_panel.modulate.a = 0.0
		_panel.position.x += 40.0
		var to_x := _panel.position.x - 40.0
		_tween = create_tween().set_parallel(true)
		_tween.tween_property(_panel, "modulate:a", 1.0, 0.14)
		_tween.tween_property(_panel, "position:x", to_x, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	if visible:
		visibility_changed_for_action.emit(false)
	visible = false
	container = null


func _on_target_changed(t: Node) -> void:
	if visible and t != container:
		close()


func _rebuild() -> void:
	for ch: Node in _list.get_children():
		ch.queue_free()
	if container == null or not is_instance_valid(container):
		close()
		return
	_title.text = container.get_display_name()
	var n := container.entries.size()
	if n == 0:
		_subtitle.text = "Rien d'intéressant…"
		var empty := InventoryStyle.label("Le conteneur est vide.", 18, InventoryStyle.TEXT_SECONDARY, 600)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 60)
		_list.add_child(empty)
		_scroll.custom_minimum_size = Vector2(0, 60)
		_take_all.disabled = true
		return
	_subtitle.text = "%d objet%s · %d $" % [n, "s" if n > 1 else "", LootRoller.total_value(container.entries)]
	_take_all.disabled = false
	for i in n:
		_list.add_child(_make_row(i, container.entries[i]))
	# Au-delà de 5 lignes : défilement (le panneau ne dépasse pas l'écran).
	_scroll.custom_minimum_size = Vector2(0, (ROW_HEIGHT + 8.0) * mini(n, 5) - 8.0)


func _make_row(i: int, e: Dictionary) -> Control:
	var it: ItemData = e["item"]
	var count := int(e["count"])
	var rc := LootDB.rarity_color(it.rarity)
	var row := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = InventoryStyle.NIGHT_BLUE_DEEP.lerp(rc, 0.10)
	st.border_color = Color(rc, 0.75)
	st.border_width_left = 5
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_right = 8
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", st)
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var tile := Control.new()
	tile.custom_minimum_size = Vector2(56, 56)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.draw.connect(func() -> void:
		InventoryStyle.draw_item_tile(tile, Rect2(Vector2.ZERO, tile.size), it, count, false, LootVisuals.text_font(800)))
	h.add_child(tile)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation", 0)
	h.add_child(names)
	var nm := InventoryStyle.label(it.display_name + ("  ×%d" % count if count > 1 else ""), 19, rc.lightened(0.2), 800)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(150, 0)
	names.add_child(nm)
	names.add_child(InventoryStyle.label("%s · ≈ %d or" % [LootDB.rarity_name(it.rarity), Economy.item_sell_price(it) * count], 14, InventoryStyle.TEXT_SECONDARY, 700))
	var take := InventoryStyle.button("Prendre", InventoryStyle.NIGHT_BLUE_LIGHT, 17, Vector2(108, 52))
	take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	take.pressed.connect(_on_take.bind(i))
	h.add_child(take)
	return row


func _on_take(i: int) -> void:
	if container == null or not is_instance_valid(container):
		close()
		return
	var got := container.take(i, inventory)
	_after_take(got)


func _on_take_all() -> void:
	if container == null or not is_instance_valid(container):
		close()
		return
	var got := container.take_all(inventory)
	_after_take(got)


func _after_take(got: int) -> void:
	_full_label.visible = got <= 0 or (container != null and is_instance_valid(container) and not container.is_emptied())
	if got <= 0:
		_play(&"error")
	if container == null or not is_instance_valid(container) or container.is_emptied():
		close()
		return
	_full_label.visible = got <= 0 or not _all_fit()
	_rebuild()


func _all_fit() -> bool:
	if container == null or inventory == null:
		return true
	for e: Dictionary in container.entries:
		if not inventory.can_add(e["item"], int(e["count"])):
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif k == KEY_R or k == KEY_SPACE:
			_on_take_all()
			get_viewport().set_input_as_handled()


func _play(sfx: StringName) -> void:
	var am := get_tree().root.get_node_or_null(^"AudioManager") if is_inside_tree() else null
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx)
