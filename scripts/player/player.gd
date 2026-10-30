class_name Player
extends CharacterBody2D
## Joueur (paysage, double stick) — Exfil Rush.
## - Déplacement : stick gauche (TouchJoystick side=left) ou ZQSD/WASD/flèches.
##   Accélération/décélération douces, vitesse constante en diagonale, glissement le long
##   des murs. Vitesse × move_speed_mult de l'arme tenue (armes lourdes plus lentes).
## - Visée/tir : stick droit (tir continu au-delà de la zone morte) ; PC : souris pour viser,
##   clic gauche pour tirer (armes non automatiques : un tir par clic). Pas de tir automatique.
## - Armes : jusqu'à [arsenal] loadout_slots emplacements (WeaponLoadout), lus dans
##   GameState.raid_weapons à la création (vide → WeaponCatalog.get_starter()). Chargeur,
##   rechargement (auto quand vide, R pour forcer, annulé au changement d'arme), munitions
##   conservées par emplacement. Changement : weapon_next (Q physique / molette),
##   weapon_prev (molette), weapon_1..3, switch_to() (HUD).
## - Visuel : PlayerVisual (planches du skin, anims, recul, éclairs) ; effets poolés dans
##   CombatFx (douilles, fumée, impacts, explosions).
## - Performance : aucun queue_redraw par frame, aucune allocation dans _process/_physics_process.
## Couche player (2), masque world (1) + enemies (4). Groupes : player, damageable.

## Émis à chaque tir (direction normalisée).
signal fired(direction: Vector2)
## Émis quand le joueur entre / sort d'une cachette.
signal hidden_changed(hidden: bool, spot: Node)
## Armes tenues ou emplacement courant changés.
signal weapons_changed
## Munitions de l'arme courante (-1 = illimité) et taille du chargeur.
signal ammo_changed(ammo: int, magazine: int)
## Rechargement commencé / terminé (true = terminé normalement, false = annulé).
signal reload_started
signal reload_finished(completed: bool)
## Équipement (grenade, mine, C4, drone) ou ses charges changés.
signal gadget_changed

const LAYER_PLAYER := 2
const MASK_WORLD := 1
const MASK_ENEMIES := 4
## Rayon du corps (collision aux pieds, cf. player.tscn).
const BODY_RADIUS := 15.0
const DEFAULT_WEAPON_PATH := "res://data/weapons/starter_pistol.tres"
const FALLBACK_WEAPON_PATH := "res://data/weapons/starter_revolver.tres"

## Directions 8 voies, dans l'ordre des angles écran (y vers le bas) : 0 = est, puis sens horaire.
const DIR8_NAMES: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const RUN_ANIMS: Array[StringName] = [&"run_e", &"run_se", &"run_s", &"run_sw", &"run_w", &"run_nw", &"run_n", &"run_ne"]
const IDLE_ANIMS: Array[StringName] = [&"idle_e", &"idle_se", &"idle_s", &"idle_sw", &"idle_w", &"idle_nw", &"idle_n", &"idle_ne"]

var hp: float = 100.0
var max_hp: float = 100.0
## Conservé pour compatibilité (debug) : plus de ciblage automatique, toujours null.
var current_target: Node2D = null
## Direction de visée (normalisée). Suit le stick droit / la souris ; sinon le déplacement.
var aim_direction: Vector2 = Vector2.RIGHT

## Armes tenues (logique pure).
var loadout: WeaponLoadout = WeaponLoadout.new(3)
## Emplacement courant (lecture ; utiliser switch_to pour changer).
var current_slot: int:
	get:
		return loadout.current
## Arme courante (compatibilité). Affecter remplace l'arme de l'emplacement courant.
var weapon: WeaponData:
	get:
		return loadout.current_weapon()
	set(value):
		loadout.replace_current(value)
		if is_node_ready():
			_on_weapon_changed(false)

# --- Valeurs d'équilibrage (balance.cfg) ---
var move_speed: float = 250.0
var acceleration: float = 2400.0
var deceleration: float = 3200.0
var accel_sharpness: float = 18.0
var turn_boost: float = 1.8
var invulnerability_duration: float = 0.6
var hit_flash_duration: float = 0.12
var noise_walk: float = 0.35
## Demi-angle (°) du cône d'aide à la visée au stick (0 = désactivée).
var _aim_assist_deg: float = 12.0
var noise_fire_decay: float = 0.6
var hide_exit_threshold: float = 0.5
var hide_exit_grace: float = 0.3
var hidden_alpha: float = 0.35
var camera_lookahead: float = 110.0
var camera_lookahead_speed: float = 4.0
var camera_shake_enabled: bool = true
var camera_shake_amount: float = 2.5
var camera_shake_duration: float = 0.09
var _shake_mult: float = 1.0
var _zoom_kick_mult: float = 1.0
var _zoom_kick_recover: float = 6.0
var _smoke_burst_shots: int = 3
var _smoke_delay: float = 0.12
var _shells_enabled: bool = true

