extends EnemySkill
## Onde de choc (colosse du réacteur, gros boss) : anneau de danger au sol pendant le
## télégraphe, puis une onde qui s'étend jusqu'à `radius` : dégâts + renversement au passage.


func defaults() -> Dictionary:
	return {"cooldown": 9.0, "windup": 1.0, "max_range": 240.0, "need_los": false, "radius": 260.0,
		"duration": 0.6, "damage": 18.0, "knock_time": 0.6, "band": 30.0}


func start() -> void:
	e.stop()
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	e._visual_call(&"play_ground_slam", [f("radius") * 0.5])
	e.spawn_hazard(&"shockwave", e.global_position, {"radius": f("radius"), "duration": f("duration"),
		"damage": f("damage") * e.diff_damage_mult, "knock_time": f("knock_time"), "band": f("band")})
	e._play_sfx(&"golem_stomp")
	return true
