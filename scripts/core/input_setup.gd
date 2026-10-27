extends Node
## Déclare les actions d'entrée en code (AZERTY et QWERTY + flèches),
## pour éviter un project.godot illisible.

const ACTIONS := {
	"move_up": [KEY_W, KEY_Z, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_Q, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"toggle_debug": [KEY_F3],
	"interact": [KEY_E],
}


func _enter_tree() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("fire_manual"):
		InputMap.add_action("fire_manual")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire_manual", mb)
