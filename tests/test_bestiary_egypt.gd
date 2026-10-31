extends GutTest
## Bestiaire des Pyramides d'Égypte (« Le royaume des morts ») : données, planches 8 directions,
## BestiaryData (pas encore de carte), compétences (registre du monde egypt) et leurs effets.

const BESTIARY_PATH := "res://data/bestiary/egypt.tres"
## 1re rangée de la planche (plus simples), puis 2e rangée (plus durs), de gauche à droite.
const ROW1 := [&"eg_skeleton", &"eg_scarab", &"eg_lizard"]
const ROW2 := [&"eg_archer", &"eg_mummy", &"eg_viper"]
const ELITES := [&"eg_shadow_warrior", &"eg_sun_priest"]
const BOSS := &"eg_pharaoh"
const ANIMS := ["idle", "run", "attack", "hit", "death"]
const Reg := preload("res://scripts/enemies/skills/egypt/registry.gd")


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
	for g: StringName in [EnemyProjectilePool.GROUP, &"enemy_dynamite", EnemyHazard.GROUP, &"eg_glyphs", &"eg_fx",
			&"eg_sandstorms"]:
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


func _all() -> Array:
	return ROW1 + ROW2 + ELITES + [BOSS]


func _hp(kind: StringName) -> float:
	return (load("res://data/enemies/%s.tres" % kind) as EnemyData).max_hp


# --- Données et planches --------------------------------------------------------------------

func test_donnees_et_planches() -> void:
	for k: StringName in _all():
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_not_null(d, "EnemyData %s" % k)
		if d == null:
			continue
		assert_eq(d.kind, k)
		assert_ne(d.display_name, "", "nom affiché %s" % k)
		assert_eq(d.elite, k in ELITES, "%s : élite" % k)
		assert_eq(d.boss, k == BOSS, "%s : boss" % k)
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
		assert_eq((meta.get("muzzle_px", {}) as Dictionary).size(), 8, "point d'impact %s" % k)
		# Même échelle monde que le héros et les autres ennemis (0,577 unité par pixel de rendu) ; le
		# boss est stocké à 72 % de sa résolution de rendu (échelle compensée dans la méta).
		var stored := float((meta.get("frame_size", [1, 1]) as Array)[0]) * float(meta.get("world_per_px", 0.0))
		assert_almost_eq(stored / float(meta.get("display_height", 1.0)), 1.0, 0.02, "échelle %s" % k)
		assert_almost_eq(float(e["scale"]), float(meta.get("world_per_px", 0.0)), 0.01, "échelle appliquée %s" % k)
		if k != BOSS:
			assert_almost_eq(float(e["scale"]), 92.3 / 160.0, 0.01, "échelle du héros %s" % k)


func test_noms_de_la_planche() -> void:
	var names := {&"eg_skeleton": "Squelette rôdeur", &"eg_scarab": "Scarabée géant", &"eg_lizard": "Lézard des sables",
		&"eg_archer": "Archer sable", &"eg_mummy": "Momie étouffée", &"eg_viper": "Vipère des sables",
		&"eg_shadow_warrior": "Guerrier de l'ombre", &"eg_sun_priest": "Prêtre du soleil", &"eg_pharaoh": "Le Pharaon éternel"}
	for k: StringName in names:
		assert_eq((load("res://data/enemies/%s.tres" % k) as EnemyData).display_name, names[k])


func test_caracteristiques_de_la_planche() -> void:
	var sk := load("res://data/enemies/eg_skeleton.tres") as EnemyData
	var sc := load("res://data/enemies/eg_scarab.tres") as EnemyData
	var li := load("res://data/enemies/eg_lizard.tres") as EnemyData
	var ar := load("res://data/enemies/eg_archer.tres") as EnemyData
	var mu := load("res://data/enemies/eg_mummy.tres") as EnemyData
	var vi := load("res://data/enemies/eg_viper.tres") as EnemyData
	assert_false(sk.is_ranged(), "squelette : mêlée")
	assert_between(sk.move_speed, 110.0, 150.0, "squelette : vitesse moyenne")
	assert_gt(sk.patrol_radius, 140.0, "squelette : rôde à la recherche des intrus")
	assert_false(sc.is_ranged(), "scarabée : mêlée")
	assert_gt(li.move_speed, 180.0, "lézard rapide")
	assert_gt(li.zigzag_amplitude, 20.0, "lézard agile")
	assert_true(ar.is_ranged(), "archer : distance")
	assert_true(ar.telegraph_line, "archer : précis (ligne de visée)")
	assert_gt(ar.attack_range, 450.0, "archer : vise de loin")
	assert_true(ar.use_cover, "archer : tire depuis les hauteurs / couverts")
	assert_gt(mu.max_hp, 2.0 * sc.max_hp, "momie : tank")
	assert_lt(mu.move_speed, 100.0, "momie : lente")
	assert_gt(vi.move_speed, 180.0, "vipère rapide")
	assert_gt(vi.hearing_radius, vi.detection_radius * 1.8, "vipère : embuscade (ouïe)")
	var hp1 := 0.0
	var hp2 := 0.0
	for k: StringName in ROW1:
		hp1 += _hp(k)
	for k2: StringName in ROW2:
		hp2 += _hp(k2)
	assert_gt(hp2, hp1, "2e rangée plus dure")


