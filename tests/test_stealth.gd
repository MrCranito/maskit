extends GutTest
## Discrétion : jauge de reconnaissance des ennemis (vue, ouïe, cachette, décroissance, paliers).
## Tests déterministes : la boucle physique de l'ennemi est coupée et la perception est
## évaluée à la main (Enemy.update_perception(dt)), comme le ferait le timer de 0,1 s.


class StealthPlayer extends CharacterBody2D:
	var hp: float = 100.0
	var move_speed: float = 250.0
	var noise: float = 0.0
	var is_in_hiding: bool = false

	func _ready() -> void:
		add_to_group(&"player")
		add_to_group(&"damageable")
		collision_layer = 2
		collision_mask = 0
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = 15.0
		cs.shape = c
		add_child(cs)

	func take_damage(amount: float, _source: Node) -> void:
		hp -= amount

	func is_alive() -> bool:
		return hp > 0.0

	func get_noise_level() -> float:
		return 0.0 if is_in_hiding else noise

	func is_hidden() -> bool:
		return is_in_hiding

	func set_hidden(on: bool, _spot: Node = null) -> void:
		is_in_hiding = on


const DT := 0.1

var _world: Node2D
var _player: StealthPlayer
var _saved_player = null


func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_player = StealthPlayer.new()
	_player.position = Vector2(5000, 5000)
	_world.add_child(_player)
	_saved_player = GameState.player if is_instance_valid(GameState.player) else null
	GameState.player = _player


func after_each() -> void:
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null


func _make_data() -> EnemyData:
	var d := EnemyData.new()
	d.kind = &"fw_raider"
	d.detection_radius = 300.0
	d.detection_angle_deg = 360.0
	d.patrol_radius = 0.0
	d.sight_gain = 1.0
	d.hearing_radius = 400.0
	d.hearing_gain = 2.0
	d.awareness_decay = 0.2
	d.awareness_alert_threshold = 1.0
	d.alert_neighbors_radius = 0.0
	return d


## Ennemi « gelé » : pas de boucle physique, perception pilotée par le test.
func _spawn(pos: Vector2, data: EnemyData = null) -> Enemy:
	var e := Enemy.spawn(data if data != null else _make_data())
	e.position = pos
	_world.add_child(e)
	e.set_physics_process(false)
	return e


func _add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = rect.get_center()
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	cs.shape = shape
	body.add_child(cs)
	_world.add_child(body)


func _tick(e: Enemy, n: int) -> void:
	for i: int in n:
		e.update_perception(DT)


func test_new_fields_have_defaults() -> void:
	var d := EnemyData.new()
	assert_gt(d.sight_gain, 0.0)
	assert_gt(d.hearing_radius, 0.0)
	assert_gt(d.hearing_gain, 0.0)
	assert_gt(d.awareness_decay, 0.0)
	assert_almost_eq(d.awareness_alert_threshold, 1.0, 0.001)
	for kind: String in ["fw_bandit", "fw_raider", "fw_sharpshooter", "fw_marauder", "fw_bruiser", "fw_guard_dog", "fw_deserter", "fw_sheriff"]:
		var r := load("res://data/enemies/%s.tres" % kind) as EnemyData
		assert_not_null(r, kind)
		if r != null:
			assert_gt(r.sight_gain, 0.0, kind)
			assert_gt(r.hearing_radius, 0.0, kind)


func test_sight_raises_awareness_faster_when_close() -> void:
	var near := _spawn(Vector2.ZERO)
	var far := _spawn(Vector2(0, 2000))
	_player.global_position = Vector2(60, 0)
	await wait_physics_frames(2)
	_tick(near, 2)
	var near_gain := near.awareness
	assert_true(near.can_see_player, "vu de près")
	assert_gt(near_gain, 0.0, "la jauge monte en vue")
	assert_lt(near_gain, 1.0, "pas instantané")
	_player.global_position = Vector2(0, 2000 + 270)
	await wait_physics_frames(2)
	_tick(far, 2)
	assert_true(far.can_see_player, "vu de loin")
	assert_gt(far.awareness, 0.0)
	assert_gt(near_gain, far.awareness * 4.0, "beaucoup plus vite de près (%.3f vs %.3f)" % [near_gain, far.awareness])


