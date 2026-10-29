extends GutTest
## Bestiaire de la Station spatiale (planches docs/reference/bestiaire_*.png, colonne STATION) :
## données (EnemyData), planches 3D 8 directions (EnemyArt), roster du monde (rangée 1 partout,
## rangée 2 surtout combat / extraction et ponts profonds), compétences propres
## (scripts/enemies/skills/space_station) et suppression des anciens monstres space_*.

const Populator := preload("res://scripts/biomes/space_station/ss_populator.gd")
const WORLD := "res://data/worlds/world_02_space_station.tres"
const ROW1: Array[StringName] = [&"ss_security_droid", &"ss_spectre", &"ss_teleporter"]
const ROW2: Array[StringName] = [&"ss_detector", &"ss_station_guardian", &"ss_alien"]
const SUMMONS: Array[StringName] = [&"ss_alien_brood"]
const ANIMS: Array[String] = ["idle", "run", "attack", "hit", "death"]
const ELITES: Array[StringName] = [&"ss_drone_tieur", &"ss_atlas"]
const BOSS := &"ss_architect"
const OLD_KINDS: Array[String] = ["space_android", "space_brute", "space_drone", "space_soldier", "space_reactor_colossus"]


class FakePlayer extends CharacterBody2D:
	var hp: float = 1000.0
	var hits: Array = []
	var statuses: Array = []

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

	func is_aiming() -> bool:
		return false

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
	for g: StringName in [EnemyProjectilePool.GROUP, &"enemy_dynamite", EnemyHazard.GROUP]:
		for n: Node in get_tree().get_nodes_in_group(g):
			n.queue_free()


func _data(kind: StringName) -> EnemyData:
	var d := (load("res://data/enemies/%s.tres" % kind) as EnemyData).duplicate() as EnemyData
	d.sight_gain = 40.0
	d.detection_angle_deg = 360.0
	d.patrol_radius = 0.0
	return d


func _spawn(kind: StringName, pos: Vector2, data: EnemyData = null) -> Enemy:
	var e := Enemy.spawn(data if data != null else _data(kind))
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


func _units() -> int:
	return get_tree().get_nodes_in_group(Enemy.GROUP_UNITS).size()


# --- Données et planches ------------------------------------------------------------------

func test_kinds_load_with_full_sheets() -> void:
	for k: StringName in ROW1 + ROW2 + SUMMONS + ELITES + [BOSS]:
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_not_null(d, "EnemyData %s" % k)
		if d == null:
			continue
		assert_eq(d.kind, k)
		assert_false(d.display_name.is_empty(), "%s : nom" % k)
		if not (ELITES.has(k) or k == BOSS):
			assert_false(d.elite or d.boss, "%s : monstre classique" % k)
		assert_true(EnemyArt.has_sheet(k), "%s : planches" % k)
		var e := EnemyArt.entry(k)
		if e.is_empty():
			continue
		var sf: SpriteFrames = e["frames"]
		for an: String in ANIMS:
			for dn: String in EnemyArt.DIR_NAMES:
				assert_true(sf.has_animation("%s_%s" % [an, dn]), "%s : %s_%s" % [k, an, dn])
		var meta: Dictionary = e["meta"]
		assert_eq((meta.get("muzzle_px", {}) as Dictionary).size(), 8, "%s : bout du canon 8 directions" % k)
		assert_not_null(EnemyArt.corpse_texture(k, "s"), "%s : carcasse" % k)
		assert_gt(EnemyArt.head_height(k), 20.0, "%s : hauteur lisible" % k)


func test_old_station_monsters_removed() -> void:
	for k: String in OLD_KINDS:
		assert_false(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "%s supprimé" % k)
		assert_false(FileAccess.file_exists("res://assets/sprites/space_station/enemies/%s.png" % k), "sprite %s supprimé" % k)


func test_difficulty_rises_from_row1_to_row2() -> void:
	var hp1 := 0.0
	var max1 := 0.0
	for k: StringName in ROW1:
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		hp1 += d.max_hp
		max1 = maxf(max1, d.max_hp)
	var hp2 := 0.0
	for k2: StringName in ROW2:
		hp2 += (load("res://data/enemies/%s.tres" % k2) as EnemyData).max_hp
	assert_gt(hp2, hp1 * 1.5, "rangée 2 bien plus résistante")
	for k3: StringName in [&"ss_station_guardian", &"ss_alien"]:
		assert_gt((load("res://data/enemies/%s.tres" % k3) as EnemyData).max_hp, max1 * 2.0, "%s : PV élevés" % k3)
	var guardian := load("res://data/enemies/ss_station_guardian.tres") as EnemyData
	var spectre := load("res://data/enemies/ss_spectre.tres") as EnemyData
	assert_lt(guardian.move_speed, spectre.move_speed * 0.5, "gardien lent, spectre rapide")


