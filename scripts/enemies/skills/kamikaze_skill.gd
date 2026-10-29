extends EnemySkill
## Drone kamikaze : bip et clignotement rouge (télégraphe), puis fonce sur le joueur et explose
## au contact (ou au bout de max_time). Le drone est détruit par sa propre explosion.

var _exploded: bool = false


func defaults() -> Dictionary:
	return {"cooldown": 999.0, "initial_cooldown": 0.5, "windup": 0.75, "max_range": 260.0, "speed": 430.0,
		"max_time": 1.4, "trigger": 46.0, "radius": 90.0, "damage": 24.0}


func start() -> void:
	e.stop()
	_exploded = false
	e._play_sfx(&"tick")
	fx(&"beep", e.global_position, Vector2.ZERO, f("radius"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	var pp := player_pos()
	if e.global_position.distance_to(pp) <= f("trigger") or t >= windup() + f("max_time"):
		_explode()
		return true
	e.dash((pp - e.global_position).normalized(), f("speed"))
	return false


func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	e.stop()
	e.spawn_hazard(&"blast", e.global_position, {"radius": f("radius"), "damage": f("damage") * e.diff_damage_mult})
	e.self_destruct()