func test_moving_player_is_more_visible() -> void:
	var still := _spawn(Vector2.ZERO)
	_player.global_position = Vector2(150, 0)
	await wait_physics_frames(2)
	_tick(still, 2)
	var g_still := still.awareness
	still.set_awareness(0.0)
	_player.velocity = Vector2(250, 0)
	_tick(still, 2)
	assert_gt(still.awareness, g_still * 1.5, "immobile = moins visible")


func test_wall_blocks_sight() -> void:
	_add_wall(Rect2(Vector2(80, -100), Vector2(40, 200)))
	var e := _spawn(Vector2.ZERO)
	_player.global_position = Vector2(200, 0)
	await wait_physics_frames(2)
	_tick(e, 10)
	assert_false(e.can_see_player)
	assert_eq(e.awareness, 0.0, "aucune montée derrière un mur (joueur silencieux)")
	assert_eq(e.current_state_name(), Enemy.STATE_PATROL)


func test_shot_behind_wall_raises_awareness_and_investigates() -> void:
	_add_wall(Rect2(Vector2(80, -100), Vector2(40, 200)))
	var e := _spawn(Vector2.ZERO)
	e.face(Vector2.LEFT)
	_player.global_position = Vector2(200, 0)
	await wait_physics_frames(2)
	_player.noise = 1.0  # Tir.
	_tick(e, 1)
	assert_false(e.can_see_player, "pas de vue")
	assert_true(e.hears_player, "le tir est entendu")
	assert_gt(e.awareness, 0.3, "un tir proche fait fortement monter la jauge (%.2f)" % e.awareness)
	assert_eq(e.current_state_name(), Enemy.STATE_INVESTIGATE, "suspicion → enquête")
	assert_eq(e.stimulus_position, _player.global_position, "va vers la source du bruit")
	assert_gt(e.facing.dot(Vector2.RIGHT), 0.9, "se tourne vers le bruit")


func test_walls_muffle_sound() -> void:
	var d := _make_data()
	d.detection_radius = 150.0  # Le joueur est entendu sans être vu.
	var open := _spawn(Vector2.ZERO, d)
	var walled := _spawn(Vector2(0, 1500), d)
	_add_wall(Rect2(Vector2(80, 1400), Vector2(40, 200)))
	await wait_physics_frames(2)
	_player.noise = 0.35
	_player.global_position = Vector2(0, 200)  # Hors vue (200 > 150) mais audible.
	_tick(open, 1)
	_player.global_position = Vector2(200, 1500)
	_tick(walled, 1)
	assert_gt(open.awareness, 0.0)
	assert_gt(walled.awareness, 0.0)
	assert_gt(open.awareness, walled.awareness * 2.0, "le mur atténue le son")


func test_hidden_player_not_seen() -> void:
	var e := _spawn(Vector2.ZERO)
	_player.global_position = Vector2(60, 0)
	_player.is_in_hiding = true
	await wait_physics_frames(2)
	_tick(e, 10)
	assert_false(e.can_see_player)
	assert_eq(e.awareness, 0.0, "caché : la jauge ne monte pas")


func test_awareness_decays_when_nothing_perceived() -> void:
	var e := _spawn(Vector2.ZERO)
	e.set_awareness(0.25)
	_player.global_position = Vector2(3000, 0)
	_tick(e, 10)  # 1 s.
	assert_almost_eq(e.awareness, 0.25 - e.data.awareness_decay, 0.01, "décroissance lente")
	_tick(e, 30)
	assert_eq(e.awareness, 0.0)


