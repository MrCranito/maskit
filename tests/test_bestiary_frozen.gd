extends GutTest
## Bestiaire des Terres gelées (« Le désert de glace ») : données, planches 8 directions, roster
## (data/bestiary/frozen.tres, BestiaryData : le monde n'a pas encore de carte), compétences
## (registre du monde frozen) et leurs effets.

const BESTIARY_PATH := "res://data/bestiary/frozen.tres"
## 1re rangée de la planche (plus simples), puis 2e rangée (plus durs), de gauche à droite.
const ROW1 := [&"ice_wolf", &"ice_spider", &"ice_drone"]
const ROW2 := [&"ice_bear", &"ice_elemental", &"ice_hunter"]
const ANIMS := ["idle", "run", "attack", "hit", "death"]
const Reg := preload("res://scripts/enemies/skills/frozen/registry.gd")
const STORM := preload("res://scripts/enemies/skills/frozen/ice_storm.gd")


class FakePlayer extends CharacterBody2D:
	var hp: float = 1000.0
	var hits: Array = []
	var statuses: Array = []
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
	EnemyTactics.override_map = null


func after_each() -> void:
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null
	EnemyTactics.override_map = null
	for g: StringName in [EnemyProjectilePool.GROUP, &"enemy_dynamite", EnemyHazard.GROUP, STORM.GROUP, &"ground_loot"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			n.queue_free()


func _data(kind: StringName) -> EnemyData:
	var d := (load("res://data/enemies/%s.tres" % kind) as EnemyData).duplicate() as EnemyData
	d.sight_gain = 40.0
	d.detection_angle_deg = 360.0
	d.patrol_radius = 0.0
	return d


func _engaged(kind: StringName, enemy_pos: Vector2, player_pos: Vector2) -> Enemy:
	_player.global_position = player_pos
	var e := Enemy.spawn(_data(kind))
	e.position = enemy_pos
	_world.add_child(e)
	await wait_physics_frames(2)
	e.become_aware(player_pos, false)
	e.update_perception(0.1)
	return e


func _classics() -> Array:
	return ROW1 + ROW2


func _load(kind: StringName) -> EnemyData:
	return load("res://data/enemies/%s.tres" % kind) as EnemyData


# --- Données et planches --------------------------------------------------------------------

func test_classiques_charges_et_planches() -> void:
	for k: StringName in _classics():
		var d := _load(k)
		assert_not_null(d, "EnemyData %s" % k)
		if d == null:
			continue
		assert_eq(d.kind, k)
		assert_ne(d.display_name, "", "nom affiché %s" % k)
		assert_false(d.elite, "%s n'est pas une élite" % k)
		assert_false(d.boss, "%s n'est pas un boss" % k)
		assert_ne(d.corpse_name, "", "nom du cadavre %s" % k)
		assert_true(ResourceLoader.exists("res://data/loot_tables/%s.tres" % d.loot_table), "table de butin %s" % k)
		assert_true(EnemyArt.has_sheet(k), "planches %s" % k)
		var e := EnemyArt.entry(k)
		if e.is_empty():
			continue
		var sf: SpriteFrames = e["frames"]
		for an: String in ANIMS:
			for dn: String in EnemyArt.DIR_NAMES:
				assert_true(sf.has_animation("%s_%s" % [an, dn]), "%s : %s_%s" % [k, an, dn])
		assert_not_null(EnemyArt.corpse_texture(k, "s"), "cadavre %s" % k)
		var meta: Dictionary = e["meta"]
		assert_eq((meta.get("muzzle_px", {}) as Dictionary).size(), 8, "point d'impact / canon %s" % k)
		# Même échelle monde que le héros et les autres ennemis (0,577 unité par pixel).
		assert_almost_eq(float(e["scale"]), 92.3 / 160.0, 0.01, "échelle %s" % k)


func test_noms_de_la_planche() -> void:
	var names := {&"ice_wolf": "Loup des glaces", &"ice_spider": "Araignée polaire", &"ice_drone": "Drone de froid",
		&"ice_bear": "Ours des neiges muté", &"ice_elemental": "Élémentaire de glace",
		&"ice_hunter": "Chasseur arctique"}
	for k: StringName in names:
		assert_eq(_load(k).display_name, names[k])


func test_caracteristiques_de_la_planche() -> void:
	var wolf := _load(&"ice_wolf")
	var spider := _load(&"ice_spider")
	var drone := _load(&"ice_drone")
	var bear := _load(&"ice_bear")
	var elem := _load(&"ice_elemental")
	var hunter := _load(&"ice_hunter")
	# Loup : rapide, mêlée.
	assert_false(wolf.is_ranged())
	assert_gt(wolf.move_speed, 200.0, "loup rapide")
	# Araignée : camouflage, mêlée ; détecte surtout à l'ouïe (enfouie).
	assert_false(spider.is_ranged())
	assert_gt(spider.hearing_radius, spider.detection_radius * 2.0, "araignée : à l'affût sous la neige")
	# Drone : soutien, distance ; surveille la zone (vision 360°, alerte large).
	assert_true(drone.is_ranged(), "drone : distance")
	assert_eq(drone.detection_angle_deg, 360.0, "drone : surveille toute la zone")
	assert_gt(drone.alert_neighbors_radius, 500.0, "drone : prévient loin")
	# Ours : tank, mêlée.
	assert_false(bear.is_ranged())
	assert_gt(bear.max_hp, 250.0, "ours : tank")
	assert_lt(bear.move_speed, 110.0, "ours lent")
	# Élémentaire : zone, vitesse moyenne.
	assert_true(elem.is_area_attack(), "élémentaire : coup de zone")
	assert_between(elem.move_speed, 100.0, 160.0, "élémentaire : vitesse moyenne")
	# Chasseur : distance, rapide.
	assert_true(hunter.is_ranged(), "chasseur : fusil cryogénique")
	assert_gt(hunter.move_speed, 170.0, "chasseur rapide")
	# Difficulté croissante : 2e rangée plus coriace que la 1re.
	var hp1 := 0.0
	var hp2 := 0.0
	for k: StringName in ROW1:
		hp1 += _load(k).max_hp
	for k2: StringName in ROW2:
		hp2 += _load(k2).max_hp
	assert_gt(hp2, hp1 * 2.0, "2e rangée nettement plus dure")


func test_competences_connues_et_actives() -> void:
	for k: StringName in _classics():
		var d := _load(k)
		var active := 0
		for entry: Variant in d.skills:
			var sid := StringName(str((entry as Dictionary).get("id", "")))
			assert_true(EnemySkills.has_skill(sid), "%s : compétence %s connue" % [k, sid])
			var s := EnemySkills.create(sid)
			if s == null:
				continue
			s.setup(null, entry)
			if not s.is_passive():
				active += 1
		assert_gt(active, 0, "%s : au moins une compétence active" % k)
	for sid2: Variant in Reg.REGISTRY:
		assert_true(String(sid2).begins_with("ice_"), "id préfixé par le monde : %s" % sid2)
		assert_true(ResourceLoader.exists(String(Reg.REGISTRY[sid2])), "script %s" % sid2)


func test_comportements_communs_froid_et_renforts() -> void:
	# « Utilisent le froid et les tempêtes » : chaque classique gèle (coup gelé, tempête, nova, tir cryo).
	var cold := [&"ice_chill", &"ice_storm", &"ice_frost_nova", &"ice_cryo_shot"]
	var calls := 0
	for k: StringName in _classics():
		var found := false
		for entry: Variant in _load(k).skills:
			var sid := StringName(str((entry as Dictionary)["id"]))
			if sid in cold:
				found = true
			if sid == &"ice_lab_call":
				calls += 1
		assert_true(found, "%s utilise le froid" % k)
	assert_gt(calls, 1, "« appellent des renforts des laboratoires »")
	assert_gt(Balance.get_float("bestiary_frozen", "group_size", 0.0), 1.0, "patrouilles en groupe")


func test_bestiaire_du_monde() -> void:
	var b := load(BESTIARY_PATH) as BestiaryData
	assert_not_null(b, "BestiaryData frozen")
	if b == null:
		return
	assert_eq(b.world_id, &"frozen")
	var everywhere := {}
	for room: Variant in b.enemy_roster:
		for k: Variant in b.enemy_roster[room]:
			everywhere[StringName(k)] = true
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "roster %s : %s" % [room, k])
			assert_true(String(k).begins_with("ice_"), "roster du monde : %s" % k)
	for k2: StringName in _classics():
		assert_true(everywhere.has(k2), "%s dans le roster" % k2)
		assert_true((b.enemy_roster[&"combat"] as Dictionary).has(k2), "%s en salle de combat" % k2)
	for k3: StringName in ROW1:
		for room2: StringName in [&"loot", &"trap"]:
			var ok := (b.enemy_roster[room2] as Dictionary).has(k3) or (k3 == &"ice_spider" and room2 == &"rest")
			assert_true(ok, "1re rangée : %s en %s" % [k3, room2])
	for k4: StringName in ROW2:
		assert_false((b.enemy_roster[&"rest"] as Dictionary).has(k4), "2e rangée absente du repos : %s" % k4)
		assert_false((b.enemy_roster[&"spawn"] as Dictionary).has(k4), "2e rangée absente du départ : %s" % k4)


