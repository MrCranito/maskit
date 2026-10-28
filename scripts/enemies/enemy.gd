class_name Enemy
extends CharacterBody2D
## Ennemi générique piloté par une StateMachine
## (Patrol → [Investigate] → Alert → Chase → Attack → Return, Dead).
## Toutes les valeurs propres à l'ennemi viennent de `data` (EnemyData, data/enemies/*.tres) ;
## les réglages globaux de l'IA viennent de balance.cfg [enemy_ai].
##
## Perception (évaluée tous les los_check_interval s, phase aléatoire par ennemi) :
##  - hors combat (Patrol/Investigate/Return) : le joueur doit être à moins de detection_radius,
##    dans le cône de vision si detection_angle_deg < 360, en ligne de vue (raycast contre la
##    couche world, portes fermées comprises) et non caché ;
##  - en combat (Alert/Chase/Attack) : cône ignoré, portée = detection_radius × chase_sight_multiplier,
##    ligne de vue toujours requise.
##  Un seul raycast par évaluation, et seulement si le joueur est dans le rayon max (vue/ouïe).
##
## Discrétion — jauge de reconnaissance `awareness` (0..1), cf. CONVENTIONS « Discrétion » :
##  - vue : + sight_gain × f(distance) (bien plus vite de près) × f(vitesse du joueur) par seconde ;
##  - ouïe : + hearing_gain × bruit × (1 - d/hearing_radius) × (hearing_wall_factor sans ligne de vue),
##    bonus immédiat sur un tir (saut de bruit) ; l'ennemi retient la position entendue ;
##  - rien perçu : − awareness_decay par seconde ;
##  - ≥ suspicion_threshold (stimulus frais) → Investigate (« ? ») ; ≥ awareness_alert_threshold
##    → « repéré » : Alert (« ! ») puis Chase, et les voisins reçoivent une forte hausse de jauge ;
##  - dégâts reçus → jauge à 1 ; joueur caché → la vue ne compte pas (sauf s'il s'est caché
##    sous les yeux d'un ennemi l'ayant repéré : celui-ci vient le déloger).
##
## Performance : ennemi « endormi » (physics/animation coupés) au-delà de sleep_distance du
## joueur (vérifié par un Timer à 2 Hz), barre de vie / jauge redessinées seulement sur
## changement, carte de navigation vérifiée à intervalle, repath limité dans le temps.
##
## Navigation : NavigationAgent2D si la carte de navigation du monde contient une région
## (salle de test), sinon steering direct avec évitement des murs par 3 raycasts « moustaches ».
## Le repli garantit un comportement correct en headless / dans les tests sans NavigationRegion2D.

const SCENE_PATH := "res://scenes/enemies/enemy.tscn"
const VISUAL_SCRIPT_PATH := "res://scripts/enemies/enemy_visual.gd"

const LAYER_ENEMIES := 4
const MASK_WORLD := 1
const MASK_PLAYER := 2

const GROUP_ENEMIES := &"enemies"
const GROUP_DAMAGEABLE := &"damageable"
const GROUP_UNITS := &"enemy_units"

const STATE_PATROL := &"Patrol"
const STATE_INVESTIGATE := &"Investigate"
const STATE_ALERT := &"Alert"
const STATE_CHASE := &"Chase"
const STATE_ATTACK := &"Attack"
const STATE_RETURN := &"Return"
const STATE_DEAD := &"Dead"

const STATE_SCRIPTS: Array[Script] = [
	preload("res://scripts/ai/enemy_states/enemy_patrol_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_investigate_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_alert_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_chase_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_attack_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_return_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_dead_state.gd"),
]

## Couleurs debug par état (F3).
const DEBUG_STATE_COLORS := {
	STATE_PATROL: Color(0.3, 0.95, 0.35),
	STATE_INVESTIGATE: Color(0.95, 0.95, 0.4),
	STATE_ALERT: Color(1.0, 0.9, 0.2),
	STATE_CHASE: Color(1.0, 0.55, 0.1),
	STATE_ATTACK: Color(1.0, 0.15, 0.15),
	STATE_RETURN: Color(0.3, 0.6, 1.0),
	STATE_DEAD: Color(0.5, 0.5, 0.5),
}

signal damaged(amount: float, current_hp: float)
signal died(enemy: Enemy)
## Émis quand la jauge de reconnaissance change de palier (0 calme, 1 suspicion, 2 repéré).
signal awareness_tier_changed(tier: int)

@export var data: EnemyData

var max_hp: float = 1.0
var hp: float = 1.0
## Point d'apparition (centre de la patrouille, destination du retour).
var spawn_position: Vector2 = Vector2.ZERO
## Direction du regard (oriente le cône de vision).
var facing: Vector2 = Vector2.DOWN

var visual: Node2D = null
var state_machine: StateMachine = null
var nav_agent: NavigationAgent2D = null
## Conservé pour compatibilité : la détection se fait désormais par distance (plus d'Area2D,
## moins de coût physique). Toujours null.
var detection_area: Area2D = null

## Résultat de la dernière perception.
var can_see_player: bool = false
var last_seen_position: Vector2 = Vector2.ZERO
var has_last_seen: bool = false
## Délai restant avant la prochaine attaque possible.
var attack_cooldown_left: float = 0.0

