class_name CombatFx
extends Node2D
## Effets de combat partagés de la scène (un seul par scène, créé à la demande via
## `CombatFx.get_or_create(tree)`) : deux couches de particules poolées (FxLayer) —
## « sol » (traces de brûlure, poussière, douilles) et « air » (étincelles, fumée,
## éclairs, ondes de choc, traçantes, numéros de dégâts).
## Toutes les quantités viennent de balance.cfg [projectile_fx] et sont réduites en mode
## économie d'énergie (Engine.max_fps ≤ 30, cf. GameState.apply_power_saving) ou si
## [projectile_fx] force_low_quality = true.

const GROUP := &"combat_fx"
const Z_GROUND := 3
const Z_AIR := 30

static var _instance: CombatFx = null

var ground: FxLayer = null
var air: FxLayer = null

# Réglages ([projectile_fx]).
var low_quality_mult: float = 0.5
var force_low: bool = false
var spark_count: int = 6
var enemy_spray_count: int = 7
var damage_numbers: bool = true
var damage_number_size: float = 17.0
var tracer_life: float = 0.12
var tracer_width: float = 2.0
var explosion_debris: int = 10
var explosion_smoke: int = 8
var explosion_fire: int = 8
var explosion_sparks: int = 12
var explosion_scorch_life: float = 6.0
var explosion_shake_px: float = 9.0
var explosion_shake_range: float = 700.0
var explosion_zoom_kick: float = 0.06
var explosion_noise_radius: float = 900.0
var explosion_min_frac: float = 0.25
var explosion_self_mult: float = 0.25
var _last_impact_msec: int = 0
## Cumul des dégâts par cible sur une courte fenêtre (plombs d'une même salve) :
## instance_id → [index de particule, total, msec].
var _number_merge: Dictionary = {}
const NUMBER_MERGE_MSEC := 140


static func get_or_create(tree: SceneTree) -> CombatFx:
	if is_instance_valid(_instance) and _instance.is_inside_tree() and not _instance.is_queued_for_deletion() \
			and _instance.get_tree() == tree:
		return _instance
	if tree == null:
		return null
	var existing := tree.get_first_node_in_group(GROUP) as CombatFx
	if existing != null and not existing.is_queued_for_deletion():
		_instance = existing
		return existing
	var fx := CombatFx.new()
	fx.name = "CombatFx"
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(fx)
	_instance = fx
	return fx


func _init() -> void:
	add_to_group(GROUP)
	z_as_relative = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_load_balance()
	ground = FxLayer.new()
	ground.name = "Ground"
	ground.z_index = Z_GROUND
	ground.z_as_relative = false
	ground.setup(int(Balance.get_value("projectile_fx", "ground_capacity", 160)))
	add_child(ground)
	air = FxLayer.new()
	air.name = "Air"
	air.z_index = Z_AIR
	air.z_as_relative = false
	air.setup(int(Balance.get_value("projectile_fx", "air_capacity", 384)))
	add_child(air)


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _load_balance() -> void:
	low_quality_mult = Balance.get_float("projectile_fx", "low_quality_mult", 0.5)
	force_low = bool(Balance.get_value("projectile_fx", "force_low_quality", false))
	spark_count = int(Balance.get_value("projectile_fx", "wall_sparks", 6))
	enemy_spray_count = int(Balance.get_value("projectile_fx", "enemy_spray", 7))
	damage_numbers = bool(Balance.get_value("projectile_fx", "damage_numbers", true))
	damage_number_size = Balance.get_float("projectile_fx", "damage_number_size", 17.0)
	tracer_life = Balance.get_float("projectile_fx", "tracer_life", 0.12)
	tracer_width = Balance.get_float("projectile_fx", "tracer_width", 2.0)
	explosion_debris = int(Balance.get_value("projectile_fx", "explosion_debris", 10))
	explosion_smoke = int(Balance.get_value("projectile_fx", "explosion_smoke", 8))
	explosion_fire = int(Balance.get_value("projectile_fx", "explosion_fire", 8))
	explosion_sparks = int(Balance.get_value("projectile_fx", "explosion_sparks", 12))
	explosion_scorch_life = Balance.get_float("projectile_fx", "explosion_scorch_life", 6.0)
	explosion_shake_px = Balance.get_float("projectile_fx", "explosion_shake_px", 9.0)
	explosion_shake_range = Balance.get_float("projectile_fx", "explosion_shake_range", 700.0)
	explosion_zoom_kick = Balance.get_float("projectile_fx", "explosion_zoom_kick", 0.06)
	explosion_noise_radius = Balance.get_float("projectile_fx", "explosion_noise_radius", 900.0)
	explosion_min_frac = Balance.get_float("projectile_fx", "explosion_min_damage_frac", 0.25)
	explosion_self_mult = Balance.get_float("projectile_fx", "explosion_self_damage_mult", 0.25)


