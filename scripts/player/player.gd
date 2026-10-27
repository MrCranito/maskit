class_name Player
extends CharacterBody2D
## Joueur (paysage, double stick).
## - Déplacement : stick gauche (TouchJoystick side=left) ou ZQSD/WASD/flèches.
##   Accélération/décélération douces (courbe exponentielle + pas linéaire minimal),
##   vitesse constante en diagonale, glissement le long des murs (move_and_slide).
## - Visée/tir : stick droit (tir continu au-delà de la zone morte) ; PC : souris pour
##   viser, clic gauche (ou Espace) pour tirer. Plus de tir automatique.
## - Visuel : AnimatedSprite2D `hero_frames.tres` (run_/idle_<dir8>) si présent, sinon
##   SVG kitsune animés en code (rebond, inclinaison, écrasement). Arme tenue tournée
##   vers `aim_direction`, recul, éclair de bouche, projectiles partant du canon.
## - Performance : aucun queue_redraw par frame (les dessins sont faits une fois ou
##   sur changement de valeur), aucune allocation dans _process/_physics_process.
## Couche player (2), masque world (1) + enemies (4). Groupes : player, damageable.

## Émis à chaque tir (direction normalisée).
signal fired(direction: Vector2)
## Émis quand le joueur entre / sort d'une cachette.
signal hidden_changed(hidden: bool, spot: Node)

const LAYER_PLAYER := 2
const MASK_WORLD := 1
const MASK_ENEMIES := 4
## Rayon du corps (collision aux pieds, cf. player.tscn).
const BODY_RADIUS := 15.0
const DEFAULT_WEAPON_PATH := "res://data/weapons/starter_revolver.tres"
const FALLBACK_WEAPON_PATH := "res://data/weapons/starter_bow.tres"

const HERO_FRAMES_PATH := "res://assets/sprites/hero3d/hero_frames.tres"
const HERO_META_PATH := "res://assets/sprites/hero3d/hero_meta.json"
const WEAPON_SPRITE_DIR := "res://assets/sprites/weapons/"
const DEFAULT_WEAPON_SPRITE_ID := "revolver"

## Directions 8 voies, dans l'ordre des angles écran (y vers le bas) : 0 = est, puis sens horaire.
const DIR8_NAMES: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const RUN_ANIMS: Array[StringName] = [&"run_e", &"run_se", &"run_s", &"run_sw", &"run_w", &"run_nw", &"run_n", &"run_ne"]
const IDLE_ANIMS: Array[StringName] = [&"idle_e", &"idle_se", &"idle_s", &"idle_sw", &"idle_w", &"idle_nw", &"idle_n", &"idle_ne"]

@export var weapon: WeaponData = null

var hp: float = 100.0
var max_hp: float = 100.0
## Conservé pour compatibilité (debug) : plus de ciblage automatique, toujours null.
var current_target: Node2D = null
## Direction de visée (normalisée). Suit le stick droit / la souris ; sinon le déplacement.
var aim_direction: Vector2 = Vector2.RIGHT

# --- Valeurs d'équilibrage (balance.cfg) ---
var move_speed: float = 250.0
var acceleration: float = 2400.0
var deceleration: float = 3200.0
var accel_sharpness: float = 18.0
var turn_boost: float = 1.8
var invulnerability_duration: float = 0.6
var hit_flash_duration: float = 0.12
var noise_walk: float = 0.35
var noise_fire_decay: float = 0.6
var hide_exit_threshold: float = 0.5
var hide_exit_grace: float = 0.3
var hidden_alpha: float = 0.35
var camera_lookahead: float = 110.0
var camera_lookahead_speed: float = 4.0
var camera_shake_enabled: bool = true
var camera_shake_amount: float = 2.5
var camera_shake_duration: float = 0.09

var _fire_cooldown: float = 0.0
var _invulnerable_left: float = 0.0
var _flash_left: float = 0.0
var _is_moving: bool = false
var _alive: bool = true
var _move_joystick: TouchJoystick = null
var _aim_joystick: TouchJoystick = null
var _joysticks_looked_up: bool = false
## Visée active ce tick (stick droit poussé, ou souris réelle).
var _aiming: bool = false
var _aim_stick_firing: bool = false
## Bouton de tir PC (clic gauche réel ou Espace) maintenu.
var _manual_fire_held: bool = false
## La souris est le dernier périphérique de visée utilisé (événements non émulés).
var _mouse_aim_active: bool = false
var _fire_noise: float = 0.0
var _hidden: bool = false
var _hide_spot: Node = null
var _hide_time: float = 0.0
var _pre_hide_position: Vector2 = Vector2.ZERO
var _saved_layer: int = LAYER_PLAYER
var _saved_mask: int = MASK_WORLD | MASK_ENEMIES
var _cam_look: Vector2 = Vector2.ZERO
var _shake_left: float = 0.0

@onready var camera: Camera2D = $Camera2D
@onready var projectile_pool: ProjectilePool = $ProjectilePool


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = LAYER_PLAYER
	collision_mask = MASK_WORLD | MASK_ENEMIES
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	_load_balance()
	if weapon == null:
		weapon = load_default_weapon()
	hp = max_hp
	_build_visual()
	_setup_camera()
	EventBus.player_spawned.emit(self)


