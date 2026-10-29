extends GutTest
## Tourelles murales : placement (TurretPlacer, sur les 3 générateurs de biome réels) et
## comportement (Turret : dégâts, destruction unique, ligne de vue, joueur caché, cône, tir).

const WORLDS := [
	"res://data/worlds/world_01_far_west.tres",
	"res://data/worlds/world_02_space_station.tres",
	"res://data/worlds/world_03_mall.tres",
]
const SEEDS := [11, 4242]


class TPlayer extends CharacterBody2D:
	var hp: float = 100.0
	var in_hiding: bool = false

	func _ready() -> void:
		add_to_group(&"player")
		add_to_group(&"damageable")
		collision_layer = 2
		collision_mask = 0
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 14.0
		cs.shape = c
		add_child(cs)

	func take_damage(amount: float, _source: Node) -> void:
		hp -= amount

	func is_alive() -> bool:
		return hp > 0.0

	func is_hidden() -> bool:
		return in_hiding

	func get_noise_level() -> float:
		return 0.0


var _world: Node2D
var _player: TPlayer
var _saved_player = null
static var _floors_cache: Dictionary = {}


func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_player = TPlayer.new()
	_player.position = Vector2(9000, 9000)
	_world.add_child(_player)
	_saved_player = GameState.player if is_instance_valid(GameState.player) else null
	GameState.player = _player


func after_each() -> void:
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null


# --- Données -------------------------------------------------------------------------------

func test_catalog_has_types_for_every_biome() -> void:
	for wp: String in WORLDS:
		var w: WorldData = load(wp)
		var types := TurretData.for_biome(w.biome)
		assert_gte(types.size(), 2, "au moins 2 types de tourelle pour %s" % w.biome)
		for d: TurretData in types:
			assert_gt(d.max_hp, 0.0)
			assert_gt(d.range, 0.0)
			assert_gt(d.projectile_speed, 0.0)
			assert_true(ResourceLoader.exists(d.base_path()), "socle %s" % d.base_path())
			assert_true(ResourceLoader.exists(d.head_path()), "tête %s" % d.head_path())
			assert_true(ResourceLoader.exists(d.wreck_path()), "épave %s" % d.wreck_path())
			assert_false(Turret.sprite_meta(d.sprite_id).is_empty(), "métadonnées %s" % d.meta_path())


func test_biome_of_world_id() -> void:
	assert_eq(TurretData.biome_of("world_02_space_station"), &"space_station")
	assert_eq(TurretData.biome_of("mall"), &"mall")
	assert_eq(TurretData.biome_of("inconnu"), &"far_west")


# --- Placement -----------------------------------------------------------------------------

func _floors(world_path: String, seed_value: int) -> Array:
	var key := "%s#%d" % [world_path, seed_value]
	if not _floors_cache.has(key):
		var w: WorldData = load(world_path)
		var gen: Script = load(w.generator_path)
		_floors_cache[key] = gen.call("generate_run", seed_value, w, 2)
	return _floors_cache[key]


func _check_spot(L: FloorLayout, s: Dictionary, ctx: String) -> void:
	var cell: Vector2i = s["cell"]
	var n: Vector2i = s["normal"]
	assert_eq(L.get_tile(cell), FloorLayout.Tile.WALL, "%s : sur un mur" % ctx)
	assert_eq(absi(n.x) + absi(n.y), 1, "%s : normale cardinale" % ctx)
	var front := L.get_tile(cell + n)
	assert_true(front == FloorLayout.Tile.FLOOR or front == FloorLayout.Tile.STREET, "%s : tournée vers la salle" % ctx)
	var dc := int(Balance.get_value("turrets", "door_clearance", 2))
	for d: FloorLayout.Door in L.doors:
		assert_gt(maxi(absi(d.cell.x - cell.x), absi(d.cell.y - cell.y)), dc, "%s : loin des portes" % ctx)
	var sc := int(Balance.get_value("turrets", "stairs_clearance", 2))
	for st: FloorLayout.Stairs in L.stairs:
		assert_gt(maxi(absi(st.cell.x - cell.x), absi(st.cell.y - cell.y)), sc, "%s : loin des escaliers" % ctx)
	for e: Vector2i in L.extraction_cells:
		assert_true(Vector2(e).distance_to(Vector2(cell)) >= Balance.get_float("turrets", "extraction_clearance", 4.0),
			"%s : loin de l'extraction" % ctx)
		assert_ne(cell + n, e)
	assert_true(Vector2(L.player_spawn).distance_to(Vector2(cell)) >= Balance.get_float("turrets", "spawn_clearance", 9.0),
		"%s : loin du spawn joueur" % ctx)
	var room := L.get_room(int(s["room_id"]))
	assert_not_null(room, "%s : salle connue" % ctx)
	if room != null:
		assert_ne(room.type, FloorLayout.ROOM_SPAWN, "%s : jamais dans la salle de départ" % ctx)
		var spawn_room := L.room_at(L.player_spawn)
		if spawn_room != null:
			assert_ne(room.id, spawn_room.id, "%s : pas dans la salle du spawn" % ctx)
	assert_not_null(TurretData.get_by_id(s["turret_id"]), "%s : type connu" % ctx)