func test_skills_are_registered() -> void:
	var reg := load("res://scripts/enemies/skills/space_station/registry.gd") as Script
	var ids: Dictionary = reg.get_script_constant_map()["REGISTRY"]
	assert_eq(ids.size(), 8)
	for k: StringName in ROW1 + ROW2 + SUMMONS + ELITES + [BOSS]:
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_false(d.skills.is_empty(), "%s : compétences" % k)
		for entry: Variant in d.skills:
			var sid := StringName(str((entry as Dictionary).get("id", "")))
			assert_true(EnemySkills.has_skill(sid), "%s : %s connue" % [k, sid])


# --- Roster -------------------------------------------------------------------------------

func test_roster_row1_everywhere_row2_in_combat_rooms() -> void:
	var w := load(WORLD) as WorldData
	for rt: Variant in w.enemy_roster:
		var r: Dictionary = w.enemy_roster[rt]
		for k: StringName in ROW1:
			assert_true(r.has(k), "rangée 1 partout : %s dans %s" % [k, rt])
		for k0: Variant in r:
			assert_true(String(k0).begins_with("ss_"), "%s : nouveau bestiaire (%s)" % [rt, k0])
			assert_false(SUMMONS.has(StringName(str(k0))), "les larves ne sont qu'invoquées")
	for k2: StringName in ROW2:
		assert_true(w.get_roster(&"combat").has(k2), "%s en salle de combat" % k2)
		assert_true(w.get_roster(&"extraction").has(k2), "%s en extraction" % k2)
	var row2_combat := 0.0
	var row2_corridor := 0.0
	for k3: StringName in ROW2:
		row2_combat += float(w.get_roster(&"combat").get(k3, 0.0))
		row2_corridor += float(w.get_roster(&"corridor").get(k3, 0.0))
	assert_gt(row2_combat, row2_corridor, "rangée 2 surtout en combat")


func test_row2_more_frequent_on_deep_decks() -> void:
	var w := load(WORLD) as WorldData
	var r: Dictionary = w.get_roster(&"combat")
	var main := Populator.roster_weights(r, 0)
	var deep := Populator.roster_weights(r, -1)
	assert_gt(float(deep[&"ss_alien"]), float(main[&"ss_alien"]), "alien plus fréquent au pont des machines")
	assert_eq(float(deep[&"ss_security_droid"]), float(main[&"ss_security_droid"]), "rangée 1 inchangée")


# --- Compétences ----------------------------------------------------------------------------

func test_teleporter_blinks_behind_player_and_strikes() -> void:
	var e := await _engaged(&"ss_teleporter", Vector2.ZERO, Vector2(300, 0))
	var s := e.get_skill(&"ss_blink_strike")
	assert_not_null(s)
	s.cooldown_left = 0.0
	assert_true(s.can_use(300.0, true), "point d'arrivée trouvé")
	e.force_skill(&"ss_blink_strike")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"blink")), "marqueur d'arrivée")
	assert_lt(e.global_position.length(), 5.0, "pas encore parti")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.0)
	assert_gt(e.global_position.x, 300.0, "réapparu dans le dos du joueur")
	assert_gt(_player.hits.size(), 0, "frappe aussitôt")


func test_detector_alarm_alerts_station_and_calls_droid() -> void:
	var det := await _engaged(&"ss_detector", Vector2.ZERO, Vector2(250, 0))
	var far1 := _spawn(&"ss_security_droid", Vector2(-600, 300))
	var far2 := _spawn(&"ss_spectre", Vector2(-500, -400))
	await wait_physics_frames(2)
	assert_false(far1.is_in_combat(), "loin et aveugle : calme")
	var before := _units()
	det.force_skill(&"ss_alarm_scan")
	await wait_physics_frames(3)
	assert_true(bool(det.visual.call("has_skill_fx", &"ring")), "balayage visible avant l'alerte")
	await wait_seconds(1.1)
	var s := det.get_skill(&"ss_alarm_scan")
	assert_gte(int(s.get("alerted")), 2, "voisins alertés")
	assert_true(far1.is_in_combat() and far2.is_in_combat(), "toute la zone sait où est le joueur")
	assert_eq(_units() - before, 1, "un droïde de renfort")


func test_guardian_zone_barrage_drops_blasts() -> void:
	var g := await _engaged(&"ss_station_guardian", Vector2.ZERO, Vector2(320, 0))
	g.force_skill(&"ss_zone_barrage")
	await wait_physics_frames(3)
	assert_true(bool(g.visual.call("has_skill_fx", &"ring")), "cercles de danger avant les obus")
	assert_eq(_player.hits.size(), 0)
	await wait_until(func() -> bool: return _player.hits.size() > 0, 3.0)
	assert_gt(_player.hits.size(), 0, "l'obus visé sur le joueur touche")