func _ids(d: EnemyData) -> Array:
	var out := []
	for entry: Variant in d.skills:
		out.append(StringName(str((entry as Dictionary).get("id", ""))))
	return out


func test_competences_connues_et_de_la_planche() -> void:
	for k: StringName in _all():
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
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
		assert_true(String(sid2).begins_with("eg_"), "id préfixé par le monde : %s" % sid2)
		assert_true(ResourceLoader.exists(String(Reg.REGISTRY[sid2])), "script %s" % sid2)
	var want := {&"eg_skeleton": [&"eg_spike_trap"], &"eg_scarab": [&"charge"], &"eg_lizard": [&"eg_burrow"],
		&"eg_archer": [&"eg_arrow_rain", &"eg_temple_call"], &"eg_mummy": [&"eg_undying", &"eg_bandage_lash"],
		&"eg_viper": [&"eg_venom", &"eg_burrow"], &"eg_shadow_warrior": [&"eg_shadow_veil"],
		&"eg_sun_priest": [&"eg_solar_blessing", &"eg_sun_flare"]}
	for k3: StringName in want:
		var ids := _ids(load("res://data/enemies/%s.tres" % k3) as EnemyData)
		for sid3: StringName in want[k3]:
			assert_true(ids.has(sid3), "%s : %s" % [k3, sid3])


func test_renforts_et_invocations_existent() -> void:
	for k: StringName in _all():
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		var entries: Array = d.skills.duplicate()
		for ph: Variant in d.phases:
			entries.append_array((ph as Dictionary).get("skills", []))
		for entry: Variant in entries:
			for rk: Variant in (entry as Dictionary).get("kinds", []):
				var path := "res://data/enemies/%s.tres" % rk
				assert_true(ResourceLoader.exists(path), "%s : renfort %s" % [k, rk])
				if ResourceLoader.exists(path):
					assert_false((load(path) as EnemyData).boss, "%s : pas de boss en renfort" % k)


func test_bestiaire_roster_elites_boss() -> void:
	var b := load(BESTIARY_PATH) as BestiaryData
	assert_not_null(b, "BestiaryData egypt")
	if b == null:
		return
	assert_eq(b.world_id, &"egypt")
	var everywhere := {}
	for room: Variant in b.enemy_roster:
		for k: Variant in b.enemy_roster[room]:
			everywhere[StringName(k)] = true
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "roster %s : %s" % [room, k])
			assert_false(StringName(k) in ELITES or StringName(k) == BOSS, "ni élite ni boss dans le roster : %s" % k)
	for k2: StringName in ROW1:
		assert_true((b.enemy_roster[&"combat"] as Dictionary).has(k2), "1re rangée en combat : %s" % k2)
		assert_true((b.enemy_roster[&"loot"] as Dictionary).has(k2), "1re rangée en fouille : %s" % k2)
	for k3: StringName in ROW2:
		assert_true((b.enemy_roster[&"combat"] as Dictionary).has(k3), "2e rangée en combat : %s" % k3)
		assert_true((b.enemy_roster[&"extraction"] as Dictionary).has(k3), "2e rangée en extraction : %s" % k3)
	assert_eq(b.elite_kinds.size(), 2, "2 élites")
	for el: StringName in ELITES:
		assert_true(b.elite_kinds.has(el), "élite %s" % el)
		assert_gt(_hp(el), 3.0 * _hp(&"eg_mummy") * 0.5, "élite coriace : %s" % el)
	assert_eq(b.boss_kind, BOSS)


func test_boss_trois_phases_tres_difficile() -> void:
	var d := load("res://data/enemies/%s.tres" % BOSS) as EnemyData
	assert_true(d.boss)
	assert_ne(d.boss_title, "")
	assert_eq(d.phases.size(), 3, "3 phases")
	var froms := [1.0, 0.7, 0.3]
	var wanted := [[&"eg_curse"], [&"eg_raise_dead", &"eg_sandstorm"], [&"eg_sun_rays", &"eg_raise_dead"]]
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
		for oe: Variant in ph.get("on_enter", []):
			assert_true(ids.has(StringName(str(oe))), "phase %d : compétence d'entrée %s active" % [i + 1, oe])
	assert_gt(float((d.phases[2] as Dictionary).get("damage_mult", 1.0)), 1.3, "phase 3 enragée")
	assert_lt(float((d.phases[2] as Dictionary).get("cooldown_mult", 1.0)), 0.7, "phase 3 enragée")
	# Escalier de difficulté (31/10) : PV 3300 → 1500, la difficulté vient de la carte (Expert) et des
	# phases ; il reste plus coriace que son escorte d'élite.
	assert_gt(d.max_hp, 2.5 * _hp(&"eg_shadow_warrior"), "vraiment très difficile")
	assert_eq(d.stagger_ratio, 0.0, "jamais étourdi")


