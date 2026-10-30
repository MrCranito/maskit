extends EnemySkill
## Passif temporaire posé par le boniment de l'Être forain (cv_rally_skill.gd) sur les créatures
## du parc : dégâts subis réduits, vitesse accrue, bouclier doré visible, pendant `left` s.
## Inerte une fois expiré (réutilisé au boniment suivant).

var left: float = 0.0
var _reduction: float = 0.0
var _speed: float = 1.0


func defaults() -> Dictionary:
	return {"passive": true}


func grant(duration: float, reduction: float, speed_mult: float) -> void:
	if left <= 0.0:
		_speed = maxf(speed_mult, 0.01)
		e.rage_speed_mult *= _speed
	left = maxf(left, duration)
	_reduction = clampf(reduction, 0.0, 0.9)
	fx(&"shield", e.global_position, Vector2.ZERO, 1.0, duration)


func is_active() -> bool:
	return left > 0.0


func tick_cooldown(dt: float) -> void:
	if left <= 0.0:
		return
	left -= dt
	if left <= 0.0 or (e != null and not e.is_alive()):
		left = 0.0
		if e != null:
			e.rage_speed_mult /= _speed
		_speed = 1.0


func modify_damage(amount: float, _source: Node) -> float:
	return amount * (1.0 - _reduction) if left > 0.0 else amount
