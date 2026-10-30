extends EnemySkill
## Bénédiction solaire (Prêtre du soleil : soutien de zone) : lève le bâton (télégraphe : halo
## doré), puis chaque allié dans `radius` (lui compris) est soigné de `heal_ratio` de ses PV max
## et galvanisé `duration` s (vitesse × `speed_mult`, recharge des attaques × `cooldown_mult`).
## Utilisée seulement si un allié blessé (sous `ally_hp_below`) ou au moins `min_allies` alliés
## sont à portée. Valeurs : [bestiary_egypt] eg_solar_blessing_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")
const FX := preload("res://scripts/enemies/skills/egypt/eg_fx.gd")

## Alliés bénis au dernier lancer (tests, debug).
var blessed: Array[Enemy] = []
var _done: bool = false


func defaults() -> Dictionary:
	return Bal.defaults("eg_solar_blessing", {"cooldown": 12.0, "initial_cooldown": 3.0, "windup": 0.8,
		"need_los": false, "radius": 300.0, "heal_ratio": 0.2, "duration": 5.0, "speed_mult": 1.25,
		"cooldown_mult": 0.75, "ally_hp_below": 0.8, "min_allies": 2, "priority": 1.8})


func _allies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	if e == null or not e.is_inside_tree():
		return out
	for n: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_ENEMIES):
		var a := n as Enemy
		if a == null or not a.is_alive() or a.data == null or a.data.boss and a != e:
			continue
		if a.global_position.distance_to(e.global_position) <= f("radius"):
			out.append(a)
	return out


func can_use_extra(_dist: float, _sees: bool) -> bool:
	var allies := _allies()
	if allies.size() >= int(f("min_allies")) + 1:
		return true
	for a: Enemy in allies:
		if a.hp < a.max_hp * f("ally_hp_below"):
			return true
	return false


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._visual_call(&"play_shout", ["Ô RÂ, BÉNIS-NOUS !"])
	if e.get_parent() != null:
		FX.spawn(e.get_parent(), &"sun", e.global_position, f("radius"), windup() + 0.4)


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		_bless()
	return t >= windup() + 0.25


func _bless() -> void:
	blessed = _allies()
	e._visual_call(&"play_strike", [Vector2.ZERO, false])
	var tree := e.get_tree()
	for a: Enemy in blessed:
		a.heal(a.max_hp * f("heal_ratio"))
		var sm := f("speed_mult")
		var cm := f("cooldown_mult")
		a.rage_speed_mult *= sm
		a.rage_cooldown_mult *= cm
		var ref: WeakRef = weakref(a)
		var undo := func() -> void:
			var aa := ref.get_ref() as Enemy
			if aa != null:
				aa.rage_speed_mult /= sm
				aa.rage_cooldown_mult /= cm
		tree.create_timer(f("duration"), false).timeout.connect(undo)
		if a.get_parent() != null:
			FX.spawn(a.get_parent(), &"sun", a.global_position, 44.0, 0.7)
