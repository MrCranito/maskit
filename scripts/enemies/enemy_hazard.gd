class_name EnemyHazard
extends Node2D
## Danger posé ou lancé par une compétence ennemie :
##   fire      : cocktail incendiaire (vol en cloche, puis zone de feu `duration` s : dégâts par
##               seconde + statut « burn ») ;
##   trap      : piège à ours (s'arme après `arm_delay`, se referme sur le joueur : dégâts + « root ») ;
##   flash     : grenade flash (vol, puis éclair : « blind » aux joueurs dans le rayon et en vue) ;
##   turret    : tourelle déployable (tire `damage` toutes les `interval` s pendant `duration` s,
##               destructible : `hp`) ;
##   shockwave : onde de choc qui s'étend jusqu'à `radius` (dégâts + « knockdown » au passage) ;
##   blast     : explosion immédiate (kamikaze).
## `real` faux = copie purement visuelle (coop, invité : l'hôte fait autorité sur les effets).
## Un seul nœud par danger, libéré à la fin ; contrôles des joueurs espacés (0,1 s).

const GROUP := &"enemy_hazards"
const OUTLINE := Color(0.08, 0.05, 0.06)
const DANGER := Color(1.0, 0.25, 0.1)
const FIRE_A := Color(1.0, 0.55, 0.12)
const FIRE_B := Color(1.0, 0.85, 0.35)
const STEEL := Color(0.62, 0.64, 0.7)
const FLASH := Color(1.0, 0.98, 0.85)
const ENERGY := Color(0.4, 0.85, 1.0)

var kind: StringName = &"fire"
var p: Dictionary = {}
var source: Node = null
var real: bool = true
var target: Vector2 = Vector2.ZERO

var _t: float = 0.0
var _phase: int = 0
var _check_left: float = 0.0
var _hit_ids: Dictionary = {}
var _hp: float = 0.0
var _fire_left: float = 0.0
var _body: StaticBody2D = null
var _targets: Array[Node2D] = []
var _ray: PhysicsRayQueryParameters2D = null
var _aim: Vector2 = Vector2.RIGHT


## Crée un danger dans `parent` à `pos` (monde). `params` : voir l'en-tête (« from » = point de
## départ d'un objet lancé, sinon posé directement).
static func spawn(parent: Node, p_kind: StringName, pos: Vector2, params: Dictionary, p_source: Node,
		p_real: bool = true) -> EnemyHazard:
	if parent == null:
		return null
	var h := EnemyHazard.new()
	h.kind = p_kind
	h.p = params
	h.source = p_source
	h.real = p_real
	h.target = pos
	h.name = "Hazard_%s" % String(p_kind)
	h.z_index = 4 if p_kind != &"turret" else 9
	var from: Vector2 = params.get("from", pos)
	var start := from if float(params.get("flight", 0.0)) > 0.0 else pos
	# Position fixée AVANT l'entrée dans l'arbre (l'explosion « blast » agit dans _ready).
	h.position = (parent as Node2D).to_local(start) if parent is Node2D else start
	parent.add_child(h)
	return h


func f(key: String, def: float) -> float:
	return float(p.get(key, def))


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"fog_hideable")
	_hp = f("hp", 30.0)
	_ray = PhysicsRayQueryParameters2D.new()
	_ray.collision_mask = 1
	if kind == &"turret" and real:
		_build_turret_body()
	if kind == &"blast":
		_blast()


func is_landed() -> bool:
	return _phase >= 1


func _flight() -> float:
	return f("flight", 0.0)


func _physics_process(delta: float) -> void:
	_t += delta
	# Phase 0 : vol (objet lancé) ; phase 1 : actif.
	if _phase == 0:
		var fl := _flight()
		if fl > 0.0 and _t < fl:
			var from: Vector2 = p.get("from", target)
			global_position = from.lerp(target, _t / fl)
			queue_redraw()
			return
		global_position = target
		_phase = 1
		_t = 0.0
		_on_landed()
	match kind:
		&"fire":
			_tick_fire(delta)
		&"trap":
			_tick_trap(delta)
		&"turret":
			_tick_turret(delta)
		&"shockwave":
			_tick_shockwave()
		&"flash", &"blast":
			if _t > 0.45:
				queue_free()
	queue_redraw()


