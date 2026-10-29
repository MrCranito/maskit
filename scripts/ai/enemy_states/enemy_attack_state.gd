extends EnemyState
## Attaque : ÉLAN (télégraphe, immobile) → FRAPPE (schéma de l'archétype) → RÉCUPÉRATION → Chase.
## Schémas (Enemy.next_pattern()) :
##  - melee  : coup simple ; touche seulement si le joueur est encore à portée (esquive possible) ;
##  - lunge  : élan visible (accroupi, lueur), ruée vers la position visée puis combo de
##             combo_hits coups espacés de combo_interval ;
##  - single / fan : un tir (ou un éventail) ; burst : rafale de burst_count tirs ;
##  - aimed  : ligne de visée rouge qui suit le joueur puis se fige (dernier quart du
##             télégraphe : fenêtre d'esquive), tir précis et rapide ;
##  - lob    : cercle au sol sur la position prévue du joueur, bâton de dynamite en cloche ;
##  - slam   : onde de choc au sol (zone autour de l'ennemi).
## Les tireurs abandonnent si la ligne de vue est perdue pendant l'élan (pas de tir dans un mur).

enum Step { WINDUP, STRIKE, RECOVER }

var _step: Step = Step.WINDUP
var _left: float = 0.0
var _windup_total: float = 0.0
var _pattern: StringName = &"melee"
var _aim: Vector2 = Vector2.RIGHT
var _target: Vector2 = Vector2.ZERO
var _locked: bool = false
var _shots_left: int = 0
var _hits_left: int = 0
var _dash_left: float = 0.0
var _no_los: float = 0.0
var _struck: bool = false


func _init() -> void:
	name = "Attack"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	e.stop()
	_struck = false
	_locked = false
	_no_los = 0.0
	_pattern = e.next_pattern()
	_windup_total = e.get_windup(_pattern)
	_left = _windup_total
	_step = Step.WINDUP
	var p := e.get_player()
	if p != null:
		_aim = (p.global_position - e.global_position).normalized()
		_target = p.global_position
		e.face_position(p.global_position)
	e._visual_call(&"set_aim_direction", [_aim])
	e._visual_call(&"use_throw_anim", [_pattern == &"lob" and e.data.get_pattern() != &"lob"])
	e._visual_call(&"play_attack_windup", [_windup_total])
	match _pattern:
		&"aimed":
			e._visual_call(&"show_aim_line", [_windup_total, minf(e.data.attack_range,
				e.global_position.distance_to(_target) + 70.0)])
		&"lob":
			_target = _lob_target(e)
			e._visual_call(&"show_ground_marker", [_target - e.global_position,
				e.data.throw_radius if e.data.throw_radius > 0.0 else 90.0, _windup_total])
			e.shout(&"dynamite")
		&"lunge":
			e._fx_dust(e.global_position, 1)


func exit() -> void:
	var e := get_enemy()
	e.direct_velocity = false
	e._visual_call(&"use_throw_anim", [false])


func _lob_target(e: Enemy) -> Vector2:
	var lead := e.lob_lead
	return e.predict_player_position((e.data.throw_flight_time + _windup_total) * lead)


func physics_update(delta: float) -> void:
	var e := get_enemy()
	match _step:
		Step.WINDUP:
			_windup(e, delta)
		Step.STRIKE:
			_strike(e, delta)
		Step.RECOVER:
			e.stop()
			_left -= delta
			if _left <= 0.0:
				request_transition(Enemy.STATE_CHASE)


