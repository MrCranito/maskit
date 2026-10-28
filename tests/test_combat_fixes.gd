extends GutTest
## Correctifs du test de jeu : trajectoire des balles au niveau du sol et aide à la visée.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _player: Node2D
var _saved_player = null


func before_each() -> void:
	_saved_player = GameState.player if is_instance_valid(GameState.player) else null
	_player = PLAYER_SCENE.instantiate()
	add_child_autofree(_player)
	_player.global_position = Vector2(100, 100)


func after_each() -> void:
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null


func _add_enemy(pos: Vector2) -> Node2D:
	var e := Node2D.new()
	e.add_to_group(&"enemies")
	add_child_autofree(e)
	e.global_position = pos
	return e


func test_projectile_travels_at_ground_level() -> void:
	await wait_physics_frames(2)
	_player.call("fire", Vector2.RIGHT)
	var found := false
	# Le pool range ses projectiles hors du joueur : on retrouve le projectile actif.
	for n: Node in get_tree().root.find_children("*", "Projectile", true, false):
		if n.get("active"):
			found = true
			assert_almost_eq((n as Node2D).global_position.y, _player.global_position.y, 0.5,
				"la trajectoire est au niveau des pieds (hitbox)")
			assert_gt(float(n.get("visual_height")), 0.0, "le dessin est surélevé à la hauteur du canon")
	assert_true(found, "un projectile a été tiré")


func test_aim_assist_snaps_to_enemy_in_cone() -> void:
	var e := _add_enemy(_player.global_position + Vector2(300, 40))  # ~7,6° sous l'axe
	var dir: Vector2 = _player.call("apply_aim_assist", Vector2.RIGHT)
	var expected := (e.global_position - _player.global_position).normalized()
	assert_almost_eq(dir.angle(), expected.angle(), 0.001)


func test_aim_assist_ignores_enemy_outside_cone() -> void:
	_add_enemy(_player.global_position + Vector2(200, 200))  # 45°
	var dir: Vector2 = _player.call("apply_aim_assist", Vector2.RIGHT)
	assert_eq(dir, Vector2.RIGHT)


func test_aim_assist_ignores_hidden_enemy() -> void:
	var e := _add_enemy(_player.global_position + Vector2(300, 0))
	e.visible = false  # caché par le brouillard
	var dir: Vector2 = _player.call("apply_aim_assist", Vector2(1, 0.1).normalized())
	assert_almost_eq(dir.angle(), Vector2(1, 0.1).angle(), 0.001)


# --- Armes multiples (API du contrat) -------------------------------------------------

func _weapon(id: String, cat: StringName, mag: int = 4) -> WeaponData:
	var w := WeaponData.new()
	w.id = StringName(id)
	w.category = cat
	w.magazine_size = mag
	w.reload_time = 0.5
	w.fire_rate = 10.0
	return w


func test_set_weapons_switch_and_signals() -> void:
	var p := _player as Player
	watch_signals(p)
	var list: Array[WeaponData] = [_weapon("pistol", &"pistol"), _weapon("sniper", &"sniper", 3)]
	p.set_weapons(list)
	assert_signal_emitted(p, "weapons_changed")
	assert_signal_emitted(p, "ammo_changed")
	assert_eq(p.get_weapons().size(), 3, "3 emplacements")
	assert_eq(p.current_slot, 0)
	assert_eq(String(p.weapon.id), "pistol")
	p.switch_to(1)
	assert_eq(p.current_slot, 1)
	assert_eq(p.get_ammo(), 3)
	p.next_weapon()
	assert_eq(p.current_slot, 0, "suivant : boucle en sautant le vide")
	p.switch_to(2)
	assert_eq(p.current_slot, 0, "emplacement vide refusé")


func test_fire_consumes_ammo_and_auto_reloads() -> void:
	await wait_physics_frames(2)
	var p := _player as Player
	var list: Array[WeaponData] = [_weapon("pistol", &"pistol", 2), _weapon("smg", &"smg", 30)]
	p.set_weapons(list)
	p.fire(Vector2.RIGHT)
	assert_eq(p.get_ammo(), 1)
	p.loadout.cooldown = 0.0
	p.fire(Vector2.RIGHT)
	assert_eq(p.get_ammo(), 0)
	assert_true(p.is_reloading(), "rechargement automatique quand vide")
	p.switch_to(1)
	assert_false(p.is_reloading(), "annulé au changement d'arme")
	p.switch_to(0)
	assert_eq(p.get_ammo(), 0)
	p.reload()
	assert_true(p.is_reloading())
	for i: int in 40:
		p._physics_process(1.0 / 60.0)
	assert_false(p.is_reloading())
	assert_eq(p.get_ammo(), 2)


func test_equip_into_current_slot_and_carried_ids() -> void:
	var p := _player as Player
	var a := _weapon("a", &"rifle")
	var b := _weapon("b", &"shotgun")
	var list: Array[WeaponData] = [a]
	p.set_weapons(list)
	var old: WeaponData = p.equip_into_current_slot(b)
	assert_eq(old, a)
	assert_eq(p.weapon, b)
	var ids: Array[StringName] = p.get_carried_weapon_ids()
	assert_eq(ids, [&"b"] as Array[StringName])


