class_name Enemy
extends CharacterBody2D
## Ennemi générique piloté par une StateMachine (Patrol → Alert → Chase → Attack → Return, Dead).
## Toutes les valeurs propres à l'ennemi viennent de `data` (EnemyData, data/enemies/*.tres) ;
## les réglages globaux de l'IA viennent de balance.cfg [enemy_ai].
##
## Perception :
##  - hors combat (Patrol/Return) : le joueur doit être dans l'Area2D de détection
##    (cercle de detection_radius), dans le cône de vision si detection_angle_deg < 360,
##    et en ligne de vue (raycast contre la couche world) ;
##  - en combat (Alert/Chase/Attack) : cône ignoré, portée = detection_radius × chase_sight_multiplier,
##    ligne de vue toujours requise.
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
const STATE_ALERT := &"Alert"
const STATE_CHASE := &"Chase"
const STATE_ATTACK := &"Attack"
const STATE_RETURN := &"Return"
const STATE_DEAD := &"Dead"

const STATE_SCRIPTS: Array[Script] = [
	preload("res://scripts/ai/enemy_states/enemy_patrol_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_alert_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_chase_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_attack_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_return_state.gd"),
	preload("res://scripts/ai/enemy_states/enemy_dead_state.gd"),
]

## Couleurs debug par état (F3).
const DEBUG_STATE_COLORS := {
	STATE_PATROL: Color(0.3, 0.95, 0.35),
	STATE_ALERT: Color(1.0, 0.9, 0.2),
	STATE_CHASE: Color(1.0, 0.55, 0.1),
	STATE_ATTACK: Color(1.0, 0.15, 0.15),
	STATE_RETURN: Color(0.3, 0.6, 1.0),
	STATE_DEAD: Color(0.5, 0.5, 0.5),
}

signal damaged(amount: float, current_hp: float)
signal died(enemy: Enemy)

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
var detection_area: Area2D = null

## Résultat de la dernière perception.
var can_see_player: bool = false
var last_seen_position: Vector2 = Vector2.ZERO
var has_last_seen: bool = false
## Délai restant avant la prochaine attaque possible.
var attack_cooldown_left: float = 0.0

# Réglages globaux [enemy_ai]
var los_check_interval: float = 0.1
var chase_sight_multiplier: float = 1.5
var arrive_distance: float = 12.0
var whisker_length: float = 48.0
var whisker_angle: float = deg_to_rad(35.0)
var nav_repath_distance: float = 24.0
var death_free_fallback: float = 2.0
var health_bar_width: float = 56.0

var _alive: bool = true
var _player: Node2D = null
var _player_in_area: bool = false
var _perception_left: float = 0.0
var _health_bar: Node2D = null
var _debug_registered: bool = false
var _last_los_clear: bool = false


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

	add_to_group(GROUP_UNITS)
	add_to_group(GROUP_ENEMIES)
	add_to_group(GROUP_DAMAGEABLE)
	collision_layer = LAYER_ENEMIES
	collision_mask = MASK_WORLD | MASK_PLAYER | LAYER_ENEMIES
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	_build_body_shape()
	_build_detection_area()
	_build_nav_agent()
	_build_visual()
	_build_health_bar()
	_build_state_machine()
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


func _build_detection_area() -> void:
	detection_area = Area2D.new()
	detection_area.name = "DetectionArea"
	detection_area.collision_layer = 0
	detection_area.collision_mask = MASK_PLAYER
	detection_area.monitorable = false
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = data.detection_radius
	cs.shape = circle
	detection_area.add_child(cs)
	add_child(detection_area)
	detection_area.body_entered.connect(_on_detection_body_entered)
	detection_area.body_exited.connect(_on_detection_body_exited)


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
	if _alive:
		_perception_left -= delta
		if _perception_left <= 0.0:
			_perception_left = los_check_interval
			update_perception()
	state_machine.physics_update(delta)
	if _alive:
		move_and_slide()
		var moving := velocity.length_squared() > 4.0
		if moving:
			face(velocity)
		_visual_call(&"set_moving", [moving])
	else:
		velocity = Vector2.ZERO


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


## Met à jour `can_see_player` et `last_seen_position` (appelé à intervalle régulier).
func update_perception() -> bool:
	can_see_player = false
	_last_los_clear = false
	var p := get_player()
	if p == null or not _alive:
		return false
	var to_player: Vector2 = p.global_position - global_position
	if is_in_combat():
		var reach := data.detection_radius * chase_sight_multiplier
		if to_player.length() > reach:
			return false
	else:
		if not (_player_in_area or _is_overlapping_player(p)):
			return false
		if not is_in_vision_cone(p.global_position):
			return false
	_last_los_clear = has_line_of_sight_to(p.global_position)
	can_see_player = _last_los_clear
	if can_see_player:
		last_seen_position = p.global_position
		has_last_seen = true
	return can_see_player


