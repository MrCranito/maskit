extends EnemySkill
## Nova de givre (Élémentaire, Gardien des glaces, Titan) : l'ennemi s'immobilise, un anneau de
## danger se dessine (télégraphe), puis une onde de froid s'étend jusqu'à `radius` : dégâts au
## passage (danger « shockwave », renversement si `knock_time` > 0) et tous les joueurs dans le
## rayon sont ralentis (statut « slow »). `waves` > 1 : ondes successives tous les `gap` s.
## Valeurs : [bestiary_frozen] nova_*.

const BAL := "bestiary_frozen"

var _spawned: int = 0


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "nova_cooldown", 9.0),
		"initial_cooldown": Balance.get_float(BAL, "nova_initial_cooldown", 2.5),
		"windup": Balance.get_float(BAL, "nova_windup", 0.9),
		"max_range": Balance.get_float(BAL, "nova_max_range", 230.0),
		"radius": Balance.get_float(BAL, "nova_radius", 260.0),
		"duration": Balance.get_float(BAL, "nova_duration", 0.55),
		"damage": Balance.get_float(BAL, "nova_damage", 12.0),
		"knock_time": Balance.get_float(BAL, "nova_knock_time", 0.0),
		"slow": Balance.get_float(BAL, "nova_slow", 0.4),
		"slow_time": Balance.get_float(BAL, "nova_slow_time", 2.0),
		"waves": 1.0, "gap": 0.5, "band": 34.0, "need_los": false, "shout": "",
	}


func start() -> void:
	e.stop()
	_spawned = 0
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), windup())
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])


func step(_dt: float) -> bool:
	e.stop()
	if t < windup():
		return false
	var n := int(f("waves"))
	while _spawned < n and t >= windup() + f("gap") * float(_spawned):
		_spawned += 1
		_wave()
	return _spawned >= n and t >= windup() + f("gap") * float(n - 1) + 0.15


func _wave() -> void:
	e._visual_call(&"play_ground_slam", [f("radius") * 0.4])
	e.spawn_hazard(&"shockwave", e.global_position, {"radius": f("radius"), "duration": f("duration"),
		"damage": f("damage") * e.diff_damage_mult * e.phase_damage_mult, "knock_time": f("knock_time"),
		"band": f("band")})
	e._play_sfx(&"golem_stomp")
	if e.is_inside_tree():
		EnemySkills.hit_players_in_radius(e.get_tree(), e.global_position, f("radius"), 0.0, e, &"slow",
			f("slow_time"), f("slow"))
