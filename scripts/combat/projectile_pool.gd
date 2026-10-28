class_name ProjectilePool
extends Node
## Pool de projectiles pré-instanciés. Peut être enfant du joueur : les projectiles
## vivent dans un conteneur Node2D ajouté à la scène courante (ils ne suivent pas le joueur).
## Le pool s'agrandit si épuisé (jamais au-delà de [projectile_fx] pool_max_size : au-delà,
## le plus ancien projectile actif est recyclé).

const PROJECTILE_SCENE: PackedScene = preload("res://scenes/combat/projectile.tscn")

## Taille du pool ; si <= 0, lue dans balance.cfg [projectile_pool] size.
@export var pool_size: int = 0
## Parent optionnel des projectiles ; sinon scène courante, sinon racine.
@export var world_parent_path: NodePath

var _container: Node2D = null
var _free: Array[Projectile] = []
var _all: Array[Projectile] = []
var _max_size: int = 256
var _steal_cursor: int = 0


func _ready() -> void:
	# Différé : la scène courante n'est pas forcément prête pendant _ready.
	_build.call_deferred()


func _exit_tree() -> void:
	if is_instance_valid(_container):
		_container.queue_free()
	_container = null
	_free.clear()
	_all.clear()


func _build() -> void:
	if is_instance_valid(_container) or not is_inside_tree():
		return
	var size: int = pool_size if pool_size > 0 else int(Balance.get_value("projectile_pool", "size", 64))
	_max_size = maxi(int(Balance.get_value("projectile_fx", "pool_max_size", 256)), size)
	_container = Node2D.new()
	_container.name = "PlayerProjectiles"
	_get_world_parent().add_child(_container)
	for i: int in size:
		_create_one()


func _get_world_parent() -> Node:
	if not world_parent_path.is_empty() and has_node(world_parent_path):
		return get_node(world_parent_path)
	var scene: Node = get_tree().current_scene
	if scene != null:
		return scene
	return get_tree().root


func _create_one() -> Projectile:
	var p: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	_container.add_child(p)
	p.released.connect(_on_released)
	_all.append(p)
	_free.append(p)
	return p


## Tire un projectile. Renvoie null si le pool n'a pas pu en fournir un.
func spawn(position: Vector2, direction: Vector2, weapon: WeaponData, source: Node, height: float = 0.0) -> Projectile:
	if not is_instance_valid(_container):
		_build()
		if not is_instance_valid(_container):
			return null
	if _free.is_empty():
		if _all.size() < _max_size:
			# Pool épuisé : on l'agrandit plutôt que de perdre un tir.
			_create_one()
		else:
			# Plafond atteint : recycle un projectile actif (tourniquet).
			_steal_cursor = (_steal_cursor + 1) % _all.size()
			_all[_steal_cursor].deactivate()
	var p: Projectile = _free.pop_back()
	p.launch(position, direction, weapon, source, height)
	EventBus.projectile_fired.emit(p)
	return p


func get_active_count() -> int:
	return _all.size() - _free.size()


func get_pool_size() -> int:
	return _all.size()


## Désactive tous les projectiles (changement d'étage, tests).
func release_all() -> void:
	for p: Projectile in _all:
		p.deactivate()


func _on_released(p: Projectile) -> void:
	if not _free.has(p):
		_free.append(p)