func test_spots_valid_on_all_biome_generators() -> void:
	var total := 0
	for wp: String in WORLDS:
		var w: WorldData = load(wp)
		for seed_value: int in SEEDS:
			for L: FloorLayout in _floors(wp, seed_value):
				var spots := TurretPlacer.find_spots(L, seed_value, 3, L.floor_index, String(w.id))
				total += spots.size()
				var spacing := Balance.get_float("turrets", "min_spacing", 6.0)
				for i: int in spots.size():
					_check_spot(L, spots[i], "%s s%d f%d #%d" % [w.biome, seed_value, L.floor_index, i])
					var td := TurretData.get_by_id(spots[i]["turret_id"])
					if td != null:
						assert_true(td.is_for_biome(w.biome), "type du bon biome")
					for j: int in range(i + 1, spots.size()):
						var a: Vector2i = spots[i]["cell"]
						var b: Vector2i = spots[j]["cell"]
						assert_true(Vector2(a).distance_to(Vector2(b)) >= spacing, "distance mini entre tourelles")
	assert_gt(total, 20, "des tourelles sont placées sur les 4 biomes")


func test_spots_deterministic() -> void:
	for wp: String in WORLDS:
		var w: WorldData = load(wp)
		for L: FloorLayout in _floors(wp, 11):
			var a := TurretPlacer.find_spots(L, 99, 2, L.floor_index, String(w.id))
			var b := TurretPlacer.find_spots(L, 99, 2, L.floor_index, String(w.id))
			assert_eq(str(a), str(b), "même seed → mêmes tourelles (%s f%d)" % [w.biome, L.floor_index])


func test_count_grows_with_difficulty() -> void:
	for wp: String in WORLDS:
		var w: WorldData = load(wp)
		var counts: Array[int] = []
		for diff: int in [0, 2, 4]:
			var n := 0
			for L: FloorLayout in _floors(wp, 4242):
				n += TurretPlacer.find_spots(L, 4242, diff, L.floor_index, String(w.id)).size()
			counts.append(n)
		assert_true(counts[0] <= counts[1] and counts[1] <= counts[2], "%s : %s croissant" % [w.biome, str(counts)])
		assert_gt(counts[2], counts[0], "%s : plus de tourelles en Cauchemar qu'en Facile" % w.biome)


func test_higher_difficulty_keeps_lower_spots() -> void:
	var wp: String = WORLDS[0]
	for L: FloorLayout in _floors(wp, 11):
		var low := TurretPlacer.find_spots(L, 5, 0, L.floor_index, "far_west")
		var high := TurretPlacer.find_spots(L, 5, 4, L.floor_index, "far_west")
		var high_cells := high.map(func(s: Dictionary) -> Vector2i: return s["cell"])
		for s: Dictionary in low:
			assert_true(high_cells.has(s["cell"]), "emplacement conservé à difficulté plus haute")


func test_sample_layout_spots() -> void:
	var L := FloorLayout.make_sample()
	var spots := TurretPlacer.find_spots(L, 3, 4, 0, "far_west")
	for s: Dictionary in spots:
		_check_spot(L, s, "exemple")


