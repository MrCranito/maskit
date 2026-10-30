extends EnemySkill
## Passif (Élémentaire de glace) : « se forme à partir de la glace et du vent ». Une fois par vie,
## le coup qui devrait le tuer le laisse à 1 PV : il se fige en bloc de glace (étourdi, invulnérable,
## teinte givrée) pendant `time` s, puis se reforme avec `heal_ratio` de ses PV max. Achever le bloc
## est impossible : il faut le retuer après sa reformation. Valeurs : [bestiary_frozen] reform_*.

const BAL := "bestiary_frozen"
const FROZEN_TINT := Color(0.7, 0.9, 1.0, 0.75)

var used: bool = false
var _left: float = -1.0


func defaults() -> Dictionary:
	return {
		"passive": true,
		"time": Balance.get_float(BAL, "reform_time", 2.2),
		"heal_ratio": Balance.get_float(BAL, "reform_heal_ratio", 0.4),
		"shout": "",
	}


func is_reforming() -> bool:
	return _left > 0.0


func modify_damage(amount: float, _source: Node) -> float:
	if is_reforming():
		return 0.0
	if used or e == null or not e.is_alive() or amount < e.hp:
		return amount
	used = true
	_left = f("time")
	e.invulnerable_left = maxf(e.invulnerable_left, f("time"))
	e.stop()
	if e.state_machine != null:
		e.state_machine.transition_to(Enemy.STATE_STUNNED, {"time": f("time")})
	e._visual_call(&"set_modulate", [FROZEN_TINT])
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])
	e._play_sfx(&"glass_break")
	return maxf(e.hp - 1.0, 0.0)


func tick_cooldown(dt: float) -> void:
	if _left <= 0.0 or e == null:
		return
	_left -= dt
	e.stop()
	if _left <= 0.0 and e.is_alive():
		e.heal(e.max_hp * f("heal_ratio"))
		e._visual_call(&"set_modulate", [Color.WHITE])
		e._visual_call(&"play_ground_slam", [80.0])
		e._fx_dust(e.global_position, 4)
