extends EnemySkill
## Tir de zone (gardien de station, Architecte) : `count` cercles de danger s'allument autour du
## joueur (le premier sur sa position anticipée) pendant le télégraphe, puis les obus plasma
## tombent l'un après l'autre (`interval`) : explosion de rayon `radius` à chaque cercle.

var _targets: Array[Vector2] = []
var _fired: int = 0
var _next: float = 0.0


func defaults() -> Dictionary:
	return {"cooldown": 9.0, "windup": 1.0, "min_range": 120.0, "max_range": 640.0, "count": 4, "spread": 120.0,
		"radius": 80.0, "damage": 16.0, "interval": 0.18, "lead": 0.4}


func start() -> void:
	e.stop()
	_fired = 0
	_next = 0.0
	_targets.clear()
	var center := e.predict_player_position(f("lead"))
	var n := maxi(int(f("count")), 1)
	for i: int in n:
		var pt := center
		if i > 0:
			var ang := TAU * float(i) / float(n - 1) + randf_range(-0.4, 0.4)
			pt = center + Vector2.from_angle(ang) * f("spread") * randf_range(0.55, 1.0)
		_targets.append(pt)
		fx(&"ring", pt, Vector2.ZERO, f("radius"), windup() + f("interval") * float(i))
	e.face_position(center)
	e._visual_call(&"play_attack_windup", [windup(), false])


func step(dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	_next -= dt
	while _fired < _targets.size() and _next <= 0.0:
		var pt := _targets[_fired]
		if _fired == 0:
			e._visual_call(&"play_strike", [pt - e.global_position, true, true])
		e.spawn_hazard(&"blast", pt, {"radius": f("radius"), "damage": f("damage") * e.diff_damage_mult * e.phase_damage_mult})
		e._play_sfx(&"explosion")
		_fired += 1
		_next += f("interval")
	return _fired >= _targets.size() and t >= windup() + f("interval") * float(_targets.size()) + 0.1


func cleanup() -> void:
	_targets.clear()


## Nombre d'obus tirés (tests).
func fired() -> int:
	return _fired
