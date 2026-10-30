extends EnemySkill
## Réveil des morts (Pharaon éternel) : lève son sceptre (télégraphe : cercles de sable aux points
## d'apparition), puis `count` morts-vivants `kinds` sortent du sable autour de lui, déjà alertés.
## Au plus `max_total` invoqués vivants. Valeurs : [bestiary_egypt] eg_raise_dead_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")
const FX := preload("res://scripts/enemies/skills/egypt/eg_fx.gd")

var spawned: Array[Enemy] = []
var _points: Array[Vector2] = []
var _done: bool = false


func defaults() -> Dictionary:
	return Bal.defaults("eg_raise_dead", {"cooldown": 18.0, "initial_cooldown": 2.0, "windup": 1.1, "need_los": false,
		"count": 3, "max_total": 6, "kinds": ["eg_mummy", "eg_skeleton", "eg_archer"], "dist": 150.0,
		"shout": "RELEVEZ-VOUS !"})


func alive_count() -> int:
	for i: int in range(spawned.size() - 1, -1, -1):
		if not is_instance_valid(spawned[i]) or not spawned[i].is_alive():
			spawned.remove_at(i)
	return spawned.size()


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return alive_count() + int(f("count")) <= int(f("max_total"))


func start() -> void:
	e.stop()
	_done = false
	_points.clear()
	var n := maxi(int(f("count")), 1)
	var base := (player_pos() - e.global_position).normalized()
	if base.length_squared() < 0.01:
		base = Vector2.DOWN
	for i: int in n:
		var ang := (float(i) - 0.5 * float(n - 1)) * (TAU / float(maxi(n, 3))) * 0.8
		var pt := e.global_position + base.rotated(ang) * f("dist")
		if not e.has_line_between(e.global_position, pt):
			pt = e.global_position + base.rotated(ang) * 40.0
		_points.append(pt)
		fx(&"ring", pt, Vector2.ZERO, 30.0, windup())
		if e.get_parent() != null:
			FX.spawn(e.get_parent(), &"rise", pt, 28.0, windup() + 0.3)
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._play_sfx(&"enemy_alert")


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var kinds: Array = p.get("kinds", ["eg_skeleton"])
		for i: int in _points.size():
			if alive_count() >= int(f("max_total")):
				break
			var r := e.spawn_reinforcement(StringName(str(kinds[i % kinds.size()])), _points[i])
			if r != null:
				spawned.append(r)
	return t >= windup() + 0.2
