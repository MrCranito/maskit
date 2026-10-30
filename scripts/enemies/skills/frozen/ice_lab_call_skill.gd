extends "res://scripts/enemies/skills/whistle_skill.gd"
## Renforts des laboratoires (Drone de froid, Chasseur arctique, Mécanicien, Titan) : balise cyan
## (télégraphe « whistle »), message au-dessus de la tête, alerte les ennemis proches, puis `count`
## renforts (`kinds`) arrivent par la porte la plus proche (comportement du sifflet commun,
## whistle_skill.gd). Au plus `max_total` renforts vivants par lanceur.
## Valeurs : [bestiary_frozen] lab_call_*.

const BAL := "bestiary_frozen"


func defaults() -> Dictionary:
	var d := super.defaults()
	d.merge({
		"cooldown": Balance.get_float(BAL, "lab_call_cooldown", 26.0),
		"initial_cooldown": Balance.get_float(BAL, "lab_call_initial_cooldown", 5.0),
		"windup": Balance.get_float(BAL, "lab_call_windup", 1.0),
		"hp_below": Balance.get_float(BAL, "lab_call_hp_below", 0.85),
		"count": Balance.get_float(BAL, "lab_call_count", 1.0),
		"max_total": Balance.get_float(BAL, "lab_call_max_total", 2.0),
		"kinds": ["ice_hunter"], "shout": "RENFORTS DU LABO !", "fx": "whistle", "ring": 80.0,
		"alert_neighbors": true,
	}, true)
	return d


func start() -> void:
	e.stop()
	_done = false
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])
	e._play_sfx(&"enemy_alert")
	fx(StringName(str(p.get("fx", "whistle"))), e.global_position, Vector2.ZERO, f("ring"), windup())
	if b("alert_neighbors"):
		e.alert_neighbors(player_pos())
