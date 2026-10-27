class_name State
extends Node
## État générique d'une StateMachine (réutilisable : ennemis, boss à phases...).
## Le nom du nœud sert d'identifiant d'état (ex. "Patrol", "Chase").
## Un état ne change jamais d'état lui-même directement : il appelle
## `request_transition()`, que la StateMachine exécute.

## Émis par l'état pour demander un changement (relayé par la StateMachine).
signal transition_requested(to_state: StringName, msg: Dictionary)

## Propriétaire de la machine (l'ennemi, le boss...). Renseigné par la StateMachine.
var actor: Node = null
## Machine à états parente. Renseignée par la StateMachine.
var state_machine: StateMachine = null


## Appelé à l'entrée dans l'état. `msg` transporte des données optionnelles.
func enter(_msg: Dictionary = {}) -> void:
	pass


## Appelé à la sortie de l'état.
func exit() -> void:
	pass


## Appelé à chaque frame (_process) tant que l'état est actif.
func update(_delta: float) -> void:
	pass


## Appelé à chaque frame physique tant que l'état est actif.
func physics_update(_delta: float) -> void:
	pass


## Demande une transition vers `to_state`.
func request_transition(to_state: StringName, msg: Dictionary = {}) -> void:
	transition_requested.emit(to_state, msg)


## Vrai si cet état est l'état courant de sa machine.
func is_active() -> bool:
	return state_machine != null and state_machine.current_state == self