# --- Comportements ---------------------------------------------------------------------------

func test_squelette_actionne_un_piege_ancien() -> void:
	var e := await _engaged(&"eg_skeleton", Vector2.ZERO, Vector2(220, 0))
	e.force_skill(&"eg_spike_trap")
	await wait_physics_frames(3)
	assert_eq(get_tree().get_nodes_in_group(&"eg_glyphs").size(), 1, "dalle piégée (télégraphe)")
	assert_eq(_player.hits.size(), 0, "aucun dégât pendant le télégraphe")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.5)
	assert_gt(_player.hits.size(), 0, "les pointes jaillissent")
	assert_true(_player.has_status_kind(&"root"), "entravé")


func test_scarabee_charge() -> void:
	var e := await _engaged(&"eg_scarab", Vector2.ZERO, Vector2(260, 0))
	e.force_skill(&"charge")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 3.0)
	assert_gt(_player.hits.size(), 0, "charge puissante")
	assert_true(_player.has_status_kind(&"knockdown"), "renverse")


func test_lezard_embuscade_sous_le_sable() -> void:
	var e := await _engaged(&"eg_lizard", Vector2.ZERO, Vector2(300, 0))
	var sk := e.get_skill(&"eg_burrow")
	e.force_skill(&"eg_burrow")
	await wait_until(func() -> bool: return bool(sk.call("is_burrowed")), 1.5)
	assert_true(bool(sk.call("is_burrowed")), "s'enfouit")
	assert_lt(e.visual.modulate.a, 0.3, "quasi invisible sous le sable")
	var hp0 := e.hp
	e.take_damage(10.0, _player)
	assert_eq(e.hp, hp0, "intouchable sous le sable")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 3.5)
	assert_gt(_player.hits.size(), 0, "jaillit sous le joueur")
	assert_gt(e.global_position.x, 150.0, "s'est déplacé vers le joueur")
	await wait_physics_frames(20)
	assert_almost_eq(e.visual.modulate.a, 1.0, 0.01, "visible après l'attaque")


func test_archer_pluie_de_fleches_et_renforts() -> void:
	var e := await _engaged(&"eg_archer", Vector2.ZERO, Vector2(400, 0))
	e.force_skill(&"eg_arrow_rain")
	await wait_physics_frames(3)
	assert_eq(get_tree().get_nodes_in_group(&"eg_glyphs").size(), 3, "3 zones de chute")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 3.0)
	assert_gt(_player.hits.size(), 0, "flèches")
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.get_skill(&"eg_temple_call").cooldown_left = 0.0
	await wait_seconds(0.3)
	e.force_skill(&"eg_temple_call")
	await wait_seconds(1.5)
	assert_gt(get_tree().get_nodes_in_group(&"enemy_units").size(), before, "renforts des temples")


func test_momie_se_releve_une_fois() -> void:
	var e := await _engaged(&"eg_mummy", Vector2.ZERO, Vector2(300, 0))
	var sk := e.get_skill(&"eg_undying")
	e.take_damage(e.max_hp * 3.0, _player)
	assert_true(e.is_alive(), "le coup mortel ne la tue pas")
	await wait_physics_frames(3)
	assert_eq(e.active_skill, sk, "effondrée")
	var hp_down := e.hp
	e.take_damage(50.0, _player)
	assert_eq(e.hp, hp_down, "intouchable au sol")
	await wait_until(func() -> bool: return bool(sk.get("revived")), 4.0)
	assert_true(bool(sk.get("revived")), "se relève")
	assert_almost_eq(e.hp, e.max_hp * 0.5, 1.0, "avec la moitié de ses PV")
	assert_gt(e.rage_speed_mult, 1.0, "plus hargneuse")
	e.invulnerable_left = 0.0
	e.take_damage(e.max_hp * 3.0, _player)
	assert_false(e.is_alive(), "la 2e mort est définitive")


func test_momie_bandelette_attire_le_joueur() -> void:
	var e := await _engaged(&"eg_mummy", Vector2.ZERO, Vector2(220, 0))
	var sk := e.get_skill(&"eg_bandage_lash")
	e.force_skill(&"eg_bandage_lash")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"lane")), "couloir (télégraphe)")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.0)
	assert_eq(sk.get("caught"), _player, "happé")
	assert_true(_player.has_status_kind(&"knockdown"), "tiré vers la momie")
	assert_true(_player.has_status_kind(&"root"), "entravé")