func _windup(e: Enemy, delta: float) -> void:
	e.stop()
	var p := e.get_player()
	if p == null:
		request_transition(Enemy.STATE_RETURN)
		return
	var lock_at := _windup_total * e.aim_lock_ratio
	if not _locked:
		_aim = (p.global_position - e.global_position).normalized()
		e.face_position(p.global_position)
		e._visual_call(&"set_aim_direction", [_aim])
		if _pattern == &"lob":
			_target = _lob_target(e)
			e._visual_call(&"set_marker_position", [_target - e.global_position])
		if _pattern == &"lunge":
			_target = p.global_position
	if _left <= lock_at and not _locked:
		_locked = true
		if _pattern == &"aimed":
			e._visual_call(&"lock_aim_line")
	# Tireurs : pas de tir dans un mur.
	if e.data.is_ranged() and _pattern != &"lob":
		_no_los = 0.0 if e.can_see_player else _no_los + delta
		if _no_los > 0.25:
			e._visual_call(&"hide_telegraphs")
			request_transition(Enemy.STATE_CHASE)
			return
	_left -= delta
	if _left <= 0.0:
		_begin_strike(e)


func _begin_strike(e: Enemy) -> void:
	_step = Step.STRIKE
	_struck = true
	e._start_cooldown()
	match _pattern:
		&"burst":
			_shots_left = maxi(e.data.burst_count, 1)
			_left = 0.0
		&"lunge":
			var dir := _target - e.global_position
			if dir.length_squared() < 1.0:
				dir = e.facing
			_aim = dir.normalized()
			var dist := minf(e.data.lunge_distance, maxf(dir.length() - e.data.attack_range * 0.6, 0.0))
			_dash_left = dist / maxf(e.data.lunge_speed, 1.0)
			_hits_left = maxi(e.data.combo_hits, 1)
			_left = 0.0
			e._visual_call(&"play_strike", [_aim, false])
		_:
			_left = 0.0


func _strike(e: Enemy, delta: float) -> void:
	var p := e.get_player()
	match _pattern:
		&"burst":
			e.stop()
			_left -= delta
			if _left <= 0.0 and _shots_left > 0:
				if p != null:
					# Rafale : réajuste légèrement la visée entre deux tirs.
					var want := (p.global_position - e.global_position).normalized()
					_aim = _aim.slerp(want, 0.5)
				e.fire_volley(_aim)
				_shots_left -= 1
				_left = e.data.burst_interval
			if _shots_left <= 0 and _left <= 0.0:
				_recover(e)
		&"lunge":
			if _dash_left > 0.0:
				_dash_left -= delta
				e.dash(_aim, e.data.lunge_speed)
				if p != null and e.global_position.distance_to(p.global_position) <= e.data.attack_range * 0.7:
					_dash_left = 0.0
				return
			e.stop()
			_left -= delta
			if _left <= 0.0 and _hits_left > 0:
				if p != null:
					e.face_position(p.global_position)
				e.melee_strike(e.data.attack_range + e.melee_hit_tolerance)
				_hits_left -= 1
				_left = e.data.combo_interval
			if _hits_left <= 0 and _left <= 0.0:
				_recover(e)
		&"aimed":
			e.fire_volley(_aim)
			_recover(e)
		&"lob":
			e.throw_explosive(_target)
			_recover(e)
		&"slam":
			_slam(e, p)
			_recover(e)
		&"single", &"fan":
			e.fire_volley(_aim if _locked or p == null else p.global_position - e.global_position)
			_recover(e)
		_:
			# Mêlée simple : le joueur doit encore être à portée (il a pu esquiver).
			e.melee_strike(e.data.attack_range + e.melee_hit_tolerance)
			_recover(e)


func _slam(e: Enemy, p: Node2D) -> void:
	e._visual_call(&"play_ground_slam", [e.data.aoe_radius])
	e._fx_dust(e.global_position, 3)
	e._play_sfx(e.data.get_sfx_attack())
	if p != null and e.global_position.distance_to(p.global_position) <= e.data.aoe_radius and p.has_method("take_damage"):
		p.call("take_damage", e.get_attack_damage(), e)


func _recover(e: Enemy) -> void:
	e.stop()
	e.notify_attack_done()
	_step = Step.RECOVER
	_left = e.attack_recovery
