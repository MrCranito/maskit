extends EnemyState
## Poursuite : navigue vers le joueur tant qu'il est vu. Perdu de vue plus de
## lose_sight_time → va à sa dernière position connue, puis Return.
## À portée d'attaque (et cooldown prêt) → Attack. L'archer recule si le joueur est trop près.
## Laisse : au-delà de leash_distance du point d'apparition → Return.
## Joueur vu en train de se cacher (Enemy.saw_player_hide) : va à la cachette, la fouille
## (hide_search_time) et l'en fait sortir.

var _unseen_time: float = 0.0
var _search_left: float = 0.0
var _dig_left: float = -1.0


func _init() -> void:
	name = "Chase"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	_unseen_time = 0.0
	_search_left = e.search_timeout
	_dig_left = -1.0


func physics_update(delta: float) -> void:
	var e := get_enemy()
	var p := e.get_player()
	if p == null:
		request_transition(Enemy.STATE_RETURN)
		return
	if e.global_position.distance_squared_to(e.spawn_position) > e.leash_distance * e.leash_distance:
		request_transition(Enemy.STATE_RETURN)
		return

	if e.saw_player_hide:
		_flush_out(delta)
		return

	if e.can_see_player:
		_unseen_time = 0.0
		_search_left = e.search_timeout
		var dist := e.global_position.distance_to(p.global_position)
		e.face_position(p.global_position)
		if e.data.is_ranged() and e.data.retreat_distance > 0.0 and dist < e.data.retreat_distance:
			e.move_away_from(p.global_position, e.data.move_speed * e.retreat_speed_ratio)
			if e.attack_cooldown_left <= 0.0 and dist <= e.data.attack_range:
				request_transition(Enemy.STATE_ATTACK)
			return
		if dist <= e.data.attack_range:
			e.stop()
			if e.attack_cooldown_left <= 0.0:
				request_transition(Enemy.STATE_ATTACK)
			return
		e.move_toward_position(p.global_position, e.data.move_speed)
		return

	# Joueur hors de vue.
	_unseen_time += delta
	if _unseen_time <= e.data.lose_sight_time:
		# Courte mémoire : continue vers la position réelle (il vient de passer derrière un pilier).
		e.move_toward_position(p.global_position if _unseen_time < e.track_memory else e.last_seen_position, e.data.move_speed)
		return
	# Recherche : dernière position connue, puis abandon.
	_search_left -= delta
	if e.is_at(e.last_seen_position, e.arrive_distance * 2.0) or _search_left <= 0.0:
		request_transition(Enemy.STATE_RETURN)
		return
	e.move_toward_position(e.last_seen_position, e.data.move_speed)


## Va à la cachette où le joueur s'est glissé, la fouille, puis le déloge.
func _flush_out(delta: float) -> void:
	var e := get_enemy()
	var reach := e.data.attack_range + e.data.body_radius + 24.0
	if e.global_position.distance_to(e.last_seen_position) > reach:
		_dig_left = -1.0
		e.move_toward_position(e.last_seen_position, e.data.move_speed)
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
