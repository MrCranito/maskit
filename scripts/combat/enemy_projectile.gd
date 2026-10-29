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
## Laser (station spatiale) et acide (station sous-marine) : même orbe, autre couleur.
const STYLE_COLORS := {&"laser": Color(0.35, 0.85, 1.0), &"acid": Color(0.55, 1.0, 0.25),
	&"laser_red": Color(1.0, 0.28, 0.2), &"plasma": Color(0.82, 0.45, 1.0)}
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
## Balle perforante (compétence « piercing ») : traverse caisses, tonneaux et chariots
## (conteneurs, décors), pas les murs. Remis à faux à chaque tir.
var pierce_props: bool = false
## Style « knife » : couteau lancé (lame qui tournoie).
const STYLE_KNIFE := &"knife"
const KNIFE_BLADE := Color(0.85, 0.87, 0.92)
const KNIFE_HANDLE := Color(0.45, 0.28, 0.16)
## Hauteur d'affichage (px monde) : trajectoire au sol (hitbox du joueur aux pieds), dessin surélevé.
var visual_height: float = 0.0
const DEFAULT_VISUAL_HEIGHT := 28.0


func _ready() -> void:
	collision_layer = LAYER_ENEMY_PROJECTILES
	collision_mask = MASK_WORLD_AND_PLAYER
	# monitorable laissé à true (voir projectile.gd : bug de détection après bascule sinon).
	body_entered.connect(_on_hit)
	_set_active(false)


func launch(pos: Vector2, dir: Vector2, proj_speed: float, proj_damage: float, from: Node, lifetime: float,
		proj_style: StringName = &"", height: float = DEFAULT_VISUAL_HEIGHT) -> void:
	style = proj_style
	visual_height = height
	global_position = pos
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	rotation = direction.angle()
	speed = proj_speed
	damage = proj_damage
	lifetime_left = lifetime
	source = from
	pierce_props = false
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
	# Pas de redessin par frame (l'ancienne pulsation coûtait un redraw par balle et par frame).


func _on_hit(other: Node) -> void:
	if not active or other == source:
		return
	if other.is_in_group(&"player") or other.is_in_group(NetHooks.GROUP_AVATAR):
		if other.has_method("take_damage"):
			other.call("take_damage", damage, source if is_instance_valid(source) else null)
		deactivate()
		return
	if other.is_in_group(&"enemies") or other.is_in_group(&"enemy_units"):
		return
	if pierce_props and is_pierceable(other):
		return
	deactivate()  # Mur.


## Obstacle traversable par une balle perforante : conteneur (caisse, tonneau, chariot…) ou décor.
static func is_pierceable(other: Node) -> bool:
	if other == null:
		return false
	if other.name == &"PropBodies":
		return true
	var par := other.get_parent()
	return par is LootContainer or par is WorldProp


func _draw() -> void:
	var k := 1.0
	if visual_height != 0.0:
		draw_set_transform(Vector2(0.0, -visual_height).rotated(-rotation))
	if style == STYLE_KNIFE:
		# Couteau : lame claire + manche, petite traînée.
		draw_line(Vector2(-22, 0), Vector2(-6, 0), Color(KNIFE_BLADE, 0.25), 6.0, true)
		draw_set_transform(Vector2(0.0, -visual_height).rotated(-rotation) if visual_height != 0.0 else Vector2.ZERO,
			0.0)
		draw_colored_polygon(PackedVector2Array([Vector2(-2, -3), Vector2(12, 0), Vector2(-2, 3)]), KNIFE_BLADE)
		draw_rect(Rect2(-9, -2.5, 7, 5), KNIFE_HANDLE)
		return
	if style == STYLE_BULLET:
		# Balle : longue traînée fine jaune-orangé, coeur blanc chaud.
		draw_line(Vector2(-30, 0), Vector2(4, 0), Color(BULLET_GLOW, 0.18), 10.0 * k, true)
		draw_line(Vector2(-24, 0), Vector2(4, 0), Color(BULLET_GLOW, 0.5), 4.5, true)
		draw_line(Vector2(-14, 0), Vector2(4, 0), Color(BULLET_CORE, 0.9), 2.0, true)
		draw_circle(Vector2(3, 0), 6.5 * k, Color(BULLET_GLOW, 0.4))
		draw_circle(Vector2(3, 0), 3.8, BULLET_GLOW.lightened(0.3))
		draw_circle(Vector2(3.5, 0), 2.2, BULLET_CORE)
		return
	var glow: Color = STYLE_COLORS.get(style, COLOR_GLOW)
	draw_line(Vector2(-26, 0), Vector2(4, 0), Color(glow, 0.2), 14.0 * k, true)
	draw_line(Vector2(-18, 0), Vector2(4, 0), Color(glow, 0.55), 7.0, true)
	draw_circle(Vector2(2, 0), 9.0 * k, Color(glow, 0.45))
	draw_circle(Vector2(2, 0), 5.5, glow.lightened(0.2))
	draw_circle(Vector2(3, 0), 3.0, COLOR_CORE)
