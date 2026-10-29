extends EnemySkill
## Ondes de panique (l'Omnistore) : cri des écrans (anneau rouge pendant le télégraphe), puis
## `waves` ondes qui s'étendent jusqu'à `radius` : petits dégâts, et les joueurs traversés sont
## désorientés (statut « blind » : visée perturbée) et ralentis (statut « slow », appliqué si le
## joueur le gère). Esquive : être hors de portée ou traverser l'onde au bon moment.

var _wave_t: Array[float] = []
var _hit: Array[Dictionary] = []
var _spawned: int = 0


func defaults() -> Dictionary:
	return {"cooldown": 9.0, "initial_cooldown": 3.0, "windup": 1.0, "need_los": false, "max_range": 620.0,
		"radius": 440.0, "duration": 0.9, "damage": 7.0, "band": 34.0, "waves": 2, "gap": 0.55,
		"blind_time": 1.6, "blind_strength": 0.8, "slow_time": 2.4, "slow_strength": 0.5, "shout": ""}


func start() -> void:
	e.stop()
	_wave_t.clear()
	_hit.clear()
	_spawned = 0
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), windup())
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	e.stop()
	var n := int(f("waves"))
	while _spawned < n and t >= windup() + f("gap") * float(_spawned):
		_wave_t.append(t)
		_hit.append({})
		_spawned += 1
		e._visual_call(&"play_ground_slam", [f("radius") * 0.3])
		e.spawn_hazard(&"shockwave", e.global_position, {"radius": f("radius"), "duration": f("duration"),
			"damage": f("damage") * e.diff_damage_mult, "knock_time": 0.0, "band": f("band")})
		e._play_sfx(&"golem_stomp")
	_apply_status()
	return _spawned >= n and t >= _wave_t[_wave_t.size() - 1] + f("duration")


## Désorientation des joueurs que l'onde traverse (même rayon que le danger « shockwave »).
func _apply_status() -> void:
	if not e.is_inside_tree():
		return
	var targets: Array[Node2D] = []
	EnemySkills.player_targets(e.get_tree(), targets)
	for w: int in _wave_t.size():
		var age := t - _wave_t[w]
		if age > f("duration"):
			continue
		var r := f("radius") * clampf(age / maxf(f("duration"), 0.05), 0.0, 1.0)
		for pl: Node2D in targets:
			var id := pl.get_instance_id()
			if _hit[w].has(id):
				continue
			if absf(pl.global_position.distance_to(e.global_position) - r) <= f("band"):
				_hit[w][id] = true
				EnemySkills.hit_player(pl, 0.0, e, &"blind", f("blind_time"), f("blind_strength"))
				EnemySkills.hit_player(pl, 0.0, e, &"slow", f("slow_time"), f("slow_strength"))
