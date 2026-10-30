extends "res://scripts/enemies/skills/projectile_skill.gd"
## Ballon piégé (Clown égaré) : lâche un ballon rouge qui dérive lentement vers le joueur (orbe
## rouge lent, longue durée de vie) puis éclate au contact. Ligne de visée pendant le télégraphe.
## Valeurs : [bestiary_carnival] balloon_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")


func defaults() -> Dictionary:
	var d := super.defaults()
	d.merge(Bal.read("balloon", {"cooldown": 7.0, "initial_cooldown": 2.0, "windup": 0.5, "min_range": 120.0,
		"max_range": 420.0, "speed": 230.0, "damage": 8.0, "lifetime": 2.2, "count": 1.0}), true)
	d["style"] = "laser_red"
	return d
