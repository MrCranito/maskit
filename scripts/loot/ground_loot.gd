class_name GroundLoot
extends Node2D
## Butin tombé au sol à la mort d'un ennemi : petite icône posée sur une lueur de rareté,
## court rebond à l'apparition. Ramassé en marchant dessus (Area2D sur le joueur) ; sac plein →
## message « Sac plein », l'objet reste et peut être ramassé plus tard par l'interaction (E).
## Aucun traitement par image hors du rebond (set_process(false) ensuite) ; dessin statique.

signal picked(loot: GroundLoot, count: int)

const GROUP := &"ground_loot"
const MASK_PLAYER := 2
const OUTLINE := Color(0.08, 0.06, 0.1)
const ICON_SIZE := 22.0
const BOUNCE_TIME := 0.55
const BOUNCE_HEIGHT := 26.0

var item: ItemData = null
var count: int = 1
## Identifiant unique dans l'étage (persistance).
var loot_id: int = 0
var floor_index: int = 0
var _from: Vector2 = Vector2.ZERO
var _t: float = -1.0
var _icon: Texture2D = null
var _height: float = 0.0
var _full_msg_msec: int = -100000
var _draw_offset: Vector2 = Vector2.ZERO


static func create(p_item: ItemData, p_count: int, from: Vector2, to: Vector2, bounce: bool = true) -> GroundLoot:
	var g := GroundLoot.new()
	g.item = p_item
	g.count = maxi(p_count, 1)
	g.position = to
	g._from = from
	g._t = 0.0 if bounce else -1.0
	g.name = "GroundLoot_%s" % String(p_item.id if p_item != null else &"x")
	return g


func _init() -> void:
	add_to_group(GROUP)
	add_to_group(&"fog_hideable")
	add_to_group(&"interactables")


func _ready() -> void:
	z_index = 7
	z_as_relative = false
	_icon = LootVisuals.item_icon(item)
	var area := Area2D.new()
	area.name = "Pickup"
	area.collision_layer = 0
	area.collision_mask = MASK_PLAYER
	area.monitorable = false
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = float(LootDB.cfg().get_value("enemy_loot", "ground_pickup_radius", 22.0))
	cs.shape = c
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	set_process(_t >= 0.0)
	queue_redraw()


func _process(delta: float) -> void:
	if _t < 0.0:
		set_process(false)
		return
	_t += delta
	var u := clampf(_t / BOUNCE_TIME, 0.0, 1.0)
	# Arc depuis le corps puis petit rebond.
	var arc := 4.0 * u * (1.0 - u)
	_height = BOUNCE_HEIGHT * arc + (6.0 * absf(sin(u * PI * 3.0)) * (1.0 - u) if u > 0.6 else 0.0)
	_draw_offset = (_from - global_position) * (1.0 - ease(u, 0.6))
	if u >= 1.0:
		_t = -1.0
		_height = 0.0
		_draw_offset = Vector2.ZERO
		set_process(false)
		_check_overlap.call_deferred()
	queue_redraw()



func _check_overlap() -> void:
	var area := get_node_or_null(^"Pickup") as Area2D
	if area == null or not is_inside_tree():
		return
	for b: Node2D in area.get_overlapping_bodies():
		_on_body_entered(b)


func _on_body_entered(body: Node2D) -> void:
	if _t >= 0.0 or not body.is_in_group(&"player"):
		return
	try_pickup(body, false)


# --- Interaction (sac plein : ramasser plus tard) -------------------------------------

func can_interact() -> bool:
	return item != null and count > 0


func get_interact_label() -> String:
	return "Ramasser"


func get_interact_icon() -> String:
	return "open"


func get_interact_reach() -> float:
	return 6.0


func interact(player: Node) -> void:
	try_pickup(player as Node2D, true)


## Ajoute l'objet au sac de raid. Renvoie le nombre pris (0 = sac plein → message).
func try_pickup(_player: Node2D, explicit: bool) -> int:
	if item == null or count <= 0:
		return 0
	var inv: Inventory = GameState.get("raid_inventory") as Inventory
	if inv == null:
		return 0
	var got := inv.add_item(item, count)
	if got <= 0:
		var now := Time.get_ticks_msec()
		if explicit or now - _full_msg_msec > 2500:
			_full_msg_msec = now
			_toast("Sac plein : %s reste au sol" % item.display_name)
		return 0
	count -= got
	EventBus.item_picked_up.emit(item, got)
	_play(&"coin_pickup" if item.id == &"silver_dollars" or item.id == &"gold_nugget" else
		(&"key_pickup" if item.is_key() else &"item_pickup"))
	picked.emit(self, got)
	_notify_manager()
	if count <= 0:
		queue_free()
	else:
		_toast("Sac plein : %d %s restent au sol" % [count, item.display_name])
		queue_redraw()
	return got


func _notify_manager() -> void:
	var lm := get_node_or_null(^"/root/LootManager")
	if lm != null and lm.has_method("on_ground_loot_changed"):
		lm.call("on_ground_loot_changed", self)


func _toast(text: String) -> void:
	if not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("show_toast"):
		scene.call("show_toast", text)
		return
	var fx := CombatFx.get_or_create(get_tree())
	if fx != null:
		fx.air.emit_text(global_position + Vector2(-40, -30), text, Color(1.0, 0.9, 0.7), 15.0, 1.4, 30.0)


func _play(sfx: StringName) -> void:
	var am := get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, global_position)


func to_record() -> Dictionary:
	return {"id": loot_id, "item": item, "count": count, "pos": position}


# --- Dessin (statique hors rebond) ------------------------------------------------------

func _draw() -> void:
	if item == null:
		return
	var col := LootDB.rarity_color(item.rarity)
	var strong := item.rarity >= 3 or item.is_key()
	# Lueur de rareté au sol (plus forte pour Épique / Légendaire / clefs).
	draw_set_transform(_draw_offset + Vector2(0, -1), 0.0, Vector2(1.0, 0.45))
	var gr := 24.0 if strong else 17.0
	for k in 4:
		var f := 1.0 - k * 0.22
		draw_circle(Vector2.ZERO, gr * f, Color(col, (0.12 if strong else 0.07) + k * (0.06 if strong else 0.04)))
	draw_circle(Vector2.ZERO, 9.0, Color(0.05, 0.06, 0.15, 0.35))
	draw_set_transform(Vector2.ZERO)
	var c := _draw_offset + Vector2(0, -10.0 - _height)
	if strong:
		# Rayon de lumière vertical (repérable de loin).
		draw_rect(Rect2(c + Vector2(-2.0, -30.0), Vector2(4.0, 30.0)), Color(col, 0.28))
	draw_circle(c, ICON_SIZE * 0.62, Color(0.07, 0.1, 0.18, 0.85))
	draw_arc(c, ICON_SIZE * 0.62, 0.0, TAU, 24, col, 2.0, true)
	if _icon != null:
		var ts := _icon.get_size()
		var k2 := ICON_SIZE / maxf(ts.x, ts.y)
		var sz := ts * k2
		draw_texture_rect(_icon, Rect2(c - sz * 0.5, sz), false, LootVisuals.item_tint(item))
	else:
		draw_circle(c, 6.0, col)
	if count > 1:
		var font := ThemeDB.fallback_font
		var s := "×%d" % count
		draw_string_outline(font, c + Vector2(6, 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, OUTLINE)
		draw_string(font, c + Vector2(6, 12), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
