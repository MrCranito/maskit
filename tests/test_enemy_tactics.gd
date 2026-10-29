extends GutTest
## IA de combat des ennemis (refonte) : couverts, flanquement, zigzag, télégraphes avant le tir,
## schémas d'attaque (rafale, tir précis, dynamite, ruée + combo), réactions (étourdissement,
## repli, phase 2 de l'élite), recherche du joueur perdu, cadavres persistants et fouillables,
## butin au sol, variantes d'apparition, performance (ennemis lointains endormis).


class FakePlayer extends CharacterBody2D:
	var hp: float = 1000.0
	var hits: Array = []

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

	func take_damage(amount: float, source: Node) -> void:
		hp -= amount
		hits.append([amount, source])

	func is_alive() -> bool:
		return hp > 0.0


var _world: Node2D
var _player: FakePlayer
var _saved_player: Node2D
var _saved_difficulty: int = 1
var _saved_inventory: Inventory = null


func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_player = FakePlayer.new()
	_player.position = Vector2(5000, 5000)
	_world.add_child(_player)
	_saved_player = GameState.player
	GameState.player = _player
	_saved_difficulty = GameState.difficulty
	GameState.difficulty = 1
	_saved_inventory = GameState.raid_inventory
	EnemyTactics.override_map = null


func after_each() -> void:
	GameState.player = _saved_player
	GameState.difficulty = _saved_difficulty
	GameState.raid_inventory = _saved_inventory
	EnemyTactics.override_map = null
	LootManager.set("_loot_root", null)
	LootManager.set("_layout", null)
	LootManager.corpse_records.clear()
	LootManager.ground_records.clear()
	var pool := get_tree().get_first_node_in_group(EnemyProjectilePool.GROUP)
	if pool != null:
		pool.queue_free()
	for d: Node in get_tree().get_nodes_in_group(&"enemy_dynamite"):
		d.queue_free()


func _data(kind: StringName) -> EnemyData:
	var d := (load("res://data/enemies/%s.tres" % kind) as EnemyData).duplicate() as EnemyData
	d.sight_gain = 40.0
	d.detection_angle_deg = 360.0
	d.patrol_radius = 0.0
	d.alert_duration = 0.05
	return d


func _spawn(kind: StringName, pos: Vector2, data: EnemyData = null) -> Enemy:
	var e := Enemy.spawn(data if data != null else _data(kind))
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


## Étage de test : 16 × 12 cases de rue, un bloc de mur (rocher) en `block`.
func _layout_with_block(block: Rect2i) -> FloorLayout:
	var l := FloorLayout.new(Vector2i(16, 12))
	l.fill_rect(Rect2i(0, 0, 16, 12), FloorLayout.Tile.STREET)
	l.fill_rect(block, FloorLayout.Tile.WALL)
	return l


func _cell_rect(r: Rect2i) -> Rect2:
	var ts := float(FloorLayout.TILE_SIZE)
	return Rect2(Vector2(r.position) * ts, Vector2(r.size) * ts)


# --- Couverts -------------------------------------------------------------------------

func test_cover_map_lists_cells_next_to_obstacles() -> void:
	var l := _layout_with_block(Rect2i(7, 5, 1, 1))
	var m := EnemyTactics.build_map(l)
	assert_gt(m.size(), 0, "des couverts")
	var left := m.points.find(FloorLayout.cell_to_world(Vector2i(6, 5)))
	assert_ne(left, -1, "la case à gauche du rocher est un couvert")
	assert_almost_eq(m.obstacle_dirs[left].dot(Vector2.RIGHT), 1.0, 0.01, "obstacle à droite")
	assert_eq(m.points.find(FloorLayout.cell_to_world(Vector2i(2, 2))), -1, "case dégagée : pas un couvert")