static func load_default_weapon() -> WeaponData:
	for path: String in [DEFAULT_WEAPON_PATH, FALLBACK_WEAPON_PATH]:
		if ResourceLoader.exists(path):
			var w := load(path) as WeaponData
			if w != null:
				return w
	return WeaponData.new()


func _load_balance() -> void:
	max_hp = Balance.get_float("player", "max_hp", 100.0)
	move_speed = Balance.get_float("player", "move_speed", 250.0)
	acceleration = Balance.get_float("player", "acceleration", 2400.0)
	deceleration = Balance.get_float("player", "deceleration", 3200.0)
	accel_sharpness = Balance.get_float("player", "accel_sharpness", 18.0)
	turn_boost = Balance.get_float("player", "turn_boost", 1.8)
	invulnerability_duration = Balance.get_float("player", "invulnerability_duration", 0.6)
	hit_flash_duration = Balance.get_float("player", "hit_flash_duration", 0.12)
	noise_walk = Balance.get_float("player", "noise_walk", 0.35)
	noise_fire_decay = Balance.get_float("player", "noise_fire_decay", 0.6)
	hide_exit_threshold = Balance.get_float("player", "hide_exit_threshold", 0.5)
	hide_exit_grace = Balance.get_float("player", "hide_exit_grace", 0.3)
	hidden_alpha = Balance.get_float("player", "hidden_alpha", 0.35)
	camera_lookahead = Balance.get_float("camera", "lookahead", 110.0)
	camera_lookahead_speed = Balance.get_float("camera", "lookahead_speed", 4.0)
	camera_shake_enabled = bool(Balance.get_value("camera", "shake_on_fire", true))
	camera_shake_amount = Balance.get_float("camera", "shake_amount", 2.5)
	camera_shake_duration = Balance.get_float("camera", "shake_duration", 0.09)


func _setup_camera() -> void:
	# Interpolation physique : la caméra calcule son défilement au rythme de la physique
	# (le joueur bouge en _physics_process) et le rendu interpole entre deux ticks.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = Balance.get_float("camera", "smoothing_speed", 7.0)
	var z: float = Balance.get_float("camera", "zoom", 1.1)
	camera.zoom = Vector2(z, z)
	camera.enabled = true
	camera.make_current()


# --- Boucle physique ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)
	_fire_noise = maxf(_fire_noise - delta / maxf(noise_fire_decay, 0.01), 0.0)
	if not _alive:
		_update_camera(delta)
		return

	var input_dir: Vector2 = get_move_input()
	if _hidden:
		_hide_time += delta
		velocity = Vector2.ZERO
		_is_moving = false
		if _hide_time >= hide_exit_grace and input_dir.length() >= hide_exit_threshold:
			set_hidden(false)
		_update_camera(delta)
		return

	velocity = step_velocity(velocity, input_dir, move_speed, acceleration, deceleration,
		accel_sharpness, turn_boost, delta)
	move_and_slide()
	_is_moving = velocity.length_squared() > 25.0 and input_dir != Vector2.ZERO

	_update_aim(input_dir)
	_update_fire()
	_update_camera(delta)


## Logique pure : nouvelle vitesse vers `input * max_speed` (input de longueur 0..1).
## Approche exponentielle (réactive au début) avec un pas linéaire minimal (arrêt net,
## pas de glisse). Contre-braquage accéléré par `turn_mult`.
static func step_velocity(vel: Vector2, input: Vector2, max_speed: float, accel: float, decel: float,
		sharpness: float, turn_mult: float, delta: float) -> Vector2:
	var target: Vector2 = input.limit_length(1.0) * max_speed
	var rate: float = decel
	if target != Vector2.ZERO:
		rate = accel
		if vel.dot(target) < 0.0:
			rate *= turn_mult
	var dist: float = vel.distance_to(target)
	if dist <= 0.0001:
		return target
	var step: float = maxf(rate * delta, dist * (1.0 - exp(-sharpness * delta)))
	return vel.move_toward(target, step)


## Vecteur de déplacement (longueur 0..1). Stick gauche prioritaire s'il est poussé.
func get_move_input() -> Vector2:
	_find_joysticks()
	if _move_joystick != null:
		var out: Vector2 = _move_joystick.output
		if out != Vector2.ZERO:
			return out.limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## Sortie du stick droit (ZERO s'il est absent ou relâché).
func get_aim_input() -> Vector2:
	_find_joysticks()
	if _aim_joystick != null:
		return _aim_joystick.output
	return Vector2.ZERO


func _find_joysticks() -> void:
	if _joysticks_looked_up and (_move_joystick == null or is_instance_valid(_move_joystick)) \
			and (_aim_joystick == null or is_instance_valid(_aim_joystick)):
		return
	_joysticks_looked_up = true
	_move_joystick = get_tree().get_first_node_in_group(TouchJoystick.GROUP_MOVE) as TouchJoystick
	_aim_joystick = get_tree().get_first_node_in_group(TouchJoystick.GROUP_AIM) as TouchJoystick


## À appeler si les joysticks sont recréés (changement d'UI).
func refresh_joysticks() -> void:
	_joysticks_looked_up = false