var _invulnerable_left: float = 0.0
var _is_moving: bool = false
var _alive: bool = true
var _move_joystick: TouchJoystick = null
var _aim_joystick: TouchJoystick = null
var _joysticks_looked_up: bool = false
## Visée active ce tick (stick droit poussé, ou souris réelle).
var _aiming: bool = false
var _aim_stick_firing: bool = false
## Bouton de tir PC (clic gauche réel) maintenu ; appui pas encore consommé (semi-auto).
var _manual_fire_held: bool = false
var _manual_fire_pending: bool = false
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
var _cam_base_zoom: Vector2 = Vector2.ONE
var _shake_left: float = 0.0
var _shake_time: float = 0.09
var _shake_amp: float = 0.0
var _zoom_kick: float = 0.0
var _last_zoom_kick: float = 0.0
var _was_reloading: bool = false
var _dry_fire_cooldown: float = 0.0
var _burst_shots: int = 0
var _since_shot: float = 10.0
var _pending_shell: float = -1.0
var _pending_shells: int = 0
## Salve de roquettes (M202) : tirs restants, délai, direction, arme.
var _salvo_left: int = 0
var _salvo_timer: float = 0.0
var _salvo_dir: Vector2 = Vector2.RIGHT
var _salvo_interval: float = 0.08
var _salvo_consumes: bool = false
## C4 posés en attente de détonation (2e appui).
var _c4_placed: Array[GadgetDevice] = []
var _active_drone: GadgetDrone = null
## Gravité faible : sur une case de layout.low_gravity_cells (mis à jour toutes les 0,1 s).
var in_low_gravity: bool = false
## Coop (scripts/net) : « à terre » (0 PV, en attente de réanimation) — immobile, ne tire pas.
var net_downed: bool = false
var _lowg_check: float = 0.0
var _lowg_accel_mult: float = 0.18
var _lowg_decel_mult: float = 0.06
var _lowg_sharpness_mult: float = 0.08
var _lowg_recoil_push: float = 6.0

@onready var camera: Camera2D = $Camera2D
@onready var projectile_pool: ProjectilePool = $ProjectilePool
var visual: PlayerVisual = null
## Statuts infligés par les ennemis (étourdi, renversé, piégé, aveuglé, en feu) ; créé à la demande.
var status: PlayerStatus = null


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = LAYER_PLAYER
	collision_mask = MASK_WORLD | MASK_ENEMIES
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	_load_balance()
	hp = max_hp
	var exported: WeaponData = loadout.current_weapon()
	loadout.resize(int(Balance.get_value("arsenal", "loadout_slots", 3)))
	visual = PlayerVisual.new()
	add_child(visual)
	visual.setup(self)
	if exported != null:
		loadout.set_weapons([exported])
	else:
		loadout.set_weapons(initial_weapons())
		if loadout.gadget == null and GameState.raid_gadget != null:
			loadout.set_gadget(GameState.raid_gadget)
	_on_weapon_changed(false)
	_setup_camera()
	EventBus.player_spawned.emit(self)


## Armes de départ : GameState.raid_weapons, sinon le pistolet de départ.
static func initial_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w: WeaponData in GameState.raid_weapons:
		if w != null and not w.is_gadget():
			out.append(w)
	if out.is_empty():
		out.append(load_default_weapon())
	return out


static func load_default_weapon() -> WeaponData:
	var starter: WeaponData = WeaponCatalog.get_starter()
	if starter != null:
		return starter
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
	_aim_assist_deg = Balance.get_float("player", "aim_assist_deg", 12.0)
	noise_fire_decay = Balance.get_float("player", "noise_fire_decay", 0.6)
	hide_exit_threshold = Balance.get_float("player", "hide_exit_threshold", 0.5)
	hide_exit_grace = Balance.get_float("player", "hide_exit_grace", 0.3)
	hidden_alpha = Balance.get_float("player", "hidden_alpha", 0.35)
	camera_lookahead = Balance.get_float("camera", "lookahead", 110.0)
	camera_lookahead_speed = Balance.get_float("camera", "lookahead_speed", 4.0)
	camera_shake_enabled = bool(Balance.get_value("camera", "shake_on_fire", true))
	camera_shake_amount = Balance.get_float("camera", "shake_amount", 2.5)
	camera_shake_duration = Balance.get_float("camera", "shake_duration", 0.09)
	_shake_mult = Balance.get_float("player_fx", "shake_mult", 1.0)
	_zoom_kick_mult = Balance.get_float("player_fx", "zoom_kick_mult", 1.0)
	_zoom_kick_recover = Balance.get_float("player_fx", "zoom_kick_recover", 6.0)
	_smoke_burst_shots = int(Balance.get_value("player_fx", "barrel_smoke_burst", 3))
	_smoke_delay = Balance.get_float("player_fx", "barrel_smoke_delay", 0.12)
	_shells_enabled = bool(Balance.get_value("player_fx", "shells", true))
	_salvo_interval = Balance.get_float("player_fx", "salvo_interval", 0.08)
	_lowg_accel_mult = Balance.get_float("low_gravity", "accel_mult", 0.18)
	_lowg_decel_mult = Balance.get_float("low_gravity", "decel_mult", 0.06)
	_lowg_sharpness_mult = Balance.get_float("low_gravity", "sharpness_mult", 0.08)
	_lowg_recoil_push = Balance.get_float("low_gravity", "recoil_push", 6.0)


