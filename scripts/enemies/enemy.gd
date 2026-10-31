class_name Enemy
extends CharacterBody2D
## Ennemi générique piloté par une StateMachine :
##   Patrol (points d'intérêt) → [Investigate] → Alert (« ! » + cri) → Chase (combat tactique)
##   ⇄ Attack (schémas : rafale, éventail, tir précis, dynamite, ruée + combo, zone)
##   → Search (joueur perdu) → Return ; Retreat (faible vie), Stunned (gros coup), Dead.
## Toutes les valeurs propres à l'ennemi viennent de `data` (EnemyData, data/enemies/*.tres) ;
## les réglages globaux de l'IA viennent de balance.cfg [enemy_ai], [enemy_tactics],
## [enemy_difficulty].
##
## Perception (évaluée tous les los_check_interval s, phase aléatoire par ennemi) :
##  - hors combat : rayon detection_radius, cône si detection_angle_deg < 360, ligne de vue
##    (raycast couche world), joueur non caché ; en combat : cône ignoré, portée × chase_sight_multiplier.
##  Un seul raycast par évaluation, et seulement si le joueur est dans le rayon max (vue/ouïe).
##
## Discrétion — jauge de reconnaissance `awareness` (0..1), cf. CONVENTIONS « Discrétion ».
##
## Déplacement : les états fixent une vitesse SOUHAITÉE (desired_velocity) ; l'ennemi l'atteint
## avec une accélération bornée (pas de tremblement), plus une séparation douce avec ses voisins
## proches (liste rafraîchie 4×/s parmi les ennemis éveillés : aucun parcours de groupe par frame).
## Navigation : NavigationAgent2D si la carte de navigation contient une région, sinon steering
## direct avec évitement des murs (3 raycasts « moustaches »).
##
## Performance : ennemi « endormi » (physics/animation coupés) au-delà de sleep_distance du
## joueur (Timer à 2 Hz) ; décisions tactiques espacées (think_interval) ; recherche de couvert
## limitée (un raycast de validation, au plus toutes les cover_search_interval s) ; barre de vie
## et jauge redessinées seulement sur changement.

const SCENE_PATH := "res://scenes/enemies/enemy.tscn"
const VISUAL_SCRIPT_PATH := "res://scripts/enemies/enemy_visual.gd"

const LAYER_ENEMIES := 4
const MASK_WORLD := 1
const MASK_PLAYER := 2

const GROUP_ENEMIES := &"enemies"
const GROUP_DAMAGEABLE := &"damageable"
const GROUP_UNITS := &"enemy_units"
const GROUP_BOSS := &"boss"

const STATE_PATROL := &"Patrol"
const STATE_INVESTIGATE := &"Investigate"
const STATE_ALERT := &"Alert"
const STATE_CHASE := &"Chase"
const STATE_ATTACK := &"Attack"
const STATE_SEARCH := &"Search"
const STATE_RETREAT := &"Retreat"
const STATE_STUNNED := &"Stunned"
const STATE_RETURN := &"Return"
const STATE_DEAD := &"Dead"
## Compétence active en cours (EnemySkill, cf. enemy_skill_state.gd).
const STATE_SKILL := &"Skill"

const STATE_SCRIPTS: Array[Script] = [
	preload("res://scripts/ai/enemy_states/enemy_patrol_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_investigate_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_alert_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_chase_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_attack_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_search_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_retreat_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_stunned_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_return_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_dead_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_skill_state.gd"),
]

## Couleurs debug par état (F3).
const DEBUG_STATE_COLORS := {
	STATE_PATROL: Color(0.3, 0.95, 0.35),
	STATE_INVESTIGATE: Color(0.95, 0.95, 0.4),
	STATE_ALERT: Color(1.0, 0.9, 0.2),
	STATE_CHASE: Color(1.0, 0.55, 0.1),
	STATE_ATTACK: Color(1.0, 0.15, 0.15),
	STATE_SEARCH: Color(0.85, 0.6, 1.0),
	STATE_RETREAT: Color(0.4, 0.9, 1.0),
	STATE_STUNNED: Color(1.0, 1.0, 1.0),
	STATE_RETURN: Color(0.3, 0.6, 1.0),
	STATE_DEAD: Color(0.5, 0.5, 0.5),
	STATE_SKILL: Color(1.0, 0.3, 0.9),
}

## Cris (bulle au-dessus de la tête), par situation.
const SHOUTS := {
	&"spot": ["Il est là !", "Là-bas !", "Un intrus !", "Feu !"],
	&"call": ["À moi !", "Par ici !"],
	&"lost": ["Où il est passé ?", "Cherchez-le !"],
	&"retreat": ["Repli !", "Couvrez-moi !"],
	&"dynamite": ["Dynamite !", "Gare à toi !"],
	&"phase2": ["Tuez-le, bon sang !", "À moi les gars !"],
}

signal damaged(amount: float, current_hp: float)
signal died(enemy: Enemy)
## Émis quand la jauge de reconnaissance change de palier (0 calme, 1 suspicion, 2 repéré).
signal awareness_tier_changed(tier: int)
## Élite : changement de phase (2 = enragé).
signal phase_changed(phase: int)

## Ennemis éveillés et vivants (séparation, flanquement). Tenu à jour sans allocation par frame.
static var active_units: Array[Enemy] = []
static var _last_shout_msec: int = -100000
## Mesure de performance (tests) : temps cumulé (µs) passé dans _physics_process des ennemis.
static var profiling: bool = false
static var profile_usec: int = 0

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
## Conservé pour compatibilité (la détection se fait par distance). Toujours null.
var detection_area: Area2D = null

## Résultat de la dernière perception.
var can_see_player: bool = false
var last_seen_position: Vector2 = Vector2.ZERO
var has_last_seen: bool = false
## Délai restant avant la prochaine attaque possible.
var attack_cooldown_left: float = 0.0

## Jauge de reconnaissance 0..1 (1 = repéré).
var awareness: float = 0.0
var stimulus_position: Vector2 = Vector2.ZERO
var stimulus_serial: int = 0
var hears_player: bool = false
var saw_player_hide: bool = false
var asleep: bool = false
## Coop, invité : « marionnette » pilotée par les instantanés de l'hôte (pas d'IA locale).
var net_puppet: bool = false

## Vitesse souhaitée par l'état courant (atteinte avec une accélération bornée).
var desired_velocity: Vector2 = Vector2.ZERO
## Vrai : la vitesse souhaitée est appliquée telle quelle (ruée).
var direct_velocity: bool = false
## Phase de combat (élite : 2 = enragé sous phase2_hp_ratio).
var phase: int = 1
## A déjà battu en retraite (une seule fois).
var has_retreated: bool = false
## Côté de flanquement courant (-1, 0, +1) et couvert réservé (indice CoverMap, -1 = aucun).
var flank_side: int = 0
var cover_index: int = -1
var cover_position: Vector2 = Vector2.ZERO
## Butin du cadavre, tiré à la mort par LootManager (vide = pas de butin).
var corpse_entries: Array[Dictionary] = []
var corpse_placed: bool = false
## Compétences (EnemyData.skills) ; `active_skill` = celle en cours d'exécution.
var skills: Array[EnemySkill] = []
var active_skill: EnemySkill = null
## Invulnérabilité brève (roulade, téléportation).
var invulnerable_left: float = 0.0
## Gel (affixe d'arme du joueur, AffixStatus) : vitesse de déplacement × affix_slow_mult.
var affix_slow_mult: float = 1.0
## Rage (compétence « rage ») : multiplicateurs de vitesse et de recharge.
var rage_speed_mult: float = 1.0
var rage_cooldown_mult: float = 1.0
## Boss (EnemyData.boss) : indice de la phase courante dans data.phases (-1 = pas de phases)
## et multiplicateurs de la phase.
var boss_phase: int = -1
var phase_speed_mult: float = 1.0
var phase_cooldown_mult: float = 1.0
var phase_damage_mult: float = 1.0
var phase_pattern: StringName = &""
var _boss_engaged: bool = false
## Étourdissement demandé par une compétence (charge contre un mur), appliqué à sa fin.
var pending_stun: float = 0.0
var _skill_check_left: float = 0.0
var _skill_gap_left: float = 0.0
var _reactive_left: float = 0.0
var skill_check_interval: float = 0.3
var reactive_check_interval: float = 0.12
var skill_gap: float = 1.2
## Multiplicateurs de difficulté ([enemy_difficulty], GameState.difficulty 0..4).
var diff_damage_mult: float = 1.0
var diff_windup_mult: float = 1.0
var diff_cooldown_mult: float = 1.0
var diff_spread_mult: float = 1.0
var diff_speed_mult: float = 1.0
var diff_skill_cooldown_mult: float = 1.0

