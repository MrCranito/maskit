extends GutTest
## Bestiaire, partie commune : un seul boss par raid (BestiaryRules), élites du monde (escorte du
## boss, gardes des salles au trésor), phases du boss (Enemy « Boss : phases ») et barre de boss.


func _world(boss: StringName, elites: Array[StringName]) -> WorldData:
	var w := WorldData.new()
	w.boss_kind = boss
	w.elite_kinds = elites
	w.enemy_roster = {&"combat": {&"grunt_a": 1.0}}
	return w


func _floor(index: int, rooms: Array) -> FloorLayout:
	var l := FloorLayout.new(Vector2i(60, 20))
	l.floor_index = index
	var x := 0
	for r: Array in rooms:
		var room := l.add_room(Rect2i(x, 0, 10, 10), false, r[0], "salle")
		for k: StringName in r[1]:
			l.add_spawn(l.enemy_spawns, Vector2i(x + 1 + l.enemy_spawns.size() % 8, 2), k, room.id)
		x += 12
	return l


func _count(floors: Dictionary, kind: StringName) -> int:
	var n := 0
	for l: FloorLayout in floors.values():
		for sp: FloorLayout.Spawn in l.enemy_spawns:
			if sp.kind == kind:
				n += 1
	return n


## Élites de test : on s'appuie sur des kinds existants (élites de n'importe quel monde) si
## possible ; sinon les règles retombent sur le roster.
func _existing_elites() -> Array[StringName]:
	var out: Array[StringName] = []
	for f: String in DirAccess.get_files_at("res://data/enemies/"):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var d := load("res://data/enemies/" + file) as EnemyData
		if d != null and d.elite and not d.boss:
			out.append(d.kind)
	return out


func test_only_one_boss_per_raid_on_deepest_floor() -> void:
	var w := _world(&"the_boss", [])
	var floors := {
		0: _floor(0, [[&"boss", [&"the_boss", &"grunt_a"]], [&"combat", [&"grunt_a"]]]),
		1: _floor(1, [[&"boss", [&"the_boss"]]]),
		-1: _floor(-1, [[&"boss", [&"the_boss", &"the_boss"]]]),
	}
	var s := BestiaryRules.apply(floors, w, 1234)
	assert_eq(_count(floors, &"the_boss"), 1, "un seul boss dans tout le raid")
	assert_eq(int(s["boss_floor"]), -1, "boss gardé à l'étage le plus dangereux (sous-sol à égalité)")
	assert_eq(_count({0: floors[-1]}, &"the_boss"), 1)
	assert_eq(int(s["boss_removed"]), 3)


func test_rules_are_deterministic() -> void:
	var w := _world(&"the_boss", _existing_elites())
	var mk := func() -> Dictionary:
		return {0: _floor(0, [[&"combat", [&"grunt_a", &"grunt_a", &"grunt_a"]], [&"super_loot", [&"grunt_a", &"grunt_a"]]]),
			1: _floor(1, [[&"boss", [&"the_boss", &"grunt_a", &"grunt_a", &"grunt_a"]]])}
	var a: Dictionary = mk.call()
	var b: Dictionary = mk.call()
	BestiaryRules.apply(a, w, 99)
	BestiaryRules.apply(b, w, 99)
	for fi: int in a:
		for i in a[fi].enemy_spawns.size():
			assert_eq(a[fi].enemy_spawns[i].kind, b[fi].enemy_spawns[i].kind)


func test_elites_guard_treasure_and_escort_boss() -> void:
	var elites := _existing_elites()
	if elites.is_empty():
		pass_test("aucune élite déclarée pour l'instant (bestiaires en cours)")
		return
	var w := _world(&"the_boss", elites)
	var floors := {
		0: _floor(0, [[&"super_loot", [&"grunt_a", &"grunt_a", &"grunt_a"]]]),
		-1: _floor(-1, [[&"boss", [&"the_boss", &"grunt_a", &"grunt_a", &"grunt_a"]]]),
	}
	BestiaryRules.apply(floors, w, 7)
	var guards := int(Balance.get_value("boss", "elite_super_loot_guards", 1))
	var escorts := BestiaryRules.boss_escorts(GameState.difficulty)
	var n0 := 0
	for sp: FloorLayout.Spawn in floors[0].enemy_spawns:
		n0 += 1 if elites.has(sp.kind) else 0
	var n1 := 0
	for sp2: FloorLayout.Spawn in floors[-1].enemy_spawns:
		n1 += 1 if elites.has(sp2.kind) else 0
	assert_eq(n0, guards, "gardes d'élite de la salle au trésor")
	assert_eq(n1, mini(escorts, 3), "escorte d'élites du boss")


