class_name Turret
extends StaticBody2D
## Tourelle immobile fixée à un mur (CONVENTIONS « Refonte Exfil Rush », ligne Tourelles).
## Données : TurretData (data/turrets/*.tres) ; réglages globaux et échelle par difficulté :
## balance.cfg [turrets]. Placement : TurretPlacer (scripts/dungeon/turret_placer.gd).
##
## Origine du nœud = point au sol devant le mur (bord du mur + saillie du bras), dans la salle :
## sert au tri en Y, au brouillard (groupe fog_hideable), au raycast de ligne de vue et au départ
## des projectiles. `normal` = direction mur → salle ; le cône de tir est centré dessus.
##
## Comportement (machine à états compacte, tout en _physics_process quand la tourelle est éveillée) :
##   SCAN     : la tête balaie lentement son cône.
##   TRACK    : joueur repéré (portée + cône + ligne de vue, test toutes les perception_interval s,
##              jamais si le joueur est caché) : la tête pivote vers lui (turn_speed_deg) ;
##              les ennemis voisins sont alertés (Enemy.receive_alert).
##   LOCK     : tête alignée → laser de visée (télégraphe) pendant lock_time.
##   FIRE     : rafale de burst_count tirs (pool de projectiles ennemis), éclair et recul du canon.
##   COOLDOWN : pause, puis nouveau verrouillage ou retour au balayage (mémoire lose_sight_memory).
##   DEAD     : explosion, débris, épave noircie qui reste au mur (plus de collision).
##
## Performance : aucun redessin par frame (laser, éclair, recul = transformations de nœuds dessinés
## une fois ; tête = changement de vignette d'une planche Blender), un seul raycast par perception,
## tourelle endormie (physics coupée) au-delà de sleep_distance du joueur (Timer 2 Hz).

signal destroyed(turret: Turret)
signal fired(direction: Vector2)
signal state_changed(state: int)

enum State { SCAN, TRACK, LOCK, FIRE, COOLDOWN, DEAD }
const STATE_NAMES := ["Balayage", "Poursuite", "Verrouillage", "Tir", "Recharge", "Détruite"]

const LAYER_ENEMIES := 4
const MASK_WORLD := 1
const GROUP_TURRETS := &"turrets"
const GROUP_HIDEABLE := &"fog_hideable"
## Ordre des vignettes du socle (normale du mur vers la salle) : cf. build_turrets.py ORIENT.
const ORIENTS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]
## Hauteur d'affichage des projectiles ennemis (EnemyProjectile.DEFAULT_VISUAL_HEIGHT).
const SHOT_HEIGHT := 28.0
## Saillie par défaut (unités monde) si les métadonnées du sprite manquent.
const DEFAULT_ARM := 14.0

var data: TurretData = null
var difficulty: int = 2
## Direction mur → salle (une des 4 directions cardinales).
var normal: Vector2i = Vector2i.DOWN
## Case du mur porteur.
var cell: Vector2i = Vector2i.ZERO
var max_hp: float = 1.0
var hp: float = 1.0
var state: int = State.SCAN
var can_see_player: bool = false
## Dernière position connue du joueur (vu ou tireur).
var target_position: Vector2 = Vector2.ZERO
## Angle absolu (rad) du canon, toujours dans le cône.
var aim_angle: float = 0.0
## Progression du verrouillage 0..1.
var lock_progress: float = 0.0
var asleep: bool = false

# Réglages [turrets]
var perception_interval: float = 0.12
var lose_sight_memory: float = 0.6
var lock_tolerance: float = deg_to_rad(10.0)
var sleep_distance: float = 1500.0
var wake_distance: float = 1300.0
var alert_cooldown: float = 4.0
var recoil_px: float = 5.0
var recoil_return: float = 0.09
var muzzle_flash_time: float = 0.06
var hit_flash_time: float = 0.08
var health_bar_width: float = 44.0

var _alive: bool = true
var _player: Node2D = null
var _ray: PhysicsRayQueryParameters2D = null
var _perception_left: float = 0.0
var _unseen: float = 999.0
var _timer: float = 0.0
var _shots_left: int = 0
var _scan_dir: float = 1.0
var _alert_left: float = 0.0
var _recoil: float = 0.0
var _flash_left: float = 0.0
var _hit_left: float = 0.0
var _base_angle: float = PI * 0.5
var _half_cone: float = PI / 3.0
var _arm: float = DEFAULT_ARM
var _barrel: float = 28.0
var _world_per_px: float = 0.41
var _head_frames: int = 32
var _head_frame: int = -1
var _muzzle_px: Array = []
var _head_pivot_px: Vector2 = Vector2(80, 80)
var _head_home: Vector2 = Vector2.ZERO
var _shape: CollisionShape2D = null
var _base: Sprite2D = null
var _head: Sprite2D = null
var _laser: Node2D = null
var _laser_dot: Node2D = null
var _flash: Node2D = null
var _health_bar: Node2D = null
var _debug: Node2D = null
var _sleep_timer: Timer = null
var _raid: WeakRef = null
var _floor_index: int = 0

