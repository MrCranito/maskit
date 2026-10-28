class_name HidingSpot
extends Node2D
## Cachette (tonneau à eau, armoire, botte de foin, dessous de porche).
## Groupes : hiding_spots, interactables. Origine = point d'appui au sol.
## interact(player) : entre (player.set_hidden(true, self)) ou sort (set_hidden(false)).
## Occupée : petit tremblement (Tween en boucle, aucun _process) + icône d'œil barré.

signal occupied_changed(spot: HidingSpot, occupied: bool)

const SPRITES_DIR := "res://assets/sprites/far_west/containers/"
const LAYER_WORLD := 1
const GROUP := &"hiding_spots"
const SHADOW_COLOR := Color(0.07, 0.1, 0.25, 0.4)
const KINDS: Array[StringName] = [&"barrel", &"wardrobe", &"haystack", &"porch"]

## kind → définition (cf. LootContainer.DEFS).
const DEFS := {
	&"barrel": {"name": "Tonneau", "scale": 0.55, "block": Vector2(36, 16), "shadow": 22.0, "foot": 4.0, "reach": 2.0},
	&"wardrobe": {"name": "Armoire", "scale": 0.55, "block": Vector2(48, 14), "shadow": 28.0, "foot": 2.0, "reach": 4.0},
	&"haystack": {"name": "Botte de foin", "scale": 0.55, "block": Vector2(58, 20), "shadow": 34.0, "foot": 4.0, "reach": 8.0},
	&"porch": {"name": "Sous le porche", "scale": 0.55, "block": Vector2(70, 16), "shadow": 0.0, "foot": 2.0, "reach": 8.0},
}

static var _tex_cache: Dictionary = {}

var kind: StringName = &"barrel"
var cell: Vector2i = Vector2i.ZERO
var occupant: Node2D = null

var _def: Dictionary = {}
var _sprite: Sprite2D = null
var _eye: Node2D = null
var _shake: Tween = null


static func create(p_kind: StringName, pos: Vector2) -> HidingSpot:
	var h := HidingSpot.new()
	h.kind = p_kind if DEFS.has(p_kind) else &"barrel"
	h.name = "Hide_%s" % String(h.kind)
	h.position = pos
	return h


static func get_texture(k: StringName) -> Texture2D:
	var key := "%s_%s" % [BiomeAssets.containers_dir, k]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var path := BiomeAssets.find_sprite("hide_" + String(k), SPRITES_DIR)
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[key] = tex
	return tex


func _init() -> void:
	add_to_group(GROUP)
	add_to_group(&"interactables")


func _ready() -> void:
	_def = DEFS.get(kind, DEFS[&"barrel"])
	z_index = 10
	set_process(false)
	var tex := get_texture(kind)
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.texture = tex
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_sprite.scale = Vector2.ONE * float(_def.get("scale", 0.55))
		_sprite.offset = Vector2(0.0, -tex.get_height() * 0.5 + float(_def.get("foot", 0.0)))
		add_child(_sprite)
	var block: Vector2 = _def.get("block", Vector2.ZERO)
	if block != Vector2.ZERO:
		var body := StaticBody2D.new()
		body.name = "Body"
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = block
		cs.shape = rect
		cs.position = Vector2(0.0, -block.y * 0.5)
		body.add_child(cs)
		add_child(body)
	_eye = Node2D.new()
	_eye.name = "HiddenEye"
	_eye.z_as_relative = false
	_eye.z_index = 60
	_eye.position = Vector2(0.0, -get_visual_height() - 22.0)
	_eye.visible = false
	_eye.draw.connect(_draw_eye)
	add_child(_eye)


func get_display_name() -> String:
	return String(_def.get("name", "Cachette"))


func get_visual_height() -> float:
	if _sprite != null and _sprite.texture != null:
		return (_sprite.texture.get_height() - float(_def.get("foot", 0.0))) * _sprite.scale.y
	return 40.0


func get_interact_reach() -> float:
	return float(_def.get("reach", 0.0))


func is_occupied() -> bool:
	return occupant != null and is_instance_valid(occupant)


func can_interact() -> bool:
	return true


func get_interact_label() -> String:
	return "Sortir" if is_occupied() else "Se cacher"


func get_interact_icon() -> String:
	return "exit" if is_occupied() else "hide"


## Entre dans la cachette, ou en sort si le joueur y est déjà.
func interact(player: Node) -> void:
	if player == null:
		return
	if is_occupied():
		if occupant == player:
			exit(player)
		return
	enter(player)


