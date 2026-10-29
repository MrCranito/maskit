extends "res://scripts/enemies/skills/whistle_skill.gd"
## Alarme du centre commercial (Sécurité robot, Gardien de magasin, appel des consommables de
## l'Omnistore) : gyrophare rouge (télégraphe « beep »), message au-dessus de la tête, alerte les
## ennemis proches et fait arriver `count` renforts (`kinds`) par la porte la plus proche
## (comportement du sifflet, whistle_skill.gd). Au plus `max_total` renforts vivants.


func defaults() -> Dictionary:
	var d := super.defaults()
	d.merge({"cooldown": 24.0, "initial_cooldown": 5.0, "windup": 1.0, "hp_below": 1.01, "count": 2,
		"max_total": 4, "kinds": ["mall_zombie"], "shout": "ALERTE !", "fx": "beep", "ring": 60.0,
		"alert_neighbors": true}, true)
	return d


func start() -> void:
	e.stop()
	_done = false
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])
	e._play_sfx(&"enemy_alert")
	fx(StringName(str(p.get("fx", "beep"))), e.global_position, Vector2.ZERO, f("ring"), windup())
	if b("alert_neighbors"):
		e.alert_neighbors(player_pos())
