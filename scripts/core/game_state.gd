extends Node
## État global de la partie en cours (raid actif, joueur, debug, seed).

var player: Node2D = null
var debug_enabled: bool = false
var run_seed: int = 0


func _ready() -> void:
	randomize()
	run_seed = randi()
	EventBus.player_spawned.connect(func(p: Node2D) -> void: player = p)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_enabled = not debug_enabled
		EventBus.debug_toggled.emit(debug_enabled)