## Branche explicitement les sticks (UI qui les crée, tests).
func set_joysticks(move_stick: TouchJoystick, aim_stick: TouchJoystick) -> void:
	_move_joystick = move_stick
	_aim_joystick = aim_stick
	_joysticks_looked_up = true


# --- Entrées souris / clavier (PC) ------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Appui de tir : seulement s'il n'a pas été pris par l'interface (boutons, inventaire).
	if event.is_action_pressed("fire_manual") and not _is_emulated(event):
		_manual_fire_held = true
		if event is InputEventMouseButton:
			_mouse_aim_active = true


func _input(event: InputEvent) -> void:
	# Relâchement toujours lu (même si l'interface a capté l'événement).
	if event.is_action_released("fire_manual"):
		_manual_fire_held = false
	elif event is InputEventMouseMotion and not _is_emulated(event):
		_mouse_aim_active = true


## Les touches génèrent des événements souris émulés : on les ignore pour la visée PC.
static func _is_emulated(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION


# --- Visée et tir ------------------------------------------------------------

func _update_aim(move_dir: Vector2) -> void:
	var stick: Vector2 = get_aim_input()
	_aim_stick_firing = stick != Vector2.ZERO
	_aiming = false
	if _aim_stick_firing:
		aim_direction = stick.normalized()
		_aiming = true
	elif _mouse_aim_active:
		var to_mouse: Vector2 = get_global_mouse_position() - (global_position + Vector2(0.0, -_hand_height))
		if to_mouse.length_squared() > 16.0:
			aim_direction = to_mouse.normalized()
		_aiming = true
	elif move_dir != Vector2.ZERO:
		aim_direction = move_dir.normalized()


func _update_fire() -> void:
	if weapon == null or _fire_cooldown > 0.0:
		return
	if _aim_stick_firing or _manual_fire_held:
		fire(aim_direction)


## Tire une salve dans `dir` selon l'arme (nombre de projectiles, dispersion), depuis le canon.
func fire(dir: Vector2) -> void:
	if weapon == null or _hidden or not _alive:
		return
	var d0: Vector2 = dir.normalized() if dir != Vector2.ZERO else aim_direction
	_fire_cooldown = weapon.get_fire_interval()
	_fire_noise = 1.0
	var origin: Vector2 = get_muzzle_position(d0)
	var count: int = maxi(weapon.projectile_count, 1)
	var spread: float = deg_to_rad(weapon.spread_degrees)
	for i: int in count:
		var offset: float = 0.0
		if count > 1:
			offset = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(count - 1))
		projectile_pool.spawn(origin, d0.rotated(offset), weapon, self)
	_on_fired_visual(d0)
	fired.emit(d0)


## Position monde du bout du canon pour une visée `dir` (calcul logique, non interpolé).
func get_muzzle_position(dir: Vector2) -> Vector2:
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var flip: float = -1.0 if d.x < 0.0 else 1.0
	var local := Vector2(_muzzle_local.x, _muzzle_local.y * flip)
	return global_position + hand_offset(d, _hand_height, _hand_radius) + local.rotated(d.angle())


## Logique pure : position de la main (pivot de l'arme) relative aux pieds.
static func hand_offset(dir: Vector2, height: float, radius: float) -> Vector2:
	return Vector2(dir.x * radius, -height + dir.y * radius * 0.5)


# --- Caméra ------------------------------------------------------------------

func _update_camera(delta: float) -> void:
	# Anticipation : la caméra se décale doucement dans la direction de visée
	# (seulement quand on vise, sinon légèrement dans le sens de la marche).
	var want: Vector2 = Vector2.ZERO
	if _alive and not _hidden:
		if _aiming:
			want = aim_direction * camera_lookahead
		elif _is_moving:
			want = velocity / maxf(move_speed, 1.0) * camera_lookahead * 0.5
	_cam_look = _cam_look.lerp(want, 1.0 - exp(-camera_lookahead_speed * delta))
	camera.position = _cam_look
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
		var k: float = _shake_left / maxf(camera_shake_duration, 0.001)
		var amp: float = camera_shake_amount * k * k
		camera.offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO


# --- Bruit, cachettes --------------------------------------------------------

func is_moving() -> bool:
	return _is_moving


func is_hidden() -> bool:
	return _hidden


## Bruit émis (0..1) : 0 immobile ou caché, ~noise_walk en marche, 1 juste après un tir.
func get_noise_level() -> float:
	if _hidden or not _alive:
		return 0.0
	return compute_noise(velocity.length() / maxf(move_speed, 1.0), _fire_noise, noise_walk)


## Logique pure du bruit : max(bruit de marche proportionnel à la vitesse, bruit de tir).
static func compute_noise(speed_ratio: float, fire_noise: float, walk_noise: float) -> float:
	var walk: float = walk_noise * clampf(speed_ratio, 0.0, 1.0) if speed_ratio > 0.05 else 0.0
	return clampf(maxf(walk, fire_noise), 0.0, 1.0)


