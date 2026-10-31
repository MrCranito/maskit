class_name InventoryLootWindow
extends Control
## Fenêtre de butin d'un conteneur ouvert (EventBus.container_opened), maquette « Butin
## révélé » (direction D) : panneau encre à coin coupé à droite de l'écran (le joueur reste
## visible), petit libellé violet (objets · valeur en or), nom du conteneur en Anton, une ligne
## par objet triée par rareté (liseré de rareté, icône, nom, rareté · valeur, « PRENDRE »),
## jauge du sac (emplacements, poids), « TOUT PRENDRE » violet.
## Se ferme quand le conteneur est vidé, via ✕, quand une autre cible d'interaction prend la
## place, et tout seul (glissement + fondu) dès que le joueur s'éloigne : distance au conteneur
## > portée d'interaction + portée propre du conteneur + marge d'hystérésis
## ([loot] loot_window_close_margin), vérifiée toutes les [loot] loot_window_check_interval s.
## Le jeu continue (pas de pause) : la fouille reste risquée.
## Reconstruite seulement quand le contenu change.

const ROW_HEIGHT := 64.0

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
var _bag_label: Label = null
var _bag_weight: Label = null
var _bag_bar: ProgressBar = null
var _tween: Tween = null
var _range_timer: Timer = null
var _closing: bool = false
## Position de repos du panneau (restaurée après le glissement de fermeture).
var _rest_x: float = 0.0


func _ready() -> void:
	name = "LootWindow"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()
	_range_timer = Timer.new()
	_range_timer.wait_time = maxf(LootDB.getf("loot_window_check_interval", 0.1), 0.02)
	_range_timer.timeout.connect(check_distance)
	add_child(_range_timer)
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
	var ps := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.9), 22.0, Color(0, 0, 0, 0), 0.0, 18.0, 16.0)
	ps.corners = CutBox.CUT_TOP_RIGHT
	_panel.add_theme_stylebox_override("panel", ps)
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
	_subtitle = MenuKit.label("", 15, MenuKit.GOLD, MenuKit.nunito(600), 0)
	_subtitle.uppercase = true
	names.add_child(_subtitle)
	_title = MenuKit.label("", 34, MenuKit.TEXT, MenuKit.display(), 0)
	_title.uppercase = true
	names.add_child(_title)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "×"
	close_btn.tooltip_text = "Fermer"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(52, 52)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_btn.add_theme_font_override("font", MenuKit.nunito(500))
	close_btn.add_theme_font_size_override("font_size", 28)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		close_btn.add_theme_color_override(k, MenuKit.TEXT)
	close_btn.add_theme_stylebox_override("normal", CutBox.make(Color(0, 0, 0, 0), 0.0, Color(1, 1, 1, 0.4), 1.5, 0.0, 0.0))
	close_btn.add_theme_stylebox_override("hover", CutBox.make(Color(1, 1, 1, 0.1), 0.0, Color(1, 1, 1, 0.6), 1.5, 0.0, 0.0))
	close_btn.add_theme_stylebox_override("pressed", CutBox.make(Color(0, 0, 0, 0.4), 0.0, Color(1, 1, 1, 0.6), 1.5, 0.0, 0.0))
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	_full_label = MenuKit.label("▲ Sac plein ou trop lourd", 16, Color(1.0, 0.44, 0.57), MenuKit.nunito(600), 0)
	_full_label.uppercase = true
	_full_label.visible = false
	v.add_child(_full_label)

	# Jauge du sac : emplacements (gauche) et poids (droite)
	var bag := VBoxContainer.new()
	bag.add_theme_constant_override("separation", 4)
	v.add_child(bag)
	var brow := HBoxContainer.new()
	bag.add_child(brow)
	_bag_label = MenuKit.label("", 15, MenuKit.TEXT, MenuKit.nunito(600), 0)
	_bag_label.uppercase = true
	_bag_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(_bag_label)
	_bag_weight = MenuKit.label("", 15, MenuKit.TEXT, MenuKit.nunito(600), 0)
	_bag_weight.uppercase = true
	brow.add_child(_bag_weight)
	_bag_bar = ProgressBar.new()
	_bag_bar.show_percentage = false
	_bag_bar.custom_minimum_size = Vector2(0, 7)
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color(1, 1, 1, 0.14)
	var bf := StyleBoxFlat.new()
	bf.bg_color = MenuKit.VIOLET_LIGHT
	_bag_bar.add_theme_stylebox_override("background", bb)
	_bag_bar.add_theme_stylebox_override("fill", bf)
	bag.add_child(_bag_bar)

	_take_all = Button.new()
	_take_all.name = "TakeAll"
	_take_all.text = "TOUT PRENDRE"
	_take_all.focus_mode = Control.FOCUS_NONE
	_take_all.custom_minimum_size = Vector2(0, 64)
	_take_all.add_theme_font_override("font", MenuKit.display())
	_take_all.add_theme_font_size_override("font_size", 28)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_take_all.add_theme_color_override(k, MenuKit.TEXT)
	_take_all.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	var mk := func(bg: Color) -> CutBox:
		var c := CutBox.make(bg, 14.0, Color(0, 0, 0, 0), 0.0, 16.0, 0.0)
		c.corners = CutBox.CUT_TOP_LEFT
		return c
	_take_all.add_theme_stylebox_override("normal", mk.call(MenuKit.VIOLET))
	_take_all.add_theme_stylebox_override("hover", mk.call(MenuKit.VIOLET.lightened(0.12)))
	_take_all.add_theme_stylebox_override("pressed", mk.call(MenuKit.VIOLET.darkened(0.2)))
	_take_all.add_theme_stylebox_override("hover_pressed", mk.call(MenuKit.VIOLET.darkened(0.2)))
	_take_all.add_theme_stylebox_override("disabled", mk.call(Color(MenuKit.VIOLET, 0.35)))
	_take_all.pressed.connect(_on_take_all)
	v.add_child(_take_all)


