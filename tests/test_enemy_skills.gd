extends GutTest
## Compétences des ennemis (scripts/enemies/skills) : déclaration dans les .tres, recharge,
## conditions, télégraphe AVANT l'effet, effets (projectiles, charge, bouclier, feu, flash,
## kamikaze, téléportation, renforts, rage, piège, perforation, tourelle, onde de choc),
## statuts du joueur (Player.apply_status) et relais coop (marionnettes de l'invité).


class FakePlayer extends CharacterBody2D:
	var hp: float = 1000.0
	var hits: Array = []
	var statuses: Array = []
	var aiming: bool = false
	var aim_direction: Vector2 = Vector2.RIGHT

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

	func apply_status(kind: StringName, duration: float, strength: float = 1.0, _from: Vector2 = Vector2.INF) -> void:
		statuses.append([kind, duration, strength])

	func has_status_kind(kind: StringName) -> bool:
		for s: Array in statuses:
			if s[0] == kind:
				return true
		return false

	func is_aiming() -> bool:
		return aiming

	func is_alive() -> bool:
		return hp > 0.0


## Coop factice (hôte) : enregistre les relais au lieu d'envoyer des paquets.
class FakeCoop extends CoopRaid:
	var log: Array = []

	func on_enemy_visual(e: Node2D, method: StringName, args: Array) -> void:
		log.append([method, args])

	func on_enemy_projectile(_pos: Vector2, _dir: Vector2, _speed: float, _life: float, style: StringName) -> void:
		log.append([&"shot", [style]])

	func on_enemy_dynamite(from: Vector2, to: Vector2, _r: float, _fl: float, _fu: float) -> void:
		log.append([&"dynamite", [from, to]])

	func register_dynamic_enemy(e: Node2D, id: int) -> int:
		log.append([&"register", [id]])
		return 30001 if id < 0 else id


var _world: Node2D
var _player: FakePlayer
var _saved_player: Node2D
var _saved_difficulty: int = 1


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
	EnemyTactics.override_map = null


func after_each() -> void:
	GameState.player = _saved_player
	GameState.difficulty = _saved_difficulty
	EnemyTactics.override_map = null
	NetHooks.reset()
	for g: StringName in [EnemyProjectilePool.GROUP, &"enemy_dynamite", EnemyHazard.GROUP]:
		for n: Node in get_tree().get_nodes_in_group(g):
			n.queue_free()


func _data(kind: StringName) -> EnemyData:
	var d := (load("res://data/enemies/%s.tres" % kind) as EnemyData).duplicate() as EnemyData
	d.sight_gain = 40.0
	d.detection_angle_deg = 360.0
	d.patrol_radius = 0.0
	return d


## Données de test : un kind du jeu (base) dont on remplace les compétences. Sert aux mécaniques
## qu'aucun monstre actuel ne porte plus (lancer de couteau, éventail, bouclier, molotov,
## dynamite à rebond, piège à ours…) : la mécanique reste couverte sans dépendre du bestiaire.
func _custom(base: StringName, skills: Array, fields: Dictionary = {}) -> EnemyData:
	var d := _data(base)
	d.skills = skills.duplicate(true)
	for k: String in fields:
		d.set(k, fields[k])
	return d


## Ancien « bandit au couteau » : roulade + lancer de couteau (sur la base du Pillard).
func _knife_data() -> EnemyData:
	return _custom(&"fw_raider", [
		{"id": &"dodge_roll", "cooldown": 3.5, "chance": 0.55, "distance": 150.0, "duration": 0.3},
		{"id": &"knife_throw", "cooldown": 5.5, "windup": 0.45, "min_range": 150.0, "max_range": 400.0,
			"speed": 640.0, "damage": 10.0, "style": "knife", "priority": 1.2}])


## Ancien « dynamiteur » : molotov + dynamite à rebond (sur la base du Bandit).
func _dynamite_data() -> EnemyData:
	return _custom(&"fw_bandit", [
		{"id": &"molotov", "kind": "fire", "cooldown": 8.5, "windup": 0.6, "min_range": 140.0, "max_range": 360.0,
			"radius": 72.0, "flight": 0.6, "duration": 4.5, "dps": 10.0, "priority": 1.2},
		{"id": &"bounce_dynamite", "kind": "dynamite", "bounce": true, "cooldown": 11.0, "windup": 0.65,
			"min_range": 200.0, "max_range": 400.0, "radius": 85.0, "damage": 22.0, "flight": 0.55, "fuse": 0.75,
			"bounce_flight": 0.35}])


