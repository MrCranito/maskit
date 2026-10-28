class_name Projectile
extends Area2D
## Projectile du joueur, recyclé par un ProjectilePool (jamais libéré).
## Couche player_projectiles (8), masque world (1) + enemies (4).
## La trajectoire (collisions) est au niveau du sol, comme les hitbox et les murs ; le
## dessin est surélevé de `visual_height` (hauteur du canon).
## Styles (WeaponData.projectile_style) :
##   bullet : balle courte et lumineuse ;  pellet : petit plomb (fusil à pompe) ;
##   tracer : sniper, trait long et fin, laisse une traçante qui persiste une fraction de seconde ;
##   rocket : corps + flamme + traînée de fumée, accélère, explose au contact (mur, ennemi)
##            ou en fin de portée ;
##   grenade : arc simulé (hauteur z, gravité, ombre au sol, rebonds sol/murs), explose
##            après la mèche (projectile_lifetime) ou au contact d'un ennemi.
## Performance : un seul redessin par tir (le corps de la roquette/grenade est un enfant
## dessiné une fois et seulement déplacé) ; fumée émise à intervalle fixe dans CombatFx.

## Émis quand le projectile redevient disponible pour le pool.
signal released(projectile: Projectile)

const LAYER_PLAYER_PROJECTILES := 8
const MASK_WORLD_AND_ENEMIES := 1 | 4
const MASK_WORLD := 1

const STYLE_BULLET := &"bullet"
const STYLE_PELLET := &"pellet"
const STYLE_TRACER := &"tracer"
const STYLE_ROCKET := &"rocket"
const STYLE_GRENADE := &"grenade"

var active: bool = false
var direction: Vector2 = Vector2.RIGHT
var speed: float = 0.0
var damage: float = 0.0
var pierce_left: int = 0
var lifetime_left: float = 0.0
var color: Color = Color.WHITE
var source: Node = null
var style: StringName = STYLE_BULLET
var explosion_radius: float = 0.0
var explosion_damage: float = 0.0
## Hauteur d'affichage (px monde) au-dessus du sol.
var visual_height: float = 0.0
## Grenade : hauteur courante et vitesse verticale (px, px/s).
var z: float = 0.0
var vz: float = 0.0
var origin: Vector2 = Vector2.ZERO
## Cibles déjà touchées pendant ce vol (évite les doubles touches).
var _hit_ids: Dictionary = {}
var _max_speed: float = 0.0
var _age: float = 0.0
var _trail_left: float = 0.0
var _body: Node2D = null
var _shape: CollisionShape2D = null
## Guidage (Javelin) : cible et vitesse de rotation max (rad/s).
var _homing_target: Node2D = null
var _homing_rate: float = 0.0

# Réglages ([projectile_fx]) partagés par toutes les instances (lus une fois).
static var _cfg_loaded: bool = false
static var _rocket_start_mult: float = 0.45
static var _rocket_accel_time: float = 0.3
static var _rocket_trail_interval: float = 0.03
static var _grenade_vz: float = 300.0
static var _grenade_gravity: float = 1100.0
static var _grenade_bounce: float = 0.45
static var _grenade_friction: float = 0.55
static var _grenade_contact_z: float = 64.0


func _ready() -> void:
	collision_layer = LAYER_PLAYER_PROJECTILES
	collision_mask = MASK_WORLD_AND_ENEMIES
	z_as_relative = false
	z_index = 20
	# NB : laisser monitorable=true. Avec monitorable=false, Godot 4.4 ne détecte plus
	# rien après une bascule de `monitoring` (constaté au smoke test).
	body_entered.connect(_on_hit)
	area_entered.connect(_on_hit)
	_shape = get_node_or_null(^"CollisionShape2D") as CollisionShape2D
	_body = Node2D.new()
	_body.name = "Body"
	_body.draw.connect(_draw_body)
	_body.visible = false
	add_child(_body)
	_load_cfg()
	_set_active(false)


