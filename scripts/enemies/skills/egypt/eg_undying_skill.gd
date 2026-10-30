extends EnemySkill
## « Se relève après la mort pour continuer son devoir » (Momie étouffée) : le premier coup
## mortel ne la tue pas — elle s'effondre (animation de mort tenue au sol, intouchable, barre de
## vie masquée) pendant `down_time` s, puis se relève avec `revive_ratio` de ses PV, plus rapide
## (`speed_mult`) et plus hargneuse (`cooldown_mult`). Une seule fois ; la 2e mort est définitive.
## Jamais choisie par l'IA : déclenchée par le coup mortel. Valeurs : [bestiary_egypt] eg_undying_*.

const Bal := preload("res://scripts/enemies/skills/egypt/eg_bal.gd")
const FX := preload("res://scripts/enemies/skills/egypt/eg_fx.gd")

## Résurrection disponible (consommée par le premier coup mortel).
var armed: bool = true
## Coup mortel encaissé, relevé en attente.
var pending: bool = false
## Relevée (tests, debug).
var revived: bool = false
var _rose: bool = false


func defaults() -> Dictionary:
	return Bal.defaults("eg_undying", {"cooldown": 999.0, "initial_cooldown": 0.0, "windup": 0.0, "need_los": false,
		"down_time": 2.2, "revive_ratio": 0.5, "speed_mult": 1.25, "cooldown_mult": 0.8, "priority": 99.0,
		"shout": "..."})


func can_use_extra(_dist: float, _sees: bool) -> bool:
	return pending


## Coup mortel : garde 1 PV et déclenche la chute (le reste du coup est absorbé).
func modify_damage(amount: float, _source: Node) -> float:
	if pending:
		return 0.0
	if armed and e != null and amount >= e.hp:
		armed = false
		pending = true
		e.call_deferred(&"force_skill", id)
		return maxf(e.hp - 1.0, 0.0)
	return amount


func start() -> void:
	e.stop()
	_rose = false
	e._visual_call(&"hide_telegraphs")
	e._visual_call(&"_play_once", ["death", f("down_time") + 0.3, -1])
	e._visual_call(&"set_modulate", [Color(0.85, 0.8, 0.75)])
	if e._health_bar != null:
		e._health_bar.visible = false
	e._fx_dust(e.global_position, 4)


func step(dt: float) -> bool:
	e.stop()
	if not _rose:
		e.invulnerable_left = maxf(e.invulnerable_left, dt * 2.0)
		if t >= f("down_time"):
			_rise()
		return false
	return t >= f("down_time") + 0.5


func _rise() -> void:
	_rose = true
	pending = false
	revived = true
	e.hp = maxf(e.max_hp * f("revive_ratio"), 1.0)
	e.rage_speed_mult *= f("speed_mult")
	e.rage_cooldown_mult *= f("cooldown_mult")
	e.invulnerable_left = maxf(e.invulnerable_left, 0.5)
	e._visual_call(&"set_modulate", [Color.WHITE])
	e._visual_call(&"_play_once", ["hit", 0.3, -1])
	e._visual_call(&"play_alert")
	var text := str(p.get("shout", ""))
	if text != "":
		e._visual_call(&"play_shout", [text])
	if e._health_bar != null:
		e._health_bar.visible = true
		e._health_bar.queue_redraw()
	if e.is_inside_tree() and e.get_parent() != null:
		FX.spawn(e.get_parent(), &"rise", e.global_position, 40.0, 0.7)
	e._play_sfx(&"enemy_alert")


## Interrompue (ne devrait pas arriver : intouchable) : se relève tout de suite.
func cleanup() -> void:
	if pending and not _rose and e != null and e.is_alive():
		_rise()
