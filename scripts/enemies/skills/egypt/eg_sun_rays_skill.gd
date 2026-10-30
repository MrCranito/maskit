extends EnemySkill
## Rayons du soleil (Pharaon éternel, colère éternelle) : `rays` couloirs rayonnent depuis le
## boss (télégraphe : couloirs au sol), puis les rayons brûlent (dégâts + « burn ») ; `waves`
## salves, chacune décalée d'un demi-angle — il faut se placer entre les rayons, puis bouger.
## Valeurs : [bestiary_egypt] eg_sun_rays_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")
const FX := preload("res://scripts/enemies/skills/egypt/eg_fx.gd")

var _wave: int = 0
var _wave_t: float = 0.0
var _base: float = 0.0
## Joueurs touchés (tests, debug).
var hits: int = 0


func defaults() -> Dictionary:
	return Bal.defaults("eg_sun_rays", {"cooldown": 10.0, "initial_cooldown": 1.0, "windup": 1.1, "need_los": false,
		"max_range": 900.0, "rays": 8, "waves": 2, "length": 640.0, "width": 54.0, "damage": 22.0,
		"burn_time": 2.0, "wave_gap": 0.75, "priority": 2.2})


func start() -> void:
	e.stop()
	_wave = 0
	_wave_t = 0.0
	hits = 0
	_base = (player_pos() - e.global_position).angle()
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._visual_call(&"play_shout", ["LA COLÈRE DE RÂ !"])
	_telegraph(windup())


func _angles(w: int) -> Array[float]:
	var out: Array[float] = []
	var n := maxi(int(f("rays")), 1)
	for i: int in n:
		out.append(_base + TAU * (float(i) + 0.5 * float(w % 2)) / float(n))
	return out


func _telegraph(dur: float) -> void:
	for a: float in _angles(_wave):
		fx(&"lane", e.global_position, e.global_position + Vector2.from_angle(a) * f("length"), f("width"), dur)


func step(dt: float) -> bool:
	e.stop()
	_wave_t += dt
	var gate := windup() if _wave == 0 else f("wave_gap")
	if _wave_t < gate:
		return false
	_fire()
	_wave += 1
	_wave_t = 0.0
	if _wave >= int(f("waves")):
		return true
	_telegraph(f("wave_gap"))
	return false


func _fire() -> void:
	e._visual_call(&"play_strike", [Vector2.ZERO, false])
	e._play_sfx(&"golem_stomp")
	if not e.is_inside_tree():
		return
	var buf: Array[Node2D] = []
	EnemySkills.player_targets(e.get_tree(), buf)
	var dmg := f("damage") * e.diff_damage_mult * e.phase_damage_mult
	var hit_ids := {}
	for a: float in _angles(_wave):
		var to := e.global_position + Vector2.from_angle(a) * f("length")
		if e.get_parent() != null:
			FX.spawn(e.get_parent(), &"beam", e.global_position, f("width"), 0.35, to)
		for pl: Node2D in buf:
			if hit_ids.has(pl.get_instance_id()):
				continue
			var q := Geometry2D.get_closest_point_to_segment(pl.global_position, e.global_position, to)
			if q.distance_to(pl.global_position) <= f("width") * 0.5 + 12.0:
				hit_ids[pl.get_instance_id()] = true
				EnemySkills.hit_player(pl, dmg, e, &"burn", f("burn_time"))
				hits += 1