static func _load_cfg() -> void:
	if _cfg_loaded:
		return
	_cfg_loaded = true
	_rocket_start_mult = Balance.get_float("projectile_fx", "rocket_start_speed_mult", 0.45)
	_rocket_accel_time = Balance.get_float("projectile_fx", "rocket_accel_time", 0.3)
	_rocket_trail_interval = Balance.get_float("projectile_fx", "rocket_trail_interval", 0.03)
	_grenade_vz = Balance.get_float("projectile_fx", "grenade_launch_vz", 300.0)
	_grenade_gravity = Balance.get_float("projectile_fx", "grenade_gravity", 1100.0)
	_grenade_bounce = Balance.get_float("projectile_fx", "grenade_bounce", 0.45)
	_grenade_friction = Balance.get_float("projectile_fx", "grenade_bounce_friction", 0.55)
	_grenade_contact_z = Balance.get_float("projectile_fx", "grenade_contact_height", 64.0)


## Lance le projectile depuis `pos` dans la direction `dir`.
func launch(pos: Vector2, dir: Vector2, weapon: WeaponData, from: Node, height: float = 0.0) -> void:
	global_position = pos
	origin = pos
	visual_height = height
	direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	rotation = direction.angle()
	style = weapon.projectile_style if not String(weapon.projectile_style).is_empty() else STYLE_BULLET
	_max_speed = weapon.projectile_speed
	speed = _max_speed
	damage = weapon.damage
	pierce_left = weapon.pierce
	lifetime_left = weapon.projectile_lifetime if weapon.projectile_lifetime > 0.0 \
		else weapon.range / maxf(weapon.projectile_speed, 1.0)
	color = weapon.projectile_color
	explosion_radius = weapon.explosion_radius
	explosion_damage = weapon.explosion_damage
	source = from
	_age = 0.0
	_trail_left = 0.0
	_homing_target = null
	_homing_rate = 0.0
	_hit_ids.clear()
	z = 0.0
	vz = 0.0
	if style == STYLE_ROCKET:
		speed = _max_speed * _rocket_start_mult
	elif style == STYLE_GRENADE:
		z = height
		vz = _grenade_vz
	_body.visible = style == STYLE_ROCKET or style == STYLE_GRENADE
	_place_body()
	_set_active(true)
	# Recyclé depuis le pool : pas d'interpolation depuis son ancienne position.
	reset_physics_interpolation()
	_body.reset_physics_interpolation()
	# Un seul redessin par tir (couleur, style, décalage de hauteur fonction de l'angle).
	queue_redraw()
	_body.queue_redraw()


## Guidage léger vers `target` (rotation bornée à `rate` rad/s).
func set_homing(target: Node2D, rate: float) -> void:
	_homing_target = target
	_homing_rate = rate


## Logique pure : nouvelle direction, tournée vers `want` d'au plus `max_angle` radians.
static func steer(dir: Vector2, want: Vector2, max_angle: float) -> Vector2:
	if want == Vector2.ZERO:
		return dir
	var diff: float = dir.angle_to(want)
	return dir.rotated(clampf(diff, -max_angle, max_angle))


func is_explosive() -> bool:
	return explosion_radius > 0.0 or style == STYLE_ROCKET or style == STYLE_GRENADE


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
	_age += delta
	lifetime_left -= delta
	if lifetime_left <= 0.0:
		_end_of_range()
		return
	if _homing_rate > 0.0 and is_instance_valid(_homing_target):
		if _homing_target.has_method("is_alive") and not bool(_homing_target.call("is_alive")):
			_homing_target = null
		else:
			direction = steer(direction, _homing_target.global_position - global_position, _homing_rate * delta)
			if absf(angle_difference(rotation, direction.angle())) > 0.05:
				rotation = direction.angle()
				_place_body()
				queue_redraw()
	if style == STYLE_ROCKET:
		var k: float = clampf(_age / maxf(_rocket_accel_time, 0.01), 0.0, 1.0)
		speed = lerpf(_max_speed * _rocket_start_mult, _max_speed, k * k)
		_trail_left -= delta
		if _trail_left <= 0.0:
			_trail_left = _rocket_trail_interval
			var fx := CombatFx.get_or_create(get_tree())
			if fx != null:
				fx.rocket_trail(global_position + Vector2(0.0, -visual_height) - direction * 14.0, direction)
	elif style == STYLE_GRENADE:
		_step_grenade(delta)
	global_position += direction * speed * delta