func _on_landed() -> void:
	var fx := CombatFx.get_or_create(get_tree())
	match kind:
		&"fire":
			_play(&"glass_break")
			_fire_left = 0.0
		&"flash":
			_play(&"explosion")
			if fx != null:
				fx.air.emit(FxLayer.Kind.FLASH, global_position, Vector2.ZERO, 0.35, f("radius", 130.0) * 0.6,
					f("radius", 130.0), Color(FLASH, 0.9))
			_blind_players()
		&"trap":
			_play(&"item_equip")


# --- Feu -------------------------------------------------------------------------------

func _tick_fire(delta: float) -> void:
	if _t >= f("duration", 4.0):
		queue_free()
		return
	_fire_left -= delta
	if _fire_left > 0.0 or not real:
		return
	var tick := f("tick", 0.5)
	_fire_left = tick
	EnemySkills.player_targets(get_tree(), _targets)
	for pl: Node2D in _targets:
		if pl.global_position.distance_to(global_position) <= f("radius", 70.0):
			EnemySkills.hit_player(pl, f("dps", 8.0) * tick, source, &"burn", tick + 0.3, 1.0)


# --- Piège -----------------------------------------------------------------------------

func _tick_trap(delta: float) -> void:
	if _phase == 2:
		if _t > 1.2:
			queue_free()
		return
	if _t >= f("life", 25.0):
		queue_free()
		return
	if _t < f("arm_delay", 0.6):
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.1
	EnemySkills.player_targets(get_tree(), _targets)
	for pl: Node2D in _targets:
		if pl.global_position.distance_to(global_position) <= f("radius", 24.0):
			_phase = 2
			_t = 0.0
			_play(&"metal_impact")
			if real:
				EnemySkills.hit_player(pl, f("damage", 12.0), source, &"root", f("root_time", 1.5), 1.0)
			return


## Le piège se referme (copie visuelle chez l'invité : déclenchée par le joueur proche).
func is_sprung() -> bool:
	return _phase == 2


# --- Flash -----------------------------------------------------------------------------

func _blind_players() -> void:
	if not real:
		return
	EnemySkills.player_targets(get_tree(), _targets)
	var space := get_world_2d().direct_space_state
	for pl: Node2D in _targets:
		var d := pl.global_position.distance_to(global_position)
		if d > f("radius", 130.0):
			continue
		_ray.from = global_position
		_ray.to = pl.global_position
		if not space.intersect_ray(_ray).is_empty():
			continue  # Un mur protège de l'éclair.
		var power := lerpf(1.0, 0.5, d / maxf(f("radius", 130.0), 1.0))
		EnemySkills.hit_player(pl, 0.0, source, &"blind", f("blind_time", 1.5) * power, power)


# --- Tourelle déployable ------------------------------------------------------------

func _build_turret_body() -> void:
	_body = TurretBody.new()
	_body.hazard = self
	_body.collision_layer = 4
	_body.collision_mask = 0
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 14.0
	cs.shape = c
	_body.add_child(cs)
	add_child(_body)


func _tick_turret(delta: float) -> void:
	if _t >= f("duration", 12.0) or _hp <= 0.0:
		var fx := CombatFx.get_or_create(get_tree())
		if fx != null:
			fx.dust_puff(global_position, Vector2(0, -20), 7.0, 0.5)
		queue_free()
		return
	if not real or _t < f("arm_delay", 0.8):
		return
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = f("interval", 0.7)
	EnemySkills.player_targets(get_tree(), _targets)
	var best: Node2D = null
	var best_d := f("range", 380.0)
	var space := get_world_2d().direct_space_state
	for pl: Node2D in _targets:
		var d := pl.global_position.distance_to(global_position)
		if d > best_d:
			continue
		_ray.from = global_position
		_ray.to = pl.global_position
		if not space.intersect_ray(_ray).is_empty():
			continue
		best = pl
		best_d = d
	if best == null:
		return
	var dir := (best.global_position - global_position).normalized()
	_aim = dir
	var pool := EnemyProjectilePool.get_or_create(get_tree())
	if pool != null:
		pool.spawn(global_position + dir * 18.0, dir, f("speed", 520.0), f("damage", 5.0), source if is_instance_valid(source) else self,
			0.0, &"laser")
	_play(&"gun_shot_alt")



