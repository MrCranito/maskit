class_name GadgetDevice
extends Node2D
## Objet d'équipement lancé ou posé (grenade frag, fumigène, mine, C4, leurre).
##   frag  : lancé en arc (hauteur z simulée, ombre au sol, rebonds sol/murs), explose
##           après fuse_time (réutilise CombatFx.explode).
##   smoke : lancé comme la frag ; à l'arrêt (ou après fuse_time) libère un SmokeField.
##   mine  : posée devant le joueur ; s'arme après fuse_time (voyant + bip), puis explose
##           dès qu'un ennemi vivant entre dans effect_radius (test toutes les 0,1 s).
##   c4    : posé ; explose quand `detonate()` est appelé (2e appui du joueur).
## Sprite au sol : assets/sprites/weapons/<id>_world.png, sinon dessin de repli.
## Mouvement : affectations par frame ; redessin du voyant uniquement quand il change.

signal exploded(device: GadgetDevice)

const MASK_WORLD := 1
const WORLD_SPRITE_DIR := "res://assets/sprites/weapons/"

var kind: StringName = &"frag"
var weapon: WeaponData = null
var source: Node = null
## Hauteur au-dessus du sol (px) et vitesse verticale.
var z: float = 0.0
var vz: float = 0.0
var velocity: Vector2 = Vector2.ZERO
var fuse_left: float = 0.0
var armed: bool = false
var detonated: bool = false
## Vrai si la case courante est en gravité faible (fourni par le joueur au lancer).
var low_gravity: bool = false

var _body: Node2D = null
var _shadow: Node2D = null
var _light_on: bool = false
var _blink_t: float = 0.0
var _check_left: float = 0.0
var _gravity: float = 1100.0
var _bounce: float = 0.4
var _friction: float = 0.6
var _mine_check: float = 0.1
var _beep_left: float = 0.0
var _tex: Texture2D = null


## Lance (frag, smoke) ou pose (mine, c4) un objet. `target` = point d'arrivée au sol.
static func throw_device(parent: Node, w: WeaponData, from_ground: Vector2, height: float,
		target: Vector2, src: Node, low_g: bool = false) -> GadgetDevice:
	var d := GadgetDevice.new()
	d.weapon = w
	d.kind = w.gadget_kind if not String(w.gadget_kind).is_empty() else &"frag"
	d.source = src
	d.low_gravity = low_g
	parent.add_child(d)
	d.global_position = from_ground
	d.z = height
	d._launch_toward(target)
	return d


## Logique pure : temps de vol et vitesse verticale pour atteindre le sol à `dist`
## avec la vitesse horizontale `speed` depuis la hauteur `h` (gravité `g`).
static func arc_vz(dist: float, speed: float, h: float, g: float) -> float:
	var t: float = maxf(dist / maxf(speed, 1.0), 0.05)
	# h + vz t - g t² / 2 = 0
	return (0.5 * g * t * t - h) / t


func _init() -> void:
	z_as_relative = false
	z_index = 12
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	_gravity = Balance.get_float("gadgets", "throw_gravity", 1100.0)
	_bounce = Balance.get_float("gadgets", "throw_bounce", 0.4)
	_friction = Balance.get_float("gadgets", "throw_friction", 0.6)
	_mine_check = Balance.get_float("gadgets", "mine_check_interval", 0.1)
	if low_gravity:
		_gravity *= Balance.get_float("low_gravity", "throw_gravity_mult", 0.35)
	if weapon != null:
		var p: String = WORLD_SPRITE_DIR + String(weapon.id) + "_world.png"
		if ResourceLoader.exists(p):
			_tex = load(p) as Texture2D
	_shadow = Node2D.new()
	_shadow.name = "Shadow"
	_shadow.draw.connect(_draw_shadow)
	add_child(_shadow)
	_body = Node2D.new()
	_body.name = "Body"
	_body.draw.connect(_draw_body)
	add_child(_body)
	_place_body()


func _launch_toward(target: Vector2) -> void:
	var to: Vector2 = target - global_position
	var dist: float = to.length()
	var dir: Vector2 = to / dist if dist > 0.01 else Vector2.RIGHT
	fuse_left = weapon.fuse_time if weapon != null else 2.0
	if kind == &"mine" or kind == &"c4":
		# Pose : petit glissement jusqu'à la cible, au sol.
		z = 0.0
		vz = 0.0
		velocity = dir * minf(dist * 4.0, 360.0)
		return
	# La frag explose en vol si la mèche est plus courte que le trajet : on vise un
	# atterrissage avant la fin de la mèche (le roulé fait le reste).
	var speed: float = Balance.get_float("gadgets", "throw_speed", 520.0)
	if kind == &"frag" and fuse_left > 0.0:
		speed = maxf(speed, dist / maxf(fuse_left * 0.75, 0.05))
	var g: float = Balance.get_float("gadgets", "throw_gravity", 1100.0)
	if low_gravity:
		g *= Balance.get_float("low_gravity", "throw_gravity_mult", 0.35)
	velocity = dir * speed
	vz = arc_vz(dist, speed, z, g)


