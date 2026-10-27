extends EnemyState
## Retour : rentre au point d'apparition en régénérant progressivement ses PV,
## puis Patrol. Le joueur aperçu en chemin relance l'alerte.

var _timeout_left: float = 0.0


func _init() -> void:
	name = "Return"


func enter(_msg: Dictionary = {}) -> void:
	_timeout_left = Balance.get_float("enemy_ai", "return_timeout", 8.0)


func physics_update(delta: float) -> void:
	var e := get_enemy()
	if e.can_see_player:
		request_transition(Enemy.STATE_ALERT, {"target_pos": e.last_seen_position, "propagate": true})
		return
	e.heal(e.max_hp * Balance.get_float("enemy_ai", "return_regen_ratio_per_sec", 0.25) * delta)
	_timeout_left -= delta
	if e.is_at(e.spawn_position, e.arrive_distance * 2.0) or _timeout_left <= 0.0:
		e.stop()
		request_transition(Enemy.STATE_PATROL)
		return
	e.move_toward_position(e.spawn_position, e.data.move_speed * Balance.get_float("enemy_ai", "return_speed_ratio", 0.7))
