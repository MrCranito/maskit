extends EnemySkill
## Chien de garde : aboiement d'alarme. Dès qu'il a repéré un intrus, il aboie (cercles sonores,
## bulle) et TOUS les ennemis dans `radius` px apprennent la position du joueur (ils passent en
## alerte / poursuite). Se répète tant que le combat dure (recharge `cooldown`) : il « marque » le
## joueur pour la meute et les bandits. Un joueur caché tout près (≤ `reveal_radius`) est débusqué.
## Valeurs par défaut : balance.cfg [bestiary_far_west] alarm_bark_* ; le .tres les remplace.

const BAL := "bestiary_far_west"

## Nombre d'ennemis alertés au dernier aboiement (tests, debug F3).
var last_alerted: int = 0
var _done: bool = false


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "alarm_bark_cooldown", 9.0),
		"initial_cooldown": Balance.get_float(BAL, "alarm_bark_initial_cooldown", 0.2),
		"windup": Balance.get_float(BAL, "alarm_bark_windup", 0.35),
		"radius": Balance.get_float(BAL, "alarm_bark_radius", 760.0),
		"reveal_radius": Balance.get_float(BAL, "alarm_bark_reveal_radius", 140.0),
		"need_los": false, "priority": 3.0, "text": "Ouaf ! Ouaf !",
	}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return e.has_last_seen or e.can_see_player


func start() -> void:
	e.stop()
	_done = false
	e.face_position(player_pos())
	e._visual_call(&"play_shout", [String(p.get("text", "Ouaf !"))])
	e._play_sfx(&"enemy_alert")
	fx(&"whistle", e.global_position, Vector2.ZERO, f("radius"), windup() + 0.4)


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		last_alerted = bark(player_pos())
	return t >= windup() + 0.15


## Alerte les ennemis dans le rayon (position du joueur). Renvoie le nombre d'ennemis alertés.
func bark(target: Vector2) -> int:
	if not e.is_inside_tree():
		return 0
	var n := 0
	var r2 := f("radius") * f("radius")
	for node: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
		var u := node as Enemy
		if u == null or u == e or not u.is_alive() or u.net_puppet:
			continue
		if u.global_position.distance_squared_to(e.global_position) > r2:
			continue
		if u.asleep:
			u.wake_up()
		u.become_aware(target, false)
		n += 1
	var pl := player()
	if pl != null and pl.global_position.distance_to(e.global_position) <= f("reveal_radius"):
		e.reveal_hidden_player()
	return n