func _setup_camera() -> void:
	# Interpolation physique : la caméra calcule son défilement au rythme de la physique.
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = Balance.get_float("camera", "smoothing_speed", 7.0)
	var z: float = Balance.get_float("camera", "zoom", 1.1)
	_cam_base_zoom = Vector2(z, z)
	camera.zoom = _cam_base_zoom
	camera.enabled = true
	camera.make_current()


# =============================================================================
# Armes (API du contrat Exfil Rush)
# =============================================================================

## Remplace toutes les armes tenues (taille ≤ emplacements, null = emplacement vide).
func set_weapons(list: Array[WeaponData]) -> void:
	var was_reloading: bool = loadout.is_reloading()
	var had_gadget: WeaponData = loadout.gadget
	loadout.set_weapons(list)
	if was_reloading:
		reload_finished.emit(false)
	_salvo_left = 0
	_on_weapon_changed(false)
	if loadout.gadget != had_gadget:
		gadget_changed.emit()


## Armes tenues (taille = nombre d'emplacements, null = vide). Copie.
func get_weapons() -> Array[WeaponData]:
	return loadout.get_weapons()


## Sélectionne l'emplacement `slot` (arme descend/remonte, rechargement annulé).
func switch_to(slot: int) -> void:
	var was_reloading: bool = loadout.is_reloading()
	if not loadout.switch_to(slot):
		return
	if was_reloading:
		reload_finished.emit(false)
	_pending_shells = 0
	_salvo_left = 0
	_play_sfx(&"weapon_switch")
	_on_weapon_changed(true)


## Arme suivante (`step` = -1 : précédente).
func next_weapon(step: int = 1) -> void:
	var i: int = loadout.cycle_slot(step)
	if i >= 0:
		switch_to(i)


## Équipe `w` dans l'emplacement courant ; renvoie l'arme remplacée (ou null) — l'appelant
## la remet dans le sac.
func equip_into_current_slot(w: WeaponData) -> WeaponData:
	if w != null and w.is_gadget():
		# Équipement : va dans l'emplacement d'équipement, renvoie l'ancien.
		return equip_gadget(w)
	var was_reloading: bool = loadout.is_reloading()
	var old: WeaponData = loadout.equip_into_current(w)
	if was_reloading:
		reload_finished.emit(false)
	_play_sfx(&"item_equip")
	_on_weapon_changed(true)
	return old


## Ids des armes tenues + équipement s'il reste des charges (extraction).
func get_carried_weapon_ids() -> Array[StringName]:
	return loadout.carried_ids()


# =============================================================================
# Équipement (contrat « Refonte n°2 »)
# =============================================================================

func get_gadget() -> WeaponData:
	return loadout.gadget


func get_gadget_charges() -> int:
	return loadout.gadget_charges if loadout.gadget != null else 0


## Place `w` dans l'emplacement d'équipement (charges pleines) ; renvoie l'ancien.
func set_gadget(w: WeaponData) -> WeaponData:
	var old: WeaponData = loadout.set_gadget(w)
	gadget_changed.emit()
	return old


## Équipe `w` dans l'emplacement d'équipement (inventaire) ; renvoie l'équipement
## remplacé (ou null) — l'appelant le remet dans le sac.
func equip_gadget(w: WeaponData) -> WeaponData:
	var old: WeaponData = set_gadget(w)
	_play_sfx(&"item_equip")
	return old


## C4 posés non encore déclenchés.
func get_placed_c4_count() -> int:
	var n: int = 0
	for d: GadgetDevice in _c4_placed:
		if is_instance_valid(d) and not d.detonated:
			n += 1
	return n


## Utilise l'équipement dans `dir` (ZERO = visée, sinon direction de déplacement).
## C4 : si des charges sont posées, l'appui suivant les fait exploser.
## Renvoie true si quelque chose s'est produit.
func use_gadget(dir: Vector2 = Vector2.ZERO) -> bool:
	var g: WeaponData = loadout.gadget
	if g == null or not _alive or _hidden or net_downed:
		return false
	var kind: StringName = g.gadget_kind
	if kind == WeaponData.GADGET_C4 and get_placed_c4_count() > 0:
		for d: GadgetDevice in _c4_placed:
			if is_instance_valid(d):
				d.detonate()
		_c4_placed.clear()
		if NetHooks.active:
			NetHooks.on_gadget(self, g, &"c4_detonate", global_position, global_position, 0.0)
		_play_sfx(&"click")
		gadget_changed.emit()
		return true
	if not loadout.consume_gadget_charge():
		_play_sfx(&"dry_fire")
		return false
	var d0: Vector2 = gadget_direction(dir, aim_direction, velocity, _aiming)
	var parent: Node = projectile_pool.get_world_parent() if projectile_pool != null else get_parent()
	if kind == WeaponData.GADGET_DRONE:
		if is_instance_valid(_active_drone):
			_active_drone.leaving = true
		_active_drone = GadgetDrone.spawn(parent, self, g)
		if NetHooks.active:
			NetHooks.on_gadget(self, g, &"drone", global_position, global_position, 0.0)
	else:
		var hand_h: float = visual.hand_height if visual != null else 24.0
		var place: bool = kind == WeaponData.GADGET_MINE or kind == WeaponData.GADGET_C4
		var dist: float = Balance.get_float("gadgets", "place_distance", 40.0) if place \
			else maxf(g.throw_range, 60.0)
		var target: Vector2 = global_position + d0 * dist
		var dev := GadgetDevice.throw_device(parent, g, global_position + d0 * 12.0, 0.0 if place else hand_h,
			target, self, in_low_gravity)
		if kind == WeaponData.GADGET_C4:
			_c4_placed.append(dev)
		if NetHooks.active:
			NetHooks.on_gadget(self, g, &"throw", global_position + d0 * 12.0, target, 0.0 if place else hand_h)
	if visual != null:
		visual.on_throw(d0, g)
	_fire_noise = maxf(_fire_noise, 0.4)
	_play_sfx(&"blade_swing")
	gadget_changed.emit()
	return true


