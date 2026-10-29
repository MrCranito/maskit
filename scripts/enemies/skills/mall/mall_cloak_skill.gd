extends EnemySkill
## Invisibilité temporaire (Le Violent) : courte distorsion (télégraphe), puis presque invisible
## (`alpha`, barre de vie masquée) et plus rapide (`speed_mult`) pendant `duration` s. L'effet
## cesse dès qu'il frappe (attaque de base) ou qu'il est touché.

var cloak_left: float = 0.0
var _speed_bonus: float = 1.0


func defaults() -> Dictionary:
	return {"cooldown": 13.0, "initial_cooldown": 3.0, "windup": 0.35, "max_range": 520.0, "duration": 3.5,
		"alpha": 0.08, "speed_mult": 1.35}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return cloak_left <= 0.0


func start() -> void:
	e.stop()
	fx(&"blink", e.global_position, e.global_position, 30.0, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	_apply(true)
	return true


func _apply(on: bool) -> void:
	if on:
		cloak_left = f("duration")
		_speed_bonus = f("speed_mult")
		e.rage_speed_mult *= _speed_bonus
		e._visual_call(&"set_modulate", [Color(1, 1, 1, f("alpha"))])
	else:
		cloak_left = 0.0
		e.rage_speed_mult /= maxf(_speed_bonus, 0.01)
		_speed_bonus = 1.0
		e._visual_call(&"set_modulate", [Color.WHITE])
	if e._health_bar != null:
		e._health_bar.visible = not on and e.is_alive()


func tick_cooldown(dt: float) -> void:
	super.tick_cooldown(dt)
	if cloak_left > 0.0:
		cloak_left -= dt
		if cloak_left <= 0.0:
			_apply(false)


func on_attack_done() -> void:
	if cloak_left > 0.0:
		_apply(false)


func on_damaged(_amount: float) -> void:
	if cloak_left > 0.0:
		_apply(false)


func is_cloaked() -> bool:
	return cloak_left > 0.0
