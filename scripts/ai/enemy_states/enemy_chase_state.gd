extends EnemyState
## Poursuite : navigue vers le joueur tant qu'il est vu. Perdu de vue plus de
## lose_sight_time → va à sa dernière position connue, puis Return.
## À portée d'attaque (et cooldown prêt) → Attack. L'archer recule si le joueur est trop près.
## Laisse : au-delà de leash_distance du point d'apparition → Return.

var _unseen_time: float = 0.0
var _search_left: float = 0.0


func _init() -> void:
	name = "Chase"


func enter(_msg: Dictionary = {}) -> void:
	_unseen_time = 0.0
	_search_left = Balance.get_float("enemy_ai", "search_timeout", 4.0)


func physics_update(delta: float) -> void:
	var e := get_enemy()
	var p := e.get_player()
	if p == null:
		request_transition(Enemy.STATE_RETURN)
		return
	if e.global_position.distance_to(e.spawn_position) > Balance.get_float("enemy_ai", "leash_distance", 900.0):
		request_transition(Enemy.STATE_RETURN)
		return

	if e.can_see_player:
		_unseen_time = 0.0
		_search_left = Balance.get_float("enemy_ai", "search_timeout", 4.0)
		var dist := e.global_position.distance_to(p.global_position)
		e.face_position(p.global_position)
		if e.data.is_ranged() and e.data.retreat_distance > 0.0 and dist < e.data.retreat_distance:
			e.move_away_from(p.global_position, e.data.move_speed * Balance.get_float("enemy_ai", "retreat_speed_ratio", 0.8))
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
		e.move_toward_position(p.global_position if _unseen_time < Balance.get_float("enemy_ai", "track_memory", 0.5) else e.last_seen_position, e.data.move_speed)
		return
	# Recherche : dernière position connue, puis abandon.
	_search_left -= delta
	if e.is_at(e.last_seen_position, e.arrive_distance * 2.0) or _search_left <= 0.0:
		request_transition(Enemy.STATE_RETURN)
		return
	e.move_toward_position(e.last_seen_position, e.data.move_speed)
