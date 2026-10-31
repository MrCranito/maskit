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
var low_gravity_fx_mult: float = 0.15
var _last_impact_msec: int = 0
## Cumul des dégâts par cible sur une courte fenêtre (plombs d'une même salve) :
## instance_id → [index de particule, total, msec].
var _number_merge: Dictionary = {}
const NUMBER_MERGE_MSEC := 140

## Matières d'impact (balance.cfg [hit_fx]) : gerbe, couleurs et éclats selon la cible.
const MAT_ORGANIC := &"organic"
const MAT_METAL := &"metal"
const MAT_HARD := &"hard"
const MAT_ALIEN := &"alien"
const MAT_ICE := &"ice"
const MAT_ETHEREAL := &"ethereal"

# Réglages des impacts ([hit_fx]), lus une fois par scène.
var hit_marker: bool = true
var hit_marker_size: float = 10.0
var hit_marker_life: float = 0.16
var hit_marker_color: Color = Color(1, 1, 1, 0.95)
var hit_marker_kill_color: Color = Color(1.0, 0.3, 0.25, 1.0)
var hit_flash_size: float = 20.0
var kick_per_recoil: float = 0.7
var kick_max_px: float = 6.0
var wall_mark_life: float = 3.0
var wall_mark_size: float = 2.2
var _palettes: Dictionary = {}
## Matière par kind d'ennemi (cache, balance.cfg [hit_fx]).
static var _material_cache: Dictionary = {}
static var _material_cfg_loaded: bool = false
static var _material_by_sfx: Dictionary = {}
static var _material_by_kind: Dictionary = {}


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
	low_gravity_fx_mult = Balance.get_float("low_gravity", "fx_gravity_mult", 0.15)
	hit_marker = bool(Balance.get_value("hit_fx", "hit_marker", true))
	hit_marker_size = Balance.get_float("hit_fx", "hit_marker_size", 10.0)
	hit_marker_life = Balance.get_float("hit_fx", "hit_marker_life", 0.16)
	hit_marker_color = Balance.get_value("hit_fx", "hit_marker_color", hit_marker_color)
	hit_marker_kill_color = Balance.get_value("hit_fx", "hit_marker_kill_color", hit_marker_kill_color)
	hit_flash_size = Balance.get_float("hit_fx", "hit_flash_size", 20.0)
	kick_per_recoil = Balance.get_float("hit_fx", "kick_per_recoil", 0.7)
	kick_max_px = Balance.get_float("hit_fx", "kick_max_px", 6.0)
	wall_mark_life = Balance.get_float("hit_fx", "wall_mark_life", 3.0)
	wall_mark_size = Balance.get_float("hit_fx", "wall_mark_size", 2.2)
	_palettes.clear()
	for m: StringName in [MAT_ORGANIC, MAT_METAL, MAT_HARD, MAT_ALIEN, MAT_ICE, MAT_ETHEREAL]:
		var c: Variant = Balance.get_value("hit_fx", "%s_colors" % m, null)
		_palettes[m] = c if c is Array and (c as Array).size() >= 2 else [Color(0.75, 0.12, 0.1), Color(1.0, 0.86, 0.6)]


## Matière d'impact de `target` : [hit_fx] kind_material (kind -> matière), sinon d'après le son de
## blessure (sfx_material : metal_impact -> metal, hit_heavy -> hard...), sinon organique. Les
## tourelles sont en métal.
static func material_of(target: Object) -> StringName:
	if target == null:
		return MAT_ORGANIC
	if target is Turret or target is EnemyHazard.TurretBody:
		return MAT_METAL
	var d: Variant = target.get("data")
	if not (d is EnemyData):
		return MAT_ORGANIC
	var ed := d as EnemyData
	if _material_cache.has(ed.kind):
		return _material_cache[ed.kind]
	_load_material_cfg()
	var m: StringName = MAT_ORGANIC
	if _material_by_kind.has(String(ed.kind)):
		m = StringName(str(_material_by_kind[String(ed.kind)]))
	elif _material_by_sfx.has(String(ed.get_sfx_hurt())):
		m = StringName(str(_material_by_sfx[String(ed.get_sfx_hurt())]))
	_material_cache[ed.kind] = m
	return m