## Effets réduits (économie d'énergie ou réglage forcé).
func is_low() -> bool:
	return force_low or (Engine.max_fps > 0 and Engine.max_fps <= 30)


## Nombre de particules après réduction de qualité (au moins `minimum`).
func count(n: int, minimum: int = 1) -> int:
	if is_low():
		return maxi(int(round(float(n) * low_quality_mult)), minimum)
	return maxi(n, minimum)


# --- Impacts ------------------------------------------------------------------

## Étincelles sur un mur : gerbe réfléchie autour de la normale (≈ -dir).
func impact_wall(pos: Vector2, dir: Vector2, color: Color) -> void:
	var normal: Vector2 = -dir
	air.emit(FxLayer.Kind.FLASH, pos, Vector2.ZERO, 0.06, 7.0, 10.0, Color(1.0, 0.92, 0.7, 0.9))
	for i: int in count(spark_count):
		var v: Vector2 = normal.rotated(randf_range(-1.2, 1.2)) * randf_range(140.0, 330.0)
		air.emit(FxLayer.Kind.SPARK, pos, v, randf_range(0.12, 0.24), randf_range(1.2, 2.0), 1.0,
			Color(1.0, 0.82, 0.4).lerp(color, 0.25))
	ground.emit(FxLayer.Kind.DUST, pos + normal * 4.0, normal * 30.0, 0.45, 4.0, 9.0, Color(0.95, 0.9, 0.8, 0.5))
	_play_impact_sfx(&"bullet_impact", pos)


## Gerbe sur ennemi (dans le sens du tir) + numéro de dégâts flottant (cumulé par cible
## `target_id` sur une courte fenêtre : une salve de plombs = un seul chiffre).
func impact_enemy(pos: Vector2, dir: Vector2, amount: float, show_number: bool = true, target_id: int = 0) -> void:
	air.emit(FxLayer.Kind.FLASH, pos, Vector2.ZERO, 0.07, 6.0, 11.0, Color(1.0, 0.95, 0.85, 0.85))
	for i: int in count(enemy_spray_count):
		var v: Vector2 = dir.rotated(randf_range(-0.7, 0.7)) * randf_range(90.0, 240.0)
		if i % 2 == 0:
			air.emit(FxLayer.Kind.DROPLET, pos, v * 0.6, randf_range(0.3, 0.5), randf_range(1.6, 2.6), 1.2,
				Color(0.75, 0.12, 0.1, 0.95), randf_range(4.0, 14.0), randf_range(60.0, 160.0))
		else:
			air.emit(FxLayer.Kind.SPARK, pos, v, randf_range(0.1, 0.2), 1.8, 1.0, Color(1.0, 0.86, 0.6))
	if show_number:
		damage_number(pos + Vector2(0.0, -30.0), amount, false, target_id)


func damage_number(pos: Vector2, amount: float, crit: bool = false, target_id: int = 0) -> void:
	if not damage_numbers or amount <= 0.0:
		return
	var size: float = damage_number_size * (1.25 if crit else 1.0)
	var now: int = Time.get_ticks_msec()
	if target_id != 0 and _number_merge.has(target_id):
		var m: Array = _number_merge[target_id]
		if now - int(m[2]) <= NUMBER_MERGE_MSEC:
			var total: float = float(m[1]) + amount
			if air.refresh_text(int(m[0]), _fmt(total), 0.65, minf(size * (1.0 + total / 200.0), size * 1.6)):
				m[1] = total
				m[2] = now
				return
	var col: Color = Color(1.0, 0.85, 0.3) if crit else Color(1.0, 0.97, 0.9)
	var idx: int = air.emit_text(pos + Vector2(randf_range(-10.0, 10.0), 0.0), _fmt(amount), col, size, 0.65, 70.0)
	if target_id != 0:
		if _number_merge.size() > 64:
			_number_merge.clear()
		_number_merge[target_id] = [idx, amount, now]


