extends GutTest
## Bestiaire du Far West (refonte, planches docs/reference/bestiaire_*.png) : données, planches 3D
## (art/blender/bestiary/far_west), roster du monde, compétences propres (aboiement d'alarme,
## chasse en meute, hurlement, garde du corps) et suppression des anciens monstres.

const CLASSIC: Array[StringName] = [&"fw_bandit", &"fw_raider", &"fw_sharpshooter",
	&"fw_marauder", &"fw_bruiser", &"fw_guard_dog"]
const ROW1: Array[StringName] = [&"fw_bandit", &"fw_raider", &"fw_sharpshooter"]
const ROW2: Array[StringName] = [&"fw_marauder", &"fw_bruiser", &"fw_guard_dog"]
const OLD: Array[StringName] = [&"outlaw_knife", &"gunslinger", &"shotgun_brute", &"rifleman",
	&"dynamiter", &"gang_boss", &"sandstone_colossus"]
const WORLD := "res://data/worlds/world_01_far_west.tres"
const ANIMS: Array[String] = ["idle", "run", "attack", "hit", "death"]


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

	func apply_status(_kind: StringName, _duration: float, _strength: float = 1.0, _from: Vector2 = Vector2.INF) -> void:
		pass

	func is_alive() -> bool:
		return hp > 0.0


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
	for n: Node in get_tree().get_nodes_in_group(EnemyProjectilePool.GROUP):
		n.queue_free()


func _load(kind: StringName) -> EnemyData:
	return load("res://data/enemies/%s.tres" % kind) as EnemyData


func _data(kind: StringName) -> EnemyData:
	var d := _load(kind).duplicate() as EnemyData
	d.sight_gain = 40.0
	d.detection_angle_deg = 360.0
	d.patrol_radius = 0.0
	return d


func _spawn(kind: StringName, pos: Vector2) -> Enemy:
	var e := Enemy.spawn(_data(kind))
	e.position = pos
	_world.add_child(e)
	return e


func _engaged(kind: StringName, enemy_pos: Vector2, player_pos: Vector2) -> Enemy:
	_player.global_position = player_pos
	var e := _spawn(kind, enemy_pos)
	await wait_physics_frames(2)
	e.become_aware(player_pos, false)
	e.update_perception(0.1)
	return e


# --- Données ---------------------------------------------------------------------------

func test_classics_load_with_complete_data() -> void:
	for k: StringName in CLASSIC:
		var d := _load(k)
		assert_not_null(d, "%s.tres charge" % k)
		if d == null:
			continue
		assert_eq(d.kind, k, "kind cohérent")
		assert_gt(d.max_hp, 0.0)
		assert_gt(d.move_speed, 0.0)
		assert_gt(d.detection_radius, 0.0)
		assert_false(d.display_name.is_empty(), "%s : nom" % k)
		assert_false(d.corpse_name.is_empty(), "%s : nom du cadavre" % k)
		assert_ne(d.get_tactic(), &"", "%s : tactique" % k)
		assert_false(d.elite, "%s : classique, pas élite" % k)
		assert_false(d.boss, "%s : classique, pas boss" % k)
		assert_true(ResourceLoader.exists("res://data/loot_tables/enemy_%s.tres" % k), "%s : table du cadavre" % k)