## Entre (`on`=true) ou sort d'une cachette. Caché : immobile, ne tire pas, bruit 0,
## silhouette semi-transparente, collisions coupées. On ressort en poussant le stick
## gauche (ou les touches) ou en rappelant set_hidden(false) via l'interaction.
func set_hidden(on: bool, spot: Node = null) -> void:
	if on == _hidden:
		if on and spot != null:
			_hide_spot = spot
		return
	_hidden = on
	if on:
		_hide_spot = spot
		_hide_time = 0.0
		_pre_hide_position = global_position
		_saved_layer = collision_layer
		_saved_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
		velocity = Vector2.ZERO
		_is_moving = false
		_manual_fire_held = false
		if spot is Node2D:
			global_position = (spot as Node2D).global_position
			reset_physics_interpolation()
	else:
		collision_layer = _saved_layer
		collision_mask = _saved_mask
		global_position = _pre_hide_position
		reset_physics_interpolation()
		spot = _hide_spot
		_hide_spot = null
	_apply_hidden_visual()
	hidden_changed.emit(_hidden, spot)


func get_hide_spot() -> Node:
	return _hide_spot


# --- Dégâts ------------------------------------------------------------------

func take_damage(amount: float, _source: Node) -> void:
	if not _alive or _invulnerable_left > 0.0 or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_invulnerable_left = invulnerability_duration
	_flash_left = hit_flash_duration
	EventBus.player_damaged.emit(amount, hp, max_hp)
	_hp_bar_dirty()
	if hp <= 0.0:
		_die()


func is_alive() -> bool:
	return _alive


func heal(amount: float) -> void:
	if _alive:
		hp = minf(hp + amount, max_hp)
		_hp_bar_dirty()


func _die() -> void:
	_alive = false
	velocity = Vector2.ZERO
	_is_moving = false
	_manual_fire_held = false
	current_target = null
	if _hidden:
		set_hidden(false)
	_apply_hidden_visual()
	EventBus.player_died.emit()


func get_debug_info() -> Dictionary:
	return {
		"hp": hp,
		"max_hp": max_hp,
		"speed": velocity.length(),
		"aim": aim_direction,
		"dir8": DIR8_NAMES[_facing_index],
		"aiming": _aiming,
		"noise": get_noise_level(),
		"hidden": _hidden,
		"fire_cooldown": _fire_cooldown,
		"invulnerable": _invulnerable_left > 0.0,
		"weapon": weapon.display_name if weapon != null else "-",
		"sprite": "hero3d" if _anim_sprite != null else "svg",
		"pool_active": projectile_pool.get_active_count() if projectile_pool != null else 0,
	}


# --- Directions --------------------------------------------------------------

## Logique pure : index 0..7 (e, se, s, sw, w, nw, n, ne) de la direction `v` (écran, y vers le bas).
## `prev` >= 0 active une hystérésis de `hysteresis` radians pour éviter le scintillement.
static func dir8_index(v: Vector2, prev: int = -1, hysteresis: float = 0.0) -> int:
	if v == Vector2.ZERO:
		return maxi(prev, 0)
	var a: float = v.angle()
	if prev >= 0 and hysteresis > 0.0:
		var center: float = float(prev) * PI * 0.25
		if absf(angle_difference(center, a)) <= PI * 0.125 + hysteresis:
			return prev
	return wrapi(roundi(a / (PI * 0.25)), 0, 8)


static func dir8_name(v: Vector2) -> String:
	return DIR8_NAMES[dir8_index(v)]


# =============================================================================
# Visuel
# =============================================================================
# Hiérarchie (construite en code) :
#   Shadow (z -3, dessin unique) · AimMarker (z -2, dessin unique, tourné)
#   Dust (CPUParticles2D, z -1)
#   Visual (rebond/inclinaison) → Body (AnimatedSprite2D ou Sprite2D)
#                               → WeaponPivot (z ±1) → WeaponSprite / revolver dessiné → MuzzleFlash
#   HpBar (redessinée seulement quand les PV changent)

const TEX_IDLE: Texture2D = preload("res://assets/sprites/hero/hero_kitsune.svg")
const TEX_WALK: Array[Texture2D] = [
	preload("res://assets/sprites/hero/hero_kitsune_walk_1.svg"),
	preload("res://assets/sprites/hero/hero_kitsune_walk_2.svg"),
]
const HIT_FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
## Hauteur du héros SVG en unités monde.
const SPRITE_WORLD_HEIGHT := 54.0
## Marge transparente sous les pieds dans le SVG (viewBox 200 de haut, pieds à y≈197).
const SPRITE_FOOT_MARGIN := 3.0 / 200.0

const COL_SHADOW := Color(0.07, 0.1, 0.25, 0.45)
const COL_AIM := Color(1.0, 0.25, 0.15)
const COL_FLASH_OUT := Color(1.0, 0.62, 0.18, 0.85)
const COL_FLASH_IN := Color(1.0, 0.95, 0.7, 1.0)

var _visual: Node2D = null
var _body: Node2D = null
var _anim_sprite: AnimatedSprite2D = null
var _svg_sprite: Sprite2D = null
var _flash_mat: ShaderMaterial = null
var _weapon_pivot: Node2D = null
var _weapon_holder: Node2D = null
var _muzzle_flash: Node2D = null
var _aim_marker: Node2D = null
var _aim_marker_rot: Node2D = null
var _hp_bar: Node2D = null
var _shadow: Node2D = null
var _dust: CPUParticles2D = null

