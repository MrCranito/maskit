extends EnemyState
## Attaque : immobile, télégraphe (attack_windup) via visual.play_attack_windup, puis le coup.
## Mêlée : touche seulement si le joueur est encore à portée (il peut esquiver).
## Distance : tire un EnemyProjectile (ou un éventail si projectile_count > 1).
## Zone (aoe_radius > 0) : onde de choc au sol autour de l'ennemi. Puis courte récupération et retour en Chase.

var _windup_left: float = 0.0
var _recover_left: float = 0.0
var _struck: bool = false


func _init() -> void:
	name = "Attack"


func enter(_msg: Dictionary = {}) -> void:
	var e := get_enemy()
	e.stop()
	_struck = false
	_windup_left = e.data.attack_windup
	_recover_left = Balance.get_float("enemy_ai", "attack_recovery", 0.25)
	var p := e.get_player()
	if p != null:
		e.face_position(p.global_position)
		e._visual_call(&"set_aim_direction", [p.global_position - e.global_position])
	e._visual_call(&"play_attack_windup", [e.data.attack_windup])


func physics_update(delta: float) -> void:
	var e := get_enemy()
	e.stop()
	if not _struck:
		var p := e.get_player()
		if p == null:
			request_transition(Enemy.STATE_RETURN)
			return
		# L'archer suit sa cible du regard pendant la visée.
		if e.data.is_ranged():
			e.face_position(p.global_position)
			e._visual_call(&"set_aim_direction", [p.global_position - e.global_position])
		_windup_left -= delta
		if _windup_left <= 0.0:
			_struck = true
			e.perform_attack()
		return
	_recover_left -= delta
	if _recover_left <= 0.0:
		request_transition(Enemy.STATE_CHASE)
