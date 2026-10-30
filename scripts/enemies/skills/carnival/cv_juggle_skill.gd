extends EnemySkill
## Jonglage de torches (Le Roi du cirque) : jongle (télégraphe : un cercle rouge par point de
## chute, autour de la position prévue du joueur), puis lance `count` torches en cloche qui
## allument chacune un foyer (EnemyHazard « fire »). Valeurs : [bestiary_carnival] juggle_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")

var _targets: Array[Vector2] = []
var _thrown: int = 0


func defaults() -> Dictionary:
	return Bal.read("juggle", {"cooldown": 9.0, "initial_cooldown": 2.0, "windup": 0.8, "min_range": 100.0,
		"max_range": 620.0, "count": 3.0, "spread": 110.0, "radius": 70.0, "flight": 0.6, "interval": 0.12,
		"duration": 4.0, "dps": 11.0, "lead": 0.5, "priority": 1.4})


func start() -> void:
	e.stop()
	_thrown = 0
	_targets.clear()
	var c := e.predict_player_position((windup() + f("flight")) * f("lead"))
	var n := maxi(int(f("count")), 1)
	for k: int in n:
		var off := Vector2.ZERO if k == 0 else Vector2.from_angle(TAU * float(k) / float(n - 1) + randf() * 0.6) * f("spread")
		_targets.append(c + off)
		fx(&"ring", c + off, Vector2.ZERO, f("radius"), windup() + f("flight") + f("interval") * k)
	e.face(c - e.global_position)
	e._visual_call(&"play_attack_windup", [windup(), false])


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	e.stop()
	while _thrown < _targets.size() and t >= windup() + f("interval") * _thrown:
		var to := _targets[_thrown]
		e._visual_call(&"play_strike", [to - e.global_position, false])
		e.spawn_hazard(&"fire", to, {"from": e.global_position + Vector2(0, -8), "flight": f("flight"),
			"radius": f("radius"), "duration": f("duration"), "dps": f("dps") * e.diff_damage_mult})
		_thrown += 1
	return _thrown >= _targets.size() and t >= windup() + f("interval") * _targets.size() + 0.2