var _body_base_scale: float = 1.0
var _body_height: float = SPRITE_WORLD_HEIGHT
var _hand_height: float = 24.0
var _hand_radius: float = 10.0
var _muzzle_local: Vector2 = Vector2(22.0, -3.0)
var _anim_ref_speed: float = 250.0
var _facing_index: int = 0
var _current_anim: StringName = &""
var _walk_phase: float = 0.0
var _breath_time: float = 0.0
var _recoil_left: float = 0.0
var _flash_vis_left: float = 0.0
var _last_flash_amount: float = -1.0
var _last_alpha: float = -1.0
var _weapon_behind: bool = false
var _svg_frame: int = -1

# Réglages visuels (balance.cfg [player_visual])
var _bounce_px: float = 3.0
var _tilt_rad: float = 0.09
var _squash: float = 0.06
var _stride_px: float = 34.0
var _recoil_px: float = 5.0
var _recoil_time: float = 0.09
var _flash_time: float = 0.05
var _dir_hysteresis: float = 0.12


func _build_visual() -> void:
	_bounce_px = Balance.get_float("player_visual", "bounce_px", 3.0)
	_tilt_rad = deg_to_rad(Balance.get_float("player_visual", "tilt_deg", 5.0))
	_squash = Balance.get_float("player_visual", "squash", 0.06)
	_stride_px = Balance.get_float("player_visual", "stride_px", 34.0)
	_recoil_px = Balance.get_float("player_visual", "recoil_px", 5.0)
	_recoil_time = Balance.get_float("player_visual", "recoil_time", 0.09)
	_flash_time = Balance.get_float("player_visual", "muzzle_flash_time", 0.05)
	_dir_hysteresis = deg_to_rad(Balance.get_float("player_visual", "dir_hysteresis_deg", 7.0))
	_hand_height = Balance.get_float("player_visual", "hand_height", 24.0)
	_hand_radius = Balance.get_float("player_visual", "hand_radius", 10.0)
	_anim_ref_speed = move_speed

	_shadow = _make_drawn_node("Shadow", -3, _draw_shadow)

	_aim_marker = Node2D.new()
	_aim_marker.name = "AimMarker"
	_aim_marker.z_index = -2
	_aim_marker.scale = Vector2(1.0, 0.6)  # perspective : flèche écrasée au sol
	_aim_marker.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_aim_marker)
	_aim_marker_rot = Node2D.new()
	_aim_marker_rot.draw.connect(_draw_aim_marker)
	_aim_marker.add_child(_aim_marker_rot)

	if bool(Balance.get_value("player_visual", "dust_enabled", true)):
		_build_dust()

	_visual = Node2D.new()
	_visual.name = "Visual"
	# Animé dans _process (rebond, recul, arme) : pas d'interpolation physique propre,
	# il suit la position interpolée du joueur.
	_visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_visual)
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = HIT_FLASH_SHADER
	if not _build_hero3d():
		_build_svg_body()
	_build_weapon()

	_hp_bar = Node2D.new()
	_hp_bar.name = "HpBar"
	_hp_bar.z_index = 2
	_hp_bar.position = Vector2(0.0, -_body_height - 9.0)
	_hp_bar.draw.connect(_draw_hp_bar)
	add_child(_hp_bar)
	_update_facing_and_weapon(true)


func _make_drawn_node(node_name: String, z: int, drawer: Callable) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.z_index = z
	n.draw.connect(drawer)
	add_child(n)
	return n


## Sprite 3D pré-rendu (artiste). Renvoie false si absent ou incomplet.
func _build_hero3d() -> bool:
	if not ResourceLoader.exists(HERO_FRAMES_PATH):
		return false
	var frames := load(HERO_FRAMES_PATH) as SpriteFrames
	if frames == null or not frames.has_animation(IDLE_ANIMS[0]):
		push_warning("Player: %s invalide, repli SVG." % HERO_FRAMES_PATH)
		return false
	var meta: Dictionary = _read_json(HERO_META_PATH)
	var first: Texture2D = frames.get_frame_texture(IDLE_ANIMS[0], 0)
	var fs: Vector2 = Vector2(first.get_size()) if first != null else Vector2(128, 128)
	fs = _vec2_from(meta.get("frame_size"), fs)
	var feet: Vector2 = _vec2_from(meta.get("feet_offset"), Vector2(fs.x * 0.5, fs.y))
	var display_h: float = float(meta.get("display_height", SPRITE_WORLD_HEIGHT * 1.6))
	_anim_sprite = AnimatedSprite2D.new()
	_anim_sprite.name = "HeroSprite"
	_anim_sprite.sprite_frames = frames
	# Format de l'artiste : centered + offset = -(feet_offset - frame_size / 2)
	# → les pieds tombent à l'origine du joueur.
	_anim_sprite.centered = true
	_anim_sprite.offset = -(feet - fs * 0.5)
	_anim_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_body_base_scale = display_h / maxf(fs.y, 1.0)
	_anim_sprite.scale = Vector2.ONE * _body_base_scale
	_anim_sprite.material = _flash_mat
	# Hauteur visible du héros (barre de vie, main) : hero_height_px si fourni.
	_body_height = float(meta.get("hero_height_px", feet.y * 0.85)) * _body_base_scale
	if meta.has("hand_height"):
		_hand_height = float(meta["hand_height"])
	else:
		_hand_height = _body_height * 0.45
	_visual.add_child(_anim_sprite)
	_body = _anim_sprite
	_current_anim = &""
	return true


