extends EnemySkill
## Bandelette étouffante (Momie étouffée) : déroule une bandelette vers le joueur (télégraphe :
## couloir au sol), le premier joueur dans le couloir est happé — dégâts, tiré vers la momie
## (renversement court dirigé vers elle) puis entravé (`root`). Valeurs : [bestiary_egypt] eg_bandage_lash_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _done: bool = false
## Joueur happé au dernier lancer (tests).
var caught: Node2D = null


func defaults() -> Dictionary:
	return Bal.defaults("eg_bandage_lash", {"cooldown": 9.0, "initial_cooldown": 3.0, "windup": 0.7, "min_range": 90.0,
		"max_range": 340.0, "width": 44.0, "damage": 9.0, "pull_time": 0.35, "pull_strength": 0.9,
		"root_time": 0.9})


func start() -> void:
	e.stop()
	_done = false
	caught = null
	_from = e.global_position
	var target := e.predict_player_position(windup() * 0.3)
	var d := target - _from
	if d.length_squared() < 1.0:
		d = e.facing
	_to = _from + d.normalized() * f("max_range")
	e.face(d)
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"lane", _from, _to, f("width"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		_lash()
	e.stop()
	return t >= windup() + 0.35


func _lash() -> void:
	e._visual_call(&"play_strike", [_to - _from, false])
	e._play_sfx(&"blade_swing")
	if not e.is_inside_tree():
		return
	var buf: Array[Node2D] = []
	EnemySkills.player_targets(e.get_tree(), buf)
	var best: Node2D = null
	var best_d := INF
	for pl: Node2D in buf:
		var q := Geometry2D.get_closest_point_to_segment(pl.global_position, _from, _to)
		if q.distance_to(pl.global_position) > f("width") * 0.5 + 16.0:
			continue
		var dd := _from.distance_to(pl.global_position)
		if dd < best_d:
			best_d = dd
			best = pl
	if best == null:
		return
	caught = best
	var dmg := f("damage") * e.diff_damage_mult * e.phase_damage_mult
	# Renversement « depuis » un point derrière le joueur : il est poussé vers la momie.
	var away := (best.global_position - _from).normalized()
	EnemySkills.hit_player(best, dmg, e, &"knockdown", f("pull_time"), f("pull_strength"), best.global_position + away * 20.0)
	EnemySkills.hit_player(best, 0.0, e, &"root", f("root_time"))
