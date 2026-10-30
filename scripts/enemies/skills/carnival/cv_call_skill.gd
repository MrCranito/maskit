extends "res://scripts/enemies/skills/whistle_skill.gd"
## Appel du parc (Manège fantôme, l'Être forain, le Roi du cirque) — comportement commun
## « appellent d'autres créatures » : orgue de barbarie / cri (bulle `shout`, cercles sonores),
## alerte des créatures proches et `count` renforts (`kinds`, créatures du carnaval) qui arrivent
## par la porte la plus proche (sifflet commun, whistle_skill.gd). Au plus `max_total` vivants.
## Valeurs : [bestiary_carnival] call_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")


func defaults() -> Dictionary:
	var d := super.defaults()
	d.merge(Bal.read("call", {"cooldown": 22.0, "initial_cooldown": 4.0, "windup": 1.0, "hp_below": 1.01,
		"count": 2.0, "max_total": 3.0, "door_radius": 900.0, "min_player_dist": 240.0,
		"kinds": ["cv_lost_clown", "cv_circus_dog"]}), true)
	d.merge({"shout": "LA FÊTE CONTINUE !", "fx": "whistle", "ring": 90.0}, true)
	return d


func start() -> void:
	e.stop()
	_done = false
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])
	e._play_sfx(&"enemy_alert")
	fx(StringName(str(p.get("fx", "whistle"))), e.global_position, Vector2.ZERO, f("ring"), windup())
	e.alert_neighbors(player_pos())
