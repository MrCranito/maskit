extends EnemyState
## Mort : animation de mort du visuel, puis libération sur death_finished
## (ou après death_free_fallback secondes si le signal n'arrive jamais).

var _fallback_left: float = 0.0


func _init() -> void:
	name = "Dead"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	e.stop()
	_fallback_left = e.death_free_fallback
	e._visual_call(&"play_death")


func physics_update(delta: float) -> void:
	_fallback_left -= delta
	if _fallback_left <= 0.0:
		var e := get_enemy()
		if not e.is_queued_for_deletion():
			e.queue_free()