static func _load_material_cfg() -> void:
	if _material_cfg_loaded:
		return
	_material_cfg_loaded = true
	var by_sfx: Variant = Balance.get_value("hit_fx", "sfx_material", {})
	var by_kind: Variant = Balance.get_value("hit_fx", "kind_material", {})
	_material_by_sfx = by_sfx if by_sfx is Dictionary else {}
	_material_by_kind = by_kind if by_kind is Dictionary else {}


## Vide le cache des matières (tests, rechargement de balance.cfg).
static func reset_material_cache() -> void:
	_material_cache.clear()
	_material_cfg_loaded = false


## Amplitude (px) du léger à-coup visuel d'un ennemi touché, d'après le recul de l'arme.
func hit_kick_px(recoil_px: float) -> float:
	return clampf(recoil_px * kick_per_recoil, 0.0, kick_max_px)


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
	if wall_mark_life > 0.0:
		# Petit impact de balle qui reste quelques secondes contre le mur.
		ground.emit(FxLayer.Kind.SCORCH, pos, Vector2.ZERO, wall_mark_life, wall_mark_size, wall_mark_size,
			Color(0.06, 0.05, 0.05, 0.75))
	_play_impact_sfx(&"bullet_impact", pos)


## Impact sur ennemi au point de contact `pos` : éclair blanc, gerbe à la matière de la cible
## (étincelles et éclats pour le métal, giclée pour l'organique, poussière pour la pierre...),
## hit-marker (rouge si le coup tue) et numéro de dégâts flottant (cumulé par cible `target_id`
## sur une courte fenêtre : une salve de plombs = un seul chiffre).
func impact_enemy(pos: Vector2, dir: Vector2, amount: float, show_number: bool = true, target_id: int = 0,
		material: StringName = MAT_ORGANIC, killed: bool = false) -> void:
	var pal: Array = _palettes.get(material, _palettes.get(MAT_ORGANIC, [Color.RED, Color.WHITE]))
	var main: Color = pal[0]
	var accent: Color = pal[1]
	air.emit(FxLayer.Kind.FLASH, pos, Vector2.ZERO, 0.07, hit_flash_size * 0.45, hit_flash_size,
		Color(1.0, 0.97, 0.9, 0.9))
	var n: int = count(enemy_spray_count)
	match material:
		MAT_METAL:
			# Gerbe d'étincelles renvoyée vers le tireur + éclats sombres qui retombent.
			for i: int in n + 2:
				var v: Vector2 = (-dir).rotated(randf_range(-1.3, 1.3)) * randf_range(160.0, 380.0)
				air.emit(FxLayer.Kind.SPARK, pos, v, randf_range(0.1, 0.22), randf_range(1.4, 2.2), 1.0,
					accent if i % 3 != 0 else Color(1, 1, 1, 0.95))
			for i: int in count(2, 1):
				var v2: Vector2 = dir.rotated(randf_range(-1.0, 1.0)) * randf_range(60.0, 150.0)
				air.emit(FxLayer.Kind.DEBRIS, pos, v2, randf_range(0.35, 0.55), randf_range(2.0, 3.0), 2.0,
					main, randf_range(6.0, 16.0), randf_range(80.0, 170.0), randf() * TAU, randf_range(-14.0, 14.0))
		MAT_HARD, MAT_ICE:
			# Éclats + petit nuage de poussière (pierre, os, carapace, glace).
			for i: int in n:
				var v: Vector2 = (-dir).rotated(randf_range(-1.2, 1.2)) * randf_range(90.0, 220.0)
				air.emit(FxLayer.Kind.DEBRIS, pos, v, randf_range(0.3, 0.5), randf_range(1.6, 2.8), 1.6,
					main if i % 2 != 0 else accent, randf_range(6.0, 16.0), randf_range(60.0, 150.0),
					randf() * TAU, randf_range(-12.0, 12.0))
			air.emit(FxLayer.Kind.DUST, pos, -dir * 25.0, 0.4, 4.0, 11.0, Color(main, 0.45))
		MAT_ETHEREAL:
			for i: int in n:
				var v: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(50.0, 150.0)
				air.emit(FxLayer.Kind.SPARK, pos, v, randf_range(0.18, 0.32), randf_range(1.6, 2.6), 1.0,
					main if i % 2 != 0 else accent)
			air.emit(FxLayer.Kind.RING, pos, Vector2.ZERO, 0.18, 4.0, 16.0, Color(main, 0.7), 0.0, 0.0, 2.0)
		_:
			# Organique / alien : giclée dans le sens du tir (sortie), quelques étincelles.
			for i: int in n:
				var v: Vector2 = dir.rotated(randf_range(-0.7, 0.7)) * randf_range(90.0, 240.0)
				if i % 3 != 2:
					air.emit(FxLayer.Kind.DROPLET, pos, v * 0.6, randf_range(0.3, 0.5), randf_range(1.6, 2.8), 1.2,
						main, randf_range(4.0, 14.0), randf_range(60.0, 160.0))
				else:
					air.emit(FxLayer.Kind.SPARK, pos, v, randf_range(0.1, 0.2), 1.8, 1.0, accent)
	if hit_marker:
		air.emit(FxLayer.Kind.HITMARK, pos, Vector2.ZERO, hit_marker_life * (1.6 if killed else 1.0),
			hit_marker_size, hit_marker_size * (1.7 if killed else 1.3),
			hit_marker_kill_color if killed else hit_marker_color)
	if show_number:
		damage_number(pos + Vector2(0.0, -30.0), amount, false, target_id)


