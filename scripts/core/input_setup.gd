extends Node
## Déclare les actions d'entrée en code (AZERTY et QWERTY + flèches),
## pour éviter un project.godot illisible.
## Les touches sont PHYSIQUES (position QWERTY) : physical KEY_A = « Q » en AZERTY.
## Armes : weapon_next = touche en haut à gauche (Q en QWERTY, A en AZERTY — le Q AZERTY
## sert déjà à aller à gauche) + molette vers le bas ; weapon_prev = molette vers le haut ;
## weapon_1..3 = rangée de chiffres (1/&, 2/é, 3/") ; reload = R ; gadget (équipement) = G.

const ACTIONS := {
	"move_up": [KEY_W, KEY_Z, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"toggle_debug": [KEY_F3],
	# Mode développeur (DevMode, builds debug uniquement), actif quand le F3 est ouvert.
	"toggle_dev_currency": [KEY_F4],
	"interact": [KEY_E],
	"reload": [KEY_R],
	"gadget": [KEY_G],
	"weapon_next": [KEY_Q],
	"weapon_prev": [],
	"weapon_1": [KEY_1, KEY_KP_1],
	"weapon_2": [KEY_2, KEY_KP_2],
	"weapon_3": [KEY_3, KEY_KP_3],
}

## Molette : action → bouton.
const WHEEL := {
	"weapon_next": MOUSE_BUTTON_WHEEL_DOWN,
	"weapon_prev": MOUSE_BUTTON_WHEEL_UP,
}


func _enter_tree() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for keycode: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
	for action: String in WHEEL:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = WHEEL[action]
		InputMap.action_add_event(action, wheel)
	if not InputMap.has_action("fire_manual"):
		InputMap.add_action("fire_manual")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("fire_manual", mb)
