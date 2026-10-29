extends EnemySkill
## Bond (Écorcheur, Nuit blanche, griffes du Violent) : s'accroupit (télégraphe : cercle rouge à
## l'endroit visé, position prévue du joueur), bondit puis retombe : dégâts aux joueurs dans
## `radius` (+ statut facultatif). Un mur arrête le bond (il retombe sur place).

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _land_t: float = -1.0
var _last_pos: Vector2 = Vector2.ZERO


func defaults() -> Dictionary:
	return {"cooldown": 6.0, "windup": 0.55, "min_range": 110.0, "max_range": 330.0, "flight": 0.38,
		"radius": 64.0, "damage": 14.0, "status": "", "status_time": 0.0, "lead": 0.3, "iframes": 0.0,
		"recover": 0.3}


func start() -> void:
	e.stop()
	_from = e.global_position
	var to := e.predict_player_position(windup() * f("lead"))
	if _from.distance_to(to) > f("max_range"):
		to = _from + (to - _from).normalized() * f("max_range")
	_to = to
	_land_t = -1.0
	_last_pos = _from
	e.face(_to - _from)
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", _to, Vector2.ZERO, f("radius"), windup() + f("flight"))


func step(dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if _land_t < 0.0:
		var ft := t - windup()
		if ft < f("iframes"):
			e.invulnerable_left = maxf(e.invulnerable_left, dt * 2.0)
		var moved := e.global_position.distance_to(_last_pos)
		var blocked := ft > 0.1 and moved < 0.5
		if ft < f("flight") and e.global_position.distance_to(_to) > 12.0 and not blocked:
			var dist := _from.distance_to(_to)
			e.dash((_to - e.global_position).normalized(), dist / maxf(f("flight"), 0.05))
			_last_pos = e.global_position
			return false
		_land()
		_land_t = t
	e.stop()
	return t >= _land_t + f("recover")


func _land() -> void:
	e.stop()
	var st := StringName(str(p.get("status", "")))
	e._visual_call(&"play_ground_slam", [f("radius")])
	e._fx_dust(e.global_position, 3)
	e._play_sfx(&"blade_swing_heavy")
	if e.is_inside_tree():
		EnemySkills.hit_players_in_radius(e.get_tree(), e.global_position, f("radius"), f("damage") * e.diff_damage_mult,
			e, st, f("status_time"))


func cleanup() -> void:
	e.stop()
