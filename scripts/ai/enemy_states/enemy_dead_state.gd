extends EnemyState
## Mort : animation de chute du visuel ; à sa fin (death_finished), le cadavre persistant
## remplace l'ennemi (Enemy.finalize_death → LootManager.place_corpse). Délai de secours
## death_free_fallback si le signal n'arrive jamais.

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
		get_enemy().finalize_death()