static func _fmt(amount: float) -> String:
	return str(maxi(roundi(amount), 1))


## Traçante qui reste une fraction de seconde (sniper) de `from` à `to`.
func tracer(from: Vector2, to: Vector2, color: Color, width: float = -1.0) -> void:
	air.emit(FxLayer.Kind.TRACER, from, to, tracer_life, width if width > 0.0 else tracer_width, 0.0, color)


# --- Tir (bouche du canon) ----------------------------------------------------

func muzzle_smoke(pos: Vector2, dir: Vector2, strength: float = 1.0) -> void:
	air.emit(FxLayer.Kind.SMOKE, pos + dir * 4.0, dir * 22.0 * strength + Vector2(0.0, -14.0),
		randf_range(0.5, 0.8), 3.0 * strength, 9.0 * strength, Color(0.82, 0.82, 0.86, 0.32))


## Douille éjectée depuis `pos` (hauteur `z` au-dessus du sol), perpendiculaire à `dir`.
func shell(ground_pos: Vector2, z: float, dir: Vector2, big: bool) -> void:
	var side: Vector2 = Vector2(-dir.y, dir.x)
	if side.y > 0.0:
		side = -side  # éjection vers le haut de l'écran (lisible), puis retombe
	var v: Vector2 = (side * randf_range(70.0, 120.0) - dir * randf_range(10.0, 40.0))
	var col: Color = Color(0.9, 0.22, 0.15) if big else Color(1.0, 0.8, 0.3)
	# Couche « air » : la douille part de la main, devant le corps.
	air.emit(FxLayer.Kind.SHELL, ground_pos, v, randf_range(1.1, 1.6), 6.5 if big else 4.5, 0.0, col,
		z, randf_range(140.0, 230.0), randf_range(0.0, TAU), randf_range(-24.0, 24.0))


## Chargeur qui tombe au rechargement.
func magazine_drop(ground_pos: Vector2, z: float, dir: Vector2) -> void:
	ground.emit(FxLayer.Kind.SHELL, ground_pos, -dir * 20.0, 1.4, 8.0, 0.0, Color(0.2, 0.22, 0.27),
		z, 40.0, dir.angle() + PI * 0.5, randf_range(-6.0, 6.0))


# --- Déplacement ----------------------------------------------------------------

func dust_puff(pos: Vector2, vel: Vector2, size: float = 4.0, alpha: float = 0.45) -> void:
	ground.emit(FxLayer.Kind.DUST, pos, vel, randf_range(0.35, 0.55), size, size * 2.2,
		Color(0.97, 0.92, 0.82, alpha))


# --- Roquettes / grenades -------------------------------------------------------

func rocket_trail(pos: Vector2, dir: Vector2) -> void:
	air.emit(FxLayer.Kind.SMOKE, pos, -dir * 25.0 + Vector2(randf_range(-8, 8), randf_range(-12, 2)),
		randf_range(0.5, 0.75), 4.0, 11.0, Color(0.78, 0.77, 0.8, 0.42))
	if randf() < 0.5:
		air.emit(FxLayer.Kind.FIRE, pos, -dir * 60.0, 0.12, 4.0, 1.5, Color(1.0, 0.7, 0.25, 0.9))


