extends GutTest
## Vérifie que l'autoload InputSetup déclare toutes les actions attendues.

const ACTIONS_ATTENDUES: Array[String] = [
	"move_up", "move_down", "move_left", "move_right",
	"toggle_debug", "interact", "fire_manual",
]


func test_autoload_input_setup_present() -> void:
	assert_not_null(get_node_or_null("/root/InputSetup"), "l'autoload InputSetup doit être chargé")


func test_actions_existent() -> void:
	for action: String in ACTIONS_ATTENDUES:
		assert_true(InputMap.has_action(action), "action manquante : %s" % action)


func test_actions_ont_des_evenements() -> void:
	for action: String in ACTIONS_ATTENDUES:
		if InputMap.has_action(action):
			assert_gt(InputMap.action_get_events(action).size(), 0, "aucun événement pour %s" % action)


func _a_touche(action: String, keycode: Key) -> bool:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == keycode:
			return true
	return false


func test_zqsd_et_wasd_et_fleches() -> void:
	assert_true(_a_touche("move_up", KEY_W), "move_up : W/Z physique")
	assert_true(_a_touche("move_up", KEY_UP), "move_up : flèche haut")
	assert_true(_a_touche("move_left", KEY_A), "move_left : A/Q physique")
	assert_true(_a_touche("move_down", KEY_S), "move_down : S")
	assert_true(_a_touche("move_right", KEY_D), "move_right : D")
	assert_true(_a_touche("move_right", KEY_RIGHT), "move_right : flèche droite")


func test_f3_bascule_debug() -> void:
	assert_true(_a_touche("toggle_debug", KEY_F3))


func test_fire_manual_clic_gauche() -> void:
	var trouve := false
	for ev: InputEvent in InputMap.action_get_events("fire_manual"):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			trouve = true
	assert_true(trouve, "fire_manual doit être lié au clic gauche")
