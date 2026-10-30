extends GutTest
## Bestiaire du Carnaval hanté (« Le parc maudit ») : données, planches 8 directions, bestiaire
## (data/bestiary/carnival.tres : roster, élites, boss), compétences (registre du monde carnival)
## et leurs effets.

const BESTIARY_PATH := "res://data/bestiary/carnival.tres"
## 1re rangée de la planche (plus simples), puis 2e rangée (plus durs), de gauche à droite.
const ROW1 := [&"cv_lost_clown", &"cv_acrobat", &"cv_circus_dog"]
const ROW2 := [&"cv_ghost_carousel", &"cv_penumbra", &"cv_big_plush"]
const ANIMS := ["idle", "run", "attack", "hit", "death"]
const Reg := preload("res://scripts/enemies/skills/carnival/registry.gd")


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
	for g: StringName in [EnemyProjectilePool.GROUP, &"enemy_dynamite", EnemyHazard.GROUP, &"cv_music_zones"]:
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


## Ennemi au repos (pas encore alerté), loin du joueur.
func _idle(kind: StringName, pos: Vector2) -> Enemy:
	var d := (load("res://data/enemies/%s.tres" % kind) as EnemyData).duplicate() as EnemyData
	d.patrol_radius = 0.0
	var e := Enemy.spawn(d)
	e.position = pos
	_world.add_child(e)
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
		# Même échelle monde que le héros et les autres ennemis (0,577 unité par pixel).
		assert_almost_eq(float(e["scale"]), 92.3 / 160.0, 0.01, "échelle %s" % k)


func test_noms_de_la_planche() -> void:
	var names := {&"cv_lost_clown": "Clown égaré", &"cv_acrobat": "Acrobate sanguinaire",
		&"cv_circus_dog": "Chien de cirque", &"cv_ghost_carousel": "Manège fantôme", &"cv_penumbra": "Pénombre",
		&"cv_big_plush": "Grosse peluche"}
	for k: StringName in names:
		assert_eq(_load(k).display_name, names[k])


func test_caracteristiques_de_la_planche() -> void:
	var clown := _load(&"cv_lost_clown")
	var acro := _load(&"cv_acrobat")
	var dog := _load(&"cv_circus_dog")
	var carousel := _load(&"cv_ghost_carousel")
	var shade := _load(&"cv_penumbra")
	var plush := _load(&"cv_big_plush")
	for d: EnemyData in [clown, acro, dog, shade, plush]:
		assert_false(d.is_ranged(), "%s : mêlée" % d.kind)
	assert_between(clown.move_speed, 100.0, 150.0, "clown : vitesse moyenne")
	assert_gt(acro.move_speed, 180.0, "acrobate rapide")
	assert_gt(dog.move_speed, acro.move_speed, "chien très rapide")
	assert_true(carousel.is_area_attack(), "manège : zone")
	assert_gt(shade.move_speed, 180.0, "pénombre rapide")
	assert_true(plush.is_area_attack(), "peluche : coup de zone")
	assert_between(plush.move_speed, 85.0, 130.0, "peluche : vitesse moyenne")
	assert_gt(plush.max_hp, carousel.max_hp, "peluche : tank")
	# Difficulté croissante : 2e rangée plus coriace que la 1re.
	var hp1 := 0.0
	var hp2 := 0.0
	for k: StringName in ROW1:
		hp1 += _load(k).max_hp
	for k2: StringName in ROW2:
		hp2 += _load(k2).max_hp
	assert_gt(hp2, hp1 * 2.0, "2e rangée plus dure")


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
		assert_true(String(sid2).begins_with("cv_"), "id préfixé par le monde : %s" % sid2)
		assert_true(ResourceLoader.exists(String(Reg.REGISTRY[sid2])), "script %s" % sid2)


func test_valeurs_par_defaut_dans_balance_cfg() -> void:
	# Aucune valeur d'équilibrage en dur : les défauts des compétences viennent de [bestiary_carnival].
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://data/balance.cfg"), OK)
	assert_true(cfg.has_section("bestiary_carnival"))
	for key: String in ["racket_radius", "balloon_speed", "vault_flight", "shade_alpha", "ambush_offset",
			"call_count", "waltz_radius", "waltz_heal_per_sec"]:
		assert_true(cfg.has_section_key("bestiary_carnival", key), "clé %s" % key)
	var s := EnemySkills.create(&"cv_waltz")
	s.setup(null, {"id": &"cv_waltz"})
	assert_almost_eq(s.f("radius"), float(cfg.get_value("bestiary_carnival", "waltz_radius")), 0.001)


