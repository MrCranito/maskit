extends EnemySkill
## Projectiles spéciaux : `knife_throw` (lancer de couteau : ligne de visée courte puis couteau
## rapide) et `fan_volley` (« éventail » : pose, cône rouge, puis `count` balles balayant l'arc).

var _aim: Vector2 = Vector2.RIGHT
var _shots: int = 0
var _next: float = 0.0


func defaults() -> Dictionary:
	return {"cooldown": 6.0, "windup": 0.5, "min_range": 140.0, "max_range": 420.0, "count": 1,
		"arc_deg": 0.0, "interval": 0.06, "speed": 620.0, "damage": 10.0, "style": "knife",
		"lifetime": 0.9, "lock_ratio": 0.2}


func start() -> void:
	e.stop()
	var pp := player_pos()
	_aim = (pp - e.global_position).normalized()
	e.face(_aim)
	_shots = 0
	_next = 0.0
	e._visual_call(&"set_aim_direction", [_aim])
	e._visual_call(&"play_attack_windup", [windup(), false])
	if int(f("count")) <= 1:
		e._visual_call(&"show_aim_line", [windup(), e.global_position.distance_to(pp) + 40.0])
	else:
		fx(&"arc", e.global_position, _aim, f("arc_deg"), windup())


func step(dt: float) -> bool:
	var count := maxi(int(f("count")), 1)
	if t < windup():
		e.stop()
		if t < windup() * (1.0 - f("lock_ratio")):
			_aim = (player_pos() - e.global_position).normalized()
			e.face(_aim)
			e._visual_call(&"set_aim_direction", [_aim])
		return false
	_next -= dt
	while _shots < count and _next <= 0.0:
		var k := 0.0 if count == 1 else float(_shots) / float(count - 1) - 0.5
		var dir := _aim.rotated(deg_to_rad(f("arc_deg")) * k)
		e.fire_special(dir, f("speed"), f("damage") * e.diff_damage_mult, StringName(str(p["style"])), f("lifetime"), count == 1)
		_shots += 1
		_next += f("interval")
	return _shots >= count and t >= windup() + f("interval") * float(count) + 0.15