static var _meta_cache: Dictionary = {}
static var _soft_tex: Texture2D = null


## Instancie une tourelle prête à être ajoutée à l'arbre, déjà positionnée devant le mur `wall_cell`.
static func create(turret_data: TurretData, wall_normal: Vector2i, wall_cell: Vector2i, p_difficulty: int = 2) -> Turret:
	var t := Turret.new()
	t.data = turret_data
	t.normal = wall_normal
	t.cell = wall_cell
	t.difficulty = p_difficulty
	t.name = "Turret_%d_%d" % [wall_cell.x, wall_cell.y]
	t.position = mount_position(wall_cell, wall_normal, arm_of(turret_data))
	t.set_meta(&"turret_cell", wall_cell)
	return t


## Point au sol devant le mur : bord de la case mur côté salle + saillie du bras.
static func mount_position(wall_cell: Vector2i, wall_normal: Vector2i, arm: float = DEFAULT_ARM) -> Vector2:
	var ts := float(FloorLayout.TILE_SIZE)
	return FloorLayout.cell_to_world(wall_cell) + Vector2(wall_normal) * (ts * 0.5 + arm)


static func arm_of(d: TurretData) -> float:
	var m := sprite_meta(d.sprite_id) if d != null else {}
	return float(m.get("arm_world", DEFAULT_ARM))


## Métadonnées du rendu Blender (<sprite_id>.json), mises en cache. {} si absentes.
static func sprite_meta(sprite_id: String) -> Dictionary:
	if _meta_cache.has(sprite_id):
		return _meta_cache[sprite_id]
	var out: Dictionary = {}
	var path := TurretData.SPRITE_DIR + sprite_id + ".json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			out = parsed
	_meta_cache[sprite_id] = out
	return out


func _ready() -> void:
	if data == null:
		push_warning("Turret %s : aucune TurretData, valeurs par défaut." % name)
		data = TurretData.new()
	if not has_meta(&"turret_cell"):
		set_meta(&"turret_cell", cell)
	_load_balance()
	_apply_difficulty()
	_base_angle = Vector2(normal).angle()
	_half_cone = deg_to_rad(clampf(data.cone_deg, 10.0, 180.0)) * 0.5
	aim_angle = _base_angle
	target_position = global_position
	_perception_left = randf() * perception_interval
	_scan_dir = 1.0 if (cell.x + cell.y) % 2 == 0 else -1.0

	collision_layer = LAYER_ENEMIES
	collision_mask = 0
	for g: StringName in [&"enemies", &"damageable", &"enemy_units", GROUP_HIDEABLE, GROUP_TURRETS]:
		add_to_group(g)
	_ray = PhysicsRayQueryParameters2D.new()
	_ray.collision_mask = MASK_WORLD
	_ray.collide_with_areas = false
	_ray.exclude = [get_rid()]

	_shape = CollisionShape2D.new()
	_shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = data.body_radius
	_shape.shape = circle
	add_child(_shape)

	_build_visual()
	_build_fx()
	_build_health_bar()
	_build_sleep_timer()
	_debug = DebugCone.new()
	_debug.set("turret", self)
	_debug.name = "Debug"
	_debug.z_index = 60
	add_child(_debug)
	EventBus.debug_toggled.connect(_on_debug_toggled)
	_on_debug_toggled(GameState.debug_enabled)
	_apply_head_frame()


func _load_balance() -> void:
	perception_interval = maxf(_bf("perception_interval", perception_interval), 0.1)
	lose_sight_memory = _bf("lose_sight_memory", lose_sight_memory)
	lock_tolerance = deg_to_rad(_bf("lock_tolerance_deg", 10.0))
	sleep_distance = _bf("sleep_distance", sleep_distance)
	wake_distance = minf(_bf("wake_distance", wake_distance), sleep_distance)
	alert_cooldown = _bf("alert_cooldown", alert_cooldown)
	recoil_px = _bf("recoil_px", recoil_px)
	recoil_return = maxf(_bf("recoil_return", recoil_return), 0.01)
	muzzle_flash_time = _bf("muzzle_flash_time", muzzle_flash_time)
	hit_flash_time = _bf("hit_flash_time", hit_flash_time)
	health_bar_width = _bf("health_bar_width", health_bar_width)


static func _bf(key: String, default: float) -> float:
	return Balance.get_float("turrets", key, default)


## Multiplicateur de difficulté (tableau [turrets] key indexé par la difficulté 0..4).
static func difficulty_mult(key: String, diff: int) -> float:
	var v: Variant = Balance.get_value("turrets", key, [])
	if v is Array and not (v as Array).is_empty():
		var a: Array = v
		return float(a[clampi(diff, 0, a.size() - 1)])
	return 1.0