# Réglages globaux [enemy_ai]
var los_check_interval: float = 0.1
var chase_sight_multiplier: float = 1.5
var arrive_distance: float = 12.0
var whisker_length: float = 48.0
var whisker_angle: float = deg_to_rad(35.0)
var nav_repath_distance: float = 24.0
var death_free_fallback: float = 2.0
var health_bar_width: float = 40.0
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
# Déplacement / tactique ([enemy_tactics])
var accel: float = 1400.0
var separation_strength: float = 140.0
var separation_margin: float = 14.0
var neighbor_refresh: float = 0.25
var knock_decay: float = 900.0
var think_interval: float = 0.45
var cover_search_interval: float = 1.2
var cover_max_travel: float = 300.0
var flank_angle_deg: float = 65.0
var shout_cooldown: float = 2.5
var melee_hit_tolerance: float = 16.0
var aim_lock_ratio: float = 0.25
var peek_offset: float = 56.0
var lob_lead: float = 0.5

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
var _fallback_shot_msec: int = -100000
var _fallback_listening: bool = false
var _knock: Vector2 = Vector2.ZERO
var _neighbors: Array[Enemy] = []
var _neighbor_left: float = 0.0
var _faced_this_frame: bool = false
var _pattern_counter: int = 0
var _shout_left: float = 0.0
var _cover_search_left: float = 0.0
var _hurt_sfx_msec: int = -100000
var _cover_buf: PackedInt32Array = PackedInt32Array()
var _avoid_ref: Vector2 = Vector2.ZERO
var _avoid_angle: float = 0.0
# Décoincement : progression mesurée toutes les 0,4 s ; pas de côté si bloqué.
var _stuck_check_left: float = 0.4
var _stuck_last_pos: Vector2 = Vector2.ZERO
var _unstick_left: float = 0.0
var _unstick_dir: Vector2 = Vector2.ZERO


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
	_load_difficulty()
	max_hp = data.max_hp * boss_hp_scale()
	hp = max_hp
	spawn_position = global_position
	last_seen_position = global_position
	stimulus_position = global_position
	_perception_left = randf() * los_check_interval
	_neighbor_left = randf() * neighbor_refresh
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
	skills = EnemySkills.build(self, data)
	_build_state_machine()
	if data.boss:
		add_to_group(GROUP_BOSS)
		_enter_boss_phase(0, false)
	_build_sleep_timer()
	_register_active(true)
	_register_debug.call_deferred()
	EventBus.enemy_spawned.emit(self)


func _exit_tree() -> void:
	_register_active(false)
	_release_cover()


func _load_balance() -> void:
	los_check_interval = Balance.get_float("enemy_ai", "los_check_interval", 0.1)
	chase_sight_multiplier = Balance.get_float("enemy_ai", "chase_sight_multiplier", 1.5)
	arrive_distance = Balance.get_float("enemy_ai", "arrive_distance", 12.0)
	whisker_length = Balance.get_float("enemy_ai", "whisker_length", 48.0)
	whisker_angle = deg_to_rad(Balance.get_float("enemy_ai", "whisker_angle_deg", 35.0))
	nav_repath_distance = Balance.get_float("enemy_ai", "nav_repath_distance", 24.0)
	death_free_fallback = Balance.get_float("enemy_ai", "death_free_fallback", 2.0)
	health_bar_width = Balance.get_float("enemy_ai", "health_bar_width", 40.0)
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
	if data != null:
		return_regen_ratio_per_sec *= data.return_regen_mult
	if data != null and data.boss:
		return_regen_ratio_per_sec = Balance.get_float("boss", "return_regen_ratio_per_sec", 0.0)
	return_timeout = _bf("return_timeout", return_timeout)
	sleep_distance = _bf("sleep_distance", sleep_distance)
	wake_distance = minf(_bf("wake_distance", wake_distance), sleep_distance)
	sleep_check_interval = _bf("sleep_check_interval", sleep_check_interval)
	nav_repath_interval = _bf("nav_repath_interval", nav_repath_interval)
	nav_check_interval = _bf("nav_check_interval", nav_check_interval)
	accel = _tf("accel", accel)
	separation_strength = _tf("separation_strength", separation_strength)
	separation_margin = _tf("separation_margin", separation_margin)
	neighbor_refresh = _tf("neighbor_refresh", neighbor_refresh)
	knock_decay = _tf("knock_decay", knock_decay)
	think_interval = _tf("think_interval", think_interval)
	cover_search_interval = _tf("cover_search_interval", cover_search_interval)
	cover_max_travel = _tf("cover_max_travel", cover_max_travel)
	flank_angle_deg = _tf("flank_angle_deg", flank_angle_deg)
	shout_cooldown = _tf("shout_cooldown", shout_cooldown)
	melee_hit_tolerance = _bf("melee_hit_tolerance", melee_hit_tolerance)
	aim_lock_ratio = _tf("aim_lock_ratio", aim_lock_ratio)
	peek_offset = _tf("peek_offset", peek_offset)
	lob_lead = _tf("lob_lead", lob_lead)


func _bf(key: String, default: float) -> float:
	return Balance.get_float("enemy_ai", key, default)


func _tf(key: String, default: float) -> float:
	return Balance.get_float("enemy_tactics", key, default)


## Multiplicateurs de difficulté (n'altèrent pas `data` : PV et vitesse de base inchangés).
func _load_difficulty() -> void:
	var d: int = clampi(int(GameState.get("difficulty")) if GameState.get("difficulty") != null else 1, 0, 4)
	diff_damage_mult = _diff_at("damage_mult", d, [0.75, 1.0, 1.12, 1.25, 1.4])
	diff_windup_mult = _diff_at("windup_mult", d, [1.25, 1.0, 0.94, 0.88, 0.8])
	diff_cooldown_mult = _diff_at("cooldown_mult", d, [1.2, 1.0, 0.92, 0.85, 0.75])
	diff_spread_mult = _diff_at("spread_mult", d, [1.4, 1.0, 0.9, 0.8, 0.65])
	diff_speed_mult = _diff_at("speed_mult", d, [0.92, 1.0, 1.03, 1.06, 1.1])
	diff_skill_cooldown_mult = _diff_at("skill_cooldown_mult", d, [1.3, 1.0, 0.92, 0.85, 0.75])
	skill_check_interval = EnemySkills.cfg("check_interval", 0.3)
	reactive_check_interval = EnemySkills.cfg("reactive_check_interval", 0.12)
	skill_gap = EnemySkills.cfg("skill_gap", 1.2)


## Multiplicateur des PV d'un boss selon la difficulté du raid ([boss] hp_mult) ; 1 sinon.
func boss_hp_scale() -> float:
	if data == null or not data.boss:
		return 1.0
	return boss_hp_mult(clampi(int(GameState.get("difficulty")) if GameState.get("difficulty") != null else 1, 0, 4))


static func boss_hp_mult(difficulty: int) -> float:
	var def: Array = [1.0]
	var v: Variant = Balance.get_value("boss", "hp_mult", def)
	var a: Array = v if v is Array and not (v as Array).is_empty() else def
	return maxf(float(a[clampi(difficulty, 0, a.size() - 1)]), 0.05)