func test_vipere_venin() -> void:
	var e := await _engaged(&"eg_viper", Vector2.ZERO, Vector2(40, 0))
	e.get_skill(&"eg_venom").on_attack_done()
	assert_true(EgVenomDot.is_poisoned(_player), "empoisonné par la morsure")
	var n := _player.hits.size()
	await wait_seconds(1.2)
	assert_gt(_player.hits.size(), n, "le venin ronge")
	assert_true(_player.has_status_kind(&"slow"), "ralenti")


func test_vipere_crachat_flaque() -> void:
	var e := await _engaged(&"eg_viper", Vector2.ZERO, Vector2(250, 0))
	e.force_skill(&"eg_venom_spit")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.0)
	var n := _player.hits.size()
	await wait_seconds(0.8)
	assert_gt(_player.hits.size(), n, "la flaque de venin reste")


func test_guerrier_voile_d_ombre() -> void:
	var e := await _engaged(&"eg_shadow_warrior", Vector2.ZERO, Vector2(300, 0))
	var sk := e.get_skill(&"eg_shadow_veil")
	e.force_skill(&"eg_shadow_veil")
	await wait_seconds(0.6)
	assert_true(bool(sk.call("is_veiled")), "camouflage")
	assert_lt(e.visual.modulate.a, 0.2)
	assert_gt(e.rage_speed_mult, 1.0, "traque plus vite")
	assert_gt(e.phase_damage_mult, 1.0, "frappe d'embuscade")
	e.take_damage(5.0, _player)
	assert_false(bool(sk.call("is_veiled")), "révélé quand il est touché")
	assert_almost_eq(e.rage_speed_mult, 1.0, 0.001)
	assert_almost_eq(e.phase_damage_mult, 1.0, 0.001)


func test_pretre_benit_et_soigne_ses_allies() -> void:
	var e := await _engaged(&"eg_sun_priest", Vector2.ZERO, Vector2(400, 0))
	var ally := Enemy.spawn(_data(&"eg_skeleton"))
	ally.position = Vector2(80, 0)
	_world.add_child(ally)
	await wait_physics_frames(2)
	ally.hp = ally.max_hp * 0.3
	var hp0 := ally.hp
	e.force_skill(&"eg_solar_blessing")
	await wait_seconds(1.3)
	assert_gt(ally.hp, hp0, "allié soigné")
	assert_gt(ally.rage_speed_mult, 1.0, "allié galvanisé")


func test_pretre_eruption_solaire_aveugle() -> void:
	var e := await _engaged(&"eg_sun_priest", Vector2.ZERO, Vector2(300, 0))
	e.force_skill(&"eg_sun_flare")
	await wait_until(func() -> bool: return _player.has_status_kind(&"blind"), 3.0)
	assert_true(_player.has_status_kind(&"blind"), "aveuglé")


func test_boss_phases_reveil_des_morts_et_colere() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(260, 0))
	assert_not_null(e.get_skill(&"eg_curse"), "phase 1 : malédictions")
	var n0 := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.take_damage(e.max_hp * 0.35, _player)
	await wait_physics_frames(2)
	assert_not_null(e.get_skill(&"eg_raise_dead"), "phase 2 : réveil des morts")
	assert_not_null(e.get_skill(&"eg_sandstorm"), "phase 2 : tempête de sable")
	await wait_seconds(1.8)
	assert_gt(get_tree().get_nodes_in_group(&"enemy_units").size(), n0, "les morts se relèvent")
	e.invulnerable_left = 0.0
	e.take_damage(e.max_hp * 0.45, _player)
	await wait_physics_frames(2)
	assert_not_null(e.get_skill(&"eg_sun_rays"), "phase 3 : rayons du soleil")
	await wait_until(func() -> bool: return _player.has_status_kind(&"burn"), 4.0)
	assert_true(_player.has_status_kind(&"burn"), "rayons brûlants")


func test_boss_tempete_de_sable() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(260, 0))
	e.take_damage(e.max_hp * 0.35, _player)
	await wait_seconds(2.0)
	e.invulnerable_left = 0.0
	var sk := e.get_skill(&"eg_sandstorm")
	sk.cooldown_left = 0.0
	e.force_skill(&"eg_sandstorm")
	await wait_until(func() -> bool: return get_tree().get_nodes_in_group(&"eg_sandstorms").size() > 0, 2.0)
	assert_gt(get_tree().get_nodes_in_group(&"eg_sandstorms").size(), 0, "tourbillons de sable")
	await wait_until(func() -> bool: return _player.has_status_kind(&"slow"), 6.0)
	assert_true(_player.has_status_kind(&"slow"), "la tempête ralentit")
