extends EnemyState
## Enquête (suspicion, jauge ≥ suspicion_threshold) : « ? » au-dessus de la tête (jauge),
## courte pause tournée vers la source du stimulus, marche vers la dernière position
## vue/entendue, regarde autour, puis Return (vers la patrouille) si rien n'est trouvé.
## Un nouveau stimulus recale la destination. La jauge pleine fait passer en Alert
## (géré par Enemy._react_to_awareness).

enum Phase { SUSPICIOUS, WALK, LOOK }

var _phase: Phase = Phase.SUSPICIOUS
var _target: Vector2 = Vector2.ZERO
var _serial: int = -1
var _phase_left: float = 0.0
var _turn_left: float = 0.0
var _total_left: float = 0.0
var _look_dir: Vector2 = Vector2.DOWN


func _init() -> void:
	name = "Investigate"


func enter(msg: Dictionary = {}) -> void:
	var e := get_enemy()
	_total_left = e.investigate_timeout
	_retarget(msg.get("target_pos", e.stimulus_position))


func _retarget(pos: Vector2) -> void:
	var e := get_enemy()
	_target = pos
	_serial = e.stimulus_serial
	e.stop()
	e.face_position(pos)
	_phase = Phase.SUSPICIOUS
	_phase_left = e.suspicion_pause


func physics_update(delta: float) -> void:
	var e := get_enemy()
	_total_left -= delta
	if _total_left <= 0.0:
		_give_up()
		return
	if e.stimulus_serial != _serial:
		# Nouveau stimulus : on ne refait pas la pause si on marchait déjà vers la zone.
		var was_walking := _phase == Phase.WALK
		_retarget(e.stimulus_position)
		if was_walking:
			_phase = Phase.WALK
			_phase_left = e.investigate_walk_timeout
	match _phase:
		Phase.SUSPICIOUS:
			e.stop()
			if e.can_see_player or e.hears_player:
				e.face_position(e.stimulus_position)
			_phase_left -= delta
			if _phase_left <= 0.0:
				_phase = Phase.WALK
				_phase_left = e.investigate_walk_timeout
		Phase.WALK:
			_phase_left -= delta
			if e.is_at(_target, e.arrive_distance * 2.0) or _phase_left <= 0.0:
				e.stop()
				_phase = Phase.LOOK
				_phase_left = e.investigate_look_time
				_turn_left = 0.0
				_look_dir = e.facing
				return
			e.move_toward_position(_target, e.data.move_speed * e.investigate_speed_ratio)
		Phase.LOOK:
			e.stop()
			_turn_left -= delta
			if _turn_left <= 0.0:
				_turn_left = e.investigate_look_turn
				_look_dir = _look_dir.rotated(randf_range(0.6, 1.4) * (1.0 if randf() < 0.5 else -1.0))
				e.face(_look_dir)
			_phase_left -= delta
			if _phase_left <= 0.0:
				_give_up()


func _give_up() -> void:
	request_transition(Enemy.STATE_RETURN)