func _build_svg_body() -> void:
	_svg_sprite = Sprite2D.new()
	_svg_sprite.name = "HeroSprite"
	_svg_sprite.texture = TEX_IDLE
	_svg_sprite.centered = true
	_svg_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tex_h: float = float(TEX_IDLE.get_height())
	_body_base_scale = SPRITE_WORLD_HEIGHT / tex_h
	# Pieds (bas-centre) à l'origine.
	_svg_sprite.offset = Vector2(0.0, -tex_h * 0.5 + tex_h * SPRITE_FOOT_MARGIN)
	_svg_sprite.scale = Vector2.ONE * _body_base_scale
	_svg_sprite.material = _flash_mat
	_body_height = SPRITE_WORLD_HEIGHT
	_visual.add_child(_svg_sprite)
	_body = _svg_sprite


## Arme tenue : PNG + JSON de l'artiste si présents, sinon revolver dessiné en code.
func _build_weapon() -> void:
	_weapon_pivot = Node2D.new()
	_weapon_pivot.name = "WeaponPivot"
	_visual.add_child(_weapon_pivot)
	_weapon_holder = Node2D.new()
	_weapon_holder.name = "Weapon"
	_weapon_pivot.add_child(_weapon_holder)

	var png: String = WEAPON_SPRITE_DIR + DEFAULT_WEAPON_SPRITE_ID + ".png"
	var sprite_id: String = DEFAULT_WEAPON_SPRITE_ID
	# Sprite propre à l'arme (<id>.png, ou <id sans préfixe starter_>.png) s'il existe.
	if weapon != null and not String(weapon.id).is_empty():
		for cand: String in [String(weapon.id), String(weapon.id).trim_prefix("starter_")]:
			if ResourceLoader.exists(WEAPON_SPRITE_DIR + cand + ".png"):
				sprite_id = cand
				png = WEAPON_SPRITE_DIR + cand + ".png"
				break
	var tex: Texture2D = load(png) as Texture2D if ResourceLoader.exists(png) else null
	if tex != null:
		var meta: Dictionary = _read_json(WEAPON_SPRITE_DIR + sprite_id + ".json")
		var tsize := Vector2(tex.get_size())
		var grip: Vector2 = _vec2_from(meta.get("grip"), Vector2(tsize.x * 0.2, tsize.y * 0.6))
		var muzzle: Vector2 = _vec2_from(meta.get("muzzle"), Vector2(tsize.x, tsize.y * 0.3))
		var sc: float = float(meta.get("scale", 26.0 / maxf(tsize.x, 1.0)))
		var spr := Sprite2D.new()
		spr.name = "WeaponSprite"
		spr.texture = tex
		spr.centered = false
		spr.offset = -grip
		spr.scale = Vector2(sc, sc)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_weapon_holder.add_child(spr)
		_muzzle_local = (muzzle - grip) * sc
	else:
		var drawn := Node2D.new()
		drawn.name = "RevolverDrawn"
		drawn.draw.connect(_draw_revolver.bind(drawn))
		_weapon_holder.add_child(drawn)
		_muzzle_local = Vector2(22.0, -3.0)

	_muzzle_flash = Node2D.new()
	_muzzle_flash.name = "MuzzleFlash"
	_muzzle_flash.position = _muzzle_local
	_muzzle_flash.visible = false
	_muzzle_flash.draw.connect(_draw_muzzle_flash)
	_weapon_holder.add_child(_muzzle_flash)


func _build_dust() -> void:
	_dust = CPUParticles2D.new()
	_dust.name = "Dust"
	_dust.z_index = -1
	_dust.emitting = false
	_dust.amount = int(Balance.get_value("player_visual", "dust_amount", 8))
	_dust.lifetime = 0.45
	_dust.local_coords = false
	_dust.position = Vector2(0.0, -2.0)
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_dust.emission_sphere_radius = 5.0
	_dust.direction = Vector2.UP
	_dust.spread = 40.0
	_dust.gravity = Vector2(0.0, 30.0)
	_dust.initial_velocity_min = 10.0
	_dust.initial_velocity_max = 24.0
	_dust.scale_amount_min = 2.0
	_dust.scale_amount_max = 4.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	_dust.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.72, 0.52, 0.45))
	grad.set_color(1, Color(0.85, 0.72, 0.52, 0.0))
	_dust.color_ramp = grad
	add_child(_dust)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _vec2_from(v: Variant, fallback: Vector2) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	if v is Dictionary and (v as Dictionary).has("x"):
		return Vector2(float(v["x"]), float(v.get("y", 0.0)))
	return fallback


# --- Animation (par frame : uniquement des affectations de propriétés) -------