## Copie de `data` mise à l'échelle de la difficulté (la ressource partagée n'est jamais modifiée).
func _apply_difficulty() -> void:
	if not data.has_meta(&"difficulty_scaled"):
		var d := data.duplicate() as TurretData
		d.max_hp = data.max_hp * difficulty_mult("hp_mult", difficulty) * Enemy.world_mult("hp_mult")
		d.damage = data.damage * difficulty_mult("damage_mult", difficulty) * Enemy.world_mult("damage_mult")
		d.lock_time = data.lock_time * difficulty_mult("lock_time_mult", difficulty)
		d.cooldown = data.cooldown * difficulty_mult("cooldown_mult", difficulty)
		d.set_meta(&"difficulty_scaled", true)
		data = d
	max_hp = data.max_hp
	hp = max_hp


## Modificateurs de carte (même signature qu'Enemy.apply_modifiers ; vitesse ignorée,
## la vigilance raccourcit le verrouillage). Une seule application.
func apply_modifiers(hp_mult: float, damage_mult: float, _speed_mult: float, awareness_mult: float) -> void:
	if data == null or data.has_meta(&"map_modified"):
		return
	var ratio := clampf(hp / maxf(max_hp, 0.001), 0.0, 1.0)
	var d := data.duplicate() as TurretData
	d.max_hp = data.max_hp * maxf(hp_mult, 0.05)
	d.damage = data.damage * maxf(damage_mult, 0.0)
	d.lock_time = data.lock_time / maxf(awareness_mult, 0.2)
	d.set_meta(&"difficulty_scaled", true)
	d.set_meta(&"map_modified", true)
	data = d
	max_hp = d.max_hp
	hp = max_hp * ratio
	refresh_health_bar()


## Lien vers le raid (mémoire des tourelles détruites/endommagées par étage, cf. TurretPlacer).
func bind_raid(raid: Node, floor_index: int) -> void:
	_raid = weakref(raid) if raid != null else null
	_floor_index = floor_index


# --- Visuel ---------------------------------------------------------------------------

func _orient_index() -> int:
	var i := ORIENTS.find(normal)
	return maxi(i, 0)


func _build_visual() -> void:
	var meta := sprite_meta(data.sprite_id)
	var base_tex: Texture2D = null
	var head_tex: Texture2D = null
	if not meta.is_empty() and ResourceLoader.exists(data.base_path()) and ResourceLoader.exists(data.head_path()):
		base_tex = load(data.base_path()) as Texture2D
		head_tex = load(data.head_path()) as Texture2D
	if base_tex == null or head_tex == null:
		_build_fallback_visual()
		return
	var o := _orient_index()
	_world_per_px = float(meta.get("world_per_px", 0.41))
	_arm = float(meta.get("arm_world", DEFAULT_ARM))
	_barrel = float(meta.get("barrel_world", 28.0))
	_head_frames = int(meta.get("head_frames", 32))
	_muzzle_px = meta.get("muzzle", [])
	var hp_px: Array = meta.get("head_pivot", [80, 80])
	_head_pivot_px = Vector2(float(hp_px[0]), float(hp_px[1]))
	var bf: Array = meta.get("base_frame", [192, 192])
	var anchor: Array = (meta.get("anchor", []) as Array)[o] if (meta.get("anchor", []) as Array).size() > o else [96, 132]
	var pivot: Array = (meta.get("pivot", []) as Array)[o] if (meta.get("pivot", []) as Array).size() > o else [96, 86]
	# Point au sol sous la tête = origine du nœud (le rendu fixe la saillie exacte du bras).
	var front: Array = (meta.get("front", []) as Array)[o] if (meta.get("front", []) as Array).size() > o else anchor
	var s := _world_per_px
	var front_px := Vector2(float(front[0]), float(front[1]))

	_base = Sprite2D.new()
	_base.name = "Base"
	_base.texture = base_tex
	_base.hframes = 4
	_base.frame = o
	_base.scale = Vector2(s, s)
	_base.position = Vector2.ZERO
	_base.offset = Vector2(float(bf[0]), float(bf[1])) * 0.5 - front_px
	add_child(_base)

	var cols := int(meta.get("head_cols", 8))
	_head = Sprite2D.new()
	_head.name = "Head"
	_head.texture = head_tex
	_head.hframes = cols
	_head.vframes = maxi(_head_frames / maxi(cols, 1), 1)
	_head.scale = Vector2(s, s)
	var hf := float(meta.get("head_frame", 192))
	_head.offset = Vector2(hf, hf) * 0.5 - _head_pivot_px
	_head_home = (Vector2(float(pivot[0]), float(pivot[1])) - front_px) * s
	_head.position = _head_home
	add_child(_head)


## Repli (sprites absents) : socle et tête dessinés une fois en code.
func _build_fallback_visual() -> void:
	_arm = DEFAULT_ARM
	_barrel = 26.0
	var fb := FallbackBase.new()
	fb.set("normal", normal)
	fb.set("arm", _arm)
	fb.name = "Base"
	add_child(fb)
	_head_home = Vector2(0, -26)
	_head = null
	var fh := FallbackHead.new()
	fh.name = "HeadFallback"
	fh.position = _head_home
	add_child(fh)
	_debug_fallback_head = fh


var _debug_fallback_head: Node2D = null


