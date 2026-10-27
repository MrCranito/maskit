class_name EnemyProjectilePool
extends Node2D
## Pool partagé des projectiles ennemis. Un seul par scène, créé à la demande
## (`EnemyProjectilePool.get_or_create(tree)`) dans la scène courante.

const SCENE: PackedScene = preload("res://scenes/combat/enemy_projectile.tscn")
const GROUP := &"enemy_projectile_pool"

var _free: Array[EnemyProjectile] = []
var _all: Array[EnemyProjectile] = []


static func get_or_create(tree: SceneTree) -> EnemyProjectilePool:
	if tree == null:
		return null
	var existing := tree.get_first_node_in_group(GROUP) as EnemyProjectilePool
	if existing != null and not existing.is_queued_for_deletion():
		return existing
	var pool := EnemyProjectilePool.new()
	pool.name = "EnemyProjectiles"
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	pool.add_to_group(GROUP)
	parent.add_child(pool)
	return pool


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 20
	for i: int in int(Balance.get_value("enemy_ai", "projectile_pool_size", 24)):
		_create_one()


func _create_one() -> EnemyProjectile:
	var p := SCENE.instantiate() as EnemyProjectile
	add_child(p)
	p.released.connect(_on_released)
	_all.append(p)
	_free.append(p)
	return p


## lifetime ≤ 0 : durée de balance.cfg. style : voir EnemyProjectile (&"" = orbe, &"bullet" = balle).
func spawn(pos: Vector2, dir: Vector2, speed: float, damage: float, source: Node,
		lifetime: float = -1.0, style: StringName = &"") -> EnemyProjectile:
	if _free.is_empty():
		_create_one()
	var p: EnemyProjectile = _free.pop_back()
	var life := lifetime if lifetime > 0.0 else Balance.get_float("enemy_ai", "projectile_lifetime", 2.5)
	p.launch(pos, dir, speed, damage, source, life, style)
	EventBus.projectile_fired.emit(p)
	return p


func get_active_count() -> int:
	return _all.size() - _free.size()


func _on_released(p: EnemyProjectile) -> void:
	if not _free.has(p):
		_free.append(p)
