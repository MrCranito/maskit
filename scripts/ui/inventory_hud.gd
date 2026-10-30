class_name InventoryHud
extends Control
## Couche UI du butin, à ajouter une fois dans le CanvasLayer du raid :
##   - InteractController (cible la plus proche, touche E) ;
##   - bouton « action » (bas droite, au-dessus du stick de visée) ;
##   - bouton sac (haut droite) + écran d'inventaire (I / Tab) ;
##   - fenêtre de butin d'un conteneur ouvert ;
##   - fil des objets ramassés (« + Pépite d'or ×2 », couleur de rareté) et des armes devenues
##     achetables (Profile.weapon_unlocked : « Nouvelle arme déblocable à l'armurerie : … »).
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
	_place_safe()

	loot_window = InventoryLootWindow.new()
	add_child(loot_window)
	loot_window.visibility_changed_for_action.connect(func(open: bool) -> void:
		action_button.set_suppressed(open))

	inventory_screen = InventoryScreen.new()
	add_child(inventory_screen)
	bag_button.pressed.connect(inventory_screen.toggle)
	inventory_screen.opened_changed.connect(_on_inventory_toggled)

	EventBus.item_picked_up.connect(_on_item_picked_up)
	# Économie : seuil de victimes atteint → arme achetable à l'armurerie.
	var prof := get_tree().root.get_node_or_null(^"Profile")
	if prof != null and prof.has_signal("weapon_unlocked"):
		prof.connect("weapon_unlocked", _on_weapon_unlocked)
	var lm := get_tree().root.get_node_or_null(^"LootManager")
	if lm != null and lm.has_signal("key_used"):
		lm.connect("key_used", _on_key_used)


## Sac (haut droite) et fil des ramassages (haut gauche, sous la vie) dans la zone sûre.
func _place_safe() -> void:
	var m := HudSafeArea.margins(self)
	bag_button.offset_left = -m.z - InventoryBagButton.SIZE.x
	bag_button.offset_right = -m.z
	bag_button.offset_top = m.y
	bag_button.offset_bottom = m.y + InventoryBagButton.SIZE.y
	_feed.offset_left = m.x
	_feed.offset_right = m.x + 360.0
	_feed.offset_top = m.y + 68.0
	_feed.offset_bottom = _feed.offset_top + FEED_MAX * 44.0
	align_pause_button()


## Bouton pause (menu pause, frère dans le CanvasLayer) : juste à gauche du sac, même haut,
## dans la zone sûre. Recalé à chaque redimensionnement.
func align_pause_button() -> void:
	var parent := get_parent()
	if parent == null or bag_button == null:
		return
	var pb := parent.get_node_or_null(^"PauseMenu/PauseButton") as Control
	if pb == null:
		return
	var m := HudSafeArea.margins(self)
	var s := maxf(pb.custom_minimum_size.x, 1.0)
	var gap := Balance.get_float("hud", "pause_bag_gap", 10.0)
	pb.anchor_left = 1.0
	pb.anchor_right = 1.0
	pb.offset_right = bag_button.offset_left - gap
	pb.offset_left = pb.offset_right - s
	var top := m.y + (InventoryBagButton.SIZE.y - s) * 0.5
	pb.offset_top = top
	pb.offset_bottom = top + s


func _place_action_button() -> void:
	if bag_button != null and _feed != null:
		_place_safe()
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
	# Arme à affixes : leurs noms suivent le nom de l'arme (« + M4A1 · Brûlure, Gel »).
	var ax := ("  · " + Affixes.names_text(it.weapon_affixes)) if not it.weapon_affixes.is_empty() else ""
	_push_feed("+ %s%s%s" % [it.display_name, ax, ("  ×%d" % count) if count > 1 else ""], LootDB.rarity_color(it.rarity).lightened(0.2), it)


func _on_key_used(key: ItemData, _door: Node) -> void:
	_push_feed("%s utilisée" % (key.display_name if key != null else "Clef"), InventoryStyle.GOLD, key)


func _on_weapon_unlocked(weapon_id: StringName) -> void:
	var w := WeaponCatalog.get_weapon(weapon_id)
	if w == null:
		return
	_push_feed("Nouvelle arme déblocable à l'armurerie : %s" % w.display_name, InventoryStyle.GOLD,
		LootDB.weapon_item(w), Balance.get_float("economy", "unlock_notice_duration", 4.5))
	var am := get_tree().root.get_node_or_null(^"AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", &"confirm", Vector2.INF, -4.0)


## Texte du fil le plus récent (tests).
func get_last_feed_text() -> String:
	if _feed == null or _feed.get_child_count() == 0:
		return ""
	var labels := _feed.get_child(_feed.get_child_count() - 1).find_children("*", "Label", true, false)
	return (labels[labels.size() - 1] as Label).text if not labels.is_empty() else ""


func _push_feed(text: String, color: Color, item: ItemData, duration: float = FEED_DURATION) -> void:
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
	tw.tween_interval(duration)
	tw.tween_property(p, "modulate:a", 0.0, 0.35)
	tw.tween_callback(p.queue_free)


func toggle_inventory() -> void:
	inventory_screen.toggle()