func test_spawn_for_floor_builds_nodes() -> void:
	var L: FloorLayout = _floors(WORLDS[1], 11)[0]
	var raid := Node2D.new()
	raid.set_meta(&"world_id", "space_station")
	_world.add_child(raid)
	var list := TurretPlacer.spawn_for_floor(raid, L, _world, 11, 3, L.floor_index)
	var spots := TurretPlacer.find_spots(L, 11, 3, L.floor_index, "space_station")
	assert_eq(list.size(), spots.size())
	for t: Node2D in list:
		assert_true(t is Turret)
		assert_true(t.has_meta(&"turret_cell"))
		assert_eq(L.get_tile(t.get_meta(&"turret_cell")), FloorLayout.Tile.WALL)
		assert_true(t.is_in_group(&"turrets") and t.is_in_group(&"enemies") and t.is_in_group(&"damageable"))
		assert_true(t.is_in_group(&"enemy_units") and t.is_in_group(&"fog_hideable"))
		assert_eq((t as Turret).collision_layer, 4)
		assert_true(String((t as Turret).data.id).begins_with("space_station"))
	# Appel en double : pas de doublons.
	var again := TurretPlacer.spawn_for_floor(raid, L, _world, 11, 3, L.floor_index)
	assert_eq(again.size(), list.size())
	assert_eq(get_tree().get_nodes_in_group(&"turrets").filter(func(n: Node) -> bool: return _world.is_ancestor_of(n)).size(), list.size())


func test_spawn_restores_destroyed_turrets() -> void:
	var L: FloorLayout = _floors(WORLDS[0], 4242)[1]
	var raid := Node2D.new()
	raid.set_meta(&"world_id", "far_west")
	_world.add_child(raid)
	var holder := Node2D.new()
	_world.add_child(holder)
	var list := TurretPlacer.spawn_for_floor(raid, L, holder, 4242, 3, L.floor_index)
	if list.is_empty():
		pass_test("aucune tourelle sur cet étage")
		return
	var t := list[0] as Turret
	t.take_damage(99999.0, null)
	holder.free()
	var holder2 := Node2D.new()
	_world.add_child(holder2)
	var list2 := TurretPlacer.spawn_for_floor(raid, L, holder2, 4242, 3, L.floor_index)
	assert_eq(list2.size(), list.size())
	var restored := list2[0] as Turret
	assert_false(restored.is_alive(), "tourelle détruite restaurée en épave")
	assert_false(restored.is_in_group(&"damageable"))


# --- Comportement --------------------------------------------------------------------------

func _data(lock: float = 0.1) -> TurretData:
	var d := TurretData.new()
	d.id = &"test_turret"
	d.sprite_id = "far_west_burst"
	d.max_hp = 50.0
	d.range = 400.0
	d.cone_deg = 90.0
	d.turn_speed_deg = 720.0
	d.lock_time = lock
	d.cooldown = 0.3
	d.burst_count = 2
	d.burst_interval = 0.05
	d.alert_neighbors_radius = 0.0
	return d


## Tourelle au mur dont la normale pointe vers le bas (salle au sud), origine en (0, 0).
func _turret(diff: int = 2, data: TurretData = null) -> Turret:
	var t := Turret.create(data if data != null else _data(), Vector2i.DOWN, Vector2i(0, -1), diff)
	t.position = Vector2.ZERO
	_world.add_child(t)
	return t


func _add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	_world.add_child(body)


func test_groups_layer_and_meta() -> void:
	var t := _turret()
	for g: StringName in [&"enemies", &"damageable", &"enemy_units", &"fog_hideable", &"turrets"]:
		assert_true(t.is_in_group(g), "groupe %s" % g)
	assert_eq(t.collision_layer, 4)
	assert_eq(t.get_meta(&"turret_cell"), Vector2i(0, -1))
	assert_true(t.is_alive())


func test_takes_damage_and_dies_once() -> void:
	var t := _turret()
	watch_signals(t)
	var died: Array = []
	EventBus.enemy_died.connect(func(e: Node2D, _p: Vector2) -> void: died.append(e))
	t.take_damage(10.0, null)
	assert_almost_eq(t.hp, t.max_hp - 10.0, 0.01)
	assert_true(t.is_alive())
	t.take_damage(9999.0, null)
	t.take_damage(9999.0, null)
	assert_false(t.is_alive())
	assert_signal_emit_count(t, "destroyed", 1)
	assert_false(t.is_in_group(&"enemies"), "plus ciblable")
	assert_false(t.is_in_group(&"damageable"))
	assert_true(t.is_in_group(&"enemy_units"), "compte toujours dans les unités")
	assert_true(t.is_inside_tree(), "l'épave reste au mur")
	if not bool(Balance.get_value("turrets", "drop_loot_on_destroy", false)):
		assert_false(died.has(t))