func test_guardian_launches_drones() -> void:
	var g := await _engaged(&"ss_station_guardian", Vector2.ZERO, Vector2(320, 0))
	var before := _units()
	g.force_skill(&"ss_drone_launch")
	await wait_seconds(1.2)
	assert_eq(_units() - before, 2, "deux spectres lancés")
	var s := g.get_skill(&"ss_drone_launch")
	assert_false(s.can_use(320.0, true), "plafond d'invocations atteint")


func test_alien_summons_brood_and_frenzies_when_close() -> void:
	var a := await _engaged(&"ss_alien", Vector2.ZERO, Vector2(400, 0))
	var before := _units()
	a.force_skill(&"ss_brood_summon")
	await wait_seconds(1.3)
	assert_eq(_units() - before, 2, "deux larves")
	var frenzy := a.get_skill(&"ss_frenzy")
	assert_false(bool(frenzy.get("active")), "calme de loin")
	_player.global_position = Vector2(100, 0)
	await wait_seconds(0.5)
	assert_true(bool(frenzy.get("active")), "furieux de près")
	assert_gt(a.rage_speed_mult, 1.0, "plus rapide")


# --- Élites et boss -----------------------------------------------------------------------

func test_world_declares_two_elites_and_the_architect() -> void:
	var w := load(WORLD) as WorldData
	assert_eq(w.elite_kinds, ELITES, "2 élites de la planche")
	assert_eq(w.boss_kind, BOSS)
	for k: StringName in ELITES:
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_true(d.elite and not d.boss, "%s : élite" % k)
		assert_gt(d.max_hp, (load("res://data/enemies/ss_station_guardian.tres") as EnemyData).max_hp * 0.7, "%s : coriace" % k)
		for rt: Variant in w.enemy_roster:
			assert_false((w.enemy_roster[rt] as Dictionary).has(k), "élites placées par les règles, pas le roster")
	var b := load("res://data/enemies/%s.tres" % BOSS) as EnemyData
	assert_true(b.boss and not b.elite)
	assert_eq(b.boss_title, "IA de défense de la station")
	assert_gte(b.max_hp, 2500.0, "vraiment très difficile")
	assert_eq(b.phases.size(), 3)
	var froms := [1.0, 0.7, 0.3]
	var need := [[&"ss_orbital_laser"], [&"ss_drone_launch", &"energy_shield"], [&"ss_overload"]]
	for i: int in 3:
		var ph: Dictionary = b.phases[i]
		assert_almost_eq(float(ph["from"]), froms[i], 0.001, "phase %d" % (i + 1))
		var ids := []
		for entry: Variant in ph["skills"]:
			var sid := StringName(str((entry as Dictionary)["id"]))
			assert_true(EnemySkills.has_skill(sid), "phase %d : %s connue" % [i + 1, sid])
			ids.append(sid)
		for sid2: StringName in need[i]:
			assert_true(ids.has(sid2), "phase %d : %s" % [i + 1, sid2])
		for sid3: Variant in ph.get("on_enter", []):
			assert_true(ids.has(StringName(str(sid3))), "phase %d : on_enter %s dans la phase" % [i + 1, sid3])


func test_architect_orbital_laser_burns_the_lane() -> void:
	var b := await _engaged(BOSS, Vector2.ZERO, Vector2(500, 0))
	b.force_skill(&"ss_orbital_laser")
	await wait_physics_frames(3)
	assert_true(bool(b.visual.call("has_skill_fx", &"lane")), "couloir de visée avant le tir")
	assert_eq(_player.hits.size(), 0, "rien pendant le télégraphe")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 3.0)
	assert_gt(int(b.get_skill(&"ss_orbital_laser").get("ticks_hit")), 0, "le rayon brûle à 500 px")


func test_architect_overload_explodes_and_knocks_down() -> void:
	var b := await _engaged(BOSS, Vector2.ZERO, Vector2(180, 0))
	b.skills = EnemySkills.build_entries(b, (b.data.phases[2] as Dictionary)["skills"], b.data.kind)
	b.force_skill(&"ss_overload")
	await wait_physics_frames(3)
	assert_true(bool(b.visual.call("has_skill_fx", &"ring")), "anneau de surcharge")
	assert_eq(_player.hits.size(), 0)
	await wait_until(func() -> bool: return _player.statuses.size() > 0, 4.0)
	assert_gt(_player.hits.size(), 0, "explosion d'énergie")


func test_atlas_shield_blocks_frontal_fire() -> void:
	var a := await _engaged(&"ss_atlas", Vector2.ZERO, Vector2(300, 0))
	var sh := a.get_skill(&"energy_shield")
	a.force_skill(&"energy_shield")
	await wait_until(func() -> bool: return bool(sh.call("is_shield_up")), 2.0)
	a.face(Vector2.RIGHT)
	var hp0 := a.hp
	a.take_damage(40.0, _player)
	assert_lt(hp0 - a.hp, 10.0, "bouclier frontal")