static func _diff_at(key: String, index: int, def: Array) -> float:
	var v: Variant = Balance.get_value("enemy_difficulty", key, def)
	var a: Array = v if v is Array and not (v as Array).is_empty() else def
	return float(a[clampi(index, 0, a.size() - 1)])


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
	nav_agent.path_desired_distance = maxf(arrive_distance, 20.0)
	nav_agent.target_desired_distance = arrive_distance
	nav_agent.avoidance_enabled = false
	add_child(nav_agent)


func _build_visual() -> void:
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
	_configure_visual_telegraphs()
	if visual.has_signal("death_finished"):
		visual.connect("death_finished", _on_death_finished)
	_visual_call(&"set_facing", [facing])
	_visual_call(&"set_elite", [data.elite])


func _configure_visual_telegraphs() -> void:
	_visual_call(&"set_attack_area", [0.0])
	_visual_call(&"set_attack_cone", [0.0, 0.0])
	if data.is_area_attack():
		_visual_call(&"set_attack_area", [data.aoe_radius])
	elif data.is_ranged() and data.projectile_count > 1:
		var reach := data.projectile_speed * (data.projectile_lifetime if data.projectile_lifetime > 0.0
			else Balance.get_float("enemy_ai", "projectile_lifetime", 2.5))
		_visual_call(&"set_attack_cone", [data.projectile_spread_deg, minf(reach, data.attack_range * 1.2)])


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
	_awareness_bar.setup(get_head_offset() + Vector2(0, -10.0 - 4.0 - 22.0), suspicion_threshold)


func _build_sleep_timer() -> void:
	_sleep_timer = Timer.new()
	_sleep_timer.name = "SleepTimer"
	_sleep_timer.one_shot = false
	_sleep_timer.wait_time = maxf(sleep_check_interval, 0.05)
	add_child(_sleep_timer)
	_sleep_timer.timeout.connect(_on_sleep_check)
	_sleep_timer.start(randf_range(0.05, maxf(sleep_check_interval, 0.05)))


func _build_state_machine() -> void:
	state_machine = StateMachine.new()
	state_machine.name = "StateMachine"
	state_machine.auto_process = false
	for s: Script in STATE_SCRIPTS:
		var st: State = s.new() as State
		state_machine.add_child(st)
	add_child(state_machine)
	state_machine.state_changed.connect(_on_state_changed)
	state_machine.start(self, STATE_PATROL)


func _register_debug() -> void:
	if _debug_registered or not is_inside_tree():
		return
	var dbg := DebugWorldDraw.find(get_tree())
	if dbg != null:
		dbg.register_drawer(_draw_debug)
		_debug_registered = true


func _register_active(on: bool) -> void:
	var i := active_units.find(self)
	if on and i < 0 and _alive and not asleep:
		active_units.append(self)
	elif not on and i >= 0:
		active_units.remove_at(i)


func _on_state_changed(_from: StringName, _to: StringName) -> void:
	if _health_bar != null:
		_health_bar.queue_redraw()
	if data.boss and not _boss_engaged and _alive and is_in_combat():
		_boss_engaged = true
		EventBus.boss_engaged.emit(self)


# --- Boucle --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec() if profiling else 0
	_physics_step(delta)
	if profiling:
		profile_usec += Time.get_ticks_usec() - t0


func _physics_step(delta: float) -> void:
	if net_puppet:
		return
	if not _debug_registered:
		_register_debug()
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	if _nav_check_left > 0.0:
		_nav_check_left -= delta
	if _repath_left > 0.0:
		_repath_left -= delta
	if _shout_left > 0.0:
		_shout_left -= delta
	if _cover_search_left > 0.0:
		_cover_search_left -= delta
	if not skills.is_empty():
		_tick_skills(delta)
	if _alive:
		_perception_left -= delta
		_perception_elapsed += delta
		if _perception_left <= 0.0:
			_perception_left += los_check_interval
			if _perception_left <= 0.0:
				_perception_left = los_check_interval
			update_perception(_perception_elapsed)
			_perception_elapsed = 0.0
		_neighbor_left -= delta
		if _neighbor_left <= 0.0:
			_neighbor_left = neighbor_refresh
			_refresh_neighbors()
	_faced_this_frame = false
	state_machine.physics_update(delta)
	if _alive:
		_integrate(delta)
	else:
		velocity = Vector2.ZERO


## Recharges des compétences + contrôle (espacé) des compétences réactives en combat.
func _tick_skills(delta: float) -> void:
	if invulnerable_left > 0.0:
		invulnerable_left -= delta
	if _skill_gap_left > 0.0:
		_skill_gap_left -= delta
	for sk: EnemySkill in skills:
		sk.tick_cooldown(delta)
	_reactive_left -= delta
	if _reactive_left > 0.0 or not _alive:
		return
	_reactive_left = reactive_check_interval
	var s := current_state_name()
	if s != STATE_CHASE:
		return
	var p := get_player()
	if p != null:
		try_use_skill(global_position.distance_to(p.global_position), can_see_player, true)


## Applique la vitesse souhaitée (accélération bornée), la séparation et le recul.
func _integrate(delta: float) -> void:
	_update_stuck(delta)
	if direct_velocity:
		velocity = desired_velocity * affix_slow_mult
	else:
		var target := desired_velocity * affix_slow_mult
		if _unstick_left > 0.0:
			target = _unstick_dir * maxf(desired_velocity.length(), data.move_speed * 0.6)
		if not _neighbors.is_empty():
			target += _separation()
		velocity = velocity.move_toward(target, accel * delta)
	if _knock != Vector2.ZERO:
		velocity += _knock
		_knock = _knock.move_toward(Vector2.ZERO, knock_decay * delta)
	if velocity.length_squared() > 1.0:
		move_and_slide()
	var speed2 := velocity.length_squared()
	var moving := speed2 > 400.0 and desired_velocity.length_squared() > 1.0
	if moving and not _faced_this_frame:
		_apply_facing(velocity)
	_set_visual_moving(moving)
	if moving and visual != null and visual.has_method(&"set_speed_scale"):
		visual.call(&"set_speed_scale", sqrt(speed2) / maxf(data.move_speed, 1.0))


## Bloqué contre un décor malgré une vitesse souhaitée : pas de côté pendant un court instant.
func _update_stuck(delta: float) -> void:
	if _unstick_left > 0.0:
		_unstick_left -= delta
	_stuck_check_left -= delta
	if _stuck_check_left > 0.0:
		return
	_stuck_check_left = 0.4
	var moved := global_position.distance_to(_stuck_last_pos)
	_stuck_last_pos = global_position
	if direct_velocity or desired_velocity.length_squared() < 900.0 or _unstick_left > 0.0:
		return
	if moved < desired_velocity.length() * 0.4 * 0.25:
		var side := 1.0 if (get_instance_id() + Engine.get_physics_frames()) % 2 == 0 else -1.0
		_unstick_dir = (desired_velocity.normalized().orthogonal() * side - desired_velocity.normalized() * 0.3).normalized()
		if _ray_blocked(_unstick_dir * (data.body_radius + 30.0)):
			_unstick_dir = (-_unstick_dir - desired_velocity.normalized() * 0.6).normalized()
		_unstick_left = 0.5
		_repath_left = 0.0


func _refresh_neighbors() -> void:
	_neighbors.clear()
	var r := data.body_radius * 2.0 + separation_margin + 40.0
	var r2 := r * r
	for n: Enemy in active_units:
		if n == self or not is_instance_valid(n) or not n._alive:
			continue
		if global_position.distance_squared_to(n.global_position) <= r2:
			_neighbors.append(n)


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for n: Enemy in _neighbors:
		if not is_instance_valid(n) or not n._alive:
			continue
		var d := global_position - n.global_position
		var r := data.body_radius + n.data.body_radius + separation_margin
		var l2 := d.length_squared()
		if l2 < r * r:
			if l2 < 0.01:
				d = Vector2.RIGHT.rotated(float(get_instance_id() % 628) * 0.01)
				l2 = 1.0
			var l := sqrt(l2)
			push += d / l * (1.0 - l / r)
	return push * separation_strength


