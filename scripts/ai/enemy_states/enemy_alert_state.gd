extends EnemyState
## Alerte (« repéré », jauge à 1) : « ! » au-dessus de la tête, courte pause (alert_duration)
## tournée vers la cible, prévient les voisins (si msg.propagate : ils reçoivent une forte
## hausse de jauge, cf. Enemy.receive_alert), puis Chase.

var _left: float = 0.0


func _init() -> void:
	name = "Alert"


func enter(msg: Dictionary = {}) -> void:
	var e := get_enemy()
	e.stop()
	e.set_awareness(1.0)
	var target_pos: Vector2 = msg.get("target_pos", e.last_seen_position)
	e.last_seen_position = target_pos
	e.has_last_seen = true
	e.face_position(target_pos)
	e._visual_call(&"play_alert")
	_left = e.data.alert_duration
	if bool(msg.get("propagate", true)):
		e.alert_neighbors(target_pos)


func physics_update(delta: float) -> void:
	var e := get_enemy()
	e.stop()
	if e.can_see_player:
		e.face_position(e.last_seen_position)
	_left -= delta
	if _left <= 0.0:
		request_transition(Enemy.STATE_CHASE)
