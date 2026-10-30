extends EnemySkill
## Réparation (Mécanicien de l'Éternité) : « répare et renforce les machines de la base ». Il
## s'immobilise (télégraphe : anneau cyan), puis tous les alliés vivants dans `radius` — lui compris —
## récupèrent `heal_ratio` de leurs PV max (lui : `self_heal_ratio`) et sont renforcés pendant
## `buff_time` s : dégâts × (1 + `buff_damage`). Utilisable seulement si un allié est blessé sous
## `need_ratio`. Valeurs : [bestiary_frozen] repair_*.

const BAL := "bestiary_frozen"

## Alliés renforcés → facteur appliqué (retiré à l'expiration).
var _buffed: Dictionary = {}
var _buff_left: float = 0.0
var _done: bool = false
## Nombre d'alliés soignés au dernier usage (tests, debug F3).
var last_healed: int = 0


func defaults() -> Dictionary:
	return {
		"cooldown": Balance.get_float(BAL, "repair_cooldown", 12.0),
		"initial_cooldown": Balance.get_float(BAL, "repair_initial_cooldown", 3.0),
		"windup": Balance.get_float(BAL, "repair_windup", 1.0),
		"radius": Balance.get_float(BAL, "repair_radius", 360.0),
		"heal_ratio": Balance.get_float(BAL, "repair_heal_ratio", 0.3),
		"self_heal_ratio": Balance.get_float(BAL, "repair_self_heal_ratio", 0.12),
		"need_ratio": Balance.get_float(BAL, "repair_need_ratio", 0.8),
		"buff_damage": Balance.get_float(BAL, "repair_buff_damage", 0.25),
		"buff_time": Balance.get_float(BAL, "repair_buff_time", 6.0),
		"need_los": false, "priority": 1.9, "shout": "RÉPARATION !",
	}


func _allies(out: Array[Enemy]) -> void:
	out.clear()
	if e == null or not e.is_inside_tree():
		return
	var r2 := f("radius") * f("radius")
	for node: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
		var u := node as Enemy
		if u != null and u.is_alive() and u.global_position.distance_squared_to(e.global_position) <= r2:
			out.append(u)


func can_use_extra(_dist: float, _sees: bool) -> bool:
	var allies: Array[Enemy] = []
	_allies(allies)
	for u: Enemy in allies:
		if u.hp < u.max_hp * f("need_ratio"):
			return true
	return false


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_attack_windup", [windup(), false])
	fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), windup())
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])


func step(_dt: float) -> bool:
	e.stop()
	if t < windup():
		return false
	if not _done:
		_done = true
		_repair()
	return t >= windup() + 0.2


func _repair() -> void:
	_clear_buffs()
	var allies: Array[Enemy] = []
	_allies(allies)
	last_healed = 0
	var k := 1.0 + f("buff_damage")
	for u: Enemy in allies:
		u.heal(u.max_hp * (f("self_heal_ratio") if u == e else f("heal_ratio")))
		u._visual_call(&"flash_hit")
		last_healed += 1
		if u != e:
			u.diff_damage_mult *= k
			_buffed[u] = k
	_buff_left = f("buff_time")
	e._play_sfx(&"item_equip")


func _clear_buffs() -> void:
	for u: Variant in _buffed:
		if is_instance_valid(u):
			(u as Enemy).diff_damage_mult /= float(_buffed[u])
	_buffed.clear()


## Alliés actuellement renforcés (tests).
func buffed_count() -> int:
	return _buffed.size()


func tick_cooldown(dt: float) -> void:
	super.tick_cooldown(dt)
	if _buff_left > 0.0:
		_buff_left -= dt
		if _buff_left <= 0.0:
			_clear_buffs()
