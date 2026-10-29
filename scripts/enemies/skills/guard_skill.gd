extends EnemySkill
## Protection frontale :
##  - `hard_skin` (passif, brute) : au contact (distance ≤ near), les coups venant de face sont
##    réduits de `reduction` (étincelle « ting ») ;
##  - `shield` (chef : plaque de tôle) / `energy_shield` (station) : actif — lève un bouclier
##    pendant `duration` s qui bloque `block` des dégâts venant de face ; l'ennemi continue à
##    se battre pendant ce temps.

var shield_left: float = 0.0
var _deflect_ms: int = -100000


func defaults() -> Dictionary:
	return {"cooldown": 11.0, "windup": 0.35, "max_range": 520.0, "duration": 4.0, "block": 1.0,
		"front_dot": 0.25, "near": 150.0, "reduction": 0.5, "style": 0.0}


func tick_cooldown(dt: float) -> void:
	super.tick_cooldown(dt)
	if shield_left > 0.0:
		shield_left -= dt


func start() -> void:
	e.stop()
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"shield", e.global_position, Vector2.ZERO, f("style"), windup() + f("duration"))


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	shield_left = f("duration")
	return true


func is_shield_up() -> bool:
	return shield_left > 0.0


func modify_damage(amount: float, source: Node) -> float:
	if amount <= 0.0 or not (source is Node2D) or not is_instance_valid(source):
		return amount
	var from := (source as Node2D).global_position
	var to_src := from - e.global_position
	if to_src.length_squared() < 1.0:
		return amount
	var frontal := e.facing.dot(to_src.normalized()) >= f("front_dot")
	if not frontal:
		return amount
	var out := amount
	if is_passive():
		if to_src.length() > f("near"):
			return amount
		out = amount * (1.0 - clampf(f("reduction"), 0.0, 1.0))
	elif shield_left > 0.0:
		out = amount * (1.0 - clampf(f("block"), 0.0, 1.0))
	else:
		return amount
	var now := Time.get_ticks_msec()
	if now - _deflect_ms > 120:
		_deflect_ms = now
		fx(&"deflect", e.global_position, to_src.normalized(), f("style"), 0.15)
	return out
