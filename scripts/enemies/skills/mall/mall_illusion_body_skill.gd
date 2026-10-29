extends EnemySkill
## Passif des doubles illusoires (data/enemies/*_illusion.tres) : silhouette translucide teintée,
## se dissipe (bouffée violette, sans cadavre ni butin) au premier dégât reçu, après `hits`
## attaques ou au bout de `lifetime` s.

var _life: float = -1.0
var _attacks: int = 0
var _tinted: bool = false
var _gone: bool = false


func defaults() -> Dictionary:
	return {"passive": true, "lifetime": 9.0, "hits": 2, "tint": Color(0.82, 0.62, 1.0, 0.72)}


func tick_cooldown(dt: float) -> void:
	if e == null or _gone:
		return
	if not _tinted and e.visual != null:
		_tinted = true
		var c: Variant = p.get("tint", Color.WHITE)
		e._visual_call(&"set_modulate", [c if c is Color else Color.WHITE])
	if _life < 0.0:
		_life = f("lifetime")
	_life -= dt
	if _life <= 0.0:
		vanish()


func modify_damage(_amount: float, _source: Node) -> float:
	vanish()
	return 0.0


func on_attack_done() -> void:
	_attacks += 1
	if _attacks >= int(f("hits")):
		vanish()


func vanish() -> void:
	if _gone or e == null or not is_instance_valid(e):
		return
	_gone = true
	e._fx_dust(e.global_position, 3)
	fx(&"blink", e.global_position, e.global_position, 22.0, 0.2)
	e.queue_free()


func is_gone() -> bool:
	return _gone