func test_cover_chosen_with_obstacle_between_enemy_and_player() -> void:
	var l := _layout_with_block(Rect2i(7, 4, 1, 3))
	var m := EnemyTactics.build_map(l)
	var threat := FloorLayout.cell_to_world(Vector2i(12, 5))
	var from := FloorLayout.cell_to_world(Vector2i(3, 5))
	var i := EnemyTactics.find_cover(m, from, threat, 150.0, 500.0, 400.0, 1)
	assert_ne(i, -1, "un couvert trouvé")
	var p := m.points[i]
	assert_lt(p.x, FloorLayout.cell_to_world(Vector2i(7, 5)).x, "couvert du côté de l'ennemi")
	assert_gt(EnemyTactics.cover_alignment(m, i, (threat - p).normalized()), 0.75, "l'obstacle fait face au joueur")
	# Menace du même côté que l'ennemi : le couvert de gauche ne protège plus.
	var j := EnemyTactics.find_cover(m, from, FloorLayout.cell_to_world(Vector2i(1, 5)), 150.0, 500.0, 400.0, 1)
	if j != -1:
		assert_gt(m.points[j].x, FloorLayout.cell_to_world(Vector2i(7, 5)).x, "couvert de l'autre côté du rocher")


func test_cover_claimed_by_one_enemy_only() -> void:
	var l := _layout_with_block(Rect2i(7, 5, 1, 1))
	var m := EnemyTactics.build_map(l)
	var threat := FloorLayout.cell_to_world(Vector2i(13, 5))
	var from := FloorLayout.cell_to_world(Vector2i(4, 5))
	var a := EnemyTactics.find_cover(m, from, threat, 150.0, 600.0, 400.0, 1)
	assert_ne(a, -1)
	m.claim(a, 1)
	var b := EnemyTactics.find_cover(m, from, threat, 150.0, 600.0, 400.0, 2)
	assert_ne(b, a, "un autre ennemi prend un autre couvert")
	m.release(1)
	assert_false(m.is_claimed_by_other(a, 2), "libéré")


func test_enemy_takes_cover_in_scene() -> void:
	var block := Rect2i(7, 4, 1, 3)
	var l := _layout_with_block(block)
	EnemyTactics.override_map = EnemyTactics.build_map(l)
	_add_wall(_cell_rect(block))
	_player.global_position = FloorLayout.cell_to_world(Vector2i(11, 5))
	var e := _spawn(&"gunslinger", FloorLayout.cell_to_world(Vector2i(3, 5)))
	await wait_physics_frames(2)
	assert_true(e.seek_cover(_player.global_position, e.data.range_min(), e.data.range_max() * 1.1), "couvert trouvé")
	assert_false(e.has_line_between(_player.global_position, e.cover_position), "le mur arrête les balles")
	assert_lt(e.cover_position.distance_to(_cell_rect(block).get_center()), 130.0, "contre le rocher")


# --- Flanquement, zigzag -----------------------------------------------------------------

func test_flank_sides() -> void:
	assert_eq(EnemyTactics.flank_side(0, 3), 0, "le premier attaque de face")
	assert_eq(EnemyTactics.flank_side(1, 3), 1)
	assert_eq(EnemyTactics.flank_side(2, 3), -1)
	assert_eq(EnemyTactics.flank_side(1, 1), 0, "seul : pas de contournement")
	var p := Vector2.ZERO
	var e := Vector2(300, 0)
	var left := EnemyTactics.flank_point(e, p, 1, 200.0, 65.0)
	var right := EnemyTactics.flank_point(e, p, -1, 200.0, 65.0)
	assert_almost_eq(left.length(), 200.0, 0.1)
	assert_almost_eq(rad_to_deg(absf(left.angle_to(right))), 130.0, 0.5, "de part et d'autre")


func test_engaged_enemies_spread_on_flanks() -> void:
	_player.global_position = Vector2(400, 0)
	var es: Array[Enemy] = []
	for i in 3:
		es.append(_spawn(&"outlaw_knife", Vector2(0, -60 + 60 * i)))
	await wait_physics_frames(2)
	for e: Enemy in es:
		e.become_aware(_player.global_position, false)
	await wait_physics_frames(2)
	var sides := []
	for e: Enemy in es:
		sides.append(e.update_flank_side())
	sides.sort()
	assert_eq(sides, [-1, 0, 1], "un de face, un par côté")