## Logique pure : direction d'un lancer — `dir` si fournie, sinon la visée si on vise,
## sinon la direction de déplacement, sinon la visée.
static func gadget_direction(dir: Vector2, aim: Vector2, vel: Vector2, aiming: bool) -> Vector2:
	if dir != Vector2.ZERO:
		return dir.normalized()
	if not aiming and vel.length_squared() > 25.0:
		return vel.normalized()
	return aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT


## Munitions dans le chargeur courant (-1 = illimité).
func get_ammo() -> int:
	return loadout.get_ammo()


func get_magazine_size() -> int:
	return loadout.get_magazine()


func is_reloading() -> bool:
	return loadout.is_reloading()


## 0 → 1 pendant le rechargement.
func get_reload_progress() -> float:
	return loadout.reload_progress()


## Force un rechargement (sans effet si le chargeur est plein ou déjà en cours).
func reload() -> void:
	if not _alive or _hidden:
		return
	if loadout.start_reload():
		_on_reload_started()


func _on_reload_started() -> void:
	_was_reloading = true
	_pending_shells = 0
	reload_started.emit()
	_play_sfx(&"reload")
	var w: WeaponData = weapon
	if w == null or visual == null:
		return
	var prof: Dictionary = visual.weapon_view.profile
	var fx := CombatFx.get_or_create(get_tree())
	if fx == null:
		return
	var hand: Vector2 = Player.hand_offset(aim_direction, visual.hand_height, visual.hand_radius)
	var ground := global_position + Vector2(hand.x, hand.y + visual.hand_height)
	if bool(prof.get("mag_drop", false)):
		fx.magazine_drop(ground, visual.hand_height, aim_direction)
	elif float(prof.get("shell_delay", 0.0)) < 0.0 and w.eject_shells and _shells_enabled:
		# Revolver : on vide le barillet au rechargement.
		var spent: int = mini(maxi(w.magazine_size - maxi(get_ammo(), 0), 1), fx.count(6, 2))
		for i: int in spent:
			fx.shell(ground, visual.hand_height, aim_direction, false)


## Vitesse max effective (vitesse de base × arme tenue).
func get_effective_speed() -> float:
	var w: WeaponData = weapon
	var slow := status.speed_mult() if status != null else 1.0
	return move_speed * (clampf(w.move_speed_mult, 0.1, 2.0) if w != null else 1.0) * slow


func _on_weapon_changed(animate: bool) -> void:
	if visual != null:
		visual.set_weapon(weapon, animate)
		visual.set_reload(-1.0)
	_was_reloading = loadout.is_reloading()
	weapons_changed.emit()
	ammo_changed.emit(get_ammo(), get_magazine_size())


# =============================================================================
# Boucle physique
# =============================================================================

