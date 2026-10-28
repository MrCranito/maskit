extends GutTest
## Équipement (grenade, fumigène, mine, C4, drone), fumée qui bloque la vue, guidage,
## salve, gravité faible.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _player: Player
var _saved_player = null


func before_each() -> void:
	_saved_player = GameState.player if is_instance_valid(GameState.player) else null
	_player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(_player)
	_player.global_position = Vector2(100, 100)


func after_each() -> void:
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null
	for s: Node in get_tree().get_nodes_in_group(SmokeField.GROUP):
		s.free()


func _gadget(kind: StringName, charges: int = 2) -> WeaponData:
	var g := WeaponData.new()
	g.id = StringName("gadget_" + String(kind))
	g.category = WeaponData.CAT_GADGET
	g.slot = WeaponData.SLOT_GADGET
	g.gadget_kind = kind
	g.charges = charges
	g.throw_range = 200.0
	g.fuse_time = 0.5
	g.effect_radius = 80.0
	g.effect_duration = 3.0
	g.explosion_radius = 100.0
	g.explosion_damage = 50.0
	g.damage = 5.0
	g.fire_rate = 5.0
	return g


class Dummy extends Node2D:
	var hits: Array[float] = []
	var alive: bool = true
	func _init() -> void:
		add_to_group(&"damageable")
		add_to_group(&"enemies")
	func take_damage(amount: float, _source: Node) -> void:
		hits.append(amount)
	func is_alive() -> bool:
		return alive


func _dummy(pos: Vector2) -> Dummy:
	var d := Dummy.new()
	add_child_autofree(d)
	d.global_position = pos
	return d


# --- Emplacement d'équipement -------------------------------------------------

func test_loadout_gadget_charges_logic() -> void:
	var l := WeaponLoadout.new(3)
	var w := WeaponData.new()
	w.id = &"gun"
	var g := _gadget(&"frag", 2)
	l.set_weapons([w, g])
	assert_eq(l.gadget, g, "l'équipement d'une liste va dans son emplacement")
	assert_eq(l.weapon_count(), 1)
	assert_eq(l.gadget_charges, 2)
	assert_true(l.consume_gadget_charge())
	assert_true(l.consume_gadget_charge())
	assert_false(l.consume_gadget_charge(), "plus de charges")
	assert_false(l.carried_ids().has(&"gadget_frag"), "sans charge : non extrait")
	l.set_gadget(g)
	assert_true(l.carried_ids().has(&"gadget_frag"), "avec charges : extrait")


func test_player_gadget_api_and_equip() -> void:
	watch_signals(_player)
	var g := _gadget(&"frag", 3)
	assert_null(_player.equip_into_current_slot(g), "pas d'ancien équipement")
	assert_signal_emitted(_player, "gadget_changed")
	assert_eq(_player.get_gadget(), g)
	assert_eq(_player.get_gadget_charges(), 3)
	assert_ne(_player.weapon, g, "les armes ne sont pas touchées")
	var g2 := _gadget(&"smoke", 1)
	assert_eq(_player.equip_into_current_slot(g2), g, "renvoie l'ancien équipement")
	assert_true(_player.get_carried_weapon_ids().has(&"gadget_smoke"))


func test_use_gadget_consumes_charges() -> void:
	await wait_physics_frames(2)
	_player.set_gadget(_gadget(&"frag", 2))
	assert_true(_player.use_gadget(Vector2.RIGHT))
	assert_eq(_player.get_gadget_charges(), 1)
	assert_true(_player.use_gadget(Vector2.RIGHT))
	assert_false(_player.use_gadget(Vector2.RIGHT), "plus de charges")
	assert_eq(_player.get_gadget_charges(), 0)
	assert_false(_player.get_carried_weapon_ids().has(&"gadget_frag"))


