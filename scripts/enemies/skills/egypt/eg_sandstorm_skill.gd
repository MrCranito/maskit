extends EnemySkill
## Tempête de sable (Pharaon éternel) : lève les bras (télégraphe : anneau au sol), fait naître
## `count` tourbillons (eg_sandstorm.gd) autour du joueur qui dérivent vers lui. Au plus
## `max_alive` à la fois. Valeurs : [bestiary_egypt] eg_sandstorm_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")
const STORM := preload("res://scripts/enemies/skills/egypt/eg_sandstorm.gd")

var spawned: Array[Node2D] = []
var _done: bool = false


func defaults() -> Dictionary:
	return Bal.defaults("eg_sandstorm", {"cooldown": 15.0, "initial_cooldown": 3.0, "windup": 0.9, "need_los": false,
		"count": 2, "max_alive": 3, "offset": 200.0, "radius": 150.0, "duration": 8.0, "drift_speed": 60.0,
		"slow": 0.4, "dps": 5.0, "blind": 0.4, "opacity": 0.8, "priority": 1.6})


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
	e._visual_call(&"play_shout", ["TEMPÊTE !"])
	fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var parent: Node = e.get_parent() if e.get_parent() != null else e.get_tree().current_scene
		var center := player_pos()
		var n := int(f("count"))
		var rot := randf() * TAU
		for i: int in n:
			if alive() >= int(f("max_alive")):
				break
			var pos := center + Vector2.from_angle(rot + TAU * float(i) / float(maxi(n, 1))) * f("offset")
			var prm := p.duplicate()
			prm["dps"] = f("dps") * e.diff_damage_mult * e.phase_damage_mult
			spawned.append(STORM.spawn(parent, pos, prm, e))
	return t >= windup() + 0.2