func is_settled() -> bool:
	return z <= 0.0 and vz == 0.0 and velocity.length_squared() < 25.0


func _physics_process(delta: float) -> void:
	if detonated:
		return
	_step_motion(delta)
	match kind:
		&"frag":
			fuse_left -= delta
			if fuse_left <= 0.0:
				explode()
		&"smoke":
			fuse_left -= delta
			if fuse_left <= 0.0 or (is_settled() and fuse_left < (weapon.fuse_time if weapon else 1.0) - 0.3):
				_release_smoke()
		&"mine":
			if not armed:
				fuse_left -= delta
				if fuse_left <= 0.0:
					armed = true
					_play(&"tick")
				_blink(delta, 6.0)
			else:
				_blink(delta, 1.2)
				_check_left -= delta
				if _check_left <= 0.0:
					_check_left = _mine_check
					if enemy_in_radius():
						explode()
		&"c4":
			_blink(delta, 2.0)
		&"decoy":
			# Leurre (agent Économie) : une fois au sol (ou mèche écoulée), DecoyDevice prend le relais.
			fuse_left -= delta
			if is_settled() or fuse_left <= -2.0:
				detonated = true
				DecoyDevice.spawn(get_parent(), global_position, weapon)
				exploded.emit(self)
				queue_free()


func _step_motion(delta: float) -> void:
	if velocity == Vector2.ZERO and z <= 0.0 and vz == 0.0:
		return
	if z > 0.0 or vz != 0.0:
		vz -= _gravity * delta
		z += vz * delta
		if z <= 0.0:
			z = 0.0
			if vz < -90.0:
				vz = -vz * _bounce
				velocity *= _friction
			else:
				vz = 0.0
	else:
		var drag: float = 2.0 if low_gravity else 8.0
		velocity *= exp(-drag * delta)
		if velocity.length_squared() < 16.0:
			velocity = Vector2.ZERO
	var step: Vector2 = velocity * delta
	if step != Vector2.ZERO and is_inside_tree():
		# Un rayon court par frame tant que l'objet bouge : rebond sur les murs.
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step * 1.5 + step.normalized() * 6.0, MASK_WORLD)
		var res: Dictionary = get_world_2d().direct_space_state.intersect_ray(q)
		if not res.is_empty():
			var n: Vector2 = res["normal"]
			velocity = velocity.bounce(n) * _friction
			step = velocity * delta
	global_position += step
	_place_body()


func _place_body() -> void:
	if _body != null:
		_body.position = Vector2(0.0, -z)
		var k: float = clampf(1.0 - z / 120.0, 0.5, 1.0)
		_shadow.scale = Vector2(k, k)


## Ennemi vivant (groupe enemies) dans effect_radius.
func enemy_in_radius() -> bool:
	var r: float = weapon.effect_radius if weapon != null and weapon.effect_radius > 0.0 else 50.0
	var r2: float = r * r
	for e: Node in get_tree().get_nodes_in_group(&"enemies"):
		var n := e as Node2D
		if n == null:
			continue
		if n.has_method("is_alive") and not bool(n.call("is_alive")):
			continue
		if n.global_position.distance_squared_to(global_position) <= r2:
			return true
	return false


## C4 : détonation à distance.
func detonate() -> void:
	explode()


func explode() -> void:
	if detonated:
		return
	detonated = true
	var fx := CombatFx.get_or_create(get_tree())
	var radius: float = weapon.explosion_radius if weapon != null and weapon.explosion_radius > 0.0 else 100.0
	var dmg: float = weapon.explosion_damage if weapon != null and weapon.explosion_damage > 0.0 else 80.0
	if fx != null:
		fx.explode(global_position, radius, dmg, source if is_instance_valid(source) else null)
	else:
		Explosion.apply_damage(get_tree(), null, global_position, radius, dmg, source)
	exploded.emit(self)
	queue_free()


func _release_smoke() -> void:
	if detonated:
		return
	detonated = true
	var r: float = weapon.effect_radius if weapon != null and weapon.effect_radius > 0.0 else 120.0
	var dur: float = weapon.effect_duration if weapon != null and weapon.effect_duration > 0.0 else 8.0
	SmokeField.spawn(get_parent(), global_position, r, dur)
	var fx := CombatFx.get_or_create(get_tree())
	if fx != null:
		fx.muzzle_smoke(global_position, Vector2.UP, 2.0)
	_play(&"flame")
	exploded.emit(self)
	queue_free()


## Voyant clignotant (mine, c4) : redessin seulement quand il change d'état.
func _blink(delta: float, hz: float) -> void:
	_blink_t += delta * hz
	var on: bool = fmod(_blink_t, 1.0) < 0.35
	if on != _light_on:
		_light_on = on
		_body.queue_redraw()
		if on and kind == &"mine" and armed:
			_beep_left -= 1.0
			if _beep_left <= 0.0:
				_beep_left = 3.0
				_play(&"tick")