func _set_visual_moving(moving: bool) -> void:
	if moving == _visual_moving:
		return
	_visual_moving = moving
	if visual != null and visual.has_method(&"set_moving"):
		visual.call(&"set_moving", moving)


# --- Sommeil (performance) ---------------------------------------------------------

func _on_sleep_check() -> void:
	if not _alive or net_puppet:
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
	desired_velocity = Vector2.ZERO
	_set_visual_moving(false)
	set_physics_process(false)
	if visual != null:
		visual.set_process(false)
	_register_active(false)


func wake_up() -> void:
	if not asleep:
		return
	asleep = false
	_perception_left = randf() * los_check_interval
	_perception_elapsed = 0.0
	set_physics_process(true)
	if visual != null:
		visual.set_process(true)
	_register_active(true)


# --- Perception ------------------------------------------------------------------

func get_player() -> Node2D:
	if NetHooks.active:
		# Coop : le joueur ciblable le plus proche (hôte : joueur local ou avatar de l'invité).
		_player = NetHooks.enemy_target(self, _player)
		return _player
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = null
		var p: Node2D = GameState.player
		if is_instance_valid(p) and p.is_inside_tree() and p.is_in_group(&"player"):
			_player = p
		elif is_inside_tree():
			_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _player == null:
		return null
	if _player.has_method("is_alive") and not bool(_player.call("is_alive")):
		return null
	return _player


func distance_to_player() -> float:
	var p := get_player()
	return INF if p == null else global_position.distance_to(p.global_position)


## États « de combat » (perception sans cône, portée étendue, jauge à 1).
func is_in_combat() -> bool:
	var s := current_state_name()
	return s == STATE_ALERT or s == STATE_CHASE or s == STATE_ATTACK or s == STATE_RETREAT or s == STATE_STUNNED \
		or s == STATE_SKILL


## Évalue vue + ouïe, met à jour `can_see_player`, `last_seen_position` et la jauge.
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
	if not hidden and _last_los_clear and dist <= sight_r and (combat or is_in_vision_cone(ppos)) \
			and not SmokeField.blocks_line(global_position, ppos):
		can_see_player = true
		last_seen_position = ppos
		has_last_seen = true
		_unseen_time = 0.0
		gain += data.sight_gain * sight_distance_factor(dist, sight_r) * _player_speed_factor(p) * dt
		stimulus = true
	else:
		_unseen_time += dt
	var noise := _player_noise(p)
	if noise > 0.0 and dist < data.hearing_radius:
		var att := (1.0 - dist / data.hearing_radius) * (1.0 if _last_los_clear else hearing_wall_factor)
		var heard := noise * att
		if heard >= hearing_noise_floor:
			hears_player = true
			gain += data.hearing_gain * heard * dt
			if noise - _last_noise >= shot_noise_jump:
				gain += shot_awareness_bump * (1.0 - dist / data.hearing_radius) \
					* (1.0 if _last_los_clear else shot_wall_factor)
			stimulus = true
	_last_noise = noise
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


func sight_distance_factor(dist: float, radius: float) -> float:
	var t := clampf(1.0 - dist / maxf(radius, 1.0), 0.0, 1.0)
	return lerpf(sight_edge_mult, sight_near_mult, t * t)


func _player_speed_factor(p: Node2D) -> float:
	var v := Vector2.ZERO
	if p is CharacterBody2D:
		v = (p as CharacterBody2D).velocity
	var ref: Variant = p.get(&"move_speed")
	var max_speed: float = float(ref) if (ref is float or ref is int) else player_speed_default
	return lerpf(sight_still_mult, 1.0, clampf(v.length() / maxf(max_speed, 1.0), 0.0, 1.0))


func _is_player_hidden(p: Node2D) -> bool:
	return p.has_method(&"is_hidden") and bool(p.call(&"is_hidden"))


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


func get_awareness_tier() -> int:
	if is_in_combat() or awareness >= data.awareness_alert_threshold:
		return 2
	return 1 if awareness >= suspicion_threshold else 0


func _refresh_awareness_ui() -> void:
	var tier := get_awareness_tier()
	if tier != _tier:
		_tier = tier
		awareness_tier_changed.emit(tier)
		if _health_bar != null:
			_health_bar.queue_redraw()
	if _awareness_bar != null:
		_awareness_bar.set_value(awareness, not is_in_combat() and _alive)


func add_awareness(amount: float, pos: Vector2, propagate: bool = true) -> void:
	if not _alive or amount <= 0.0:
		return
	wake_up()
	_set_stimulus(pos)
	_apply_awareness(amount, 0.0, propagate)


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


func set_awareness(value: float) -> void:
	awareness = clampf(value, 0.0, 1.0)
	_refresh_awareness_ui()


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
	return has_line_between(global_position, to)


## Aucun obstacle de la couche world entre `from` et `to` (requête réutilisée).
func has_line_between(from: Vector2, to: Vector2) -> bool:
	if not is_inside_tree():
		return false
	_ray_query.from = from
	_ray_query.to = to
	return get_world_2d().direct_space_state.intersect_ray(_ray_query).is_empty()


func reveal_hidden_player() -> bool:
	var p := get_player()
	saw_player_hide = false
	if p == null or not _is_player_hidden(p) or not p.has_method(&"set_hidden"):
		return false
	p.call(&"set_hidden", false)
	return true


# --- Alerte des voisins et cris ------------------------------------------------------

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


func receive_alert(target_pos: Vector2) -> bool:
	if not _alive or is_in_combat():
		return false
	if can_see_player:
		become_aware(last_seen_position, false)
		return true
	add_awareness(neighbor_awareness_boost, target_pos, false)
	return true


## Cri bref (bulle) : limité par ennemi (shout_cooldown) et globalement (pas de cacophonie).
func shout(kind: StringName, force: bool = false) -> bool:
	if not _alive or (not force and _shout_left > 0.0):
		return false
	var now := Time.get_ticks_msec()
	if not force and now - _last_shout_msec < 450:
		return false
	var lines: Array = SHOUTS.get(kind, [])
	if lines.is_empty():
		return false
	_shout_left = shout_cooldown
	_last_shout_msec = now
	_visual_call(&"play_shout", [String(lines[randi() % lines.size()])])
	var am := get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", &"enemy_alert", global_position, -6.0)
	return true


# --- Déplacement -------------------------------------------------------------------

## Oriente le regard (et le sprite) vers `dir` ; prioritaire sur l'orientation par la vitesse.
func face(dir: Vector2) -> void:
	_faced_this_frame = true
	_apply_facing(dir)


func _apply_facing(dir: Vector2) -> void:
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
	desired_velocity = Vector2.ZERO
	direct_velocity = false


func is_at(pos: Vector2, tolerance: float = -1.0) -> bool:
	var tol := arrive_distance if tolerance < 0.0 else tolerance
	return global_position.distance_to(pos) <= tol


## Vitesse de course effective (difficulté, phase d'élite).
func run_speed() -> float:
	var s := data.move_speed * diff_speed_mult * rage_speed_mult * phase_speed_mult
	if phase >= 2:
		s *= data.phase2_speed_mult
	return s


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


## Fixe la vitesse souhaitée pour se diriger vers `target` (navigation ou steering).
func move_toward_position(target: Vector2, speed: float) -> void:
	desired_velocity = direction_toward(target) * speed
	direct_velocity = false
	if global_position.distance_squared_to(target) <= arrive_distance * arrive_distance:
		desired_velocity = Vector2.ZERO