func _build_fx() -> void:
	_laser = Beam.new()
	_laser.name = "Laser"
	_laser.z_index = 2
	_laser.visible = false
	_laser.modulate = data.laser_color
	add_child(_laser)
	_laser_dot = Dot.new()
	_laser_dot.name = "LaserDot"
	_laser_dot.z_index = 2
	_laser_dot.visible = false
	_laser_dot.modulate = data.laser_color
	add_child(_laser_dot)
	_flash = MuzzleFlash.new()
	_flash.name = "MuzzleFlash"
	_flash.z_index = 3
	_flash.visible = false
	_flash.modulate = data.flash_color
	_flash.scale = Vector2.ONE * data.muzzle_flash_scale
	add_child(_flash)


func _build_health_bar() -> void:
	_health_bar = HealthBar.new()
	_health_bar.name = "HealthBar"
	_health_bar.set("turret", self)
	_health_bar.z_index = 5
	_health_bar.position = _head_home + Vector2(0, -30)
	_health_bar.visible = false
	add_child(_health_bar)


func _build_sleep_timer() -> void:
	_sleep_timer = Timer.new()
	_sleep_timer.name = "SleepTimer"
	_sleep_timer.wait_time = maxf(_bf("sleep_check_interval", 0.5), 0.05)
	add_child(_sleep_timer)
	_sleep_timer.timeout.connect(_on_sleep_check)
	_sleep_timer.start(randf_range(0.05, _sleep_timer.wait_time))


## Vignette de la tête correspondant à aim_angle (mise à jour seulement si elle change).
func _apply_head_frame() -> void:
	var k := posmod(roundi(aim_angle / TAU * float(_head_frames)), _head_frames)
	if k != _head_frame:
		_head_frame = k
		if _head != null:
			_head.frame = k
	var head_pos := _head_home - Vector2.from_angle(aim_angle) * _recoil
	if _head != null:
		_head.position = head_pos
	elif _debug_fallback_head != null:
		_debug_fallback_head.position = head_pos
		_debug_fallback_head.rotation = aim_angle


## Position (locale) de la bouche du canon à l'écran (vignette courante, recul compris).
func get_muzzle_local() -> Vector2:
	var head_pos := _head_home - Vector2.from_angle(aim_angle) * _recoil
	if _head != null and _head_frame >= 0 and _head_frame < _muzzle_px.size():
		var m: Array = _muzzle_px[_head_frame]
		return head_pos + (Vector2(float(m[0]), float(m[1])) - _head_pivot_px) * _world_per_px
	return head_pos + Vector2.from_angle(aim_angle) * _barrel


## Hauteur d'affichage des tirs (hauteur du canon au-dessus du sol).
func get_shot_height() -> float:
	return maxf(-_head_home.y, SHOT_HEIGHT)


## Point de départ logique des projectiles (au sol, au bout du canon).
func get_shot_origin() -> Vector2:
	return global_position + Vector2.from_angle(aim_angle) * _barrel


# --- Boucle ----------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _alive:
		return
	_alert_left = maxf(_alert_left - delta, 0.0)
	_perception_left -= delta
	if _perception_left <= 0.0:
		_perception_left = perception_interval
		update_perception()
	if can_see_player:
		_unseen = 0.0
	else:
		_unseen += delta
	var has_target := can_see_player or _unseen <= lose_sight_memory
	match state:
		State.SCAN:
			_scan(delta)
			if can_see_player:
				_on_spotted()
				_set_state(State.TRACK)
		State.TRACK:
			if not has_target:
				_set_state(State.SCAN)
			else:
				var err := _turn_toward(target_position, delta)
				if can_see_player and err <= lock_tolerance:
					_start_lock()
		State.LOCK:
			if not has_target:
				_stop_laser()
				_set_state(State.SCAN)
			else:
				_turn_toward(target_position, delta)
				if can_see_player:
					lock_progress = minf(lock_progress + delta / maxf(data.lock_time, 0.01), 1.0)
				_update_laser()
				if lock_progress >= 1.0:
					_stop_laser()
					_shots_left = maxi(data.burst_count, 1)
					_timer = 0.0
					_set_state(State.FIRE)
		State.FIRE:
			if data.track_while_firing and has_target:
				_turn_toward(target_position, delta)
			_timer -= delta
			if _timer <= 0.0:
				_fire_shot()
				_shots_left -= 1
				_timer = data.burst_interval
				if _shots_left <= 0:
					_timer = data.cooldown
					_set_state(State.COOLDOWN)
		State.COOLDOWN:
			if has_target:
				_turn_toward(target_position, delta)
			_timer -= delta
			if _timer <= 0.0:
				if can_see_player:
					_set_state(State.TRACK)
				elif has_target:
					_set_state(State.TRACK)
				else:
					_set_state(State.SCAN)
	_update_fx(delta)
	_apply_head_frame()


func _set_state(s: int) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)
	if _debug != null and _debug.visible:
		_debug.queue_redraw()