func _step_grenade(delta: float) -> void:
	var was_high: bool = z > _grenade_contact_z
	vz -= _grenade_gravity * delta
	z += vz * delta
	if was_high and z <= _grenade_contact_z:
		# Redescend à hauteur d'homme : un ennemi déjà chevauché déclenche l'explosion
		# (body_entered n'est émis qu'à l'entrée). Requête rare (une fois par descente).
		for b: Node2D in get_overlapping_bodies():
			if active and b.is_in_group(&"enemies"):
				_on_hit(b)
	if z <= 0.0:
		z = 0.0
		if vz < -80.0:
			vz = -vz * _grenade_bounce
			speed *= _grenade_friction
		else:
			vz = 0.0
			speed = maxf(speed - 900.0 * delta, 0.0)
	_place_body()


func _place_body() -> void:
	# Le corps est surélevé « vers le haut de l'écran » quelle que soit la rotation.
	var h: float = z if style == STYLE_GRENADE else visual_height
	_body.position = Vector2(0.0, -h).rotated(-rotation)


func _end_of_range() -> void:
	if is_explosive():
		_explode(global_position)
	elif style == STYLE_TRACER:
		_leave_tracer(global_position)
	deactivate()


func _on_hit(other: Node) -> void:
	if not active:
		return
	if other == source:
		return
	if other.is_in_group("damageable") and other.has_method("take_damage"):
		if other.is_in_group("player"):
			return
		var key: int = other.get_instance_id()
		if _hit_ids.has(key):
			return
		if other.has_method("is_alive") and not other.is_alive():
			return
		if style == STYLE_GRENADE and z > _grenade_contact_z:
			return  # Passe au-dessus.
		_hit_ids[key] = true
		if style == STYLE_ROCKET or style == STYLE_GRENADE:
			# Impact direct : dégâts de base + explosion.
			other.take_damage(damage, source)
			_explode(global_position)
			deactivate()
			return
		other.take_damage(damage, source)
		_fx_enemy_hit(other)
		if pierce_left > 0:
			pierce_left -= 1
		else:
			if style == STYLE_TRACER:
				_leave_tracer(global_position)
			deactivate()
		return
	if other.is_in_group("enemies") or other.is_in_group("player"):
		return  # Ennemi mort ou non damageable : on le traverse.
	# Tout le reste (murs de la couche world, TileMapLayer compris).
	if style == STYLE_GRENADE:
		_bounce_off_wall()
		return
	var hit_pos: Vector2 = global_position - direction * 6.0
	if style == STYLE_ROCKET or explosion_radius > 0.0:
		_explode(global_position - direction * 12.0)
	else:
		var fx := CombatFx.get_or_create(get_tree())
		if fx != null:
			fx.impact_wall(hit_pos + Vector2(0.0, -visual_height * 0.7), direction, color)
		if style == STYLE_TRACER:
			_leave_tracer(hit_pos)
	deactivate()


## Grenade contre un mur : un raycast pour la normale, rebond amorti.
func _bounce_off_wall() -> void:
	var normal: Vector2 = -direction
	if is_inside_tree():
		var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
		var q := PhysicsRayQueryParameters2D.create(global_position - direction * 24.0,
			global_position + direction * 24.0, MASK_WORLD)
		var res: Dictionary = space.intersect_ray(q)
		if not res.is_empty():
			normal = res["normal"]
	direction = direction.bounce(normal).normalized()
	rotation = direction.angle()
	global_position += normal * 6.0
	speed *= _grenade_friction
	_place_body()
	queue_redraw()


func _explode(pos: Vector2) -> void:
	var fx := CombatFx.get_or_create(get_tree())
	var radius: float = explosion_radius if explosion_radius > 0.0 else 60.0
	var dmg: float = explosion_damage if explosion_damage > 0.0 else damage
	if fx != null:
		fx.explode(pos, radius, dmg, source)
	else:
		Explosion.apply_damage(get_tree(), null, pos, radius, dmg, source)


func _leave_tracer(end: Vector2) -> void:
	var fx := CombatFx.get_or_create(get_tree())
	if fx == null:
		return
	var up := Vector2(0.0, -visual_height)
	fx.tracer(origin + up, end + up, color)


func _fx_enemy_hit(other: Node) -> void:
	var fx := CombatFx.get_or_create(get_tree())
	if fx == null:
		return
	var p: Vector2 = global_position
	if other is Node2D:
		p = (other as Node2D).global_position
	var show_number: bool = not other.has_method("_spawn_damage_number")
	fx.impact_enemy(p + Vector2(0.0, -maxf(visual_height, 24.0)), direction, damage, show_number,
		other.get_instance_id())


