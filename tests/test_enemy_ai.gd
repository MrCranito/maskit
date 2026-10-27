extends GutTest
## Tests de l'IA ennemie : détection, ligne de vue, alerte des voisins, mort.
## Scènes construites dans le test : ennemis, faux joueur, murs.


class FakePlayer extends CharacterBody2D:
	var hp: float = 100.0
	var hits: Array = []

	func _ready() -> void:
		add_to_group(&"player")
		add_to_group(&"damageable")
		collision_layer = 2
		collision_mask = 0
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 20.0
		cs.shape = c
		add_child(cs)

	func take_damage(amount: float, source: Node) -> void:
		hp -= amount
		hits.append([amount, source])

	func is_alive() -> bool:
		return hp > 0.0


var _world: Node2D
var _player: FakePlayer
var _saved_player: Node2D


func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_player = FakePlayer.new()
	_player.position = Vector2(5000, 5000)  # Loin de tout par défaut.
	_world.add_child(_player)
	_saved_player = GameState.player
	GameState.player = _player


func after_each() -> void:
	GameState.player = _saved_player


func _make_data(angle: float = 360.0) -> EnemyData:
	var d := EnemyData.new()
	d.kind = &"masked_grunt"
	d.max_hp = 30.0
	d.move_speed = 120.0
	d.detection_radius = 300.0
	d.detection_angle_deg = angle
	d.alert_duration = 0.15
	d.alert_neighbors_radius = 250.0
	d.patrol_radius = 0.0  # Immobile en patrouille : tests déterministes.
	d.attack_range = 50.0
	d.attack_windup = 0.1
	d.attack_cooldown = 0.5
	d.attack_damage = 5.0
	return d


func _spawn_enemy(pos: Vector2, data: EnemyData = null) -> Enemy:
	var e := Enemy.spawn(data if data != null else _make_data())
	e.position = pos
	_world.add_child(e)
	return e


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


func test_spawn_groups_layers_and_state() -> void:
	var e := _spawn_enemy(Vector2.ZERO)
	assert_true(e.is_in_group("enemies"))
	assert_true(e.is_in_group("damageable"))
	assert_true(e.is_in_group("enemy_units"))
	assert_eq(e.collision_layer, 4, "couche enemies")
	assert_true(e.collision_mask & 1 != 0, "collision avec world")
	assert_eq(e.current_state_name(), Enemy.STATE_PATROL)
	assert_true(e.is_alive())
	assert_not_null(e.visual, "visuel (EnemyVisual ou repli) créé")


func test_player_out_of_range_stays_patrol() -> void:
	var e := _spawn_enemy(Vector2.ZERO)
	_player.global_position = Vector2(600, 0)
	await wait_physics_frames(20)
	assert_false(e.can_see_player)
	assert_eq(e.current_state_name(), Enemy.STATE_PATROL)


func test_player_in_range_with_los_alert_then_chase() -> void:
	var e := _spawn_enemy(Vector2.ZERO)
	var seen: Array = []
	e.state_machine.state_changed.connect(func(_f: StringName, t: StringName) -> void: seen.append(t))
	_player.global_position = Vector2(200, 0)
	await wait_physics_frames(15)
	assert_true(e.can_see_player, "joueur vu")
	assert_has(seen, Enemy.STATE_ALERT)
	await wait_seconds(0.4)
	assert_has(seen, Enemy.STATE_CHASE, "Alert → Chase après alert_duration")
	assert_lt(seen.find(Enemy.STATE_ALERT), seen.find(Enemy.STATE_CHASE))


func test_wall_blocks_detection() -> void:
	_add_wall(Rect2(Vector2(80, -100), Vector2(40, 200)))
	var e := _spawn_enemy(Vector2.ZERO)
	_player.global_position = Vector2(200, 0)
	await wait_physics_frames(20)
	assert_false(e.has_line_of_sight_to(_player.global_position), "raycast bloqué par le mur")
	assert_false(e.can_see_player)
	assert_eq(e.current_state_name(), Enemy.STATE_PATROL)


func test_vision_cone_ignores_player_behind() -> void:
	var e := _spawn_enemy(Vector2.ZERO, _make_data(120.0))
	e.face(Vector2.RIGHT)
	_player.global_position = Vector2(-200, 0)  # Dans le dos.
	await wait_physics_frames(15)
	assert_false(e.is_in_vision_cone(_player.global_position))
	assert_eq(e.current_state_name(), Enemy.STATE_PATROL)
	_player.global_position = Vector2(200, 30)  # Devant.
	await wait_physics_frames(15)
	assert_ne(e.current_state_name(), Enemy.STATE_PATROL, "détecté dans le cône")