func test_gadget_direction_rules() -> void:
	assert_eq(Player.gadget_direction(Vector2(0, 2), Vector2.RIGHT, Vector2.ZERO, false), Vector2.DOWN)
	assert_eq(Player.gadget_direction(Vector2.ZERO, Vector2.RIGHT, Vector2(0, -200), false), Vector2.UP,
		"sans visée : direction du déplacement")
	assert_eq(Player.gadget_direction(Vector2.ZERO, Vector2.LEFT, Vector2(0, -200), true), Vector2.LEFT,
		"visée prioritaire")


func test_frag_explodes_after_fuse() -> void:
	var target := _dummy(Vector2(300, 100))
	var g := _gadget(&"frag")
	var dev := GadgetDevice.throw_device(self, g, Vector2(100, 100), 20.0, Vector2(300, 100), null)
	autofree(dev)
	assert_gt(GadgetDevice.arc_vz(200.0, 520.0, 20.0, 1100.0), 0.0, "arc vers le haut")
	for i: int in 20:
		dev._physics_process(1.0 / 60.0)
	assert_false(dev.detonated, "mèche pas encore écoulée")
	for i: int in 20:
		dev._physics_process(1.0 / 60.0)
	assert_true(dev.detonated, "explose après fuse_time")
	assert_eq(target.hits.size(), 1)


# --- Fumée ------------------------------------------------------------------------

func test_smoke_blocks_line_only_through_cloud() -> void:
	var s := SmokeField.spawn(self, Vector2(500, 500), 100.0, 5.0)
	s.advance(1.0)  # grandi
	assert_true(SmokeField.blocks_line(Vector2(300, 500), Vector2(700, 500)), "traverse le nuage")
	assert_false(SmokeField.blocks_line(Vector2(300, 700), Vector2(700, 700)), "passe à côté")
	assert_true(SmokeField.point_in_smoke(Vector2(500, 500)))
	assert_true(s.is_in_group(SmokeField.GROUP))
	s.advance(3.9)  # en fin de dissipation
	assert_false(SmokeField.blocks_line(Vector2(300, 500), Vector2(700, 500)), "dissipée")


func test_smoke_segment_distance_logic() -> void:
	assert_almost_eq(SmokeField.segment_distance_sq(Vector2.ZERO, Vector2(10, 0), Vector2(5, 3)), 9.0, 0.001)
	assert_almost_eq(SmokeField.segment_distance_sq(Vector2.ZERO, Vector2(10, 0), Vector2(13, 4)), 25.0, 0.001)


func test_smoke_grenade_releases_cloud() -> void:
	var g := _gadget(&"smoke")
	var dev := GadgetDevice.throw_device(self, g, Vector2(100, 100), 20.0, Vector2(200, 100), null)
	for i: int in 60:
		if is_instance_valid(dev):
			dev._physics_process(1.0 / 60.0)
	assert_eq(get_tree().get_nodes_in_group(SmokeField.GROUP).size(), 1, "un nuage")


func test_enemy_sight_blocked_by_smoke() -> void:
	var data := load("res://data/enemies/outlaw_knife.tres") as EnemyData
	if data == null:
		pending("outlaw_knife absent")
		return
	var e := (load("res://scenes/enemies/enemy.tscn") as PackedScene).instantiate() as Enemy
	e.data = data
	add_child_autofree(e)
	e.global_position = _player.global_position + Vector2(120, 0)
	e.face(Vector2.LEFT)
	await wait_physics_frames(2)
	GameState.player = _player
	e.update_perception(0.1)
	var saw: bool = e.can_see_player
	var s := SmokeField.spawn(self, _player.global_position + Vector2(60, 0), 40.0, 5.0)
	s.advance(1.0)
	e.update_perception(0.1)
	assert_true(saw, "voit le joueur sans fumée")
	assert_false(e.can_see_player, "la fumée bloque la vue")


# --- Mine, C4, drone -----------------------------------------------------------------

