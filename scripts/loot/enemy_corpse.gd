class_name EnemyCorpse
extends LootContainer
## Cadavre d'ennemi persistant et fouillable (« Pistolero abattu ») : la dernière image de
## l'animation de mort (planches 3D) ou le sprite basculé au sol (autres biomes), sous les
## personnages (z), sans collision ni traitement par image. Fouille = LootContainer (maintenir
## l'interaction ; contenu tiré à la mort par LootManager, table de l'archétype).
## Vidé : légèrement grisé, reste au sol. Conservé quand on change d'étage (LootManager).

const KIND := &"enemy_corpse"
## Sous les personnages et les murs triés en Y (10), au-dessus du sol et des décors au sol.
const Z_CORPSE := 6

var enemy_kind: StringName = &""
var display_name: String = "Cadavre"
## Pose : texture, offset, scale, rotation, centered, pivot, tint (cf. EnemyVisual.get_corpse_info).
var pose: Dictionary = {}
## Identifiant unique dans l'étage (persistance).
var corpse_id: int = 0


static func create_corpse(p_enemy_kind: StringName, pos: Vector2, p_pose: Dictionary, p_name: String) -> EnemyCorpse:
	var c := EnemyCorpse.new()
	c.kind = KIND
	c.enemy_kind = p_enemy_kind
	c.position = pos
	c.pose = p_pose
	c.display_name = p_name
	c.name = "Corpse_%s" % String(p_enemy_kind)
	return c


func _ready() -> void:
	_def = {"name": display_name, "reach": 14.0, "shadow": 0.0}
	z_as_relative = false
	z_index = Z_CORPSE
	search_time = float(LootDB.cfg().get_value("enemy_loot", "corpse_search_time", 0.9))
	search_hold = bool(LootDB.cfg().get_value(LootDB.SECTION, "search_hold", true))
	move_tolerance = LootDB.getf("search_move_tolerance", 10.0)
	_build()
	set_process(false)


func _build() -> void:
	var tex: Texture2D = pose.get("texture") as Texture2D
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.texture = tex
		_sprite.centered = bool(pose.get("centered", true))
		_sprite.offset = pose.get("offset", Vector2.ZERO)
		var pivot: Vector2 = pose.get("pivot", Vector2.ZERO)
		_sprite.position = pivot
		_sprite.scale = pose.get("scale", Vector2.ONE)
		_sprite.rotation = float(pose.get("rotation", 0.0))
		_sprite.modulate = pose.get("tint", Color.WHITE)
		add_child(_sprite)
	_ring = Node2D.new()
	_ring.name = "SearchRing"
	_ring.z_as_relative = false
	_ring.z_index = 60
	_ring.position = Vector2(0.0, -40.0)
	_ring.visible = false
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_refresh_visual()


func get_display_name() -> String:
	return display_name


func get_interact_reach() -> float:
	return 14.0


func get_visual_height() -> float:
	return 24.0


func _refresh_visual() -> void:
	if _sprite != null:
		var tint: Color = pose.get("tint", Color.WHITE)
		_sprite.modulate = tint * Color(0.72, 0.68, 0.72) if state == State.EMPTIED else tint
	var best := LootRoller.best_rarity(entries) if state == State.OPENED else -1
	if state == State.CLOSED and has_preset:
		best = LootRoller.best_rarity(preset_entries) if bool(LootDB.cfg().get_value("enemy_loot", "corpse_glow_before_search", false)) else -1
	_glow_color = LootDB.rarity_color(best) if best >= LootDB.geti("glow_min_rarity", 2) else Color(0, 0, 0, 0)
	queue_redraw()


## Ombre de contact (le corps est à plat) + lueur de rareté éventuelle. Dessin statique.
func _draw() -> void:
	draw_set_transform(Vector2(0.0, -2.0), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, 30.0, Color(0.06, 0.07, 0.18, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _glow_color.a > 0.0:
		draw_set_transform(Vector2(0.0, -4.0), 0.0, Vector2(1.0, 0.42))
		for k in 4:
			var f := 1.0 - k * 0.22
			draw_circle(Vector2.ZERO, 36.0 * f, Color(_glow_color, 0.08 + k * 0.04))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Enregistrement pour la persistance d'étage.
func to_record() -> Dictionary:
	return {
		"id": corpse_id, "enemy_kind": enemy_kind, "pos": position, "pose": pose, "name": display_name,
		"preset": preset_entries.duplicate(), "persist_key": persist_key,
	}


static func from_record(r: Dictionary) -> EnemyCorpse:
	var c := create_corpse(StringName(r.get("enemy_kind", &"")), r.get("pos", Vector2.ZERO), r.get("pose", {}),
		String(r.get("name", "Cadavre")))
	c.corpse_id = int(r.get("id", 0))
	c.has_preset = true
	var pre: Array = r.get("preset", [])
	for e: Dictionary in pre:
		c.preset_entries.append({"item": e["item"], "count": int(e["count"])})
	c.persist_key = String(r.get("persist_key", ""))
	return c