func test_worlds_declare_one_boss_and_two_elites() -> void:
	for p: String in ["res://data/worlds/world_01_far_west.tres", "res://data/worlds/world_02_space_station.tres",
			"res://data/worlds/world_03_mall.tres"]:
		var w := load(p) as WorldData
		assert_not_null(w, p)
		if w.elite_kinds.is_empty():
			pending("%s : élites pas encore déclarées (bestiaire en cours)" % p)
			continue
		assert_eq(w.elite_kinds.size(), 2, "%s : 2 élites" % p)
		var bd := load("res://data/enemies/%s.tres" % w.boss_kind) as EnemyData
		assert_not_null(bd, "%s : boss %s" % [p, w.boss_kind])
		if bd != null:
			assert_true(bd.boss, "%s : boss = true" % w.boss_kind)
			assert_eq(bd.phases.size(), 3, "%s : 3 phases" % w.boss_kind)
		for ek: StringName in w.elite_kinds:
			var ed := load("res://data/enemies/%s.tres" % ek) as EnemyData
			assert_true(ed != null and ed.elite, "%s : élite" % ek)


func _boss_data() -> EnemyData:
	var d := EnemyData.new()
	d.kind = &""
	d.display_name = "Boss de test"
	d.boss = true
	d.boss_title = "Titre"
	d.max_hp = 1000.0
	d.stagger_ratio = 0.0
	d.phases = [
		{"from": 1.0, "name": "Phase 1"},
		{"from": 0.7, "name": "Phase 2", "speed_mult": 1.3, "cooldown_mult": 0.8, "invuln": 0.5},
		{"from": 0.3, "name": "Phase 3", "damage_mult": 1.5, "attack_pattern": &"burst",
			"skills": [{"id": &"rage", "cooldown": 9.0}]},
	]
	return d


func test_boss_phases_follow_hp_and_emit_signals() -> void:
	var e := Enemy.spawn(_boss_data())
	add_child_autofree(e)
	await wait_physics_frames(2)
	assert_eq(e.boss_phase, 0)
	assert_true(e.is_in_group(Enemy.GROUP_BOSS))
	var seen: Array = []
	var cb := func(_b: Node2D, i: int, n: String) -> void: seen.append([i, n])
	EventBus.boss_phase_changed.connect(cb)
	var base_speed := e.run_speed()
	# Dégâts en part des PV max : ceux-ci dépendent de la difficulté ([boss] hp_mult).
	e.take_damage(e.max_hp * 0.35, null)
	assert_eq(e.boss_phase, 1, "phase 2 sous 70 %")
	assert_almost_eq(e.run_speed(), base_speed * 1.3, 0.01)
	assert_gt(e.invulnerable_left, 0.0, "invulnérable pendant la transition")
	# Gros coup : passe directement de la phase 2 à la phase 3.
	e.invulnerable_left = 0.0
	e.take_damage(e.max_hp * 0.5, null)
	assert_eq(e.boss_phase, 2, "phase 3 sous 30 %")
	assert_eq(e.next_pattern(), &"burst")
	assert_almost_eq(e.get_attack_damage(), e.data.attack_damage * e.diff_damage_mult * 1.5, 0.01)
	assert_not_null(e.get_skill(&"rage"), "compétences de la phase 3")
	assert_eq(seen.size(), 2)
	assert_eq(seen[1][1], "Phase 3")
	EventBus.boss_phase_changed.disconnect(cb)


func test_boss_bar_tracks_boss() -> void:
	var e := Enemy.spawn(_boss_data())
	add_child_autofree(e)
	var bar := BossBar.new()
	add_child_autofree(bar)
	await wait_physics_frames(1)
	assert_false(bar.visible)
	EventBus.boss_engaged.emit(e)
	assert_true(bar.visible)
	assert_almost_eq(bar.ratio(), 1.0, 0.001)
	e.take_damage(e.max_hp * 0.4, null)
	assert_almost_eq(bar.ratio(), 0.6, 0.001)
	EventBus.boss_defeated.emit(e)
	assert_null(bar.boss)
