extends GutTest
## Bestiaire du centre commercial abandonné (« Les égarés de la nuit ») : données, planches
## 8 directions, roster du monde, compétences (registre du monde mall) et leurs effets.

const WORLD_PATH := "res://data/worlds/world_03_mall.tres"
## 1re rangée de la planche (plus simples), puis 2e rangée (plus durs), de gauche à droite.
const ROW1 := [&"mall_zombie", &"mall_flayer", &"mall_security_bot"]
const ROW2 := [&"mall_clone", &"mall_brute", &"mall_night_spider"]
const ANIMS := ["idle", "run", "attack", "hit", "death"]
const OLD := ["mall_clown", "mall_director", "mall_guard", "mall_mannequin", "mall_sniper"]
const Reg := preload("res://scripts/enemies/skills/mall/registry.gd")


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
	for g: StringName in [EnemyProjectilePool.GROUP, &"enemy_dynamite", EnemyHazard.GROUP]:
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


# --- Données et planches --------------------------------------------------------------------

func test_classiques_charges_et_planches() -> void:
	for k: StringName in _classics():
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
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
		assert_eq((meta.get("muzzle_px", {}) as Dictionary).size(), 8, "point d'impact / canon %s" % k)
		# Même échelle monde que le héros et les autres ennemis (0,577 unité par pixel).
		assert_almost_eq(float(e["scale"]), 92.3 / 160.0, 0.01, "échelle %s" % k)


func test_noms_de_la_planche() -> void:
	var names := {&"mall_zombie": "Zombie", &"mall_flayer": "Écorcheur", &"mall_security_bot": "Sécurité robot",
		&"mall_clone": "Clone", &"mall_brute": "Gros brute", &"mall_night_spider": "Nuit blanche"}
	for k: StringName in names:
		assert_eq((load("res://data/enemies/%s.tres" % k) as EnemyData).display_name, names[k])


func test_caracteristiques_de_la_planche() -> void:
	var zombie := load("res://data/enemies/mall_zombie.tres") as EnemyData
	var flayer := load("res://data/enemies/mall_flayer.tres") as EnemyData
	var bot := load("res://data/enemies/mall_security_bot.tres") as EnemyData
	var clone := load("res://data/enemies/mall_clone.tres") as EnemyData
	var brute := load("res://data/enemies/mall_brute.tres") as EnemyData
	var spider := load("res://data/enemies/mall_night_spider.tres") as EnemyData
	assert_false(zombie.is_ranged(), "zombie : mêlée")
	assert_lt(zombie.move_speed, 100.0, "zombie lent")
	assert_gt(flayer.move_speed, 160.0, "écorcheur rapide")
	assert_true(bot.is_ranged(), "robot : tir à distance")
	assert_gt(bot.max_hp, flayer.max_hp, "robot : PV élevés")
	assert_gt(clone.move_speed, 160.0, "clone rapide")
	assert_true(brute.is_area_attack(), "gros brute : coup de zone")
	assert_gt(brute.max_hp, bot.max_hp, "gros brute : encaisse beaucoup")
	assert_lt(brute.move_speed, 100.0, "gros brute lent")
	assert_gt(spider.move_speed, 160.0, "nuit blanche rapide")
	assert_gt(spider.hearing_radius, spider.detection_radius * 2.0, "nuit blanche : détection sonore")
	# Difficulté croissante : 2e rangée plus coriace que la 1re.
	var hp1 := 0.0
	var hp2 := 0.0
	for k: StringName in ROW1:
		hp1 += (load("res://data/enemies/%s.tres" % k) as EnemyData).max_hp
	for k2: StringName in ROW2:
		hp2 += (load("res://data/enemies/%s.tres" % k2) as EnemyData).max_hp
	assert_gt(hp2, hp1, "2e rangée plus dure")


func test_competences_connues_et_actives() -> void:
	for k: StringName in _classics():
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
		assert_true(String(sid2).begins_with("mall_"), "id préfixé par le monde : %s" % sid2)
		assert_true(ResourceLoader.exists(String(Reg.REGISTRY[sid2])), "script %s" % sid2)


