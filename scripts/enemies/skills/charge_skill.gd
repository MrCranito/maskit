extends EnemySkill
## Charge en ligne droite (`charge` : brute — renverse ; `rush` : ruée générique sans
## renversement). Télégraphe : couloir rouge au sol jusqu'à la cible, puis course rapide ;
## le joueur touché subit des dégâts (+ statut). Contre un mur : l'ennemi est sonné.

var _dir: Vector2 = Vector2.RIGHT
var _from: Vector2 = Vector2.ZERO
var _length: float = 0.0
var _hit: bool = false
var _last_pos: Vector2 = Vector2.ZERO
var _blocked: float = 0.0


func defaults() -> Dictionary:
	return {"cooldown": 9.0, "windup": 0.9, "min_range": 140.0, "max_range": 420.0, "speed": 560.0,
		"overshoot": 90.0, "width": 56.0, "damage": 18.0, "status": "knockdown", "status_time": 0.8,
		"self_stun": 0.6}


func start() -> void:
	e.stop()
	_from = e.global_position
	var pp := player_pos()
	_dir = (pp - _from).normalized()
	_length = minf(_from.distance_to(pp) + f("overshoot"), f("max_range") + f("overshoot"))
	_hit = false
	_blocked = 0.0
	e.face(_dir)
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"lane", _from, _from + _dir * _length, f("width"), windup() + _length / maxf(f("speed"), 1.0))


func step(dt: float) -> bool:
	if t < windup():
		e.stop()
		_last_pos = e.global_position
		return false
	var travelled := e.global_position.distance_to(_from)
	if travelled >= _length or _hit:
		return true
	e.dash(_dir, f("speed"))
	# Joueur dans le couloir, au contact.
	var pl := player()
	if pl != null and not _hit and pl.global_position.distance_to(e.global_position) <= e.data.body_radius + 30.0:
		_hit = true
		var st := StringName(str(p.get("status", "")))
		EnemySkills.hit_player(pl, f("damage") * e.diff_damage_mult, e, st, f("status_time"), 1.0, e.global_position - _dir * 30.0)
		e._visual_call(&"play_strike", [_dir, false])
		return true
	# Bloqué contre un mur : sonné.
	if t > windup() + 0.12 and e.global_position.distance_to(_last_pos) < f("speed") * dt * 0.2:
		_blocked += dt
		if _blocked > 0.08:
			e.pending_stun = f("self_stun")
			e._fx_dust(e.global_position + _dir * 20.0, 3)
			return true
	_last_pos = e.global_position
	return false


func cleanup() -> void:
	e.stop()
