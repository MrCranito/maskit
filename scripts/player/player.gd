class_name Player
extends CharacterBody2D
## Joueur : déplacement clavier / joystick virtuel, tir automatique style Archero
## (immobile → tire sur l'ennemi le plus proche visible), tir manuel souris sur PC.
## Couche player (2), masque world (1) + enemies (4). Groupes : player, damageable.

const LAYER_PLAYER := 2
const MASK_WORLD := 1
const MASK_ENEMIES := 4
const BODY_RADIUS := 22.0
const MUZZLE_OFFSET := 24.0
const DEFAULT_WEAPON: WeaponData = preload("res://data/weapons/starter_bow.tres")

@export var weapon: WeaponData = DEFAULT_WEAPON

var hp: float = 100.0
var max_hp: float = 100.0
var current_target: Node2D = null
## Direction de visée (sert au dessin et au tir sans cible).
var aim_direction: Vector2 = Vector2.UP

# Valeurs d'équilibrage (balance.cfg)
var move_speed: float = 260.0
var acceleration: float = 2200.0
var friction: float = 2600.0
var auto_fire_only_when_still: bool = true
var invulnerability_duration: float = 0.6
var hit_flash_duration: float = 0.12
var retarget_interval: float = 0.1

var _fire_cooldown: float = 0.0
var _invulnerable_left: float = 0.0
var _flash_left: float = 0.0
var _retarget_left: float = 0.0
var _is_moving: bool = false
var _alive: bool = true
var _joystick: Node = null

@onready var camera: Camera2D = $Camera2D
@onready var projectile_pool: ProjectilePool = $ProjectilePool


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = LAYER_PLAYER
	collision_mask = MASK_WORLD | MASK_ENEMIES
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_load_balance()
	if weapon == null:
		weapon = DEFAULT_WEAPON
	hp = max_hp
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = Balance.get_float("camera", "smoothing_speed", 8.0)
	var z: float = Balance.get_float("camera", "zoom", 1.0)
	camera.zoom = Vector2(z, z)
	camera.enabled = true
	camera.make_current()
	EventBus.player_spawned.emit(self)


func _load_balance() -> void:
	max_hp = Balance.get_float("player", "max_hp", 100.0)
	move_speed = Balance.get_float("player", "move_speed", 260.0)
	acceleration = Balance.get_float("player", "acceleration", 2200.0)
	friction = Balance.get_float("player", "friction", 2600.0)
	auto_fire_only_when_still = bool(Balance.get_value("player", "auto_fire_only_when_still", true))
	invulnerability_duration = Balance.get_float("player", "invulnerability_duration", 0.6)
	hit_flash_duration = Balance.get_float("player", "hit_flash_duration", 0.12)
	retarget_interval = Balance.get_float("player", "retarget_interval", 0.1)


