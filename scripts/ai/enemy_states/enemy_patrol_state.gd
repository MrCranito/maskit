extends EnemyState
## Patrouille : enchaîne des points d'intérêt de sa salle / rue (cases près des obstacles,
## décors, portes — EnemyTactics.patrol_points), avec des pauses où il regarde autour de lui.
## Sans carte (tests, salle d'essai) : points aléatoires dans patrol_radius. patrol_radius = 0 :
## reste sur place. Ne réagit pas directement à la vue : c'est la jauge de reconnaissance
## (Enemy.awareness) qui fait passer en Investigate puis en Alert.

var _points: PackedVector2Array = PackedVector2Array()
var _index: int = 0
var _target: Vector2 = Vector2.ZERO
var _pause_left: float = 0.0
var _walk_left: float = 0.0
var _look_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "Patrol"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	e.stop()
	if _points.is_empty():
		_build_points()
	_start_pause()


func _build_points() -> void:
	var e := get_enemy()
	_rng.seed = hash([e.spawn_position.x, e.spawn_position.y, String(e.data.kind)])
	var n := int(Balance.get_value("enemy_tactics", "patrol_points", 4))
	var r := e.data.patrol_radius * Balance.get_float("enemy_tactics", "patrol_radius_mult", 1.6)
	_points = EnemyTactics.patrol_points(e.spawn_position, r, n, _rng, EnemyTactics.current_map())
	_index = _rng.randi_range(0, maxi(_points.size() - 1, 0))


func physics_update(delta: float) -> void:
	var e := get_enemy()
	if _pause_left > 0.0:
		_pause_left -= delta
		e.stop()
		_look_left -= delta
		if _look_left <= 0.0 and e.data.patrol_radius > 0.0:
			_look_left = _rng.randf_range(0.7, 1.4)
			e.face(e.facing.rotated(_rng.randf_range(-1.2, 1.2)))
		if _pause_left <= 0.0:
			_pick_target()
		return
	_walk_left -= delta
	if e.is_at(_target, e.arrive_distance * 1.5) or _walk_left <= 0.0:
		e.stop()
		_start_pause()
		return
	e.move_toward_position(_target, e.data.move_speed * e.patrol_speed_ratio)


func _start_pause() -> void:
	var e := get_enemy()
	_pause_left = _rng.randf_range(e.patrol_pause_min, e.patrol_pause_max)
	_look_left = _rng.randf_range(0.3, 0.8)


func _pick_target() -> void:
	var e := get_enemy()
	if _points.is_empty() or e.data.patrol_radius <= 0.0:
		_target = e.spawn_position
		_walk_left = 0.0
		_pause_left = e.patrol_pause_max
		return
	_index = (_index + 1) % _points.size()
	_target = _points[_index]
	var d := e.global_position.distance_to(_target)
	# Garde-fou : abandonne une destination inatteignable (mur) après ce délai.
	_walk_left = maxf(e.patrol_walk_timeout, d / maxf(e.data.move_speed * e.patrol_speed_ratio, 1.0) * 1.6)
