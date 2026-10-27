class_name EnemyProjectile
extends Area2D
## Projectile ennemi (flèche/orbe orange-rouge lumineuse), recyclé par EnemyProjectilePool.
## Couche enemy_projectiles (16), masque world (1) + player (2).

signal released(projectile: EnemyProjectile)

const LAYER_ENEMY_PROJECTILES := 16
const MASK_WORLD_AND_PLAYER := 1 | 2

const COLOR_CORE := Color(1.0, 0.85, 0.55)
const COLOR_GLOW := Color(1.0, 0.38, 0.12)
## Style « bullet » (hors-la-loi) : balle jaune-orangé, traînée fine.
const STYLE_BULLET := &"bullet"
const BULLET_CORE := Color(1.0, 0.97, 0.75)
const BULLET_GLOW := Color(1.0, 0.72, 0.15)

var active: bool = false
var direction: Vector2 = Vector2.RIGHT
var speed: float = 0.0
var damage: float = 0.0
var lifetime_left: float = 0.0
var source: Node = null
var style: StringName = &""
var _pulse: float = 0.0


func _ready() -> void:
	collision_layer = LAYER_ENEMY_PROJECTILES
	collision_mask = MASK_WORLD_AND_PLAYER
	# monitorable laissé à true (voir projectile.gd : bug de détection après bascule sinon).
	body_entered.connect(_on_hit)
	_set_active(false)


func launch(pos: Vector2, dir: Vector2, proj_speed: float, proj_damage: float, from: Node, lifetime: float,
		proj_style: StringName = &"") -> void:
	style = proj_style
	global_position = pos
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	rotation = direction.angle()
	speed = proj_speed
	damage = proj_damage
	lifetime_left = lifetime
	source = from
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
	set_deferred("monitoring", value)
	set_physics_process(value)


func _physics_process(delta: float) -> void:
	lifetime_left -= delta
	if lifetime_left <= 0.0:
		deactivate()
		return
	global_position += direction * speed * delta
	_pulse += delta
	queue_redraw()


func _on_hit(other: Node) -> void:
	if not active or other == source:
		return
	if other.is_in_group(&"player"):
		if other.has_method("take_damage"):
			other.call("take_damage", damage, source if is_instance_valid(source) else null)
		deactivate()
		return
	if other.is_in_group(&"enemies") or other.is_in_group(&"enemy_units"):
		return
	deactivate()  # Mur.


func _draw() -> void:
	var k := 1.0 + 0.15 * sin(_pulse * 25.0)
	if style == STYLE_BULLET:
		# Balle : longue traînée fine jaune-orangé, coeur blanc chaud.
		draw_line(Vector2(-30, 0), Vector2(4, 0), Color(BULLET_GLOW, 0.18), 10.0 * k, true)
		draw_line(Vector2(-24, 0), Vector2(4, 0), Color(BULLET_GLOW, 0.5), 4.5, true)
		draw_line(Vector2(-14, 0), Vector2(4, 0), Color(BULLET_CORE, 0.9), 2.0, true)
		draw_circle(Vector2(3, 0), 6.5 * k, Color(BULLET_GLOW, 0.4))
		draw_circle(Vector2(3, 0), 3.8, BULLET_GLOW.lightened(0.3))
		draw_circle(Vector2(3.5, 0), 2.2, BULLET_CORE)
		return
	draw_line(Vector2(-26, 0), Vector2(4, 0), Color(COLOR_GLOW, 0.2), 14.0 * k, true)
	draw_line(Vector2(-18, 0), Vector2(4, 0), Color(COLOR_GLOW, 0.55), 7.0, true)
	draw_circle(Vector2(2, 0), 9.0 * k, Color(COLOR_GLOW, 0.45))
	draw_circle(Vector2(2, 0), 5.5, COLOR_GLOW.lightened(0.2))
	draw_circle(Vector2(3, 0), 3.0, COLOR_CORE)
