extends EnemySkill
## Embuscade sous le sable (Lézard des sables, Vipère des sables) : s'enfouit (télégraphe :
## nuage de sable), file sous le sable vers le joueur (quasi invisible, intouchable, barre de vie
## masquée), puis un cercle de danger trahit sa sortie et il jaillit : dégâts de zone (+ statut,
## + venin pour la vipère). Valeurs : [bestiary_egypt] eg_burrow_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")
const FX := preload("res://scripts/enemies/skills/egypt/eg_fx.gd")

enum Phase { DIG, TRAVEL, EMERGE, DONE }

var phase: int = Phase.DIG
var _phase_t: float = 0.0
var _dust: float = 0.0
var _hidden: bool = false


func defaults() -> Dictionary:
	return Bal.defaults("eg_burrow", {"cooldown": 10.0, "initial_cooldown": 3.0, "windup": 0.5, "min_range": 150.0,
		"max_range": 520.0, "speed": 300.0, "travel_time": 1.6, "emerge_windup": 0.45, "near": 36.0,
		"radius": 70.0, "damage": 14.0, "status": "", "status_time": 0.0, "alpha": 0.12, "venom": false,
		"venom_dps": 3.0, "venom_time": 3.0, "venom_slow": 0.2, "venom_max_stacks": 3})


func start() -> void:
	e.stop()
	phase = Phase.DIG
	_phase_t = 0.0
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._fx_dust(e.global_position, 4)
	_spawn_fx(&"sand", e.global_position, 50.0, windup())


func step(dt: float) -> bool:
	_phase_t += dt
	match phase:
		Phase.DIG:
			e.stop()
			if t >= windup():
				_hide(true)
				phase = Phase.TRAVEL
				_phase_t = 0.0
		Phase.TRAVEL:
			e.invulnerable_left = maxf(e.invulnerable_left, dt * 2.0)
			var target := player_pos()
			e.move_toward_position(target, f("speed"))
			_dust -= dt
			if _dust <= 0.0:
				_dust = 0.15
				e._fx_dust(e.global_position, 1)
			if e.global_position.distance_to(target) <= f("near") or _phase_t >= f("travel_time"):
				e.stop()
				phase = Phase.EMERGE
				_phase_t = 0.0
				fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), f("emerge_windup"))
				_spawn_fx(&"sand", e.global_position, f("radius"), f("emerge_windup"))
		Phase.EMERGE:
			e.invulnerable_left = maxf(e.invulnerable_left, dt * 2.0)
			e.stop()
			if _phase_t >= f("emerge_windup") * e.diff_windup_mult:
				_erupt()
				phase = Phase.DONE
				_phase_t = 0.0
		Phase.DONE:
			e.stop()
			return _phase_t >= 0.25
	return false


func _erupt() -> void:
	_hide(false)
	e._visual_call(&"play_ground_slam", [f("radius")])
	e._fx_dust(e.global_position, 5)
	e._play_sfx(&"blade_swing_heavy")
	if not e.is_inside_tree():
		return
	var dmg := f("damage") * e.diff_damage_mult * e.phase_damage_mult
	var st := StringName(str(p.get("status", "")))
	EnemySkills.hit_players_in_radius(e.get_tree(), e.global_position, f("radius"), dmg, e, st, f("status_time"))
	if b("venom"):
		var buf: Array[Node2D] = []
		EnemySkills.player_targets(e.get_tree(), buf)
		for pl: Node2D in buf:
			if pl.global_position.distance_to(e.global_position) <= f("radius"):
				EgVenomDot.apply(pl, p, e)


func _hide(on: bool) -> void:
	_hidden = on
	if on:
		e.invulnerable_left = maxf(e.invulnerable_left, 0.1)
	e._visual_call(&"set_modulate", [Color(1, 1, 1, f("alpha")) if on else Color.WHITE])
	if e._health_bar != null:
		e._health_bar.visible = not on and e.is_alive()


func _spawn_fx(style: StringName, pos: Vector2, r: float, dur: float) -> void:
	if e.is_inside_tree() and e.get_parent() != null:
		FX.spawn(e.get_parent(), style, pos, r, dur)


func is_burrowed() -> bool:
	return _hidden


func cleanup() -> void:
	if _hidden:
		_hide(false)
	e.stop()
