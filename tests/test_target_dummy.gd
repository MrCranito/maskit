extends GutTest
## Tests de la cible d'entraînement (dégâts, mort, réapparition, signaux).

const DUMMY_SCENE := preload("res://scenes/enemies/target_dummy.tscn")

var _dummy: Node2D
var _died: Array = []
var _spawned: Array = []


func before_each() -> void:
	_died.clear()
	_spawned.clear()
	EventBus.enemy_died.connect(_on_enemy_died)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	_dummy = DUMMY_SCENE.instantiate() as Node2D
	add_child_autofree(_dummy)


func after_each() -> void:
	EventBus.enemy_died.disconnect(_on_enemy_died)
	EventBus.enemy_spawned.disconnect(_on_enemy_spawned)


func _on_enemy_died(enemy: Node2D, _pos: Vector2) -> void:
	_died.append(enemy)


func _on_enemy_spawned(enemy: Node2D) -> void:
	_spawned.append(enemy)


func test_spawn_state() -> void:
	var expected := Balance.get_float("target_dummy", "max_hp", 60.0)
	assert_eq(_dummy.get("max_hp"), expected, "PV max lus dans balance.cfg")
	assert_eq(_dummy.get("hp"), expected, "PV pleins à l'apparition")
	assert_true(_dummy.is_alive())
	assert_true(_dummy.is_in_group("enemies"))
	assert_true(_dummy.is_in_group("damageable"))
	assert_eq((_dummy as CollisionObject2D).collision_layer, 4, "Couche enemies")
	assert_true(_spawned.has(_dummy), "enemy_spawned émis à l'apparition")


func test_take_damage_reduces_hp() -> void:
	var max_hp: float = _dummy.get("max_hp")
	_dummy.take_damage(10.0, null)
	assert_almost_eq(float(_dummy.get("hp")), max_hp - 10.0, 0.001)
	assert_true(_dummy.is_alive())
	assert_eq(_died.size(), 0)


func test_death_emits_and_leaves_groups() -> void:
	var max_hp: float = _dummy.get("max_hp")
	_dummy.take_damage(max_hp + 50.0, null)
	assert_eq(float(_dummy.get("hp")), 0.0, "PV bornés à 0")
	assert_false(_dummy.is_alive())
	assert_eq(_died.size(), 1, "enemy_died émis une fois")
	assert_eq(_died[0], _dummy)
	assert_false(_dummy.is_in_group("enemies"))
	assert_false(_dummy.is_in_group("damageable"))


func test_no_damage_when_dead() -> void:
	var max_hp: float = _dummy.get("max_hp")
	_dummy.take_damage(max_hp, null)
	_dummy.take_damage(10.0, null)
	assert_eq(_died.size(), 1, "Pas de seconde mort")


func test_respawn_after_delay() -> void:
	var max_hp: float = _dummy.get("max_hp")
	_dummy.take_damage(max_hp, null)
	_spawned.clear()
	var delay: float = _dummy.get("respawn_delay")
	await wait_seconds(delay + 0.3)
	assert_true(_dummy.is_alive(), "Réapparu")
	assert_eq(float(_dummy.get("hp")), max_hp, "PV pleins après réapparition")
	assert_true(_dummy.is_in_group("enemies"))
	assert_true(_spawned.has(_dummy), "enemy_spawned émis à la réapparition")