func test_classics_follow_the_board() -> void:
	var bandit := _load(&"fw_bandit")
	var raider := _load(&"fw_raider")
	var sniper := _load(&"fw_sharpshooter")
	var marauder := _load(&"fw_marauder")
	var bruiser := _load(&"fw_bruiser")
	var dog := _load(&"fw_guard_dog")
	# Bandit : tir à distance, PV faible, vitesse moyenne, se met à couvert.
	assert_true(bandit.is_ranged())
	assert_true(bandit.use_cover)
	# Pillard : corps à corps, PV moyen, rapide, charge.
	assert_false(raider.is_ranged())
	assert_gt(raider.max_hp, bandit.max_hp)
	assert_gt(raider.move_speed, bandit.move_speed)
	assert_true(_has_skill(raider, &"rush"), "le pillard charge")
	# Tireur d'élite : longue portée, PV faible, lent.
	assert_true(sniper.is_ranged())
	assert_gt(sniper.attack_range, bandit.attack_range * 1.5)
	assert_lt(sniper.move_speed, bandit.move_speed)
	assert_lte(sniper.max_hp, bandit.max_hp)
	assert_eq(sniper.get_pattern(), &"aimed")
	# Maraudeur : très rapide, morsure, chasse en meute.
	assert_false(marauder.is_ranged())
	assert_gt(marauder.move_speed, raider.move_speed)
	assert_true(_has_skill(marauder, &"fw_pack_hunter"))
	# Robuste : PV élevés, lent, bouclier, protège ses alliés.
	for k: StringName in CLASSIC:
		if k != &"fw_bruiser":
			assert_gt(bruiser.max_hp, _load(k).max_hp, "le Robuste encaisse le plus")
	assert_lt(bruiser.move_speed, bandit.move_speed)
	assert_true(_has_skill(bruiser, &"hard_skin") and _has_skill(bruiser, &"fw_bodyguard"))
	# Chien de garde : PV faible, rapide, détection.
	assert_lt(dog.max_hp, bandit.max_hp)
	assert_gt(dog.move_speed, bandit.move_speed)
	for k: StringName in CLASSIC:
		if k != &"fw_guard_dog":
			assert_gt(dog.hearing_radius, _load(k).hearing_radius, "le chien entend le mieux")
	assert_true(_has_skill(dog, &"fw_alarm_bark"))
	# Comportements communs : encerclement (flanc), couverture, renforts.
	for k: StringName in [&"fw_bandit", &"fw_raider", &"fw_marauder", &"fw_guard_dog"]:
		assert_true(_load(k).can_flank, "%s : contourne le joueur" % k)
	assert_true(_has_skill(bandit, &"whistle"), "le bandit appelle des renforts")


func _has_skill(d: EnemyData, sid: StringName) -> bool:
	for entry: Variant in d.skills:
		if entry is Dictionary and StringName(str((entry as Dictionary).get("id", ""))) == sid:
			return true
	return false


func test_skills_are_known() -> void:
	for k: StringName in CLASSIC:
		for entry: Variant in _load(k).skills:
			var sid := StringName(str((entry as Dictionary).get("id", "")))
			assert_true(EnemySkills.has_skill(sid), "%s : compétence %s connue" % [k, sid])
	for sid: StringName in [&"fw_alarm_bark", &"fw_pack_hunter", &"fw_pack_howl", &"fw_bodyguard"]:
		assert_not_null(EnemySkills.create(sid), "%s instanciable" % sid)


# --- Planches 3D -------------------------------------------------------------------------

func test_classics_have_sheets() -> void:
	for k: StringName in CLASSIC:
		assert_true(EnemyArt.has_sheet(k), "%s : planches" % k)
		var e := EnemyArt.entry(k)
		if e.is_empty():
			continue
		var sf: SpriteFrames = e["frames"]
		for a: String in ANIMS:
			for d: String in EnemyArt.DIR_NAMES:
				assert_true(sf.has_animation(a + "_" + d), "%s : %s_%s" % [k, a, d])
		assert_not_null(EnemyArt.corpse_texture(k, "s"), "%s : cadavre" % k)
		var v := EnemyVisual.new()
		add_child_autofree(v)
		v.setup(k)
		assert_eq(v.kind, k, "%s : visuel sans repli" % k)
		assert_true(v.uses_sheet)


# --- Roster ------------------------------------------------------------------------------

func test_roster_uses_new_bestiary() -> void:
	var w := load(WORLD) as WorldData
	var seen := {}
	for rt: Variant in w.enemy_roster:
		var r: Dictionary = w.enemy_roster[rt]
		assert_true(r.has(&"fw_bandit"), "rangée 1 partout : bandit dans %s" % rt)
		for k: Variant in r:
			seen[StringName(k)] = true
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "roster %s : %s existe" % [rt, k])
			assert_false(OLD.has(StringName(k)), "roster %s : ancien kind %s" % [rt, k])
	for k: StringName in CLASSIC:
		assert_true(seen.has(k), "%s présent dans le roster" % k)
	for rt: StringName in [&"combat", &"extraction"]:
		for k: StringName in ROW2:
			assert_true(w.get_roster(rt).has(k), "rangée 2 en %s : %s" % [rt, k])
	# Rangée 2 : plus rare dans les salles calmes que dans les salles de combat.
	var calm: Dictionary = w.get_roster(&"loot")
	var fight: Dictionary = w.get_roster(&"combat")
	assert_lt(_share(calm, ROW2), _share(fight, ROW2))