func test_bestiaire_du_monde() -> void:
	var b := load(BESTIARY_PATH) as BestiaryData
	assert_not_null(b)
	if b == null:
		return
	assert_eq(b.world_id, &"carnival")
	var everywhere := {}
	for room: Variant in b.enemy_roster:
		for k: Variant in b.enemy_roster[room]:
			everywhere[StringName(k)] = true
			assert_true(String(k).begins_with("cv_"), "roster %s : %s du carnaval" % [room, k])
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "roster %s : %s" % [room, k])
	for k2: StringName in _classics():
		assert_true(everywhere.has(k2), "%s dans le roster" % k2)
		assert_true((b.enemy_roster[&"combat"] as Dictionary).has(k2), "%s en salle de combat" % k2)
	for k3: StringName in ROW1:
		assert_true((b.enemy_roster[&"loot"] as Dictionary).has(k3), "1re rangée dans les salles de fouille : %s" % k3)
	# 2e rangée rare dans les salles calmes.
	var loot: Dictionary = b.enemy_roster[&"loot"]
	for k4: StringName in ROW2:
		assert_lt(float(loot.get(k4, 0.0)), float((b.enemy_roster[&"combat"] as Dictionary)[k4]), "%s rare en fouille" % k4)


# --- Compétences ----------------------------------------------------------------------------

func test_clown_klaxonne_et_attire_les_creatures() -> void:
	var e := await _engaged(&"cv_lost_clown", Vector2.ZERO, Vector2(300, 0))
	var other := _idle(&"cv_circus_dog", Vector2(-500, 0))
	await wait_physics_frames(2)
	assert_false(other.is_in_combat(), "le chien dort encore")
	e.force_skill(&"cv_racket")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"whistle")), "cercles sonores (télégraphe)")
	await wait_seconds(0.7)
	assert_gt(int(e.get_skill(&"cv_racket").get("alerted")), 0, "créatures attirées")
	assert_true(other.is_in_combat() or other.awareness >= 1.0, "le chien accourt vers le joueur")


func test_clown_lache_un_ballon() -> void:
	var e := await _engaged(&"cv_lost_clown", Vector2.ZERO, Vector2(300, 0))
	e.force_skill(&"cv_balloon")
	await wait_seconds(0.75)
	var pool := EnemyProjectilePool.get_or_create(get_tree())
	var balloon: EnemyProjectile = null
	for c: Node in pool.get_children():
		var proj := c as EnemyProjectile
		if proj != null and proj.active and proj.style == &"laser_red":
			balloon = proj
	assert_not_null(balloon, "ballon rouge lancé")
	if balloon != null:
		assert_lt(balloon.speed, 300.0, "ballon lent")


func test_acrobate_saute_derriere_le_joueur() -> void:
	var e := await _engaged(&"cv_acrobat", Vector2.ZERO, Vector2(260, 0))
	e.force_skill(&"cv_vault")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"ring")), "cercle d'atterrissage")
	assert_lt(e.global_position.x, 10.0, "ramassé pendant le télégraphe")
	await wait_until(func() -> bool: return e.global_position.x > 40.0, 1.5)
	assert_gt(e.invulnerable_left, 0.0, "intouchable pendant le salto")
	await wait_seconds(0.7)
	assert_gt(e.global_position.x, 300.0, "a retombé derrière le joueur")


func test_chien_aboie_et_charge() -> void:
	var e := await _engaged(&"cv_circus_dog", Vector2.ZERO, Vector2(300, 0))
	assert_not_null(e.get_skill(&"cv_racket"))
	e.force_skill(&"rush")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.5)
	assert_gt(_player.hits.size(), 0, "charge du chien")


func test_manege_zone_de_musique_ralentit_et_soigne() -> void:
	var e := await _engaged(&"cv_ghost_carousel", Vector2.ZERO, Vector2(120, 0))
	var ally := _idle(&"cv_lost_clown", Vector2(-80, 40))
	await wait_physics_frames(2)
	ally.hp = ally.max_hp * 0.5
	e.force_skill(&"cv_waltz")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"ring")), "anneau de l'orgue (télégraphe)")
	await wait_seconds(1.6)
	var zones := get_tree().get_nodes_in_group(&"cv_music_zones")
	assert_eq(zones.size(), 1, "zone de musique active")
	assert_true(_player.has_status_kind(&"slow"), "joueur ralenti dans la zone")
	assert_gt(ally.hp, ally.max_hp * 0.5, "créature soignée par la musique")
	e.take_damage(e.hp + 10.0, _player)
	await wait_physics_frames(3)
	assert_eq(get_tree().get_nodes_in_group(&"cv_music_zones").filter(func(n: Node) -> bool:
		return not n.is_queued_for_deletion()).size(), 0, "la musique cesse à sa mort")