func _is_overlapping_player(p: Node2D) -> bool:
	# Filet de sécurité si le signal body_entered n'est pas encore arrivé.
	return global_position.distance_to(p.global_position) <= data.detection_radius


## Le point est-il dans le cône de vision (toujours vrai si angle >= 360) ?
func is_in_vision_cone(pos: Vector2) -> bool:
	if data.detection_angle_deg >= 360.0:
		return true
	var to := pos - global_position
	if to.length_squared() < 1.0:
		return true
	var half := deg_to_rad(data.detection_angle_deg) * 0.5
	return absf(facing.angle_to(to)) <= half


## Aucun obstacle de la couche world entre l'ennemi et `to`.
func has_line_of_sight_to(to: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, to, MASK_WORLD, [get_rid()])
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


func _on_detection_body_entered(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player_in_area = true
		_player = body


func _on_detection_body_exited(body: Node2D) -> void:
	if body.is_in_group(&"player"):
		_player_in_area = false


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


## Alerte reçue d'un voisin : passe en Alert si l'ennemi est hors combat (pas de propagation).
func receive_alert(target_pos: Vector2) -> bool:
	if not _alive or is_in_combat():
		return false
	last_seen_position = target_pos
	has_last_seen = true
	state_machine.transition_to(STATE_ALERT, {"target_pos": target_pos, "propagate": false})
	return true


# --- Déplacement -------------------------------------------------------------------

## Oriente le regard (et le sprite) vers `dir`.
func face(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		return
	facing = dir.normalized()
	_visual_call(&"set_facing", [facing])


func face_position(pos: Vector2) -> void:
	face(pos - global_position)


func stop() -> void:
	velocity = Vector2.ZERO


func is_at(pos: Vector2, tolerance: float = -1.0) -> bool:
	var tol := arrive_distance if tolerance < 0.0 else tolerance
	return global_position.distance_to(pos) <= tol


## Navigation disponible : la carte du monde contient au moins une région synchronisée.
func is_navigation_available() -> bool:
	if not is_inside_tree():
		return false
	var map := get_world_2d().navigation_map
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return false
	return not NavigationServer2D.map_get_regions(map).is_empty()


## Fixe la vélocité pour se diriger vers `target` à `speed` (navigation ou steering).
func move_toward_position(target: Vector2, speed: float) -> void:
	var dir := Vector2.ZERO
	if is_navigation_available():
		if nav_agent.target_position.distance_to(target) > nav_repath_distance or nav_agent.is_navigation_finished():
			nav_agent.target_position = target
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
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + offset, MASK_WORLD, [get_rid()])
	return not space.intersect_ray(query).is_empty()


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
	# Être touché déclenche l'alerte (vers la source si connue, sinon vers le joueur).
	if not is_in_combat():
		var pos := global_position
		var p := get_player()
		if source is Node2D and is_instance_valid(source):
			pos = (source as Node2D).global_position
		elif p != null:
			pos = p.global_position
		last_seen_position = pos
		has_last_seen = true
		state_machine.transition_to(STATE_ALERT, {"target_pos": pos, "propagate": true})


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
	# Retiré immédiatement des cibles ; reste dans enemy_units jusqu'à sa libération.
	remove_from_group(GROUP_ENEMIES)
	remove_from_group(GROUP_DAMAGEABLE)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	for child: Node in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
	if detection_area != null:
		detection_area.set_deferred("monitoring", false)
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
	# Portée d'attaque.
	canvas.draw_arc(pos, data.attack_range, 0.0, TAU, 40, Color(1.0, 0.2, 0.2, 0.7), 1.5, true)
	# Ligne de vue vers le joueur (si à portée de perception).
	var p := get_player()
	if p != null and _alive and pos.distance_to(p.global_position) <= radius:
		var clear := has_line_of_sight_to(p.global_position)
		canvas.draw_line(pos, p.global_position, Color(0.2, 1.0, 0.3, 0.8) if clear else Color(1.0, 0.15, 0.15, 0.8), 2.0, true)
	# Dernière position connue.
	if has_last_seen and (state == STATE_CHASE or state == STATE_ALERT):
		canvas.draw_circle(last_seen_position, 6.0, Color(1.0, 0.55, 0.1, 0.9))
	# Point d'apparition / patrouille.
	canvas.draw_arc(spawn_position, data.patrol_radius, 0.0, TAU, 32, Color(0.3, 0.95, 0.35, 0.25), 1.0, true)
	# Nom de l'état au-dessus de la tête.
	var font := ThemeDB.fallback_font
	var label := "%s %s" % [String(state), "(vu)" if can_see_player else ""]
	var head := pos + get_head_offset() + Vector2(-40, -26)
	canvas.draw_string_outline(font, head, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0.07, 0.1, 0.18))
	canvas.draw_string(font, head, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)


## Barre de vie au-dessus de la tête (enfant dessiné après le visuel).
class HealthBar extends Node2D:
	var enemy: Enemy = null

	func _process(_delta: float) -> void:
		queue_redraw()

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
