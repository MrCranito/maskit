extends EnemySkill
## Passif (Nuit blanche) : se déplace dans l'ombre — silhouette presque transparente (`alpha`) tant
## qu'elle n'attaque pas ; redevient pleinement visible pendant ses attaques et compétences, et
## `reveal_time` s après avoir été touchée. Contrôle espacé (`check`), changement d'opacité
## seulement quand il le faut (aucun redessin par image).

var _reveal: float = 0.0
var _check: float = 0.0
var _shown: float = 1.0


func defaults() -> Dictionary:
	return {"passive": true, "alpha": 0.32, "reveal_time": 1.4, "check": 0.15}


func tick_cooldown(dt: float) -> void:
	if e == null or not e.is_alive():
		return
	if _reveal > 0.0:
		_reveal -= dt
	_check -= dt
	if _check > 0.0:
		return
	_check = f("check")
	var s := e.current_state_name()
	var visible_now := _reveal > 0.0 or s == Enemy.STATE_ATTACK or s == Enemy.STATE_SKILL or s == Enemy.STATE_STUNNED
	var target := 1.0 if visible_now else f("alpha")
	if not is_equal_approx(target, _shown):
		_shown = target
		e._visual_call(&"set_modulate", [Color(1, 1, 1, target)])


func on_damaged(_amount: float) -> void:
	_reveal = f("reveal_time")
	_check = 0.0


func is_hidden() -> bool:
	return _shown < 0.99
