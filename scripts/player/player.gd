class_name Player
extends CharacterBody2D
## Joueur : déplacement clavier / joystick virtuel, tir automatique style Archero
## (immobile → tire sur l'ennemi le plus proche visible), tir manuel souris sur PC.
## Couche player (2), masque world (1) + enemies (4). Groupes : player, damageable.

const LAYER_PLAYER := 2
const MASK_WORLD := 1
const MASK_ENEMIES := 4
## Rayon du corps (collision aux pieds, cf. player.tscn).
const BODY_RADIUS := 15.0
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
	_build_visual()
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
	_on_fired_visual(dir)


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

# --- Visuel : sprite SVG du héros kitsune -------------------------------------
# Le sprite (Sprite2D construit en code) porte le personnage ; _draw() ne dessine
# que l'ombre au sol et la flèche de visée (sous le sprite). Un nœud overlay
# au-dessus du sprite dessine l'arc de lame rouge et la barre de vie.

const TEX_IDLE: Texture2D = preload("res://assets/sprites/hero/hero_kitsune.svg")
const TEX_WALK: Array[Texture2D] = [
	preload("res://assets/sprites/hero/hero_kitsune_walk_1.svg"),
	preload("res://assets/sprites/hero/hero_kitsune_walk_2.svg"),
]
const HIT_FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
## Hauteur du héros en unités monde (≈ 70 px à l'écran avec le zoom 1.3).
const SPRITE_WORLD_HEIGHT := 54.0
## Marge transparente sous les pieds dans le SVG (viewBox 200 de haut, pieds à y≈197).
const SPRITE_FOOT_MARGIN := 3.0 / 200.0
const WALK_FRAME_TIME := 0.13
const BREATH_SPEED := 2.6
const BREATH_AMOUNT := 0.025
const SLASH_DURATION := 0.12
const SLASH_RADIUS := 32.0
const SLASH_HALF_ANGLE := 1.15
const SLASH_HEIGHT := 16.0
const KICK_DURATION := 0.14

const COL_SHADOW := Color(0.07, 0.1, 0.25, 0.45)
const COL_AIM := Color(1.0, 0.25, 0.15)
const COL_SLASH := Color(1.0, 0.16, 0.12)
const COL_SLASH_CORE := Color(1.0, 0.85, 0.7)

var _sprite: Sprite2D = null
var _overlay: Node2D = null
var _flash_mat: ShaderMaterial = null
var _sprite_base_scale: float = 1.0
var _anim_time: float = 0.0
var _walk_time: float = 0.0
var _slash_left: float = 0.0
var _slash_dir: Vector2 = Vector2.UP
var _kick_left: float = 0.0
var _facing_left: bool = false


func _build_visual() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "HeroSprite"
	_sprite.texture = TEX_IDLE
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tex_h: float = float(TEX_IDLE.get_height())
	_sprite_base_scale = SPRITE_WORLD_HEIGHT / tex_h
	# Pieds (bas-centre) à l'origine du CharacterBody2D.
	_sprite.offset = Vector2(0.0, -tex_h * 0.5 + tex_h * SPRITE_FOOT_MARGIN)
	_sprite.scale = Vector2.ONE * _sprite_base_scale
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = HIT_FLASH_SHADER
	_sprite.material = _flash_mat
	add_child(_sprite)
	_overlay = Node2D.new()
	_overlay.name = "HeroOverlay"
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _process(delta: float) -> void:
	if _sprite == null:
		return
	_anim_time += delta
	_slash_left = maxf(_slash_left - delta, 0.0)
	_kick_left = maxf(_kick_left - delta, 0.0)

	# Orientation gauche/droite : visée prioritaire au tir, sinon déplacement.
	var face_x: float = aim_direction.x
	if _is_moving and _kick_left <= 0.0 and absf(velocity.x) > 5.0:
		face_x = velocity.x
	if absf(face_x) > 0.15:
		_facing_left = face_x < 0.0
	_sprite.flip_h = _facing_left

	# Marche : alternance des frames ; arrêt : respiration (scale Y).
	var sy: float = 1.0
	if _alive and _is_moving:
		_walk_time += delta
		var idx: int = int(_walk_time / WALK_FRAME_TIME) % 4
		_sprite.texture = TEX_WALK[0] if idx == 0 else (TEX_WALK[1] if idx == 2 else TEX_IDLE)
	else:
		_walk_time = 0.0
		_sprite.texture = TEX_IDLE
		sy = 1.0 + sin(_anim_time * BREATH_SPEED) * BREATH_AMOUNT
	_sprite.scale = Vector2(_sprite_base_scale, _sprite_base_scale * sy)

	# Poussée vers l'avant + inclinaison au tir.
	var kick: float = _kick_left / KICK_DURATION
	kick = kick * kick
	_sprite.position = _slash_dir * 3.5 * kick
	_sprite.rotation = signf(_slash_dir.x if absf(_slash_dir.x) > 0.1 else (-1.0 if _facing_left else 1.0)) * 0.14 * kick

	# Flash blanc (shader) + clignotement d'invulnérabilité (alpha).
	_flash_mat.set_shader_parameter("flash_amount", clampf(_flash_left / maxf(hit_flash_duration, 0.001), 0.0, 1.0))
	var alpha: float = 1.0
	if not _alive:
		alpha = 0.35
	elif _invulnerable_left > 0.0 and _flash_left <= 0.0:
		alpha = 0.45 if int(_invulnerable_left * 20.0) % 2 == 0 else 1.0
	_sprite.modulate.a = alpha
	_overlay.queue_redraw()