func test_zigzag_alternates() -> void:
	assert_eq(EnemyTactics.zigzag_lateral(0.1, 0.6, 0.0, 200.0), 0.0, "sans amplitude : ligne droite")
	var a := EnemyTactics.zigzag_lateral(0.1, 0.6, 40.0, 200.0)
	var b := EnemyTactics.zigzag_lateral(0.4, 0.6, 40.0, 200.0)
	assert_gt(absf(a), 0.0)
	assert_lt(a * b, 0.0, "change de côté chaque demi-période")
	var d := EnemyTactics.zigzag_dir(Vector2.ZERO, Vector2(500, 0), 0.1, 0.6, 40.0)
	assert_gt(d.x, 0.5, "avance toujours vers la cible")
	assert_ne(d.y, 0.0, "avec un écart latéral")


# --- Schémas d'attaque et télégraphes -------------------------------------------------------

func test_rifleman_aim_line_before_precise_shot() -> void:
	var d := _data(&"rifleman")
	var e := _spawn(&"rifleman", Vector2.ZERO, d)
	_player.global_position = Vector2(450, 0)
	var fired: Array = []
	var cb := func(p: Node) -> void: fired.append([p, Time.get_ticks_msec()])
	EventBus.projectile_fired.connect(cb)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_ATTACK, 2.0)
	var t0 := Time.get_ticks_msec()
	await wait_physics_frames(3)
	assert_gt(float(e.visual.get("_aim_line_t")), -0.5, "ligne de visée rouge affichée")
	assert_eq(fired.size(), 0, "pas de tir pendant le télégraphe")
	await wait_until(func() -> bool: return fired.size() > 0, 3.0)
	EventBus.projectile_fired.disconnect(cb)
	assert_gt(fired.size(), 0, "tir parti")
	if fired.size() > 0:
		assert_gt(float(fired[0][1] - t0), d.attack_windup * 1000.0 * 0.8, "tir après le télégraphe")
		var proj := fired[0][0] as EnemyProjectile
		assert_gt(proj.speed, 800.0, "tir précis rapide")


func test_gunslinger_fires_burst_of_three() -> void:
	var d := _data(&"gunslinger")
	d.aim_spread_deg = 0.0
	var e := _spawn(&"gunslinger", Vector2.ZERO, d)
	_player.global_position = Vector2(260, 0)
	var fired: Array = []
	var cb := func(p: Node) -> void: fired.append(p)
	EventBus.projectile_fired.connect(cb)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_ATTACK, 2.0)
	await wait_until(func() -> bool: return fired.size() >= 3, 2.0)
	EventBus.projectile_fired.disconnect(cb)
	assert_eq(fired.size(), d.burst_count, "rafale de 3")


func test_dynamiter_lobs_dynamite_with_ground_circle() -> void:
	var d := _data(&"dynamiter")
	var e := _spawn(&"dynamiter", Vector2.ZERO, d)
	_player.global_position = Vector2(260, 0)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_ATTACK, 2.0)
	await wait_physics_frames(2)
	assert_gt(float(e.visual.get("_marker_t")), -0.5, "cercle au sol avant le lancer")
	await wait_until(func() -> bool: return not get_tree().get_nodes_in_group(&"enemy_dynamite").is_empty(), 2.0)
	var dyn := get_tree().get_first_node_in_group(&"enemy_dynamite") as EnemyDynamite
	assert_not_null(dyn, "bâton lancé")
	if dyn == null:
		return
	assert_lt(dyn.target.distance_to(_player.global_position), d.throw_radius, "visé sur le joueur")
	var hp0 := _player.hp
	var did := dyn.get_instance_id()
	await wait_until(func() -> bool: return not is_instance_id_valid(did), 3.0)
	assert_lt(_player.hp, hp0, "l'explosion blesse le joueur resté dans le cercle")


func test_dynamite_damage_falls_off_and_spares_far_targets() -> void:
	_player.global_position = Vector2(500, 0)
	var n := EnemyDynamite.apply_damage(get_tree(), Vector2.ZERO, 90.0, 20.0, null, 0.5, 0.3)
	assert_eq(n, 0, "hors du cercle : rien")
	_player.global_position = Vector2(10, 0)
	var hp0 := _player.hp
	EnemyDynamite.apply_damage(get_tree(), Vector2.ZERO, 90.0, 20.0, null, 0.5, 0.3)
	assert_almost_eq(hp0 - _player.hp, Explosion.falloff_damage(10.0, 90.0, 20.0, 0.3), 0.01, "dégâts pleins au centre")


