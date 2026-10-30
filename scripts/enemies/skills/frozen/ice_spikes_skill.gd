extends EnemySkill
## Pics de glace (Gardien des glaces, Titan) : frappe le sol, `count` lignes de pics partent vers la
## position prévue du joueur (éventail de `spread_deg`). Télégraphe : couloirs + cercles au sol ; les
## pics jaillissent en cascade du lanceur vers l'extrémité (`stagger` s entre deux pics) : dégâts +
## statut « root » (pris dans la glace). Valeurs : [bestiary_frozen] spikes_*.

const BAL := "bestiary_frozen"
const SHARDS := preload("res://scripts/enemies/skills/frozen/ice_shards.gd")

var _aim: Vector2 = Vector2.RIGHT
var _done: bool = false


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "spikes_cooldown", 8.0),
		"initial_cooldown": Balance.get_float(BAL, "spikes_initial_cooldown", 2.0),
		"windup": Balance.get_float(BAL, "spikes_windup", 0.7),
		"min_range": Balance.get_float(BAL, "spikes_min_range", 60.0),
		"max_range": Balance.get_float(BAL, "spikes_max_range", 560.0),
		"count": Balance.get_float(BAL, "spikes_count", 1.0),
		"spread_deg": Balance.get_float(BAL, "spikes_spread_deg", 30.0),
		"length": Balance.get_float(BAL, "spikes_length", 520.0),
		"spacing": Balance.get_float(BAL, "spikes_spacing", 58.0),
		"radius": Balance.get_float(BAL, "spikes_radius", 40.0),
		"delay": Balance.get_float(BAL, "spikes_delay", 0.35),
		"stagger": Balance.get_float(BAL, "spikes_stagger", 0.035),
		"damage": Balance.get_float(BAL, "spikes_damage", 16.0),
		"root_time": Balance.get_float(BAL, "spikes_root_time", 0.8),
		"need_los": false, "lead": 0.4, "priority": 1.5, "shout": "",
	}


func start() -> void:
	e.stop()
	_done = false
	var target := e.predict_player_position(windup() * f("lead"))
	_aim = (target - e.global_position).normalized() if target.distance_to(e.global_position) > 1.0 else e.facing
	e.face(_aim)
	e._visual_call(&"play_attack_windup", [windup(), false])
	for d: Vector2 in _dirs():
		fx(&"lane", e.global_position, e.global_position + d * f("length"), f("radius") * 2.0, windup())
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])


func _dirs() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := maxi(int(f("count")), 1)
	for i: int in n:
		var off := 0.0 if n == 1 else (float(i) / float(n - 1) - 0.5) * deg_to_rad(f("spread_deg"))
		out.append(_aim.rotated(off))
	return out


func step(_dt: float) -> bool:
	e.stop()
	if t < windup():
		return false
	if not _done:
		_done = true
		_erupt()
	return t >= windup() + 0.25


func _erupt() -> void:
	if not e.is_inside_tree():
		return
	var parent: Node = e.get_parent() if e.get_parent() != null else e.get_tree().current_scene
	e._visual_call(&"play_ground_slam", [f("radius") * 2.0])
	e._play_sfx(&"golem_stomp")
	var params := {"radius": f("radius"), "delay": f("delay"), "stagger": f("stagger"), "status": "root",
		"status_time": f("root_time"), "damage": f("damage") * e.diff_damage_mult * e.phase_damage_mult}
	for d: Vector2 in _dirs():
		var pts := PackedVector2Array()
		var k := 1
		while f("spacing") * float(k) <= f("length"):
			var pt := e.global_position + d * f("spacing") * float(k)
			if not e.has_line_between(e.global_position, pt):
				break
			pts.append(pt)
			k += 1
		if not pts.is_empty():
			SHARDS.spawn(parent, pts, params, e)
