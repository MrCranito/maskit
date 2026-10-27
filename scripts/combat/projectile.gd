class_name Projectile
extends Area2D
## Projectile en ligne droite, recyclé par un ProjectilePool (jamais libéré).
## Couche player_projectiles (8), masque world (1) + enemies (4).

## Émis quand le projectile redevient disponible pour le pool.
signal released(projectile: Projectile)

const LAYER_PLAYER_PROJECTILES := 8
const MASK_WORLD_AND_ENEMIES := 1 | 4

var active: bool = false
var direction: Vector2 = Vector2.RIGHT
var speed: float = 0.0
var damage: float = 0.0
var pierce_left: int = 0
var lifetime_left: float = 0.0
var color: Color = Color.WHITE
var source: Node = null
## Cibles déjà touchées pendant ce vol (évite les doubles touches).
var _hit_ids: Dictionary = {}


func _ready() -> void:
	collision_layer = LAYER_PLAYER_PROJECTILES
	collision_mask = MASK_WORLD_AND_ENEMIES
	# NB : laisser monitorable=true. Avec monitorable=false, Godot 4.4 ne détecte plus
	# rien après une bascule de `monitoring` (constaté au smoke test).
	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit)
	_set_active(false)


## Lance le projectile depuis `pos` dans la direction `dir`.
func launch(pos: Vector2, dir: Vector2, weapon: WeaponData, from: Node) -> void:
	global_position = pos
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	rotation = direction.angle()
	speed = weapon.projectile_speed
	damage = weapon.damage
	pierce_left = weapon.pierce
	lifetime_left = weapon.projectile_lifetime
	color = weapon.projectile_color
	source = from
	_hit_ids.clear()
	_set_active(true)
	queue_redraw()


func deactivate() -> void:
	if not active:
		return
	_set_active(false)
	source = null
	released.emit(self)


func _set_active(value: bool) -> void:
	active = value
	visible = value
	# Appelé potentiellement pendant un callback physique : différé obligatoire.
	set_deferred("monitoring", value)
	set_physics_process(value)


func _physics_process(delta: float) -> void:
	lifetime_left -= delta
	if lifetime_left <= 0.0:
		deactivate()
		return
	global_position += direction * speed * delta


func _on_hit(other: Node) -> void:
	if not active:
		return
	if other == source:
		return
	if other.is_in_group("damageable") and other.has_method("take_damage"):
		var key: int = other.get_instance_id()
		if _hit_ids.has(key):
			return
		if other.has_method("is_alive") and not other.is_alive():
			return
		_hit_ids[key] = true
		other.take_damage(damage, source)
		if pierce_left > 0:
			pierce_left -= 1
		else:
			deactivate()
		return
	if other.is_in_group("enemies"):
		return  # Ennemi mort ou non damageable : on le traverse.
	# Tout le reste (murs de la couche world, TileMapLayer compris) arrête le projectile.
	deactivate()


func _draw() -> void:
	# Traînée lumineuse (halo + coeur clair) et pointe, orientées vers +X.
	draw_line(Vector2(-30, 0), Vector2(6, 0), Color(color, 0.18), 11.0, true)
	draw_line(Vector2(-24, 0), Vector2(6, 0), Color(color, 0.45), 6.0, true)
	draw_line(Vector2(-16, 0), Vector2(8, 0), color.lightened(0.5), 2.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(13, 0), Vector2(4, -5), Vector2(4, 5)]), color.lightened(0.7))
