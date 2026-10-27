class_name EnemyState
extends State
## Base des états d'Enemy : accès typé à l'ennemi propriétaire.


func get_enemy() -> Enemy:
	return actor as Enemy