## Jauge de reconnaissance 0..1 (1 = repéré).
var awareness: float = 0.0
## Dernière position d'un stimulus (vu ou entendu) : cible de l'enquête.
var stimulus_position: Vector2 = Vector2.ZERO
## Incrémenté à chaque nouveau stimulus (l'enquête se recale dessus).
var stimulus_serial: int = 0
## Vrai si le joueur est actuellement entendu (dernière évaluation).
var hears_player: bool = false
## L'ennemi a vu le joueur se cacher sous ses yeux : il va le déloger (Chase).
var saw_player_hide: bool = false
## Ennemi endormi (loin du joueur) : physics et animation suspendus.
var asleep: bool = false
# Réglages globaux [enemy_ai]
var los_check_interval: float = 0.1
var chase_sight_multiplier: float = 1.5
var arrive_distance: float = 12.0
var whisker_length: float = 48.0
var whisker_angle: float = deg_to_rad(35.0)
var nav_repath_distance: float = 24.0
var death_free_fallback: float = 2.0
var health_bar_width: float = 56.0
# Discrétion
var suspicion_threshold: float = 0.3
var sight_edge_mult: float = 0.1
var sight_near_mult: float = 2.0
var sight_still_mult: float = 0.45
var player_speed_default: float = 250.0
var hearing_wall_factor: float = 0.4
var hearing_noise_floor: float = 0.05
var shot_noise_jump: float = 0.5
var shot_awareness_bump: float = 0.9
var shot_wall_factor: float = 0.7
var fallback_walk_noise: float = 0.35
var fallback_shot_noise_decay: float = 0.6
var neighbor_awareness_boost: float = 0.6
var lost_awareness: float = 0.6
var hide_reveal_distance: float = 220.0
var hide_seen_memory: float = 0.6
var hide_search_time: float = 0.6
var suspicion_pause: float = 0.7
var investigate_speed_ratio: float = 0.55
var investigate_walk_timeout: float = 6.0
var investigate_look_time: float = 2.4
var investigate_look_turn: float = 0.6
var investigate_timeout: float = 12.0
# Réglages lus par les états chaque frame (mis en cache : pas d'accès ConfigFile par frame).
var patrol_speed_ratio: float = 0.4
var patrol_pause_min: float = 0.8
var patrol_pause_max: float = 2.2
var patrol_walk_timeout: float = 3.0
var track_memory: float = 0.5
var search_timeout: float = 4.0
var leash_distance: float = 900.0
var retreat_speed_ratio: float = 0.8
var attack_recovery: float = 0.25
var return_speed_ratio: float = 0.7
var return_regen_ratio_per_sec: float = 0.25
var return_timeout: float = 8.0
# Performance
var sleep_distance: float = 1800.0
var wake_distance: float = 1600.0
var sleep_check_interval: float = 0.5
var nav_repath_interval: float = 0.25
var nav_check_interval: float = 1.0

var _alive: bool = true
var _player: Node2D = null
var _perception_left: float = 0.0
var _perception_elapsed: float = 0.0
var _health_bar: Node2D = null
var _awareness_bar: AwarenessBar = null
var _debug_registered: bool = false
var _last_los_clear: bool = false
var _unseen_time: float = 999.0
var _last_noise: float = 0.0
var _tier: int = 0
var _visual_moving: bool = false
var _sleep_timer: Timer = null
var _ray_query: PhysicsRayQueryParameters2D = null
var _nav_cached: bool = false
var _nav_check_left: float = 0.0
var _repath_left: float = 0.0
# Repli si le joueur n'expose pas get_noise_level() : instant (ms) du dernier tir du joueur.
var _fallback_shot_msec: int = -100000
var _fallback_listening: bool = false


## Instancie un ennemi prêt à être ajouté à l'arbre.
static func spawn(enemy_data: EnemyData) -> Enemy:
	var scene := load(SCENE_PATH) as PackedScene
	var e: Enemy = scene.instantiate() as Enemy if scene != null else Enemy.new()
	e.data = enemy_data
	return e


func _ready() -> void:
	if data == null:
		push_warning("Enemy %s : aucune EnemyData, valeurs par défaut." % name)
		data = EnemyData.new()
	_load_balance()
	max_hp = data.max_hp
	hp = max_hp
	spawn_position = global_position
	last_seen_position = global_position
	stimulus_position = global_position
	# Désynchronise les évaluations de perception entre ennemis.
	_perception_left = randf() * los_check_interval
	_ray_query = PhysicsRayQueryParameters2D.new()
	_ray_query.collision_mask = MASK_WORLD
	_ray_query.exclude = [get_rid()]
	_ray_query.collide_with_areas = false

	add_to_group(GROUP_UNITS)
	add_to_group(GROUP_ENEMIES)
	add_to_group(GROUP_DAMAGEABLE)
	collision_layer = LAYER_ENEMIES
	collision_mask = MASK_WORLD | MASK_PLAYER | LAYER_ENEMIES
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	_build_body_shape()
	_build_nav_agent()
	_build_visual()
	_build_health_bar()
	_build_awareness_bar()
	_build_state_machine()
	_build_sleep_timer()
	_register_debug.call_deferred()
	EventBus.enemy_spawned.emit(self)


