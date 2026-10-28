extends EnemyState
## Retour : rentre au point d'apparition en régénérant progressivement ses PV, puis Patrol.
## Après une poursuite perdue, la jauge redescend à lost_awareness (re-repérage plus rapide).
## Le joueur perçu en chemin fait remonter la jauge (Investigate / Alert via Enemy).

var _timeout_left: float = 0.0


func _init() -> void:
	name = "Return"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	_timeout_left = e.return_timeout
	if e.awareness > e.lost_awareness:
		e.set_awareness(e.lost_awareness)


func physics_update(delta: float) -> void:
	var e := get_enemy()
	if e.hp < e.max_hp:
		e.heal(e.max_hp * e.return_regen_ratio_per_sec * delta)
	_timeout_left -= delta
	if e.is_at(e.spawn_position, e.arrive_distance * 2.0) or _timeout_left <= 0.0:
		e.stop()
		request_transition(Enemy.STATE_PATROL)
		return
	e.move_toward_position(e.spawn_position, e.data.move_speed * e.return_speed_ratio)
