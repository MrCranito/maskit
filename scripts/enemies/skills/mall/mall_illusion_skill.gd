extends EnemySkill
## Illusion (Clone, Omnistore en phase 1) : l'ennemi se brouille (télégraphe), fait apparaître
## `count` doubles illusoires (`illusion` = fichier data/enemies/<id>.tres, visuel du kind copié,
## très peu de PV, compétence passive mall_illusion_body : se dissipent au premier coup reçu) en
## cercle autour du joueur, puis devient presque invisible `stealth_time` s et frappe aussitôt :
## on ne sait plus lequel est le vrai.

var _spawned: Array[Enemy] = []
var _done: bool = false
var _stealth_left: float = 0.0


func defaults() -> Dictionary:
	return {"cooldown": 12.0, "initial_cooldown": 3.0, "windup": 0.5, "max_range": 460.0, "count": 2,
		"max_total": 4, "illusion": "mall_clone_illusion", "ring": 150.0, "stealth_time": 1.6,
		"stealth_alpha": 0.22}


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return _alive_count() < int(f("max_total"))


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
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"blink", e.global_position, e.global_position, 30.0, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		_spawn()
		_stealth_left = f("stealth_time")
		e._visual_call(&"set_modulate", [Color(1, 1, 1, f("stealth_alpha"))])
		e.attack_cooldown_left = 0.0
	return true


func _spawn() -> void:
	var center := player_pos()
	var base := (e.global_position - center).angle()
	var n := mini(int(f("count")), int(f("max_total")) - _alive_count())
	for i: int in n:
		var ang := base + TAU * float(i + 1) / float(n + 1)
		var pos := center + Vector2.from_angle(ang) * f("ring")
		if not _free(pos) or not e.has_line_between(center, pos):
			pos = e.global_position + Vector2.from_angle(ang) * 60.0
			if not _free(pos):
				continue
		var r := e.spawn_reinforcement(StringName(str(p["illusion"])), pos)
		if r != null:
			_spawned.append(r)
			e._fx_dust(pos, 2)


func _free(pt: Vector2) -> bool:
	if not e.is_inside_tree():
		return false
	var q := PhysicsPointQueryParameters2D.new()
	q.position = pt
	q.collision_mask = 1
	return e.get_world_2d().direct_space_state.intersect_point(q, 1).is_empty()


func tick_cooldown(dt: float) -> void:
	super.tick_cooldown(dt)
	if _stealth_left > 0.0:
		_stealth_left -= dt
		if _stealth_left <= 0.0 and e != null and e.is_alive():
			e._visual_call(&"set_modulate", [Color.WHITE])


func on_damaged(_amount: float) -> void:
	if _stealth_left > 0.0:
		_stealth_left = minf(_stealth_left, 0.05)