# --- Compétences ----------------------------------------------------------------------------

func test_loups_chassent_en_meute() -> void:
	var a := await _engaged(&"ice_wolf", Vector2.ZERO, Vector2(900, 0))
	var sk := a.get_skill(&"ice_pack_hunter")
	assert_not_null(sk)
	sk.call("refresh")
	assert_eq(int(sk.get("pack_size")), 0, "seul")
	var dmg0 := a.diff_damage_mult
	for i in 2:
		var w := Enemy.spawn(_data(&"ice_wolf"))
		w.position = Vector2(40 + 30 * i, 30)
		_world.add_child(w)
	await wait_physics_frames(2)
	sk.call("refresh")
	assert_eq(int(sk.get("pack_size")), 2, "deux congénères comptés")
	assert_gt(a.diff_damage_mult, dmg0, "plus dangereux en meute")


func test_morsure_gelee_ralentit() -> void:
	var e := await _engaged(&"ice_wolf", Vector2.ZERO, Vector2(40, 0))
	var sk := e.get_skill(&"ice_chill")
	assert_not_null(sk)
	e.notify_attack_done()
	assert_true(_player.has_status_kind(&"slow"), "joueur au contact ralenti")
	_player.statuses.clear()
	_player.global_position = Vector2(600, 0)
	e.notify_attack_done()
	assert_false(_player.has_status_kind(&"slow"), "hors de portée : rien")