## Direction (unitaire) à suivre pour atteindre `target` (chemin de navigation lissé, ou steering).
func direction_toward(target: Vector2) -> Vector2:
	var dir := Vector2.ZERO
	if is_navigation_available():
		var moved := nav_agent.target_position.distance_squared_to(target) > nav_repath_distance * nav_repath_distance
		if (moved and _repath_left <= 0.0) or (nav_agent.is_navigation_finished() and moved):
			nav_agent.target_position = target
			_repath_left = nav_repath_interval
		if not nav_agent.is_navigation_finished():
			dir = nav_agent.get_next_path_position() - global_position
	if dir.length_squared() < 1.0:
		dir = target - global_position
	return _avoid_obstacles(dir)


## Évitement des décors bloquants (caisses, chariots, rochers : absents de la navigation cuite)
## par moustaches, recalculé au plus 10×/s : entre deux calculs, la déviation est réappliquée.
func _avoid_obstacles(dir: Vector2) -> Vector2:
	if dir.length_squared() < 0.0001:
		return Vector2.ZERO
	var n := dir.normalized()
	var frame := Engine.get_physics_frames() + (get_instance_id() % 6)
	if frame % 6 == 0 or absf(n.angle_to(_avoid_ref)) > 0.5:
		_avoid_ref = n
		var steered := _steer_direct(n)
		_avoid_angle = n.angle_to(steered.normalized()) if steered.length_squared() > 0.0001 else 0.0
	return n.rotated(_avoid_angle)


## Se déplace selon une direction donnée (déjà lissée par l'appelant).
func move_in_direction(dir: Vector2, speed: float) -> void:
	direct_velocity = false
	desired_velocity = _steer_direct(dir).normalized() * speed if dir.length_squared() > 0.0001 else Vector2.ZERO


func move_away_from(from: Vector2, speed: float) -> void:
	var away := global_position - from
	if away.length_squared() < 1.0:
		away = -facing
	var dir := _steer_direct(away)
	desired_velocity = dir.normalized() * speed if dir.length_squared() > 0.0001 else Vector2.ZERO
	direct_velocity = false


## Ruée : vitesse appliquée directement (sans accélération ni séparation).
func dash(dir: Vector2, speed: float) -> void:
	desired_velocity = dir.normalized() * speed
	direct_velocity = true


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
	return dir.orthogonal()


func _ray_blocked(offset: Vector2) -> bool:
	_ray_query.from = global_position
	_ray_query.to = global_position + offset
	return not get_world_2d().direct_space_state.intersect_ray(_ray_query).is_empty()


# --- Tactique ----------------------------------------------------------------------

## Rang de flanquement parmi les ennemis éveillés en combat près du joueur → côté (-1, 0, +1).
func update_flank_side() -> int:
	if not data.can_flank:
		flank_side = 0
		return 0
	var p := get_player()
	if p == null:
		flank_side = 0
		return 0
	var my_id := get_instance_id()
	var count := 0
	var rank := 0
	var r2 := 900.0 * 900.0
	for n: Enemy in active_units:
		if not is_instance_valid(n) or not n._alive or not n.is_in_combat():
			continue
		if n.global_position.distance_squared_to(p.global_position) > r2:
			continue
		count += 1
		if n.get_instance_id() < my_id:
			rank += 1
	flank_side = EnemyTactics.flank_side(rank, count)
	return flank_side


## Cherche (au plus toutes les cover_search_interval s) un couvert entre soi et le joueur.
## Valide le choix par un raycast joueur → couvert bloqué. Renvoie vrai si un couvert est réservé.
func seek_cover(threat: Vector2, min_d: float, max_d: float) -> bool:
	if not data.use_cover:
		return false
	if cover_index >= 0 and _cover_still_valid(threat, min_d, max_d):
		return true
	if _cover_search_left > 0.0:
		return false
	_cover_search_left = cover_search_interval * randf_range(0.8, 1.2)
	var map := EnemyTactics.current_map()
	EnemyTactics.find_covers(map, global_position, threat, min_d, max_d, cover_max_travel, get_instance_id(),
		3, _cover_buf)
	# Validation physique (au plus 3 raycasts) : l'obstacle doit vraiment arrêter les balles.
	for idx: int in _cover_buf:
		var p := map.points[idx]
		if not has_line_between(threat, p):
			map.claim(idx, get_instance_id())
			cover_index = idx
			cover_position = p
			return true
	_release_cover()
	return false


func _cover_still_valid(threat: Vector2, min_d: float, max_d: float) -> bool:
	var d := cover_position.distance_to(threat)
	return d >= min_d * 0.8 and d <= max_d * 1.15


func _release_cover() -> void:
	if cover_index >= 0:
		var map := EnemyTactics.current_map()
		if map != null:
			map.release(get_instance_id())
	cover_index = -1


func has_cover() -> bool:
	return cover_index >= 0


## Doit battre en retraite (une fois, sous retreat_hp_ratio).
func should_retreat() -> bool:
	return not has_retreated and data.retreat_hp_ratio > 0.0 and hp <= max_hp * data.retreat_hp_ratio


## Position du joueur extrapolée de `t` secondes (vitesse courante, bornée).
func predict_player_position(t: float) -> Vector2:
	var p := get_player()
	if p == null:
		return last_seen_position
	var v := Vector2.ZERO
	if p is CharacterBody2D:
		v = (p as CharacterBody2D).velocity
	return p.global_position + v.limit_length(320.0) * t


# --- Combat ----------------------------------------------------------------------

func attack_ready() -> bool:
	return attack_cooldown_left <= 0.0


## Prochain schéma d'attaque (élite en phase 2 : alterne avec phase2_alt_pattern).
func next_pattern() -> StringName:
	_pattern_counter += 1
	if phase >= 2 and data.phase2_alt_pattern != &"" and _pattern_counter % 2 == 0:
		return data.phase2_alt_pattern
	if phase_pattern != &"":
		return phase_pattern
	return data.get_pattern()


## Durée du télégraphe effective.
func get_windup(pattern: StringName = &"") -> float:
	var w := data.attack_windup * diff_windup_mult
	if pattern == &"lob" and data.get_pattern() != &"lob":
		w = maxf(w, 0.55)
	if phase >= 2:
		w *= 0.85
	return w


## Portée à partir de laquelle l'attaque est lancée selon le schéma.
func attack_reach(pattern: StringName) -> float:
	match pattern:
		&"lunge":
			return data.attack_range + data.lunge_distance * 0.85
		&"lob":
			return maxf(data.attack_range, 320.0)
		&"slam":
			return maxf(data.attack_range, data.aoe_radius * 0.8)
	return data.attack_range


func get_attack_damage() -> float:
	return data.attack_damage * diff_damage_mult * phase_damage_mult


func _start_cooldown() -> void:
	var cd := data.attack_cooldown * diff_cooldown_mult * rage_cooldown_mult * phase_cooldown_mult
	if phase >= 2:
		cd *= data.phase2_cooldown_mult
	attack_cooldown_left = cd


## Multiplicateur des temps de recharge des compétences (difficulté, rage).
func skill_cooldown_mult() -> float:
	return diff_skill_cooldown_mult * rage_cooldown_mult * phase_cooldown_mult


## Exécute le coup à la fin du télégraphe (schéma simple, compatibilité). Renvoie vrai si un
## coup/tir est parti.
func perform_attack() -> bool:
	var p := get_player()
	if p == null:
		return false
	_start_cooldown()
	var pattern := data.get_pattern()
	if pattern == &"lob":
		return throw_explosive(predict_player_position(data.throw_flight_time * 0.5))
	if data.is_ranged():
		return fire_volley(p.global_position - global_position) > 0
	if data.is_area_attack():
		_visual_call(&"play_ground_slam", [data.aoe_radius])
		_fx_dust(global_position, 3)
		_play_sfx(data.get_sfx_attack())
		if global_position.distance_to(p.global_position) <= data.aoe_radius and p.has_method("take_damage"):
			p.call("take_damage", get_attack_damage(), self)
			return true
		return false
	return melee_strike(data.attack_range + melee_hit_tolerance)