func test_heavy_weapon_slows_player() -> void:
	var p := _player as Player
	var w := _weapon("lmg", &"lmg")
	w.move_speed_mult = 0.8
	var list: Array[WeaponData] = [w]
	p.set_weapons(list)
	assert_almost_eq(p.get_effective_speed(), p.move_speed * 0.8, 0.01)


func test_missing_weapon_sprite_falls_back_to_drawing() -> void:
	var p := _player as Player
	var w := _weapon("inconnue", &"grenade_launcher")
	w.sprite_id = &"sprite_qui_n_existe_pas"
	var list: Array[WeaponData] = [w]
	p.set_weapons(list)
	var view: WeaponView = p.visual.weapon_view
	assert_eq(view.weapon, w)
	assert_gt(view.muzzle_local.x, 10.0, "canon de la silhouette dessinée")


# --- Explosion : dégâts en zone et ligne de vue -----------------------------------------

class DummyTarget extends Node2D:
	var hits: Array[float] = []
	func _init() -> void:
		add_to_group(&"damageable")
	func take_damage(amount: float, _source: Node) -> void:
		hits.append(amount)
	func is_alive() -> bool:
		return true


func _target(pos: Vector2) -> DummyTarget:
	var t := DummyTarget.new()
	add_child_autofree(t)
	t.global_position = pos
	return t


func test_explosion_damage_decreases_with_distance() -> void:
	var near := _target(Vector2(1000, 1000))
	var far := _target(Vector2(1080, 1000))
	var out := _target(Vector2(1200, 1000))
	var hit: Array[Node2D] = Explosion.apply_damage(get_tree(), null, Vector2(1000, 1000), 100.0, 60.0, null)
	assert_eq(hit.size(), 2)
	assert_almost_eq(near.hits[0], 60.0, 0.01)
	assert_lt(far.hits[0], near.hits[0], "décroissant")
	assert_true(out.hits.is_empty(), "hors rayon")


func test_explosion_blocked_by_wall() -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 200)
	shape.shape = rect
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = Vector2(2040, 2000)
	var behind := _target(Vector2(2080, 2000))
	var open := _target(Vector2(2000, 2060))
	await wait_physics_frames(2)
	var space := (_player as Node2D).get_world_2d().direct_space_state
	Explosion.apply_damage(get_tree(), space, Vector2(2000, 2000), 120.0, 50.0, null)
	assert_true(behind.hits.is_empty(), "mur entre le centre et la cible : aucun dégât")
	assert_eq(open.hits.size(), 1, "cible à découvert touchée")


func test_explosion_spares_player_mostly() -> void:
	var p := _player as Player
	var hp0: float = p.hp
	var amounts: Array = []
	Explosion.apply_damage(get_tree(), null, p.global_position, 100.0, 40.0, p, 0.25, 0.25, amounts)
	assert_almost_eq(hp0 - p.hp, 10.0, 0.01, "le joueur ne subit que 25 %")


# --- Pools sans fuite ----------------------------------------------------------------

func test_projectile_pool_no_leak() -> void:
	await wait_physics_frames(2)
	var p := _player as Player
	var w := _weapon("smg", &"smg", 0)
	var list: Array[WeaponData] = [w]
	p.set_weapons(list)
	var pool: ProjectilePool = p.projectile_pool
	for i: int in 30:
		p.loadout.cooldown = 0.0
		p.fire(Vector2.RIGHT)
	var size_after: int = pool.get_pool_size()
	pool.release_all()
	assert_eq(pool.get_active_count(), 0, "tous rendus au pool")
	for i: int in 30:
		p.loadout.cooldown = 0.0
		p.fire(Vector2.RIGHT)
	pool.release_all()
	assert_eq(pool.get_pool_size(), size_after, "réutilisation : le pool ne grossit pas")


func test_fx_layer_capacity_bounded_and_stops() -> void:
	var layer := FxLayer.new()
	add_child_autofree(layer)
	layer.setup(16)
	for i: int in 100:
		layer.emit(FxLayer.Kind.SPARK, Vector2.ZERO, Vector2.RIGHT * 10.0, 0.1, 1.0, 1.0, Color.WHITE)
	assert_eq(layer.get_alive_count(), 16, "capacité fixe : les plus anciennes sont recyclées")
	assert_true(layer.is_processing())
	for i: int in 10:
		layer._process(0.05)
	assert_eq(layer.get_alive_count(), 0)
	assert_false(layer.is_processing(), "au repos : plus aucun _process")


func test_rocket_explodes_on_wall() -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 300)
	shape.shape = rect
	wall.add_child(shape)
	add_child_autofree(wall)
	wall.global_position = Vector2(400, 100)
	var victim := _target(Vector2(360, 140))
	var w := _weapon("rocket", &"rocket_launcher", 1)
	w.projectile_style = &"rocket"
	w.projectile_speed = 600.0
	w.projectile_lifetime = 2.0
	w.explosion_radius = 90.0
	w.explosion_damage = 50.0
	var list: Array[WeaponData] = [w]
	(_player as Player).set_weapons(list)
	await wait_physics_frames(2)
	(_player as Player).fire(Vector2.RIGHT)
	await wait_physics_frames(50)
	assert_eq(victim.hits.size(), 1, "explosion au mur : la cible proche est touchée")
