extends EnemySkill
## Shérif Sable-Fou : tornade de sable. Lève les bras (télégraphe : anneau au sol) puis fait
## naître `count` tornades autour du joueur (sand_tornado.gd) qui dérivent vers lui : vision
## réduite, ralentissement, petits dégâts. Au plus `max_alive` tornades à la fois.
## Valeurs : [bestiary_far_west] sand_tornado_*.

const BAL := "bestiary_far_west"
const TORNADO := preload("res://scripts/enemies/skills/far_west/sand_tornado.gd")

var _done: bool = false
var spawned: Array[Node2D] = []


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "sand_tornado_cooldown", 14.0),
		"initial_cooldown": Balance.get_float(BAL, "sand_tornado_initial_cooldown", 2.0),
		"windup": Balance.get_float(BAL, "sand_tornado_windup", 0.9),
		"count": Balance.get_float(BAL, "sand_tornado_count", 1.0),
		"max_alive": Balance.get_float(BAL, "sand_tornado_max_alive", 2.0),
		"offset": Balance.get_float(BAL, "sand_tornado_offset", 140.0),
		"radius": Balance.get_float(BAL, "sand_tornado_radius", 130.0),
		"duration": Balance.get_float(BAL, "sand_tornado_duration", 7.0),
		"drift_speed": Balance.get_float(BAL, "sand_tornado_drift_speed", 70.0),
		"slow": Balance.get_float(BAL, "sand_tornado_slow", 0.45),
		"dps": Balance.get_float(BAL, "sand_tornado_dps", 4.0),
		"opacity": Balance.get_float(BAL, "sand_tornado_opacity", 0.82),
		"need_los": false, "priority": 2.2,
	}


func _alive() -> int:
	for i: int in range(spawned.size() - 1, -1, -1):
		if not is_instance_valid(spawned[i]):
			spawned.remove_at(i)
	return spawned.size()


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return _alive() < int(f("max_alive"))


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", player_pos(), Vector2.ZERO, f("radius"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var parent: Node = e.get_parent() if e.get_parent() != null else e.get_tree().current_scene
		var center := player_pos()
		var n := int(f("count"))
		for i: int in n:
			if _alive() >= int(f("max_alive")):
				break
			var ang := TAU * float(i) / float(maxi(n, 1)) + randf() * 0.6
			var pos := center + Vector2.from_angle(ang) * f("offset") * (0.0 if n == 1 and i == 0 and randf() < 0.3 else 1.0)
			spawned.append(TORNADO.spawn(parent, pos, p, e))
	return t >= windup() + 0.2
