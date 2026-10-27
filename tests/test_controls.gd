extends GutTest
## Double joystick (paysage) et contrôles du joueur : multi-touch, moitiés d'écran,
## tir continu au stick droit, plus de tir automatique, cachette, bruit.

const AREA := Vector2(1280, 720)

var _ui: Control
var _left: TouchJoystick
var _right: TouchJoystick


func before_each() -> void:
	# Comme en jeu : les sticks vivent dans un CanvasLayer (indépendant de la Camera2D).
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	_ui = Control.new()
	_ui.size = AREA
	layer.add_child(_ui)
	var pair: Array[TouchJoystick] = TouchJoystick.create_pair(_ui)
	assert_eq(pair.size(), 2)
	_left = pair[0]
	_right = pair[1]
	for j: TouchJoystick in pair:
		j.set_enabled(true)


func after_each() -> void:
	# Les joueurs instanciés ici s'annoncent via EventBus.player_spawned : on ne laisse
	# pas GameState pointer sur un joueur libéré (les autres suites le sauvegardent).
	GameState.player = null


func _touch(j: TouchJoystick, index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	if pressed:
		j._unhandled_input(ev)
	else:
		j._input(ev)


func _drag(j: TouchJoystick, index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	j._input(ev)


## Envoie l'événement aux deux sticks (comme le moteur).
func _touch_both(index: int, pos: Vector2, pressed: bool) -> void:
	_touch(_left, index, pos, pressed)
	_touch(_right, index, pos, pressed)


func _drag_both(index: int, pos: Vector2) -> void:
	_drag(_left, index, pos)
	_drag(_right, index, pos)


# --- Logique pure ------------------------------------------------------------------

func test_side_accepts_halves() -> void:
	assert_true(TouchJoystick.side_accepts(&"left", Vector2(200, 500), AREA, 0.25))
	assert_false(TouchJoystick.side_accepts(&"left", Vector2(900, 500), AREA, 0.25))
	assert_true(TouchJoystick.side_accepts(&"right", Vector2(900, 500), AREA, 0.25))
	assert_false(TouchJoystick.side_accepts(&"right", Vector2(200, 500), AREA, 0.25))


func test_side_accepts_ignores_top_band_and_outside() -> void:
	assert_false(TouchJoystick.side_accepts(&"left", Vector2(200, 100), AREA, 0.25), "bande HUD")
	assert_false(TouchJoystick.side_accepts(&"right", Vector2(1300, 500), AREA, 0.25), "hors écran")


# --- Instances -----------------------------------------------------------------------

func test_pair_groups_and_sides() -> void:
	assert_eq(_left.side, &"left")
	assert_eq(_right.side, &"right")
	assert_true(_left.is_in_group(TouchJoystick.GROUP_MOVE))
	assert_true(_right.is_in_group(TouchJoystick.GROUP_AIM))
	assert_false(_right.is_in_group(TouchJoystick.GROUP_MOVE))


func test_multitouch_each_stick_follows_its_finger() -> void:
	_touch_both(0, Vector2(200, 500), true)
	_touch_both(1, Vector2(1000, 500), true)
	assert_eq(_left.get_touch_index(), 0)
	assert_eq(_right.get_touch_index(), 1)
	_drag_both(0, Vector2(290, 500))   # gauche : plein à droite
	_drag_both(1, Vector2(1000, 410))  # droit : plein vers le haut
	assert_almost_eq(_left.output.x, 1.0, 0.01)
	assert_almost_eq(_left.output.y, 0.0, 0.01)
	assert_almost_eq(_right.output.y, -1.0, 0.01)
	# Relâcher le doigt gauche ne touche pas au stick droit.
	_touch_both(0, Vector2(290, 500), false)
	assert_false(_left.is_held())
	assert_eq(_left.output, Vector2.ZERO)
	assert_true(_right.is_held())
	assert_almost_eq(_right.output.y, -1.0, 0.01)


func test_second_finger_same_side_ignored() -> void:
	_touch_both(0, Vector2(200, 500), true)
	_touch_both(2, Vector2(300, 600), true)
	assert_eq(_left.get_touch_index(), 0, "le stick garde son premier doigt")
	_drag_both(2, Vector2(500, 600))
	assert_eq(_left.output, Vector2.ZERO, "le second doigt ne pilote pas le stick")


func test_base_follows_finger_beyond_radius() -> void:
	_touch(_left, 0, Vector2(200, 500), true)
	_drag(_left, 0, Vector2(200 + _left.radius * 3.0, 500))
	assert_almost_eq(_left.output.length(), 1.0, 0.01)
	# En revenant d'un rayon vers la gauche, la base a suivi : on est au centre.
	_drag(_left, 0, Vector2(200 + _left.radius * 2.0, 500))
	assert_eq(_left.output, Vector2.ZERO)


func test_disabled_stick_ignores_touch() -> void:
	_left.set_enabled(false)
	_touch(_left, 0, Vector2(200, 500), true)
	# _unhandled_input appelé directement : vérifie que set_enabled coupe bien la lecture.
	assert_false(_left.is_processing_unhandled_input())
	assert_false(_left.visible)


func test_no_per_frame_processing() -> void:
	assert_false(_left.is_processing(), "pas de _process sur les sticks")
	assert_false(_left.is_physics_processing())


# --- Joueur ---------------------------------------------------------------------------

func _spawn_player() -> Player:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(p)
	p.set_joysticks(_left, _right)
	return p


func test_player_reads_left_stick_for_movement() -> void:
	var p := _spawn_player()
	_touch_both(0, Vector2(200, 500), true)
	_drag_both(0, Vector2(290, 500))
	assert_almost_eq(p.get_move_input().x, 1.0, 0.01)
	for i: int in 10:
		p._physics_process(1.0 / 60.0)
	assert_true(p.is_moving())
	assert_gt(p.velocity.x, 100.0)
	assert_almost_eq(p.get_noise_level(), p.noise_walk * p.velocity.length() / p.move_speed, 0.02)


func test_right_stick_aims_and_fires_continuously() -> void:
	var p := _spawn_player()
	watch_signals(p)
	_touch_both(1, Vector2(1000, 500), true)
	_drag_both(1, Vector2(1000, 590))  # vers le bas
	p._physics_process(1.0 / 60.0)
	assert_eq(p.get_noise_level(), 1.0, "bruit max juste après un tir")
	for i: int in 59:  # 1 s au total
		p._physics_process(1.0 / 60.0)
	assert_almost_eq(p.aim_direction.y, 1.0, 0.01)
	var expected: int = int(p.weapon.fire_rate)
	assert_between(get_signal_emit_count(p, "fired"), expected, expected + 1, "tir continu à la cadence de l'arme")
	assert_gt(p.get_noise_level(), 0.4, "bruit de tir encore élevé")


func test_right_stick_inside_dead_zone_does_not_fire() -> void:
	var p := _spawn_player()
	watch_signals(p)
	_touch_both(1, Vector2(1000, 500), true)
	_drag_both(1, Vector2(1000 + _right.radius * _right.dead_zone * 0.5, 500))
	for i: int in 30:
		p._physics_process(1.0 / 60.0)
	assert_signal_not_emitted(p, "fired")


func test_no_auto_fire_near_enemies() -> void:
	var p := _spawn_player()
	var dummy := Node2D.new()
	dummy.add_to_group(&"enemies")
	dummy.position = Vector2(100, 0)
	add_child_autofree(dummy)
	watch_signals(p)
	for i: int in 60:
		p._physics_process(1.0 / 60.0)
	assert_signal_not_emitted(p, "fired", "plus de tir automatique")


func test_muzzle_position_in_front_of_player() -> void:
	var p := _spawn_player()
	p.global_position = Vector2(500, 500)
	var right_m: Vector2 = p.get_muzzle_position(Vector2.RIGHT)
	var left_m: Vector2 = p.get_muzzle_position(Vector2.LEFT)
	assert_gt(right_m.x, 515.0)
	assert_lt(left_m.x, 485.0)


func test_hidden_player_silent_still_and_cannot_fire() -> void:
	var p := _spawn_player()
	var spot := Node2D.new()
	spot.position = Vector2(64, 0)
	add_child_autofree(spot)
	watch_signals(p)
	p.set_hidden(true, spot)
	assert_true(p.is_hidden())
	assert_eq(p.get_hide_spot(), spot)
	assert_eq(p.collision_layer, 0, "caché : collisions coupées")
	p.fire(Vector2.RIGHT)
	assert_signal_not_emitted(p, "fired")
	# Stick droit poussé : toujours pas de tir.
	_touch_both(1, Vector2(1000, 500), true)
	_drag_both(1, Vector2(1090, 500))
	for i: int in 10:
		p._physics_process(1.0 / 60.0)
	assert_signal_not_emitted(p, "fired")
	assert_eq(p.get_noise_level(), 0.0)
	assert_eq(p.velocity, Vector2.ZERO)


func test_hidden_player_exits_by_moving_left_stick() -> void:
	var p := _spawn_player()
	p.global_position = Vector2(10, 10)
	p.set_hidden(true, null)
	_touch_both(0, Vector2(200, 500), true)
	_drag_both(0, Vector2(290, 500))
	p._physics_process(0.05)  # avant le délai de grâce
	assert_true(p.is_hidden(), "pas de sortie immédiate (délai de grâce)")
	for i: int in 30:
		p._physics_process(1.0 / 60.0)
	assert_false(p.is_hidden(), "sortie en poussant le stick gauche")
	assert_eq(p.collision_layer, Player.LAYER_PLAYER)


func test_set_hidden_false_via_interaction() -> void:
	var p := _spawn_player()
	p.set_hidden(true)
	watch_signals(p)
	p.set_hidden(false)
	assert_false(p.is_hidden())
	assert_signal_emitted(p, "hidden_changed")