## Un coup de mêlée : touche si le joueur est à moins de `reach`. Visuel de frappe.
func melee_strike(reach: float) -> bool:
	var p := get_player()
	_visual_call(&"play_strike", [facing, false])
	_play_sfx(data.get_sfx_attack())
	if p == null:
		return false
	if global_position.distance_to(p.global_position) <= reach and p.has_method("take_damage"):
		p.call("take_damage", get_attack_damage(), self)
		return true
	return false


## Tire une volée (un projectile, ou un éventail si projectile_count > 1) vers `aim`.
## Éclair de bouche, fumée, douille, recul. Renvoie le nombre de projectiles.
func fire_volley(aim: Vector2, speed_mult: float = 1.0) -> int:
	if not is_inside_tree():
		return 0
	var base := aim.normalized() if aim.length_squared() > 0.0001 else facing
	if data.aim_spread_deg > 0.0:
		base = base.rotated(deg_to_rad(randf_range(-data.aim_spread_deg, data.aim_spread_deg) * diff_spread_mult))
	var pool := EnemyProjectilePool.get_or_create(get_tree())
	if pool == null:
		return 0
	var muzzle := global_position + base * (data.body_radius + 6.0)
	var n := 0
	for shot_dir: Vector2 in get_shot_directions(base):
		var proj := pool.spawn(muzzle, shot_dir, data.projectile_speed * speed_mult, get_attack_damage(), self,
			data.projectile_lifetime, data.projectile_style)
		for sk: EnemySkill in skills:
			sk.on_fire(proj)
		n += 1
	face(base)
	var big := data.projectile_count > 1
	_visual_call(&"play_strike", [base, true, big])
	var fx := CombatFx.get_or_create(get_tree())
	if fx != null:
		var mz: Variant = _visual_call(&"get_muzzle_offset", [base])
		var mpos: Vector2 = global_position + (mz as Vector2 if mz is Vector2 else base * 20.0)
		fx.muzzle_smoke(mpos, base, 1.4 if big else 0.8)
		fx.shell(global_position + base * 8.0, 26.0, base, big)
	if big:
		_knock += -base * Balance.get_float("enemy_tactics", "shotgun_recoil_push", 110.0)
	_play_sfx(data.get_sfx_attack())
	return n


## Projectile de compétence (couteau lancé, éventail) : éclair de bouche, relais coop par le pool.
func fire_special(dir: Vector2, speed: float, damage: float, style: StringName, lifetime: float, smoke: bool = true) -> void:
	if not is_inside_tree():
		return
	var pool := EnemyProjectilePool.get_or_create(get_tree())
	if pool == null:
		return
	var d := dir.normalized()
	var proj := pool.spawn(global_position + d * (data.body_radius + 6.0), d, speed, damage, self, lifetime, style)
	for sk: EnemySkill in skills:
		sk.on_fire(proj)
	face(d)
	var gun := style != &"knife"
	_visual_call(&"play_strike", [d, gun, false])
	if gun and smoke:
		var fx := CombatFx.get_or_create(get_tree())
		if fx != null:
			fx.shell(global_position + d * 8.0, 26.0, d, false)
	_play_sfx(&"blade_swing" if not gun else data.get_sfx_attack())


## Dynamite de compétence (rebond facultatif : `bounce_to` ≠ INF). Relayée au coéquipier
## (visuel : un seul arc vers le point final).
func throw_dynamite_custom(from: Vector2, to: Vector2, radius: float, damage: float, flight: float, fuse: float,
		bounce_to: Vector2 = Vector2.INF, bounce_flight: float = 0.35) -> void:
	if not is_inside_tree():
		return
	var parent: Node = get_parent() if get_parent() != null else get_tree().current_scene
	var dyn := EnemyDynamite.throw(parent, from, to, radius, damage, flight, fuse, self)
	if bounce_to != Vector2.INF:
		dyn.set_bounce(bounce_to, bounce_flight)
	if NetHooks.active:
		var final_to := bounce_to if bounce_to != Vector2.INF else to
		var total := flight + (bounce_flight if bounce_to != Vector2.INF else 0.0)
		NetHooks.on_enemy_dynamite(from, final_to, radius, total, fuse)
	face(to - from)


## Danger au sol (EnemyHazard) créé par une compétence ; relayé au coéquipier (copie visuelle).
func spawn_hazard(kind: StringName, pos: Vector2, params: Dictionary) -> EnemyHazard:
	if not is_inside_tree():
		return null
	var parent: Node = get_parent() if get_parent() != null else get_tree().current_scene
	var h := EnemyHazard.spawn(parent, kind, pos, params, self, true)
	if NetHooks.active:
		NetHooks.on_enemy_visual(self, &"spawn_hazard", [kind, pos, params])
	return h


## Renfort appelé (sifflet du chef) : nouvel ennemi déjà alerté, enregistré pour le coop.
## Vrai pour un ennemi appelé en renfort (sifflet, appel, invocation) pendant le raid.
func is_reinforcement() -> bool:
	return has_meta(&"reinforcement")


func spawn_reinforcement(kind: StringName, pos: Vector2) -> Enemy:
	var path := "res://data/enemies/%s.tres" % kind
	if not is_inside_tree() or not ResourceLoader.exists(path):
		return null
	var d := (load(path) as EnemyData).duplicate() as EnemyData
	d.set_meta(&"variant_rolled", true)
	var r := Enemy.spawn(d)
	r.position = pos
	r.set_meta(&"reinforcement", true)
	if is_in_group(&"fog_hideable"):
		r.add_to_group(&"fog_hideable")
	get_parent().add_child(r)
	r.global_position = pos
	var target := get_player()
	r.become_aware(target.global_position if target != null else last_seen_position, false)
	if NetHooks.active:
		var id := NetHooks.register_dynamic_enemy(r)
		if id >= 0:
			NetHooks.on_enemy_visual(self, &"spawn_reinforcement", [kind, pos, id])
	return r


## Autodestruction (drone kamikaze).
func self_destruct() -> void:
	if _alive:
		invulnerable_left = 0.0
		take_damage(hp + max_hp, null)


## Fin d'une attaque de base : crochets des compétences (repositionnement du tireur…).
func notify_attack_done() -> void:
	for sk: EnemySkill in skills:
		sk.on_attack_done()


## Choisit et lance une compétence utilisable (priorité, puis hasard). `reactive_only` :
## seulement les compétences réactives (roulade). Renvoie vrai si une compétence démarre.
func try_use_skill(dist: float, sees: bool, reactive_only: bool = false) -> bool:
	if skills.is_empty() or state_machine == null or not _alive:
		return false
	if not reactive_only and _skill_gap_left > 0.0:
		return false
	var best: EnemySkill = null
	var best_score := -1.0
	for sk: EnemySkill in skills:
		if reactive_only != sk.is_reactive():
			continue
		if not sk.can_use(dist, sees):
			continue
		if randf() > sk.f("chance"):
			continue
		var score := sk.f("priority") + randf() * 0.5
		if score > best_score:
			best_score = score
			best = sk
	if best == null:
		return false
	_skill_gap_left = skill_gap
	state_machine.transition_to(STATE_SKILL, {"skill": best})
	return true


## Compétence par id (tests, debug).
func get_skill(sid: StringName) -> EnemySkill:
	for sk: EnemySkill in skills:
		if sk.id == sid:
			return sk
	return null


## Lance une compétence par démarrage forcé (tests). Ignore conditions et recharge.
func force_skill(sid: StringName) -> bool:
	var sk := get_skill(sid)
	if sk == null or sk.is_passive() or state_machine == null:
		return false
	sk.cooldown_left = 0.0
	state_machine.transition_to(STATE_SKILL, {"skill": sk})
	return true


