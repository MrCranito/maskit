extends GutTest
## Impacts des balles du joueur : arrêt sur le premier ennemi, perforation N, aucune traversée
## à haute vitesse (collision balayée sur le segment parcouru à chaque pas physique), impacts
## sur les murs.

const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")


## Cible minimale comme un ennemi : corps physique couche enemies (4), groupes enemies + damageable.
class Target extends StaticBody2D:
	var hp: float = 1000.0
	var hits: int = 0

	func _init(radius: float) -> void:
		collision_layer = 4
		collision_mask = 0
		add_to_group(&"enemies")
		add_to_group(&"damageable")
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = radius
		cs.shape = c
		add_child(cs)

	func take_damage(amount: float, _source: Node) -> void:
		hp -= amount
		hits += 1

	func is_alive() -> bool:
		return hp > 0.0


var _released_at: Vector2 = Vector2.INF


func _target(pos: Vector2, radius: float = 20.0) -> Target:
	var t := Target.new(radius)
	add_child_autofree(t)
	t.global_position = pos
	return t


func _wall(pos: Vector2, size: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	wall.add_child(cs)
	add_child_autofree(wall)
	wall.global_position = pos
	return wall


func _weapon(speed: float, pierce: int, range_px: float = 1200.0) -> WeaponData:
	var w := WeaponData.new()
	w.damage = 10.0
	w.projectile_speed = speed
	w.range = range_px
	w.projectile_lifetime = 0.0
	w.pierce = pierce
	w.projectile_style = &"bullet"
	return w


func _fire(from: Vector2, dir: Vector2, w: WeaponData) -> Projectile:
	var p: Projectile = PROJECTILE_SCENE.instantiate() as Projectile
	add_child_autofree(p)
	_released_at = Vector2.INF
	p.released.connect(func(pr: Projectile) -> void: _released_at = pr.global_position)
	await wait_physics_frames(1)
	p.launch(from, dir, w, null, 0.0)
	return p


func test_bullet_without_pierce_stops_on_first_enemy() -> void:
	var a := _target(Vector2(300, 100))
	var b := _target(Vector2(380, 100))
	var c := _target(Vector2(460, 100))
	var p: Projectile = await _fire(Vector2(100, 100), Vector2.RIGHT, _weapon(1100.0, 0))
	await wait_physics_frames(40)
	assert_eq(a.hits, 1, "le premier ennemi est touché")
	assert_eq(b.hits, 0, "la balle ne traverse pas le premier ennemi")
	assert_eq(c.hits, 0)
	assert_false(p.active, "la balle est consommée")
	# Contact : centre de la forme (décalée de 4 px vers l'avant, rayon 9) à 20 px de la cible.
	var contact_x: float = a.global_position.x - 20.0 - 9.0 - 4.0
	assert_almost_eq(_released_at.x, contact_x, 2.0,
		"la balle s'arrête au point de contact, pas un pas physique plus loin")


func test_hit_material_from_enemy_data() -> void:
	CombatFx.reset_material_cache()
	var robot := EnemyData.new()
	robot.kind = &"test_robot"
	robot.sfx_hurt = &"metal_impact"
	var outlaw := EnemyData.new()
	outlaw.kind = &"test_outlaw"
	outlaw.sfx_hurt = &"outlaw_hurt"
	var alien := EnemyData.new()
	alien.kind = &"ss_alien"
	alien.sfx_hurt = &"hit_flesh"
	var holder := Node2D.new()
	assert_eq(CombatFx.material_of(_with_data(robot)), CombatFx.MAT_METAL, "robot : étincelles métal")
	assert_eq(CombatFx.material_of(_with_data(outlaw)), CombatFx.MAT_ORGANIC, "hors-la-loi : giclée")
	assert_eq(CombatFx.material_of(_with_data(alien)), CombatFx.MAT_ALIEN, "exception par kind")
	assert_eq(CombatFx.material_of(holder), CombatFx.MAT_ORGANIC, "sans données : organique")
	holder.free()
	CombatFx.reset_material_cache()


func test_hit_spawns_marker_and_kick_is_capped() -> void:
	var fx := CombatFx.get_or_create(get_tree())
	assert_not_null(fx)
	fx.air.clear()
	fx.impact_enemy(Vector2(50, 50), Vector2.RIGHT, 12.0, false, 0, CombatFx.MAT_METAL, false)
	assert_gt(fx.air.get_alive_count(), 3, "éclair, étincelles et hit-marker émis")
	assert_almost_eq(fx.hit_kick_px(5.5), minf(5.5 * fx.kick_per_recoil, fx.kick_max_px), 0.001)
	assert_eq(fx.hit_kick_px(1000.0), fx.kick_max_px, "à-coup plafonné")
	fx.air.clear()


class DataHolder extends Node2D:
	var data: EnemyData = null


func _with_data(d: EnemyData) -> Node2D:
	var h := DataHolder.new()
	h.data = d
	autofree(h)
	return h


func test_pierce_n_crosses_n_enemies() -> void:
	for n: int in [1, 2, 3]:
		var targets: Array[Target] = []
		for i: int in 5:
			targets.append(_target(Vector2(300 + i * 80, 400 + n * 100)))
		var p: Projectile = await _fire(Vector2(100, 400 + n * 100), Vector2.RIGHT, _weapon(1100.0, n, 2000.0))
		await wait_physics_frames(60)
		for i: int in 5:
			assert_eq(targets[i].hits, 1 if i <= n else 0,
				"perforation %d : cible %d %s" % [n, i, "touchée" if i <= n else "épargnée"])
		assert_false(p.active)


func test_no_tunneling_at_high_speed() -> void:
	# 9000 px/s = 150 px par pas physique (60 Hz), bien plus que le diamètre de la cible.
	# Départ décalé d'un demi-pas : sans balayage, les positions successives (175, 325, 475…)
	# encadrent la cible sans jamais la chevaucher.
	var small := _target(Vector2(400, 100), 8.0)
	var behind := _target(Vector2(700, 100), 8.0)
	var p: Projectile = await _fire(Vector2(175, 100), Vector2.RIGHT, _weapon(9000.0, 0, 2000.0))
	await wait_physics_frames(20)
	assert_eq(small.hits, 1, "une balle très rapide touche une petite cible sur sa trajectoire")
	assert_eq(behind.hits, 0, "et s'arrête dessus")
	assert_false(p.active)
	assert_lt(_released_at.x, small.global_position.x + 1.0)


func test_high_speed_bullet_stops_on_thin_wall() -> void:
	_wall(Vector2(400, 100), Vector2(6, 200))
	var behind := _target(Vector2(500, 100))
	var p: Projectile = await _fire(Vector2(175, 100), Vector2.RIGHT, _weapon(9000.0, 0, 2000.0))
	await wait_physics_frames(20)
	assert_eq(behind.hits, 0, "un mur fin arrête une balle rapide")
	assert_false(p.active)
	assert_lt(_released_at.x, 400.0)


func test_pierce_bullet_still_stops_on_wall() -> void:
	var a := _target(Vector2(250, 100))
	_wall(Vector2(350, 100), Vector2(10, 200))
	var b := _target(Vector2(450, 100))
	var p: Projectile = await _fire(Vector2(100, 100), Vector2.RIGHT, _weapon(1500.0, 3, 2000.0))
	await wait_physics_frames(40)
	assert_eq(a.hits, 1)
	assert_eq(b.hits, 0, "la perforation traverse les ennemis, pas les murs")
	assert_false(p.active)


func test_dead_enemy_is_crossed_without_consuming() -> void:
	var dead := _target(Vector2(250, 100))
	dead.hp = 0.0
	var alive := _target(Vector2(400, 100))
	await _fire(Vector2(100, 100), Vector2.RIGHT, _weapon(1100.0, 0))
	await wait_physics_frames(30)
	assert_eq(dead.hits, 0, "un cadavre ne prend pas la balle")
	assert_eq(alive.hits, 1, "la balle continue jusqu'à l'ennemi vivant")