## Déclenche l'arc de lame rouge et la poussée (appelé à chaque salve).
func _on_fired_visual(dir: Vector2) -> void:
	_slash_dir = dir.normalized() if dir.length_squared() > 0.0001 else aim_direction
	_slash_left = SLASH_DURATION
	_kick_left = KICK_DURATION


func _draw() -> void:
	var alpha: float = 0.35 if not _alive else 1.0
	# Ombre ovale bleu nuit sous les pieds
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 17.0, Color(COL_SHADOW, COL_SHADOW.a * alpha))
	draw_circle(Vector2.ZERO, 12.0, Color(COL_SHADOW, COL_SHADOW.a * 0.6 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not _alive:
		return
	# Flèche de visée au sol (lueur rouge), en perspective écrasée.
	var flat := Vector2(1.0, 0.6)
	var tip: Vector2 = aim_direction * 30.0 * flat
	var base: Vector2 = aim_direction * 21.0 * flat
	var side: Vector2 = aim_direction.orthogonal() * 6.0 * flat
	draw_colored_polygon(PackedVector2Array([tip * 1.12, base + side * 1.5, base - side * 1.5]), Color(COL_AIM, 0.3))
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), COL_AIM)


func _draw_overlay() -> void:
	# Arc de lame rouge lumineux devant le héros
	if _slash_left > 0.0:
		var t: float = 1.0 - _slash_left / SLASH_DURATION
		var center := Vector2(0.0, -SLASH_HEIGHT) + _slash_dir * 8.0
		var a0: float = _slash_dir.angle()
		var sweep: float = lerpf(0.35, 1.0, minf(t * 2.0, 1.0))
		var from: float = a0 - SLASH_HALF_ANGLE
		var to: float = a0 - SLASH_HALF_ANGLE + SLASH_HALF_ANGLE * 2.0 * sweep
		var fade: float = 1.0 - maxf(t - 0.4, 0.0) / 0.6
		_draw_crescent(center, SLASH_RADIUS + 4.0, 11.0, from, to, Color(COL_SLASH, 0.28 * fade))
		_draw_crescent(center, SLASH_RADIUS, 7.0, from, to, Color(COL_SLASH, 0.85 * fade))
		_draw_crescent(center, SLASH_RADIUS + 1.0, 2.5, from, to, Color(COL_SLASH_CORE, 0.9 * fade))
	# Barre de vie (panneau bleu nuit) au-dessus de la tête
	var w: float = 40.0
	var h: float = 5.0
	var top_left := Vector2(-w * 0.5, -SPRITE_WORLD_HEIGHT - 9.0)
	var ratio: float = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_overlay.draw_rect(Rect2(top_left - Vector2(1.5, 1.5), Vector2(w + 3, h + 3)), Color(0.07, 0.1, 0.18, 0.9))
	_overlay.draw_rect(Rect2(top_left, Vector2(w, h)), Color(0.25, 0.05, 0.07))
	var hp_col: Color = Color(0.35, 0.9, 0.35).lerp(Color(0.95, 0.2, 0.15), 1.0 - ratio)
	_overlay.draw_rect(Rect2(top_left, Vector2(w * ratio, h)), hp_col)


## Croissant : épais au milieu, effilé aux extrémités, aplati en perspective.
func _draw_crescent(center: Vector2, radius: float, thickness: float, from: float, to: float, col: Color) -> void:
	var n: int = 14
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var flat := Vector2(1.0, 0.7)
	for i: int in n + 1:
		var k: float = float(i) / float(n)
		var a: float = lerpf(from, to, k)
		var th: float = thickness * sin(k * PI)
		var dir := Vector2(cos(a), sin(a))
		outer.append(center + dir * (radius + th * 0.5) * flat)
		inner.append(center + dir * (radius - th * 0.5) * flat)
	inner.reverse()
	outer.append_array(inner)
	_overlay.draw_colored_polygon(outer, col)