## Lance un explosif vers `target` (borné à la portée). Renvoie vrai si lancé.
func throw_explosive(target: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var from := global_position
	var to := target
	var max_r := maxf(data.attack_range, 320.0)
	if from.distance_to(to) > max_r:
		to = from + (to - from).normalized() * max_r
	var parent: Node = get_parent() if get_parent() != null else get_tree().current_scene
	var dmg := (data.throw_damage if data.throw_damage > 0.0 else data.attack_damage) * diff_damage_mult
	var radius := data.throw_radius if data.throw_radius > 0.0 else 90.0
	EnemyDynamite.throw(parent, from + Vector2(0, -4), to, radius, dmg, data.throw_flight_time, data.throw_fuse, self)
	if NetHooks.active:
		NetHooks.on_enemy_dynamite(from + Vector2(0, -4), to, radius, data.throw_flight_time, data.throw_fuse)
	_play_sfx(&"blade_swing_heavy")
	_visual_call(&"play_strike", [to - from, false])
	face(to - from)
	return true


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


## Élite : passage en phase 2 (enragé) — cri, appel des alliés proches, plus rapide.
func enter_phase2() -> void:
	if phase >= 2:
		return
	phase = 2
	phase_changed.emit(phase)
	shout(&"phase2", true)
	_visual_call(&"play_alert")
	if is_inside_tree():
		var r2 := 700.0 * 700.0
		var p := get_player()
		var target := p.global_position if p != null else global_position
		for n: Enemy in active_units.duplicate():
			if n != self and is_instance_valid(n) and n._alive and global_position.distance_squared_to(n.global_position) <= r2:
				n.become_aware(target, false)


# --- Boss : phases ------------------------------------------------------------------

## Fraction de PV à laquelle commence la phase `i` (data.phases[i].from).
func boss_phase_from(i: int) -> float:
	if i < 0 or i >= data.phases.size() or not (data.phases[i] is Dictionary):
		return 1.0
	return float((data.phases[i] as Dictionary).get("from", 1.0))


func boss_phase_name(i: int = -1) -> String:
	var k := boss_phase if i < 0 else i
	if k < 0 or k >= data.phases.size() or not (data.phases[k] is Dictionary):
		return ""
	return str((data.phases[k] as Dictionary).get("name", "Phase %d" % (k + 1)))


## Passe à la phase la plus avancée atteinte par les PV (plusieurs d'un coup si gros dégâts).
func _check_boss_phase() -> void:
	if data.phases.is_empty() or not _alive:
		return
	var ratio := hp / maxf(max_hp, 0.001)
	var target := boss_phase
	for i in range(boss_phase + 1, data.phases.size()):
		if ratio <= boss_phase_from(i):
			target = i
	if target > boss_phase:
		_enter_boss_phase(target, true)


## Applique la phase `i` : compétences, multiplicateurs, schéma ; avec effets si `fx`.
func _enter_boss_phase(i: int, fx: bool) -> void:
	if data.phases.is_empty() or i < 0 or i >= data.phases.size():
		return
	boss_phase = i
	var ph: Dictionary = data.phases[i] if data.phases[i] is Dictionary else {}
	phase_speed_mult = float(ph.get("speed_mult", 1.0))
	phase_cooldown_mult = float(ph.get("cooldown_mult", 1.0))
	phase_damage_mult = float(ph.get("damage_mult", 1.0))
	phase_pattern = StringName(str(ph.get("attack_pattern", "")))
	if ph.has("skills") and ph["skills"] is Array:
		if active_skill != null and state_machine != null and current_state_name() == STATE_SKILL:
			state_machine.transition_to(STATE_CHASE)
		skills = EnemySkills.build_entries(self, ph["skills"], data.kind)
	if not fx:
		return
	phase_changed.emit(i + 1)
	var inv := float(ph.get("invuln", Balance.get_float("boss", "phase_invuln", 1.2)))
	invulnerable_left = maxf(invulnerable_left, inv)
	shout(&"phase2", true)
	_visual_call(&"play_alert")
	EventBus.boss_phase_changed.emit(self, i, boss_phase_name(i))
	# Compétences d'entrée de phase : la première est lancée, les autres sont prêtes.
	var first := true
	for sid: Variant in ph.get("on_enter", []):
		var sk := get_skill(StringName(str(sid)))
		if sk == null:
			continue
		sk.cooldown_left = 0.0
		if first and not sk.is_passive():
			first = false
			force_skill(sk.id)


# --- Modificateurs de carte (MapCard) -------------------------------------------------

func apply_modifiers(hp_mult: float, damage_mult: float, speed_mult: float, awareness_mult: float) -> void:
	if data == null or data.has_meta(&"map_modified"):
		return
	var ratio: float = clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	var d := data.duplicate() as EnemyData
	d.max_hp = data.max_hp * maxf(hp_mult, 0.05)
	d.attack_damage = data.attack_damage * maxf(damage_mult, 0.0)
	d.move_speed = data.move_speed * maxf(speed_mult, 0.05)
	d.sight_gain = data.sight_gain * maxf(awareness_mult, 0.0)
	d.hearing_gain = data.hearing_gain * maxf(awareness_mult, 0.0)
	d.set_meta(&"map_modified", true)
	if data.has_meta(&"variant_rolled"):
		d.set_meta(&"variant_rolled", true)
	data = d
	max_hp = d.max_hp * boss_hp_scale()
	hp = max_hp * ratio
	if _health_bar != null:
		_health_bar.queue_redraw()


## Change d'archétype (variante d'apparition, garde d'élite) : données, corps, visuel, PV pleins.
func set_variant(new_data: EnemyData) -> void:
	if new_data == null:
		return
	var d := new_data.duplicate() as EnemyData
	d.set_meta(&"variant_rolled", true)
	data = d
	max_hp = d.max_hp * boss_hp_scale()
	hp = max_hp
	if not is_inside_tree():
		return
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs != null and cs.shape is CircleShape2D:
		(cs.shape as CircleShape2D).radius = d.body_radius
	nav_agent.radius = d.body_radius
	if visual != null and visual.has_method("setup"):
		visual.call("setup", d.kind)
	_configure_visual_telegraphs()
	skills = EnemySkills.build(self, d)
	_visual_call(&"set_elite", [d.elite])
	_visual_call(&"set_facing", [facing])
	if _awareness_bar != null:
		_awareness_bar.setup(get_head_offset() + Vector2(0, -10.0 - 4.0 - 22.0), suspicion_threshold)
	if _health_bar != null:
		_health_bar.queue_redraw()


# --- Interface de dégâts ------------------------------------------------------------

func take_damage(amount: float, source: Node) -> void:
	if not _alive or amount <= 0.0 or net_puppet:
		return
	if invulnerable_left > 0.0 and source != null:
		return
	for sk: EnemySkill in skills:
		amount = sk.modify_damage(amount, source)
	if amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	for sk2: EnemySkill in skills:
		sk2.on_damaged(amount)
	damaged.emit(amount, hp)
	if _health_bar != null:
		_health_bar.queue_redraw()
	if hp <= 0.0:
		_visual_call(&"flash_hit")
		_die()
		return
	_visual_call(&"play_hit")
	var now := Time.get_ticks_msec()
	if now - _hurt_sfx_msec > 350:
		_hurt_sfx_msec = now
		_play_sfx(data.get_sfx_hurt())
	# Aucun recul au coup par défaut ([enemy_tactics] hit_knockback_mult = 0 : retour testeur) ;
	# le flash, l'animation « hit » sur place et l'étourdissement immobile restent.
	var from := global_position
	var p := get_player()
	if source is Node2D and is_instance_valid(source):
		from = (source as Node2D).global_position
	elif p != null:
		from = p.global_position
	var push_dir := global_position - from
	var kb_mult := hit_knockback_mult()
	if push_dir.length_squared() > 1.0 and data.knockback > 0.0 and kb_mult > 0.0:
		_knock += push_dir.normalized() * data.knockback * kb_mult * clampf(amount / maxf(max_hp * 0.2, 1.0), 0.4, 1.6)
	# Élite : phase 2.
	if data.elite and data.phase2_hp_ratio > 0.0 and phase < 2 and hp <= max_hp * data.phase2_hp_ratio:
		enter_phase2()
	# Boss : phases successives (data.phases[i].from).
	if data.boss:
		_check_boss_phase()
	# Être touché = jauge à 1 : alerte vers la source si hors combat.
	if not is_in_combat():
		become_aware(from, true)
	elif data.stagger_ratio > 0.0 and amount >= max_hp * data.stagger_ratio \
			and current_state_name() != STATE_STUNNED and state_machine != null:
		state_machine.transition_to(STATE_STUNNED, {"time": data.stagger_time})


## Multiplicateur du recul imprimé par un coup reçu (balles, plombs, explosions). 0 = aucun.
static func hit_knockback_mult() -> float:
	return maxf(Balance.get_float("enemy_tactics", "hit_knockback_mult", 0.0), 0.0)


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
	desired_velocity = Vector2.ZERO
	_knock = Vector2.ZERO
	wake_up()  # L'animation de mort doit se jouer.
	_register_active(false)
	_release_cover()
	if _sleep_timer != null:
		_sleep_timer.stop()
	if _awareness_bar != null:
		_awareness_bar.set_value(0.0, false)
	remove_from_group(GROUP_ENEMIES)
	remove_from_group(GROUP_DAMAGEABLE)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	for child: Node in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
	if _health_bar != null:
		_health_bar.visible = false
	_visual_call(&"hide_telegraphs")
	_play_sfx(data.get_sfx_death())
	state_machine.transition_to(STATE_DEAD)
	died.emit(self)
	EventBus.enemy_died.emit(self, global_position)
	if data.boss:
		EventBus.boss_defeated.emit(self)


## Fin de l'animation de mort : le cadavre persistant remplace l'ennemi (LootManager), puis
## l'ennemi est libéré.
func finalize_death() -> void:
	if _alive or is_queued_for_deletion():
		return
	if not corpse_placed:
		corpse_placed = true
		var lm := get_node_or_null(^"/root/LootManager")
		if lm != null and lm.has_method("place_corpse"):
			lm.call("place_corpse", self)
	queue_free()


func _on_death_finished() -> void:
	finalize_death()


# --- Visuel ------------------------------------------------------------------------

func _visual_call(method: StringName, args: Array = []) -> Variant:
	if NetHooks.active:
		NetHooks.on_enemy_visual(self, method, args)  # Hôte : animation relayée au coéquipier.
	if visual != null and is_instance_valid(visual) and visual.has_method(method):
		return visual.callv(method, args)
	return null


func _fx_dust(pos: Vector2, count: int) -> void:
	var fx := CombatFx.get_or_create(get_tree()) if is_inside_tree() else null
	if fx == null:
		return
	for i: int in count:
		fx.dust_puff(pos + Vector2(randf_range(-14, 14), randf_range(-4, 4)), Vector2(randf_range(-30, 30), -12.0), 6.0, 0.4)


func _play_sfx(sfx: StringName) -> void:
	var am := get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, global_position, -4.0)


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
		"tactic": String(data.get_tactic()),
		"hp": hp,
		"max_hp": max_hp,
		"sees_player": can_see_player,
		"hears_player": hears_player,
		"awareness": awareness,
		"asleep": asleep,
		"cooldown": attack_cooldown_left,
		"cover": cover_index,
		"flank": flank_side,
		"phase": phase,
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
	canvas.draw_arc(pos, data.hearing_radius, 0.0, TAU, 48, Color(0.6, 0.75, 1.0, 0.35 if hears_player else 0.18), 1.5 if hears_player else 1.0, true)
	canvas.draw_arc(pos, data.attack_range, 0.0, TAU, 40, Color(1.0, 0.2, 0.2, 0.7), 1.5, true)
	var p := get_player()
	if p != null and _alive and pos.distance_to(p.global_position) <= radius:
		var clear := _last_los_clear
		canvas.draw_line(pos, p.global_position, Color(0.2, 1.0, 0.3, 0.8) if clear else Color(1.0, 0.15, 0.15, 0.8), 2.0, true)
	if has_last_seen and (state == STATE_CHASE or state == STATE_ALERT or state == STATE_SEARCH):
		canvas.draw_circle(last_seen_position, 6.0, Color(1.0, 0.55, 0.1, 0.9))
	if state == STATE_INVESTIGATE:
		canvas.draw_circle(stimulus_position, 6.0, Color(1.0, 0.9, 0.3, 0.9))
		canvas.draw_line(pos, stimulus_position, Color(1.0, 0.9, 0.3, 0.35), 1.0, true)
	if cover_index >= 0:
		canvas.draw_rect(Rect2(cover_position - Vector2(10, 10), Vector2(20, 20)), Color(0.3, 0.8, 1.0, 0.9), false, 2.0)
		canvas.draw_line(pos, cover_position, Color(0.3, 0.8, 1.0, 0.5), 1.0, true)
	if desired_velocity.length_squared() > 1.0:
		canvas.draw_line(pos, pos + desired_velocity * 0.4, Color(1, 1, 1, 0.7), 2.0, true)
	canvas.draw_arc(spawn_position, data.patrol_radius, 0.0, TAU, 32, Color(0.3, 0.95, 0.35, 0.25), 1.0, true)
	var font := ThemeDB.fallback_font
	var label := "%s %s %d%%%s%s%s%s" % [String(state), String(data.get_tactic()), roundi(awareness * 100.0),
		" vu" if can_see_player else "", " entendu" if hears_player else "", " zzz" if asleep else "",
		(" flanc%+d" % flank_side) if flank_side != 0 else ""]
	var head := pos + get_head_offset() + Vector2(-40, -26)
	canvas.draw_string_outline(font, head, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0.07, 0.1, 0.18))
	canvas.draw_string(font, head, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)