func test_difficulty_scales_hp() -> void:
	var easy := _turret(0)
	var hard := _turret(4)
	assert_gt(hard.max_hp, easy.max_hp)


func test_sees_player_in_cone() -> void:
	var t := _turret()
	_player.global_position = Vector2(20, 250)
	await wait_physics_frames(2)
	assert_true(t.update_perception(), "joueur devant la tourelle, en ligne de vue")


func test_cone_respected() -> void:
	var t := _turret()
	assert_true(t.is_in_cone(Vector2(0, 200)))
	assert_false(t.is_in_cone(Vector2(0, -200)), "derrière le mur")
	assert_false(t.is_in_cone(Vector2(300, 60)), "trop sur le côté (cône 90°)")
	_player.global_position = Vector2(300, 60)
	await wait_physics_frames(2)
	assert_false(t.update_perception(), "hors cône : pas vu")
	_player.global_position = Vector2(0, 600)
	assert_false(t.update_perception(), "hors portée : pas vu")


func test_wall_blocks_sight() -> void:
	var t := _turret()
	_add_wall(Rect2(Vector2(-100, 100), Vector2(200, 30)))
	_player.global_position = Vector2(0, 250)
	await wait_physics_frames(3)
	assert_false(t.update_perception(), "le mur bloque la vue")
	assert_false(t.has_line_of_sight_to(_player.global_position))


func test_hidden_player_not_seen_nor_shot() -> void:
	var t := _turret()
	watch_signals(t)
	_player.in_hiding = true
	_player.global_position = Vector2(0, 200)
	await wait_physics_frames(3)
	assert_false(t.update_perception(), "joueur caché invisible")
	await wait_seconds(0.8)
	assert_signal_not_emitted(t, "fired")
	assert_eq(_player.hp, 100.0)


func test_locks_then_fires_at_visible_player() -> void:
	var t := _turret()
	watch_signals(t)
	_player.global_position = Vector2(30, 220)
	await wait_until(func() -> bool: return t.state == Turret.State.LOCK, 1.0)
	assert_eq(t.state, Turret.State.LOCK, "télégraphe avant le tir")
	await wait_until(func() -> bool: return t.state == Turret.State.FIRE or t.state == Turret.State.COOLDOWN, 1.5)
	await wait_physics_frames(4)
	assert_signal_emitted(t, "fired")
	var pool := get_tree().get_first_node_in_group(&"enemy_projectile_pool") as EnemyProjectilePool
	assert_not_null(pool, "tire avec le pool de projectiles ennemis")


func test_aim_stays_in_cone() -> void:
	var t := _turret()
	_player.global_position = Vector2(390, 30)  # hors cône, sur le côté
	await wait_seconds(0.4)
	var rel := absf(wrapf(t.aim_angle - t.get_base_angle(), -PI, PI))
	assert_true(rel <= t.get_cone_half_angle() + 0.001, "le canon ne sort jamais du cône")


func test_alerts_neighbors_when_spotting() -> void:
	var d := _data(5.0)
	d.alert_neighbors_radius = 400.0
	var t := _turret(2, d)
	var ed := EnemyData.new()
	ed.patrol_radius = 0.0
	ed.detection_radius = 10.0
	ed.hearing_radius = 10.0
	ed.alert_neighbors_radius = 0.0
	var e := Enemy.spawn(ed)
	e.position = Vector2(200, 60)
	_world.add_child(e)
	await wait_physics_frames(2)
	var before := e.awareness
	_player.global_position = Vector2(0, 250)
	await wait_until(func() -> bool: return t.state != Turret.State.SCAN, 1.0)
	assert_gt(e.awareness, before, "l'ennemi voisin est prévenu")


func test_sleeps_far_from_player() -> void:
	var t := _turret()
	_player.global_position = Vector2(50000, 50000)
	t._on_sleep_check()
	assert_true(t.asleep)
	assert_false(t.is_physics_processing())
	_player.global_position = Vector2(0, 200)
	t._on_sleep_check()
	assert_false(t.asleep)
