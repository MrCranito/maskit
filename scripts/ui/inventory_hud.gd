class_name InventoryHud
extends Control
## Couche UI du butin, à ajouter une fois dans le CanvasLayer du raid :
##   - InteractController (cible la plus proche, touche E) ;
##   - bouton « action » (bas droite, au-dessus du stick de visée) ;
##   - bouton sac (haut droite) + écran d'inventaire (I / Tab) ;
##   - fenêtre de butin d'un conteneur ouvert ;
##   - fil des objets ramassés (« + Pépite d'or ×2 », couleur de rareté).
## Aucun _process ici : tout est piloté par signaux.

const FEED_MAX := 4
const FEED_DURATION := 2.2

var controller: InteractController = null
var action_button: InteractButton = null
var bag_button: InventoryBagButton = null
var loot_window: InventoryLootWindow = null
var inventory_screen: InventoryScreen = null
var _feed: VBoxContainer = null


func _ready() -> void:
	name = "InventoryHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)

	controller = InteractController.new()
	add_child(controller)

	action_button = InteractButton.new()
	action_button.controller = controller
	add_child(action_button)
	_place_action_button()
	get_viewport().size_changed.connect(_place_action_button)

	bag_button = InventoryBagButton.new()
	add_child(bag_button)
	bag_button.anchor_left = 1.0
	bag_button.anchor_right = 1.0
	bag_button.offset_left = -16.0 - InventoryBagButton.SIZE.x
	bag_button.offset_right = -16.0
	bag_button.offset_top = 16.0
	bag_button.offset_bottom = 16.0 + InventoryBagButton.SIZE.y

	_feed = VBoxContainer.new()
	_feed.name = "PickupFeed"
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.add_theme_constant_override("separation", 6)
	# Sous la barre de vie (haut gauche) : jamais sous la fenêtre de butin ni le sac.
	_feed.offset_left = 16.0
	_feed.offset_right = 16.0 + 360.0
	_feed.offset_top = 84.0
	_feed.offset_bottom = 84.0 + FEED_MAX * 44.0
	add_child(_feed)

	loot_window = InventoryLootWindow.new()
	add_child(loot_window)
	loot_window.visibility_changed_for_action.connect(func(open: bool) -> void:
		action_button.set_suppressed(open))

	inventory_screen = InventoryScreen.new()
	add_child(inventory_screen)
	bag_button.pressed.connect(inventory_screen.toggle)
	inventory_screen.opened_changed.connect(_on_inventory_toggled)

	EventBus.item_picked_up.connect(_on_item_picked_up)
	var lm := get_tree().root.get_node_or_null(^"LootManager")
	if lm != null and lm.has_signal("key_used"):
		lm.connect("key_used", _on_key_used)


func _place_action_button() -> void:
	var vp := get_viewport_rect().size
	action_button.place_above_right_stick(vp,
		Balance.get_float("joystick", "right_rest_x", 0.87),
		Balance.get_float("joystick", "rest_y", 0.77),
		Balance.get_float("joystick", "radius", 90.0))


func _on_inventory_toggled(open: bool) -> void:
	if open:
		loot_window.close()
	action_button.set_suppressed(open)


func _on_item_picked_up(item: Resource, count: int) -> void:
	var it := item as ItemData
	if it == null:
		return
	_push_feed("+ %s%s" % [it.display_name, ("  ×%d" % count) if count > 1 else ""], LootDB.rarity_color(it.rarity).lightened(0.2), it)


func _on_key_used(key: ItemData, _door: Node) -> void:
	_push_feed("%s utilisée" % (key.display_name if key != null else "Clef"), InventoryStyle.GOLD, key)


func _push_feed(text: String, color: Color, item: ItemData) -> void:
	while _feed.get_child_count() >= FEED_MAX:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := InventoryStyle.panel(12, 6)
	st.content_margin_left = 10
	st.content_margin_right = 12
	st.shadow_size = 4
	st.border_color = Color(color, 0.8)
	p.add_theme_stylebox_override("panel", st)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var tex := LootVisuals.item_icon(item)
	if tex != null:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.modulate = item.tint
		ic.custom_minimum_size = Vector2(26, 26)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(ic)
	elif item != null and item.is_weapon():
		# Arme sans icône encore produite : pictogramme de la catégorie.
		var w := WeaponCatalog.get_weapon(item.weapon_id)
		var g := Control.new()
		g.custom_minimum_size = Vector2(44, 26)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.draw.connect(func() -> void: LootVisuals.draw_weapon(g, Rect2(Vector2.ZERO, g.size), w))
		h.add_child(g)
	h.add_child(InventoryStyle.label(text, 17, color, 800))
	_feed.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(FEED_DURATION)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
	tw.tween_callback(p.queue_free)


func toggle_inventory() -> void:
	inventory_screen.toggle()