func test_roster_du_monde() -> void:
	var w := load(WORLD_PATH) as WorldData
	var everywhere := {}
	for room: Variant in w.enemy_roster:
		for k: Variant in w.enemy_roster[room]:
			everywhere[StringName(k)] = true
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "roster %s : %s" % [room, k])
	for k2: StringName in _classics():
		assert_true(everywhere.has(k2), "%s dans le roster" % k2)
	for k3: StringName in ROW1:
		assert_true((w.enemy_roster[&"combat"] as Dictionary).has(k3), "1re rangée en combat : %s" % k3)
		assert_true((w.enemy_roster[&"loot"] as Dictionary).has(k3) or k3 == &"mall_security_bot",
			"1re rangée dans les salles de fouille : %s" % k3)
	for k4: StringName in ROW2:
		assert_true((w.enemy_roster[&"combat"] as Dictionary).has(k4), "2e rangée en combat : %s" % k4)
	for old: String in OLD:
		assert_false(everywhere.has(StringName(old)), "ancien ennemi retiré du roster : %s" % old)
		assert_false(ResourceLoader.exists("res://data/enemies/%s.tres" % old), "ancien .tres supprimé : %s" % old)


func test_le_generateur_place_le_bestiaire_en_groupes() -> void:
	var w := load(WORLD_PATH) as WorldData
	var seen := {}
	var grouped := 0
	var rooms := 0
	for s in 6:
		for f: FloorLayout in MallGenerator.generate_run(9100 + s * 13, w, 3):
			var by_room := {}
			for sp in f.enemy_spawns:
				seen[sp.kind] = true
				(by_room.get_or_add(sp.room_id, []) as Array).append(sp.cell)
			for rid: Variant in by_room:
				var cells: Array = by_room[rid]
				if cells.size() < 3:
					continue
				rooms += 1
				# Au moins une paire d'ennemis voisins (≤ 2 cases) : ils forment un groupe.
				var near := false
				for i in cells.size():
					for j in range(i + 1, cells.size()):
						var a: Vector2i = cells[i]
						var b: Vector2i = cells[j]
						if absi(a.x - b.x) + absi(a.y - b.y) <= 2:
							near = true
				if near:
					grouped += 1
	for k: StringName in _classics():
		assert_true(seen.has(k), "%s généré dans un raid" % k)
	for old: String in OLD:
		assert_false(seen.has(StringName(old)), "plus d'ancien ennemi généré : %s" % old)
	assert_gt(rooms, 0)
	assert_gt(float(grouped) / float(maxi(rooms, 1)), 0.6, "ennemis regroupés par zones")


# --- Compétences ----------------------------------------------------------------------------

func test_ecorcheur_bondit_sur_sa_cible() -> void:
	var e := await _engaged(&"mall_flayer", Vector2.ZERO, Vector2(260, 0))
	e.force_skill(&"mall_pounce")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"ring")), "cercle d'atterrissage (télégraphe)")
	assert_lt(e.global_position.x, 10.0, "accroupi pendant le télégraphe")
	assert_eq(_player.hits.size(), 0, "aucun dégât avant le bond")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.0)
	assert_gt(e.global_position.x, 150.0, "a bondi vers le joueur")
	assert_gt(_player.hits.size(), 0, "retombe sur le joueur")


func test_robot_declenche_l_alarme_et_appelle_des_renforts() -> void:
	var e := await _engaged(&"mall_security_bot", Vector2.ZERO, Vector2(300, 0))
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.force_skill(&"mall_alarm")
	await wait_physics_frames(3)
	assert_true(bool(e.visual.call("has_skill_fx", &"beep")), "gyrophare (télégraphe)")
	await wait_seconds(1.4)
	var after := get_tree().get_nodes_in_group(&"enemy_units").size()
	assert_gt(after, before, "renforts arrivés")


func test_robot_blindage_reduit_les_degats() -> void:
	var e := await _engaged(&"mall_security_bot", Vector2.ZERO, Vector2(200, 0))
	e.face(Vector2.RIGHT)
	var hp0 := e.hp
	e.take_damage(10.0, _player)
	assert_lt(hp0 - e.hp, 10.0, "blindage frontal")


