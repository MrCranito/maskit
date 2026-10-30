extends EnemySkill
## Valse du manège (Manège fantôme) : soutien / zone. Orgue de barbarie (anneau violet pendant le
## télégraphe), puis zone de musique (cv_music_zone.gd) qui le suit `duration` s : joueurs ralentis
## et brûlés par la musique, créatures du parc soignées. La musique « attire » : les créatures
## à moins de `lure_radius` sont alertées vers le joueur. Une seule zone active par créateur.
## Valeurs : [bestiary_carnival] waltz_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")
const ZONE := preload("res://scripts/enemies/skills/carnival/cv_music_zone.gd")

var zone: Node2D = null
var _done: bool = false


func defaults() -> Dictionary:
	return Bal.read("waltz", {"cooldown": 11.0, "initial_cooldown": 1.5, "windup": 0.8, "max_range": 420.0,
		"radius": 230.0, "duration": 5.5, "slow": 0.4, "dps": 3.0, "heal_per_sec": 6.0, "tick": 0.25,
		"lure_radius": 620.0, "follow": 1.0, "need_los": false, "priority": 1.6})


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return not is_instance_valid(zone)


func start() -> void:
	e.stop()
	_done = false
	e._visual_call(&"play_attack_windup", [windup(), false])
	e._visual_call(&"play_shout", ["♪ ♫ ♪"])
	fx(&"ring", e.global_position, Vector2.ZERO, f("radius"), windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		var parent: Node = e.get_parent() if e.get_parent() != null else e.get_tree().current_scene
		zone = ZONE.spawn(parent, e.global_position, {"radius": f("radius"), "duration": f("duration"),
			"slow": f("slow"), "dps": f("dps") * e.diff_damage_mult, "heal_per_sec": f("heal_per_sec"),
			"tick": f("tick"), "follow": f("follow") > 0.5}, e)
		_lure()
	return t >= windup() + 0.2


func _lure() -> void:
	if not e.is_inside_tree():
		return
	var target := player_pos()
	var r2 := f("lure_radius") * f("lure_radius")
	for n: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
		var o := n as Enemy
		if o != null and o != e and o.is_alive() and not o.is_in_combat() \
				and o.global_position.distance_squared_to(e.global_position) <= r2:
			o.become_aware(target, false)
