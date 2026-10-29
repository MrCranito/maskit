class_name GadgetDrone
extends Node2D
## Drone allié : vole en orbite autour du joueur, tire sur l'ennemi visible (non caché par
## le brouillard, ligne de vue sans mur) le plus proche dans effect_radius, pendant
## effect_duration, puis s'éloigne en montant et disparaît. Ne bloque rien (aucune
## collision). Ciblage espacé ([gadgets] drone_retarget, une requête de vue par cible).
## Hélices : deux images alternées (aucun redessin par frame), son « hélice » espacé.

const MASK_WORLD := 1

var owner_player: Node2D = null
var weapon: WeaponData = null
var radius: float = 300.0
var duration: float = 15.0
var age: float = 0.0
var target: Node2D = null
var shots_fired: int = 0
var leaving: bool = false
## Coop : drone du coéquipier affiché sans tirer (ses tirs arrivent par le réseau).
var net_visual_only: bool = false

var _orbit_r: float = 46.0
var _orbit_speed: float = 1.6
var _height: float = 52.0
var _fire_interval: float = 0.4
var _damage: float = 8.0
var _fire_left: float = 0.5
var _retarget_left: float = 0.0
var _retarget: float = 0.25
var _leave_t: float = 0.0
var _phase: float = 0.0
var _body: Node2D = null
var _rotor_a: Node2D = null
var _rotor_b: Node2D = null
var _shadow: Node2D = null
var _query: PhysicsRayQueryParameters2D = null
var _tex: Texture2D = null
var _buzz_left: float = 0.0
var _proj: WeaponData = null


static func spawn(parent: Node, player: Node2D, w: WeaponData) -> GadgetDrone:
	var d := GadgetDrone.new()
	d.owner_player = player
	d.weapon = w
	d.radius = w.effect_radius if w.effect_radius > 0.0 else 300.0
	d.duration = w.effect_duration if w.effect_duration > 0.0 else 15.0
	parent.add_child(d)
	d.global_position = player.global_position
	return d


func _init() -> void:
	z_as_relative = false
	z_index = 35
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	_orbit_r = Balance.get_float("gadgets", "drone_orbit_radius", 46.0)
	_orbit_speed = Balance.get_float("gadgets", "drone_orbit_speed", 1.6)
	_height = Balance.get_float("gadgets", "drone_height", 52.0)
	_retarget = Balance.get_float("gadgets", "drone_retarget", 0.25)
	_fire_interval = 1.0 / maxf(weapon.fire_rate if weapon != null and weapon.fire_rate > 0.0 else 2.5, 0.1)
	_damage = weapon.damage if weapon != null and weapon.damage > 0.0 else 8.0
	_query = PhysicsRayQueryParameters2D.create(Vector2.ZERO, Vector2.ZERO, MASK_WORLD)
	_query.collide_with_areas = false
	if weapon != null:
		var p: String = "res://assets/sprites/weapons/" + String(weapon.id) + "_world.png"
		if ResourceLoader.exists(p):
			_tex = load(p) as Texture2D
	# Arme virtuelle du drone (balle légère) pour le pool de projectiles.
	_proj = WeaponData.new()
	_proj.damage = _damage
	_proj.projectile_speed = Balance.get_float("gadgets", "drone_bullet_speed", 900.0)
	_proj.range = radius * 1.3
	_proj.projectile_lifetime = radius * 1.3 / _proj.projectile_speed
	_proj.projectile_color = Color(0.45, 0.85, 1.0)
	_proj.projectile_style = &"bullet"
	_shadow = Node2D.new()
	_shadow.draw.connect(func() -> void:
		_shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
		_shadow.draw_circle(Vector2.ZERO, 9.0, Color(0.05, 0.07, 0.15, 0.35)))
	add_child(_shadow)
	_body = Node2D.new()
	_body.draw.connect(_draw_body)
	add_child(_body)
	_rotor_a = _make_rotor(0)
	_rotor_b = _make_rotor(1)
	_rotor_b.visible = false


func _make_rotor(frame: int) -> Node2D:
	var r := Node2D.new()
	r.draw.connect(func() -> void:
		for p: Vector2 in [Vector2(-10, -7), Vector2(10, 7), Vector2(-10, 7), Vector2(10, -7)]:
			var a: float = 0.0 if frame == 0 else PI * 0.5
			r.draw_line(p + Vector2(6, 0).rotated(a), p - Vector2(6, 0).rotated(a), Color(0.85, 0.9, 1.0, 0.6), 1.5, true)
			r.draw_circle(p, 5.5, Color(0.75, 0.9, 1.0, 0.18), true, -1.0, true))
	_body.add_child(r)
	return r