func test_clone_cree_des_illusions_qui_se_dissipent() -> void:
	var e := await _engaged(&"mall_clone", Vector2.ZERO, Vector2(260, 0))
	var n0 := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.force_skill(&"mall_illusion")
	await wait_seconds(0.9)
	var units := get_tree().get_nodes_in_group(&"enemy_units")
	assert_gt(units.size(), n0, "doubles illusoires apparus")
	var illusion: Enemy = null
	for u: Node in units:
		if u != e and u is Enemy and (u as Enemy).data.kind == &"mall_clone":
			illusion = u as Enemy
	assert_not_null(illusion, "l'illusion a l'apparence du clone")
	if illusion != null:
		assert_not_null(illusion.get_skill(&"mall_illusion_body"))
		illusion.take_damage(5.0, _player)
		assert_true(illusion.is_queued_for_deletion(), "se dissipe au premier coup, sans cadavre")
	assert_lt(e.visual.modulate.a, 0.5, "le vrai clone devient presque invisible")


func test_clone_surgit_dans_le_dos() -> void:
	var e := await _engaged(&"mall_clone", Vector2.ZERO, Vector2(300, 0))
	_player.aim_direction = Vector2.LEFT  # le joueur vise le clone
	var s := e.get_skill(&"mall_shadow_step")
	s.cooldown_left = 0.0
	assert_true(s.can_use(300.0, true), "position dans le dos trouvée")
	e.force_skill(&"mall_shadow_step")
	await wait_seconds(0.6)
	assert_gt(e.global_position.x, 330.0, "réapparu derrière le joueur")


func test_gros_brute_onde_de_choc_et_peau_dure() -> void:
	var e := await _engaged(&"mall_brute", Vector2.ZERO, Vector2(150, 0))
	e.face(Vector2.RIGHT)
	var hp0 := e.hp
	e.take_damage(10.0, _player)
	assert_almost_eq(hp0 - e.hp, 6.5, 0.01, "peau dure de face au contact")
	e.force_skill(&"shockwave")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 2.5)
	assert_gt(_player.hits.size(), 0, "onde de choc")


func test_nuit_blanche_se_cache_dans_l_ombre() -> void:
	var e := await _engaged(&"mall_night_spider", Vector2.ZERO, Vector2(600, 0))
	var sk := e.get_skill(&"mall_shadow_skin")
	assert_not_null(sk)
	await wait_seconds(0.4)
	if e.current_state_name() != Enemy.STATE_ATTACK and e.current_state_name() != Enemy.STATE_SKILL:
		assert_true(bool(sk.call("is_hidden")), "translucide en dehors des attaques")
		assert_lt(e.visual.modulate.a, 0.5)
	e.take_damage(5.0, _player)
	await wait_physics_frames(2)
	assert_false(bool(sk.call("is_hidden")), "révélée quand on la touche")
	assert_almost_eq(e.visual.modulate.a, 1.0, 0.01)


# --- Élites et boss -------------------------------------------------------------------------

const ELITES := [&"mall_violent", &"mall_store_warden"]
const BOSS := &"mall_omnistore"


func test_elites_declares() -> void:
	var w := load(WORLD_PATH) as WorldData
	assert_eq(w.elite_kinds.size(), 2, "2 élites par monde")
	for k: StringName in ELITES:
		assert_true(w.elite_kinds.has(k), "élite du monde : %s" % k)
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_not_null(d)
		if d == null:
			continue
		assert_true(d.elite, "%s : elite = true" % k)
		assert_false(d.boss)
		assert_gt(d.max_hp, (load("res://data/enemies/mall_brute.tres") as EnemyData).max_hp, "%s plus coriace que les classiques" % k)
		assert_true(EnemyArt.has_sheet(k), "planches %s" % k)
		for entry: Variant in d.skills:
			assert_true(EnemySkills.has_skill(StringName(str((entry as Dictionary)["id"]))), "%s : %s" % [k, entry["id"]])
	assert_eq((load("res://data/enemies/mall_violent.tres") as EnemyData).display_name, "Le Violent")
	assert_eq((load("res://data/enemies/mall_store_warden.tres") as EnemyData).display_name, "Le Gardien de magasin")