func take_hit(amount: float) -> void:
	_hp -= amount
	modulate = Color(1.6, 1.6, 1.6)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.12)


func is_destroyed() -> bool:
	return _hp <= 0.0


class TurretBody extends StaticBody2D:
	var hazard: EnemyHazard = null

	func _ready() -> void:
		add_to_group(&"damageable")
		add_to_group(&"enemies")

	func take_damage(amount: float, _source: Node) -> void:
		if hazard != null and is_instance_valid(hazard):
			hazard.take_hit(amount)

	func is_alive() -> bool:
		return hazard != null and is_instance_valid(hazard) and not hazard.is_destroyed()


# --- Onde de choc ---------------------------------------------------------------------

func shock_radius() -> float:
	return f("radius", 260.0) * clampf(_t / maxf(f("duration", 0.6), 0.05), 0.0, 1.0)


func _tick_shockwave() -> void:
	var dur := f("duration", 0.6)
	if _t >= dur + 0.25:
		queue_free()
		return
	if _t > dur or not real:
		return
	var r := shock_radius()
	var band := f("band", 30.0)
	EnemySkills.player_targets(get_tree(), _targets)
	for pl: Node2D in _targets:
		var id := pl.get_instance_id()
		if _hit_ids.has(id):
			continue
		var d := pl.global_position.distance_to(global_position)
		if absf(d - r) <= band:
			_hit_ids[id] = true
			EnemySkills.hit_player(pl, f("damage", 18.0), source, &"knockdown", f("knock_time", 0.6), 1.0, global_position)


# --- Explosion (kamikaze) -----------------------------------------------------------

func _blast() -> void:
	_phase = 1
	var fx := CombatFx.get_or_create(get_tree())
	if fx != null:
		fx.explode(global_position, f("radius", 90.0), 0.0, null)
	if real:
		EnemySkills.player_targets(get_tree(), _targets)
		for pl: Node2D in _targets:
			var d := pl.global_position.distance_to(global_position)
			if d <= f("radius", 90.0):
				EnemySkills.hit_player(pl, Explosion.falloff_damage(d, f("radius", 90.0), f("damage", 22.0), 0.35), source)


func _play(sfx: StringName) -> void:
	var am := get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, global_position, -4.0)


# --- Dessin -------------------------------------------------------------------------

