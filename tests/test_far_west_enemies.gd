extends GutTest
## Ennemis du monde 1 (Far West) : données, visuels, tir en éventail, coup de zone.

const KINDS: Array[StringName] = [&"outlaw_knife", &"gunslinger", &"shotgun_brute", &"sandstone_colossus"]


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
	_player.position = Vector2(5000, 5000)
	_world.add_child(_player)
	_saved_player = GameState.player
	GameState.player = _player


func after_each() -> void:
	GameState.player = _saved_player
	var pool := get_tree().get_first_node_in_group(EnemyProjectilePool.GROUP)
	if pool != null:
		pool.queue_free()


func _load(kind: StringName) -> EnemyData:
	return load("res://data/enemies/%s.tres" % kind) as EnemyData


func test_all_resources_load() -> void:
	for k: StringName in KINDS:
		var d := _load(k)
		assert_not_null(d, "%s.tres charge" % k)
		if d == null:
			continue
		assert_eq(d.kind, k, "kind cohérent")
		assert_gt(d.max_hp, 0.0)
		assert_gt(d.move_speed, 0.0)
		assert_false(d.display_name.is_empty())


func test_archetype_balance() -> void:
	var knife := _load(&"outlaw_knife")
	var gun := _load(&"gunslinger")
	var brute := _load(&"shotgun_brute")
	var colossus := _load(&"sandstone_colossus")
	assert_false(knife.is_ranged())
	assert_gt(knife.move_speed, gun.move_speed, "bandit plus rapide que le pistolero")
	assert_lt(knife.max_hp, brute.max_hp, "bandit fragile")
	assert_true(gun.is_ranged())
	assert_gt(gun.retreat_distance, 0.0, "pistolero garde ses distances")
	assert_true(brute.is_ranged())
	assert_eq(brute.projectile_count, 5)
	assert_gt(brute.projectile_spread_deg, 0.0)
	assert_lt(brute.attack_range, gun.attack_range, "brute = courte portée")
	assert_gte(brute.attack_windup, 0.8, "gros télégraphe")
	assert_true(colossus.is_area_attack())
	assert_gt(colossus.max_hp, brute.max_hp, "colosse = tank")
	assert_lt(colossus.move_speed, knife.move_speed * 0.5, "colosse lent")
	assert_eq(gun.projectile_style, &"bullet")
	assert_eq(brute.projectile_style, &"bullet")


func test_defaults_keep_legacy_behaviour() -> void:
	var d := EnemyData.new()
	assert_eq(d.projectile_count, 1)
	assert_eq(d.aoe_radius, 0.0)
	assert_false(d.is_area_attack())
	for k: StringName in [&"golem", &"masked_grunt", &"masked_archer", &"masked_brute"]:
		var old := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_eq(old.projectile_count, 1, "%s inchangé" % k)
		assert_false(old.is_area_attack())


func test_kinds_setup_in_visual() -> void:
	for k: StringName in KINDS:
		assert_true(EnemyVisual.KINDS.has(k), "KINDS contient %s" % k)
		var v := EnemyVisual.new()
		add_child_autofree(v)
		v.setup(k)
		assert_eq(v.kind, k, "%s setup sans repli" % k)
		var sprite := v.get_node("Body/Sprite") as Sprite2D
		assert_not_null(sprite.texture, "%s : texture chargée" % k)
		assert_lt(v.get_head_offset().y, -40.0)
		v.set_attack_cone(50.0, 120.0)
		v.set_attack_area(80.0)
		v.set_aim_direction(Vector2.RIGHT)
		v.play_alert()
		v.play_attack_windup(0.3)
		v.play_ground_slam(80.0)
		await wait_frames(2)
		assert_false(v.is_dying())


func test_brute_fires_fan_of_pellets() -> void:
	var e := Enemy.spawn(_load(&"shotgun_brute"))
	e.position = Vector2.ZERO
	_world.add_child(e)
	_player.global_position = Vector2(120, 0)
	await wait_physics_frames(2)
	var dirs := e.get_shot_directions(Vector2.RIGHT)
	assert_eq(dirs.size(), 5)
	var spread := rad_to_deg(dirs[0].angle_to(dirs[4]))
	assert_almost_eq(absf(spread), e.data.projectile_spread_deg, 0.5, "ouverture de l'éventail")
	assert_almost_eq(dirs[2].angle(), 0.0, 0.01, "plomb central dans l'axe")
	var fired: Array = []
	var cb := func(p: Node) -> void: fired.append(p)
	EventBus.projectile_fired.connect(cb)
	assert_true(e.perform_attack())
	EventBus.projectile_fired.disconnect(cb)
	assert_eq(fired.size(), 5, "5 plombs tirés")
	var angles: Array[float] = []
	for p: Node in fired:
		var proj := p as EnemyProjectile
		assert_eq(proj.style, &"bullet")
		assert_almost_eq(proj.lifetime_left, e.data.projectile_lifetime, 0.05, "courte portée")
		angles.append(proj.direction.angle())
	angles.sort()
	assert_gt(angles[4] - angles[0], deg_to_rad(40.0), "projectiles en éventail")


func test_gunslinger_single_bullet() -> void:
	var e := Enemy.spawn(_load(&"gunslinger"))
	_world.add_child(e)
	_player.global_position = Vector2(200, 0)
	await wait_physics_frames(2)
	var fired: Array = []
	var cb := func(p: Node) -> void: fired.append(p)
	EventBus.projectile_fired.connect(cb)
	e.perform_attack()
	EventBus.projectile_fired.disconnect(cb)
	assert_eq(fired.size(), 1)


func test_colossus_area_hits_player_in_range() -> void:
	var data := _load(&"sandstone_colossus")
	var e := Enemy.spawn(data)
	_world.add_child(e)
	# Dans la zone mais au-delà de la portée de mêlée classique (+ tolérance).
	_player.global_position = Vector2(data.aoe_radius - 10.0, 0)
	await wait_physics_frames(2)
	assert_gt(data.aoe_radius - 10.0, data.attack_range + 16.0)
	var hp0 := _player.hp
	assert_true(e.perform_attack(), "coup de zone touche")
	assert_almost_eq(_player.hp, hp0 - data.attack_damage, 0.01)


func test_colossus_area_misses_player_out_of_range() -> void:
	var data := _load(&"sandstone_colossus")
	var e := Enemy.spawn(data)
	_world.add_child(e)
	_player.global_position = Vector2(data.aoe_radius + 40.0, 0)
	await wait_physics_frames(2)
	var hp0 := _player.hp
	assert_false(e.perform_attack())
	assert_eq(_player.hp, hp0)