## Logique pure : ennemi vivant et visible le plus proche de `from` dans `r`.
## `los` (Callable(from, to) -> bool) filtre la ligne de vue ; vide = pas de filtre.
static func pick_target(candidates: Array, from: Vector2, r: float, los: Callable = Callable()) -> Node2D:
	var best: Node2D = null
	var best_d: float = r * r
	for e: Variant in candidates:
		var n := e as Node2D
		if n == null or not n.is_visible_in_tree():
			continue
		if n.has_method("is_alive") and not bool(n.call("is_alive")):
			continue
		var d2: float = from.distance_squared_to(n.global_position)
		if d2 > best_d:
			continue
		if los.is_valid() and not bool(los.call(from, n.global_position)):
			continue
		best_d = d2
		best = n
	return best


func _los(a: Vector2, b: Vector2) -> bool:
	if not is_inside_tree():
		return true
	_query.from = a
	_query.to = b
	return get_world_2d().direct_space_state.intersect_ray(_query).is_empty()


## Avance le temps (public pour les tests).
func advance(delta: float) -> void:
	age += delta
	_phase += delta * _orbit_speed
	var flip: bool = fmod(age * 30.0, 1.0) < 0.5
	if _rotor_a.visible != flip:
		_rotor_a.visible = flip
		_rotor_b.visible = not flip
	if leaving or age >= duration or not is_instance_valid(owner_player):
		leaving = true
		_leave_t += delta
		_body.position.y -= 90.0 * delta
		modulate.a = clampf(1.0 - _leave_t / 0.8, 0.0, 1.0)
		if _leave_t >= 0.8:
			queue_free()
		return
	var center: Vector2 = owner_player.global_position
	var want: Vector2 = center + Vector2(cos(_phase), sin(_phase) * 0.6) * _orbit_r
	global_position = global_position.lerp(want, 1.0 - exp(-6.0 * delta))
	_body.position = Vector2(0.0, -_height + sin(age * 3.0) * 3.0)
	_retarget_left -= delta
	if _retarget_left <= 0.0:
		_retarget_left = _retarget
		target = pick_target(get_tree().get_nodes_in_group(&"enemies"), global_position, radius, _los)
	_fire_left -= delta
	if target != null and is_instance_valid(target) and _fire_left <= 0.0:
		_fire_left = _fire_interval
		_shoot()
	_buzz_left -= delta
	if _buzz_left <= 0.0:
		_buzz_left = 1.4
		# Bruit d'hélices : son dédié s'il existe dans AudioManager (« drone_buzz »).
		var am: Node = get_node_or_null(^"/root/AudioManager")
		if am != null and am.has_method("has_sfx") and bool(am.call("has_sfx", &"drone_buzz")):
			am.call("play_sfx", &"drone_buzz", global_position, -14.0)


func _process(delta: float) -> void:
	advance(delta)


func _shoot() -> void:
	if net_visual_only:
		return
	shots_fired += 1
	var dir: Vector2 = (target.global_position - global_position).normalized()
	var pool: Node = owner_player.get("projectile_pool") if is_instance_valid(owner_player) else null
	if pool != null and pool.has_method("spawn"):
		pool.call("spawn", global_position, dir, _proj, owner_player, _height)
	var am: Node = get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", &"pistol_shot_light", global_position, -10.0)


func _draw_body() -> void:
	if _tex != null:
		var sz := Vector2(_tex.get_size())
		var sc: float = 30.0 / maxf(sz.x, 1.0)
		_body.draw_set_transform(Vector2.ZERO, 0.0, Vector2(sc, sc))
		_body.draw_texture(_tex, -sz * 0.5)
		_body.draw_set_transform(Vector2.ZERO)
		return
	var dark := Color(0.12, 0.13, 0.16)
	_body.draw_line(Vector2(-10, -7), Vector2(10, 7), dark, 2.5)
	_body.draw_line(Vector2(-10, 7), Vector2(10, -7), dark, 2.5)
	_body.draw_rect(Rect2(-6, -4, 12, 8), Color(0.24, 0.26, 0.3))
	_body.draw_rect(Rect2(-6, -4, 12, 8), dark, false, 1.2)
	_body.draw_circle(Vector2(3, 0), 2.0, Color(0.4, 0.85, 1.0), true, -1.0, true)