func test_knife_lunges_and_combo() -> void:
	var d := _data(&"outlaw_knife")
	d.zigzag_amplitude = 0.0
	var e := _spawn(&"outlaw_knife", Vector2.ZERO, d)
	_player.global_position = Vector2(140, 0)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_ATTACK, 2.0)
	var x0 := e.global_position.x
	await wait_until(func() -> bool: return _player.hits.size() >= 2, 2.5)
	assert_gt(e.global_position.x - x0, 40.0, "ruée vers le joueur")
	assert_gte(_player.hits.size(), 2, "combo de deux coups")


func test_knife_windup_is_visible_before_lunge() -> void:
	var d := _data(&"outlaw_knife")
	var e := _spawn(&"outlaw_knife", Vector2.ZERO, d)
	_player.global_position = Vector2(140, 0)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_ATTACK, 2.0)
	await wait_physics_frames(2)
	assert_gt(float(e.visual.get("_windup_t")), -0.5, "élan (lueur rouge) avant la ruée")
	assert_eq(_player.hits.size(), 0, "pas de coup pendant l'élan")


# --- Réactions ------------------------------------------------------------------------

func test_big_hit_staggers() -> void:
	var e := _spawn(&"gunslinger", Vector2.ZERO)
	_player.global_position = Vector2(300, 0)
	await wait_physics_frames(2)
	e.become_aware(_player.global_position)
	await wait_physics_frames(2)
	e.take_damage(e.max_hp * 0.5, _player)
	assert_eq(e.current_state_name(), Enemy.STATE_STUNNED, "étourdi par un gros coup")


func test_low_hp_retreats_once() -> void:
	var e := _spawn(&"gunslinger", Vector2.ZERO)
	_player.global_position = Vector2(150, 0)
	e.data.stagger_ratio = 0.0
	await wait_until(func() -> bool: return e.is_in_combat(), 1.5)
	e.take_damage(e.max_hp * 0.8, _player)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_RETREAT, 1.5)
	assert_eq(e.current_state_name(), Enemy.STATE_RETREAT, "repli à faible vie")
	assert_true(e.has_retreated)
	assert_false(e.should_retreat(), "une seule fois")


func test_elite_enters_phase_two() -> void:
	var e := _spawn(&"gang_boss", Vector2.ZERO)
	_player.global_position = Vector2(300, 0)
	await wait_physics_frames(2)
	var v1 := e.run_speed()
	e.take_damage(e.max_hp * 0.55, _player)
	assert_eq(e.phase, 2, "phase 2 sous 50 % des PV")
	assert_gt(e.run_speed(), v1, "plus rapide")
	e.phase = 2
	var seen := {}
	for i in 4:
		seen[e.next_pattern()] = true
	assert_true(seen.has(&"lob") and seen.has(&"burst"), "alterne rafale et dynamite")


func test_lost_player_triggers_search() -> void:
	var d := _data(&"gunslinger")
	d.lose_sight_time = 0.3
	var e := _spawn(&"gunslinger", Vector2.ZERO, d)
	_player.global_position = Vector2(250, 0)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_CHASE \
		or e.current_state_name() == Enemy.STATE_ATTACK, 1.5)
	_add_wall(Rect2(Vector2(100, -400), Vector2(30, 800)))
	_player.global_position = Vector2(400, 0)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_SEARCH, 3.0)
	assert_eq(e.current_state_name(), Enemy.STATE_SEARCH, "fouille la zone où il a perdu le joueur")


# --- Cadavres et butin ---------------------------------------------------------------------

func _register_floor() -> Node2D:
	var root := Node2D.new()
	root.name = "Loot"
	_world.add_child(root)
	LootManager.register_floor(_layout_with_block(Rect2i(7, 5, 1, 1)), root, 1234, 1)
	return root