func test_boss_declare_avec_trois_phases() -> void:
	var w := load(WORLD_PATH) as WorldData
	assert_eq(w.boss_kind, BOSS)
	var d := load("res://data/enemies/%s.tres" % BOSS) as EnemyData
	assert_not_null(d)
	if d == null:
		return
	assert_true(d.boss)
	assert_eq(d.display_name, "L'Omnistore")
	assert_eq(d.boss_title, "Entité de consommation corrompue")
	assert_true(EnemyArt.has_sheet(BOSS), "planches du boss")
	assert_eq(d.phases.size(), 3, "3 phases")
	var froms := [1.0, 0.7, 0.3]
	var wanted := [[&"mall_panic_wave", &"mall_illusion"], [&"mall_alarm", &"teleport"], [&"mall_overload"]]
	for i in 3:
		var ph: Dictionary = d.phases[i]
		assert_almost_eq(float(ph["from"]), froms[i], 0.001, "phase %d" % (i + 1))
		var ids := []
		for entry: Variant in ph.get("skills", []):
			var sid := StringName(str((entry as Dictionary)["id"]))
			assert_true(EnemySkills.has_skill(sid), "phase %d : %s connue" % [i + 1, sid])
			ids.append(sid)
		for sid2: StringName in wanted[i]:
			assert_true(ids.has(sid2), "phase %d : %s (planche)" % [i + 1, sid2])
	assert_gt(float((d.phases[2] as Dictionary).get("damage_mult", 1.0)), 1.2, "phase 3 enragée")
	# « Vraiment très difficile » : plusieurs fois les PV d'une élite.
	assert_gt(d.max_hp, 5.0 * (load("res://data/enemies/mall_store_warden.tres") as EnemyData).max_hp)


func test_violent_devient_invisible() -> void:
	var e := await _engaged(&"mall_violent", Vector2.ZERO, Vector2(300, 0))
	var sk := e.get_skill(&"mall_cloak")
	e.force_skill(&"mall_cloak")
	await wait_seconds(0.6)
	assert_true(bool(sk.call("is_cloaked")), "invisibilité temporaire")
	assert_lt(e.visual.modulate.a, 0.2)
	assert_gt(e.rage_speed_mult, 1.0, "plus rapide")
	e.take_damage(5.0, _player)
	assert_false(bool(sk.call("is_cloaked")), "révélé quand il est touché")
	assert_almost_eq(e.rage_speed_mult, 1.0, 0.001)
	assert_almost_eq(e.visual.modulate.a, 1.0, 0.01)


func test_gardien_bouclier_et_renforts() -> void:
	var e := await _engaged(&"mall_store_warden", Vector2.ZERO, Vector2(320, 0))
	var sh := e.get_skill(&"energy_shield")
	e.force_skill(&"energy_shield")
	await wait_until(func() -> bool: return bool(sh.call("is_shield_up")), 2.0)
	e.face(Vector2.RIGHT)
	var hp0 := e.hp
	e.take_damage(20.0, _player)
	assert_lt(hp0 - e.hp, 5.0, "bouclier de protection")
	var before := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.get_skill(&"mall_alarm").cooldown_left = 0.0
	await wait_seconds(0.3)
	e.force_skill(&"mall_alarm")
	await wait_seconds(1.5)
	assert_gt(get_tree().get_nodes_in_group(&"enemy_units").size(), before, "appel de renforts")