func _share(r: Dictionary, kinds: Array[StringName]) -> float:
	var tot := 0.0
	var part := 0.0
	for k: Variant in r:
		tot += float(r[k])
		if kinds.has(StringName(k)):
			part += float(r[k])
	return part / maxf(tot, 0.001)


func test_old_far_west_monsters_removed() -> void:
	for k: StringName in OLD:
		assert_false(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "%s.tres supprimé" % k)
		assert_false(DirAccess.dir_exists_absolute("res://assets/sprites/enemies/%s" % k), "planches %s supprimées" % k)


# --- Compétences -------------------------------------------------------------------------

func test_guard_dog_bark_alerts_the_whole_area() -> void:
	var dog := await _engaged(&"fw_guard_dog", Vector2.ZERO, Vector2(200, 0))
	var far := _spawn(&"fw_bandit", Vector2(-600, 0))
	var out := _spawn(&"fw_bandit", Vector2(-2000, 0))
	await wait_physics_frames(2)
	assert_false(far.is_in_combat(), "bandit lointain calme avant l'aboiement")
	assert_true(dog.force_skill(&"fw_alarm_bark"))
	await wait_seconds(0.8)
	var sk := dog.get_skill(&"fw_alarm_bark")
	assert_gte(int(sk.get(&"last_alerted")), 1)
	assert_true(far.is_in_combat() or far.awareness >= 1.0, "bandit à 600 px alerté par l'aboiement")
	assert_false(out.is_in_combat(), "hors du rayon : pas alerté")


func test_marauder_pack_is_stronger() -> void:
	var a := await _engaged(&"fw_marauder", Vector2.ZERO, Vector2(400, 0))
	var sk := a.get_skill(&"fw_pack_hunter")
	sk.call(&"refresh")
	var alone := a.get_attack_damage()
	var speed_alone := a.run_speed()
	_spawn(&"fw_marauder", Vector2(60, 80))
	_spawn(&"fw_marauder", Vector2(-60, 80))
	await wait_physics_frames(2)
	sk.call(&"refresh")
	assert_eq(int(sk.get(&"pack_size")), 2)
	assert_gt(a.get_attack_damage(), alone * 1.2, "plus de dégâts en meute")
	assert_gt(a.run_speed(), speed_alone, "plus rapide en meute")


func test_lone_marauder_howls_for_the_pack() -> void:
	var a := await _engaged(&"fw_marauder", Vector2.ZERO, Vector2(400, 0))
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	assert_true(a.force_skill(&"fw_pack_howl"))
	await wait_seconds(1.2)
	var after := get_tree().get_nodes_in_group(&"enemy_units").size()
	assert_eq(after - before, 1, "un maraudeur rejoint la meute")


func test_bruiser_steps_between_player_and_ally() -> void:
	var ally := _spawn(&"fw_sharpshooter", Vector2(0, 0))
	var b := await _engaged(&"fw_bruiser", Vector2(-60, 100), Vector2(400, 0))
	ally.hp = ally.max_hp * 0.5
	var sk := b.get_skill(&"fw_bodyguard")
	assert_true(sk.can_use(b.global_position.distance_to(_player.global_position), true) or sk.cooldown_left > 0.0)
	sk.cooldown_left = 0.0
	assert_true(sk.call(&"can_use_extra", 400.0, true), "allié à protéger trouvé")
	assert_true(b.force_skill(&"fw_bodyguard"))
	await wait_until(func() -> bool: return bool(sk.get(&"guarding")), 3.0)
	var spot: Vector2 = sk.call(&"guard_spot", ally, _player.global_position)
	assert_lt(b.global_position.distance_to(spot), 40.0, "le Robuste s'est placé devant l'allié")
	assert_lt(b.global_position.distance_to(_player.global_position), ally.global_position.distance_to(_player.global_position))


func test_bruiser_shield_reduces_frontal_shots() -> void:
	var b := await _engaged(&"fw_bruiser", Vector2.ZERO, Vector2(300, 0))
	b.data.stagger_ratio = 0.0
	b.face(Vector2.RIGHT)
	var hp0 := b.hp
	b.take_damage(20.0, _player)
	var front := hp0 - b.hp
	b.face(Vector2.LEFT)
	var hp1 := b.hp
	b.take_damage(20.0, _player)
	var back := hp1 - b.hp
	assert_lt(front, back * 0.6, "les tirs de face sont amortis par le bouclier")
