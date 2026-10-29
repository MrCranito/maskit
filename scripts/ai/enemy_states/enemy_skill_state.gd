extends EnemyState
## Compétence active (EnemySkill) : télégraphe puis exécution, pilotés par la compétence
## (begin / update / finish). À la fin : retour au combat (Chase), ou étourdi si la compétence
## l'a demandé (charge contre un mur). Interrompue proprement si l'ennemi est étourdi ou meurt.

var _skill: EnemySkill = null


func _init() -> void:
	name = "Skill"


func enter(msg: Dictionary = {}) -> void:
	var e := get_enemy()
	_skill = msg.get("skill") as EnemySkill
	e.pending_stun = 0.0
	if _skill == null:
		request_transition(Enemy.STATE_CHASE)
		return
	e.active_skill = _skill
	_skill.begin()


func exit() -> void:
	var e := get_enemy()
	if _skill != null:
		_skill.finish()
	_skill = null
	e.active_skill = null
	e.direct_velocity = false
	e._visual_call(&"use_throw_anim", [false])


func physics_update(delta: float) -> void:
	var e := get_enemy()
	if _skill == null:
		request_transition(Enemy.STATE_CHASE)
		return
	if _skill.update(delta):
		if e.pending_stun > 0.0:
			request_transition(Enemy.STATE_STUNNED, {"time": e.pending_stun})
		else:
			request_transition(Enemy.STATE_CHASE)
