extends EnemyState
## Recherche du joueur perdu : va à sa dernière position connue, puis fouille quelques points
## autour (search_points, rayon search_radius) en regardant à droite et à gauche, puis Return.
## La jauge reste haute (search_awareness) : le revoir relance vite l'alerte.

var _points: PackedVector2Array = PackedVector2Array()
var _index: int = 0
var _look_left: float = 0.0
var _walk_left: float = 0.0
var _total_left: float = 0.0
var _looking: bool = false
var _speed_ratio: float = 0.75
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "Search"


func enter(msg: Dictionary = {}) -> void:
	var e := get_enemy()
	var origin: Vector2 = msg.get("target_pos", e.last_seen_position)
	_rng.randomize()
	_points.clear()
	_points.append(origin)
	var n := int(Balance.get_value("enemy_tactics", "search_points", 3))
	var r := Balance.get_float("enemy_tactics", "search_radius", 180.0)
	for i: int in n:
		_points.append(origin + Vector2.from_angle(_rng.randf() * TAU) * r * _rng.randf_range(0.5, 1.0))
	_index = 0
	_looking = false
	_walk_left = 4.0
	_total_left = Balance.get_float("enemy_tactics", "search_time", 9.0)
	_speed_ratio = Balance.get_float("enemy_tactics", "search_speed_ratio", 0.75)
	e.set_awareness(maxf(e.awareness, Balance.get_float("enemy_tactics", "search_awareness", 0.75)))
	e.shout(&"lost")


func physics_update(delta: float) -> void:
	var e := get_enemy()
	_total_left -= delta
	if _total_left <= 0.0 or _index >= _points.size():
		request_transition(Enemy.STATE_RETURN)
		return
	if _looking:
		e.stop()
		_look_left -= delta
		if int(_look_left * 2.0) != int((_look_left + delta) * 2.0):
			e.face(e.facing.rotated(_rng.randf_range(0.8, 1.6) * (1.0 if _rng.randf() < 0.5 else -1.0)))
		if _look_left <= 0.0:
			_looking = false
			_index += 1
			_walk_left = 4.0
		return
	_walk_left -= delta
	var target := _points[_index]
	if e.is_at(target, e.arrive_distance * 2.5) or _walk_left <= 0.0:
		_looking = true
		_look_left = Balance.get_float("enemy_tactics", "search_look_time", 1.2)
		return
	e.move_toward_position(target, e.data.move_speed * _speed_ratio)
