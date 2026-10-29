extends EnemySkill
## Pas de l'ombre (Clone) : se brouille puis réapparaît DANS LE DOS du joueur (à l'opposé de sa
## visée), prêt à frapper aussitôt — « attaque au mauvais moment ». Télégraphe : silhouette qui
## s'efface et marqueur bleu à l'arrivée.

var _dest: Vector2 = Vector2.ZERO
var _moved: bool = false


func defaults() -> Dictionary:
	return {"cooldown": 7.0, "initial_cooldown": 2.5, "windup": 0.4, "min_range": 90.0, "max_range": 420.0,
		"behind": 70.0}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	_dest = _pick()
	return _dest != Vector2.INF


func _pick() -> Vector2:
	var pl := player()
	if pl == null:
		return Vector2.INF
	var aim: Variant = pl.get(&"aim_direction")
	var fwd: Vector2 = (aim as Vector2).normalized() if aim is Vector2 and (aim as Vector2).length_squared() > 0.01 \
		else (e.global_position - pl.global_position).normalized()
	for rot: float in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var pt := pl.global_position - fwd.rotated(rot) * f("behind")
		if _free(pt) and e.has_line_between(pl.global_position, pt):
			return pt
	return Vector2.INF


func _free(pt: Vector2) -> bool:
	if not e.is_inside_tree():
		return false
	var q := PhysicsPointQueryParameters2D.new()
	q.position = pt
	q.collision_mask = 1
	return e.get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


func start() -> void:
	e.stop()
	_moved = false
	var d := _pick()
	_dest = d if d != Vector2.INF else e.global_position
	e.invulnerable_left = windup()
	fx(&"blink", e.global_position, _dest, 22.0, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _moved:
		_moved = true
		e.global_position = _dest
		e._fx_dust(_dest, 2)
		e.face(player_pos() - _dest)
		e.attack_cooldown_left = 0.0
	return t >= windup() + 0.05