func test_araignee_enfouie_puis_surgit() -> void:
	_player.global_position = Vector2(3000, 0)
	var e := Enemy.spawn(_load(&"ice_spider").duplicate() as EnemyData)
	_world.add_child(e)
	await wait_seconds(0.4)
	var bur := e.get_skill(&"ice_burrow")
	assert_not_null(bur)
	assert_true(bool(bur.get("buried")), "enfouie hors combat")
	assert_lt(e.visual.modulate.a, 0.3, "presque invisible sous la neige")
	# Le joueur approche : elle surgit et bondit (surprise).
	e.become_aware(Vector2(220, 0), false)
	_player.global_position = Vector2(220, 0)
	e.update_perception(0.1)
	await wait_seconds(0.3)
	assert_false(bool(bur.get("buried")), "sortie de la neige en combat")
	assert_almost_eq(e.visual.modulate.a, 1.0, 0.01)
	var amb := e.get_skill(&"ice_ambush")
	amb.cooldown_left = 0.0
	e.force_skill(&"ice_ambush")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.0)
	assert_gt(_player.hits.size(), 0, "bond sur le joueur")
	assert_gte(int(amb.get("surprise_uses")), 1, "attaque surprise")
	assert_gt(float(_player.hits[0][0]), _load(&"ice_spider").attack_damage, "dégâts de surprise")
	assert_true(_player.has_status_kind(&"root"), "pris dans la glace")