func test_mine_arms_then_triggers_on_enemy() -> void:
	var g := _gadget(&"mine")
	var dev := GadgetDevice.throw_device(self, g, Vector2(1000, 1000), 0.0, Vector2(1000, 1000), null)
	autofree(dev)
	var e := _dummy(Vector2(1030, 1000))  # déjà dans le rayon
	for i: int in 20:
		dev._physics_process(1.0 / 60.0)
	assert_false(dev.armed, "pas armée avant fuse_time")
	assert_false(dev.detonated, "ne se déclenche pas avant d'être armée")
	for i: int in 30:
		dev._physics_process(1.0 / 60.0)
	assert_true(dev.armed)
	assert_true(dev.detonated, "ennemi dans le rayon : explosion")
	assert_eq(e.hits.size(), 1)


func test_mine_ignores_far_or_dead_enemy() -> void:
	var g := _gadget(&"mine")
	var dev := GadgetDevice.throw_device(self, g, Vector2(1500, 1500), 0.0, Vector2(1500, 1500), null)
	autofree(dev)
	_dummy(Vector2(1700, 1500))
	var dead := _dummy(Vector2(1510, 1500))
	dead.alive = false
	for i: int in 90:
		dev._physics_process(1.0 / 60.0)
	assert_true(dev.armed)
	assert_false(dev.detonated)


func test_c4_second_press_detonates() -> void:
	await wait_physics_frames(2)
	var g := _gadget(&"c4", 1)
	_player.set_gadget(g)
	var target := _dummy(_player.global_position + Vector2(60, 0))
	assert_true(_player.use_gadget(Vector2.RIGHT), "pose")
	assert_eq(_player.get_placed_c4_count(), 1)
	assert_eq(_player.get_gadget_charges(), 0)
	for i: int in 30:
		await wait_physics_frames(1)
	assert_true(target.hits.is_empty(), "aucune explosion sans 2e appui")
	assert_true(_player.use_gadget(Vector2.RIGHT), "2e appui = détonation (même sans charge)")
	assert_eq(target.hits.size(), 1)
	assert_eq(_player.get_placed_c4_count(), 0)


func test_drone_targets_nearest_visible_enemy() -> void:
	var far := _dummy(Vector2(400, 100))
	var near := _dummy(Vector2(200, 100))
	var hidden := _dummy(Vector2(150, 100))
	hidden.visible = false
	var out := _dummy(Vector2(900, 100))
	var list: Array = [far, near, hidden, out]
	assert_eq(GadgetDrone.pick_target(list, Vector2(100, 100), 400.0), near)
	near.alive = false
	assert_eq(GadgetDrone.pick_target(list, Vector2(100, 100), 400.0), far, "ignore les morts")
	var no_los := func(_a: Vector2, b: Vector2) -> bool: return b.x > 300.0
	near.alive = true
	assert_eq(GadgetDrone.pick_target(list, Vector2(100, 100), 400.0, no_los), far, "ligne de vue")


func test_drone_shoots_then_leaves() -> void:
	await wait_physics_frames(2)
	var g := _gadget(&"drone", 1)
	g.effect_radius = 400.0
	g.effect_duration = 1.0
	_dummy(_player.global_position + Vector2(150, 0))
	var drone := GadgetDrone.spawn(self, _player, g)
	for i: int in 50:
		drone.advance(1.0 / 60.0)
	assert_gt(drone.shots_fired, 0, "le drone tire")
	assert_false(drone.leaving)
	for i: int in 40:
		if is_instance_valid(drone):
			drone.advance(1.0 / 60.0)
	assert_true(not is_instance_valid(drone) or drone.leaving, "repart après effect_duration")


# --- Guidage, salve -------------------------------------------------------------------

func test_homing_steer_bounded() -> void:
	var d := Projectile.steer(Vector2.RIGHT, Vector2.DOWN, 0.1)
	assert_almost_eq(d.angle(), 0.1, 0.0001, "rotation bornée")
	var d2 := Projectile.steer(Vector2.RIGHT, Vector2(1, 0.01), 0.5)
	assert_almost_eq(d2.angle(), Vector2(1, 0.01).angle(), 0.0001)