func _spawn(kind: StringName, pos: Vector2, data: EnemyData = null) -> Enemy:
	var e := Enemy.spawn(data if data != null else _data(kind))
	e.position = pos
	_world.add_child(e)
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


## Ennemi prêt au combat à côté du joueur (perception évaluée, IA en Chase).
func _engaged(kind: StringName, enemy_pos: Vector2, player_pos: Vector2, data: EnemyData = null) -> Enemy:
	_player.global_position = player_pos
	var e := _spawn(kind, enemy_pos, data)
	await wait_physics_frames(2)
	e.become_aware(player_pos, false)
	e.update_perception(0.1)
	return e


# --- Déclaration ----------------------------------------------------------------------

func test_every_enemy_declares_known_skills() -> void:
	for f: String in DirAccess.get_files_at("res://data/enemies/"):
		if not f.ends_with(".tres"):
			continue
		var d := load("res://data/enemies/" + f) as EnemyData
		assert_false(d.skills.is_empty(), "%s : au moins une compétence" % f)
		var active := 0
		for entry: Variant in d.skills:
			var sid := StringName(str((entry as Dictionary).get("id", "")))
			assert_true(EnemySkills.has_skill(sid), "%s : compétence %s connue" % [f, sid])
			var s := EnemySkills.create(sid)
			s.setup(null, entry)
			if not s.is_passive():
				active += 1
		assert_gt(active, 0, "%s : au moins une compétence active" % f)


func test_far_west_archetypes_have_skills() -> void:
	for k: StringName in [&"fw_bandit", &"fw_raider", &"fw_sharpshooter", &"fw_marauder", &"fw_bruiser", &"fw_guard_dog"]:
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_gte(d.skills.size(), 1, "%s : au moins une compétence" % k)
	var elite := load("res://data/enemies/fw_deserter.tres") as EnemyData
	assert_gte(elite.skills.size(), 2, "élite : plusieurs compétences")


# --- Recharge, conditions, télégraphe -----------------------------------------------------

func test_cooldown_and_conditions() -> void:
	var e := await _engaged(&"fw_raider", Vector2.ZERO, Vector2(260, 0), _knife_data())
	var s := e.get_skill(&"knife_throw")
	assert_not_null(s)
	s.cooldown_left = 0.0
	assert_true(s.can_use(260.0, true), "à portée, en vue : utilisable")
	assert_false(s.can_use(60.0, true), "trop près : non")
	assert_false(s.can_use(260.0, false), "sans ligne de vue : non")
	assert_true(e.force_skill(&"knife_throw"))
	assert_almost_eq(s.cooldown_left, s.f("cooldown") * e.skill_cooldown_mult(), 0.01, "recharge lancée")
	assert_false(s.can_use(260.0, true), "en recharge : non")
	s.tick_cooldown(s.cooldown_left + 0.1)
	await wait_seconds(1.0)
	assert_true(s.can_use(260.0, true) or s.running, "recharge terminée")


func test_knife_throw_telegraph_before_projectile() -> void:
	var e := await _engaged(&"fw_raider", Vector2.ZERO, Vector2(260, 0), _knife_data())
	var fired: Array = []
	var cb := func(p: Node) -> void: fired.append([p, Time.get_ticks_msec()])
	EventBus.projectile_fired.connect(cb)
	var t0 := Time.get_ticks_msec()
	e.force_skill(&"knife_throw")
	await wait_physics_frames(3)
	assert_gt(float(e.visual.get("_aim_line_t")), -0.5, "ligne de visée (télégraphe)")
	assert_eq(fired.size(), 0, "rien avant la fin du télégraphe")
	await wait_until(func() -> bool: return fired.size() > 0, 2.0)
	EventBus.projectile_fired.disconnect(cb)
	assert_eq(fired.size(), 1)
	if not fired.is_empty():
		assert_gt(float(fired[0][1] - t0), e.get_skill(&"knife_throw").windup() * 1000.0 * 0.8)
		assert_eq((fired[0][0] as EnemyProjectile).style, &"knife", "couteau lancé")


