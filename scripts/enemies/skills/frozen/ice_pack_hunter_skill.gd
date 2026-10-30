extends EnemySkill
## Passif (Loup des glaces) : chasse en meute. Chaque congénère vivant (`pack_kinds`) à moins de
## `radius` px augmente ses dégâts (+`damage_per_ally`) et sa vitesse (+`speed_per_ally`), au plus
## `max_allies` congénères comptés. Recalcul toutes les `interval` s, sans allocation.
## Valeurs : [bestiary_frozen] pack_*.

const BAL := "bestiary_frozen"

## Congénères comptés au dernier calcul (tests, debug F3).
var pack_size: int = 0
var _left: float = 0.0
var _dmg_factor: float = 1.0
var _spd_factor: float = 1.0


func defaults() -> Dictionary:
	return {
		"passive": true,
		"radius": Balance.get_float(BAL, "pack_radius", 320.0),
		"damage_per_ally": Balance.get_float(BAL, "pack_damage_per_ally", 0.12),
		"speed_per_ally": Balance.get_float(BAL, "pack_speed_per_ally", 0.05),
		"max_allies": Balance.get_float(BAL, "pack_max_allies", 3.0),
		"interval": Balance.get_float(BAL, "pack_interval", 0.5),
		"pack_kinds": ["ice_wolf"],
	}


func tick_cooldown(dt: float) -> void:
	super.tick_cooldown(dt)
	_left -= dt
	if _left > 0.0:
		return
	_left = f("interval")
	refresh()


## Recompte la meute et applique les bonus (multiplicateurs de difficulté de l'ennemi).
func refresh() -> void:
	if e == null or not e.is_inside_tree():
		return
	var kinds: Array = p.get("pack_kinds", [])
	var r2 := f("radius") * f("radius")
	var n := 0
	if e.is_alive():
		for node: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
			var u := node as Enemy
			if u == null or u == e or not u.is_alive() or u.data == null:
				continue
			if not kinds.has(String(u.data.kind)) and not kinds.has(u.data.kind):
				continue
			if u.global_position.distance_squared_to(e.global_position) <= r2:
				n += 1
	pack_size = mini(n, int(f("max_allies")))
	var dmg := 1.0 + f("damage_per_ally") * float(pack_size)
	var spd := 1.0 + f("speed_per_ally") * float(pack_size)
	e.diff_damage_mult = e.diff_damage_mult / _dmg_factor * dmg
	e.diff_speed_mult = e.diff_speed_mult / _spd_factor * spd
	_dmg_factor = dmg
	_spd_factor = spd