func test_corpse_stays_on_ground_and_is_searchable() -> void:
	var root := _register_floor()
	var e := _spawn(&"gunslinger", Vector2(200, 200))
	await wait_physics_frames(2)
	var eid := e.get_instance_id()
	e.take_damage(10000.0, _player)
	await wait_until(func() -> bool: return not is_instance_id_valid(eid), 3.0)
	assert_false(is_instance_id_valid(eid), "l'ennemi est remplacé")
	var corpses := root.get_children().filter(func(n: Node) -> bool: return n is EnemyCorpse)
	assert_eq(corpses.size(), 1, "un cadavre au sol")
	if corpses.is_empty():
		return
	var c := corpses[0] as EnemyCorpse
	assert_almost_eq(c.global_position.distance_to(Vector2(200, 200)), 0.0, 1.0, "à l'endroit de la mort")
	assert_lt(c.z_index, 10, "sous les personnages")
	assert_false(c.is_processing(), "aucun traitement par image")
	assert_eq(c.find_children("*", "CollisionObject2D", true, false).size(), 0, "aucune collision")
	assert_true(c.is_in_group(&"interactables") and c.is_in_group(&"containers"))
	assert_eq(c.get_interact_label(), "Fouiller")
	assert_not_null(c.get_node_or_null(^"Sprite"), "sprite de la pose finale")
	var preset := c.preset_entries.size()
	c.force_open()
	assert_eq(c.entries.size(), preset, "contenu tiré à la mort")
	assert_eq(LootManager.corpse_records.get(0, []).size(), 1, "mémorisé pour l'étage")


func test_corpse_restored_after_floor_change() -> void:
	var root := _register_floor()
	var e := _spawn(&"outlaw_knife", Vector2(100, 100))
	await wait_physics_frames(2)
	var eid := e.get_instance_id()
	e.take_damage(10000.0, _player)
	await wait_until(func() -> bool: return not is_instance_id_valid(eid), 3.0)
	var c := root.get_children().filter(func(n: Node) -> bool: return n is EnemyCorpse)[0] as EnemyCorpse
	c.force_open()
	var inv := Inventory.new(6, 4, 999.0)
	c.take_all(inv)
	assert_true(c.is_emptied(), "fouillé et vidé")
	# Changement d'étage : l'étage est détruit puis reconstruit.
	root.queue_free()
	await wait_physics_frames(1)
	var root2 := Node2D.new()
	_world.add_child(root2)
	LootManager.restore_floor(0, root2)
	var back := root2.get_children().filter(func(n: Node) -> bool: return n is EnemyCorpse)
	assert_eq(back.size(), 1, "le cadavre est toujours là au retour")
	if not back.is_empty():
		assert_true((back[0] as EnemyCorpse).is_emptied(), "et toujours vidé")
		assert_almost_eq((back[0] as EnemyCorpse).position.distance_to(Vector2(100, 100)), 0.0, 1.0)


func test_ground_drop_follows_chance() -> void:
	var d := _data(&"gunslinger")
	var keys: Array[StringName] = []
	d.ground_drop_chance = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var always := LootManager.roll_enemy_loot(d, rng, 1, 0, keys)
	assert_false((always["ground"] as Array).is_empty(), "chance 1 : butin au sol")
	assert_false((always["corpse"] as Array).is_empty() and LootManager.corpse_table_for(d).empty_chance == 0.0)
	d.ground_drop_chance = 0.0
	var none := LootManager.roll_enemy_loot(d, rng, 1, 0, keys)
	assert_true((none["ground"] as Array).is_empty(), "chance 0 : rien au sol")
	d.ground_drop_chance = 0.35
	var n := 0
	for i in 400:
		if not (LootManager.roll_enemy_loot(d, rng, 1, 0, keys)["ground"] as Array).is_empty():
			n += 1
	assert_between(float(n) / 400.0, 0.25, 0.45, "proportion réglable (~35 %%)")


func test_archetype_corpse_tables() -> void:
	for k: StringName in [&"outlaw_knife", &"gunslinger", &"shotgun_brute", &"rifleman", &"dynamiter", &"gang_boss"]:
		var t := LootManager.corpse_table_for(load("res://data/enemies/%s.tres" % k) as EnemyData)
		assert_not_null(t, k)
		assert_eq(t.kind, StringName("enemy_" + String(k)), "table propre à %s" % k)
		for id: Variant in t.entries:
			assert_true(LootDB.has_item(StringName(id)), "%s : %s existe" % [k, id])
	assert_not_null(LootDB.get_table(&"enemy_drop"))
	# Autres biomes : table du biome.
	var mall := load("res://data/enemies/mall_guard.tres") as EnemyData
	assert_eq(LootManager.corpse_table_for(mall, &"enemy_mall").kind, &"enemy_mall")


