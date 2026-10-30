extends EnemySkill
## Araignée polaire : surgit de la neige. Accroupie (télégraphe : cercle à l'endroit visé, position
## prévue du joueur), elle bondit, retombe dans une gerbe de neige : dégâts aux joueurs dans `radius`
## + statut (« root » : pris dans la glace). Si elle était encore enfouie (ice_burrow) au moment
## du bond (ou en sortait depuis moins de `surprise_window` s), dégâts × `surprise_mult` et télégraphe raccourci (× `surprise_windup`) : la surprise.
## Un mur arrête le bond. Valeurs : [bestiary_frozen] ambush_*.

const BAL := "bestiary_frozen"

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _land_t: float = -1.0
var _last_pos: Vector2 = Vector2.ZERO
var _surprise: bool = false
var _windup: float = 0.0
## Bonds lancés depuis la neige (tests).
var surprise_uses: int = 0


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "ambush_cooldown", 7.0),
		"initial_cooldown": Balance.get_float(BAL, "ambush_initial_cooldown", 0.3),
		"windup": Balance.get_float(BAL, "ambush_windup", 0.5),
		"min_range": Balance.get_float(BAL, "ambush_min_range", 90.0),
		"max_range": Balance.get_float(BAL, "ambush_max_range", 340.0),
		"flight": Balance.get_float(BAL, "ambush_flight", 0.32),
		"radius": Balance.get_float(BAL, "ambush_radius", 60.0),
		"damage": Balance.get_float(BAL, "ambush_damage", 13.0),
		"status": "root",
		"status_time": Balance.get_float(BAL, "ambush_root_time", 0.7),
		"surprise_mult": Balance.get_float(BAL, "ambush_surprise_mult", 1.6),
		"surprise_windup": Balance.get_float(BAL, "ambush_surprise_windup", 0.5),
		"surprise_window": Balance.get_float(BAL, "ambush_surprise_window", 1.5),
		"lead": 0.3, "recover": 0.3, "priority": 1.6,
	}


func _burrow() -> EnemySkill:
	for sk: EnemySkill in e.skills:
		if sk.id == &"ice_burrow":
			return sk
	return null


func start() -> void:
	e.stop()
	var bur := _burrow()
	# Surprise : encore enfouie, ou sortie de la neige depuis moins de `surprise_window` s.
	_surprise = bur != null and (bool(bur.get(&"buried")) or float(bur.get(&"since_surface")) <= f("surprise_window"))
	if _surprise:
		surprise_uses += 1
		bur.call(&"set_buried", false)
	_windup = windup() * (f("surprise_windup") if _surprise else 1.0)
	_from = e.global_position
	var to := e.predict_player_position(_windup * f("lead"))
	if _from.distance_to(to) > f("max_range"):
		to = _from + (to - _from).normalized() * f("max_range")
	_to = to
	_land_t = -1.0
	_last_pos = _from
	e.face(_to - _from)
	e._visual_call(&"play_attack_windup", [_windup, false])
	fx(&"ring", _to, Vector2.ZERO, f("radius"), _windup + f("flight"))
	e._fx_dust(e.global_position, 4)


func step(dt: float) -> bool:
	if t < _windup:
		e.stop()
		return false
	if _land_t < 0.0:
		var ft := t - _windup
		var moved := e.global_position.distance_to(_last_pos)
		var blocked := ft > 0.1 and moved < 0.5
		if ft < f("flight") and e.global_position.distance_to(_to) > 12.0 and not blocked:
			e.dash((_to - e.global_position).normalized(), _from.distance_to(_to) / maxf(f("flight"), 0.05))
			_last_pos = e.global_position
			return false
		_land()
		_land_t = t
	e.stop()
	return t >= _land_t + f("recover")


func _land() -> void:
	e.stop()
	e._visual_call(&"play_ground_slam", [f("radius")])
	e._fx_dust(e.global_position, 5)
	e._play_sfx(&"blade_swing_heavy")
	var dmg := f("damage") * e.diff_damage_mult * (f("surprise_mult") if _surprise else 1.0)
	if e.is_inside_tree():
		EnemySkills.hit_players_in_radius(e.get_tree(), e.global_position, f("radius"), dmg, e,
			StringName(str(p.get("status", ""))), f("status_time"))


func cleanup() -> void:
	e.stop()
