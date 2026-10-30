extends EnemySkill
## Cercle de feu (Le Clown de feu, le Roi du cirque) : comme le cerceau enflammé des fauves, un
## anneau de `count` foyers (EnemyHazard « fire ») s'allume autour du joueur, avec `gaps` trous pour
## s'échapper. Télégraphe : anneau rouge au sol sur le joueur. Valeurs : [bestiary_carnival] fire_ring_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")

var _center: Vector2 = Vector2.ZERO
var _done: bool = false
var placed: int = 0


func defaults() -> Dictionary:
	return Bal.read("fire_ring", {"cooldown": 12.0, "initial_cooldown": 3.0, "windup": 0.9, "min_range": 0.0,
		"max_range": 560.0, "ring": 170.0, "count": 10.0, "gaps": 2.0, "radius": 46.0, "duration": 4.5,
		"dps": 10.0, "priority": 1.6})


func start() -> void:
	e.stop()
	_done = false
	placed = 0
	_center = player_pos()
	e.face(_center - e.global_position)
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", _center, Vector2.ZERO, f("ring"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		_ignite()
	return t >= windup() + 0.25


func _ignite() -> void:
	var n := maxi(int(f("count")), 3)
	var gaps := clampi(int(f("gaps")), 0, n - 2)
	var start_k := randi() % n
	e._play_sfx(&"blade_swing_heavy")
	for k: int in n:
		# Trous consécutifs pour laisser une sortie.
		if (k - start_k + n) % n < gaps:
			continue
		var a := TAU * float(k) / float(n)
		var pt := _center + Vector2.from_angle(a) * f("ring")
		e.spawn_hazard(&"fire", pt, {"radius": f("radius"), "duration": f("duration"),
			"dps": f("dps") * e.diff_damage_mult})
		placed += 1
