extends EnemySkill
## Chef de bande : coup de sifflet (cercles sonores, cri « À moi ! ») qui appelle `count`
## renforts. Ils arrivent par la porte la plus proche (groupe « doors », pas trop près du
## joueur) ou, à défaut, de derrière le chef ; ils connaissent la position du joueur.
## Au plus max_total renforts vivants par chef.
## `kinds` vide (défaut) : roster « combat » du monde courant (GameState.world_path), sans élites
## ni boss ; à défaut, FALLBACK_KINDS.

const FALLBACK_KINDS: Array = ["fw_bandit", "fw_raider"]

var _spawned: Array[Enemy] = []
var _done: bool = false


func defaults() -> Dictionary:
	return {"cooldown": 28.0, "initial_cooldown": 4.0, "windup": 0.9, "need_los": false, "hp_below": 0.92,
		"count": 2, "max_total": 4, "kinds": [], "door_radius": 900.0,
		"min_player_dist": 260.0}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	# Un renfort ne siffle pas à son tour (sinon réaction en chaîne sans fin).
	if e.has_meta(&"reinforcement"):
		return false
	return _alive_count() + int(f("count")) <= int(f("max_total"))


func _alive_count() -> int:
	var n := 0
	for i: int in range(_spawned.size() - 1, -1, -1):
		if not is_instance_valid(_spawned[i]) or not _spawned[i].is_alive():
			_spawned.remove_at(i)
		else:
			n += 1
	return n


func start() -> void:
	e.stop()
	_done = false
	e.shout(&"call", true)
	e._play_sfx(&"enemy_alert")
	fx(&"whistle", e.global_position, Vector2.ZERO, 0.0, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var kinds: Array = reinforcement_kinds()
		for i: int in int(f("count")):
			var pos := _spawn_point(i)
			var r := e.spawn_reinforcement(StringName(str(kinds[i % kinds.size()])), pos)
			if r != null:
				_spawned.append(r)
	return t >= windup() + 0.2


## Kinds des renforts : paramètre `kinds`, sinon le roster « combat » du monde courant.
func reinforcement_kinds() -> Array:
	var ks: Variant = p.get("kinds", [])
	if ks is Array and not (ks as Array).is_empty():
		return ks
	var roster := world_combat_kinds()
	return roster if not roster.is_empty() else FALLBACK_KINDS


## Kinds classiques (ni élite ni boss) du roster « combat » du monde courant ([] si inconnu).
static func world_combat_kinds() -> Array:
	var path := String(GameState.get("world_path")) if GameState != null else ""
	if path == "" or not ResourceLoader.exists(path):
		return []
	var w := load(path) as WorldData
	if w == null:
		return []
	var out: Array = []
	for k: Variant in w.get_roster(&"combat"):
		var kind := StringName(str(k))
		if kind in w.elite_kinds or kind == w.boss_kind:
			continue
		var dp := "res://data/enemies/%s.tres" % kind
		if not ResourceLoader.exists(dp):
			continue
		var d := load(dp) as EnemyData
		if d != null and not d.elite and not d.boss:
			out.append(String(kind))
	out.sort()
	return out


func _spawn_point(i: int) -> Vector2:
	var threat := player_pos()
	var best: Node2D = null
	var best_d := f("door_radius")
	if e.is_inside_tree():
		for n: Node in e.get_tree().get_nodes_in_group(&"doors"):
			var d := n as Node2D
			if d == null:
				continue
			var dd := d.global_position.distance_to(e.global_position)
			if dd >= best_d or d.global_position.distance_to(threat) < f("min_player_dist"):
				continue
			# Côté de la porte qui donne sur le joueur (les renforts doivent le voir en arrivant).
			var out := d.global_position + (threat - d.global_position).normalized() * 48.0
			if e.has_line_between(out, threat):
				best_d = dd
				best = d
	var off := Vector2.from_angle(float(i) * 2.1) * 28.0
	if best != null:
		return best.global_position + (threat - best.global_position).normalized() * 48.0 + off
	var back := (e.global_position - threat).normalized().rotated((float(i) - 0.5) * 0.9)
	var pt := e.global_position + back * 220.0
	if not e.has_line_between(e.global_position, pt):
		pt = e.global_position + back * 80.0
	return pt + off