func is_open() -> bool:
	return visible and not _closing


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
	_range_timer.start()
	if _closing:
		# Rouvert pendant le fondu de fermeture : on repart d'un panneau visible.
		_closing = false
		visible = false
		_panel.position.x = _rest_x
		_panel.modulate.a = 1.0
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


## Ferme la fenêtre ; `animated` : glissement vers la droite + fondu (le joueur s'éloigne).
func close(animated: bool = false) -> void:
	if visible and not _closing:
		visibility_changed_for_action.emit(false)
	container = null
	if _range_timer != null:
		_range_timer.stop()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animated or not visible or not is_inside_tree():
		if _closing:
			_panel.position.x = _rest_x
		visible = false
		_closing = false
		_panel.modulate.a = 1.0
		return
	_closing = true
	_rest_x = _panel.position.x
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.2)
	_tween.tween_property(_panel, "position:x", _panel.position.x + 40.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func() -> void:
		visible = false
		_closing = false
		_panel.modulate.a = 1.0
		_panel.position.x = _rest_x)


## Logique pure : le joueur est-il trop loin du conteneur ? (hystérésis : la fenêtre ne se ferme
## qu'au-delà de la portée d'interaction + marge, jamais pile à la limite).
static func out_of_range(distance: float, interact_range: float, reach: float, margin: float) -> bool:
	return distance > interact_range + reach + maxf(margin, 0.0)


## Fermeture automatique quand le joueur s'éloigne (appelée par le minuteur et sur perte de cible).
func check_distance() -> void:
	if not visible or _closing:
		return
	if container == null or not is_instance_valid(container) or not container.is_inside_tree():
		close(true)
		return
	var p: Node2D = GameState.player
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return
	var reach := float(container.call("get_interact_reach")) if container.has_method("get_interact_reach") else 0.0
	if out_of_range(p.global_position.distance_to(container.global_position), LootDB.getf("interact_range", 78.0),
			reach, LootDB.getf("loot_window_close_margin", 24.0)):
		close(true)


func _on_target_changed(t: Node) -> void:
	if not visible or _closing or t == container:
		return
	if t != null:
		# Une autre cible prend la place (le bouton action doit redevenir utilisable).
		close(true)
	else:
		# Plus de cible : on ne ferme qu'au-delà de la marge (pas de clignotement en limite).
		check_distance()


