extends EnemySkill
## Passif (alien) : furieux quand le joueur est proche. En combat, à moins de `near` px du joueur,
## l'alien entre en frénésie pour `duration` s (prolongée tant que le joueur reste proche) :
## vitesse × speed_mult, recharges × cooldown_mult, aura rouge et cri au premier déclenchement.

var active: bool = false
var _left: float = 0.0
var _check: float = 0.0
var _shown: bool = false


func defaults() -> Dictionary:
	return {"passive": true, "near": 170.0, "duration": 2.5, "speed_mult": 1.45, "cooldown_mult": 0.6,
		"check_interval": 0.2, "shout": "GRRAAAH !"}


func tick_cooldown(dt: float) -> void:
	super.tick_cooldown(dt)
	if e == null or not e.is_alive():
		return
	_check -= dt
	if _check <= 0.0:
		_check = f("check_interval")
		var pl := player()
		if pl != null and e.is_in_combat() and pl.global_position.distance_to(e.global_position) <= f("near"):
			_left = f("duration")
	if _left > 0.0:
		_left -= dt
		if not active:
			_apply_frenzy(true)
	elif active:
		_apply_frenzy(false)


func _apply_frenzy(on: bool) -> void:
	active = on
	e.rage_speed_mult = f("speed_mult") if on else 1.0
	e.rage_cooldown_mult = f("cooldown_mult") if on else 1.0
	if on and not _shown:
		_shown = true
		e._visual_call(&"play_shout", [str(p.get("shout", "!"))])
		fx(&"rage", e.global_position, Vector2.ZERO, 0.0, 999.0)
