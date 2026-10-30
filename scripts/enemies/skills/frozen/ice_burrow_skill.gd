extends EnemySkill
## Passif (Araignée polaire) : enfouie sous la neige. Hors combat (patrouille, enquête, retour) elle
## n'est qu'une bosse de neige presque invisible (opacité `alpha`) et sa barre de vie est cachée ;
## dès qu'elle repère le joueur ou qu'elle est touchée, elle surgit (pleinement visible) et le
## reste `reveal_time` s après la fin du combat. Contrôle espacé (`check`), aucun redessin par image.
## Valeurs : [bestiary_frozen] burrow_*.

const BAL := "bestiary_frozen"

var _reveal: float = 0.0
var _check: float = 0.0
var _shown: float = 1.0
## Vrai tant qu'elle est enfouie (tests, compétence ice_ambush : bonus de surprise).
var buried: bool = false
## Temps (s) depuis la dernière sortie de la neige (grand tant qu'elle n'est jamais sortie).
var since_surface: float = 999.0


func defaults() -> Dictionary:
	return {
		"passive": true,
		"alpha": Balance.get_float(BAL, "burrow_alpha", 0.14),
		"reveal_time": Balance.get_float(BAL, "burrow_reveal_time", 2.0),
		"check": Balance.get_float(BAL, "burrow_check", 0.15),
	}


func tick_cooldown(dt: float) -> void:
	if e == null or not e.is_alive():
		return
	if _reveal > 0.0:
		_reveal -= dt
	since_surface += dt
	_check -= dt
	if _check > 0.0:
		return
	_check = f("check")
	if e.is_in_combat() or e.current_state_name() == Enemy.STATE_STUNNED:
		_reveal = f("reveal_time")
	set_buried(_reveal <= 0.0)


func set_buried(on: bool) -> void:
	var target := f("alpha") if on else 1.0
	if buried and not on:
		since_surface = 0.0
	buried = on
	if is_equal_approx(target, _shown):
		return
	_shown = target
	e._visual_call(&"set_modulate", [Color(0.9, 0.95, 1.0, target) if on else Color(1, 1, 1, 1)])
	if e._health_bar != null:
		e._health_bar.visible = not on and e.is_alive()


func on_damaged(_amount: float) -> void:
	_reveal = f("reveal_time")
	_check = 0.0
	set_buried(false)
