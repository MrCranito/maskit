extends GutTest
## Non-régression : un renfort n'appelle pas de renforts ([enemy_skills] reinforcements_can_summon).
## Avant le correctif, le loup des glaces (sifflet « whistle » qui appelle un loup, PV à 100 %)
## appelait un loup qui appelait un loup… : 21 loups devenaient ~870 en 60 s sur les Terres gelées.


class FakePlayer extends CharacterBody2D:
	var hp: float = 100000.0

	func _ready() -> void:
		add_to_group(&"player")
		add_to_group(&"damageable")
		collision_layer = 2
		collision_mask = 0
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 16.0
		cs.shape = c
		add_child(cs)

	func take_damage(amount: float, _source: Node) -> void:
		hp -= amount

	func apply_status(_k: StringName, _d: float, _s: float = 1.0, _f: Vector2 = Vector2.INF) -> void:
		pass

	func has_status_kind(_k: StringName) -> bool:
		return false

	func is_aiming() -> bool:
		return false

	func is_alive() -> bool:
		return hp > 0.0


var _world: Node2D
var _player: FakePlayer
var _saved_player: Node2D


func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_player = FakePlayer.new()
	_player.position = Vector2(400, 0)
	_world.add_child(_player)
	_saved_player = GameState.player
	GameState.player = _player


func after_each() -> void:
	GameState.player = _saved_player
	for n: Node in get_tree().get_nodes_in_group(&"enemy_units"):
		n.queue_free()


func _wolf(pos: Vector2) -> Enemy:
	var d := (load("res://data/enemies/ice_wolf.tres") as EnemyData).duplicate() as EnemyData
	d.sight_gain = 40.0
	d.detection_angle_deg = 360.0
	d.patrol_radius = 0.0
	var e := Enemy.spawn(d)
	e.position = pos
	_world.add_child(e)
	return e


func _count(kind: StringName) -> int:
	var n := 0
	for u: Node in get_tree().get_nodes_in_group(&"enemy_units"):
		var e := u as Enemy
		if e != null and e.is_alive() and e.data.kind == kind:
			n += 1
	return n


func test_reglage_par_defaut() -> void:
	assert_false(EnemySkill.reinforcements_can_summon(), "[enemy_skills] reinforcements_can_summon = false")


func test_competences_d_appel_declarees() -> void:
	for sid: StringName in [&"whistle", &"ice_lab_call", &"cv_call", &"eg_temple_call", &"eg_raise_dead",
			&"fw_pack_howl", &"mall_alarm", &"ss_drone_launch", &"fw_call_outlaws"]:
		var sk := EnemySkills.create(sid)
		assert_not_null(sk, "compétence %s" % sid)
		if sk != null:
			assert_true(sk.summons(), "%s fait apparaître des ennemis" % sid)
	var other := EnemySkills.create(&"charge")
	assert_false(other.summons(), "une charge n'appelle personne")


func test_renfort_ne_peut_pas_siffler() -> void:
	var chef := _wolf(Vector2.ZERO)
	await wait_physics_frames(2)
	chef.become_aware(_player.global_position, false)
	var renfort := chef.spawn_reinforcement(&"ice_wolf", Vector2(-80, 0))
	assert_not_null(renfort)
	await wait_physics_frames(2)
	assert_true(renfort.is_reinforcement())
	assert_false(chef.is_reinforcement())
	var sk_chef := chef.get_skill(&"whistle")
	var sk_renfort := renfort.get_skill(&"whistle")
	assert_not_null(sk_renfort, "le renfort garde sa compétence (données inchangées)")
	sk_chef.cooldown_left = 0.0
	sk_renfort.cooldown_left = 0.0
	assert_true(sk_chef.can_use(300.0, true), "le loup d'origine peut siffler")
	assert_false(sk_renfort.can_use(300.0, true), "le loup appelé ne siffle pas")


## Meute réelle (données du jeu) pendant 12 s : le loup d'origine appelle au plus max_total
## loups ; sans le correctif la population grossit à chaque génération d'appels.
func test_pas_de_croissance_en_chaine() -> void:
	var chef := _wolf(Vector2.ZERO)
	await wait_physics_frames(2)
	chef.become_aware(_player.global_position, false)
	var max_total := int(chef.get_skill(&"whistle").f("max_total"))
	var peak := 0
	var t := 0.0
	while t < 12.0:
		await wait_physics_frames(6)
		t += 0.1
		# Le chef et ses renforts restent éveillés et en combat.
		for u: Node in get_tree().get_nodes_in_group(&"enemy_units"):
			var e := u as Enemy
			if e != null and e.is_alive() and not e.is_in_combat():
				e.become_aware(_player.global_position, false)
		peak = maxi(peak, _count(&"ice_wolf"))
	assert_lte(peak, 1 + max_total, "au plus le chef + %d renforts (pic : %d)" % [max_total, peak])
