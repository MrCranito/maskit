extends EnemySkill
## Passif (loups, araignée, ours, élémentaire…) : morsure / coup gelé. Quand l'attaque de base part
## (fin du coup, `notify_attack_done`), un joueur encore à portée du coup (mêlée : portée + tolérance ;
## frappe de zone : `aoe_radius`) est ralenti (statut « slow » `slow` pendant `slow_time` s).
## Valeurs : [bestiary_frozen] chill_*.

const BAL := "bestiary_frozen"

## Nombre de joueurs gelés (tests, debug F3).
var chilled: int = 0


func defaults() -> Dictionary:
	return {
		"passive": true,
		"slow": Balance.get_float(BAL, "chill_slow", 0.3),
		"slow_time": Balance.get_float(BAL, "chill_slow_time", 1.4),
		"reach_bonus": Balance.get_float(BAL, "chill_reach_bonus", 12.0),
	}


func reach() -> float:
	if e.data.is_area_attack():
		return e.data.aoe_radius + f("reach_bonus")
	return e.data.attack_range + e.melee_hit_tolerance + f("reach_bonus")


func on_attack_done() -> void:
	if e == null or not e.is_alive() or not e.is_inside_tree():
		return
	var targets: Array[Node2D] = []
	EnemySkills.player_targets(e.get_tree(), targets)
	for pl: Node2D in targets:
		if pl.global_position.distance_to(e.global_position) <= reach():
			EnemySkills.hit_player(pl, 0.0, e, &"slow", f("slow_time"), f("slow"))
			chilled += 1