func _load_balance() -> void:
	los_check_interval = Balance.get_float("enemy_ai", "los_check_interval", 0.1)
	chase_sight_multiplier = Balance.get_float("enemy_ai", "chase_sight_multiplier", 1.5)
	arrive_distance = Balance.get_float("enemy_ai", "arrive_distance", 12.0)
	whisker_length = Balance.get_float("enemy_ai", "whisker_length", 48.0)
	whisker_angle = deg_to_rad(Balance.get_float("enemy_ai", "whisker_angle_deg", 35.0))
	nav_repath_distance = Balance.get_float("enemy_ai", "nav_repath_distance", 24.0)
	death_free_fallback = Balance.get_float("enemy_ai", "death_free_fallback", 2.0)
	health_bar_width = Balance.get_float("enemy_ai", "health_bar_width", 56.0)
	suspicion_threshold = _bf("suspicion_threshold", suspicion_threshold)
	sight_edge_mult = _bf("sight_edge_mult", sight_edge_mult)
	sight_near_mult = _bf("sight_near_mult", sight_near_mult)
	sight_still_mult = _bf("sight_still_mult", sight_still_mult)
	player_speed_default = _bf("player_speed_default", player_speed_default)
	hearing_wall_factor = _bf("hearing_wall_factor", hearing_wall_factor)
	hearing_noise_floor = _bf("hearing_noise_floor", hearing_noise_floor)
	shot_noise_jump = _bf("shot_noise_jump", shot_noise_jump)
	shot_awareness_bump = _bf("shot_awareness_bump", shot_awareness_bump)
	shot_wall_factor = _bf("shot_wall_factor", shot_wall_factor)
	fallback_walk_noise = _bf("fallback_walk_noise", fallback_walk_noise)
	fallback_shot_noise_decay = _bf("fallback_shot_noise_decay", fallback_shot_noise_decay)
	neighbor_awareness_boost = _bf("neighbor_awareness_boost", neighbor_awareness_boost)
	lost_awareness = _bf("lost_awareness", lost_awareness)
	hide_reveal_distance = _bf("hide_reveal_distance", hide_reveal_distance)
	hide_seen_memory = _bf("hide_seen_memory", hide_seen_memory)
	hide_search_time = _bf("hide_search_time", hide_search_time)
	suspicion_pause = _bf("suspicion_pause", suspicion_pause)
	investigate_speed_ratio = _bf("investigate_speed_ratio", investigate_speed_ratio)
	investigate_walk_timeout = _bf("investigate_walk_timeout", investigate_walk_timeout)
	investigate_look_time = _bf("investigate_look_time", investigate_look_time)
	investigate_look_turn = _bf("investigate_look_turn", investigate_look_turn)
	investigate_timeout = _bf("investigate_timeout", investigate_timeout)
	patrol_speed_ratio = _bf("patrol_speed_ratio", patrol_speed_ratio)
	patrol_pause_min = _bf("patrol_pause_min", patrol_pause_min)
	patrol_pause_max = _bf("patrol_pause_max", patrol_pause_max)
	patrol_walk_timeout = _bf("patrol_walk_timeout", patrol_walk_timeout)
	track_memory = _bf("track_memory", track_memory)
	search_timeout = _bf("search_timeout", search_timeout)
	leash_distance = _bf("leash_distance", leash_distance)
	retreat_speed_ratio = _bf("retreat_speed_ratio", retreat_speed_ratio)
	attack_recovery = _bf("attack_recovery", attack_recovery)
	return_speed_ratio = _bf("return_speed_ratio", return_speed_ratio)
	return_regen_ratio_per_sec = _bf("return_regen_ratio_per_sec", return_regen_ratio_per_sec)
	return_timeout = _bf("return_timeout", return_timeout)
	sleep_distance = _bf("sleep_distance", sleep_distance)
	wake_distance = minf(_bf("wake_distance", wake_distance), sleep_distance)
	sleep_check_interval = _bf("sleep_check_interval", sleep_check_interval)
	nav_repath_interval = _bf("nav_repath_interval", nav_repath_interval)
	nav_check_interval = _bf("nav_check_interval", nav_check_interval)


func _bf(key: String, default: float) -> float:
	return Balance.get_float("enemy_ai", key, default)


# --- Construction --------------------------------------------------------------

func _build_body_shape() -> void:
	var cs: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null:
		cs = CollisionShape2D.new()
		cs.name = "CollisionShape2D"
		add_child(cs)
	var circle := CircleShape2D.new()
	circle.radius = data.body_radius
	cs.shape = circle


func _build_nav_agent() -> void:
	nav_agent = NavigationAgent2D.new()
	nav_agent.name = "NavigationAgent2D"
	nav_agent.radius = data.body_radius
	nav_agent.path_desired_distance = arrive_distance
	nav_agent.target_desired_distance = arrive_distance
	nav_agent.avoidance_enabled = false
	add_child(nav_agent)


func _build_visual() -> void:
	# Chargement tolérant : le composant visuel est écrit par un autre module.
	var script: Script = null
	if ResourceLoader.exists(VISUAL_SCRIPT_PATH):
		script = load(VISUAL_SCRIPT_PATH) as Script
	if script != null and script.can_instantiate():
		visual = script.new() as Node2D
	if visual == null:
		visual = FallbackVisual.new()
	visual.name = "Visual"
	add_child(visual)
	if visual.has_method("setup"):
		visual.call("setup", data.kind)
	if data.aura_color.a > 0.0 and visual.has_method("set_aura"):
		visual.call("set_aura", data.aura_color)
	# Télégraphes spécifiques (méthodes optionnelles du visuel).
	if data.is_area_attack():
		_visual_call(&"set_attack_area", [data.aoe_radius])
	elif data.is_ranged() and data.projectile_count > 1:
		var reach := data.projectile_speed * (data.projectile_lifetime if data.projectile_lifetime > 0.0
			else Balance.get_float("enemy_ai", "projectile_lifetime", 2.5))
		_visual_call(&"set_attack_cone", [data.projectile_spread_deg, minf(reach, data.attack_range * 1.2)])
	if visual.has_signal("death_finished"):
		visual.connect("death_finished", _on_death_finished)
	_visual_call(&"set_facing", [facing])


func _build_health_bar() -> void:
	_health_bar = HealthBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.set("enemy", self)
	_health_bar.z_index = 5
	add_child(_health_bar)


func _build_awareness_bar() -> void:
	_awareness_bar = AwarenessBar.new()
	_awareness_bar.name = "AwarenessBar"
	add_child(_awareness_bar)
	# Au-dessus de la barre de vie (tête - 12 px, hauteur 7 px) : centre de l'anneau.
	_awareness_bar.setup(get_head_offset() + Vector2(0, -12.0 - 7.0 - 22.0), suspicion_threshold)


## Vérifie à faible fréquence (Timer, aucun coût par frame) s'il faut endormir / réveiller.
func _build_sleep_timer() -> void:
	_sleep_timer = Timer.new()
	_sleep_timer.name = "SleepTimer"
	_sleep_timer.one_shot = false
	_sleep_timer.wait_time = maxf(sleep_check_interval, 0.05)
	add_child(_sleep_timer)
	_sleep_timer.timeout.connect(_on_sleep_check)
	# Phase aléatoire : premier contrôle décalé.
	_sleep_timer.start(randf_range(0.05, maxf(sleep_check_interval, 0.05)))


