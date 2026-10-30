extends EnemySkill
## Vacarme du parc (Clown égaré : coup de klaxon ; Chien de cirque : aboiement) — comportement
## commun « attirent les survivants par le bruit » : cri au-dessus de la tête et cercles sonores
## (télégraphe), puis toutes les créatures dans `radius` convergent vers le joueur (alertées),
## et un joueur caché à moins de `reveal_radius` est débusqué.
## Valeurs : [bestiary_carnival] racket_*.

const Bal := preload("res://scripts/enemies/skills/carnival/cv_balance.gd")

var alerted: int = 0
var _done: bool = false


func defaults() -> Dictionary:
	var d := Bal.read("racket", {"cooldown": 16.0, "initial_cooldown": 1.0, "windup": 0.45, "max_range": 700.0,
		"radius": 680.0, "reveal_radius": 150.0, "priority": 1.4})
	d.merge({"shout": "HONK !", "fx": "whistle"}, true)
	return d


func start() -> void:
	e.stop()
	alerted = 0
	_done = false
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])
	e._play_sfx(&"enemy_alert")
	fx(StringName(str(p.get("fx", "whistle"))), e.global_position, Vector2.ZERO, f("radius") * 0.25, windup())


func step(_dt: float) -> bool:
	if t < windup():
		e.stop()
		return false
	if not _done:
		_done = true
		_racket()
	return t >= windup() + 0.15


func _racket() -> void:
	if not e.is_inside_tree():
		return
	var target := player_pos()
	var r2 := f("radius") * f("radius")
	for n: Node in e.get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
		var o := n as Enemy
		if o == null or o == e or not o.is_alive() or o.net_puppet:
			continue
		if e.global_position.distance_squared_to(o.global_position) > r2:
			continue
		if not o.is_in_combat():
			o.become_aware(target, false)
			alerted += 1
	var pl := player()
	if pl != null and pl.global_position.distance_to(e.global_position) <= f("reveal_radius"):
		e.reveal_hidden_player()