func _scan(delta: float) -> void:
	var rel := wrapf(aim_angle - _base_angle, -PI, PI)
	var limit := _half_cone * 0.85
	rel += _scan_dir * deg_to_rad(data.scan_speed_deg) * delta
	if rel > limit:
		rel = limit
		_scan_dir = -1.0
	elif rel < -limit:
		rel = -limit
		_scan_dir = 1.0
	aim_angle = _base_angle + rel


## Pivote vers `pos` (limité au cône). Renvoie l'écart angulaire restant (rad, ≥ 0).
func _turn_toward(pos: Vector2, delta: float) -> float:
	var to := pos - global_position
	if to.length_squared() < 1.0:
		return 0.0
	var want := clampf(wrapf(to.angle() - _base_angle, -PI, PI), -_half_cone, _half_cone)
	var rel := wrapf(aim_angle - _base_angle, -PI, PI)
	var step := deg_to_rad(data.turn_speed_deg) * delta
	rel = move_toward(rel, want, step)
	aim_angle = _base_angle + rel
	return absf(wrapf(to.angle() - aim_angle, -PI, PI))


func _start_lock() -> void:
	lock_progress = 0.0
	_set_state(State.LOCK)
	_laser.visible = true
	_laser_dot.visible = true
	_update_laser()


func _stop_laser() -> void:
	if _laser != null:
		_laser.visible = false
		_laser_dot.visible = false


## Laser de visée : de la bouche du canon, dans l'axe du canon, jusqu'à la cible (hauteur de tir).
## Transformations seulement (le trait est dessiné une fois).
func _update_laser() -> void:
	var start := get_muzzle_local()
	var dist := minf(global_position.distance_to(target_position), data.range)
	var end_ground := Vector2.from_angle(aim_angle) * dist
	var end := end_ground + Vector2(0, -get_shot_height())
	var v := end - start
	_laser.position = start
	_laser.rotation = v.angle()
	var pulse := 0.55 + 0.45 * lock_progress
	_laser.scale = Vector2(v.length(), 0.6 + 1.2 * lock_progress)
	_laser.modulate.a = pulse
	_laser_dot.position = end
	_laser_dot.scale = Vector2.ONE * (0.6 + 0.8 * lock_progress)


func _update_fx(delta: float) -> void:
	if _recoil > 0.0:
		_recoil = maxf(_recoil - recoil_px * delta / recoil_return, 0.0)
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.visible = false
		else:
			_flash.position = get_muzzle_local()
	if _hit_left > 0.0:
		_hit_left -= delta
		if _hit_left <= 0.0:
			_set_hit_tint(false)


# --- Perception --------------------------------------------------------------------------

func get_player() -> Node2D:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = null
		var p: Node2D = GameState.player
		if is_instance_valid(p) and p.is_inside_tree() and p.is_in_group(&"player"):
			_player = p
		elif is_inside_tree():
			_player = get_tree().get_first_node_in_group(&"player") as Node2D
	if _player == null:
		return null
	if _player.has_method(&"is_alive") and not bool(_player.call(&"is_alive")):
		return null
	return _player


## Le point est-il dans le cône de la tourelle (centré sur la normale du mur) ?
func is_in_cone(pos: Vector2) -> bool:
	var to := pos - global_position
	if to.length_squared() < 1.0:
		return true
	return absf(wrapf(to.angle() - _base_angle, -PI, PI)) <= _half_cone


func has_line_of_sight_to(pos: Vector2) -> bool:
	if not is_inside_tree():
		return false
	_ray.from = global_position
	_ray.to = pos
	return get_world_2d().direct_space_state.intersect_ray(_ray).is_empty()


## Évalue la vue (portée, cône, joueur non caché, puis UN raycast). Appelé toutes les
## perception_interval s (≥ 0,1 s), jamais à chaque frame.
func update_perception() -> bool:
	can_see_player = false
	var p := get_player()
	if p == null or not _alive:
		return false
	if p.has_method(&"is_hidden") and bool(p.call(&"is_hidden")):
		return false
	var ppos := p.global_position
	if global_position.distance_squared_to(ppos) > data.range * data.range:
		return false
	if not is_in_cone(ppos):
		return false
	if not has_line_of_sight_to(ppos):
		return false
	# Fumée (SmokeField) : la tourelle ne voit pas à travers.
	if SmokeField.blocks_line(global_position, ppos):
		return false
	can_see_player = true
	target_position = ppos
	return true


func _on_spotted() -> void:
	_wake()
	if _alert_left <= 0.0:
		_alert_left = alert_cooldown
		alert_neighbors(target_position)


## Prévient les ennemis vivants dans alert_neighbors_radius (comme Enemy.alert_neighbors).
func alert_neighbors(pos: Vector2) -> int:
	if not is_inside_tree() or data.alert_neighbors_radius <= 0.0:
		return 0
	var r2 := data.alert_neighbors_radius * data.alert_neighbors_radius
	var count := 0
	for n: Node in get_tree().get_nodes_in_group(&"enemy_units"):
		if n == self or not (n is Enemy):
			continue
		var e := n as Enemy
		if e.is_alive() and global_position.distance_squared_to(e.global_position) <= r2 and e.receive_alert(pos):
			count += 1
	return count