func _draw() -> void:
	var lt := target - global_position
	if _phase == 0 and _flight() > 0.0:
		# Cible au sol pendant le vol + objet en cloche.
		var r := f("radius", 70.0)
		var w := clampf(_t / _flight(), 0.0, 1.0)
		draw_circle(lt, r, Color(DANGER, 0.08 + 0.08 * w))
		draw_arc(lt, r, 0.0, TAU, 40, Color(DANGER, 0.6 + 0.3 * sin(_t * 20.0)), 2.5, true)
		var h := 4.0 * 60.0 * w * (1.0 - w)
		draw_set_transform(Vector2(0, -6.0 - h), _t * 12.0)
		if kind == &"fire":
			draw_rect(Rect2(-4, -8, 8, 14), OUTLINE)
			draw_rect(Rect2(-3, -7, 6, 12), Color(0.45, 0.65, 0.35))
			draw_circle(Vector2(0, -10), 3.5, FIRE_A)
		else:
			draw_circle(Vector2.ZERO, 6.0, OUTLINE)
			draw_circle(Vector2.ZERO, 4.5, Color(0.75, 0.8, 0.85))
			draw_circle(Vector2(2, -2), 1.5, ENERGY)
		draw_set_transform(Vector2.ZERO)
		return
	match kind:
		&"fire":
			var r2 := f("radius", 70.0)
			var fade := clampf((f("duration", 4.0) - _t) / 0.5, 0.0, 1.0)
			draw_circle(Vector2.ZERO, r2, Color(0.1, 0.04, 0.02, 0.35 * fade))
			draw_circle(Vector2.ZERO, r2, Color(FIRE_A, 0.16 * fade))
			draw_arc(Vector2.ZERO, r2, 0.0, TAU, 40, Color(DANGER, 0.7 * fade), 2.0, true)
			for i: int in 9:
				var a := TAU * float(i) / 9.0 + float(i) * 0.7
				var rr := r2 * (0.25 + 0.6 * fposmod(float(i) * 0.37, 1.0))
				var base := Vector2.from_angle(a) * rr
				var hh := (12.0 + 8.0 * absf(sin(_t * 9.0 + float(i)))) * fade
				draw_colored_polygon(PackedVector2Array([base + Vector2(-6, 0), base + Vector2(0, -hh), base + Vector2(6, 0)]),
					Color(FIRE_A, 0.9 * fade))
				draw_colored_polygon(PackedVector2Array([base + Vector2(-3, 0), base + Vector2(0, -hh * 0.6), base + Vector2(3, 0)]),
					Color(FIRE_B, 0.95 * fade))
		&"trap":
			var armed := _t >= f("arm_delay", 0.6)
			var open := _phase != 2
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, 15.0, Color(OUTLINE, 0.85))
			draw_arc(Vector2.ZERO, 13.0 if open else 7.0, 0.0, TAU, 20, STEEL, 3.0, true)
			for i: int in 10:
				var a := TAU * float(i) / 10.0
				var r0 := 13.0 if open else 7.0
				draw_line(Vector2.from_angle(a) * r0, Vector2.from_angle(a) * (r0 - 5.0), STEEL.lightened(0.3), 2.0, true)
			draw_set_transform(Vector2.ZERO)
			if armed and open:
				draw_circle(Vector2(0, -1), 2.5, Color(DANGER, 0.5 + 0.5 * sin(_t * 6.0)))
		&"flash":
			var k := clampf(_t / 0.45, 0.0, 1.0)
			draw_circle(Vector2.ZERO, f("radius", 130.0) * (0.4 + 0.6 * k), Color(FLASH, 0.55 * (1.0 - k)))
			draw_arc(Vector2.ZERO, f("radius", 130.0) * k, 0.0, TAU, 40, Color(FLASH, 0.9 * (1.0 - k)), 4.0, true)
		&"turret":
			var lifek := clampf(1.0 - _t / f("duration", 12.0), 0.0, 1.0)
			draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, 18.0, Color(0.06, 0.08, 0.2, 0.4))
			draw_set_transform(Vector2.ZERO)
			for i: int in 3:
				var a := PI * 0.5 + (float(i) - 1.0) * 0.8
				draw_line(Vector2(0, -8), Vector2.from_angle(a) * 16.0 + Vector2(0, -2), OUTLINE, 4.0, true)
			draw_circle(Vector2(0, -12), 10.0, OUTLINE)
			draw_circle(Vector2(0, -12), 8.5, Color(0.55, 0.6, 0.68))
			draw_line(Vector2(0, -12), Vector2(0, -12) + _aim * 16.0, OUTLINE, 5.0, true)
			draw_line(Vector2(0, -12), Vector2(0, -12) + _aim * 15.0, Color(0.3, 0.32, 0.38), 3.0, true)
			draw_circle(Vector2(0, -12), 3.0, Color(ENERGY, 0.6 + 0.4 * sin(_t * 8.0)))
			draw_arc(Vector2(0, -12), 13.0, -PI * 0.5, -PI * 0.5 + TAU * lifek, 20, Color(ENERGY, 0.7), 2.0, true)
		&"shockwave":
			var r3 := shock_radius()
			var a2 := 1.0 if _t <= f("duration", 0.6) else clampf(1.0 - (_t - f("duration", 0.6)) / 0.25, 0.0, 1.0)
			draw_arc(Vector2.ZERO, r3, 0.0, TAU, 64, Color(1.0, 0.8, 0.5, 0.85 * a2), 8.0, true)
			draw_arc(Vector2.ZERO, maxf(r3 - 14.0, 0.0), 0.0, TAU, 64, Color(ENERGY.lerp(Color.WHITE, 0.4), 0.5 * a2), 4.0, true)