func _draw() -> void:
	if style == STYLE_GRENADE:
		# Ombre au sol (le corps est un enfant surélevé).
		draw_set_transform(Vector2.ZERO, -rotation, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 6.0, Color(0.05, 0.07, 0.15, 0.45))
		return
	if visual_height != 0.0:
		draw_set_transform(Vector2(0.0, -visual_height).rotated(-rotation))
	match style:
		STYLE_PELLET:
			draw_line(Vector2(-12, 0), Vector2(2, 0), Color(color, 0.35), 4.0, true)
			draw_circle(Vector2(2, 0), 2.2, color.lightened(0.6), true, -1.0, true)
		STYLE_TRACER:
			draw_line(Vector2(-110, 0), Vector2(8, 0), Color(color, 0.22), 6.0, true)
			draw_line(Vector2(-90, 0), Vector2(10, 0), color.lightened(0.55), 1.6, true)
			draw_circle(Vector2(9, 0), 2.4, Color(1, 1, 1, 0.95), true, -1.0, true)
		STYLE_ROCKET:
			# Ombre au sol sous la roquette (elle vole à hauteur du canon).
			draw_set_transform(Vector2.ZERO, -rotation, Vector2(1.0, 0.45))
			draw_circle(Vector2.ZERO, 7.0, Color(0.05, 0.07, 0.15, 0.35))
		_:
			draw_line(Vector2(-28, 0), Vector2(6, 0), Color(color, 0.16), 9.0, true)
			draw_line(Vector2(-20, 0), Vector2(6, 0), Color(color, 0.5), 4.0, true)
			draw_line(Vector2(-12, 0), Vector2(8, 0), color.lightened(0.6), 2.0, true)
			draw_circle(Vector2(8, 0), 2.6, Color(1.0, 1.0, 0.95), true, -1.0, true)


## Corps de la roquette / grenade (dessin unique par tir).
func _draw_body() -> void:
	var b: Node2D = _body
	if style == STYLE_ROCKET:
		# Flamme arrière + halo, corps, ogive et ailerons (canon vers +X).
		b.draw_circle(Vector2(-12, 0), 9.0, Color(1.0, 0.55, 0.15, 0.35), true, -1.0, true)
		b.draw_colored_polygon(PackedVector2Array([Vector2(-9, -4), Vector2(-26, 0), Vector2(-9, 4)]),
			Color(1.0, 0.62, 0.18, 0.95))
		b.draw_colored_polygon(PackedVector2Array([Vector2(-9, -2.2), Vector2(-18, 0), Vector2(-9, 2.2)]),
			Color(1.0, 0.95, 0.7))
		b.draw_rect(Rect2(-9, -3.5, 16, 7), Color(0.32, 0.38, 0.3))
		b.draw_colored_polygon(PackedVector2Array([Vector2(7, -3.5), Vector2(13, 0), Vector2(7, 3.5)]),
			Color(0.85, 0.22, 0.15))
		b.draw_colored_polygon(PackedVector2Array([Vector2(-9, -3.5), Vector2(-5, -3.5), Vector2(-11, -8)]),
			Color(0.22, 0.25, 0.22))
		b.draw_colored_polygon(PackedVector2Array([Vector2(-9, 3.5), Vector2(-5, 3.5), Vector2(-11, 8)]),
			Color(0.22, 0.25, 0.22))
		b.draw_rect(Rect2(-9, -3.5, 16, 7), Color(0.08, 0.1, 0.12), false, 1.0)
	elif style == STYLE_GRENADE:
		b.draw_circle(Vector2.ZERO, 9.0, Color(color, 0.25), true, -1.0, true)
		b.draw_circle(Vector2.ZERO, 6.5, Color(0.25, 0.32, 0.2), true, -1.0, true)
		b.draw_circle(Vector2(-1.8, -1.8), 2.4, Color(0.55, 0.62, 0.45), true, -1.0, true)
		b.draw_arc(Vector2.ZERO, 6.5, 0.0, TAU, 16, Color(0.06, 0.08, 0.06), 1.4, true)
		b.draw_circle(Vector2(4.5, -4.0), 2.0, Color(1.0, 0.4, 0.15), true, -1.0, true)