func test_manege_appelle_des_creatures() -> void:
	var e := await _engaged(&"cv_ghost_carousel", Vector2.ZERO, Vector2(320, 0))
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.force_skill(&"cv_call")
	await wait_seconds(1.4)
	var after := get_tree().get_nodes_in_group(&"enemy_units")
	assert_gt(after.size(), before, "renforts arrivés")
	for u: Node in after:
		if u is Enemy and u != e:
			assert_true(String((u as Enemy).data.kind).begins_with("cv_"), "renfort du carnaval")


func test_penombre_cachee_dans_l_ombre() -> void:
	var e := await _engaged(&"cv_penumbra", Vector2.ZERO, Vector2(700, 0))
	var sk := e.get_skill(&"cv_shade")
	assert_not_null(sk)
	await wait_seconds(0.4)
	if e.current_state_name() != Enemy.STATE_ATTACK and e.current_state_name() != Enemy.STATE_SKILL:
		assert_true(bool(sk.call("is_hidden")), "presque invisible hors attaque")
		assert_lt(e.visual.modulate.a, 0.3)
	e.take_damage(5.0, _player)
	await wait_physics_frames(2)
	assert_false(bool(sk.call("is_hidden")), "révélée quand on la touche")
	assert_almost_eq(e.visual.modulate.a, 1.0, 0.01)


func test_penombre_surgit_dans_le_dos() -> void:
	var e := await _engaged(&"cv_penumbra", Vector2.ZERO, Vector2(300, 0))
	_player.aim_direction = Vector2.LEFT  # le joueur vise la pénombre
	var s := e.get_skill(&"cv_ambush")
	s.cooldown_left = 0.0
	assert_true(s.can_use(300.0, true), "position dans le dos trouvée")
	e.force_skill(&"cv_ambush")
	await wait_seconds(0.5)
	assert_gt(e.global_position.x, 330.0, "réapparue derrière le joueur")


func test_peluche_rembourrage_et_plongeon() -> void:
	var e := await _engaged(&"cv_big_plush", Vector2.ZERO, Vector2(250, 0))
	e.face(Vector2.LEFT)  # même de dos, le rembourrage amortit
	var hp0 := e.hp
	e.take_damage(10.0, _player)
	assert_almost_eq(hp0 - e.hp, 7.5, 0.01, "rembourrage : -25 % de tous côtés")
	e.force_skill(&"cv_vault")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.5)
	assert_gt(_player.hits.size(), 0, "plongeon écrasant")
	assert_true(_player.has_status_kind(&"knockdown"), "renversé")


# --- Élites et boss -------------------------------------------------------------------------

const ELITES := [&"cv_fairground_being", &"cv_fire_clown"]
const BOSS := &"cv_circus_king"


func test_elites_declares() -> void:
	var b := load(BESTIARY_PATH) as BestiaryData
	assert_eq(b.elite_kinds.size(), 2, "2 élites par monde")
	for k: StringName in ELITES:
		assert_true(b.elite_kinds.has(k), "élite du monde : %s" % k)
		var d := _load(k)
		assert_not_null(d)
		if d == null:
			continue
		assert_true(d.elite, "%s : elite = true" % k)
		assert_false(d.boss)
		assert_gt(d.max_hp, _load(&"cv_big_plush").max_hp, "%s plus coriace que les classiques" % k)
		assert_true(EnemyArt.has_sheet(k), "planches %s" % k)
		for entry: Variant in d.skills:
			assert_true(EnemySkills.has_skill(StringName(str((entry as Dictionary)["id"]))), "%s : %s" % [k, entry["id"]])
	assert_eq(_load(&"cv_fairground_being").display_name, "L'Être forain")
	assert_eq(_load(&"cv_fire_clown").display_name, "Le Clown de feu")
	assert_false(_load(&"cv_fairground_being").is_ranged(), "forain : mêlée / soutien")
	assert_true(_load(&"cv_fire_clown").is_ranged(), "clown de feu : distance / zone")


func test_boss_declare_avec_trois_phases() -> void:
	var b := load(BESTIARY_PATH) as BestiaryData
	assert_eq(b.boss_kind, BOSS)
	var d := _load(BOSS)
	assert_not_null(d)
	if d == null:
		return
	assert_true(d.boss)
	assert_false(d.elite)
	assert_eq(d.display_name, "Le Roi du cirque")
	assert_ne(d.boss_title, "")
	assert_true(EnemyArt.has_sheet(BOSS), "planches du boss")
	assert_eq(d.phases.size(), 3, "3 phases")
	var froms := [1.0, 0.7, 0.3]
	var wanted := [[&"cv_juggle", &"cv_fire_ring"], [&"cv_call", &"cv_fair_traps", &"teleport"],
		[&"cv_fireworks", &"cv_waltz", &"cv_call"]]
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
			assert_true(ids.has(StringName(str(sid3))), "phase %d : compétence d'entrée %s active" % [i + 1, sid3])
	assert_gt(float((d.phases[2] as Dictionary).get("damage_mult", 1.0)), 1.3, "phase 3 enragée")
	assert_lt(float((d.phases[2] as Dictionary).get("cooldown_mult", 1.0)), 0.7, "phase 3 : compétences en rafale")
	# « Vraiment très difficile » : plusieurs fois les PV d'une élite.
	assert_gt(d.max_hp, 7.0 * _load(&"cv_fairground_being").max_hp)