func _process(delta: float) -> void:
	if _visual == null:
		return
	_recoil_left = maxf(_recoil_left - delta, 0.0)
	if _flash_vis_left > 0.0:
		_flash_vis_left -= delta
		if _flash_vis_left <= 0.0:
			_muzzle_flash.visible = false

	_update_facing_and_weapon(false)
	var speed: float = velocity.length()
	var speed_ratio: float = speed / maxf(_anim_ref_speed, 1.0)
	if _anim_sprite != null:
		_animate_hero3d(speed_ratio)
	else:
		_animate_svg(delta, speed, speed_ratio)

	# Recul de l'arme (le long du canon).
	var rk: float = _recoil_left / maxf(_recoil_time, 0.001)
	_weapon_holder.position.x = -_recoil_px * rk * rk

	if _dust != null:
		var want_dust: bool = _alive and not _hidden and speed_ratio > 0.6
		if want_dust != _dust.emitting:
			_dust.emitting = want_dust

	# Flash blanc (shader) + clignotement d'invulnérabilité : seulement si la valeur change.
	var fa: float = clampf(_flash_left / maxf(hit_flash_duration, 0.001), 0.0, 1.0)
	if fa != _last_flash_amount:
		_last_flash_amount = fa
		_flash_mat.set_shader_parameter("flash_amount", fa)
	var alpha: float = 1.0
	if not _alive:
		alpha = 0.35
	elif _hidden:
		alpha = hidden_alpha
	elif _invulnerable_left > 0.0 and _flash_left <= 0.0:
		alpha = 0.45 if int(_invulnerable_left * 20.0) % 2 == 0 else 1.0
	if alpha != _last_alpha:
		_last_alpha = alpha
		_visual.modulate.a = alpha


func _animate_hero3d(speed_ratio: float) -> void:
	var running: bool = _alive and not _hidden and _is_moving
	var anim: StringName = RUN_ANIMS[_facing_index] if running else IDLE_ANIMS[_facing_index]
	if anim != _current_anim and _anim_sprite.sprite_frames.has_animation(anim):
		_current_anim = anim
		_anim_sprite.play(anim)
	var sc: float = clampf(speed_ratio, 0.45, 1.3) if running else 1.0
	if absf(_anim_sprite.speed_scale - sc) > 0.02:
		_anim_sprite.speed_scale = sc
	# Légère inclinaison dans le sens de la course + recul.
	var tilt: float = clampf(velocity.x / maxf(move_speed, 1.0), -1.0, 1.0) * _tilt_rad * 0.5
	_visual.rotation = tilt
	_visual.position = -aim_direction * 1.5 * _recoil_curve()


func _animate_svg(delta: float, speed: float, speed_ratio: float) -> void:
	var sx: float = 1.0
	var sy: float = 1.0
	var y: float = 0.0
	var rot: float = 0.0
	if _alive and not _hidden and _is_moving:
		# Une foulée tous les `_stride_px` parcourus : cadence proportionnelle à la vitesse.
		_walk_phase += speed * delta / maxf(_stride_px, 1.0) * PI
		var s: float = absf(sin(_walk_phase))
		y = -s * _bounce_px * clampf(speed_ratio, 0.3, 1.0)
		var land: float = 1.0 - s  # 1 au contact du sol
		sx = 1.0 + _squash * land * speed_ratio
		sy = 1.0 - _squash * land * speed_ratio
		rot = clampf(velocity.x / maxf(move_speed, 1.0), -1.0, 1.0) * _tilt_rad + sin(_walk_phase * 2.0) * _tilt_rad * 0.25
		var frame: int = 1 if fmod(_walk_phase, TAU) < PI else 2
		_set_svg_frame(frame)
	else:
		_walk_phase = 0.0
		_breath_time += delta
		sy = 1.0 + sin(_breath_time * 2.6) * 0.022
		sx = 1.0 - (sy - 1.0) * 0.5
		_set_svg_frame(0)
	var face_left: bool = _facing_index >= 3 and _facing_index <= 5
	_svg_sprite.flip_h = face_left
	_svg_sprite.scale = Vector2(_body_base_scale * sx, _body_base_scale * sy)
	_visual.position = Vector2(0.0, y) - aim_direction * 1.5 * _recoil_curve()
	_visual.rotation = rot


func _set_svg_frame(frame: int) -> void:
	if frame == _svg_frame:
		return
	_svg_frame = frame
	_svg_sprite.texture = TEX_IDLE if frame == 0 else TEX_WALK[frame - 1]


func _recoil_curve() -> float:
	var k: float = _recoil_left / maxf(_recoil_time, 0.001)
	return k * k


## Orientation 8 voies (visée si on vise, sinon mouvement) + arme tournée vers la visée.
func _update_facing_and_weapon(force: bool) -> void:
	var facing_vec: Vector2 = aim_direction
	if not _aiming and _is_moving:
		facing_vec = velocity
	_facing_index = dir8_index(facing_vec, -1 if force else _facing_index, _dir_hysteresis)

	var a: float = aim_direction.angle()
	_weapon_pivot.position = hand_offset(aim_direction, _hand_height, _hand_radius)
	_weapon_pivot.rotation = a
	var flip_y: float = -1.0 if aim_direction.x < 0.0 else 1.0
	if _weapon_pivot.scale.y != flip_y:
		_weapon_pivot.scale = Vector2(1.0, flip_y)
	# Visée vers le haut : l'arme passe derrière le corps.
	var behind: bool = aim_direction.y < -0.35
	if force or behind != _weapon_behind:
		_weapon_behind = behind
		_weapon_pivot.z_index = -1 if behind else 1
	_weapon_pivot.visible = _alive and not _hidden
	_aim_marker_rot.rotation = a
	_aim_marker.visible = _alive and not _hidden