func _build_state_machine() -> void:
	state_machine = StateMachine.new()
	state_machine.name = "StateMachine"
	state_machine.auto_process = false  # Ordonnancement manuel avec move_and_slide.
	for s: Script in STATE_SCRIPTS:
		var st: State = s.new() as State  # Chaque état fixe son nom dans _init.
		state_machine.add_child(st)
	add_child(state_machine)
	state_machine.start(self, STATE_PATROL)


func _register_debug() -> void:
	if _debug_registered or not is_inside_tree():
		return
	var dbg := DebugWorldDraw.find(get_tree())
	if dbg != null:
		dbg.register_drawer(_draw_debug)
		_debug_registered = true


# --- Boucle --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _debug_registered:
		_register_debug()
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	if _nav_check_left > 0.0:
		_nav_check_left -= delta
	if _repath_left > 0.0:
		_repath_left -= delta
	if _alive:
		_perception_left -= delta
		_perception_elapsed += delta
		if _perception_left <= 0.0:
			_perception_left += los_check_interval
			if _perception_left <= 0.0:
				_perception_left = los_check_interval
			update_perception(_perception_elapsed)
			_perception_elapsed = 0.0
	state_machine.physics_update(delta)
	if _alive:
		if velocity != Vector2.ZERO:
			move_and_slide()
		var moving := velocity.length_squared() > 4.0
		if moving:
			face(velocity)
		_set_visual_moving(moving)
	else:
		velocity = Vector2.ZERO


func _set_visual_moving(moving: bool) -> void:
	if moving == _visual_moving:
		return
	_visual_moving = moving
	if visual != null and visual.has_method(&"set_moving"):
		visual.call(&"set_moving", moving)


# --- Sommeil (performance) ---------------------------------------------------------

func _on_sleep_check() -> void:
	if not _alive:
		_sleep_timer.stop()
		return
	var p := get_player()
	var d2 := INF if p == null else global_position.distance_squared_to(p.global_position)
	if asleep:
		if d2 <= wake_distance * wake_distance:
			wake_up()
	elif d2 > sleep_distance * sleep_distance and current_state_name() == STATE_PATROL:
		go_to_sleep()


## Suspend physics, perception et animation (ennemi loin du joueur).
func go_to_sleep() -> void:
	if asleep or not _alive:
		return
	asleep = true
	velocity = Vector2.ZERO
	_set_visual_moving(false)
	set_physics_process(false)
	if visual != null:
		visual.set_process(false)


func wake_up() -> void:
	if not asleep:
		return
	asleep = false
	_perception_left = randf() * los_check_interval
	_perception_elapsed = 0.0
	set_physics_process(true)
	if visual != null:
		visual.set_process(true)


# --- Perception ------------------------------------------------------------------

## Joueur vivant ou null.
func get_player() -> Node2D:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = null
		var p: Node2D = GameState.player
		if is_instance_valid(p) and p.is_inside_tree() and p.is_in_group(&"player"):
			_player = p
		else:
			_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _player == null:
		return null
	if _player.has_method("is_alive") and not bool(_player.call("is_alive")):
		return null
	return _player


func distance_to_player() -> float:
	var p := get_player()
	return INF if p == null else global_position.distance_to(p.global_position)


## Vrai si les états actuels utilisent la perception « combat » (sans cône, portée étendue).
func is_in_combat() -> bool:
	var s := current_state_name()
	return s == STATE_ALERT or s == STATE_CHASE or s == STATE_ATTACK


## Évalue vue + ouïe, met à jour `can_see_player`, `last_seen_position` et la jauge
## `awareness` (dt = temps écoulé depuis l'évaluation précédente ; 0 = vue seule).
## Appelé à intervalle (los_check_interval), jamais à chaque frame.
func update_perception(dt: float = 0.0) -> bool:
	can_see_player = false
	hears_player = false
	_last_los_clear = false
	var p := get_player()
	if p == null or not _alive:
		_apply_awareness(0.0, dt)
		return false
	var ppos: Vector2 = p.global_position
	var d2 := global_position.distance_squared_to(ppos)
	var combat := is_in_combat()
	var sight_r := data.detection_radius * (chase_sight_multiplier if combat else 1.0)
	var max_r := maxf(sight_r, data.hearing_radius)
	if d2 > max_r * max_r:
		# Hors de portée : aucune requête physique.
		_unseen_time += dt
		_last_noise = 0.0
		saw_player_hide = false
		_apply_awareness(0.0, dt)
		return false
	var dist := sqrt(d2)
	var hidden := _is_player_hidden(p)
	_last_los_clear = has_line_of_sight_to(ppos)
	var gain := 0.0
	var stimulus := false
	# Vue.
	if not hidden and _last_los_clear and dist <= sight_r and (combat or is_in_vision_cone(ppos)):
		can_see_player = true
		last_seen_position = ppos
		has_last_seen = true
		_unseen_time = 0.0
		gain += data.sight_gain * sight_distance_factor(dist, sight_r) * _player_speed_factor(p) * dt
		stimulus = true
	else:
		_unseen_time += dt
	# Ouïe (murs = atténuation, pas blocage).
	var noise := _player_noise(p)
	if noise > 0.0 and dist < data.hearing_radius:
		var att := (1.0 - dist / data.hearing_radius) * (1.0 if _last_los_clear else hearing_wall_factor)
		var heard := noise * att
		if heard >= hearing_noise_floor:
			hears_player = true
			gain += data.hearing_gain * heard * dt
			if noise - _last_noise >= shot_noise_jump:
				# Tir : sursaut immédiat (un coup de feu traverse mieux les murs que des pas).
				gain += shot_awareness_bump * (1.0 - dist / data.hearing_radius) \
					* (1.0 if _last_los_clear else shot_wall_factor)
			stimulus = true
	_last_noise = noise
	# Vu en train de se cacher, de près, alors qu'il était repéré.
	if hidden:
		if not saw_player_hide and awareness >= data.awareness_alert_threshold \
				and _unseen_time <= hide_seen_memory + dt and dist <= hide_reveal_distance:
			saw_player_hide = true
			last_seen_position = ppos
			has_last_seen = true
	else:
		saw_player_hide = false
	if stimulus:
		_set_stimulus(ppos)
	_apply_awareness(gain, dt)
	return can_see_player


