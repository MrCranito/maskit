extends EnemySkill
## Robuste : garde du corps. Repère l'allié le plus blessé que le joueur peut viser (dans
## `ally_radius` px), court se placer ENTRE lui et le joueur (à `stand_offset` px de l'allié),
## puis plante son bouclier face au joueur pendant `hold` s (télégraphe « bouclier ») : son corps
## arrête les balles destinées à l'allié et son passif `hard_skin` réduit les tirs de face.
## Valeurs : [bestiary_far_west] bodyguard_*.

const BAL := "bestiary_far_west"

var ward: Enemy = null
## Vrai pendant la tenue du bouclier (tests, debug F3).
var guarding: bool = false
var _dest: Vector2 = Vector2.ZERO
var _arrive_t: float = -1.0


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "bodyguard_cooldown", 7.0),
		"initial_cooldown": Balance.get_float(BAL, "bodyguard_initial_cooldown", 2.0),
		"windup": Balance.get_float(BAL, "bodyguard_windup", 0.25),
		"ally_radius": Balance.get_float(BAL, "bodyguard_ally_radius", 340.0),
		"stand_offset": Balance.get_float(BAL, "bodyguard_stand_offset", 70.0),
		"min_gain": Balance.get_float(BAL, "bodyguard_min_gain", 40.0),
		"move_time": Balance.get_float(BAL, "bodyguard_move_time", 3.0),
		"speed_mult": Balance.get_float(BAL, "bodyguard_speed_mult", 1.25),
		"hold": Balance.get_float(BAL, "bodyguard_hold", 2.4),
		"need_los": false, "priority": 1.6,
	}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	ward = _pick_ward()
	return ward != null


func _pick_ward() -> Enemy:
	if not e.is_inside_tree():
		return null
	var threat := player_pos()
	var best: Enemy = null
	var best_score := INF
	var r2 := f("ally_radius") * f("ally_radius")
	for node: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
		var u := node as Enemy
		if u == null or u == e or not u.is_alive() or u.data == null or u.data.kind == e.data.kind:
			continue
		if u.global_position.distance_squared_to(e.global_position) > r2:
			continue
		var spot := guard_spot(u, threat)
		if spot.distance_to(e.global_position) < f("min_gain"):
			continue  # déjà en place
		var score := u.hp / maxf(u.max_hp, 1.0) + u.global_position.distance_to(e.global_position) * 0.001
		if score < best_score:
			best_score = score
			best = u
	return best


## Case de garde : sur le segment allié → joueur, à stand_offset px de l'allié.
func guard_spot(ally: Enemy, threat: Vector2) -> Vector2:
	var to := threat - ally.global_position
	if to.length_squared() < 1.0:
		return ally.global_position
	return ally.global_position + to.normalized() * minf(f("stand_offset"), to.length() * 0.5)


func start() -> void:
	guarding = false
	_arrive_t = -1.0
	e.shout(&"retreat")
	_dest = guard_spot(ward, player_pos()) if is_instance_valid(ward) else e.global_position


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	var threat := player_pos()
	if _arrive_t < 0.0:
		if is_instance_valid(ward) and ward.is_alive():
			_dest = guard_spot(ward, threat)
		if e.is_at(_dest, 16.0) or t > windup() + f("move_time"):
			_arrive_t = t
			guarding = true
			e.stop()
			e.face_position(threat)
			fx(&"shield", e.global_position, Vector2.ZERO, 0.0, f("hold"))
			return false
		e.move_toward_position(_dest, e.run_speed() * f("speed_mult"))
		return false
	e.stop()
	e.face_position(threat)
	return t >= _arrive_t + f("hold")


func cleanup() -> void:
	guarding = false
	e.stop()
