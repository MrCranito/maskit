extends EnemySkill
## Soldat de la station : déploie une petite tourelle (EnemyHazard « turret ») qui tire sur le
## joueur pendant `duration` s ; destructible (hp). Au plus une tourelle par soldat.

var _turret: EnemyHazard = null


func defaults() -> Dictionary:
	return {"cooldown": 18.0, "initial_cooldown": 5.0, "windup": 0.7, "max_range": 460.0, "duration": 12.0,
		"hp": 30.0, "interval": 0.7, "damage": 5.0, "range": 380.0, "speed": 520.0}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return _turret == null or not is_instance_valid(_turret)


func start() -> void:
	e.stop()
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"deploy", _spot(), Vector2.ZERO, 20.0, windup())


func _spot() -> Vector2:
	var side := e.facing.orthogonal() * 34.0
	var pt := e.global_position + side
	return pt if e.has_line_between(e.global_position, pt) else e.global_position + e.facing * 20.0


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if _turret == null or not is_instance_valid(_turret):
		_turret = e.spawn_hazard(&"turret", _spot(), {"duration": f("duration"), "hp": f("hp"), "interval": f("interval"),
			"damage": f("damage") * e.diff_damage_mult, "range": f("range"), "speed": f("speed"), "arm_delay": 0.6})
	return true
