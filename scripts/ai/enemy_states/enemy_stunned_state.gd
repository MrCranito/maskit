extends EnemyState
## Étourdi (gros dégâts d'un coup) : immobile, étoiles au-dessus de la tête, télégraphe annulé,
## puis reprend le combat.

var _left: float = 0.0


func _init() -> void:
	name = "Stunned"


func enter(msg: Dictionary = {}) -> void:
	var e := get_enemy()
	e.stop()
	_left = float(msg.get("time", e.data.stagger_time))
	e._visual_call(&"hide_telegraphs")
	e._visual_call(&"play_stun", [_left])
	e._fx_dust(e.global_position, 2)


func physics_update(delta: float) -> void:
	var e := get_enemy()
	e.stop()
	_left -= delta
	if _left <= 0.0:
		request_transition(Enemy.STATE_CHASE)