func test_drone_declenche_une_tempete_de_glace() -> void:
	var e := await _engaged(&"ice_drone", Vector2.ZERO, Vector2(300, 0))
	var sk := e.get_skill(&"ice_storm")
	sk.cooldown_left = 0.0
	e.force_skill(&"ice_storm")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"ring")), "télégraphe sous le joueur")
	await wait_until(func() -> bool: return get_tree().get_nodes_in_group(STORM.GROUP).size() > 0, 2.0)
	assert_eq(get_tree().get_nodes_in_group(STORM.GROUP).size(), 1, "une tempête")
	await wait_until(func() -> bool: return _player.has_status_kind(&"slow"), 2.0)
	assert_true(_player.has_status_kind(&"slow"), "la tempête ralentit")
	assert_gt(_player.hits.size(), 0, "petits dégâts de froid")
	assert_false(sk.can_use(300.0, true), "une seule tempête à la fois")


func test_drone_appelle_des_renforts_du_labo() -> void:
	var e := await _engaged(&"ice_drone", Vector2.ZERO, Vector2(300, 0))
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.get_skill(&"ice_lab_call").cooldown_left = 0.0
	e.force_skill(&"ice_lab_call")
	await wait_seconds(1.5)
	var after := get_tree().get_nodes_in_group(&"enemy_units")
	assert_gt(after.size(), before, "renforts arrivés")
	var ok := false
	for u: Node in after:
		if u != e and u is Enemy and String((u as Enemy).data.kind).begins_with("ice_"):
			ok = true
	assert_true(ok, "renforts du bestiaire des glaces")


func test_ours_charge_et_enrage() -> void:
	var e := await _engaged(&"ice_bear", Vector2.ZERO, Vector2(320, 0))
	assert_not_null(e.get_skill(&"charge"), "charge")
	assert_not_null(e.get_skill(&"rage"), "très agressif : rage")
	e.force_skill(&"charge")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 3.0)
	assert_gt(_player.hits.size(), 0, "charge sur le joueur")


func test_elementaire_nova_de_givre() -> void:
	var e := await _engaged(&"ice_elemental", Vector2.ZERO, Vector2(150, 0))
	e.force_skill(&"ice_frost_nova")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"ring")), "anneau de danger")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.5)
	assert_gt(_player.hits.size(), 0, "onde de froid")
	assert_true(_player.has_status_kind(&"slow"), "ralentit")


func test_elementaire_se_reforme_une_fois() -> void:
	var e := await _engaged(&"ice_elemental", Vector2.ZERO, Vector2(400, 0))
	e.take_damage(e.max_hp * 3.0, _player)
	assert_true(e.is_alive(), "le coup fatal le fige en bloc de glace")
	var sk := e.get_skill(&"ice_reform")
	assert_true(bool(sk.call("is_reforming")))
	var hp_block := e.hp
	e.take_damage(50.0, _player)
	assert_eq(e.hp, hp_block, "bloc invulnérable")
	await wait_until(func() -> bool: return not bool(sk.call("is_reforming")), 4.0)
	assert_gt(e.hp, e.max_hp * 0.3, "reformé")
	e.data.ground_drop_chance = 0.0
	e.take_damage(e.max_hp * 3.0, _player)
	assert_false(e.is_alive(), "une seule fois")


func test_chasseur_tir_cryogenique() -> void:
	var e := await _engaged(&"ice_hunter", Vector2.ZERO, Vector2(300, 0))
	e.get_skill(&"ice_cryo_shot").cooldown_left = 0.0
	e.force_skill(&"ice_cryo_shot")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"lane")), "couloir de visée (télégraphe)")
	assert_eq(_player.hits.size(), 0, "rien avant le tir")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.0)
	assert_gt(_player.hits.size(), 0, "touché par le trait cryogénique")
	assert_true(_player.has_status_kind(&"slow"), "gelé : ralenti")


func test_chasseur_esquive_et_appelle_son_equipe() -> void:
	var d := _load(&"ice_hunter")
	var ids := []
	for entry: Variant in d.skills:
		ids.append(StringName(str((entry as Dictionary)["id"])))
	assert_true(ids.has(&"dodge_roll"), "rapide : roulade")
	assert_true(ids.has(&"ice_lab_call"), "équipe de chasseurs")
	assert_true(d.use_cover, "tireur à couvert")


# --- Élites et boss -------------------------------------------------------------------------