func test_ground_loot_picked_up_by_walking_or_stays_if_bag_full() -> void:
	var it := LootDB.get_item(&"bandage")
	GameState.raid_inventory = Inventory.new(6, 4, 999.0)
	var g := GroundLoot.create(it, 2, Vector2(300, 0), Vector2(300, 0), false)
	_world.add_child(g)
	_player.global_position = Vector2(300, 0)
	await wait_physics_frames(4)
	assert_false(is_instance_valid(g), "ramassé en marchant dessus")
	assert_eq(GameState.raid_inventory.count_of(&"bandage"), 2)
	# Sac plein.
	GameState.raid_inventory = Inventory.new(1, 1, 999.0)
	GameState.raid_inventory.add_item(LootDB.get_item(&"gold_bar"), 1)
	_player.global_position = Vector2(5000, 5000)
	var g2 := GroundLoot.create(it, 1, Vector2(600, 0), Vector2(600, 0), false)
	_world.add_child(g2)
	await wait_physics_frames(2)
	_player.global_position = Vector2(600, 0)
	await wait_physics_frames(4)
	assert_true(is_instance_valid(g2), "sac plein : reste au sol")
	assert_eq(g2.get_interact_label(), "Ramasser", "ramassable plus tard par l'interaction")


func test_corpse_count_is_capped() -> void:
	var root := _register_floor()
	var cap := int(LootDB.cfg().get_value("enemy_loot", "max_corpses_per_floor", 30))
	var list: Array[Node2D] = LootManager.get("_corpses")
	for i in cap + 5:
		var c := EnemyCorpse.create_corpse(&"gunslinger", Vector2(i, 0), {}, "x")
		root.add_child(c)
		list.append(c)
	LootManager.call("_enforce_corpse_limit")
	await wait_physics_frames(1)
	assert_eq(LootManager.get_corpse_count(), cap, "nombre de cadavres limité")


# --- Variantes et performance -------------------------------------------------------------

func test_variants_are_deterministic_and_mixed() -> void:
	assert_eq(EnemyVariants.roll_kind(&"gunslinger", 42), EnemyVariants.roll_kind(&"gunslinger", 42))
	var seen := {}
	for s in 60:
		seen[EnemyVariants.roll_kind(&"gunslinger", s)] = true
	assert_true(seen.has(&"gunslinger") and seen.has(&"rifleman"), "pistoleros et tireurs embusqués")
	assert_eq(EnemyVariants.roll_kind(&"golem", 3), &"golem", "pas de variantes : inchangé")


func test_far_enemies_sleep_and_leave_active_list() -> void:
	_player.global_position = Vector2.ZERO
	var es: Array[Enemy] = []
	for i in 30:
		es.append(_spawn(&"gunslinger", Vector2(4000 + 60 * i, 3000)))
	await wait_physics_frames(2)
	for e: Enemy in es:
		e._on_sleep_check()
	var asleep := 0
	for e: Enemy in es:
		if e.asleep and not e.is_physics_processing() and not Enemy.active_units.has(e):
			asleep += 1
	assert_eq(asleep, 30, "IA endormie loin du joueur")


func test_awake_enemies_frame_cost() -> void:
	# 24 ennemis éveillés en combat dans une arène ouverte : coût physique moyen par image.
	_player.global_position = Vector2.ZERO
	var kinds: Array[StringName] = [&"outlaw_knife", &"gunslinger", &"shotgun_brute", &"rifleman", &"dynamiter", &"gang_boss"]
	for i in 24:
		_spawn(kinds[i % kinds.size()], Vector2.from_angle(TAU * float(i) / 24.0) * 420.0)
	await wait_physics_frames(30)
	Enemy.profile_usec = 0
	Enemy.profiling = true
	await wait_physics_frames(120)
	Enemy.profiling = false
	var avg_ms := float(Enemy.profile_usec) / 120.0 / 1000.0
	gut.p("IA ennemie : %.3f ms/image pour 24 ennemis en combat (%.1f µs/ennemi)" % [avg_ms, avg_ms * 1000.0 / 24.0])
	assert_lt(avg_ms, 4.0, "budget IA raisonnable (scripts, hors moteur physique)")
