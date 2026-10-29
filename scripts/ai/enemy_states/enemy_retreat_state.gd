extends EnemyState
## Repli (PV sous retreat_hp_ratio, une seule fois) : cri, court vers un couvert éloigné du
## joueur (ou s'en éloigne), puis reprend le combat. Tire s'il en a l'occasion en reculant
## (tireurs), sans s'arrêter.

var _left: float = 0.0
var _target: Vector2 = Vector2.ZERO


func _init() -> void:
	name = "Retreat"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	e.has_retreated = true
	_left = Balance.get_float("enemy_tactics", "retreat_time", 2.2)
	e.shout(&"retreat", true)
	var p := e.get_player()
	var threat := p.global_position if p != null else e.last_seen_position
	var far := Balance.get_float("enemy_tactics", "retreat_distance", 300.0)
	_target = EnemyTactics.retreat_point(e.global_position, threat, far)
	if e.seek_cover(threat, e.global_position.distance_to(threat) + 80.0, e.global_position.distance_to(threat) + far * 1.5):
		_target = e.cover_position


func physics_update(delta: float) -> void:
	var e := get_enemy()
	_left -= delta
	var p := e.get_player()
	if p == null:
		request_transition(Enemy.STATE_RETURN)
		return
	if _left <= 0.0 or e.is_at(_target, e.arrive_distance * 2.0):
		request_transition(Enemy.STATE_CHASE)
		return
	e.move_toward_position(_target, e.run_speed() * 1.05)
	if e.data.is_ranged() and e.can_see_player and e.attack_ready() and e.data.get_pattern() != &"lob" \
			and e.global_position.distance_to(p.global_position) <= e.data.attack_range:
		e._start_cooldown()
		e.fire_volley(p.global_position - e.global_position)
