extends EnemySkill
## Saut de foire (Acrobate sanguinaire : salto ; Grosse peluche : plongeon écrasant).
##   mode « behind » : bondit PAR-DESSUS le décor (`over_obstacles` : trajectoire libre, sans
##                     collision, comme s'il courait sur les structures) et retombe DERRIÈRE le
##                     joueur, intouchable pendant le vol, attaque prête à l'atterrissage ;
##   mode « on »     : saute sur la position prévue du joueur et l'écrase (dégâts de zone + statut).
## Télégraphe : cercle rouge à l'atterrissage. Valeurs : [bestiary_carnival] vault_* (+ .tres).

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _land_t: float = -1.0
var _last_pos: Vector2 = Vector2.ZERO


func defaults() -> Dictionary:
	var d := Bal.read("vault", {"cooldown": 7.0, "initial_cooldown": 2.0, "windup": 0.5, "min_range": 120.0,
		"max_range": 380.0, "flight": 0.45, "radius": 60.0, "damage": 10.0, "status_time": 0.0, "behind": 80.0,
		"iframes": 1.0, "recover": 0.25, "lead": 0.3})
	d.merge({"mode": "behind", "status": "", "over_obstacles": true}, true)
	return d


func _landing() -> Vector2:
	var pp := e.predict_player_position(windup() * f("lead"))
	var from := e.global_position
	var to := pp
	if str(p.get("mode", "behind")) == "behind":
		var dir := (pp - from).normalized() if pp.distance_to(from) > 1.0 else Vector2.RIGHT
		for rot: float in [0.0, 0.5, -0.5, 1.0, -1.0]:
			var c := pp + dir.rotated(rot) * f("behind")
			if _free(c):
				return c
		to = pp - dir * 30.0
	if from.distance_to(to) > f("max_range") + f("behind"):
		to = from + (to - from).normalized() * (f("max_range") + f("behind"))
	return to


func _free(pt: Vector2) -> bool:
	if not e.is_inside_tree():
		return true
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = maxf(e.data.body_radius, 8.0)
	q.shape = c
	q.transform = Transform2D(0.0, pt)
	q.collision_mask = 1
	return e.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func start() -> void:
	e.stop()
	_from = e.global_position
	_to = _landing()
	_land_t = -1.0
	_last_pos = _from
	e.face(_to - _from)
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", _to, Vector2.ZERO, f("radius"), windup() + f("flight"))


func step(dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if _land_t < 0.0:
		var ft := t - windup()
		if ft < f("flight") * f("iframes"):
			e.invulnerable_left = maxf(e.invulnerable_left, dt * 2.0)
		if ft < f("flight"):
			var u := clampf(ft / maxf(f("flight"), 0.05), 0.0, 1.0)
			if b("over_obstacles"):
				e.stop()
				e.global_position = _from.lerp(_to, u)
				return false
			var moved := e.global_position.distance_to(_last_pos)
			if not (ft > 0.1 and moved < 0.5) and e.global_position.distance_to(_to) > 12.0:
				e.dash((_to - e.global_position).normalized(), _from.distance_to(_to) / maxf(f("flight"), 0.05))
				_last_pos = e.global_position
				return false
		if b("over_obstacles"):
			e.global_position = _to
		_land()
		_land_t = t
	e.stop()
	return t >= _land_t + f("recover")


func _land() -> void:
	e.stop()
	e._visual_call(&"play_ground_slam", [f("radius")])
	e._fx_dust(e.global_position, 3)
	e._play_sfx(&"blade_swing_heavy")
	e.face(player_pos() - e.global_position)
	if str(p.get("mode", "behind")) == "behind":
		e.attack_cooldown_left = 0.0
	if e.is_inside_tree() and f("damage") > 0.0:
		EnemySkills.hit_players_in_radius(e.get_tree(), e.global_position, f("radius"), f("damage") * e.diff_damage_mult,
			e, StringName(str(p.get("status", ""))), f("status_time"))


func cleanup() -> void:
	e.stop()
