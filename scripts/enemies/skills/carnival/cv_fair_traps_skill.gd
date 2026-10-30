extends EnemySkill
## Pièges de foire (Le Roi du cirque) : frappe le sol de son sceptre et sème `count` pièges à
## mâchoires (EnemyHazard « trap » : dégâts + « root ») sur un anneau autour du joueur. Au plus
## `max_alive` pièges de ce boss à la fois. Valeurs : [bestiary_carnival] fair_traps_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")

var traps: Array[Node2D] = []
var _done: bool = false


func defaults() -> Dictionary:
	return Bal.read("fair_traps", {"cooldown": 13.0, "initial_cooldown": 2.0, "windup": 0.7, "max_range": 700.0,
		"count": 5.0, "ring_min": 90.0, "ring_max": 220.0, "radius": 26.0, "damage": 14.0, "root_time": 1.4,
		"arm_delay": 0.6, "life": 18.0, "max_alive": 10.0, "need_los": false, "priority": 1.3})


func _alive() -> int:
	for i: int in range(traps.size() - 1, -1, -1):
		if not is_instance_valid(traps[i]):
			traps.remove_at(i)
	return traps.size()


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return _alive() + int(f("count")) <= int(f("max_alive"))


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", player_pos(), Vector2.ZERO, f("ring_max"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var c := player_pos()
		var n := maxi(int(f("count")), 1)
		e._visual_call(&"play_ground_slam", [60.0])
		for k: int in n:
			var a := TAU * float(k) / float(n) + randf() * 0.5
			var pt := c + Vector2.from_angle(a) * randf_range(f("ring_min"), f("ring_max"))
			var h := e.spawn_hazard(&"trap", pt, {"radius": f("radius"), "damage": f("damage") * e.diff_damage_mult,
				"root_time": f("root_time"), "arm_delay": f("arm_delay"), "life": f("life")})
			if h != null:
				traps.append(h)
	return t >= windup() + 0.25
