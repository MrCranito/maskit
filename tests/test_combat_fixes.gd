extends GutTest
## Correctifs du test de jeu : trajectoire des balles au niveau du sol et aide à la visée.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _player: Node2D
var _saved_player = null


func before_each() -> void:
	_saved_player = GameState.player if is_instance_valid(GameState.player) else null
	_player = PLAYER_SCENE.instantiate()
	add_child_autofree(_player)
	_player.global_position = Vector2(100, 100)


func after_each() -> void:
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null


func _add_enemy(pos: Vector2) -> Node2D:
	var e := Node2D.new()
	e.add_to_group(&"enemies")
	add_child_autofree(e)
	e.global_position = pos
	return e


func test_projectile_travels_at_ground_level() -> void:
	await wait_physics_frames(2)
	_player.call("fire", Vector2.RIGHT)
	var found := false
	# Le pool range ses projectiles hors du joueur : on retrouve le projectile actif.
	for n: Node in get_tree().root.find_children("*", "Projectile", true, false):
		if n.get("active"):
			found = true
			assert_almost_eq((n as Node2D).global_position.y, _player.global_position.y, 0.5,
				"la trajectoire est au niveau des pieds (hitbox)")
			assert_gt(float(n.get("visual_height")), 0.0, "le dessin est surélevé à la hauteur du canon")
	assert_true(found, "un projectile a été tiré")


func test_aim_assist_snaps_to_enemy_in_cone() -> void:
	var e := _add_enemy(_player.global_position + Vector2(300, 40))  # ~7,6° sous l'axe
	var dir: Vector2 = _player.call("apply_aim_assist", Vector2.RIGHT)
	var expected := (e.global_position - _player.global_position).normalized()
	assert_almost_eq(dir.angle(), expected.angle(), 0.001)


func test_aim_assist_ignores_enemy_outside_cone() -> void:
	_add_enemy(_player.global_position + Vector2(200, 200))  # 45°
	var dir: Vector2 = _player.call("apply_aim_assist", Vector2.RIGHT)
	assert_eq(dir, Vector2.RIGHT)


func test_aim_assist_ignores_hidden_enemy() -> void:
	var e := _add_enemy(_player.global_position + Vector2(300, 0))
	e.visible = false  # caché par le brouillard
	var dir: Vector2 = _player.call("apply_aim_assist", Vector2(1, 0.1).normalized())
	assert_almost_eq(dir.angle(), Vector2(1, 0.1).angle(), 0.001)
