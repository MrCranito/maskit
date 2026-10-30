extends EnemySkill
## Tempête de glace (Drone de froid, Titan de glace) : télégraphe (anneau au sol sous le joueur),
## puis `count` tempêtes (ice_storm.gd) naissent autour du joueur et dérivent vers lui : vision
## réduite, ralentissement (« slow »), petits dégâts. Au plus `max_alive` tempêtes à la fois pour
## ce lanceur. Valeurs : [bestiary_frozen] storm_*.

const BAL := "bestiary_frozen"
const STORM := preload("res://scripts/enemies/skills/frozen/ice_storm.gd")

var _done: bool = false
var spawned: Array[Node2D] = []


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "storm_cooldown", 14.0),
		"initial_cooldown": Balance.get_float(BAL, "storm_initial_cooldown", 3.0),
		"windup": Balance.get_float(BAL, "storm_windup", 0.9),
		"max_range": Balance.get_float(BAL, "storm_max_range", 620.0),
		"count": Balance.get_float(BAL, "storm_count", 1.0),
		"max_alive": Balance.get_float(BAL, "storm_max_alive", 1.0),
		"offset": Balance.get_float(BAL, "storm_offset", 130.0),
		"radius": Balance.get_float(BAL, "storm_radius", 110.0),
		"duration": Balance.get_float(BAL, "storm_duration", 6.0),
		"drift_speed": Balance.get_float(BAL, "storm_drift_speed", 55.0),
		"slow": Balance.get_float(BAL, "storm_slow", 0.35),
		"dps": Balance.get_float(BAL, "storm_dps", 3.0),
		"opacity": Balance.get_float(BAL, "storm_opacity", 0.75),
		"need_los": false, "priority": 1.8, "shout": "",
	}


func alive() -> int:
	for i: int in range(spawned.size() - 1, -1, -1):
		if not is_instance_valid(spawned[i]):
			spawned.remove_at(i)
	return spawned.size()


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return alive() < int(f("max_alive"))


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", player_pos(), Vector2.ZERO, f("radius"), windup())
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var parent: Node = e.get_parent() if e.get_parent() != null else e.get_tree().current_scene
		var center := player_pos()
		var n := int(f("count"))
		var params := p.duplicate()
		params["dps"] = f("dps") * e.diff_damage_mult * e.phase_damage_mult
		for i: int in n:
			if alive() >= int(f("max_alive")):
				break
			var ang := TAU * float(i) / float(maxi(n, 1)) + randf() * 0.6
			var off := 0.0 if n == 1 else f("offset")
			spawned.append(STORM.spawn(parent, center + Vector2.from_angle(ang) * off, params, e))
	return t >= windup() + 0.2