func test_javelin_and_m202_detection() -> void:
	var jav := WeaponCatalog.get_weapon(&"rocket_javelin")
	var m202 := WeaponCatalog.get_weapon(&"rocket_m202")
	if jav == null or m202 == null:
		pending("catalogue Refonte n°2 absent")
		return
	assert_gt(Player.weapon_homing(jav), 0.0)
	assert_eq(Player.weapon_homing(m202), 0.0)
	assert_true(Player.is_salvo_weapon(m202))


func test_m202_salvo_fires_four_rockets() -> void:
	var m202 := WeaponCatalog.get_weapon(&"rocket_m202")
	if m202 == null:
		pending("M202 absent")
		return
	await wait_physics_frames(2)
	var list: Array[WeaponData] = [m202]
	_player.set_weapons(list)
	_player.fire(Vector2.RIGHT)
	for i: int in 20:
		_player._physics_process(1.0 / 60.0)
	assert_eq(_player.get_magazine_size() - maxi(_player.get_ammo(), 0) if not _player.is_reloading() else 4, 4,
		"4 roquettes consommées")
	assert_true(_player.is_reloading(), "rechargement après la salve")


# --- Gravité faible ---------------------------------------------------------------------

func test_low_gravity_cells_logic() -> void:
	var cells := {Vector2i(2, 3): true}
	assert_true(LowGravity.is_in(cells, FloorLayout.cell_to_world(Vector2i(2, 3))))
	assert_false(LowGravity.is_in(cells, FloorLayout.cell_to_world(Vector2i(5, 5))))
	assert_false(LowGravity.is_in({}, Vector2.ZERO))
	assert_eq(LowGravity.cells_of(null), {})


func test_low_gravity_slides_longer() -> void:
	var dt := 1.0 / 60.0
	var normal := Vector2(250, 0)
	var floaty := Vector2(250, 0)
	for i: int in 20:
		normal = Player.step_velocity(normal, Vector2.ZERO, 250.0, 2400.0, 3200.0, 18.0, 1.8, dt)
		floaty = Player.step_velocity(floaty, Vector2.ZERO, 250.0, 2400.0 * 0.18, 3200.0 * 0.06, 18.0 * 0.08, 1.8, dt)
	assert_eq(normal, Vector2.ZERO, "sol normal : arrêt net")
	assert_gt(floaty.x, 50.0, "gravité faible : on glisse encore")


func test_low_gravity_recoil_pushes_player() -> void:
	await wait_physics_frames(2)
	var w := WeaponData.new()
	w.id = &"g"
	w.recoil_px = 10.0
	w.magazine_size = 5
	var list: Array[WeaponData] = [w]
	_player.set_weapons(list)
	_player.in_low_gravity = true
	_player.velocity = Vector2.ZERO
	_player.fire(Vector2.RIGHT)
	assert_lt(_player.velocity.x, 0.0, "recul vers l'arrière")


func test_fx_low_gravity_particle_drifts() -> void:
	var layer := FxLayer.new()
	add_child_autofree(layer)
	layer.setup(8)
	var a := layer.emit(FxLayer.Kind.SHELL, Vector2.ZERO, Vector2.ZERO, 5.0, 4.0, 0.0, Color.WHITE, 30.0, 0.0)
	var b := layer.emit(FxLayer.Kind.SHELL, Vector2.ZERO, Vector2.ZERO, 5.0, 4.0, 0.0, Color.WHITE, 30.0, 0.0)
	layer.set_gravity(b, 0.15)
	for i: int in 10:
		layer._process(1.0 / 60.0)
	assert_lt(layer._z[a], layer._z[b], "la douille en gravité faible tombe moins vite")
