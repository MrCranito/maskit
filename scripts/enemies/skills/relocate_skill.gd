extends EnemySkill
## Tireur embusqué : après chaque tir, se replace vers un AUTRE couvert (au moins min_move px
## plus loin) ; s'il en a la compétence (`trap` = true), pose un piège à ours sur place avant
## de partir (recharge propre trap_cooldown, au plus max_traps actifs).

var pending: bool = false
var _dest: Vector2 = Vector2.ZERO
var _trap_left: float = 0.0
var _traps: Array[EnemyHazard] = []
var _buf: PackedInt32Array = PackedInt32Array()


func defaults() -> Dictionary:
	return {"cooldown": 0.5, "initial_cooldown": 0.0, "windup": 0.15, "need_los": false, "max_time": 2.6,
		"min_move": 140.0, "lateral": 190.0, "trap": false, "trap_cooldown": 9.0, "max_traps": 2,
		"trap_damage": 12.0, "root_time": 1.5, "trap_life": 25.0}


func tick_cooldown(dt: float) -> void:
	super.tick_cooldown(dt)
	if _trap_left > 0.0:
		_trap_left -= dt


func on_attack_done() -> void:
	pending = true


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return pending


func start() -> void:
	pending = false
	var threat := player_pos()
	if b("trap") and _trap_left <= 0.0:
		_drop_trap()
	_dest = _pick_destination(threat)
	fx(&"roll", e.global_position, _dest, 0.0, 0.3)


func _drop_trap() -> void:
	for i: int in range(_traps.size() - 1, -1, -1):
		if not is_instance_valid(_traps[i]):
			_traps.remove_at(i)
	if _traps.size() >= int(f("max_traps")):
		return
	_trap_left = f("trap_cooldown")
	var h := e.spawn_hazard(&"trap", e.global_position, {"damage": f("trap_damage") * e.diff_damage_mult,
		"root_time": f("root_time"), "life": f("trap_life"), "arm_delay": 0.6, "radius": 24.0})
	if h != null:
		_traps.append(h)


func _pick_destination(threat: Vector2) -> Vector2:
	var here := e.global_position
	e._release_cover()
	var map := EnemyTactics.current_map()
	EnemyTactics.find_covers(map, here, threat, e.data.range_min(), e.data.range_max() * 1.15,
		e.cover_max_travel, e.get_instance_id(), 8, _buf)
	for idx: int in _buf:
		var c := map.points[idx]
		if c.distance_to(here) >= f("min_move") and not e.has_line_between(threat, c):
			map.claim(idx, e.get_instance_id())
			e.cover_index = idx
			e.cover_position = c
			return c
	var axis := (here - threat).normalized()
	var side := axis.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
	if e._ray_blocked(side * f("lateral")):
		side = -side
	return here + side * f("lateral")


func step(_dt: float) -> bool:
	if t < windup():
		return false
	if e.is_at(_dest, 18.0) or t > f("max_time"):
		return true
	e.move_toward_position(_dest, e.run_speed() * 1.1)
	return false


func cleanup() -> void:
	e.stop()
