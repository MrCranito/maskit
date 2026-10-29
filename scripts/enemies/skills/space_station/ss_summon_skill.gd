extends EnemySkill
## Invocation (station) : `ss_drone_launch` (gardien, Architecte : lance des drones d'attaque) et
## `ss_brood_summon` (alien : fait éclore des petits). Anneaux de pose au sol pendant le
## télégraphe, puis `count` ennemis `kinds` apparaissent autour de l'invocateur, déjà alertés.
## Au plus `max_total` invocations vivantes par invocateur.

var _spawned: Array[Enemy] = []
var _points: Array[Vector2] = []
var _done: bool = false


func defaults() -> Dictionary:
	return {"cooldown": 16.0, "initial_cooldown": 3.0, "windup": 0.8, "need_los": false, "count": 2,
		"max_total": 4, "kinds": ["ss_spectre"], "dist": 70.0, "hp_below": 1.01}


func alive_count() -> int:
	for i: int in range(_spawned.size() - 1, -1, -1):
		if not is_instance_valid(_spawned[i]) or not _spawned[i].is_alive():
			_spawned.remove_at(i)
	return _spawned.size()


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return alive_count() + int(f("count")) <= int(f("max_total"))


func start() -> void:
	e.stop()
	_done = false
	_points.clear()
	var n := maxi(int(f("count")), 1)
	var base := (player_pos() - e.global_position).normalized()
	if base.length_squared() < 0.01:
		base = Vector2.DOWN
	for i: int in n:
		var ang := (float(i) - 0.5 * float(n - 1)) * (TAU / float(maxi(n, 3)))
		var pt := e.global_position + base.rotated(ang) * f("dist")
		if not e.has_line_between(e.global_position, pt):
			pt = e.global_position + base * 20.0
		_points.append(pt)
		fx(&"deploy", pt, Vector2.ZERO, 22.0, windup())
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._play_sfx(&"enemy_alert")


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var kinds: Array = p.get("kinds", ["ss_spectre"])
		for i: int in _points.size():
			var r := e.spawn_reinforcement(StringName(str(kinds[i % kinds.size()])), _points[i])
			if r != null:
				_spawned.append(r)
	return t >= windup() + 0.15