# --- Tir -----------------------------------------------------------------------------------

func _fire_shot() -> void:
	var pool := EnemyProjectilePool.get_or_create(get_tree())
	if pool == null:
		return
	var dir := Vector2.from_angle(aim_angle)
	var origin := get_shot_origin()
	var life := data.range / maxf(data.projectile_speed, 1.0) * 1.1
	var n := maxi(data.pellets, 1)
	var spread := deg_to_rad(data.spread_deg)
	for i: int in n:
		var d := dir
		if n > 1:
			d = dir.rotated(spread * (float(i) / float(n - 1) - 0.5))
		elif spread > 0.0:
			d = dir.rotated(randf_range(-0.5, 0.5) * spread)
		var p := pool.spawn(origin, d, data.projectile_speed, data.damage, self, life, data.projectile_style)
		if p == null:
			continue
		# Trajectoire au sol, dessin à la hauteur du canon (relancé à la hauteur par défaut par le pool).
		# (le décalage de dessin est dans le repère local du projectile : divisé par son échelle).
		p.visual_height = get_shot_height() / maxf(data.projectile_scale, 0.1)
		p.queue_redraw()
		if not is_equal_approx(data.projectile_scale, 1.0):
			p.scale = Vector2.ONE * data.projectile_scale
			p.released.connect(_reset_projectile_scale, CONNECT_ONE_SHOT)
	_recoil = recoil_px
	_flash_left = muzzle_flash_time
	_flash.visible = true
	_flash.rotation = aim_angle
	_flash.position = get_muzzle_local()
	_play_sfx(data.shot_sfx)
	fired.emit(dir)


static func _reset_projectile_scale(p: Node2D) -> void:
	if is_instance_valid(p):
		p.scale = Vector2.ONE


func _play_sfx(sfx: StringName) -> void:
	if sfx == &"" or not is_inside_tree():
		return
	var am := get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method(&"play_sfx"):
		am.call(&"play_sfx", sfx, global_position)


# --- Dégâts --------------------------------------------------------------------------------

func take_damage(amount: float, source: Node) -> void:
	if not _alive or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_hit_left = hit_flash_time
	_set_hit_tint(true)
	refresh_health_bar()
	_save_state()
	if hp <= 0.0:
		_destroy(false)
		return
	# Touchée : se tourne vers le tireur (dans la limite du cône).
	_wake()
	if source is Node2D and is_instance_valid(source):
		target_position = (source as Node2D).global_position
		_unseen = 0.0
		if state == State.SCAN:
			_set_state(State.TRACK)


func is_alive() -> bool:
	return _alive


func is_destroyed() -> bool:
	return not _alive


func _set_hit_tint(on: bool) -> void:
	var c := Color(2.2, 2.0, 1.9) if on else Color.WHITE
	if _base != null:
		_base.self_modulate = c
	if _head != null:
		_head.self_modulate = c


## Destruction : explosion + débris (sauf `silent`, restauration d'un étage), épave au mur.
func _destroy(silent: bool) -> void:
	if not _alive:
		return
	_alive = false
	can_see_player = false
	hp = 0.0
	_stop_laser()
	_flash.visible = false
	_set_hit_tint(false)
	_set_state(State.DEAD)
	for g: StringName in [&"enemies", &"damageable", GROUP_HIDEABLE]:
		remove_from_group(g)
	# L'épave reste comme décor (le brouillard la recouvre comme les murs).
	visible = true
	modulate.a = 1.0
	set_deferred(&"collision_layer", 0)
	if _shape != null:
		_shape.set_deferred(&"disabled", true)
	if _health_bar != null:
		_health_bar.visible = false
	if _sleep_timer != null:
		_sleep_timer.stop()
	set_physics_process(false)
	_show_wreck()
	if _debug != null and _debug.visible:
		_debug.queue_redraw()
	if silent:
		return
	_spawn_explosion()
	_play_sfx(data.destroy_sfx)
	destroyed.emit(self)
	if bool(Balance.get_value("turrets", "drop_loot_on_destroy", false)):
		EventBus.enemy_died.emit(self, global_position + Vector2(normal) * float(FloorLayout.TILE_SIZE) * 0.6)


## Épave immédiate, sans effets ni signal (tourelle déjà détruite lors d'une visite précédente).
func set_destroyed_silently() -> void:
	_destroy(true)


func _show_wreck() -> void:
	if ResourceLoader.exists(data.wreck_path()) and _base != null:
		_base.texture = load(data.wreck_path()) as Texture2D
		if _head != null:
			_head.visible = false
	else:
		if _head != null:
			_head.self_modulate = Color(0.25, 0.22, 0.24)
		if _base != null:
			_base.self_modulate = Color(0.3, 0.27, 0.28)
		if _debug_fallback_head != null:
			_debug_fallback_head.modulate = Color(0.25, 0.22, 0.24)


