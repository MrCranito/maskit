extends GutTest
## Tests de DoorNode : ouverture au contact, verrou, clefs, collision.

const DOOR_SCENE := preload("res://scenes/dungeon/door.tscn")


class FakeBody extends CharacterBody2D:
	var combat: bool = false

	func _init(layer: int, groups: Array[StringName]) -> void:
		collision_layer = layer
		collision_mask = 0
		for g: StringName in groups:
			add_to_group(g)
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 14.0
		cs.shape = c
		add_child(cs)

	func is_in_combat() -> bool:
		return combat


func _make_door(state: int, key: StringName = &"") -> DoorNode:
	var d := FloorLayout.Door.new()
	d.cell = Vector2i(5, 5)
	d.state = state
	d.key_id = key
	var door := DOOR_SCENE.instantiate() as DoorNode
	door.setup(d)
	add_child_autofree(door)
	return door


func _door_center(door: DoorNode) -> Vector2:
	return FloorLayout.cell_to_world(door.cell)


func test_api_and_groups() -> void:
	var door := _make_door(FloorLayout.DoorState.CLOSED)
	assert_true(door.is_in_group(&"doors"))
	assert_eq(door.cell, Vector2i(5, 5))
	assert_false(door.is_open())
	assert_false(door.is_locked())
	assert_eq(door.collision_layer, 1, "Fermée : couche world")


func test_open_close_and_collision() -> void:
	var door := _make_door(FloorLayout.DoorState.CLOSED)
	watch_signals(door)
	door.open()
	assert_true(door.is_open())
	assert_signal_emitted(door, "state_changed")
	assert_eq(door.collision_layer, 0, "Ouverte : plus de collision")
	var shape := door.get_node("CollisionShape2D") as CollisionShape2D
	await wait_physics_frames(1)
	assert_true(shape.disabled)
	door.close()
	assert_false(door.is_open())
	assert_eq(door.collision_layer, 1)


func test_player_contact_opens() -> void:
	var door := _make_door(FloorLayout.DoorState.CLOSED)
	var p := FakeBody.new(2, [&"player"])
	p.position = _door_center(door) + Vector2(0, 40)
	add_child_autofree(p)
	await wait_physics_frames(4)
	assert_true(door.is_open(), "Le joueur ouvre la porte au contact")


func test_enemy_opens_only_when_pursuing() -> void:
	var door := _make_door(FloorLayout.DoorState.CLOSED)
	var e := FakeBody.new(4, [&"enemies"])
	e.position = _door_center(door) + Vector2(0, -40)
	add_child_autofree(e)
	await wait_physics_frames(4)
	assert_false(door.is_open(), "Ennemi en patrouille : ne force pas la porte")
	e.combat = true
	await wait_seconds(0.35)
	assert_true(door.is_open(), "Ennemi en poursuite : ouvre")


func test_locked_does_not_open_on_contact() -> void:
	var door := _make_door(FloorLayout.DoorState.LOCKED, &"key_bank_vault")
	watch_signals(door)
	assert_eq(door.kind, DoorNode.KIND_VAULT, "Verrouillée → grille de coffre")
	var p := FakeBody.new(2, [&"player"])
	p.position = _door_center(door) + Vector2(0, 40)
	add_child_autofree(p)
	await wait_physics_frames(4)
	assert_false(door.is_open())
	assert_true(door.is_locked())
	assert_signal_emitted(door, "locked_bumped")
	assert_true(door.is_locked_message_visible(), "Message « Clef requise »")
	door.open()
	assert_false(door.is_open(), "open() ne force pas un verrou")


func test_try_unlock() -> void:
	var door := _make_door(FloorLayout.DoorState.LOCKED, &"key_bank_vault")
	assert_false(door.try_unlock(&"key_wrong"), "Mauvaise clef")
	assert_false(door.try_unlock(&""), "Pas de clef")
	assert_true(door.is_locked())
	assert_eq(door.collision_layer, 1)
	assert_true(door.try_unlock(&"key_bank_vault"), "Bonne clef")
	assert_true(door.is_open())
	assert_false(door.is_locked())
	assert_eq(door.collision_layer, 0)
	assert_eq(door.data.state, FloorLayout.DoorState.OPEN, "Donnée de carte mise à jour")


func test_open_animation_progresses() -> void:
	var door := _make_door(FloorLayout.DoorState.CLOSED)
	door.open()
	assert_almost_eq(door.get_open_progress(), 0.0, 0.01)
	await wait_seconds(0.4)
	assert_almost_eq(door.get_open_progress(), 1.0, 0.01)


func test_initially_open_door() -> void:
	var door := _make_door(FloorLayout.DoorState.OPEN)
	assert_true(door.is_open())
	assert_eq(door.collision_layer, 0)
