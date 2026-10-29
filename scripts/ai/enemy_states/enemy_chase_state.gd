extends EnemyState
## Combat (« Chase ») : décisions tactiques espacées (think_interval) selon la tactique de
## l'archétype (EnemyData.get_tactic()) :
##  - rusher (couteau) : fonce en zigzag ; contourne si un allié attaque déjà de face ;
##  - gunner / sniper / grenadier / elite : garde sa distance [range_min, range_max], se met à
##    couvert (case voisine d'un obstacle entre lui et le joueur), sort la tête pour tirer
##    (« peek »), se décale latéralement sinon ; flanque quand plusieurs alliés sont engagés ;
##  - heavy (brute, colosse) : avance droit sur le joueur.
## À portée d'attaque (Enemy.attack_reach) et cooldown prêt → Attack. Joueur perdu de vue plus
## de lose_sight_time → Search. PV faibles → Retreat. Laisse dépassée → Return.
## Joueur vu en train de se cacher : va à la cachette, la fouille et l'en fait sortir.

var _unseen_time: float = 0.0
var _think_left: float = 0.0
var _goal: Vector2 = Vector2.ZERO
var _has_goal: bool = false
var _goal_speed: float = 0.0
var _strafe_side: int = 1
var _dig_left: float = -1.0
var _zig_t: float = 0.0
var _peek_side: int = 1
var _peek_left: float = 0.0


func _init() -> void:
	name = "Chase"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	_unseen_time = 0.0
	_think_left = 0.0
	_has_goal = false
	_dig_left = -1.0
	_strafe_side = 1 if randf() < 0.5 else -1
	_peek_side = _strafe_side
	_zig_t = randf() * maxf(e.data.zigzag_period, 0.1)


func physics_update(delta: float) -> void:
	var e := get_enemy()
	var p := e.get_player()
	if p == null:
		request_transition(Enemy.STATE_RETURN)
		return
	if e.global_position.distance_squared_to(e.spawn_position) > e.leash_distance * e.leash_distance \
			and not e.can_see_player:
		request_transition(Enemy.STATE_RETURN)
		return
	if e.saw_player_hide:
		_flush_out(delta)
		return
	if e.should_retreat():
		request_transition(Enemy.STATE_RETREAT)
		return

	if not e.can_see_player:
		_unseen_time += delta
		if _unseen_time > e.data.lose_sight_time:
			request_transition(Enemy.STATE_SEARCH, {"target_pos": e.last_seen_position})
			return
		# À couvert : sort la tête d'un côté puis de l'autre pour retrouver la ligne de tir.
		if e.has_cover() and e.is_at(e.cover_position, 48.0) and _unseen_time < e.data.lose_sight_time * 0.8:
			_peek(e, p, delta)
			return
		var t := p.global_position if _unseen_time < e.track_memory else e.last_seen_position
		e.move_toward_position(t, e.run_speed())
		return

	_unseen_time = 0.0
	var dist := e.global_position.distance_to(p.global_position)
	e.face_position(p.global_position)
	var pattern := e.data.get_pattern()
	if e.attack_ready() and dist <= e.attack_reach(pattern):
		request_transition(Enemy.STATE_ATTACK)
		return
	_think_left -= delta
	if _think_left <= 0.0 or not _has_goal:
		_think_left = e.think_interval * randf_range(0.8, 1.25)
		_think(e, p, dist)
	_move(e, p, dist, delta)


## Choisit un objectif de déplacement selon la tactique.
func _think(e: Enemy, p: Node2D, dist: float) -> void:
	var tactic := e.data.get_tactic()
	var ppos := p.global_position
	var rmin := e.data.range_min()
	var rmax := e.data.range_max()
	var side := e.update_flank_side()
	var speed := e.run_speed()
	_has_goal = true
	match tactic:
		&"rusher":
			_goal = ppos
			if side != 0 and dist > 170.0:
				_goal = EnemyTactics.flank_point(e.global_position, ppos, side, minf(dist * 0.6, 160.0), e.flank_angle_deg)
			_goal_speed = speed
		&"heavy":
			_goal = ppos
			_goal_speed = speed
			if dist < rmax * 0.75:
				_has_goal = false
		_:
			_goal_speed = speed
			if dist < rmin:
				# Trop près : recule (vers un couvert plus loin si possible).
				if e.seek_cover(ppos, rmin, rmax):
					_goal = e.cover_position
				else:
					_goal = EnemyTactics.retreat_point(e.global_position, ppos, rmin - dist + 80.0)
				_goal_speed = speed * maxf(e.retreat_speed_ratio, 0.6)
			elif dist > rmax:
				if side != 0:
					_goal = EnemyTactics.flank_point(e.global_position, ppos, side, rmax * 0.85, e.flank_angle_deg)
				else:
					_goal = ppos
			elif e.seek_cover(ppos, rmin, rmax * 1.1):
				_goal = e.cover_position
			else:
				var hold := Balance.get_float("enemy_tactics", "sniper_hold_chance", 0.7) if tactic == &"sniper" else 0.25
				if randf() < hold:
					_has_goal = false
				else:
					if randf() < 0.35:
						_strafe_side = -_strafe_side
					var step := Balance.get_float("enemy_tactics", "strafe_step", 110.0)
					_goal = EnemyTactics.strafe_point(e.global_position, ppos, _strafe_side, step)
					if not e.has_line_between(e.global_position, _goal):
						_strafe_side = -_strafe_side
						_goal = EnemyTactics.strafe_point(e.global_position, ppos, _strafe_side, step)
					_goal_speed = speed * e.data.strafe_ratio


func _move(e: Enemy, _p: Node2D, dist: float, delta: float) -> void:
	if not _has_goal or e.is_at(_goal, 14.0):
		e.stop()
		return
	var base := e.direction_toward(_goal)
	if e.data.zigzag_amplitude > 0.0 and dist > e.attack_reach(e.data.get_pattern()) * 1.15:
		_zig_t += delta
		var lat := EnemyTactics.zigzag_lateral(_zig_t, e.data.zigzag_period, e.data.zigzag_amplitude, _goal_speed)
		e.move_in_direction(base + base.orthogonal() * lat, _goal_speed)
	else:
		e.desired_velocity = base * _goal_speed
		e.direct_velocity = false


func _peek(e: Enemy, p: Node2D, delta: float) -> void:
	_peek_left -= delta
	var to := (p.global_position - e.cover_position).normalized()
	var spot := e.cover_position + to.orthogonal() * float(_peek_side) * e.peek_offset
	if _peek_left <= 0.0:
		_peek_left = 1.1
		_peek_side = -_peek_side
	e.move_toward_position(spot, e.run_speed() * 0.7)
	e.face_position(e.last_seen_position)


## Va à la cachette où le joueur s'est glissé, la fouille, puis le déloge.
func _flush_out(delta: float) -> void:
	var e := get_enemy()
	var reach := e.data.attack_range + e.data.body_radius + 24.0
	if e.global_position.distance_to(e.last_seen_position) > reach:
		_dig_left = -1.0
		e.move_toward_position(e.last_seen_position, e.run_speed())
		return
	e.stop()
	e.face_position(e.last_seen_position)
	if _dig_left < 0.0:
		_dig_left = e.hide_search_time
		e._visual_call(&"play_alert")
	_dig_left -= delta
	if _dig_left <= 0.0:
		_dig_left = -1.0
		e.reveal_hidden_player()
