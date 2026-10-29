extends EnemySkill
## Surcharge (l'Omnistore, phase finale) : les écrans saturent (long télégraphe : anneau rouge à la
## portée maximale), puis `pulses` ondes de choc de plus en plus larges (dégâts + renversement) ;
## attaque de zone massive à fuir ou à franchir au bon moment.

var _pulses: int = 0


func defaults() -> Dictionary:
	return {"cooldown": 11.0, "initial_cooldown": 2.0, "windup": 1.3, "need_los": false, "max_range": 720.0,
		"pulses": 3, "interval": 0.5, "radius_start": 220.0, "radius_step": 120.0, "duration": 0.7,
		"damage": 20.0, "knock_time": 0.5, "band": 32.0, "shout": "SURCHARGE !"}


func start() -> void:
	e.stop()
	_pulses = 0
	e._visual_call(&"play_attack_windup", [windup(), false])
	var rmax := f("radius_start") + f("radius_step") * (f("pulses") - 1.0)
	fx(&"ring", e.global_position, Vector2.ZERO, rmax, windup())
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	e.stop()
	var n := int(f("pulses"))
	while _pulses < n and t >= windup() + f("interval") * float(_pulses):
		var r := f("radius_start") + f("radius_step") * float(_pulses)
		_pulses += 1
		e._visual_call(&"play_ground_slam", [r * 0.4])
		e.spawn_hazard(&"shockwave", e.global_position, {"radius": r, "duration": f("duration"),
			"damage": f("damage") * e.diff_damage_mult, "knock_time": f("knock_time"), "band": f("band")})
		e._play_sfx(&"golem_stomp")
		e._fx_dust(e.global_position, 4)
	return _pulses >= n and t >= windup() + f("interval") * float(n - 1) + f("duration")