func _spawn_explosion() -> void:
	var fx := Node2D.new()
	fx.name = "Explosion"
	fx.z_index = 4
	fx.position = _head_home
	add_child(fx)
	var boom := Boom.new()
	boom.modulate = data.flash_color
	fx.add_child(boom)
	var tw := fx.create_tween()
	tw.set_parallel(true)
	boom.scale = Vector2.ONE * 0.3
	tw.tween_property(boom, "scale", Vector2.ONE * 1.7, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(boom, "modulate:a", 0.0, 0.38).set_delay(0.08)
	# Débris (projetés vers la salle, retombent)
	var debris := CPUParticles2D.new()
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = int(_bf("debris_amount", 22.0))
	debris.lifetime = 0.9
	debris.direction = Vector2(normal)
	debris.spread = 75.0
	debris.initial_velocity_min = 120.0
	debris.initial_velocity_max = 280.0
	debris.gravity = Vector2(0, 520)
	debris.angular_velocity_min = -540.0
	debris.angular_velocity_max = 540.0
	debris.scale_amount_min = 2.5
	debris.scale_amount_max = 5.5
	var g := Gradient.new()
	var cols: Array[Color] = data.debris_colors
	if cols.is_empty():
		cols = [Color(0.3, 0.3, 0.36)]
	g.colors = PackedColorArray(cols)
	var offs := PackedFloat32Array()
	for i: int in cols.size():
		offs.append(float(i) / float(maxi(cols.size() - 1, 1)))
	g.offsets = offs
	debris.color_initial_ramp = g
	fx.add_child(debris)
	debris.emitting = true
	# Fumée sombre qui monte
	var smoke := CPUParticles2D.new()
	smoke.one_shot = true
	smoke.explosiveness = 0.7
	smoke.amount = int(_bf("smoke_amount", 10.0))
	smoke.lifetime = 1.3
	smoke.texture = _soft_dot()
	smoke.direction = Vector2(0, -1)
	smoke.spread = 50.0
	smoke.initial_velocity_min = 20.0
	smoke.initial_velocity_max = 60.0
	smoke.gravity = Vector2(0, -30)
	smoke.scale_amount_min = 0.35
	smoke.scale_amount_max = 0.7
	var sr := Gradient.new()
	sr.colors = PackedColorArray([Color(0.16, 0.14, 0.18, 0.75), Color(0.2, 0.2, 0.26, 0.0)])
	smoke.color_ramp = sr
	fx.add_child(smoke)
	smoke.emitting = true
	get_tree().create_timer(1.6).timeout.connect(fx.queue_free)


## Petite texture ronde floue (fumée), créée une fois.
static func _soft_dot() -> Texture2D:
	if _soft_tex != null:
		return _soft_tex
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y: int in n:
		for x: int in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.6))
	_soft_tex = ImageTexture.create_from_image(img)
	return _soft_tex


func refresh_health_bar() -> void:
	if _health_bar == null:
		return
	_health_bar.visible = _alive and hp < max_hp
	_health_bar.queue_redraw()


## Mémorise PV / destruction dans la meta du raid (restaurés par TurretPlacer.spawn_for_floor).
func _save_state() -> void:
	var raid: Node = _raid.get_ref() as Node if _raid != null else null
	if raid == null:
		return
	var all: Dictionary = raid.get_meta(&"turret_states", {})
	var floor_states: Dictionary = all.get(_floor_index, {})
	floor_states[cell] = hp
	all[_floor_index] = floor_states
	raid.set_meta(&"turret_states", all)


# --- Sommeil ---------------------------------------------------------------------------------

func _on_sleep_check() -> void:
	if not _alive:
		return
	var p := get_player()
	var d2 := INF if p == null else global_position.distance_squared_to(p.global_position)
	if asleep:
		if d2 <= wake_distance * wake_distance:
			_wake()
	elif d2 > sleep_distance * sleep_distance and (state == State.SCAN or p == null):
		_sleep()


func _sleep() -> void:
	if asleep or not _alive:
		return
	asleep = true
	can_see_player = false
	_stop_laser()
	_set_state(State.SCAN)
	set_physics_process(false)


func _wake() -> void:
	if not asleep or not _alive:
		return
	asleep = false
	_perception_left = randf() * perception_interval
	set_physics_process(true)


# --- Debug F3 ------------------------------------------------------------------------------

func _on_debug_toggled(enabled: bool) -> void:
	if _debug == null:
		return
	_debug.visible = enabled
	if enabled:
		_debug.queue_redraw()


func get_state_name() -> String:
	return STATE_NAMES[clampi(state, 0, STATE_NAMES.size() - 1)]


func get_debug_info() -> Dictionary:
	return {"id": String(data.id), "state": get_state_name(), "hp": hp, "max_hp": max_hp,
		"sees_player": can_see_player, "asleep": asleep, "cell": cell}


func get_cone_half_angle() -> float:
	return _half_cone


func get_base_angle() -> float:
	return _base_angle


# --- Nœuds dessinés une fois -------------------------------------------------------------------