## Barre de vie discrète au-dessus de la tête : visible seulement en combat ou blessé ;
## dorée pour l'élite. Redessinée uniquement sur changement (PV, palier, état).
class HealthBar extends Node2D:
	var enemy: Enemy = null

	func _draw() -> void:
		if enemy == null or not enemy.is_alive():
			return
		var hurt := enemy.hp < enemy.max_hp - 0.01
		if not hurt and not enemy.is_in_combat() and not enemy.data.elite:
			return
		var w: float = enemy.health_bar_width * (1.35 if enemy.data.elite else 1.0)
		var h := 4.0 if not enemy.data.elite else 5.0
		var head: Vector2 = enemy.get_head_offset() + Vector2(0, -8)
		var bar := Rect2(head - Vector2(w * 0.5, h), Vector2(w, h))
		var ratio := clampf(enemy.hp / maxf(enemy.max_hp, 0.01), 0.0, 1.0)
		draw_rect(bar.grow(1.5), Color(0.07, 0.10, 0.18, 0.78))
		draw_rect(bar, Color(0.25, 0.05, 0.07, 0.85))
		var fill := Color(0.92, 0.22, 0.16).lerp(Color(0.95, 0.5, 0.18), 1.0 - ratio)
		draw_rect(Rect2(bar.position, Vector2(w * ratio, h)), fill)
		if enemy.data.elite:
			draw_rect(bar.grow(1.5), Color(1.0, 0.78, 0.3, 0.95), false, 1.2)


## Visuel de repli (cercle) si res://scripts/enemies/enemy_visual.gd n'existe pas.
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
			&"fw_bruiser":
				radius = 28.0
				color = Color(0.55, 0.18, 0.16)
			&"fw_sharpshooter":
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

	func play_attack_windup(duration: float, _special: bool = true) -> void:
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