## Multiplicateur de gain de vue selon la distance : sight_near_mult tout près,
## sight_edge_mult au bord du rayon, courbe quadratique entre les deux.
func sight_distance_factor(dist: float, radius: float) -> float:
	var t := clampf(1.0 - dist / maxf(radius, 1.0), 0.0, 1.0)
	return lerpf(sight_edge_mult, sight_near_mult, t * t)


## Joueur immobile = moins visible (sight_still_mult), en course = 1.
func _player_speed_factor(p: Node2D) -> float:
	var v := Vector2.ZERO
	if p is CharacterBody2D:
		v = (p as CharacterBody2D).velocity
	var ref: Variant = p.get(&"move_speed")
	var max_speed: float = float(ref) if (ref is float or ref is int) else player_speed_default
	return lerpf(sight_still_mult, 1.0, clampf(v.length() / maxf(max_speed, 1.0), 0.0, 1.0))


func _is_player_hidden(p: Node2D) -> bool:
	return p.has_method(&"is_hidden") and bool(p.call(&"is_hidden"))


## Bruit du joueur (0..1). Repli si get_noise_level() manque : marche = fallback_walk_noise,
## tir (EventBus.projectile_fired d'une source joueur) = 1 décroissant.
func _player_noise(p: Node2D) -> float:
	if p.has_method(&"get_noise_level"):
		return float(p.call(&"get_noise_level"))
	if not _fallback_listening:
		_fallback_listening = true
		EventBus.projectile_fired.connect(_on_any_projectile_fired)
	if _is_player_hidden(p):
		return 0.0
	var n := 0.0
	if p is CharacterBody2D and (p as CharacterBody2D).velocity.length_squared() > 25.0:
		n = fallback_walk_noise
	var since := float(Time.get_ticks_msec() - _fallback_shot_msec) / 1000.0
	return maxf(n, clampf(1.0 - since / maxf(fallback_shot_noise_decay, 0.01), 0.0, 1.0))


func _on_any_projectile_fired(projectile: Node2D) -> void:
	if projectile == null:
		return
	var src: Variant = projectile.get(&"source")
	if src is Node and (src as Node).is_in_group(&"player"):
		_fallback_shot_msec = Time.get_ticks_msec()


func _set_stimulus(pos: Vector2) -> void:
	stimulus_position = pos
	stimulus_serial += 1


## Applique le gain (ou la décroissance) et déclenche les réactions de palier.
func _apply_awareness(gain: float, dt: float, propagate: bool = true) -> void:
	if not _alive:
		return
	if is_in_combat():
		awareness = 1.0
	elif gain > 0.0:
		awareness = minf(awareness + gain, 1.0)
	elif dt > 0.0:
		awareness = maxf(awareness - data.awareness_decay * dt, 0.0)
	_react_to_awareness(gain > 0.0, propagate)
	_refresh_awareness_ui()


func _react_to_awareness(fresh: bool, propagate: bool) -> void:
	if state_machine == null or is_in_combat():
		return
	var s := current_state_name()
	if s == STATE_DEAD:
		return
	if awareness >= data.awareness_alert_threshold:
		awareness = 1.0
		state_machine.transition_to(STATE_ALERT, {"target_pos": stimulus_position, "propagate": propagate})
	elif fresh and awareness >= suspicion_threshold and (s == STATE_PATROL or s == STATE_RETURN):
		state_machine.transition_to(STATE_INVESTIGATE, {"target_pos": stimulus_position})


## Palier de la jauge : 0 calme, 1 suspicion, 2 repéré.
func get_awareness_tier() -> int:
	if is_in_combat() or awareness >= data.awareness_alert_threshold:
		return 2
	return 1 if awareness >= suspicion_threshold else 0


func _refresh_awareness_ui() -> void:
	var tier := get_awareness_tier()
	if tier != _tier:
		_tier = tier
		awareness_tier_changed.emit(tier)
	if _awareness_bar != null:
		_awareness_bar.set_value(awareness, not is_in_combat() and _alive)


## Ajoute `amount` à la jauge depuis un stimulus situé en `pos` (bruit externe, voisin...).
func add_awareness(amount: float, pos: Vector2, propagate: bool = true) -> void:
	if not _alive or amount <= 0.0:
		return
	wake_up()
	_set_stimulus(pos)
	_apply_awareness(amount, 0.0, propagate)


## Jauge à 1 immédiatement (dégâts, etc.) : Alert vers `pos` si hors combat.
func become_aware(pos: Vector2, propagate: bool = true) -> void:
	if not _alive:
		return
	wake_up()
	last_seen_position = pos
	has_last_seen = true
	_set_stimulus(pos)
	awareness = 1.0
	if not is_in_combat() and state_machine != null:
		state_machine.transition_to(STATE_ALERT, {"target_pos": pos, "propagate": propagate})
	_refresh_awareness_ui()


## Fixe la jauge (ex. Return garde une partie de la jauge après une poursuite perdue).
func set_awareness(value: float) -> void:
	awareness = clampf(value, 0.0, 1.0)
	_refresh_awareness_ui()


## Le point est-il dans le cône de vision (toujours vrai si angle >= 360) ?
func is_in_vision_cone(pos: Vector2) -> bool:
	if data.detection_angle_deg >= 360.0:
		return true
	var to := pos - global_position
	if to.length_squared() < 1.0:
		return true
	var half := deg_to_rad(data.detection_angle_deg) * 0.5
	return absf(facing.angle_to(to)) <= half


