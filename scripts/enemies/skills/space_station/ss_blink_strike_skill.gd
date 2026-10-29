extends EnemySkill
## Téléporteur (station) : la silhouette se brouille (marqueur bleu à l'arrivée, invulnérable
## pendant le télégraphe), réapparaît DANS LE DOS du joueur puis frappe aussitôt après un court
## élan rouge (fenêtre d'esquive `strike_windup`). Tous les réglages dans le .tres.

var _dest: Vector2 = Vector2.ZERO
var _moved: bool = false
var _struck: bool = false
## Vrai si le dernier coup a touché (tests, debug F3).
var last_hit: bool = false


func defaults() -> Dictionary:
	return {"cooldown": 7.0, "windup": 0.55, "min_range": 150.0, "max_range": 560.0, "behind": 64.0,
		"strike_windup": 0.22, "reach": 80.0, "damage": 14.0}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	_dest = _pick()
	return _dest != Vector2.INF


## Derrière le joueur (à l'opposé du téléporteur), sinon sur ses flancs ; case libre et visible
## depuis le joueur (jamais derrière un mur).
func _pick() -> Vector2:
	var pp := player_pos()
	var to := pp - e.global_position
	var axis := to.normalized() if to.length_squared() > 1.0 else Vector2.RIGHT
	for ang: float in [0.0, 0.7, -0.7, 1.4, -1.4]:
		var pt := pp + axis.rotated(ang) * f("behind")
		if _free(pt) and e.has_line_between(pp, pt):
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
	_struck = false
	last_hit = false
	var d := _pick()
	_dest = d if d != Vector2.INF else e.global_position
	e.invulnerable_left = windup()
	fx(&"blink", e.global_position, _dest, 26.0, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	var sw := f("strike_windup") * e.diff_windup_mult
	if not _moved:
		_moved = true
		e.global_position = _dest
		e._fx_dust(_dest, 2)
		e.face_position(player_pos())
		e._visual_call(&"play_attack_windup", [sw])
	if t < windup() + sw:
		e.stop()
		e.face_position(player_pos())
		return false
	if not _struck:
		_struck = true
		e._visual_call(&"play_strike", [e.facing, false])
		e._play_sfx(e.data.get_sfx_attack())
		var pl := player()
		if pl != null and pl.global_position.distance_to(e.global_position) <= f("reach"):
			EnemySkills.hit_player(pl, f("damage") * e.diff_damage_mult * e.phase_damage_mult, e)
			last_hit = true
	return t >= windup() + sw + 0.2