func _physics_process(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	var was_flashing: bool = _flash_left > 0.0
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	if not _alive:
		if was_flashing:
			queue_redraw()
		return

	var input_dir: Vector2 = get_move_input()
	_is_moving = input_dir.length_squared() > 0.0001
	if _is_moving:
		velocity = velocity.move_toward(input_dir * move_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

	_update_target(delta)
	_update_fire()
	queue_redraw()


## Vecteur de déplacement (longueur 0..1). Joystick prioritaire s'il est actif.
func get_move_input() -> Vector2:
	var joy: Node = _get_joystick()
	if joy != null:
		var out: Vector2 = joy.get("output")
		if out.length_squared() > 0.0:
			return out.limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _get_joystick() -> Node:
	if not is_instance_valid(_joystick):
		_joystick = get_tree().get_first_node_in_group("virtual_joystick")
	return _joystick


func _is_joystick_held() -> bool:
	var joy: Node = _get_joystick()
	return joy != null and joy.has_method("is_held") and bool(joy.call("is_held"))


# --- Ciblage ---------------------------------------------------------------

func _update_target(delta: float) -> void:
	_retarget_left -= delta
	var target_lost: bool = current_target != null and (not is_instance_valid(current_target) or not _is_target_valid(current_target))
	if _retarget_left > 0.0 and not target_lost:
		return
	_retarget_left = retarget_interval
	var range_px: float = weapon.range if weapon != null else 0.0
	current_target = select_nearest_target(global_position, get_tree().get_nodes_in_group("enemies"), range_px, has_line_of_sight)


func _is_target_valid(t: Node2D) -> bool:
	if t.has_method("is_alive") and not t.is_alive():
		return false
	var range_px: float = weapon.range if weapon != null else 0.0
	return global_position.distance_to(t.global_position) <= range_px


## Logique pure : renvoie le Node2D vivant le plus proche de `origin` dans `max_range`,
## pour lequel `los_check.call(position_cible) == true` (Callable invalide = pas de test).
static func select_nearest_target(origin: Vector2, candidates: Array, max_range: float, los_check: Callable = Callable()) -> Node2D:
	var best: Node2D = null
	var best_d2: float = max_range * max_range
	# Trier d'abord par distance permet de ne lancer les raycasts que si nécessaire.
	var in_range: Array = []
	for c: Variant in candidates:
		if not (c is Node2D) or not is_instance_valid(c):
			continue
		var n: Node2D = c
		if n.has_method("is_alive") and not n.call("is_alive"):
			continue
		var d2: float = origin.distance_squared_to(n.global_position)
		if d2 <= best_d2:
			in_range.append([d2, n])
	in_range.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in in_range:
		var n2: Node2D = entry[1]
		if not los_check.is_valid() or los_check.call(n2.global_position):
			best = n2
			break
	return best


## Ligne de vue : aucun obstacle de la couche world entre le joueur et `to`.
func has_line_of_sight(to: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, to, MASK_WORLD, [get_rid()])
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


# --- Tir -------------------------------------------------------------------

func _update_fire() -> void:
	if weapon == null:
		return
	var manual: bool = Input.is_action_pressed("fire_manual") and not _is_joystick_held() and not DisplayServer.is_touchscreen_available()
	var dir: Vector2 = Vector2.ZERO
	if manual:
		dir = get_global_mouse_position() - global_position
	elif current_target != null and is_instance_valid(current_target):
		dir = current_target.global_position - global_position
		if auto_fire_only_when_still and _is_moving:
			dir = Vector2.ZERO
	if dir.length_squared() > 0.01:
		aim_direction = dir.normalized()
	elif _is_moving:
		aim_direction = velocity.normalized() if velocity.length_squared() > 1.0 else aim_direction
	if dir.length_squared() > 0.01 and _fire_cooldown <= 0.0:
		fire(aim_direction)


## Tire une salve dans `dir` selon l'arme (nombre de projectiles, dispersion).
func fire(dir: Vector2) -> void:
	_fire_cooldown = weapon.get_fire_interval()
	var count: int = maxi(weapon.projectile_count, 1)
	var spread: float = deg_to_rad(weapon.spread_degrees)
	for i: int in count:
		var offset: float = 0.0
		if count > 1:
			offset = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(count - 1))
		var d: Vector2 = dir.rotated(offset)
		projectile_pool.spawn(global_position + d * MUZZLE_OFFSET, d, weapon, self)


# --- Dégâts ----------------------------------------------------------------

func take_damage(amount: float, _source: Node) -> void:
	if not _alive or _invulnerable_left > 0.0 or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_invulnerable_left = invulnerability_duration
	_flash_left = hit_flash_duration
	EventBus.player_damaged.emit(amount, hp, max_hp)
	queue_redraw()
	if hp <= 0.0:
		_die()


func is_alive() -> bool:
	return _alive


func heal(amount: float) -> void:
	if _alive:
		hp = minf(hp + amount, max_hp)
		queue_redraw()


func _die() -> void:
	_alive = false
	velocity = Vector2.ZERO
	current_target = null
	EventBus.player_died.emit()


func get_debug_info() -> Dictionary:
	var target_name: String = "-"
	if current_target != null and is_instance_valid(current_target):
		target_name = String(current_target.name)
	return {
		"hp": hp,
		"max_hp": max_hp,
		"speed": velocity.length(),
		"target": target_name,
		"fire_cooldown": _fire_cooldown,
		"invulnerable": _invulnerable_left > 0.0,
		"weapon": weapon.display_name if weapon != null else "-",
		"pool_active": projectile_pool.get_active_count() if projectile_pool != null else 0,
	}


# --- Dessin placeholder ------------------------------------------------------
# Héros de référence : masque blanc kitsune, marques et yeux rouges lumineux,
# cornes rouges, écharpe rouge, armure sombre à liserés rouges, ombre bleu nuit.

const COL_ARMOR := Color(0.14, 0.13, 0.17)
const COL_ARMOR_TRIM := Color(0.85, 0.12, 0.12)
const COL_LEATHER := Color(0.45, 0.27, 0.15)
const COL_SCARF := Color(0.82, 0.1, 0.1)
const COL_MASK := Color(0.97, 0.95, 0.92)
const COL_MARK := Color(0.88, 0.06, 0.1)
const COL_EYE := Color(1.0, 0.18, 0.12)
const COL_OUTLINE := Color(0.04, 0.03, 0.06)
const COL_SHADOW := Color(0.07, 0.1, 0.25, 0.45)
const COL_AIM := Color(1.0, 0.25, 0.15)


func _draw() -> void:
	var flash: bool = _flash_left > 0.0
	var alpha: float = 1.0
	if _invulnerable_left > 0.0 and not flash:
		alpha = 0.45 if int(_invulnerable_left * 20.0) % 2 == 0 else 1.0
	if not _alive:
		alpha = 0.35
	var tint := func(c: Color) -> Color: return Color(1, 1, 1, 1) if flash else Color(c, c.a * alpha)

	# Ombre bleu nuit
	draw_set_transform(Vector2(0, 8), 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, BODY_RADIUS + 3.0, Color(COL_SHADOW, COL_SHADOW.a * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Flèche de visée (lueur rouge)
	var tip: Vector2 = aim_direction * (BODY_RADIUS + 18.0)
	var base: Vector2 = aim_direction * (BODY_RADIUS + 6.0)
	var side: Vector2 = aim_direction.orthogonal() * 7.0
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), tint.call(COL_AIM))

	# Tout le corps est orienté vers la visée : repère local où -Y = avant.
	var ang: float = aim_direction.angle() + PI * 0.5
	draw_set_transform(Vector2.ZERO, ang, Vector2.ONE)
	# Pans d'écharpe flottant à l'arrière
	draw_colored_polygon(PackedVector2Array([Vector2(-4, 8), Vector2(-14, 30), Vector2(-6, 28), Vector2(0, 10)]), tint.call(COL_SCARF))
	draw_colored_polygon(PackedVector2Array([Vector2(3, 9), Vector2(10, 32), Vector2(15, 26), Vector2(7, 8)]), tint.call(COL_SCARF.darkened(0.2)))
	# Épaulières / armure sombre
	draw_circle(Vector2.ZERO, BODY_RADIUS + 2.0, tint.call(COL_OUTLINE))
	draw_circle(Vector2.ZERO, BODY_RADIUS, tint.call(COL_ARMOR))
	draw_arc(Vector2.ZERO, BODY_RADIUS - 2.5, 0.0, TAU, 32, tint.call(COL_ARMOR_TRIM), 2.0, true)
	# Sangle de cuir en diagonale
	draw_line(Vector2(-12, -9), Vector2(11, 11), tint.call(COL_LEATHER), 3.0, true)
	# Écharpe autour du cou
	draw_arc(Vector2(0, -2), 10.0, PI * 0.1, PI * 0.9, 12, tint.call(COL_SCARF), 5.0, true)
	# Cornes / plumes rouges
	draw_colored_polygon(PackedVector2Array([Vector2(-7, -14), Vector2(-14, -27), Vector2(-3, -17)]), tint.call(COL_MARK))
	draw_colored_polygon(PackedVector2Array([Vector2(7, -14), Vector2(14, -27), Vector2(3, -17)]), tint.call(COL_MARK))
	# Masque kitsune : tête ovale + museau pointu vers l'avant
	var mask := PackedVector2Array([
		Vector2(-9, -6), Vector2(-10, -13), Vector2(-6, -19), Vector2(0, -25),
		Vector2(6, -19), Vector2(10, -13), Vector2(9, -6), Vector2(0, -2)])
	var mask_outline := PackedVector2Array()
	for v: Vector2 in mask:
		mask_outline.append(v * 1.15 + Vector2(0, 1.5))
	draw_colored_polygon(mask_outline, tint.call(COL_OUTLINE))
	draw_colored_polygon(mask, tint.call(COL_MASK))
	# Marques rouges sur le masque
	draw_line(Vector2(0, -24), Vector2(0, -17), tint.call(COL_MARK), 2.0, true)
	draw_line(Vector2(-8, -8), Vector2(-4, -11), tint.call(COL_MARK), 2.0, true)
	draw_line(Vector2(8, -8), Vector2(4, -11), tint.call(COL_MARK), 2.0, true)
	# Yeux rouges lumineux (halo + coeur)
	for ex: float in [-4.0, 4.0]:
		var e := Vector2(ex, -14)
		draw_circle(e, 3.6, Color(COL_EYE, 0.35 * alpha))
		draw_circle(e, 1.8, Color(1, 1, 1) if flash else Color(1.0, 0.55, 0.4, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Barre de vie (panneau bleu nuit)
	var w: float = 44.0
	var h: float = 6.0
	var top_left := Vector2(-w * 0.5, -BODY_RADIUS - 22.0)
	var ratio: float = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	draw_rect(Rect2(top_left - Vector2(1.5, 1.5), Vector2(w + 3, h + 3)), Color(0.07, 0.1, 0.18, 0.9))
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0.25, 0.05, 0.07))
	var hp_col: Color = Color(0.35, 0.9, 0.35).lerp(Color(0.95, 0.2, 0.15), 1.0 - ratio)
	draw_rect(Rect2(top_left, Vector2(w * ratio, h)), hp_col)