## Équilibrage du Gardien (fix/gardien-magasin, duels du bot : 0 % → 65 % de victoires avec
## l'arsenal moyen). Il tuait par ses renforts en chaîne et se soignait en décrochant.
func test_gardien_equilibrage() -> void:
	var d := _data(&"mall_store_warden")
	assert_almost_eq(d.max_hp, 400.0, 0.01, "PV 520 → 400")
	assert_almost_eq(d.attack_damage, 15.0, 0.01, "dégâts 20 → 15")
	assert_almost_eq(d.return_regen_mult, 0.0, 0.001, "pas de soin au retour")
	var alarm: Dictionary = {}
	for entry: Variant in d.skills:
		if StringName(str((entry as Dictionary)["id"])) == &"mall_alarm":
			alarm = entry
	assert_false(alarm.is_empty(), "alarme gardée (identité)")
	assert_almost_eq(float(alarm.get("hp_below", 1.0)), 0.5, 0.001, "alarme sous 50 % des PV")
	assert_eq(int(alarm.get("max_total", 0)), 2, "2 renforts vivants au plus")
	assert_eq(alarm.get("kinds", []), ["mall_zombie"])
	# Aucun renfort qui appelle lui-même des renforts (sinon le flot ne s'arrête jamais).
	for k: Variant in alarm.get("kinds", []):
		var rd := _data(StringName(str(k)))
		for entry2: Variant in rd.skills:
			var sid := StringName(str((entry2 as Dictionary)["id"]))
			assert_false(sid == &"mall_alarm" or sid == &"whistle", "%s n'appelle pas de renforts" % k)


func test_gardien_ne_se_soigne_pas_au_retour() -> void:
	var e := await _engaged(&"mall_store_warden", Vector2.ZERO, Vector2(320, 0))
	assert_almost_eq(e.return_regen_ratio_per_sec, 0.0, 0.0001)
	e.take_damage(100.0, _player)
	var hp0 := e.hp
	e.state_machine.transition_to(Enemy.STATE_RETURN)
	await wait_seconds(0.5)
	assert_almost_eq(e.hp, hp0, 0.01, "entamé, il le reste")
	var z := await _engaged(&"mall_zombie", Vector2(-400, 0), Vector2(320, 0))
	assert_gt(z.return_regen_ratio_per_sec, 0.0, "les autres ennemis gardent leur régénération")


func test_boss_ondes_de_panique_desorientent() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(200, 0))
	e.force_skill(&"mall_panic_wave")
	await wait_until(func() -> bool: return _player.has_status_kind(&"blind"), 3.0)
	assert_true(_player.has_status_kind(&"blind"), "désoriente")
	assert_true(_player.has_status_kind(&"slow"), "ralentit")


func test_boss_change_de_phase_et_surcharge() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(260, 0))
	assert_not_null(e.get_skill(&"mall_panic_wave"), "phase 1 : ondes de panique")
	e.take_damage(e.max_hp * 0.35, _player)
	await wait_physics_frames(2)
	assert_not_null(e.get_skill(&"mall_alarm"), "phase 2 : appel des consommables")
	assert_not_null(e.get_skill(&"teleport"), "phase 2 : téléportation")
	e.invulnerable_left = 0.0
	e.take_damage(e.max_hp * 0.45, _player)
	await wait_physics_frames(2)
	assert_not_null(e.get_skill(&"mall_overload"), "phase 3 : surcharge")
	await wait_until(func() -> bool: return _player.hits.size() > 0, 4.0)
	assert_gt(_player.hits.size(), 0, "surcharge : attaque de zone")


func test_boss_illusions_sans_butin() -> void:
	var e := await _engaged(BOSS, Vector2.ZERO, Vector2(300, 0))
	var n0 := get_tree().get_nodes_in_group(&"enemy_units").size()
	e.force_skill(&"mall_illusion")
	await wait_seconds(1.1)
	var mirages: Array = []
	for u: Node in get_tree().get_nodes_in_group(&"enemy_units"):
		if u != e and u is Enemy and (u as Enemy).data.kind == BOSS:
			mirages.append(u)
	assert_gt(get_tree().get_nodes_in_group(&"enemy_units").size(), n0, "illusions")
	for m: Enemy in mirages:
		assert_false(m.data.boss, "un mirage n'est pas un second boss")
	await wait_seconds(1.0)
	assert_almost_eq(e.visual.modulate.a, 1.0, 0.01, "le vrai boss redevient visible")
