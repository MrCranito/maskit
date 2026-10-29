extends EnemySkill
## Laser orbital (L'Architecte) : couloir de visée rouge qui suit le joueur puis se fige
## (`lock_ratio` de la fin du télégraphe), puis un rayon à longue portée brûle le couloir pendant
## `beam_time` s (dégâts toutes les `tick` s aux joueurs dans la largeur `width`). Le rayon
## s'arrête au premier mur. `sweep_deg` : le rayon balaie cet angle pendant qu'il tire.

var _dir: Vector2 = Vector2.RIGHT
var _end: Vector2 = Vector2.ZERO
var _tick_left: float = 0.0
var _beam_shown: bool = false
var _ray: PhysicsRayQueryParameters2D = null
var _buf: Array[Node2D] = []
## Nombre de tics de dégâts infligés (tests).
var ticks_hit: int = 0


func defaults() -> Dictionary:
	return {"cooldown": 7.0, "windup": 1.1, "min_range": 0.0, "max_range": 1100.0, "length": 1100.0, "width": 46.0,
		"beam_time": 0.9, "tick": 0.15, "damage": 9.0, "lock_ratio": 0.3, "sweep_deg": 0.0}


func start() -> void:
	e.stop()
	ticks_hit = 0
	_beam_shown = false
	_tick_left = 0.0
	_aim()
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"lane", e.global_position, _end, f("width"), windup())
	e._play_sfx(&"danger_jingle")


func _aim() -> void:
	var to := player_pos() - e.global_position
	if to.length_squared() > 1.0:
		_dir = to.normalized()
	e.face(_dir)
	_end = _clip(e.global_position, e.global_position + _dir * f("length"))


## Point d'arrêt du rayon (premier mur).
func _clip(from: Vector2, to: Vector2) -> Vector2:
	if not e.is_inside_tree():
		return to
	if _ray == null:
		_ray = PhysicsRayQueryParameters2D.new()
		_ray.collision_mask = 1
	_ray.from = from
	_ray.to = to
	var hit := e.get_world_2d().direct_space_state.intersect_ray(_ray)
	return hit["position"] if not hit.is_empty() else to


func step(dt: float) -> bool:
	if t < windup():
		e.stop()
		if t < windup() * (1.0 - f("lock_ratio")):
			_aim()
		return false
	var bt := f("beam_time")
	var u := clampf((t - windup()) / maxf(bt, 0.01), 0.0, 1.0)
	if f("sweep_deg") > 0.0:
		var d2 := _dir.rotated(deg_to_rad(f("sweep_deg")) * (u - 0.5))
		_end = _clip(e.global_position, e.global_position + d2 * f("length"))
	if not _beam_shown:
		_beam_shown = true
		e._visual_call(&"play_strike", [_end - e.global_position, true, true])
		e._play_sfx(&"flame")
		fx(&"lane", e.global_position, _end, f("width") * 0.6, bt)
	_tick_left -= dt
	if _tick_left <= 0.0:
		_tick_left += f("tick")
		_burn()
	return t >= windup() + bt


func _burn() -> void:
	EnemySkills.player_targets(e.get_tree(), _buf)
	var a := e.global_position
	for pl: Node2D in _buf:
		var q := Geometry2D.get_closest_point_to_segment(pl.global_position, a, _end)
		if q.distance_to(pl.global_position) <= f("width") * 0.5:
			EnemySkills.hit_player(pl, f("damage") * e.diff_damage_mult * e.phase_damage_mult, e)
			ticks_hit += 1
