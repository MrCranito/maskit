extends EnemyState
## Patrouille : erre autour du point d'apparition (patrol_radius) avec des pauses aléatoires.
## Bascule en Alert dès que le joueur est perçu (zone + cône + ligne de vue).

var _target: Vector2 = Vector2.ZERO
var _pause_left: float = 0.0
var _walk_left: float = 0.0


func _init() -> void:
	name = "Patrol"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	e.stop()
	_start_pause()


func physics_update(delta: float) -> void:
	var e := get_enemy()
	if e.can_see_player:
		request_transition(Enemy.STATE_ALERT, {"target_pos": e.last_seen_position, "propagate": true})
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		e.stop()
		if _pause_left <= 0.0:
			_pick_target()
		return
	_walk_left -= delta
	if e.is_at(_target) or _walk_left <= 0.0:
		e.stop()
		_start_pause()
		return
	e.move_toward_position(_target, e.data.move_speed * Balance.get_float("enemy_ai", "patrol_speed_ratio", 0.4))


func _start_pause() -> void:
	_pause_left = randf_range(
		Balance.get_float("enemy_ai", "patrol_pause_min", 0.8),
		Balance.get_float("enemy_ai", "patrol_pause_max", 2.2))


func _pick_target() -> void:
	var e := get_enemy()
	var r := e.data.patrol_radius * sqrt(randf())
	_target = e.spawn_position + Vector2.from_angle(randf() * TAU) * r
	# Garde-fou : abandonne une destination inatteignable (mur) après ce délai.
	_walk_left = Balance.get_float("enemy_ai", "patrol_walk_timeout", 3.0)