## Aucun obstacle de la couche world entre l'ennemi et `to` (requête réutilisée).
func has_line_of_sight_to(to: Vector2) -> bool:
	if not is_inside_tree():
		return false
	_ray_query.from = global_position
	_ray_query.to = to
	return get_world_2d().direct_space_state.intersect_ray(_ray_query).is_empty()


## Déloge le joueur de sa cachette (l'ennemi l'a vu s'y glisser).
func reveal_hidden_player() -> bool:
	var p := get_player()
	saw_player_hide = false
	if p == null or not _is_player_hidden(p) or not p.has_method(&"set_hidden"):
		return false
	p.call(&"set_hidden", false)
	return true


# --- Alerte des voisins ------------------------------------------------------------

## Prévient les ennemis vivants dans alert_neighbors_radius. Renvoie le nombre prévenu.
func alert_neighbors(target_pos: Vector2) -> int:
	if not is_inside_tree():
		return 0
	var count := 0
	var r2 := data.alert_neighbors_radius * data.alert_neighbors_radius
	for n: Node in get_tree().get_nodes_in_group(GROUP_UNITS):
		if n == self or not (n is Enemy):
			continue
		var e := n as Enemy
		if not e.is_alive() or global_position.distance_squared_to(e.global_position) > r2:
			continue
		if e.receive_alert(target_pos):
			count += 1
	return count


## Alerte reçue d'un voisin : forte hausse de jauge (neighbor_awareness_boost) vers la
## position signalée — enquête, ou Alert si la jauge déborde. S'il voit lui-même le joueur,
## il passe directement en Alert. Jamais de propagation en chaîne.
func receive_alert(target_pos: Vector2) -> bool:
	if not _alive or is_in_combat():
		return false
	if can_see_player:
		become_aware(last_seen_position, false)
		return true
	add_awareness(neighbor_awareness_boost, target_pos, false)
	return true


# --- Déplacement -------------------------------------------------------------------

