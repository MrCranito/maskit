extends EnemySkill
## Voile d'ombre (Guerrier de l'ombre : camouflage, traque les intrus) : se fond dans l'ombre
## (télégraphe court : volute sombre), devient presque invisible (`alpha`, barre de vie masquée),
## plus rapide (`speed_mult`), connaît la position du joueur, et son premier coup sorti de l'ombre
## frappe plus fort (`ambush_mult`). Le voile tombe au premier coup donné ou reçu, ou après
## `duration` s. Valeurs : [bestiary_egypt] eg_shadow_veil_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")
const FX := preload("res://scripts/enemies/skills/egypt/eg_fx.gd")

var veil_left: float = 0.0
var _speed: float = 1.0
var _dmg: float = 1.0


func defaults() -> Dictionary:
	return Bal.defaults("eg_shadow_veil", {"cooldown": 12.0, "initial_cooldown": 2.5, "windup": 0.35, "min_range": 120.0,
		"max_range": 620.0, "need_los": false, "duration": 4.0, "alpha": 0.07, "speed_mult": 1.4, "ambush_mult": 1.6})


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return veil_left <= 0.0


func start() -> void:
	e.stop()
	fx(&"blink", e.global_position, e.global_position, 34.0, windup())
	if e.get_parent() != null:
		FX.spawn(e.get_parent(), &"curse", e.global_position, 46.0, windup() + 0.2)


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	_apply(true)
	return true


func _apply(on: bool) -> void:
	if on:
		veil_left = f("duration")
		_speed = f("speed_mult")
		_dmg = f("ambush_mult")
		e.rage_speed_mult *= _speed
		e.phase_damage_mult *= _dmg
		e._visual_call(&"set_modulate", [Color(0.6, 0.6, 0.9, f("alpha"))])
		e.become_aware(player_pos(), false)
	else:
		veil_left = 0.0
		e.rage_speed_mult /= maxf(_speed, 0.01)
		e.phase_damage_mult /= maxf(_dmg, 0.01)
		_speed = 1.0
		_dmg = 1.0
		e._visual_call(&"set_modulate", [Color.WHITE])
	if e._health_bar != null:
		e._health_bar.visible = not on and e.is_alive()


func tick_cooldown(dt: float) -> void:
	super.tick_cooldown(dt)
	if veil_left > 0.0:
		veil_left -= dt
		if veil_left <= 0.0:
			veil_left = 0.001
			_apply(false)


func on_attack_done() -> void:
	if veil_left > 0.0:
		_apply(false)


func on_damaged(_amount: float) -> void:
	if veil_left > 0.0:
		_apply(false)


func is_veiled() -> bool:
	return veil_left > 0.0
