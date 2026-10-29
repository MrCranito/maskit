extends EnemySkill
## Androïde : se téléporte de couvert en couvert. Télégraphe : silhouette qui se brouille et
## marqueur à l'arrivée (on voit où il va réapparaître) ; réapparaît prêt à frapper.

var _dest: Vector2 = Vector2.ZERO
var _moved: bool = false
var _buf: PackedInt32Array = PackedInt32Array()


func defaults() -> Dictionary:
	return {"cooldown": 6.0, "windup": 0.45, "min_range": 120.0, "max_range": 560.0, "near": 140.0,
		"far": 240.0}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	_dest = _pick()
	return _dest != Vector2.INF


func _pick() -> Vector2:
	var threat := player_pos()
	var map := EnemyTactics.current_map()
	if map != null:
		EnemyTactics.find_covers(map, threat, threat, f("near"), f("far"), f("far"), e.get_instance_id(), 6, _buf)
		for idx: int in _buf:
			var c := map.points[idx]
			if c.distance_to(e.global_position) > 120.0 and _free(c):
				return c
	# Sans couvert : sur le flanc du joueur.
	var axis := (e.global_position - threat).normalized()
	for s: float in [1.0, -1.0]:
		var pt := threat + axis.rotated(s * 1.6) * (f("near") + f("far")) * 0.5
		if _free(pt) and e.has_line_between(threat, pt):
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
	# Destination recalculée au lancement (fraîche, et valable aussi pour un lancement forcé).
	var d := _pick()
	_dest = d if d != Vector2.INF else e.global_position
	e.invulnerable_left = windup()
	fx(&"blink", e.global_position, _dest, 26.0, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _moved:
		_moved = true
		e.global_position = _dest
		e._fx_dust(_dest, 2)
		e.attack_cooldown_left = minf(e.attack_cooldown_left, 0.25)
	return t >= windup() + 0.1