func _on_fired_visual(_dir: Vector2) -> void:
	_recoil_left = _recoil_time
	_flash_vis_left = _flash_time
	_muzzle_flash.rotation = randf_range(-0.3, 0.3)
	_muzzle_flash.visible = true
	if camera_shake_enabled:
		_shake_left = camera_shake_duration


func _apply_hidden_visual() -> void:
	if _shadow != null:
		_shadow.visible = not _hidden
	if _hp_bar != null:
		_hp_bar.visible = not _hidden
		_hp_bar.queue_redraw()
	if _weapon_pivot != null:
		_update_facing_and_weapon(true)


func _hp_bar_dirty() -> void:
	if _hp_bar != null:
		_hp_bar.queue_redraw()


# --- Dessins (appelés une fois ou sur changement) ----------------------------

func _draw_shadow() -> void:
	_shadow.draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.42))
	_shadow.draw_circle(Vector2.ZERO, 17.0, COL_SHADOW)
	_shadow.draw_circle(Vector2.ZERO, 12.0, Color(COL_SHADOW, COL_SHADOW.a * 0.6))


func _draw_aim_marker() -> void:
	# Flèche au sol pointant vers +X (le nœud parent l'écrase en perspective).
	var c: Node2D = _aim_marker_rot
	c.draw_colored_polygon(PackedVector2Array([Vector2(34, 0), Vector2(22, -10), Vector2(22, 10)]), Color(COL_AIM, 0.3))
	c.draw_colored_polygon(PackedVector2Array([Vector2(31, 0), Vector2(23, -6), Vector2(23, 6)]), COL_AIM)


func _draw_revolver(c: Node2D) -> void:
	# Revolver placeholder, poignée à l'origine, canon vers +X (≈ 26 px).
	var dark := Color(0.16, 0.16, 0.2)
	var steel := Color(0.55, 0.57, 0.63)
	var wood := Color(0.47, 0.27, 0.13)
	var gold := Color(0.91, 0.72, 0.36)
	# Poignée en bois (inclinée vers le bas-arrière)
	c.draw_colored_polygon(PackedVector2Array([Vector2(-3, -4), Vector2(4, -4), Vector2(2, 6), Vector2(-5, 7)]), wood)
	c.draw_polyline(PackedVector2Array([Vector2(-3, -4), Vector2(-5, 7), Vector2(2, 6), Vector2(4, -4)]), dark, 1.2, true)
	# Carcasse + barillet
	c.draw_rect(Rect2(Vector2(1, -7), Vector2(9, 6)), steel)
	c.draw_circle(Vector2(7, -4), 3.6, Color(0.45, 0.47, 0.53), true, -1.0, true)
	c.draw_arc(Vector2(7, -4), 3.6, 0.0, TAU, 16, dark, 1.0, true)
	# Canon
	c.draw_rect(Rect2(Vector2(9, -5.5), Vector2(14, 3)), steel)
	c.draw_line(Vector2(9, -5.5), Vector2(23, -5.5), Color(0.8, 0.82, 0.88), 1.0)
	c.draw_rect(Rect2(Vector2(9, -5.5), Vector2(14, 3)), dark, false, 1.0)
	# Pontet, chien, guidon or
	c.draw_arc(Vector2(5, 0), 2.6, 0.0, PI, 8, dark, 1.2, true)
	c.draw_line(Vector2(1, -7), Vector2(-1, -9), dark, 2.0, true)
	c.draw_line(Vector2(21, -5.5), Vector2(21, -7), gold, 1.5)


func _draw_muzzle_flash() -> void:
	var c: Node2D = _muzzle_flash
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(0, -5), Vector2(6, -2), Vector2(16, 0), Vector2(6, 2), Vector2(0, 5), Vector2(3, 0)]), COL_FLASH_OUT)
	c.draw_circle(Vector2(3, 0), 4.0, COL_FLASH_IN, true, -1.0, true)


func _draw_hp_bar() -> void:
	if _hidden:
		return
	var c: Node2D = _hp_bar
	var w: float = 40.0
	var h: float = 5.0
	var top_left := Vector2(-w * 0.5, 0.0)
	var ratio: float = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	c.draw_rect(Rect2(top_left - Vector2(1.5, 1.5), Vector2(w + 3, h + 3)), Color(0.07, 0.1, 0.18, 0.9))
	c.draw_rect(Rect2(top_left, Vector2(w, h)), Color(0.25, 0.05, 0.07))
	var hp_col: Color = Color(0.35, 0.9, 0.35).lerp(Color(0.95, 0.2, 0.15), 1.0 - ratio)
	c.draw_rect(Rect2(top_left, Vector2(w * ratio, h)), hp_col)