## Oriente le regard (et le sprite) vers `dir`.
func face(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		return
	var n := dir.normalized()
	if n.dot(facing) > 0.9995:
		return
	facing = n
	if visual != null and visual.has_method(&"set_facing"):
		visual.call(&"set_facing", facing)


func face_position(pos: Vector2) -> void:
	face(pos - global_position)


func stop() -> void:
	velocity = Vector2.ZERO


func is_at(pos: Vector2, tolerance: float = -1.0) -> bool:
	var tol := arrive_distance if tolerance < 0.0 else tolerance
	return global_position.distance_to(pos) <= tol


## Navigation disponible : la carte du monde contient au moins une région synchronisée.
## Résultat mis en cache nav_check_interval s (map_get_regions alloue un tableau).
func is_navigation_available() -> bool:
	if not is_inside_tree():
		return false
	if _nav_check_left > 0.0:
		return _nav_cached
	_nav_check_left = nav_check_interval
	var map := get_world_2d().navigation_map
	_nav_cached = map.is_valid() and NavigationServer2D.map_get_iteration_id(map) != 0 \
		and not NavigationServer2D.map_get_regions(map).is_empty()
	return _nav_cached


## Fixe la vélocité pour se diriger vers `target` à `speed` (navigation ou steering).
## Repath limité : au plus toutes les nav_repath_interval s, et seulement si la cible a bougé.
func move_toward_position(target: Vector2, speed: float) -> void:
	var dir := Vector2.ZERO
	if is_navigation_available():
		var moved := nav_agent.target_position.distance_squared_to(target) > nav_repath_distance * nav_repath_distance
		if (moved and _repath_left <= 0.0) or (nav_agent.is_navigation_finished() and moved):
			nav_agent.target_position = target
			_repath_left = nav_repath_interval
		if not nav_agent.is_navigation_finished():
			var next := nav_agent.get_next_path_position()
			dir = (next - global_position)
	if dir.length_squared() < 1.0:
		dir = _steer_direct(target - global_position)
	velocity = dir.normalized() * speed if dir.length_squared() > 0.0001 else Vector2.ZERO


## S'éloigne de `from` (l'archer garde ses distances).
func move_away_from(from: Vector2, speed: float) -> void:
	var away := global_position - from
	if away.length_squared() < 1.0:
		away = -facing
	var dir := _steer_direct(away)
	velocity = dir.normalized() * speed if dir.length_squared() > 0.0001 else Vector2.ZERO


## Steering direct avec évitement simple : si le rayon frontal touche un mur,
## on prend le côté libre (moustaches à ±whisker_angle).
func _steer_direct(desired: Vector2) -> Vector2:
	if desired.length_squared() < 0.0001 or not is_inside_tree():
		return desired
	var dir := desired.normalized()
	var length := whisker_length + data.body_radius
	if not _ray_blocked(dir * length):
		return dir
	var left := dir.rotated(-whisker_angle)
	var right := dir.rotated(whisker_angle)
	var left_free := not _ray_blocked(left * length)
	var right_free := not _ray_blocked(right * length)
	if left_free and not right_free:
		return left
	if right_free and not left_free:
		return right
	if left_free and right_free:
		return left if absf(left.angle_to(facing)) < absf(right.angle_to(facing)) else right
	# Coincé : longer le mur (perpendiculaire).
	return dir.orthogonal()


func _ray_blocked(offset: Vector2) -> bool:
	_ray_query.from = global_position
	_ray_query.to = global_position + offset
	return not get_world_2d().direct_space_state.intersect_ray(_ray_query).is_empty()


# --- Combat ----------------------------------------------------------------------

## Exécute le coup à la fin du télégraphe. Renvoie vrai si un coup/tir est parti.
func perform_attack() -> bool:
	var p := get_player()
	if p == null:
		return false
	attack_cooldown_left = data.attack_cooldown
	if data.is_ranged():
		var dir := p.global_position - global_position
		var pool := EnemyProjectilePool.get_or_create(get_tree())
		if pool == null:
			return false
		var muzzle := global_position + dir.normalized() * (data.body_radius + 6.0)
		for shot_dir: Vector2 in get_shot_directions(dir):
			pool.spawn(muzzle, shot_dir, data.projectile_speed, data.attack_damage, self,
				data.projectile_lifetime, data.projectile_style)
		return true
	# Coup de zone au sol : touche le joueur s'il est dans aoe_radius (pas de tolérance).
	if data.is_area_attack():
		_visual_call(&"play_ground_slam", [data.aoe_radius])
		if global_position.distance_to(p.global_position) <= data.aoe_radius and p.has_method("take_damage"):
			p.call("take_damage", data.attack_damage, self)
			return true
		return false
	# Mêlée : le joueur doit encore être à portée (il a pu esquiver pendant le télégraphe).
	var tolerance := Balance.get_float("enemy_ai", "melee_hit_tolerance", 16.0)
	if global_position.distance_to(p.global_position) <= data.attack_range + tolerance and p.has_method("take_damage"):
		p.call("take_damage", data.attack_damage, self)
		return true
	return false


## Directions des projectiles d'un tir : une seule (projectile_count = 1) ou un éventail
## régulier de projectile_count directions sur projectile_spread_deg, centré sur `aim`.
func get_shot_directions(aim: Vector2) -> Array[Vector2]:
	var base := aim.normalized() if aim.length_squared() > 0.0001 else facing
	var out: Array[Vector2] = []
	var n := maxi(data.projectile_count, 1)
	if n == 1:
		out.append(base)
		return out
	var spread := deg_to_rad(data.projectile_spread_deg)
	for i: int in n:
		var t := float(i) / float(n - 1) - 0.5
		out.append(base.rotated(spread * t))
	return out


# --- Interface de dégâts ------------------------------------------------------------

func take_damage(amount: float, source: Node) -> void:
	if not _alive or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_visual_call(&"flash_hit")
	damaged.emit(amount, hp)
	if _health_bar != null:
		_health_bar.queue_redraw()
	if hp <= 0.0:
		_die()
		return
	# Être touché = jauge à 1 : alerte vers la source si connue, sinon vers le joueur.
	if not is_in_combat():
		var pos := global_position
		var p := get_player()
		if source is Node2D and is_instance_valid(source):
			pos = (source as Node2D).global_position
		elif p != null:
			pos = p.global_position
		become_aware(pos, true)


func is_alive() -> bool:
	return _alive


func heal(amount: float) -> void:
	if _alive and amount > 0.0:
		hp = minf(hp + amount, max_hp)
		if _health_bar != null:
			_health_bar.queue_redraw()


func _die() -> void:
	_alive = false
	can_see_player = false
	velocity = Vector2.ZERO
	wake_up()  # L'animation de mort doit se jouer.
	if _sleep_timer != null:
		_sleep_timer.stop()
	if _awareness_bar != null:
		_awareness_bar.set_value(0.0, false)
	# Retiré immédiatement des cibles ; reste dans enemy_units jusqu'à sa libération.
	remove_from_group(GROUP_ENEMIES)
	remove_from_group(GROUP_DAMAGEABLE)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	for child: Node in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
	if _health_bar != null:
		_health_bar.visible = false
	state_machine.transition_to(STATE_DEAD)
	died.emit(self)
	EventBus.enemy_died.emit(self, global_position)


func _on_death_finished() -> void:
	if not _alive and not is_queued_for_deletion():
		queue_free()


# --- Visuel ------------------------------------------------------------------------

## Appel tolérant sur le composant visuel (méthode absente = ignorée).
func _visual_call(method: StringName, args: Array = []) -> Variant:
	if visual != null and is_instance_valid(visual) and visual.has_method(method):
		return visual.callv(method, args)
	return null


func get_head_offset() -> Vector2:
	var v: Variant = _visual_call(&"get_head_offset")
	if v is Vector2:
		return v
	return Vector2(0, -data.body_radius * 2.5)


func current_state_name() -> StringName:
	return state_machine.get_current_state_name() if state_machine != null else &""


func get_debug_info() -> Dictionary:
	return {
		"kind": String(data.kind),
		"state": String(current_state_name()),
		"hp": hp,
		"max_hp": max_hp,
		"sees_player": can_see_player,
		"hears_player": hears_player,
		"awareness": awareness,
		"asleep": asleep,
		"cooldown": attack_cooldown_left,
		"nav": "agent" if is_navigation_available() else "steering",
	}


# --- Debug F3 ----------------------------------------------------------------------

func _draw_debug(canvas: Node2D) -> void:
	if not is_inside_tree() or data == null:
		return
	var state := current_state_name()
	var col: Color = DEBUG_STATE_COLORS.get(state, Color.WHITE)
	var pos := global_position
	var radius := data.detection_radius * (chase_sight_multiplier if is_in_combat() else 1.0)
	# Zone de détection (cercle ou cône selon l'état et l'archétype).
	if data.detection_angle_deg >= 360.0 or is_in_combat():
		canvas.draw_circle(pos, radius, Color(col, 0.07))
		canvas.draw_arc(pos, radius, 0.0, TAU, 64, Color(col, 0.75), 2.0, true)
	else:
		var half := deg_to_rad(data.detection_angle_deg) * 0.5
		var a0 := facing.angle() - half
		var pts := PackedVector2Array([pos])
		var steps := 24
		for i: int in steps + 1:
			pts.append(pos + Vector2.from_angle(a0 + 2.0 * half * float(i) / float(steps)) * radius)
		canvas.draw_colored_polygon(pts, Color(col, 0.10))
		pts.append(pos)
		canvas.draw_polyline(pts, Color(col, 0.8), 2.0, true)
	# Rayon d'audition (pointillé discret).
	canvas.draw_arc(pos, data.hearing_radius, 0.0, TAU, 48, Color(0.6, 0.75, 1.0, 0.35 if hears_player else 0.18), 1.5 if hears_player else 1.0, true)
	# Portée d'attaque.
	canvas.draw_arc(pos, data.attack_range, 0.0, TAU, 40, Color(1.0, 0.2, 0.2, 0.7), 1.5, true)
	# Ligne de vue vers le joueur (si à portée de perception).
	var p := get_player()
	if p != null and _alive and pos.distance_to(p.global_position) <= radius:
		var clear := _last_los_clear
		canvas.draw_line(pos, p.global_position, Color(0.2, 1.0, 0.3, 0.8) if clear else Color(1.0, 0.15, 0.15, 0.8), 2.0, true)
	# Dernière position connue.
	if has_last_seen and (state == STATE_CHASE or state == STATE_ALERT):
		canvas.draw_circle(last_seen_position, 6.0, Color(1.0, 0.55, 0.1, 0.9))
	if state == STATE_INVESTIGATE:
		canvas.draw_circle(stimulus_position, 6.0, Color(1.0, 0.9, 0.3, 0.9))
		canvas.draw_line(pos, stimulus_position, Color(1.0, 0.9, 0.3, 0.35), 1.0, true)
	# Point d'apparition / patrouille.
	canvas.draw_arc(spawn_position, data.patrol_radius, 0.0, TAU, 32, Color(0.3, 0.95, 0.35, 0.25), 1.0, true)
	# Nom de l'état au-dessus de la tête.
	var font := ThemeDB.fallback_font
	var label := "%s %d%%%s%s%s" % [String(state), roundi(awareness * 100.0),
		" vu" if can_see_player else "", " entendu" if hears_player else "", " zzz" if asleep else ""]
	var head := pos + get_head_offset() + Vector2(-40, -26)
	canvas.draw_string_outline(font, head, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0.07, 0.1, 0.18))
	canvas.draw_string(font, head, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)


