extends EnemySkill
## Roulade réactive (`dodge_roll` : esquive latérale ; `cover_roll` : roulade vers un couvert).
## Déclenchée quand le joueur le VISE (direction de visée à moins de aim_cone_deg de l'ennemi) :
## courte poussière (télégraphe), roulade rapide avec un bref instant d'invulnérabilité.

var _dir: Vector2 = Vector2.RIGHT
var _speed: float = 0.0


func defaults() -> Dictionary:
	return {"cooldown": 3.5, "initial_cooldown": 1.0, "windup": 0.1, "reactive": true, "need_los": true,
		"max_range": 480.0, "chance": 0.6, "aim_cone_deg": 14.0, "distance": 150.0, "duration": 0.3,
		"iframes": 0.25, "to_cover": false}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	var pl := player()
	if pl == null:
		return false
	var aiming := pl.has_method("is_aiming") and bool(pl.call("is_aiming"))
	if not aiming and pl.has_method("get_noise_level"):
		aiming = float(pl.call("get_noise_level")) > 0.8  # vient de tirer
	if not aiming:
		return false
	var aim: Variant = pl.get(&"aim_direction")
	if not (aim is Vector2):
		return false
	var to_me := e.global_position - pl.global_position
	if to_me.length_squared() < 1.0:
		return false
	return (aim as Vector2).normalized().dot(to_me.normalized()) >= cos(deg_to_rad(f("aim_cone_deg")))


func start() -> void:
	e.stop()
	var threat := player_pos()
	var dist := f("distance")
	_dir = Vector2.ZERO
	if b("to_cover") and e.seek_cover(threat, e.data.range_min() * 0.7, e.data.range_max() * 1.2):
		var to_cover := e.cover_position - e.global_position
		if to_cover.length() > 20.0 and to_cover.length() < dist * 1.6:
			_dir = to_cover.normalized()
			dist = to_cover.length()
	if _dir == Vector2.ZERO:
		var axis := (e.global_position - threat).normalized()
		var side := axis.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
		if e._ray_blocked(side * (dist * 0.8)):
			side = -side
		_dir = side
	_speed = dist / maxf(f("duration"), 0.05)
	fx(&"roll", e.global_position, e.global_position + _dir * dist, 0.0, windup() + f("duration"))
	e._fx_dust(e.global_position, 2)


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if t < windup() + f("duration"):
		e.invulnerable_left = maxf(e.invulnerable_left, f("iframes") - (t - windup()))
		e.dash(_dir, _speed)
		return false
	return true


func cleanup() -> void:
	e.stop()