func enter(player: Node) -> void:
	if is_occupied() or player == null:
		return
	occupant = player as Node2D
	if player.has_method("set_hidden"):
		player.call("set_hidden", true, self)
	if player.has_signal("hidden_changed") and not player.is_connected("hidden_changed", _on_player_hidden_changed):
		player.connect("hidden_changed", _on_player_hidden_changed)
	_set_player_visible(occupant, false)
	_set_occupied_visual(true)
	_play(&"door_close")
	occupied_changed.emit(self, true)


func exit(player: Node = null) -> void:
	if not is_occupied():
		return
	var p := occupant
	occupant = null
	_set_player_visible(p, true)
	if p != null and is_instance_valid(p):
		if p.is_connected("hidden_changed", _on_player_hidden_changed):
			p.disconnect("hidden_changed", _on_player_hidden_changed)
		if p.has_method("is_hidden") and bool(p.call("is_hidden")):
			p.call("set_hidden", false)
		elif player != null and player.has_method("set_hidden") and not player.has_method("is_hidden"):
			player.call("set_hidden", false)
	_set_occupied_visual(false)
	_play(&"door_open")
	occupied_changed.emit(self, false)


## Le joueur est sorti par lui-même (stick poussé, dégâts…).
func _on_player_hidden_changed(is_hidden: bool, _spot: Node) -> void:
	if not is_hidden and is_occupied():
		var p := occupant
		occupant = null
		_set_player_visible(p, true)
		if p.is_connected("hidden_changed", _on_player_hidden_changed):
			p.disconnect("hidden_changed", _on_player_hidden_changed)
		_set_occupied_visual(false)
		occupied_changed.emit(self, false)


## Sprite du joueur masqué tant qu'il est caché ([loot] hide_player_sprite) ; la
## cachette tremble et l'œil barré indique où il est.
func _set_player_visible(p: Node, on: bool) -> void:
	if p is CanvasItem and is_instance_valid(p) and bool(LootDB.cfg().get_value(LootDB.SECTION, "hide_player_sprite", true)):
		(p as CanvasItem).visible = on


func _set_occupied_visual(on: bool) -> void:
	_eye.visible = on
	if _shake != null and _shake.is_valid():
		_shake.kill()
		_shake = null
	if _sprite == null:
		return
	_sprite.position = Vector2.ZERO
	_sprite.rotation = 0.0
	if on and is_inside_tree():
		var px := LootDB.getf("hiding_shake_px", 1.6)
		var per := LootDB.getf("hiding_shake_period", 0.09)
		_shake = create_tween().set_loops()
		_shake.tween_property(_sprite, "position:x", px, per).set_trans(Tween.TRANS_SINE)
		_shake.tween_property(_sprite, "position:x", -px, per * 2.0).set_trans(Tween.TRANS_SINE)
		_shake.tween_property(_sprite, "position:x", 0.0, per).set_trans(Tween.TRANS_SINE)
		_shake.tween_interval(per * 6.0)


func is_shaking() -> bool:
	return _shake != null and _shake.is_valid()


func _exit_tree() -> void:
	if is_occupied():
		exit()


func _draw() -> void:
	var r: float = float(_def.get("shadow", 0.0))
	if r <= 0.0:
		return
	draw_set_transform(Vector2(r * 0.35, 3.0), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, r, SHADOW_COLOR)
	draw_circle(Vector2.ZERO, r * 0.7, Color(SHADOW_COLOR, SHADOW_COLOR.a * 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Œil barré (statique, dessiné une fois).
func _draw_eye() -> void:
	var bg := Color(0.07, 0.1, 0.18, 0.92)
	_eye.draw_circle(Vector2.ZERO, 16.0, bg)
	_eye.draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color(0.85, 0.88, 0.95, 0.85), 1.5, true)
	var w := Color(0.95, 0.96, 1.0)
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		var x := lerpf(-10.0, 10.0, t)
		var y := sin(t * PI) * 6.5
		top.append(Vector2(x, -y))
		bot.append(Vector2(x, y))
	_eye.draw_polyline(top, w, 2.2, true)
	_eye.draw_polyline(bot, w, 2.2, true)
	_eye.draw_circle(Vector2.ZERO, 3.2, w)
	_eye.draw_line(Vector2(-10, 9), Vector2(10, -9), bg, 6.0, true)
	_eye.draw_line(Vector2(-10, 9), Vector2(10, -9), Color(1.0, 0.45, 0.4), 2.6, true)


func _play(sfx: StringName) -> void:
	if not is_inside_tree():
		return
	var am := get_tree().root.get_node_or_null(^"AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, global_position)
