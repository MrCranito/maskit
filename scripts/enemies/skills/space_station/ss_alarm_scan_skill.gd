extends EnemySkill
## Détecteur (station) : repère le joueur et donne l'alerte. Télégraphe : balayage (anneau) et
## cri ; puis tous les ennemis dans `radius` connaissent la position du joueur (alertés, même
## sans le voir), le joueur caché est débusqué, et `call_count` renforts (`kinds`) arrivent
## derrière le détecteur (au plus `max_total` vivants).

var _done: bool = false
var _spawned: Array[Enemy] = []
## Nombre d'ennemis alertés par le dernier balayage (tests, debug F3).
var alerted: int = 0


func defaults() -> Dictionary:
	return {"cooldown": 14.0, "initial_cooldown": 0.3, "windup": 0.8, "radius": 900.0, "scan_radius": 140.0,
		"call_count": 0, "max_total": 2, "kinds": [], "call_dist": 90.0, "priority": 3.0, "shout": "ALERTE !"}


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_shout", [str(p.get("shout", "ALERTE !"))])
	e._play_sfx(&"danger_jingle")
	fx(&"ring", e.global_position, Vector2.ZERO, f("scan_radius"), windup())
	fx(&"whistle", e.global_position, Vector2.ZERO, 0.0, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		e.face_position(player_pos())
		return false
	if not _done:
		_done = true
		_alert_all()
		_call_reinforcements()
	return t >= windup() + 0.2


func _alert_all() -> void:
	alerted = 0
	if not e.is_inside_tree():
		return
	var pp := player_pos()
	e.reveal_hidden_player()
	var r2 := f("radius") * f("radius")
	for n: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
		var o := n as Enemy
		if o == null or o == e or not o.is_alive():
			continue
		if o.global_position.distance_squared_to(e.global_position) > r2:
			continue
		o.become_aware(pp, false)
		alerted += 1


func _call_reinforcements() -> void:
	for i: int in range(_spawned.size() - 1, -1, -1):
		if not is_instance_valid(_spawned[i]) or not _spawned[i].is_alive():
			_spawned.remove_at(i)
	var kinds: Array = p.get("kinds", [])
	if kinds.is_empty():
		return
	var n := mini(int(f("call_count")), int(f("max_total")) - _spawned.size())
	var away := (e.global_position - player_pos()).normalized()
	if away.length_squared() < 0.01:
		away = Vector2.UP
	for i: int in n:
		var pt := e.global_position + away.rotated((float(i) - 0.5 * float(n - 1)) * 0.8) * f("call_dist")
		if not e.has_line_between(e.global_position, pt):
			pt = e.global_position
		var r := e.spawn_reinforcement(StringName(str(kinds[i % kinds.size()])), pt)
		if r != null:
			_spawned.append(r)
