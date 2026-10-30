extends EnemySkill
## Tir cryogénique (Chasseur arctique ; canon du Mécanicien) : épaule (télégraphe : couloir de visée
## vers la position prévue du joueur), puis tire `count` traits cryogéniques (ice_bolt.gd) en éventail
## de `spread_deg` : dégâts + statut « slow » (et « root » si `root_time` > 0). Arrêtés par les murs.
## Valeurs : [bestiary_frozen] cryo_*.

const BAL := "bestiary_frozen"
const BOLT := preload("res://scripts/enemies/skills/frozen/ice_bolt.gd")

var _aim: Vector2 = Vector2.RIGHT
var _fired: bool = false


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "cryo_cooldown", 6.0),
		"initial_cooldown": Balance.get_float(BAL, "cryo_initial_cooldown", 2.0),
		"windup": Balance.get_float(BAL, "cryo_windup", 0.6),
		"min_range": Balance.get_float(BAL, "cryo_min_range", 80.0),
		"max_range": Balance.get_float(BAL, "cryo_max_range", 620.0),
		"speed": Balance.get_float(BAL, "cryo_speed", 760.0),
		"damage": Balance.get_float(BAL, "cryo_damage", 12.0),
		"lifetime": Balance.get_float(BAL, "cryo_lifetime", 1.1),
		"slow": Balance.get_float(BAL, "cryo_slow", 0.5),
		"slow_time": Balance.get_float(BAL, "cryo_slow_time", 2.0),
		"root_time": Balance.get_float(BAL, "cryo_root_time", 0.0),
		"count": 1.0, "spread_deg": 0.0, "lead": 0.35, "lane_width": 34.0, "priority": 1.4,
	}


func start() -> void:
	e.stop()
	_fired = false
	var target := e.predict_player_position(windup() * f("lead"))
	_aim = (target - e.global_position).normalized() if target.distance_to(e.global_position) > 1.0 else e.facing
	e.face(_aim)
	e._visual_call(&"play_attack_windup", [windup(), true])
	fx(&"lane", e.global_position, e.global_position + _aim * f("max_range"), f("lane_width"), windup())


func step(_dt: float) -> bool:
	e.stop()
	if t < windup():
		e.face(_aim)
		return false
	if not _fired:
		_fired = true
		_fire()
	return t >= windup() + 0.15


func _fire() -> void:
	if not e.is_inside_tree():
		return
	var parent: Node = e.get_parent() if e.get_parent() != null else e.get_tree().current_scene
	var n := maxi(int(f("count")), 1)
	var params := p.duplicate()
	params["damage"] = f("damage") * e.diff_damage_mult * e.phase_damage_mult
	var muzzle := e.global_position + _aim * (e.data.body_radius + 8.0)
	for i: int in n:
		var off := 0.0 if n == 1 else (float(i) / float(n - 1) - 0.5) * deg_to_rad(f("spread_deg"))
		BOLT.spawn(parent, muzzle, _aim.rotated(off), params, e)
	e._visual_call(&"play_strike", [_aim, true, n > 1])
	e._play_sfx(&"rifle_shot")
