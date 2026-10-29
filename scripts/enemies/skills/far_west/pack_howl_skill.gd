extends "res://scripts/enemies/skills/whistle_skill.gd"
## Maraudeur : hurlement de meute. Tous les congénères (`pack_kinds`) dans `howl_radius` px
## rejoignent la chasse (position du joueur) ; si la meute proche compte moins de `min_pack`
## bêtes, `count` maraudeurs surgissent (porte la plus proche ou derrière le hurleur, cf. sifflet),
## au plus `max_total` vivants par hurleur. Valeurs : [bestiary_far_west] pack_howl_*.

const BAL := "bestiary_far_west"

var last_joined: int = 0


func defaults() -> Dictionary:
	var d: Dictionary = super.defaults()
	d.merge({
		"cooldown": Balance.get_float(BAL, "pack_howl_cooldown", 26.0),
		"initial_cooldown": Balance.get_float(BAL, "pack_howl_initial_cooldown", 1.5),
		"windup": Balance.get_float(BAL, "pack_howl_windup", 0.7),
		"hp_below": 1.01,
		"howl_radius": Balance.get_float(BAL, "pack_howl_radius", 900.0),
		"pack_radius": Balance.get_float(BAL, "pack_howl_pack_radius", 320.0),
		"min_pack": Balance.get_float(BAL, "pack_howl_min_pack", 2.0),
		"count": Balance.get_float(BAL, "pack_howl_count", 1.0),
		"max_total": Balance.get_float(BAL, "pack_howl_max_total", 2.0),
		"kinds": ["fw_marauder"], "pack_kinds": ["fw_marauder"], "text": "Aouuuh !",
	}, true)
	return d


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_shout", [String(p.get("text", "Aouuuh !"))])
	e._play_sfx(&"enemy_alert")
	fx(&"whistle", e.global_position, Vector2.ZERO, f("howl_radius"), windup())


func step(dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		var target := player_pos()
		last_joined = 0
		var near := 0
		var kinds: Array = p.get("pack_kinds", [])
		if e.is_inside_tree():
			for node: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
				var u := node as Enemy
				if u == null or u == e or not u.is_alive() or u.data == null or not kinds.has(String(u.data.kind)):
					continue
				var d := u.global_position.distance_to(e.global_position)
				if d <= f("howl_radius"):
					if u.asleep:
						u.wake_up()
					u.become_aware(target, false)
					last_joined += 1
				if d <= f("pack_radius"):
					near += 1
		if near >= int(f("min_pack")):
			_done = true  # meute déjà au complet : pas de renfort
			return t >= windup() + 0.2
	return super.step(dt)