func test_fan_volley_fires_six_in_an_arc() -> void:
	var d := _custom(&"fw_bandit", [{"id": &"fan_volley", "cooldown": 8.0, "windup": 0.8, "min_range": 0.0,
		"max_range": 360.0, "count": 6, "arc_deg": 70.0, "interval": 0.07, "speed": 480.0, "damage": 6.0,
		"style": "bullet", "lifetime": 1.0, "priority": 1.3}])
	var e := await _engaged(&"fw_bandit", Vector2.ZERO, Vector2(250, 0), d)
	var fired: Array = []
	var cb := func(p: Node) -> void: fired.append((p as EnemyProjectile).direction.angle())
	EventBus.projectile_fired.connect(cb)
	e.force_skill(&"fan_volley")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"arc")), "cône rouge pendant la pose")
	assert_eq(fired.size(), 0)
	await wait_until(func() -> bool: return fired.size() >= 6, 2.5)
	EventBus.projectile_fired.disconnect(cb)
	assert_eq(fired.size(), 6, "6 balles")
	fired.sort()
	assert_gt(rad_to_deg(float(fired[5]) - float(fired[0])), 60.0, "en arc")


func test_brute_charge_knocks_down_after_lane_telegraph() -> void:
	var e := await _engaged(&"fw_bruiser", Vector2.ZERO, Vector2(280, 0))
	e.force_skill(&"charge")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"lane")), "couloir au sol")
	assert_lt(e.global_position.x, 10.0, "immobile pendant le télégraphe")
	assert_eq(_player.hits.size(), 0)
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.5)
	assert_gt(_player.hits.size(), 0, "le joueur est percuté")
	assert_true(_player.has_status_kind(&"knockdown"), "renversé")


func test_hard_skin_and_shield_block_frontal_hits() -> void:
	var brute := await _engaged(&"fw_bruiser", Vector2.ZERO, Vector2(100, 0))
	var red := float(brute.get_skill(&"hard_skin").f("reduction"))
	brute.face(Vector2.RIGHT)
	var hp0 := brute.hp
	brute.take_damage(10.0, _player)
	assert_almost_eq(hp0 - brute.hp, 10.0 * (1.0 - red), 0.01, "peau dure : dégâts réduits de face")
	brute.face(Vector2.LEFT)
	hp0 = brute.hp
	brute.take_damage(10.0, _player)
	assert_almost_eq(hp0 - brute.hp, 10.0, 0.01, "de dos : dégâts pleins")
	var shd := _custom(&"fw_deserter", [{"id": &"shield", "style": 0.0, "duration": 3.5, "block": 1.0,
		"cooldown": 12.0, "windup": 0.35, "max_range": 520.0}])
	var boss := await _engaged(&"fw_deserter", Vector2(0, 400), Vector2(300, 400), shd)
	var sh := boss.get_skill(&"shield")
	boss.force_skill(&"shield")
	await wait_until(func() -> bool: return bool(sh.call("is_shield_up")), 2.0)
	boss.face(Vector2.RIGHT)
	hp0 = boss.hp
	boss.take_damage(20.0, _player)
	assert_eq(boss.hp, hp0, "bouclier levé : tir de face bloqué")


# --- Objets lancés et dangers ---------------------------------------------------------

func test_molotov_leaves_burning_fire() -> void:
	var e := await _engaged(&"fw_bandit", Vector2.ZERO, Vector2(220, 0), _dynamite_data())
	e.force_skill(&"molotov")
	await wait_physics_frames(3)
	assert_gt(float(e.visual.get("_marker_t")), -0.5, "cercle au sol avant le lancer")
	await wait_until(func() -> bool: return not get_tree().get_nodes_in_group(EnemyHazard.GROUP).is_empty(), 2.0)
	await wait_seconds(1.6)
	assert_gt(_player.hits.size(), 0, "le feu brûle")
	assert_true(_player.has_status_kind(&"burn"))


func test_bouncing_dynamite_lands_at_final_target() -> void:
	var e := await _engaged(&"fw_bandit", Vector2.ZERO, Vector2(300, 0), _dynamite_data())
	e.force_skill(&"bounce_dynamite")
	await wait_until(func() -> bool: return not get_tree().get_nodes_in_group(&"enemy_dynamite").is_empty(), 2.0)
	var dyn := get_tree().get_first_node_in_group(&"enemy_dynamite") as EnemyDynamite
	assert_not_null(dyn)
	if dyn != null:
		assert_ne(dyn.bounce_to, Vector2.INF, "rebond prévu")
		assert_lt(dyn.final_target().distance_to(_player.global_position), 90.0, "explose près du joueur")
		assert_lt(dyn.target.distance_to(Vector2.ZERO), dyn.final_target().distance_to(Vector2.ZERO), "premier impact plus court")