func test_alert_propagates_to_neighbors() -> void:
	# Le voisin est caché derrière un mur : il ne voit pas le joueur lui-même.
	_add_wall(Rect2(Vector2(-160, -40), Vector2(40, 80)))
	var a := _spawn_enemy(Vector2.ZERO)
	var b := _spawn_enemy(Vector2(-200, 0))
	var far := _spawn_enemy(Vector2(-1000, 0))
	_player.global_position = Vector2(200, 0)
	await wait_physics_frames(15)
	assert_false(b.has_line_of_sight_to(_player.global_position), "le voisin ne voit pas le joueur")
	assert_ne(a.current_state_name(), Enemy.STATE_PATROL)
	assert_true(b.current_state_name() == Enemy.STATE_ALERT or b.current_state_name() == Enemy.STATE_CHASE,
		"voisin alerté (état %s)" % b.current_state_name())
	assert_eq(far.current_state_name(), Enemy.STATE_PATROL, "ennemi lointain non alerté")


func test_damage_triggers_alert() -> void:
	var e := _spawn_enemy(Vector2.ZERO)
	_player.global_position = Vector2(2000, 0)
	await wait_physics_frames(2)
	e.take_damage(1.0, _player)
	assert_eq(e.current_state_name(), Enemy.STATE_ALERT)
	assert_almost_eq(e.hp, e.max_hp - 1.0, 0.001)


func test_melee_attack_hits_player_in_range() -> void:
	var e := _spawn_enemy(Vector2.ZERO)
	_player.global_position = Vector2(40, 0)
	await wait_seconds(0.8)
	assert_gt(_player.hits.size(), 0, "le joueur au contact est touché")
	assert_eq(_player.hits[0][0], 5.0)


func test_melee_attack_dodged_if_player_leaves() -> void:
	var e := _spawn_enemy(Vector2.ZERO)
	_player.global_position = Vector2(40, 0)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_ATTACK, 1.0)
	_player.global_position = Vector2(400, 0)  # Esquive pendant le télégraphe.
	await wait_seconds(0.15)
	assert_eq(_player.hits.size(), 0, "esquive : aucun dégât")


func test_death_leaves_groups_and_emits() -> void:
	var died: Array = []
	var cb := func(en: Node2D, _p: Vector2) -> void: died.append(en)
	EventBus.enemy_died.connect(cb)
	var e := _spawn_enemy(Vector2.ZERO)
	e.take_damage(1000.0, null)
	EventBus.enemy_died.disconnect(cb)
	assert_false(e.is_alive())
	assert_false(e.is_in_group("enemies"), "retiré de enemies immédiatement")
	assert_false(e.is_in_group("damageable"))
	assert_eq(e.current_state_name(), Enemy.STATE_DEAD)
	assert_eq(died, [e])
	# Libéré après l'animation de mort (ou le délai de secours).
	await wait_seconds(Balance.get_float("enemy_ai", "death_free_fallback", 2.0) + 0.3)
	assert_false(is_instance_valid(e), "ennemi libéré après la mort")


func test_ranged_enemy_fires_projectile() -> void:
	var d := _make_data()
	d.kind = &"masked_archer"
	d.attack_type = EnemyData.AttackType.RANGED
	d.attack_range = 280.0
	d.projectile_speed = 600.0
	var e := _spawn_enemy(Vector2.ZERO, d)
	_player.global_position = Vector2(220, 0)
	await wait_seconds(1.0)
	assert_gt(_player.hits.size(), 0, "le projectile ennemi touche le joueur")
	var pool := EnemyProjectilePool.get_or_create(get_tree())
	assert_not_null(pool)
	if is_instance_valid(pool):
		pool.queue_free()
	assert_true(is_instance_valid(e))


func test_enemy_data_resources_load() -> void:
	for kind: String in ["golem", "masked_grunt", "masked_archer", "masked_brute"]:
		var d := load("res://data/enemies/%s.tres" % kind) as EnemyData
		assert_not_null(d, kind)
		if d != null:
			assert_eq(String(d.kind), kind)
			assert_gt(d.max_hp, 0.0)
	var archer := load("res://data/enemies/masked_archer.tres") as EnemyData
	assert_true(archer.is_ranged())
