extends EnemySkill
## Overload (L'Architecte) : surcharge du réacteur interne. Long télégraphe (anneau rouge qui se
## remplit, l'Architecte immobile et vulnérable), puis explosion d'énergie : dégâts dégressifs dans
## `radius` + onde de choc qui renverse jusqu'à `wave_radius`. Lancée en entrant en phase 3 et
## ensuite périodiquement.

var _done: bool = false


func defaults() -> Dictionary:
	return {"cooldown": 16.0, "windup": 1.8, "need_los": false, "max_range": 9999.0, "radius": 230.0,
		"damage": 40.0, "wave_radius": 420.0, "wave_damage": 12.0, "wave_duration": 0.7, "knock_time": 0.8}


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), windup())
	fx(&"beep", e.global_position, Vector2.ZERO, f("radius") * 0.5, windup())
	e._play_sfx(&"danger_jingle")


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var dmg := e.diff_damage_mult * e.phase_damage_mult
		e.spawn_hazard(&"blast", e.global_position, {"radius": f("radius"), "damage": f("damage") * dmg})
		e.spawn_hazard(&"shockwave", e.global_position, {"radius": f("wave_radius"), "duration": f("wave_duration"),
			"damage": f("wave_damage") * dmg, "knock_time": f("knock_time"), "band": 34.0})
		e._visual_call(&"play_ground_slam", [f("radius")])
		e._play_sfx(&"explosion")
	return t >= windup() + 0.3