func test_flash_grenade_blinds_only_in_sight() -> void:
	var e := await _engaged(&"ss_security_droid", Vector2.ZERO, Vector2(250, 0))
	e.force_skill(&"flash_grenade")
	await wait_until(func() -> bool: return _player.has_status_kind(&"blind"), 2.5)
	assert_true(_player.has_status_kind(&"blind"), "aveuglé")
	# Derrière un mur : rien.
	_player.statuses.clear()
	var h := EnemyHazard.spawn(_world, &"flash", Vector2(0, 600), {"radius": 200.0, "blind_time": 1.5}, null, true)
	_player.global_position = Vector2(0, 760)
	_add_wall(Rect2(Vector2(-200, 680), Vector2(400, 20)))
	await wait_physics_frames(4)
	assert_false(_player.has_status_kind(&"blind"), "un mur protège de l'éclair")
	assert_true(is_instance_valid(h) or true)


func test_kamikaze_drone_explodes_on_player() -> void:
	var e := await _engaged(&"ss_spectre", Vector2.ZERO, Vector2(200, 0))
	var eid := e.get_instance_id()
	e.force_skill(&"kamikaze")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"beep")), "bip / clignotement")
	assert_eq(_player.hits.size(), 0)
	await wait_until(func() -> bool: return _player.hits.size() > 0, 3.0)
	assert_gt(_player.hits.size(), 0, "explosion au contact")
	var dead := not is_instance_id_valid(eid) or not (instance_from_id(eid) as Enemy).is_alive()
	assert_true(dead, "le drone est détruit")


func test_android_teleports_after_marker() -> void:
	var e := await _engaged(&"ss_teleporter", Vector2.ZERO, Vector2(380, 0))
	var s := e.get_skill(&"teleport")
	s.cooldown_left = 0.0
	assert_true(s.can_use(380.0, true), "destination trouvée")
	e.force_skill(&"teleport")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"blink")), "marqueur d'arrivée")
	assert_lt(e.global_position.length(), 5.0, "pas encore parti")
	await wait_seconds(0.7)
	assert_gt(e.global_position.length(), 100.0, "téléporté")


func test_soldier_deploys_turret_that_shoots() -> void:
	var e := await _engaged(&"ss_security_droid", Vector2.ZERO, Vector2(260, 0))
	e.force_skill(&"deploy_turret")
	await wait_until(func() -> bool: return not get_tree().get_nodes_in_group(EnemyHazard.GROUP).is_empty(), 2.0)
	var t := get_tree().get_first_node_in_group(EnemyHazard.GROUP) as EnemyHazard
	assert_not_null(t)
	if t != null:
		assert_eq(t.kind, &"turret")
		t.take_hit(1000.0)
		assert_true(t.is_destroyed(), "destructible")


func test_shockwave_knocks_down_when_ring_passes() -> void:
	var e := await _engaged(&"ss_station_guardian", Vector2.ZERO, Vector2(150, 0))
	e.force_skill(&"shockwave")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"ring")), "anneau de danger")
	assert_eq(_player.hits.size(), 0)
	await wait_until(func() -> bool: return _player.has_status_kind(&"knockdown"), 3.0)
	assert_true(_player.has_status_kind(&"knockdown"), "renversé par l'onde")


# --- Chef, tireur, réactions ---------------------------------------------------------------

func test_boss_whistle_calls_two_reinforcements() -> void:
	var boss := await _engaged(&"fw_deserter", Vector2.ZERO, Vector2(300, 0))
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	boss.force_skill(&"whistle")
	await wait_seconds(1.4)
	var after := get_tree().get_nodes_in_group(&"enemy_units").size()
	assert_eq(after - before, 2, "deux renforts")
	for n: Node in get_tree().get_nodes_in_group(&"enemy_units"):
		if n.has_meta(&"reinforcement"):
			assert_true((n as Enemy).is_in_combat(), "renfort déjà alerté")


