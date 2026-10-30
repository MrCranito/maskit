extends "res://scripts/enemies/skills/whistle_skill.gd"
## Appel des temples (Archer sable, Prêtre du soleil) : souffle dans une corne / psalmodie
## (télégraphe : cercles sonores, cri « Les temples s'éveillent ! »), alerte les ennemis proches et
## fait arriver `count` renforts `kinds` par la porte la plus proche (comportement du sifflet,
## whistle_skill.gd). Au plus `max_total` renforts vivants. Valeurs : [bestiary_egypt] eg_temple_call_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")


func defaults() -> Dictionary:
	var d := super.defaults()
	d.merge(Bal.defaults("eg_temple_call", {"cooldown": 26.0, "initial_cooldown": 6.0, "windup": 1.0,
		"hp_below": 0.95, "count": 2, "max_total": 3, "kinds": ["eg_skeleton"], "shout": "LES TEMPLES S'ÉVEILLENT !",
		"alert_neighbors": true}), true)
	return d


func start() -> void:
	e.stop()
	_done = false
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])
	e._play_sfx(&"enemy_alert")
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"whistle", e.global_position, Vector2.ZERO, 0.0, windup())
	if b("alert_neighbors"):
		e.alert_neighbors(player_pos())
