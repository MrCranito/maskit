extends GutTest
## Tests de la machine à états générique (State / StateMachine).


class RecState extends State:
	var log: Array = []
	var last_msg: Dictionary = {}
	var updates: int = 0
	var physics_updates: int = 0

	func _init(n: String, shared_log: Array) -> void:
		name = n
		log = shared_log

	func enter(msg: Dictionary = {}) -> void:
		last_msg = msg
		log.append("enter:" + String(name))

	func exit() -> void:
		log.append("exit:" + String(name))

	func update(_d: float) -> void:
		updates += 1

	func physics_update(_d: float) -> void:
		physics_updates += 1


var _log: Array = []
var _sm: StateMachine
var _a: RecState
var _b: RecState
var _changes: Array = []


func before_each() -> void:
	_log = []
	_changes = []
	_sm = StateMachine.new()
	_sm.auto_process = false
	_a = RecState.new("A", _log)
	_b = RecState.new("B", _log)
	_sm.add_child(_a)
	_sm.add_child(_b)
	add_child_autofree(_sm)
	_sm.state_changed.connect(func(f: StringName, t: StringName) -> void: _changes.append([f, t]))


func test_start_enters_initial_state() -> void:
	var actor := Node.new()
	autofree(actor)
	_sm.start(actor, &"A")
	assert_eq(_sm.current_state, _a)
	assert_eq(_log, ["enter:A"])
	assert_eq(_a.actor, actor, "l'acteur est propagé aux états")
	assert_eq(_a.state_machine, _sm)
	assert_eq(_changes, [[&"", &"A"]])


func test_start_defaults_to_first_child() -> void:
	_sm.start()
	assert_eq(_sm.get_current_state_name(), &"A")


func test_transition_calls_exit_then_enter_with_msg() -> void:
	_sm.start(null, &"A")
	_log.clear()
	assert_true(_sm.transition_to(&"B", {"k": 42}))
	assert_eq(_log, ["exit:A", "enter:B"])
	assert_eq(_b.last_msg, {"k": 42})
	assert_eq(_sm.current_state, _b)
	assert_eq(_changes.back(), [&"A", &"B"])


## NB : affiche volontairement « ERROR: StateMachine: état inconnu » dans la sortie.
func test_unknown_state_is_refused() -> void:
	_sm.start(null, &"A")
	assert_false(_sm.transition_to(&"Nope"))
	assert_eq(_sm.current_state, _a)


func test_state_requests_transition() -> void:
	_sm.start(null, &"A")
	_a.request_transition(&"B", {"from": "A"})
	assert_eq(_sm.get_current_state_name(), &"B")
	assert_eq(_b.last_msg, {"from": "A"})
	assert_true(_b.is_active())
	assert_false(_a.is_active())


func test_updates_only_reach_current_state() -> void:
	_sm.start(null, &"A")
	_sm.update(0.016)
	_sm.physics_update(0.016)
	assert_eq(_a.updates, 1)
	assert_eq(_a.physics_updates, 1)
	assert_eq(_b.updates, 0)
	assert_eq(_b.physics_updates, 0)


func test_transition_requested_during_enter_is_queued() -> void:
	var c := ChainState.new()
	_sm.add_child(c)
	_sm.register_state(c)
	_sm.start(null, &"A")
	_sm.transition_to(&"C")
	# C demande B dans son enter : la transition est exécutée après celle vers C.
	assert_eq(_sm.get_current_state_name(), &"B")
	assert_eq(_changes.slice(-2), [[&"A", &"C"], [&"C", &"B"]])


class ChainState extends State:
	func _init() -> void:
		name = "C"

	func enter(_msg: Dictionary = {}) -> void:
		request_transition(&"B")
