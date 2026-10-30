extends EnemySkill
## Pluie de stalactites (Titan de glace) : le Titan lève les bras ; `count` cercles de danger
## apparaissent — un sur la position prévue du joueur, les autres dispersés autour (`scatter` px).
## Après `delay` s (cascade de `stagger` s), des blocs de glace tombent : dégâts + statut « slow ».
## Valeurs : [bestiary_frozen] icefall_*.

const BAL := "bestiary_frozen"
const SHARDS := preload("res://scripts/enemies/skills/frozen/ice_shards.gd")

var _done: bool = false


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "icefall_cooldown", 11.0),
		"initial_cooldown": Balance.get_float(BAL, "icefall_initial_cooldown", 3.0),
		"windup": Balance.get_float(BAL, "icefall_windup", 0.6),
		"max_range": Balance.get_float(BAL, "icefall_max_range", 900.0),
		"count": Balance.get_float(BAL, "icefall_count", 6.0),
		"scatter": Balance.get_float(BAL, "icefall_scatter", 220.0),
		"radius": Balance.get_float(BAL, "icefall_radius", 70.0),
		"delay": Balance.get_float(BAL, "icefall_delay", 1.0),
		"stagger": Balance.get_float(BAL, "icefall_stagger", 0.12),
		"damage": Balance.get_float(BAL, "icefall_damage", 20.0),
		"slow": Balance.get_float(BAL, "icefall_slow", 0.45),
		"slow_time": Balance.get_float(BAL, "icefall_slow_time", 1.8),
		"need_los": false, "lead": 0.6, "priority": 1.7, "shout": "",
	}


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_attack_windup", [windup(), false])
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])


func step(_dt: float) -> bool:
	e.stop()
	if t < windup():
		return false
	if not _done:
		_done = true
		_drop()
	return t >= windup() + 0.2


## Points d'impact : le premier sur la position prévue du joueur, les autres en couronne irrégulière.
func impact_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var center := e.predict_player_position(f("delay") * f("lead"))
	pts.append(center)
	var n := maxi(int(f("count")), 1)
	for i: int in range(1, n):
		var ang := TAU * float(i) / float(n - 1) + randf_range(-0.35, 0.35)
		pts.append(center + Vector2.from_angle(ang) * f("scatter") * randf_range(0.45, 1.0))
	return pts


func _drop() -> void:
	if not e.is_inside_tree():
		return
	var parent: Node = e.get_parent() if e.get_parent() != null else e.get_tree().current_scene
	e._play_sfx(&"golem_growl")
	SHARDS.spawn(parent, impact_points(), {"radius": f("radius"), "delay": f("delay"), "stagger": f("stagger"),
		"status": "slow", "status_time": f("slow_time"), "strength": f("slow"),
		"damage": f("damage") * e.diff_damage_mult * e.phase_damage_mult}, e)
