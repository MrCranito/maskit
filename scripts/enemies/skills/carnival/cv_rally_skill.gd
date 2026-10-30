extends EnemySkill
## Boniment du maître de piste (L'Être forain) : « protège ses zones d'attraction ». Lève sa canne
## (anneau doré au sol), puis chaque créature du parc dans `radius` (lui compris) reçoit
## l'aura du forain (`cv_rallied`) pendant `duration` s : dégâts subis réduits de `reduction`,
## vitesse × `speed_mult`, et `heal` PV rendus. Valeurs : [bestiary_carnival] rally_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")

var rallied: int = 0
var _done: bool = false


func defaults() -> Dictionary:
	return Bal.read("rally", {"cooldown": 15.0, "initial_cooldown": 3.0, "windup": 0.7, "max_range": 700.0,
		"radius": 420.0, "duration": 5.0, "reduction": 0.35, "speed_mult": 1.2, "heal": 25.0, "need_los": false,
		"priority": 1.7})


func start() -> void:
	e.stop()
	_done = false
	rallied = 0
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._visual_call(&"play_shout", [str(p.get("shout", "MESDAMES ET MESSIEURS !"))])
	fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		_rally()
	return t >= windup() + 0.2


func _rally() -> void:
	if not e.is_inside_tree():
		return
	var r2 := f("radius") * f("radius")
	for n: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
		var o := n as Enemy
		if o == null or not o.is_alive() or o.net_puppet:
			continue
		if o.global_position.distance_squared_to(e.global_position) > r2:
			continue
		var aura := o.get_skill(&"cv_rallied")
		if aura == null:
			var built := EnemySkills.build_entries(o, [{"id": &"cv_rallied"}], o.data.kind)
			if built.is_empty():
				continue
			aura = built[0]
			o.skills.append(aura)
		aura.call(&"grant", f("duration"), f("reduction"), f("speed_mult"))
		o.heal(f("heal"))
		if o != e and not o.is_in_combat():
			o.become_aware(player_pos(), false)
		rallied += 1