## Trait de longueur 1 le long de +X (le laser est mis à l'échelle, jamais redessiné).
class Beam extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, -3.0, 1.0, 6.0), Color(1, 1, 1, 0.22))
		draw_rect(Rect2(0, -1.4, 1.0, 2.8), Color(1, 1, 1, 0.55))
		draw_rect(Rect2(0, -0.6, 1.0, 1.2), Color(1.0, 0.95, 0.92, 1.0))


class Dot extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 7.0, Color(1, 1, 1, 0.25))
		draw_circle(Vector2.ZERO, 3.5, Color(1, 1, 1, 0.8))
		draw_circle(Vector2.ZERO, 1.6, Color(1, 1, 1, 1))


class MuzzleFlash extends Node2D:
	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(-2, 0), Vector2(6, -6), Vector2(20, 0), Vector2(6, 6)])
		draw_colored_polygon(pts, Color(1, 1, 1, 0.85))
		draw_circle(Vector2(3, 0), 8.0, Color(1, 1, 1, 0.45))
		draw_circle(Vector2(3, 0), 4.0, Color(1.0, 1.0, 0.92, 1.0))
		draw_line(Vector2(4, 0), Vector2(14, -10), Color(1, 1, 1, 0.6), 2.0, true)
		draw_line(Vector2(4, 0), Vector2(14, 10), Color(1, 1, 1, 0.6), 2.0, true)


class Boom extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 34.0, Color(1, 1, 1, 0.25))
		draw_circle(Vector2.ZERO, 22.0, Color(1, 1, 1, 0.6))
		draw_circle(Vector2.ZERO, 12.0, Color(1.0, 0.98, 0.9, 1.0))
		for i: int in 8:
			var a := TAU * float(i) / 8.0 + 0.2
			draw_line(Vector2.from_angle(a) * 14.0, Vector2.from_angle(a) * 40.0, Color(1, 1, 1, 0.7), 3.0, true)


## Barre de vie discrète (seulement si endommagée), redessinée sur changement de PV.
class HealthBar extends Node2D:
	var turret: Turret = null

	func _draw() -> void:
		if turret == null or not turret.is_alive():
			return
		var w: float = turret.health_bar_width
		var h := 5.0
		var bar := Rect2(Vector2(-w * 0.5, -h), Vector2(w, h))
		var ratio := clampf(turret.hp / maxf(turret.max_hp, 0.01), 0.0, 1.0)
		draw_rect(bar.grow(1.5), Color(0.07, 0.10, 0.18, 0.85))
		draw_rect(bar, Color(0.25, 0.05, 0.07))
		draw_rect(Rect2(bar.position, Vector2(w * ratio, h)), Color(0.95, 0.25, 0.15).lerp(Color(1.0, 0.6, 0.2), 1.0 - ratio))


## Cône et portée (F3). Redessiné au basculement du debug et aux changements d'état.
class DebugCone extends Node2D:
	var turret: Turret = null

	func _draw() -> void:
		if turret == null or turret.data == null:
			return
		var r: float = turret.data.range
		var half: float = turret.get_cone_half_angle()
		var base: float = turret.get_base_angle()
		var col := Color(1.0, 0.3, 0.2) if turret.is_alive() else Color(0.5, 0.5, 0.5)
		var pts := PackedVector2Array([Vector2.ZERO])
		var steps := 24
		for i: int in steps + 1:
			pts.append(Vector2.from_angle(base - half + 2.0 * half * float(i) / float(steps)) * r)
		draw_colored_polygon(pts, Color(col, 0.08))
		pts.append(Vector2.ZERO)
		draw_polyline(pts, Color(col, 0.8), 2.0, true)
		draw_arc(Vector2.ZERO, turret.data.alert_neighbors_radius, 0.0, TAU, 40, Color(1.0, 0.85, 0.3, 0.3), 1.0, true)
		var font := ThemeDB.fallback_font
		var label := "%s [%s] %d/%d" % [String(turret.data.id), turret.get_state_name(), roundi(turret.hp), roundi(turret.max_hp)]
		var at := Vector2(-60, -70)
		draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0.07, 0.1, 0.18))
		draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col.lightened(0.3))


## Repli sans sprite : platine + bras (dessin unique).
class FallbackBase extends Node2D:
	var normal: Vector2i = Vector2i.DOWN
	var arm: float = 14.0

	func _draw() -> void:
		var n := Vector2(normal)
		var wall := -n * arm
		var side := Vector2(-n.y, n.x)
		draw_line(wall + side * 14.0 + Vector2(0, -26), wall - side * 14.0 + Vector2(0, -26), Color(0.2, 0.2, 0.26), 8.0)
		draw_line(wall + Vector2(0, -26), Vector2(0, -26), Color(0.3, 0.3, 0.36), 5.0)


class FallbackHead extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-10, -8, 20, 16), Color(0.45, 0.45, 0.52))
		draw_rect(Rect2(8, -3, 18, 6), Color(0.25, 0.25, 0.3))
		draw_rect(Rect2(-10, -8, 20, 16), Color(0.08, 0.06, 0.1), false, 2.0)