func test_reinforcement_never_whistles() -> void:
	# Sinon les loups des glaces appelés sifflent à leur tour : meute sans fin.
	var wolf := await _engaged(&"ice_wolf", Vector2.ZERO, Vector2(300, 0))
	var s := wolf.get_skill(&"whistle")
	assert_true(s.can_use_extra(300.0, true), "le chef peut siffler")
	wolf.set_meta(&"reinforcement", true)
	assert_false(s.can_use_extra(300.0, true), "un renfort ne siffle pas")


func test_boss_rage_under_thirty_percent() -> void:
	var boss := await _engaged(&"fw_deserter", Vector2.ZERO, Vector2(300, 0))
	boss.data.stagger_ratio = 0.0
	var v := boss.run_speed()
	boss.take_damage(boss.max_hp * 0.75, null)
	assert_gt(boss.run_speed(), v * 1.2, "plus rapide")
	assert_lt(boss.rage_cooldown_mult, 1.0, "cadence accrue")


func test_sharpshooter_relocates_and_drops_trap_after_shot() -> void:
	# Le Tireur d'élite se replace sans piège : le piège à ours reste une option de `relocate`.
	var d := _custom(&"fw_sharpshooter", [{"id": &"relocate", "trap": true, "trap_cooldown": 9.0, "trap_damage": 12.0,
		"root_time": 1.5, "max_traps": 2, "min_move": 140.0, "priority": 3.0}, {"id": &"piercing", "passive": true}])
	var e := await _engaged(&"fw_sharpshooter", Vector2.ZERO, Vector2(420, 0), d)
	var s := e.get_skill(&"relocate")
	e.notify_attack_done()
	assert_true(bool(s.get("pending")))
	e.state_machine.transition_to(Enemy.STATE_CHASE)
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_SKILL, 1.5)
	await wait_physics_frames(3)
	var traps := get_tree().get_nodes_in_group(EnemyHazard.GROUP).filter(func(h: Node) -> bool: return (h as EnemyHazard).kind == &"trap")
	assert_eq(traps.size(), 1, "piège à ours posé sur place")
	await wait_seconds(1.2)
	assert_gt(e.global_position.length(), 60.0, "s'est replacé")


func test_bear_trap_roots_player() -> void:
	var h := EnemyHazard.spawn(_world, &"trap", Vector2(100, 100), {"arm_delay": 0.1, "damage": 12.0, "root_time": 1.5}, null, true)
	await wait_seconds(0.2)
	_player.global_position = Vector2(100, 100)
	await wait_seconds(0.3)
	assert_true(h.is_sprung(), "refermé")
	assert_true(_player.has_status_kind(&"root"), "pris au piège")


func test_piercing_shot_passes_through_crates() -> void:
	var crate := LootContainer.create(&"crate", Vector2(150, 0))
	_world.add_child(crate)
	var e := await _engaged(&"fw_sharpshooter", Vector2.ZERO, Vector2(300, 0))
	var fired: Array = []
	var cb := func(p: Node) -> void: fired.append(p)
	EventBus.projectile_fired.connect(cb)
	e.fire_volley(Vector2.RIGHT)
	EventBus.projectile_fired.disconnect(cb)
	assert_eq(fired.size(), 1)
	if not fired.is_empty():
		assert_true(bool((fired[0] as EnemyProjectile).pierce_props), "balle perforante")
	assert_true(EnemyProjectile.is_pierceable(crate.get_node(^"Body")), "les caisses se traversent")


func test_knife_bandit_rolls_when_aimed_at() -> void:
	var d := _knife_data()
	for entry: Variant in d.skills:
		if (entry as Dictionary)["id"] == &"dodge_roll":
			(entry as Dictionary)["chance"] = 1.0
	var e := await _engaged(&"fw_raider", Vector2.ZERO, Vector2(320, 0), d)
	e.get_skill(&"dodge_roll").cooldown_left = 0.0
	e.get_skill(&"knife_throw").cooldown_left = 99.0
	_player.aiming = true
	_player.aim_direction = Vector2.LEFT
	await wait_until(func() -> bool: return e.current_state_name() == Enemy.STATE_SKILL, 1.0)
	assert_eq(e.active_skill.id if e.active_skill != null else &"", &"dodge_roll", "roulade quand on le vise")
	await wait_seconds(0.5)
	assert_gt(absf(e.global_position.y), 60.0, "esquive latérale")


# --- Statuts du joueur -------------------------------------------------------------------