func test_etre_forain_galvanise_ses_creatures() -> void:
	var e := await _engaged(&"cv_fairground_being", Vector2.ZERO, Vector2(320, 0))
	var ally := _idle(&"cv_lost_clown", Vector2(-120, 60))
	await wait_physics_frames(2)
	var speed0 := ally.rage_speed_mult
	e.force_skill(&"cv_rally")
	await wait_seconds(1.0)
	var aura := ally.get_skill(&"cv_rallied")
	assert_not_null(aura, "aura du forain posée")
	if aura == null:
		return
	assert_true(bool(aura.call("is_active")))
	assert_gt(ally.rage_speed_mult, speed0, "créature plus rapide")
	var hp0 := ally.hp
	ally.take_damage(10.0, _player)
	assert_almost_eq(hp0 - ally.hp, 6.5, 0.01, "dégâts réduits sous l'aura")
	aura.tick_cooldown(30.0)
	assert_false(bool(aura.call("is_active")), "l'aura expire")
	assert_almost_eq(ally.rage_speed_mult, speed0, 0.001, "vitesse rendue")


func test_etre_forain_appelle_des_renforts() -> void:
	var e := await _engaged(&"cv_fairground_being", Vector2.ZERO, Vector2(320, 0))
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.force_skill(&"cv_call")
	await wait_seconds(1.4)
	assert_gt(get_tree().get_nodes_in_group(&"enemy_units").size(), before, "créatures appelées")


func _hazards(kind: StringName) -> int:
	var n := 0
	for h: Node in get_tree().get_nodes_in_group(EnemyHazard.GROUP):
		if (h as EnemyHazard).kind == kind and not h.is_queued_for_deletion():
			n += 1
	return n


func test_clown_de_feu_cercle_de_feu() -> void:
	var e := await _engaged(&"cv_fire_clown", Vector2.ZERO, Vector2(300, 0))
	e.force_skill(&"cv_fire_ring")
	await wait_seconds(1.3)
	var sk := e.get_skill(&"cv_fire_ring")
	var expected := int(sk.f("count")) - int(sk.f("gaps"))
	assert_eq(_hazards(&"fire"), expected, "anneau de foyers avec une sortie")
	assert_true(e.data.is_ranged())


func test_roi_jongle_seme_des_pieges_et_tire_le_grand_final() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(320, 0))
	e.force_skill(&"cv_juggle")
	await wait_seconds(1.8)
	assert_gt(_hazards(&"fire"), 0, "torches enflammées")
	e._enter_boss_phase(1, false)
	e.force_skill(&"cv_fair_traps")
	await wait_seconds(1.1)
	assert_eq(_hazards(&"trap"), int(e.get_skill(&"cv_fair_traps").f("count")), "pièges de foire semés")
	e._enter_boss_phase(2, false)
	_player.hits.clear()
	e.force_skill(&"cv_fireworks")
	await wait_until(func() -> bool: return int(e.get_skill(&"cv_fireworks").get("blasts")) > 0, 3.0)
	assert_gt(int(e.get_skill(&"cv_fireworks").get("blasts")), 0, "feux d'artifice")
	await wait_seconds(0.5)
	assert_gt(_player.hits.size(), 0, "la première fusée vise le joueur")


func test_roi_passe_ses_phases_et_appelle_la_parade() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(400, 0))
	assert_eq(e.boss_phase, 0, "phase 1 au départ")
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.take_damage(e.max_hp * 0.35, _player)
	assert_eq(e.boss_phase, 1, "phase 2 sous 70 %")
	assert_almost_eq(e.phase_damage_mult, 1.15, 0.001)
	await wait_seconds(1.6)
	assert_gt(get_tree().get_nodes_in_group(&"enemy_units").size(), before, "la parade des monstres arrive")
	e.invulnerable_left = 0.0
	e.take_damage(e.max_hp * 0.4, _player)
	assert_eq(e.boss_phase, 2, "phase 3 sous 30 %")
	assert_gt(e.phase_damage_mult, 1.3, "enragé")
	assert_not_null(e.get_skill(&"cv_fireworks"))