func _play(sfx: StringName) -> void:
	var am: Node = get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, global_position, -8.0)


func _draw_shadow() -> void:
	_shadow.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	_shadow.draw_circle(Vector2.ZERO, 8.0 if kind == &"c4" or kind == &"mine" else 6.0, Color(0.05, 0.07, 0.15, 0.45))


func _draw_body() -> void:
	var c: Node2D = _body
	var light := Color(1.0, 0.2, 0.15) if _light_on else Color(0.35, 0.08, 0.06)
	if kind == &"mine" and armed and _light_on:
		light = Color(1.0, 0.15, 0.1)
	elif kind == &"mine" and not armed:
		light = Color(1.0, 0.8, 0.2) if _light_on else Color(0.4, 0.3, 0.08)
	if _tex != null:
		var sz := Vector2(_tex.get_size())
		var sc: float = 22.0 / maxf(sz.x, 1.0)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(sc, sc))
		c.draw_texture(_tex, -sz * 0.5)
		c.draw_set_transform(Vector2.ZERO)
		if kind == &"mine" or kind == &"c4":
			c.draw_circle(Vector2(0, -3), 2.4, light, true, -1.0, true)
		return
	draw_gadget_shape(c, kind, light)


## Dessin de repli d'un équipement (au sol ou en main), centré sur l'origine.
static func draw_gadget_shape(c: CanvasItem, k: StringName, light: Color = Color(1.0, 0.2, 0.15)) -> void:
	var dark := Color(0.08, 0.1, 0.08)
	match k:
		&"smoke":
			c.draw_rect(Rect2(-4.5, -7, 9, 13), Color(0.55, 0.6, 0.62))
			c.draw_rect(Rect2(-4.5, -3, 9, 3), Color(0.2, 0.55, 0.3))
			c.draw_rect(Rect2(-2, -10, 4, 3), dark)
			c.draw_rect(Rect2(-4.5, -7, 9, 13), dark, false, 1.2)
		&"mine":
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
			c.draw_circle(Vector2.ZERO, 10.0, Color(0.33, 0.36, 0.28), true, -1.0, true)
			c.draw_circle(Vector2.ZERO, 6.0, Color(0.42, 0.45, 0.36), true, -1.0, true)
			c.draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 20, dark, 1.4, true)
			c.draw_set_transform(Vector2.ZERO)
			c.draw_circle(Vector2(0, -1), 2.4, light, true, -1.0, true)
		&"c4":
			c.draw_rect(Rect2(-10, -6, 20, 11), Color(0.82, 0.76, 0.6))
			c.draw_rect(Rect2(-10, -6, 20, 11), dark, false, 1.2)
			c.draw_line(Vector2(-10, -1), Vector2(10, -1), Color(0.3, 0.3, 0.32), 1.5)
			c.draw_rect(Rect2(-4, -9, 8, 5), Color(0.15, 0.16, 0.18))
			c.draw_circle(Vector2(2, -7), 1.8, light, true, -1.0, true)
			c.draw_line(Vector2(-6, -9), Vector2(-9, -12), Color(0.9, 0.2, 0.15), 1.2)
		&"decoy":
			DecoyDevice.draw_shape(c, light)
		&"drone":
			c.draw_line(Vector2(-9, -6), Vector2(9, 6), dark, 2.0)
			c.draw_line(Vector2(-9, 6), Vector2(9, -6), dark, 2.0)
			for p: Vector2 in [Vector2(-9, -6), Vector2(9, 6), Vector2(-9, 6), Vector2(9, -6)]:
				c.draw_circle(p, 4.5, Color(0.7, 0.85, 1.0, 0.35), true, -1.0, true)
			c.draw_circle(Vector2.ZERO, 4.5, Color(0.2, 0.22, 0.26), true, -1.0, true)
			c.draw_circle(Vector2(1.5, 0), 1.6, Color(0.4, 0.8, 1.0), true, -1.0, true)
		_:
			# Grenade frag.
			c.draw_circle(Vector2.ZERO, 6.5, Color(0.3, 0.37, 0.24), true, -1.0, true)
			c.draw_line(Vector2(-6, 0), Vector2(6, 0), Color(0.2, 0.25, 0.16), 1.0)
			c.draw_line(Vector2(0, -6), Vector2(0, 6), Color(0.2, 0.25, 0.16), 1.0)
			c.draw_circle(Vector2(-2, -2), 2.0, Color(0.55, 0.62, 0.45), true, -1.0, true)
			c.draw_arc(Vector2.ZERO, 6.5, 0.0, TAU, 16, dark, 1.3, true)
			c.draw_rect(Rect2(-2.5, -9.5, 5, 3.5), Color(0.5, 0.52, 0.55))
			c.draw_arc(Vector2(4, -8), 2.5, 0.0, TAU, 10, Color(0.75, 0.75, 0.8), 1.0, true)