const ELITES := [&"ice_glacier_guardian", &"ice_eternal_mechanic"]
const BOSS := &"ice_titan"


func test_elites_declares() -> void:
	var b := load(BESTIARY_PATH) as BestiaryData
	assert_eq(b.elite_kinds.size(), 2, "2 élites par monde")
	var bear_hp := _load(&"ice_bear").max_hp
	for k: StringName in ELITES:
		assert_true(b.elite_kinds.has(k), "élite du monde : %s" % k)
		var d := _load(k)
		assert_not_null(d)
		if d == null:
			continue
		assert_true(d.elite, "%s : elite = true" % k)
		assert_false(d.boss)
		assert_gt(d.phase2_hp_ratio, 0.0, "%s : phase 2 d'élite" % k)
		assert_gt(d.max_hp, bear_hp, "%s plus coriace que les classiques" % k)
		assert_true(EnemyArt.has_sheet(k), "planches %s" % k)
		assert_true(ResourceLoader.exists("res://data/loot_tables/%s.tres" % d.loot_table), "butin %s" % k)
		for entry: Variant in d.skills:
			assert_true(EnemySkills.has_skill(StringName(str((entry as Dictionary)["id"]))), "%s : %s" % [k, entry["id"]])
	assert_eq(_load(&"ice_glacier_guardian").display_name, "Gardien des glaces")
	assert_eq(_load(&"ice_eternal_mechanic").display_name, "Mécanicien de l'Éternité")
	assert_true(_load(&"ice_glacier_guardian").is_area_attack(), "gardien : tank / zone")
	assert_true(_load(&"ice_eternal_mechanic").is_ranged(), "mécanicien : soutien à distance")


func test_boss_declare_avec_trois_phases() -> void:
	var b := load(BESTIARY_PATH) as BestiaryData
	assert_eq(b.boss_kind, BOSS)
	var d := _load(BOSS)
	assert_not_null(d)
	if d == null:
		return
	assert_true(d.boss)
	assert_false(d.elite)
	assert_eq(d.display_name, "Le Titan de glace")
	assert_ne(d.boss_title, "")
	assert_true(EnemyArt.has_sheet(BOSS), "planches du boss")
	assert_eq(d.phases.size(), 3, "3 phases")
	var froms := [1.0, 0.7, 0.3]
	var wanted := [[&"ice_spikes", &"ice_frost_nova"], [&"ice_storm", &"ice_lab_call"], [&"ice_icefall", &"ice_storm"]]
	for i in 3:
		var ph: Dictionary = d.phases[i]
		assert_almost_eq(float(ph["from"]), froms[i], 0.001, "phase %d" % (i + 1))
		var ids := []
		for entry: Variant in ph.get("skills", []):
			var sid := StringName(str((entry as Dictionary)["id"]))
			assert_true(EnemySkills.has_skill(sid), "phase %d : %s connue" % [i + 1, sid])
			ids.append(sid)
		for sid2: StringName in wanted[i]:
			assert_true(ids.has(sid2), "phase %d : %s" % [i + 1, sid2])
		for sid3: Variant in ph.get("on_enter", []):
			assert_true(ids.has(StringName(str(sid3))), "phase %d : on_enter %s dans la phase" % [i + 1, sid3])
	assert_gt(float((d.phases[2] as Dictionary).get("damage_mult", 1.0)), 1.3, "phase 3 enragée")
	assert_lt(float((d.phases[2] as Dictionary).get("cooldown_mult", 1.0)), 0.7, "phase 3 : rythme effréné")
	# « Vraiment très difficile » : plusieurs fois les PV d’une élite.
	assert_gt(d.max_hp, 5.0 * _load(&"ice_glacier_guardian").max_hp)
	assert_eq(d.stagger_ratio, 0.0, "pas d'étourdissement")


func test_gardien_pics_de_glace_immobilisent() -> void:
	var e := await _engaged(&"ice_glacier_guardian", Vector2.ZERO, Vector2(300, 0))
	e.get_skill(&"ice_spikes").cooldown_left = 0.0
	e.force_skill(&"ice_spikes")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"lane")), "couloir de pics (télégraphe)")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 3.0)
	assert_gt(_player.hits.size(), 0, "les pics jaillissent sous le joueur")
	assert_true(_player.has_status_kind(&"root"), "pris dans la glace")


