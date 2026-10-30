extends EnemySkill
## Venin (passif, Vipère des sables) : chaque morsure (attaque de base) qui atteint le joueur
## l'empoisonne (eg_venom_dot.gd : dégâts par seconde, ralentissement, doses cumulables).
## Valeurs : [bestiary_egypt] eg_venom_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")


func defaults() -> Dictionary:
	return Bal.defaults("eg_venom", {"passive": true, "venom_dps": 3.0, "venom_time": 3.5, "venom_slow": 0.2,
		"venom_max_stacks": 3, "reach_bonus": 16.0})


func on_attack_done() -> void:
	if e == null:
		return
	var pl := player()
	if pl == null:
		return
	if e.global_position.distance_to(pl.global_position) <= e.data.attack_range + f("reach_bonus"):
		EgVenomDot.apply(pl, p, e)
