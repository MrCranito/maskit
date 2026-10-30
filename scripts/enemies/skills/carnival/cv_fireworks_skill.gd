extends EnemySkill
## Grand final (Le Roi du cirque, phase 3) : « que la fête ne s'arrête jamais ». Lève son sceptre
## et tire `volleys` salves de `count` feux d'artifice : chaque fusée marque son point de chute
## (cercle rouge pendant `delay` s) puis explose (EnemyHazard « blast »). La première fusée de
## chaque salve vise le joueur, les autres l'entourent. Valeurs : [bestiary_carnival] fireworks_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")

## [position, instant d'explosion]
var _pending: Array = []
var _volley: int = 0
var blasts: int = 0


func defaults() -> Dictionary:
	return Bal.read("fireworks", {"cooldown": 11.0, "initial_cooldown": 1.0, "windup": 0.9, "max_range": 900.0,
		"volleys": 3.0, "count": 5.0, "gap": 0.7, "delay": 0.9, "spread": 200.0, "radius": 80.0, "damage": 24.0,
		"need_los": false, "priority": 2.2})


func start() -> void:
	e.stop()
	_pending.clear()
	_volley = 0
	blasts = 0
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._visual_call(&"play_shout", [str(p.get("shout", "QUE LA FÊTE NE S'ARRÊTE JAMAIS !"))])
	fx(&"ring", e.global_position, Vector2.ZERO, 120.0, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	e.stop()
	var nv := maxi(int(f("volleys")), 1)
	while _volley < nv and t >= windup() + f("gap") * _volley:
		_launch_volley()
		_volley += 1
	for i: int in range(_pending.size() - 1, -1, -1):
		var item: Array = _pending[i]
		if t >= float(item[1]):
			e.spawn_hazard(&"blast", item[0], {"radius": f("radius"), "damage": f("damage") * e.diff_damage_mult})
			blasts += 1
			_pending.remove_at(i)
	return _volley >= nv and _pending.is_empty()


func _launch_volley() -> void:
	var c := player_pos()
	var n := maxi(int(f("count")), 1)
	e._play_sfx(&"enemy_attack")
	for k: int in n:
		var pt := c if k == 0 else c + Vector2.from_angle(randf() * TAU) * randf_range(f("radius"), f("spread"))
		fx(&"ring", pt, Vector2.ZERO, f("radius"), f("delay"))
		_pending.append([pt, t + f("delay")])


func cleanup() -> void:
	_pending.clear()