func _rebuild() -> void:
	for ch: Node in _list.get_children():
		ch.queue_free()
	if container == null or not is_instance_valid(container):
		close()
		return
	_title.text = container.get_display_name()
	_refresh_bag()
	var n := container.entries.size()
	if n == 0:
		_subtitle.text = "Rien d'intéressant"
		var empty := MenuKit.label("Le conteneur est vide.", 18, Color(1, 1, 1, 0.6), MenuKit.nunito(600), 0)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(0, 60)
		_list.add_child(empty)
		_scroll.custom_minimum_size = Vector2(0, 60)
		_take_all.disabled = true
		return
	var gold := 0
	for e: Dictionary in container.entries:
		gold += Economy.item_sell_price(e["item"] as ItemData) * int(e["count"])
	_subtitle.text = "%d objet%s · ≈ %d or" % [n, "s" if n > 1 else "", gold]
	_take_all.disabled = false
	# Affichage du plus rare au moins rare ; chaque ligne garde l'index réel de l'entrée.
	for i: int in display_order(container.entries):
		_list.add_child(_make_row(i, container.entries[i]))
	# Au-delà de 4 lignes : défilement (le panneau ne dépasse pas l'écran).
	_scroll.custom_minimum_size = Vector2(0, (ROW_HEIGHT + 6.0) * mini(n, 4) - 6.0)


## Index des entrées dans l'ordre d'affichage : rareté décroissante, puis valeur décroissante.
static func display_order(entries: Array[Dictionary]) -> Array[int]:
	var idx: Array[int] = []
	for i in entries.size():
		idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool:
		var ia: ItemData = entries[a]["item"]
		var ib: ItemData = entries[b]["item"]
		return ia.rarity > ib.rarity if ia.rarity != ib.rarity else ia.value > ib.value)
	return idx


func _refresh_bag() -> void:
	if inventory == null or _bag_label == null:
		return
	_bag_label.text = "Sac %d / %d" % [inventory.used_slots(), inventory.capacity()]
	_bag_weight.text = ("%.1f / %.0f kg" % [inventory.total_weight(), inventory.max_weight]).replace(".", ",")
	_bag_bar.max_value = maxf(inventory.max_weight, 0.1)
	_bag_bar.value = inventory.total_weight()


func _make_row(i: int, e: Dictionary) -> Control:
	var it: ItemData = e["item"]
	var count := int(e["count"])
	var rc := LootDB.rarity_color(it.rarity)
	var row := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(rc, 0.14) if it.rarity >= ItemData.Rarity.EPIC else Color(1, 1, 1, 0.04)
	st.border_color = rc
	st.border_width_left = 4
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", st)
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var tile := Control.new()
	tile.custom_minimum_size = Vector2(52, 52)
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
	var nm := MenuKit.label(it.display_name + ("  ×%d" % count if count > 1 else ""), 18, MenuKit.TEXT, MenuKit.nunito(700), 0)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(150, 0)
	names.add_child(nm)
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	names.add_child(meta)
	var rl := MenuKit.label(LootDB.rarity_name(it.rarity), 14, rc, MenuKit.nunito(600), 0)
	rl.uppercase = true
	meta.add_child(rl)
	var vl := MenuKit.label("· ≈ %d or" % (Economy.item_sell_price(it) * count), 14, Color(1, 1, 1, 0.55), MenuKit.nunito(600), 0)
	vl.uppercase = true
	meta.add_child(vl)
	var take := Button.new()
	take.text = "PRENDRE"
	take.focus_mode = Control.FOCUS_NONE
	take.custom_minimum_size = Vector2(104, 48)
	take.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	take.add_theme_font_override("font", MenuKit.display())
	take.add_theme_font_size_override("font_size", 19)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		take.add_theme_color_override(k, MenuKit.TEXT)
	take.add_theme_stylebox_override("normal", CutBox.make(MenuKit.NIGHT_DEEP, 0.0, Color(1, 1, 1, 0.35), 1.0, 0.0, 0.0))
	take.add_theme_stylebox_override("hover", CutBox.make(MenuKit.NIGHT_PANEL, 0.0, Color(1, 1, 1, 0.6), 1.0, 0.0, 0.0))
	take.add_theme_stylebox_override("pressed", CutBox.make(Color(MenuKit.VIOLET, 0.8), 0.0, Color(0, 0, 0, 0), 0.0, 0.0, 0.0))
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
