class_name EnemyDynamite
extends Node2D
## Bâton de dynamite lancé par un ennemi (dynamiteur, chef de bande) : vol en cloche jusqu'à la
## cible, mèche qui grésille au sol avec un cercle de danger qui se remplit, puis explosion
## (visuel CombatFx.explode sans ses dégâts, dégâts calculés ici : le joueur prend la totalité,
## les autres ennemis une fraction [enemy_tactics] dynamite_friendly_fire).
## Aucun redessin quand rien ne change ; un seul nœud par bâton, libéré après l'explosion.

const STICK := Color(0.82, 0.16, 0.12)
const STICK_DARK := Color(0.4, 0.06, 0.08)
const OUTLINE := Color(0.08, 0.05, 0.06)
const SPARK := Color(1.0, 0.85, 0.35)
const DANGER := Color(1.0, 0.25, 0.1)
const ARC_HEIGHT := 70.0

signal exploded(at: Vector2)

var source: Node = null
var start: Vector2 = Vector2.ZERO
var target: Vector2 = Vector2.ZERO
var flight_time: float = 0.7
var fuse_time: float = 0.9
var radius: float = 90.0
var damage: float = 20.0
var friendly_fire: float = 0.5
var min_frac: float = 0.3

var _t: float = 0.0
var _landed: bool = false
var _fuse_left: float = 0.0
var _done: bool = false
var _spin: float = 0.0
## Rebond (dynamite à rebonds) : second point d'impact et durée du saut ; INF = aucun.
var bounce_to: Vector2 = Vector2.INF
var bounce_flight: float = 0.35
var bounced: bool = false


## Après le premier impact, la dynamite rebondit vers `to` en `flight` s avant la mèche.
func set_bounce(to: Vector2, flight: float) -> void:
	bounce_to = to
	bounce_flight = maxf(flight, 0.1)


## Point d'explosion final (après rebond éventuel).
func final_target() -> Vector2:
	return bounce_to if bounce_to != Vector2.INF and not bounced else target


static func throw(parent: Node, from: Vector2, to: Vector2, p_radius: float, p_damage: float,
		p_flight: float, p_fuse: float, p_source: Node) -> EnemyDynamite:
	var d := EnemyDynamite.new()
	d.name = "Dynamite"
	d.start = from
	d.target = to
	d.radius = p_radius
	d.damage = p_damage
	d.flight_time = maxf(p_flight, 0.1)
	d.fuse_time = maxf(p_fuse, 0.05)
	d.source = p_source
	d.friendly_fire = Balance.get_float("enemy_tactics", "dynamite_friendly_fire", 0.5)
	d.min_frac = Balance.get_float("enemy_tactics", "dynamite_min_frac", 0.3)
	d.z_index = 4
	parent.add_child(d)
	d.global_position = from
	return d


func _ready() -> void:
	add_to_group(&"enemy_dynamite")
	_fuse_left = fuse_time


func is_landed() -> bool:
	return _landed


func time_to_explosion() -> float:
	if _landed:
		return _fuse_left
	return flight_time - _t + fuse_time


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not _landed:
		_t += delta
		var u := clampf(_t / flight_time, 0.0, 1.0)
		global_position = start.lerp(target, u)
		_spin += delta * 14.0
		if u >= 1.0 and bounce_to != Vector2.INF and not bounced:
			bounced = true
			start = target
			target = bounce_to
			flight_time = bounce_flight
			_t = 0.0
			var fxb := CombatFx.get_or_create(get_tree())
			if fxb != null:
				fxb.dust_puff(global_position, Vector2(0, -10), 5.0, 0.4)
		elif u >= 1.0:
			_landed = true
			var fx := CombatFx.get_or_create(get_tree())
			if fx != null:
				fx.dust_puff(global_position, Vector2(0, -10), 5.0, 0.4)
	else:
		_fuse_left -= delta
		if _fuse_left <= 0.0:
			_explode()
			return
	queue_redraw()


func _explode() -> void:
	_done = true
	var pos := global_position
	var fx := CombatFx.get_or_create(get_tree())
	if fx != null:
		# Visuel, secousse et bruit uniquement (dégâts calculés ci-dessous).
		fx.explode(pos, radius, 0.0, source if is_instance_valid(source) else null)
	apply_damage(get_tree(), pos, radius, damage, source, friendly_fire, min_frac)
	exploded.emit(pos)
	queue_free()


## Dégâts de l'explosion (logique pure : utilisable en test). Renvoie le nombre de cibles touchées.
static func apply_damage(tree: SceneTree, pos: Vector2, r: float, dmg: float, src: Node,
		ff: float, mf: float) -> int:
	var n := 0
	if tree == null:
		return 0
	for t: Node in tree.get_nodes_in_group(&"damageable"):
		var t2 := t as Node2D
		if t2 == null or not t.has_method("take_damage"):
			continue
		if t.has_method("is_alive") and not bool(t.call("is_alive")):
			continue
		var d := pos.distance_to(t2.global_position)
		if d > r:
			continue
		var mult := 1.0 if (t.is_in_group(&"player") or t.is_in_group(&"coop_avatar")) else ff
		if mult <= 0.0:
			continue
		var amount := Explosion.falloff_damage(d, r, dmg, mf) * mult
		if amount > 0.0:
			t.call("take_damage", amount, src if is_instance_valid(src) else null)
			n += 1
	return n


func _draw() -> void:
	if _done:
		return
	# Cercle de danger au sol (cible), présent pendant tout le vol puis la mèche.
	var total := flight_time + fuse_time
	var elapsed := _t + (fuse_time - _fuse_left if _landed else 0.0)
	var w := clampf(elapsed / total, 0.0, 1.0)
	var local_target := final_target() - global_position
	var pulse := 0.5 + 0.5 * sin(elapsed * (10.0 + 20.0 * w))
	draw_circle(local_target, radius, Color(DANGER, 0.07 + 0.08 * w))
	draw_circle(local_target, radius * w, Color(DANGER, 0.10 + 0.12 * w))
	draw_arc(local_target, radius, 0.0, TAU, 48, Color(DANGER, 0.5 + 0.45 * pulse), 2.5 + 1.5 * w, true)
	# Bâton : en l'air (hauteur parabolique, ombre au sol) ou posé.
	var h := 0.0
	if not _landed:
		var u := clampf(_t / flight_time, 0.0, 1.0)
		h = 4.0 * ARC_HEIGHT * u * (1.0 - u)
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
		draw_circle(Vector2.ZERO, 6.0, Color(0.06, 0.08, 0.2, 0.35))
		draw_set_transform(Vector2.ZERO)
	var rot := _spin if not _landed else 0.35
	draw_set_transform(Vector2(0, -4.0 - h), rot)
	draw_rect(Rect2(-9, -3.5, 18, 7), OUTLINE)
	draw_rect(Rect2(-8, -2.5, 16, 5), STICK)
	draw_rect(Rect2(-8, 0.5, 16, 2), STICK_DARK)
	draw_line(Vector2(8, 0), Vector2(12, -3), OUTLINE, 1.5)
	var sp := 2.5 + 1.5 * pulse
	draw_circle(Vector2(12, -3), sp + 1.5, Color(1.0, 0.5, 0.15, 0.5))
	draw_circle(Vector2(12, -3), sp * 0.6, SPARK)
	draw_set_transform(Vector2.ZERO)