func test_player_statuses_block_move_fire_and_aim() -> void:
	var pl := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	_world.add_child(pl)
	await wait_physics_frames(2)
	pl.apply_status(&"stun", 0.5)
	assert_true(pl.has_status(&"stun"))
	assert_true(pl.status.blocks_move() and pl.status.blocks_fire(), "étourdi : ni déplacement ni tir")
	pl.apply_status(&"root", 0.5)
	pl.status.left.erase(&"stun")
	assert_true(pl.status.blocks_move() and not pl.status.blocks_fire(), "piégé : tire encore")
	pl.apply_status(&"blind", 1.0)
	var changed := false
	for i in 10:
		if pl.status.perturb_aim(Vector2.RIGHT) != Vector2.RIGHT:
			changed = true
	assert_true(changed, "aveuglé : visée perturbée")
	await wait_seconds(1.2)
	assert_false(pl.has_status(&"blind"), "le statut expire")
	# Coop, invité : seuls les statuts envoyés par l'hôte comptent.
	NetHooks.active = true
	NetHooks.guest_mode = true
	pl.apply_status(&"stun", 1.0)
	assert_false(pl.has_status(&"stun"), "statut local ignoré chez l'invité")
	NetHooks.applying_remote = true
	pl.apply_status(&"stun", 1.0)
	assert_true(pl.has_status(&"stun"), "statut de l'hôte appliqué")


# --- Coop : relais et marionnettes ------------------------------------------------------

func test_skill_fx_relayed_and_played_by_guest_puppet() -> void:
	for m: StringName in [&"play_skill_fx", &"spawn_hazard", &"spawn_reinforcement"]:
		assert_ne(NetProtocol.fx_index(m), -1, "%s relayé" % m)
	var coop := FakeCoop.new()
	NetHooks.active = true
	NetHooks.is_host = true
	NetHooks.coop = coop
	NetHooks.targets.assign([_player])
	var e := await _engaged(&"fw_bandit", Vector2.ZERO, Vector2(220, 0), _dynamite_data())
	e.force_skill(&"molotov")
	await wait_seconds(1.0)
	var methods := coop.log.map(func(x: Array) -> StringName: return x[0])
	assert_has(methods, &"show_ground_marker", "télégraphe relayé")
	assert_has(methods, &"spawn_hazard", "zone de feu relayée")
	# Invité : la marionnette rejoue les messages (sérialisés comme sur le réseau).
	NetHooks.reset()
	var puppet := _spawn(&"fw_bandit", Vector2(0, 500), _dynamite_data())
	await wait_physics_frames(2)
	puppet.net_puppet = true
	var hp0 := _player.hp
	_player.global_position = Vector2(0, 900)
	var hazards_before := get_tree().get_nodes_in_group(EnemyHazard.GROUP).size()
	for entry: Array in coop.log:
		var m: StringName = entry[0]
		if NetProtocol.fx_index(m) < 0:
			continue
		var args: Array = bytes_to_var(var_to_bytes(entry[1]))
		puppet._visual_call(m, args)
	await wait_physics_frames(2)
	assert_gt(float(puppet.visual.get("_marker_t")), -0.5, "la marionnette joue le télégraphe")
	var hz := get_tree().get_nodes_in_group(EnemyHazard.GROUP)
	assert_gt(hz.size(), hazards_before, "copie visuelle du danger")
	var copy_real := true
	for n: Node in hz:
		if not (n as EnemyHazard).real:
			copy_real = false
	assert_false(copy_real, "copie purement visuelle (aucun dégât chez l'invité)")
	assert_eq(_player.hp, hp0)
	coop.free()


func test_reinforcements_registered_for_coop() -> void:
	var coop := FakeCoop.new()
	NetHooks.active = true
	NetHooks.is_host = true
	NetHooks.coop = coop
	NetHooks.targets.assign([_player])
	var boss := await _engaged(&"fw_deserter", Vector2.ZERO, Vector2(300, 0))
	boss.force_skill(&"whistle")
	await wait_seconds(1.4)
	var regs := coop.log.filter(func(x: Array) -> bool: return x[0] == &"register")
	var spawns := coop.log.filter(func(x: Array) -> bool: return x[0] == &"spawn_reinforcement")
	assert_eq(regs.size(), 2, "identités réseau attribuées")
	assert_eq(spawns.size(), 2, "renforts relayés à l'invité")
	NetHooks.reset()
	coop.free()