## Explosion visuelle + dégâts + secousse + bruit. `source` = tireur (dégâts attribués).
func explode(pos: Vector2, radius: float, damage: float, source: Node) -> void:
	var r: float = maxf(radius, 20.0)
	# Dégâts (une requête de ligne de vue par cible dans le rayon).
	var amounts: Array = []
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state if is_inside_tree() else null
	var hit: Array[Node2D] = Explosion.apply_damage(get_tree(), space, pos, radius, damage, source,
		explosion_min_frac, explosion_self_mult, amounts)
	for i: int in hit.size():
		if not hit[i].is_in_group(&"player") and not hit[i].has_method("_spawn_damage_number"):
			damage_number(hit[i].global_position + Vector2(0.0, -40.0), float(amounts[i]), true,
				hit[i].get_instance_id())
	# Visuel.
	air.emit(FxLayer.Kind.FLASH, pos, Vector2.ZERO, 0.32, r * 0.75, r * 1.0, Color(1.0, 0.55, 0.15, 0.55))
	air.emit(FxLayer.Kind.FLASH, pos, Vector2.ZERO, 0.16, r * 0.45, r * 0.7, Color(1.0, 0.97, 0.85, 1.0))
	# Onde de choc (RING : `rot` = épaisseur initiale du trait).
	air.emit(FxLayer.Kind.RING, pos, Vector2.ZERO, 0.32, r * 0.25, r * 1.15, Color(1.0, 0.9, 0.7, 0.8), 0.0, 0.0, 6.0)
	for i: int in count(explosion_fire, 3):
		var v: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(40.0, 150.0) * r / 90.0
		air.emit(FxLayer.Kind.FIRE, pos + v * 0.08, v, randf_range(0.3, 0.55), randf_range(9.0, 15.0) * r / 90.0,
			4.0, Color(1.0, randf_range(0.6, 0.85), 0.25, 0.95))
	for i: int in count(explosion_smoke, 3):
		var v: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(20.0, 70.0) + Vector2(0.0, -20.0)
		air.emit(FxLayer.Kind.SMOKE, pos + v * 0.3, v, randf_range(0.9, 1.5), 8.0 * r / 90.0, 22.0 * r / 90.0,
			Color(0.55, 0.5, 0.5, 0.32))
	for i: int in count(explosion_debris, 3):
		var v: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(80.0, 260.0)
		ground.emit(FxLayer.Kind.DEBRIS, pos, v, randf_range(0.8, 1.3), randf_range(2.5, 4.5), 0.0,
			Color(0.36, 0.27, 0.2).lerp(Color(0.6, 0.48, 0.32), randf()), 6.0, randf_range(150.0, 320.0),
			randf() * TAU, randf_range(-14.0, 14.0))
	for i: int in count(explosion_sparks, 4):
		var v: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(200.0, 480.0)
		air.emit(FxLayer.Kind.SPARK, pos, v, randf_range(0.18, 0.35), 2.0, 1.0, Color(1.0, 0.85, 0.45))
	ground.emit(FxLayer.Kind.SCORCH, pos, Vector2.ZERO, explosion_scorch_life, r * 0.4, r * 0.4,
		Color(0.12, 0.08, 0.07, 0.35))
	_play_sfx(&"explosion", pos)
	# Secousse (atténuée par la distance au joueur) + petit kick de zoom + bruit.
	var p := get_tree().get_first_node_in_group(&"player") as Node2D
	if p != null:
		var d: float = p.global_position.distance_to(pos)
		var k: float = clampf(1.0 - d / maxf(explosion_shake_range, 1.0), 0.0, 1.0)
		if k > 0.0 and p.has_method("add_shake"):
			p.call("add_shake", explosion_shake_px * k, 0.3, explosion_zoom_kick * k)
		if source == p and p.has_method("add_noise"):
			p.call("add_noise", 1.0)
	alert_enemies(pos, explosion_noise_radius)


## Bruit fort : les ennemis dans `radius` (ligne de vue non requise) deviennent méfiants
## en proportion de la distance. Un parcours du groupe par explosion.
func alert_enemies(pos: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	for e: Node in get_tree().get_nodes_in_group(&"enemies"):
		var n := e as Node2D
		if n == null or not n.has_method("add_awareness"):
			continue
		var d: float = n.global_position.distance_to(pos)
		if d > radius:
			continue
		n.call("add_awareness", lerpf(1.0, 0.35, d / radius), pos, false)


func _play_impact_sfx(sfx: StringName, pos: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_impact_msec < 70:
		return
	_last_impact_msec = now
	_play_sfx(sfx, pos, -6.0)


func _play_sfx(sfx: StringName, pos: Vector2, db: float = 0.0) -> void:
	var am: Node = get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, pos, db)