## Barre de vie au-dessus de la tête (enfant dessiné après le visuel).
## Redessinée uniquement quand les PV changent (take_damage / heal appellent queue_redraw).
class HealthBar extends Node2D:
	var enemy: Enemy = null

	func _draw() -> void:
		if enemy == null or not enemy.is_alive():
			return
		var w: float = enemy.health_bar_width
		var h := 7.0
		var head: Vector2 = enemy.get_head_offset() + Vector2(0, -12)
		var bar := Rect2(head - Vector2(w * 0.5, h), Vector2(w, h))
		var ratio := clampf(enemy.hp / maxf(enemy.max_hp, 0.01), 0.0, 1.0)
		draw_rect(bar.grow(2.0), Color(0.07, 0.10, 0.18, 0.92))
		draw_rect(bar, Color(0.25, 0.05, 0.07))
		draw_rect(Rect2(bar.position, Vector2(w * ratio, h)), Color(0.95, 0.2, 0.15).lerp(Color(0.95, 0.45, 0.15), 1.0 - ratio))
		draw_rect(bar.grow(2.0), Color(0.85, 0.88, 0.95, 0.6), false, 1.0)


## Visuel de repli (cercle) si res://scripts/enemies/enemy_visual.gd n'existe pas.
## Implémente la même API qu'EnemyVisual.
class FallbackVisual extends Node2D:
	signal death_finished

	var radius: float = 22.0
	var head_offset: Vector2 = Vector2(0, -60)
	var color: Color = Color(0.78, 0.58, 0.36)
	var _facing: Vector2 = Vector2.DOWN
	var _flash: float = 0.0
	var _alert: float = 0.0
	var _windup: float = 0.0
	var _windup_total: float = 0.0
	var _dying: float = -1.0

	func setup(kind: StringName) -> void:
		match kind:
			&"golem":
				radius = 34.0
				color = Color(0.72, 0.58, 0.40)
			&"masked_brute":
				radius = 28.0
				color = Color(0.55, 0.18, 0.16)
			&"masked_archer":
				radius = 18.0
				color = Color(0.35, 0.30, 0.45)
			_:
				radius = 20.0
				color = Color(0.45, 0.25, 0.22)
		head_offset = Vector2(0, -radius * 2.6)

	func set_facing(dir: Vector2) -> void:
		_facing = dir

	func set_moving(_moving: bool) -> void:
		pass

	func flash_hit() -> void:
		_flash = 0.12

	func play_alert() -> void:
		_alert = 0.8

	func play_attack_windup(duration: float) -> void:
		_windup = duration
		_windup_total = maxf(duration, 0.01)

	func play_death() -> void:
		_dying = 0.5

	func set_aura(c: Color) -> void:
		color = color.lerp(c, 0.4)

	func get_head_offset() -> Vector2:
		return head_offset

	func _process(delta: float) -> void:
		_flash = maxf(_flash - delta, 0.0)
		_alert = maxf(_alert - delta, 0.0)
		_windup = maxf(_windup - delta, 0.0)
		if _dying > 0.0:
			_dying -= delta
			modulate.a = clampf(_dying / 0.5, 0.0, 1.0)
			if _dying <= 0.0:
				death_finished.emit()
		queue_redraw()

	func _draw() -> void:
		var c := Color.WHITE if _flash > 0.0 else color
		draw_circle(Vector2(0, 4), radius * 1.1, Color(0.07, 0.1, 0.22, 0.45))
		draw_circle(Vector2(0, -radius), radius, c)
		draw_arc(Vector2(0, -radius), radius, 0.0, TAU, 32, Color(0.1, 0.08, 0.12), 2.5, true)
		draw_line(Vector2(0, -radius), Vector2(0, -radius) + _facing * radius, Color(1.0, 0.9, 0.8), 3.0)
		if _windup > 0.0:
			var t := 1.0 - _windup / _windup_total
			draw_arc(Vector2(0, -radius), radius + 6.0, 0.0, TAU * t, 32, Color(1.0, 0.2, 0.1, 0.9), 4.0, true)
		if _alert > 0.0:
			var font := ThemeDB.fallback_font
			draw_string(font, head_offset + Vector2(-6, -20), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(1.0, 0.85, 0.2))
