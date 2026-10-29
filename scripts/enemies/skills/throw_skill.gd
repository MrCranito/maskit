extends EnemySkill
## Objets lancés en cloche, cercle de danger au sol dès le télégraphe :
##  - `molotov` : cocktail incendiaire → zone de feu (EnemyHazard « fire ») ;
##  - `bounce_dynamite` : dynamite qui rebondit une fois avant d'exploser plus loin ;
##  - `grenade` : grenade générique (EnemyDynamite à mèche courte) ;
##  - `flash_grenade` : grenade flash (EnemyHazard « flash » : aveugle 1,5 s).

var _target: Vector2 = Vector2.ZERO
var _thrown: bool = false


func defaults() -> Dictionary:
	return {"cooldown": 9.0, "windup": 0.6, "min_range": 140.0, "max_range": 380.0, "kind": "fire",
		"radius": 70.0, "flight": 0.6, "fuse": 0.6, "damage": 20.0, "duration": 4.5, "dps": 9.0,
		"blind_time": 1.5, "lead": 0.4, "bounce": false, "bounce_ratio": 0.6, "bounce_flight": 0.35}


func _aim_point() -> Vector2:
	var to := e.predict_player_position((f("flight") + windup()) * f("lead"))
	var from := e.global_position
	if from.distance_to(to) > f("max_range"):
		to = from + (to - from).normalized() * f("max_range")
	return to


func start() -> void:
	e.stop()
	_thrown = false
	_target = _aim_point()
	e.face(_target - e.global_position)
	e._visual_call(&"use_throw_anim", [true])
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._visual_call(&"show_ground_marker", [_target - e.global_position, f("radius"), windup()])


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		if t < windup() * 0.7:
			_target = _aim_point()
			e._visual_call(&"set_marker_position", [_target - e.global_position])
		return false
	if not _thrown:
		_thrown = true
		_throw()
	return t >= windup() + 0.25


func _throw() -> void:
	var from := e.global_position + Vector2(0, -4)
	var kind := StringName(str(p["kind"]))
	e._visual_call(&"play_strike", [_target - e.global_position, false])
	e._play_sfx(&"blade_swing_heavy")
	if kind == &"dynamite":
		var first := _target
		var bounce := Vector2.INF
		if b("bounce"):
			first = from.lerp(_target, f("bounce_ratio"))
			bounce = _target
		e.throw_dynamite_custom(from, first, f("radius"), f("damage") * e.diff_damage_mult, f("flight"), f("fuse"),
			bounce, f("bounce_flight"))
		return
	var params := {"from": from, "flight": f("flight"), "radius": f("radius"), "duration": f("duration"),
		"dps": f("dps") * e.diff_damage_mult, "blind_time": f("blind_time")}
	e.spawn_hazard(kind, _target, params)


func cleanup() -> void:
	e._visual_call(&"use_throw_anim", [false])
