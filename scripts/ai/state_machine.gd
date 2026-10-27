class_name StateMachine
extends Node
## Machine à états finis générique. Les états sont les enfants `State` de ce nœud,
## identifiés par leur nom. Réutilisable par tout acteur (ennemis, boss...).
##
##   var sm := StateMachine.new()
##   sm.add_child(MyIdle.new())      # nœud nommé "Idle"
##   actor.add_child(sm)
##   sm.start(actor, &"Idle")
##
## Si `auto_process` vaut false, le propriétaire appelle lui-même
## `update(delta)` / `physics_update(delta)` (utile pour ordonner avec move_and_slide).

signal state_changed(from_state: StringName, to_state: StringName)

## État initial (nom d'un enfant). Vide = premier enfant State.
@export var initial_state: StringName = &""
## Si vrai, la machine appelle update/physics_update dans ses propres callbacks.
@export var auto_process: bool = true

var actor: Node = null
var current_state: State = null
var states: Dictionary = {}  # StringName -> State
var _started: bool = false
var _transitioning: bool = false
var _pending: Array = []  # [[StringName, Dictionary], ...] transitions demandées pendant une transition


func _ready() -> void:
	_collect_states()
	set_process(auto_process)
	set_physics_process(auto_process)


func _collect_states() -> void:
	for child: Node in get_children():
		if child is State:
			register_state(child as State)


## Enregistre un état (appelé automatiquement pour les enfants présents au _ready).
func register_state(state: State) -> void:
	var key := StringName(state.name)
	if states.has(key) and states[key] == state:
		return
	states[key] = state
	state.actor = actor
	state.state_machine = self
	if not state.transition_requested.is_connected(_on_transition_requested):
		state.transition_requested.connect(_on_transition_requested)


## Démarre la machine sur `state_name` (ou `initial_state`, ou le premier état).
func start(owner_actor: Node = null, state_name: StringName = &"", msg: Dictionary = {}) -> void:
	_collect_states()
	if owner_actor != null:
		actor = owner_actor
	for s: State in states.values():
		s.actor = actor
	var first: StringName = state_name if state_name != &"" else initial_state
	if first == &"" and get_child_count() > 0:
		for child: Node in get_children():
			if child is State:
				first = StringName(child.name)
				break
	if not states.has(first):
		push_error("StateMachine: état initial introuvable '%s'" % first)
		return
	_started = true
	current_state = states[first]
	current_state.enter(msg)
	state_changed.emit(&"", first)


func get_current_state_name() -> StringName:
	return StringName(current_state.name) if current_state != null else &""


func has_state(state_name: StringName) -> bool:
	return states.has(state_name)


## Change d'état : exit() de l'ancien, enter(msg) du nouveau, puis state_changed.
## Une transition demandée pendant un enter/exit est mise en file et exécutée ensuite.
## Renvoie false si l'état n'existe pas.
func transition_to(state_name: StringName, msg: Dictionary = {}) -> bool:
	if not states.has(state_name):
		push_error("StateMachine: état inconnu '%s'" % state_name)
		return false
	if _transitioning:
		_pending.append([state_name, msg])
		return true
	_transitioning = true
	var from: StringName = get_current_state_name()
	if current_state != null:
		current_state.exit()
	current_state = states[state_name]
	_started = true
	current_state.enter(msg)
	_transitioning = false
	state_changed.emit(from, state_name)
	if not _pending.is_empty():
		var next: Array = _pending.pop_front()
		transition_to(next[0], next[1])
	return true


func update(delta: float) -> void:
	if current_state != null:
		current_state.update(delta)


func physics_update(delta: float) -> void:
	if current_state != null:
		current_state.physics_update(delta)


func _process(delta: float) -> void:
	update(delta)


func _physics_process(delta: float) -> void:
	physics_update(delta)


func _on_transition_requested(to_state: StringName, msg: Dictionary) -> void:
	transition_to(to_state, msg)