func _physics_process(delta: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_fire_noise = maxf(_fire_noise - delta / maxf(noise_fire_decay, 0.01), 0.0)
	_dry_fire_cooldown = maxf(_dry_fire_cooldown - delta, 0.0)
	_tick_weapon(delta)
	if not _alive or net_downed:
		if net_downed:
			velocity = Vector2.ZERO
			_is_moving = false
			_aiming = false
		_update_camera(delta)
		return

	var input_dir: Vector2 = get_move_input()
	if status != null and status.blocks_move():
		input_dir = Vector2.ZERO
	if _hidden:
		_hide_time += delta
		velocity = Vector2.ZERO
		_is_moving = false
		if _hide_time >= hide_exit_grace and input_dir.length() >= hide_exit_threshold:
			set_hidden(false)
		_update_camera(delta)
		return

	_lowg_check -= delta
	if _lowg_check <= 0.0:
		_lowg_check = 0.1
		in_low_gravity = LowGravity.is_at(get_tree(), global_position)
	var acc: float = acceleration
	var dec: float = deceleration
	var sharp: float = accel_sharpness
	if in_low_gravity:
		# Inertie : on glisse, on met longtemps à s'arrêter ou à tourner.
		acc *= _lowg_accel_mult
		dec *= _lowg_decel_mult
		sharp *= _lowg_sharpness_mult
	velocity = step_velocity(velocity, input_dir, get_effective_speed(), acc, dec, sharp, turn_boost, delta)
	move_and_slide()
	_is_moving = velocity.length_squared() > 25.0 and input_dir != Vector2.ZERO

	_update_aim(input_dir)
	_update_fire()
	_update_camera(delta)


func _tick_weapon(delta: float) -> void:
	_tick_salvo(delta)
	if loadout.tick(delta):
		_was_reloading = false
		ammo_changed.emit(get_ammo(), get_magazine_size())
		reload_finished.emit(true)
	if visual != null:
		visual.set_reload(loadout.reload_progress() if loadout.is_reloading() else -1.0)
	# Douille différée (pompe, culasse) et fumée de canon après une rafale.
	if _pending_shells > 0:
		_pending_shell -= delta
		if _pending_shell <= 0.0:
			_pending_shells -= 1
			_pending_shell = 0.05
			_eject_shell()
	_since_shot += delta
	if _burst_shots > 0 and _since_shot >= _smoke_delay:
		if _burst_shots >= _smoke_burst_shots:
			_emit_barrel_smoke(1.0)
		_burst_shots = 0


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
		_manual_fire_pending = true
		if event is InputEventMouseButton:
			_mouse_aim_active = true
		return
	if not _alive or net_downed:
		return
	if event.is_action_pressed("gadget"):
		use_gadget(Vector2.ZERO)
	elif event.is_action_pressed("reload"):
		reload()
	elif event.is_action_pressed("weapon_next"):
		next_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		next_weapon(-1)
	elif event.is_action_pressed("weapon_1"):
		switch_to(0)
	elif event.is_action_pressed("weapon_2"):
		switch_to(1)
	elif event.is_action_pressed("weapon_3"):
		switch_to(2)


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
		var hh: float = visual.hand_height if visual != null else 24.0
		var to_mouse: Vector2 = get_global_mouse_position() - (global_position + Vector2(0.0, -hh))
		if to_mouse.length_squared() > 16.0:
			aim_direction = to_mouse.normalized()
		_aiming = true
	elif move_dir != Vector2.ZERO:
		aim_direction = move_dir.normalized()


func is_aiming() -> bool:
	return _aiming


func _update_fire() -> void:
	var w: WeaponData = weapon
	if w == null or (status != null and status.blocks_fire()):
		return
	var wants: bool = false
	var dir: Vector2 = aim_direction
	if _aim_stick_firing:
		# Mobile : cadence continue, aide à la visée (cône étroit vers l'ennemi visible le plus proche).
		wants = true
	elif _manual_fire_held or _manual_fire_pending:
		# PC : arme automatique = tir maintenu ; sinon un tir par appui (appui mémorisé).
		wants = _manual_fire_pending or w.automatic
	if not wants:
		return
	if loadout.needs_reload():
		_manual_fire_pending = false
		if not loadout.is_reloading():
			if _dry_fire_cooldown <= 0.0:
				_dry_fire_cooldown = 0.4
				_play_sfx(&"dry_fire")
			reload()
		return
	if not loadout.can_fire():
		return
	if _aim_stick_firing and not (status != null and status.has(&"blind")):
		dir = apply_aim_assist(aim_direction)
	if status != null:
		dir = status.perturb_aim(dir)
	_manual_fire_pending = false
	fire(dir)


## Aide à la visée du stick : si un ennemi vivant et visible (non caché par le brouillard)
## est dans un cône de [player] aim_assist_deg autour de `dir` et à portée de l'arme,
## renvoie la direction (au sol) vers lui ; sinon `dir`. Coût : un parcours du groupe
## enemies par tir, pas par frame.
func apply_aim_assist(dir: Vector2) -> Vector2:
	var w: WeaponData = weapon
	if _aim_assist_deg <= 0.0 or w == null:
		return dir
	var cos_limit: float = cos(deg_to_rad(_aim_assist_deg))
	var max_d: float = w.range
	var best: Node2D = null
	var best_score: float = -1.0
	for e: Node in get_tree().get_nodes_in_group(&"enemies"):
		var n := e as Node2D
		if n == null or not n.is_visible_in_tree():
			continue
		var to: Vector2 = n.global_position - global_position
		var d: float = to.length()
		if d < 1.0 or d > max_d:
			continue
		var c: float = dir.dot(to / d)
		if c < cos_limit:
			continue
		# Préfère l'ennemi le mieux aligné, puis le plus proche.
		var score: float = c - d / (max_d * 10.0)
		if score > best_score:
			best_score = score
			best = n
	if best == null:
		return dir
	return (best.global_position - global_position).normalized()


## Tire une salve dans `dir` selon l'arme courante (munition, cadence, nombre de projectiles,
## dispersion, imprécision), depuis le canon. Sans effet si le tir est impossible.
func fire(dir: Vector2) -> void:
	var w: WeaponData = weapon
	if w == null or _hidden or not _alive or not loadout.can_fire():
		return
	var d0: Vector2 = dir.normalized() if dir != Vector2.ZERO else aim_direction
	# Imprécision du tir : base + dispersion accumulée (rafale) + déplacement.
	var inacc: float = get_current_spread()
	loadout.consume_shot()
	_fire_noise = 1.0
	# Trajectoire au niveau du sol (hitbox des ennemis et murs aux pieds) ; la balle est
	# dessinée à la hauteur du canon.
	var muzzle: Vector2 = get_muzzle_position(d0)
	var height: float = maxf(global_position.y - muzzle.y, 0.0)
	var origin: Vector2 = Vector2(muzzle.x, muzzle.y + height)
	var count: int = maxi(w.projectile_count, 1)
	var homing: Node2D = find_homing_target(d0) if weapon_homing(w) > 0.0 else null
	if is_salvo_weapon(w):
		# Salve (M202) : une roquette maintenant, les suivantes (prises dans le chargeur)
		# à `salvo_interval` ; la cadence repart après la salve.
		var extra: int = int(Balance.get_value("player_fx", "salvo_size", 4)) - 1
		_salvo_left = mini(extra, maxi(get_ammo(), 0)) if get_ammo() >= 0 else extra
		_salvo_consumes = true
		_salvo_timer = _salvo_interval
		_salvo_dir = d0
		loadout.cooldown += _salvo_interval * float(_salvo_left)
	elif count > 1 and w.projectile_style == &"rocket":
		# Plusieurs roquettes par tir : partent en salve rapide plutôt qu'ensemble.
		_salvo_left = count - 1
		_salvo_consumes = false
		_salvo_timer = _salvo_interval
		_salvo_dir = d0
		count = 1
	for i: int in count:
		var p: Projectile = projectile_pool.spawn(origin,
			spread_direction(d0, i, count, w.spread_degrees, inacc), w, self, height)
		if p != null and homing != null:
			p.set_homing(homing, weapon_homing(w))
	_on_fired_feel(w, d0)
	if in_low_gravity:
		# Recul : pousse légèrement le joueur vers l'arrière.
		velocity -= d0 * _lowg_recoil_push * maxf(w.recoil_px, 1.0) * float(maxi(w.projectile_count, 1))
	fired.emit(d0)
	ammo_changed.emit(get_ammo(), get_magazine_size())
	if loadout.needs_reload():
		reload()


## Force de guidage d'une arme (0 = aucun) : champ `homing` s'il existe, sinon le
## Javelin est guidé par défaut ([player_fx] javelin_homing).
static func weapon_homing(w: WeaponData) -> float:
	if w == null:
		return 0.0
	var h: Variant = w.get("homing")
	if h != null and float(h) > 0.0:
		return float(h)
	if w.affixes.has(&"homing") or String(w.id) == "rocket_javelin":
		return Balance.get_float("player_fx", "javelin_homing", 3.0)
	return 0.0


## Arme à salve (M202) : une pression tire jusqu'à [player_fx] salvo_size projectiles du
## chargeur à salvo_interval. Affixe `salvo`, ou id rocket_m202.
static func is_salvo_weapon(w: WeaponData) -> bool:
	return w != null and (w.affixes.has(&"salvo") or String(w.id) == "rocket_m202")


## Ennemi visible le plus proche de l'axe de visée (cône [player_fx] homing_cone_deg,
## portée de l'arme). Un parcours du groupe par tir.
func find_homing_target(dir: Vector2) -> Node2D:
	var w: WeaponData = weapon
	var max_d: float = w.range if w != null else 800.0
	var cos_lim: float = cos(deg_to_rad(Balance.get_float("player_fx", "homing_cone_deg", 35.0)))
	var best: Node2D = null
	var best_score: float = -INF
	for e: Node in get_tree().get_nodes_in_group(&"enemies"):
		var n := e as Node2D
		if n == null or not n.is_visible_in_tree():
			continue
		if n.has_method("is_alive") and not bool(n.call("is_alive")):
			continue
		var to: Vector2 = n.global_position - global_position
		var d: float = to.length()
		if d < 1.0 or d > max_d:
			continue
		var c: float = dir.dot(to / d)
		if c < cos_lim:
			continue
		var score: float = c * 2.0 - d / max_d
		if score > best_score:
			best_score = score
			best = n
	return best


func _tick_salvo(delta: float) -> void:
	if _salvo_left <= 0:
		return
	_salvo_timer -= delta
	if _salvo_timer > 0.0:
		return
	var w: WeaponData = weapon
	if w == null or not _alive or _hidden:
		_salvo_left = 0
		return
	_salvo_timer = _salvo_interval
	if _salvo_consumes:
		if not loadout.has_ammo() or loadout.is_reloading():
			_salvo_left = 0
			return
		if loadout.get_ammo() > 0:
			loadout.ammo[loadout.current] -= 1
		ammo_changed.emit(get_ammo(), get_magazine_size())
	var i: int = maxi(w.projectile_count, 1) - _salvo_left
	_salvo_left -= 1
	var muzzle: Vector2 = get_muzzle_position(_salvo_dir)
	var height: float = maxf(global_position.y - muzzle.y, 0.0)
	var dir: Vector2 = spread_direction(_salvo_dir, i, maxi(w.projectile_count, 1), w.spread_degrees, w.inaccuracy_deg)
	projectile_pool.spawn(Vector2(muzzle.x, muzzle.y + height), dir, w, self, height)
	if visual != null:
		visual.on_fired(_salvo_dir)
	_play_sfx(StringName(String(visual.weapon_view.profile.get("sfx", "gun_shot_alt"))) if visual != null else &"gun_shot_alt")
	add_shake(w.shake_px * 0.6, camera_shake_duration)
	_fire_noise = 1.0
	if _salvo_consumes and _salvo_left <= 0 and loadout.needs_reload():
		reload()


## Logique pure : direction du projectile `i` sur `count` (éventail régulier de
## `spread_deg` au total) + imprécision aléatoire ±`inaccuracy_deg`.
static func spread_direction(dir: Vector2, i: int, count: int, spread_deg: float, inaccuracy_deg: float) -> Vector2:
	var offset: float = 0.0
	if count > 1:
		var spread: float = deg_to_rad(spread_deg)
		offset = lerpf(-spread * 0.5, spread * 0.5, float(i) / float(count - 1))
	if inaccuracy_deg > 0.0:
		offset += deg_to_rad(randf_range(-inaccuracy_deg, inaccuracy_deg))
	return dir.rotated(offset)


## Position monde du bout du canon pour une visée `dir` (calcul logique, non interpolé).
func get_muzzle_position(dir: Vector2) -> Vector2:
	if visual != null:
		return global_position + visual.muzzle_offset(dir)
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	return global_position + hand_offset(d, 24.0, 10.0) + Vector2(20.0, 0.0).rotated(d.angle())


## Logique pure : position de la main (pivot de l'arme) relative aux pieds.
static func hand_offset(dir: Vector2, height: float, radius: float) -> Vector2:
	return Vector2(dir.x * radius, -height + dir.y * radius * 0.5)


## Ressenti du tir : visuel (recul, éclair), son, secousse/zoom, douilles, fumée.
func _on_fired_feel(w: WeaponData, dir: Vector2) -> void:
	if visual == null:
		return
	visual.on_fired(dir)
	var prof: Dictionary = visual.weapon_view.profile
	_play_sfx(StringName(String(prof.get("sfx", "pistol_shot_light"))))
	add_shake(w.shake_px, camera_shake_duration * (1.0 + w.shake_px * 0.05),
		float(prof.get("zoom_kick", 0.0)))
	_burst_shots += 1
	_since_shot = 0.0
	if float(prof.get("smoke", 0.0)) > 0.0:
		_emit_barrel_smoke(float(prof.get("smoke", 0.0)))
	if w.eject_shells and _shells_enabled:
		var delay: float = float(prof.get("shell_delay", 0.0))
		if delay == 0.0:
			_eject_shell()
		elif delay > 0.0:
			_pending_shells = 1
			_pending_shell = delay


func _eject_shell() -> void:
	var w: WeaponData = weapon
	var fx := CombatFx.get_or_create(get_tree())
	if fx == null or w == null or visual == null:
		return
	var hand: Vector2 = visual.hand_position()
	var ground := global_position + Vector2(hand.x, hand.y + visual.hand_height)
	var big: bool = w.category == WeaponData.CAT_SHOTGUN
	fx.shell(ground, visual.hand_height, aim_direction, big, in_low_gravity)


func _emit_barrel_smoke(strength: float) -> void:
	var fx := CombatFx.get_or_create(get_tree())
	if fx == null or visual == null:
		return
	var m: Vector2 = get_muzzle_position(aim_direction)
	fx.muzzle_smoke(m, aim_direction, strength)
	if strength >= 1.0 and not fx.is_low():
		fx.muzzle_smoke(m + aim_direction * 6.0, aim_direction, strength * 0.7)


# --- Caméra ------------------------------------------------------------------

## Secousse caméra (px), cumulée avec la secousse en cours (la plus forte gagne) ;
## `zoom_kick` = petit zoom avant temporaire (0.03 = +3 %).
func add_shake(amount_px: float, duration: float = -1.0, zoom_kick: float = 0.0) -> void:
	if not camera_shake_enabled:
		return
	var amp: float = amount_px * _shake_mult
	var dur: float = duration if duration > 0.0 else camera_shake_duration
	var cur: float = _current_shake_amp()
	if amp >= cur:
		_shake_amp = amp
		_shake_time = maxf(dur, 0.01)
		_shake_left = _shake_time
	_zoom_kick = maxf(_zoom_kick, zoom_kick * _zoom_kick_mult)


func _current_shake_amp() -> float:
	if _shake_left <= 0.0:
		return 0.0
	var k: float = _shake_left / maxf(_shake_time, 0.001)
	return _shake_amp * k * k


func _update_camera(delta: float) -> void:
	# Anticipation : la caméra se décale doucement dans la direction de visée
	# (seulement quand on vise, sinon légèrement dans le sens de la marche).
	var want: Vector2 = Vector2.ZERO
	if _alive and not _hidden:
		if _aiming:
			want = aim_direction * camera_lookahead
		elif _is_moving:
			want = velocity / maxf(get_effective_speed(), 1.0) * camera_lookahead * 0.5
	_cam_look = _cam_look.lerp(want, 1.0 - exp(-camera_lookahead_speed * delta))
	camera.position = _cam_look
	if _shake_left > 0.0:
		_shake_left = maxf(_shake_left - delta, 0.0)
		var amp: float = _current_shake_amp()
		camera.offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	elif camera.offset != Vector2.ZERO:
		camera.offset = Vector2.ZERO
	if _zoom_kick > 0.0 or _last_zoom_kick > 0.0:
		_zoom_kick = maxf(_zoom_kick - _zoom_kick * minf(_zoom_kick_recover * delta, 1.0) - 0.0005, 0.0)
		_last_zoom_kick = _zoom_kick
		camera.zoom = _cam_base_zoom * (1.0 + _zoom_kick)


# --- Bruit, cachettes --------------------------------------------------------

## Imprécision effective (±°) du prochain tir : arme + rafale (bloom) + déplacement.
func get_current_spread() -> float:
	if loadout == null:
		return 0.0
	return loadout.current_inaccuracy(velocity.length() / maxf(move_speed, 1.0))


func is_moving() -> bool:
	return _is_moving


func is_hidden() -> bool:
	return _hidden


## Bruit émis (0..1) : 0 immobile ou caché, ~noise_walk en marche, 1 juste après un tir.
func get_noise_level() -> float:
	if _hidden or not _alive:
		return 0.0
	return compute_noise(velocity.length() / maxf(move_speed, 1.0), _fire_noise, noise_walk)


## Bruit ponctuel (explosion…) : `level` 0..1, décroît comme le bruit de tir.
func add_noise(level: float) -> void:
	_fire_noise = maxf(_fire_noise, clampf(level, 0.0, 1.0))


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
		_manual_fire_pending = false
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
	if visual != null:
		visual.refresh_state()
	hidden_changed.emit(_hidden, spot)


func get_hide_spot() -> Node:
	return _hide_spot


# --- Dégâts ------------------------------------------------------------------

func take_damage(amount: float, _source: Node) -> void:
	if not _alive or net_downed or _invulnerable_left > 0.0 or amount <= 0.0:
		return
	# Coop, invité : seuls les dégâts envoyés par l'hôte comptent.
	if NetHooks.active and NetHooks.blocks_local_damage():
		return
	if PlaytestProbe.enabled:
		PlaytestProbe.player_hit(minf(amount, hp), _source)
	hp = maxf(hp - amount, 0.0)
	_invulnerable_left = invulnerability_duration
	if visual != null:
		visual.on_hit()
		visual.hp_dirty()
	add_shake(camera_shake_amount * 1.6, 0.15)
	EventBus.player_damaged.emit(amount, hp, max_hp)
	if hp <= 0.0 and not (NetHooks.active and NetHooks.player_down(self)):
		_die()


func is_alive() -> bool:
	return _alive


## Statut infligé par un ennemi (PlayerStatus.KINDS) ; `from` = origine du coup (poussée du
## renversement). Coop, invité : seuls les statuts envoyés par l'hôte comptent (comme les dégâts).
func apply_status(kind: StringName, duration: float, strength: float = 1.0, from: Vector2 = Vector2.INF) -> void:
	if not _alive or net_downed or duration <= 0.0:
		return
	if NetHooks.active and NetHooks.blocks_local_damage():
		return
	if status == null:
		status = PlayerStatus.new()
		status.name = "Status"
		add_child(status)
	if visual != null:
		status.head_height = visual.body_height + 18.0
	status.apply(kind, duration, strength)
	if kind == &"knockdown" and from != Vector2.INF:
		var away := global_position - from
		if away.length_squared() > 1.0:
			velocity = away.normalized() * Balance.get_float("player_status", "knockdown_push", 420.0) * strength
			move_and_slide()
	if kind == &"stun" or kind == &"knockdown":
		add_shake(camera_shake_amount * 2.0, 0.2)


func has_status(kind: StringName) -> bool:
	return status != null and status.has(kind)


func is_invulnerable() -> bool:
	return _invulnerable_left > 0.0


func get_invulnerable_left() -> float:
	return _invulnerable_left


func heal(amount: float) -> void:
	if _alive:
		hp = minf(hp + amount, max_hp)
		if visual != null:
			visual.hp_dirty()


func _die() -> void:
	_alive = false
	velocity = Vector2.ZERO
	_is_moving = false
	_manual_fire_held = false
	_manual_fire_pending = false
	current_target = null
	if loadout.is_reloading():
		loadout.cancel_reload()
		reload_finished.emit(false)
	if _hidden:
		set_hidden(false)
	if visual != null:
		visual.refresh_state()
	EventBus.player_died.emit()


func get_debug_info() -> Dictionary:
	var w: WeaponData = weapon
	return {
		"hp": hp,
		"max_hp": max_hp,
		"speed": velocity.length(),
		"aim": aim_direction,
		"dir8": DIR8_NAMES[visual.facing_index] if visual != null else "-",
		"anim": String(visual.current_base) if visual != null else "-",
		"aiming": _aiming,
		"noise": get_noise_level(),
		"hidden": _hidden,
		"fire_cooldown": loadout.cooldown,
		"invulnerable": _invulnerable_left > 0.0,
		"weapon": ("%s [%d/%d]" % [w.display_name, current_slot + 1, loadout.size()]) if w != null else "-",
		"ammo": "%d/%d%s" % [get_ammo(), get_magazine_size(), " (recharge)" if is_reloading() else ""],
		"sprite": "planche" if visual != null and visual.uses_sheets else "repli",
		"pool_active": projectile_pool.get_active_count() if projectile_pool != null else 0,
		"gadget": ("%s x%d" % [loadout.gadget.display_name, get_gadget_charges()]) if loadout.gadget != null else "-",
		"low_gravity": in_low_gravity,
	}


func _play_sfx(sfx: StringName) -> void:
	var am: Node = get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, global_position)


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