## Affixe d'arme déclenché (onde de choc, ricochet, brûlure, gel) : anneau + éclat à la couleur
## de l'affixe, sans son ni secousse (peut se répéter à chaque balle).
func affix_pulse(pos: Vector2, radius: float, color: Color) -> void:
	var r: float = maxf(radius, 8.0)
	air.emit(FxLayer.Kind.RING, pos, Vector2.ZERO, 0.22, r * 0.2, r, Color(color, 0.85), 0.0, 0.0, 3.0)
	air.emit(FxLayer.Kind.FLASH, pos, Vector2.ZERO, 0.08, r * 0.15, r * 0.35, Color(color, 0.6))
	for i: int in count(3, 1):
		var v: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60.0, 160.0)
		air.emit(FxLayer.Kind.SPARK, pos, v, randf_range(0.1, 0.2), 1.6, 1.0, color)


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
## `low_g` : gravité faible (la douille dérive longtemps).
func shell(ground_pos: Vector2, z: float, dir: Vector2, big: bool, low_g: bool = false) -> void:
	var side: Vector2 = Vector2(-dir.y, dir.x)
	if side.y > 0.0:
		side = -side  # éjection vers le haut de l'écran (lisible), puis retombe
	var v: Vector2 = (side * randf_range(70.0, 120.0) - dir * randf_range(10.0, 40.0))
	var col: Color = Color(0.9, 0.22, 0.15) if big else Color(1.0, 0.8, 0.3)
	# Couche « air » : la douille part de la main, devant le corps.
	var life: float = randf_range(1.1, 1.6) * (2.0 if low_g else 1.0)
	var i: int = air.emit(FxLayer.Kind.SHELL, ground_pos, v, life, 6.5 if big else 4.5, 0.0, col,
		z, randf_range(140.0, 230.0), randf_range(0.0, TAU), randf_range(-24.0, 24.0))
	if low_g:
		air.set_gravity(i, low_gravity_fx_mult)


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
	var low_g: bool = LowGravity.is_at(get_tree(), pos)
	for i: int in count(explosion_debris, 3):
		var v: Vector2 = Vector2.RIGHT.rotated(randf() * TAU) * randf_range(80.0, 260.0)
		var di: int = ground.emit(FxLayer.Kind.DEBRIS, pos, v, randf_range(0.8, 1.3), randf_range(2.5, 4.5), 0.0,
			Color(0.36, 0.27, 0.2).lerp(Color(0.6, 0.48, 0.32), randf()), 6.0, randf_range(150.0, 320.0),
			randf() * TAU, randf_range(-14.0, 14.0))
		if low_g:
			ground.set_gravity(di, low_gravity_fx_mult)
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
