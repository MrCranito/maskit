extends EnemySkill
## Passif (chef de bande) : rage sous `threshold` des PV — cri, aura rouge, vitesse × speed_mult,
## temps de recharge × cooldown_mult (attaques et compétences).

var triggered: bool = false


func defaults() -> Dictionary:
	return {"passive": true, "threshold": 0.3, "speed_mult": 1.35, "cooldown_mult": 0.6}


func on_damaged(_amount: float) -> void:
	if triggered or e.hp > e.max_hp * f("threshold") or not e.is_alive():
		return
	triggered = true
	e.rage_speed_mult = f("speed_mult")
	e.rage_cooldown_mult = f("cooldown_mult")
	e.shout(&"phase2", true)
	fx(&"rage", e.global_position, Vector2.ZERO, 0.0, 999.0)