func test_threshold_triggers_alert() -> void:
	var e := _spawn(Vector2.ZERO)
	var seen: Array = []
	e.state_machine.state_changed.connect(func(_f: StringName, t: StringName) -> void: seen.append(t))
	_player.global_position = Vector2(40, 0)
	_player.velocity = Vector2(200, 0)
	await wait_physics_frames(2)
	var ticks := 0
	while not e.is_in_combat() and ticks < 100:
		_tick(e, 1)
		ticks += 1
	assert_true(e.is_in_combat(), "repéré")
	assert_gt(ticks, 1, "pas instantané")
	assert_eq(e.awareness, 1.0)
	assert_has(seen, Enemy.STATE_ALERT, "jauge pleine → Alert")
	assert_eq(e.get_awareness_tier(), 2)


func test_suspicion_tier_before_alert() -> void:
	var e := _spawn(Vector2.ZERO)
	_player.global_position = Vector2(220, 0)
	await wait_physics_frames(2)
	var ticks := 0
	while e.awareness < 0.35 and ticks < 200:
		_tick(e, 1)
		ticks += 1
	assert_eq(e.get_awareness_tier(), 1, "suspicion")
	assert_eq(e.current_state_name(), Enemy.STATE_INVESTIGATE)


func test_damage_sets_awareness_to_one() -> void:
	var e := _spawn(Vector2.ZERO)
	_player.global_position = Vector2(2000, 0)
	e.take_damage(1.0, _player)
	assert_eq(e.awareness, 1.0)
	assert_eq(e.current_state_name(), Enemy.STATE_ALERT)


func test_neighbor_gets_boost_not_instant_alert() -> void:
	var a := _spawn(Vector2.ZERO)
	var b := _spawn(Vector2(-200, 0))
	a.data = a.data.duplicate()
	a.data.alert_neighbors_radius = 300.0
	_player.global_position = Vector2(2000, 0)
	await wait_physics_frames(2)
	_tick(b, 1)  # b ne voit pas le joueur (trop loin).
	a.become_aware(_player.global_position, true)
	assert_true(a.is_in_combat())
	assert_false(b.is_in_combat(), "voisin non repéré instantanément")
	assert_gt(b.awareness, 0.4)
	assert_lt(b.awareness, 1.0)


func test_enemy_flushes_out_player_seen_hiding() -> void:
	var e := _spawn(Vector2.ZERO)
	_player.global_position = Vector2(120, 0)
	await wait_physics_frames(2)
	e.become_aware(_player.global_position, false)
	_tick(e, 1)
	assert_true(e.can_see_player)
	_player.is_in_hiding = true
	_tick(e, 1)
	assert_true(e.saw_player_hide, "l'a vu se cacher")
	assert_true(e.reveal_hidden_player())
	assert_false(_player.is_in_hiding, "délogé")


func test_far_enemy_sleeps_and_wakes() -> void:
	var e := _spawn(Vector2.ZERO)
	e.set_physics_process(true)
	_player.global_position = Vector2(e.sleep_distance + 400.0, 0)
	e._on_sleep_check()
	assert_true(e.asleep, "loin du joueur : endormi")
	assert_false(e.is_physics_processing())
	_player.global_position = Vector2(100, 0)
	e._on_sleep_check()
	assert_false(e.asleep, "réveillé quand le joueur approche")
	assert_true(e.is_physics_processing())


func test_awareness_bar_visibility() -> void:
	var e := _spawn(Vector2.ZERO)
	var bar := e.get_node("AwarenessBar") as AwarenessBar
	assert_false(bar.visible, "cachée à 0")
	e.set_awareness(0.5)
	assert_true(bar.visible, "visible en cours de remplissage")
	e.become_aware(Vector2(10, 0), false)
	assert_false(bar.visible, "cachée une fois repéré (le « ! » prend le relais)")
	assert_ne(AwarenessBar.fill_color(0.1), AwarenessBar.fill_color(0.9), "jaune → rouge")