func test_gardien_armure_de_glace() -> void:
	var e := await _engaged(&"ice_glacier_guardian", Vector2.ZERO, Vector2(200, 0))
	e.face(Vector2.RIGHT)
	var hp0 := e.hp
	e.take_damage(20.0, _player)
	assert_lt(hp0 - e.hp, 20.0, "armure frontale")


func test_mecanicien_repare_et_renforce() -> void:
	var e := await _engaged(&"ice_eternal_mechanic", Vector2.ZERO, Vector2(600, 0))
	var ally := Enemy.spawn(_data(&"ice_drone"))
	ally.position = Vector2(80, 40)
	_world.add_child(ally)
	await wait_physics_frames(2)
	ally.hp = ally.max_hp * 0.3
	var dmg0 := ally.diff_damage_mult
	var sk := e.get_skill(&"ice_repair")
	sk.cooldown_left = 0.0
	assert_true(sk.can_use(600.0, true), "un allié est endommagé")
	e.force_skill(&"ice_repair")
	await wait_until(func() -> bool: return int(sk.get("last_healed")) > 0, 2.5)
	assert_gt(ally.hp, ally.max_hp * 0.5, "machine réparée")
	assert_gt(ally.diff_damage_mult, dmg0, "machine renforcée")
	assert_eq(int(sk.call("buffed_count")), 1)


func test_mecanicien_deploie_tourelle_et_drones() -> void:
	var d := _load(&"ice_eternal_mechanic")
	var ids := []
	for entry: Variant in d.skills:
		ids.append(StringName(str((entry as Dictionary)["id"])))
		if StringName(str((entry as Dictionary)["id"])) == &"ice_lab_call":
			assert_true((entry["kinds"] as Array).has("ice_drone"), "appelle des drones de la base")
	assert_true(ids.has(&"deploy_turret"), "machines : tourelle")
	assert_true(ids.has(&"ice_repair"), "soutien : réparation")


func test_boss_change_de_phase_tempete_puis_stalactites() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(260, 0))
	assert_not_null(e.get_skill(&"ice_spikes"), "phase 1 : pics de glace")
	assert_null(e.get_skill(&"ice_icefall"), "pas encore de stalactites")
	var units0 := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.take_damage(e.max_hp * 0.32, _player)
	await wait_physics_frames(2)
	assert_eq(e.boss_phase, 1, "phase 2")
	assert_not_null(e.get_skill(&"ice_storm"), "phase 2 : tempêtes de glace")
	assert_gt(e.invulnerable_left, 0.0, "transition invulnérable")
	await wait_until(func() -> bool: return get_tree().get_nodes_in_group(STORM.GROUP).size() > 0, 3.0)
	assert_gt(get_tree().get_nodes_in_group(STORM.GROUP).size(), 0, "tempête déclenchée en entrant")
	e.invulnerable_left = 0.0
	e.take_damage(e.max_hp * 0.42, _player)
	await wait_physics_frames(2)
	assert_eq(e.boss_phase, 2, "phase 3")
	assert_gt(e.phase_damage_mult, 1.3, "enragé")
	assert_not_null(e.get_skill(&"ice_icefall"), "phase 3 : pluie de stalactites")
	_player.hits.clear()
	_player.statuses.clear()
	await wait_until(func() -> bool: return _player.has_status_kind(&"slow") and _player.hits.size() > 0, 4.0)
	assert_gt(_player.hits.size(), 0, "les stalactites frappent")
	e.force_skill(&"ice_lab_call")
	await wait_seconds(1.6)
	assert_gt(get_tree().get_nodes_in_group(&"enemy_units").size(), units0, "renforts du noyau")


func test_stalactites_visent_le_joueur() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(300, 0))
	var sk := EnemySkills.create(&"ice_icefall")
	sk.setup(e, {"id": &"ice_icefall", "count": 6})
	var pts: PackedVector2Array = sk.call("impact_points")
	assert_eq(pts.size(), 6)
	assert_lt(pts[0].distance_to(Vector2(300, 0)), 60.0, "le premier impact sur le joueur")
