extends GutTest
## Difficulté selon le nombre de joueurs ([coop] enemy_density_<n>, enemy_hp_<n>, enemy_damage_<n>) :
## solo inchangé, plus d'ennemis et plus solides à deux, et l'hôte et l'invité génèrent le même
## étage (même seed + même nombre de joueurs).

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 424242

var _saved_seed: int = 0
var _saved_map: Resource = null


func before_each() -> void:
	_saved_seed = GameState.run_seed
	_saved_map = GameState.current_map


func after_each() -> void:
	CoopRules.party_override = 0
	GameState.run_seed = _saved_seed
	GameState.current_map = _saved_map


## Raid généré pour `players` joueurs (sans réseau) ; renvoie {floor index: [ "kind@x,y", … ]}.
func _spawns(players: int) -> Dictionary:
	CoopRules.party_override = players
	GameState.run_seed = SEED
	GameState.current_map = null
	var raid := (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child(raid)
	await wait_physics_frames(1)
	var out := {}
	for idx: Variant in raid.floors:
		var l: FloorLayout = raid.floors[idx]
		var list: Array[String] = []
		for sp: FloorLayout.Spawn in l.enemy_spawns:
			list.append("%s@%d,%d#%d" % [sp.kind, sp.cell.x, sp.cell.y, sp.room_id])
		out[int(idx)] = list
	assert_eq(raid.party_size, players)
	raid.queue_free()
	await wait_physics_frames(1)
	return out


## « n salles occupées, moyenne a → b ennemis par salle, salle la plus peuplée c → d ».
func _room_stats(solo: Array, duo: Array) -> String:
	var rs := {}
	var rd := {}
	for e: String in solo:
		var r := e.get_slice("#", 1)
		rs[r] = int(rs.get(r, 0)) + 1
	for e: String in duo:
		var r := e.get_slice("#", 1)
		rd[r] = int(rd.get(r, 0)) + 1
	var big := ""
	for r: String in rs:
		if big == "" or int(rs[r]) > int(rs[big]):
			big = r
	var ts := 0
	var td := 0
	for r: String in rs:
		ts += int(rs[r])
		td += int(rd.get(r, 0))
	return "%d salles occupées, moyenne %.1f → %.1f ennemis par salle, salle la plus peuplée %d → %d" % [
		rs.size(), float(ts) / maxf(rs.size(), 1), float(td) / maxf(rs.size(), 1), int(rs.get(big, 0)), int(rd.get(big, 0))]


func _count(d: Dictionary) -> int:
	var n := 0
	for k: Variant in d:
		n += (d[k] as Array).size()
	return n


func test_solo_multipliers_are_one() -> void:
	for key: String in ["enemy_density", "enemy_hp", "enemy_damage"]:
		assert_eq(CoopRules.party_mult(key, 1), 1.0, "%s solo = 1" % key)
		assert_eq(CoopRules.party_mult(key, 0), 1.0, "%s (0 joueur) = 1" % key)
	assert_eq(CoopRules.raid_party_size(), 1, "hors salon : 1 joueur")


func test_two_players_harder() -> void:
	assert_gt(CoopRules.party_mult("enemy_density", 2), 1.0, "plus d'ennemis à deux")
	assert_gt(CoopRules.party_mult("enemy_hp", 2), 1.0, "ennemis plus solides à deux")
	assert_gte(CoopRules.party_mult("enemy_damage", 2), 1.0)
	assert_gte(CoopRules.party_mult("enemy_density", 4), CoopRules.party_mult("enemy_density", 2), "barème croissant")


func test_more_enemies_with_two_players() -> void:
	var solo: Dictionary = await _spawns(1)
	var duo: Dictionary = await _spawns(2)
	var ns := _count(solo)
	var nd := _count(duo)
	gut.p("Ennemis du raid (seed %d) : solo %d, à deux %d (étage 0 : %d → %d)" % [SEED, ns, nd,
		(solo.get(0, []) as Array).size(), (duo.get(0, []) as Array).size()])
	gut.p("Salle type (étage 0) : %s" % _room_stats(solo.get(0, []), duo.get(0, [])))
	assert_gt(nd, ns, "plus d'ennemis à deux")
	# Les points d'apparition du solo sont tous conservés (on ajoute, on ne déplace pas).
	for idx: Variant in solo:
		for s: String in solo[idx]:
			assert_has(duo[idx], s)


func test_host_and_guest_generate_the_same_floors() -> void:
	var host: Dictionary = await _spawns(2)
	var guest: Dictionary = await _spawns(2)
	assert_eq(host.keys().size(), guest.keys().size())
	for idx: Variant in host:
		assert_eq(guest[idx], host[idx], "étage %d identique chez l'hôte et l'invité" % idx)


func test_solo_generation_unchanged_by_coop_rules() -> void:
	var a: Dictionary = await _spawns(1)
	CoopRules.party_override = 0
	GameState.run_seed = SEED
	GameState.current_map = null
	var raid := (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child(raid)
	await wait_physics_frames(1)
	assert_eq(raid.party_size, 1, "solo : 1 joueur")
	assert_eq((raid.floors[0] as FloorLayout).enemy_spawns.size(), (a[0] as Array).size())
	raid.queue_free()
	await wait_physics_frames(1)


func test_coop_scales_enemy_hp_and_damage() -> void:
	CoopRules.party_override = 2
	GameState.run_seed = SEED
	GameState.current_map = null
	var raid := (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child(raid)
	await wait_physics_frames(2)
	var before := {}
	for e: Node in raid.enemies_container.get_children():
		if e is Enemy:
			before[e] = [(e as Enemy).max_hp, (e as Enemy).diff_damage_mult]
	assert_gt(before.size(), 0)
	var s := NetSession.new()
	s.name = "TestNetDifficulty"
	s.role = NetSession.ROLE_HOST
	s.peer_info = {"name": "Moreau"}
	add_child(s)
	var c := CoopRaid.new()
	c.setup(raid, s)
	raid.add_child(c)
	await wait_physics_frames(1)
	for e: Variant in before:
		var en := e as Enemy
		assert_almost_eq(en.max_hp, float(before[e][0]) * CoopRules.party_mult("enemy_hp", 2), 0.01, "PV × enemy_hp_2")
		assert_almost_eq(en.diff_damage_mult, float(before[e][1]) * CoopRules.party_mult("enemy_damage", 2), 0.001, "dégâts × enemy_damage_2")
	raid.queue_free()
	NetHooks.reset()
	s.queue_free()
	await wait_physics_frames(1)
