extends GutTest
## Biome « centre commercial abandonné » (Galeries Lumière) : monde, générateur (20 seeds ×
## 5 difficultés), constructeur de décor, ennemis, conteneurs et butin.

const WORLD_PATH := "res://data/worlds/world_03_mall.tres"
const SEEDS := 20
const DIFFS := 5
const MAX_MS_PER_FLOOR := 50.0
const T := FloorLayout.Tile
const KINDS := [&"mall_guard", &"mall_clown", &"mall_sniper", &"mall_mannequin", &"mall_director"]
const KEYS := [&"key_mall_jewelry", &"key_mall_offices"]
const Pop := preload("res://scripts/biomes/mall/mall_populator.gd")
const EnemyKinds := preload("res://scripts/biomes/mall/enemy_kinds.gd")

var world: WorldData
## runs[seed][diff] = Array[FloorLayout]
var runs: Array = []


func before_all() -> void:
	world = load(WORLD_PATH) as WorldData
	for s in SEEDS:
		var per: Array = []
		for d in DIFFS:
			per.append(MallGenerator.generate_run(_seed(s), world, d))
		runs.append(per)


func _seed(i: int) -> int:
	return 4242 + i * 6007


func _all_floors() -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	for per: Array in runs:
		for floors: Array in per:
			for f: FloorLayout in floors:
				out.append(f)
	return out


func _floor(floors: Array, idx: int) -> FloorLayout:
	for f: FloorLayout in floors:
		if f.floor_index == idx:
			return f
	return null


func _entries(f: FloorLayout) -> Array[Vector2i]:
	var out: Array[Vector2i] = [f.player_spawn]
	for s in f.stairs:
		out.append(s.cell)
	return out


func _flood(f: FloorLayout, through_locked: bool) -> Dictionary:
	var all := {}
	for e in _entries(f):
		all.merge(f.flood_reachable(e, through_locked))
	return all


func _tag(f: FloorLayout) -> String:
	return "étage %d" % f.floor_index


# --- Monde ------------------------------------------------------------------------

func test_monde_charge() -> void:
	assert_not_null(world)
	assert_eq(world.biome, &"mall")
	assert_eq(world.display_name, "Galeries Lumière")
	assert_true(ResourceLoader.exists(world.generator_path), "générateur")
	assert_true(ResourceLoader.exists(world.builder_path), "constructeur")
	assert_eq(world.boss_kind, &"mall_director")
	assert_eq(world.floors_min, -1)
	assert_eq(world.floors_max, 2)
	for i in range(-1, 3):
		assert_true(world.floor_names.has(i), "nom d'étage %d" % i)
	assert_eq(BiomeRegistry.world_path(&"mall"), WORLD_PATH)


# --- Structure -----------------------------------------------------------------------

func test_quatre_etages_meme_grille() -> void:
	for per: Array in runs:
		var floors: Array = per[0]
		assert_eq(floors.size(), 4, "4 étages")
		var g := _floor(floors, 0)
		assert_not_null(g)
		var prev := -99
		for f: FloorLayout in floors:
			assert_gt(f.floor_index, prev, "trié par floor_index")
			prev = f.floor_index
			assert_eq(f.size, g.size, "même grille")
			for r in f.rooms:
				assert_gt(r.tags.size(), 0, "rôle de salle (tags[0])")


func test_types_de_salles_presents() -> void:
	for per: Array in runs:
		var types := {}
		for f: FloorLayout in per[2]:
			for r in f.rooms:
				types[r.type] = true
		for t: StringName in [FloorLayout.ROOM_SPAWN, FloorLayout.ROOM_COMBAT, FloorLayout.ROOM_LOOT, FloorLayout.ROOM_TRAP,
				FloorLayout.ROOM_REST, FloorLayout.ROOM_SUPER_LOOT, FloorLayout.ROOM_BOSS, FloorLayout.ROOM_EXTRACTION, FloorLayout.ROOM_CORRIDOR]:
			assert_true(types.has(t), "type %s présent dans le run" % t)
		var g := _floor(per[2], 0)
		var spawn := 0
		for r in g.rooms:
			if r.type == FloorLayout.ROOM_SPAWN:
				spawn += 1
		assert_eq(spawn, 1, "un seul hall d'entrée")
		assert_gt(_floor(per[2], -1).extraction_cells.size(), 0, "sortie du parking")
		assert_gt(_floor(per[2], 2).extraction_cells.size(), 0, "héliport")


func test_boss_unique_sur_le_toit() -> void:
	for per: Array in runs:
		for d in DIFFS:
			var bosses := 0
			for f: FloorLayout in per[d]:
				for e in f.enemy_spawns:
					if e.kind == &"mall_director":
						bosses += 1
						assert_eq(f.floor_index, 2, "le Directeur est dans les bureaux")
						assert_eq(f.get_room(e.room_id).type, FloorLayout.ROOM_BOSS)
			assert_eq(bosses, 1, "un seul Directeur")


func test_super_loot_verrouillees_et_gardees() -> void:
	for f in _all_floors():
		for r in f.rooms:
			if r.type != FloorLayout.ROOM_SUPER_LOOT:
				continue
			var locked := 0
			for d in f.doors:
				if d.room_a == r.id or d.room_b == r.id:
					assert_eq(d.state, FloorLayout.DoorState.LOCKED, "%s : %s verrouillée" % [_tag(f), r.name])
					assert_true(String(d.key_id).begins_with("key_mall_"), "clef préfixée par le biome")
					assert_true(LootDB.has_item(d.key_id), "clef %s existe comme objet" % d.key_id)
					locked += 1
			assert_gte(locked, 1)
			var guards := 0
			for e in f.enemy_spawns:
				if e.room_id == r.id:
					guards += 1
			assert_gte(guards, 2, "%s : %s gardée" % [_tag(f), r.name])
			var safes := 0
			for c in f.container_spawns:
				if c.room_id == r.id:
					safes += 1
			assert_gte(safes, 1, "%s : %s a des coffres" % [_tag(f), r.name])


func test_clefs_par_etage() -> void:
	for per: Array in runs:
		var keys := {}
		for f: FloorLayout in per[0]:
			for d in f.doors:
				if d.state == FloorLayout.DoorState.LOCKED:
					keys[d.key_id] = f.floor_index
		assert_eq(keys.get(&"key_mall_jewelry", 99), 0, "bijouterie au rez-de-chaussée")
		assert_eq(keys.get(&"key_mall_offices", 99), 2, "salle des coffres sur le toit")


# --- Connectivité -----------------------------------------------------------------------

func test_connectivite_tout_atteignable() -> void:
	for f in _all_floors():
		var reach := _flood(f, true)
		var missing := 0
		for y in f.size.y:
			for x in f.size.x:
				if FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y))) and not reach.has(Vector2i(x, y)):
					missing += 1
		assert_eq(missing, 0, "%s : cases inatteignables" % _tag(f))


func test_un_seul_bloc_depuis_le_spawn() -> void:
	# Chaque étage est d'un seul tenant : tout est atteignable depuis le point d'arrivée seul.
	for f in _all_floors():
		var reach := f.flood_reachable(f.player_spawn, true)
		for s in f.stairs:
			assert_true(reach.has(s.cell), "%s : escalier %s atteignable depuis l'arrivée" % [_tag(f), s.cell])


func test_super_loot_inatteignables_sans_clef() -> void:
	for f in _all_floors():
		var reach := _flood(f, false)
		for r in f.rooms:
			if r.type != FloorLayout.ROOM_SUPER_LOOT:
				continue
			var leak := 0
			for y in range(r.rect.position.y, r.rect.end.y):
				for x in range(r.rect.position.x, r.rect.end.x):
					if reach.has(Vector2i(x, y)):
						leak += 1
			assert_eq(leak, 0, "%s : %s atteignable sans clef" % [_tag(f), r.name])


func test_escaliers_coherents() -> void:
	for per: Array in runs:
		var floors: Array = per[1]
		for f: FloorLayout in floors:
			for s in f.stairs:
				var t := f.get_tile(s.cell)
				assert_true(t == (T.STAIRS_UP if s.up else T.STAIRS_DOWN), "tuile d'escalier")
				assert_eq(s.target_floor, f.floor_index + (1 if s.up else -1), "étage cible voisin")
				var g := _floor(floors, s.target_floor)
				assert_not_null(g, "étage cible %d existe" % s.target_floor)
				if g == null:
					continue
				var back := false
				for s2 in g.stairs:
					if s2.cell == s.target_cell and s2.target_floor == f.floor_index and s2.target_cell == s.cell and s2.up != s.up:
						back = true
				assert_true(back, "%s : escalier %s a son retour" % [_tag(f), s.cell])
				var arrival := false
				for dir: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
					var tt := g.get_tile(s.target_cell + dir)
					if tt == T.FLOOR or tt == T.STREET:
						arrival = true
				assert_true(arrival, "case d'arrivée libre à côté de %s" % s.target_cell)


func test_spawns_valides() -> void:
	var bad: Array[String] = []
	for f in _all_floors():
		if not (FloorLayout.is_walkable_tile(f.get_tile(f.player_spawn)) and f.get_tile(f.player_spawn) != T.DOOR):
			bad.append("%s : spawn joueur" % _tag(f))
		for e in f.extraction_cells:
			if not (f.get_tile(e) == T.STREET or f.get_tile(e) == T.FLOOR):
				bad.append("%s : extraction %s" % [_tag(f), e])
		var used := {}
		for list: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns, f.hiding_spot_spawns]:
			for sp: FloorLayout.Spawn in list:
				var t := f.get_tile(sp.cell)
				if not (t == T.FLOOR or t == T.STREET):
					bad.append("%s : %s hors sol praticable" % [_tag(f), sp.kind])
				if used.has(sp.cell):
					bad.append("%s : deux choses en %s" % [_tag(f), sp.cell])
				used[sp.cell] = true
		for c in f.container_spawns:
			if not world.container_kinds.has(c.kind):
				bad.append("conteneur inconnu %s" % c.kind)
		for p in f.prop_spawns:
			if not world.prop_kinds.has(p.kind):
				bad.append("décor inconnu %s" % p.kind)
		for e2 in f.enemy_spawns:
			if not ResourceLoader.exists("res://data/enemies/%s.tres" % e2.kind):
				bad.append("ennemi inconnu %s" % e2.kind)
	assert_eq(bad.size(), 0, "spawns invalides : %s" % str(bad.slice(0, 5)))


## Décors (emprises comprises), conteneurs et cachettes ne coupent aucun passage.
func test_decors_ne_bloquent_pas() -> void:
	for f in _all_floors():
		var blocked := {}
		for s in f.prop_spawns:
			for q in Pop.spawn_footprint(s):
				blocked[q] = true
		for list: Array in [f.container_spawns, f.hiding_spot_spawns]:
			for s2: FloorLayout.Spawn in list:
				blocked[s2.cell] = true
		var seen := {}
		var stack: Array[Vector2i] = []
		for e in _entries(f):
			seen[e] = true
			stack.append(e)
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := c + d
				if seen.has(n) or blocked.has(n) or not FloorLayout.is_walkable_tile(f.get_tile(n)):
					continue
				seen[n] = true
				stack.append(n)
		var missing := 0
		for y in f.size.y:
			for x in f.size.x:
				var p := Vector2i(x, y)
				if FloorLayout.is_walkable_tile(f.get_tile(p)) and not blocked.has(p) and not seen.has(p):
					missing += 1
		assert_eq(missing, 0, "%s : passage coupé" % _tag(f))


func test_cachettes_et_conteneurs_presents() -> void:
	for f in _all_floors():
		assert_gte(f.hiding_spot_spawns.size(), 3, "%s : cachettes" % _tag(f))
		assert_gte(f.container_spawns.size(), 5, "%s : conteneurs" % _tag(f))


func test_difficulte_augmente_les_ennemis() -> void:
	for per: Array in runs:
		var prev := -1
		for d in DIFFS:
			var n := 0
			for f: FloorLayout in per[d]:
				n += f.enemy_spawns.size()
			assert_gte(n, prev, "plus d'ennemis à difficulté %d" % d)
			prev = n


func test_deterministe() -> void:
	var a := MallGenerator.generate_run(777, world, 2)
	var b := MallGenerator.generate_run(777, world, 2)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i].tiles, b[i].tiles, "mêmes tuiles")
		assert_eq(a[i].doors.size(), b[i].doors.size())
		assert_eq(a[i].enemy_spawns.size(), b[i].enemy_spawns.size())
		for j in a[i].container_spawns.size():
			assert_eq(a[i].container_spawns[j].cell, b[i].container_spawns[j].cell)
			assert_eq(a[i].container_spawns[j].kind, b[i].container_spawns[j].kind)
	var c := MallGenerator.generate_floor(777, world, 2, 1)
	assert_eq(c.tiles, MallGenerator.find_floor(a, 1).tiles, "generate_floor == generate_run")
	assert_null(MallGenerator.generate_floor(777, world, 2, 5))


func test_performance() -> void:
	var t0 := Time.get_ticks_usec()
	var n := 0
	for s in 6:
		n += MallGenerator.generate_run(90000 + s, world, 4).size()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	assert_lt(ms, MAX_MS_PER_FLOOR, "génération : %.1f ms par étage" % ms)


# --- Décor ------------------------------------------------------------------------------

func test_construction_de_chaque_etage() -> void:
	var floors := MallGenerator.generate_run(31337, world, 2)
	BiomeAssets.set_world(world)
	for f: FloorLayout in floors:
		var root := MallBuilder.build(f, world)
		add_child_autofree(root)
		assert_true(root.y_sort_enabled)
		assert_true(root.has_signal("stairs_entered"))
		for m: String in ["get_doors", "get_stairs_areas", "get_room_at_world", "set_stairs_cooldown"]:
			assert_true(root.has_method(m), m)
		assert_eq(root.get_doors().size(), f.doors.size(), "une porte par layout.doors")
		for d: DoorNode in root.get_doors():
			assert_true(d.is_in_group(&"doors"))
			assert_eq(d.is_locked(), f.get_door_at(d.cell).state == FloorLayout.DoorState.LOCKED)
		assert_eq(root.get_stairs_areas().size(), f.stairs.size())
		for a: Area2D in root.get_stairs_areas():
			assert_true(a.get_meta(&"stairs") is FloorLayout.Stairs)
		assert_eq(root.get_props().size(), f.prop_spawns.size(), "un décor par spawn")
		assert_eq(root.get_roofs().size(), f.buildings.size(), "un plafond par boutique")
		var body := root.get_wall_body()
		assert_eq(body.collision_layer, 1, "murs sur la couche world")
		var solid := 0
		for t: int in f.tiles:
			if FloorLayout.is_opaque_tile(t):
				solid += 1
		assert_lt(body.get_child_count(), solid / 4, "collisions fusionnées")
		var r := root.get_room_at_world(FloorLayout.cell_to_world(f.player_spawn))
		assert_not_null(r, "salle au spawn")
		root.set_stairs_cooldown(0.4)


func test_conteneurs_du_biome_gardent_leur_kind() -> void:
	var floors := MallGenerator.generate_run(2024, world, 1)
	var g := MallGenerator.find_floor(floors, 0)
	BiomeAssets.set_world(world)
	var root := MallBuilder.build(g, world)
	add_child_autofree(root)
	var loot := LootSpawner.spawn_for_floor(g, root, 2024, 1)
	await wait_frames(2)
	var by_cell := {}
	for c in g.container_spawns:
		by_cell[c.cell] = c.kind
	var n := 0
	for ch: Node in loot.get_children():
		if ch is LootContainer:
			var lc := ch as LootContainer
			assert_eq(lc.kind, by_cell[lc.cell], "kind du biome conservé")
			assert_not_null(LootDB.get_table(lc.kind), "table %s" % lc.kind)
			assert_ne(lc.get_display_name(), "Caisse", "libellé propre au biome")
			n += 1
		elif ch is HidingSpot:
			assert_true(String((ch as HidingSpot).kind).begins_with("mall_"), "cachette du biome")
	assert_eq(n, g.container_spawns.size())
	BiomeAssets.set_world(null)


# --- Ennemis, conteneurs, objets ----------------------------------------------------------

func test_ennemis_visuels_et_donnees() -> void:
	var extra := BiomeRegistry.extra_enemy_kinds()
	for k: StringName in KINDS:
		assert_true(EnemyKinds.KINDS.has(k), "KINDS %s" % k)
		assert_true(extra.has(k), "chargé par BiomeRegistry : %s" % k)
		var data := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_not_null(data, "EnemyData %s" % k)
		assert_eq(data.kind, k)
		assert_gt(data.max_hp, 0.0)
		assert_gt(data.sight_gain, 0.0)
		assert_gt(data.hearing_radius, 0.0)
		assert_gt(data.awareness_decay, 0.0)
		var v := EnemyVisual.new()
		add_child_autofree(v)
		v.setup(k)
		assert_eq(v.kind, k, "EnemyVisual accepte %s" % k)
		var tex := load(EnemyKinds.KINDS[k]["path"]) as Texture2D
		assert_not_null(tex, "sprite %s" % k)
		assert_eq(Vector2(tex.get_size()), EnemyKinds.KINDS[k]["svg_size"], "svg_size = taille du PNG")
	var sniper := load("res://data/enemies/mall_sniper.tres") as EnemyData
	assert_true(sniper.is_ranged(), "sniper à distance")
	var boss := load("res://data/enemies/mall_director.tres") as EnemyData
	assert_true(boss.is_area_attack(), "Directeur : coup de zone")


func test_conteneurs_tables_et_sprites() -> void:
	BiomeAssets.set_world(world)
	for k: StringName in world.container_kinds:
		var t := LootDB.get_table(k)
		assert_not_null(t, "table %s" % k)
		if t != null:
			assert_false(t.entries.is_empty())
			for id: Variant in t.entries:
				assert_true(LootDB.has_item(StringName(id)), "%s : objet %s" % [k, id])
		assert_true(ResourceLoader.exists(world.containers_dir + String(k) + ".png"), "sprite %s" % k)
		assert_true(ResourceLoader.exists(world.containers_dir + String(k) + "_open.png"), "sprite %s ouvert" % k)
	for h: StringName in Pop.HIDING.values().reduce(func(acc: Array, d: Dictionary) -> Array:
			for kk: Variant in d:
				if not acc.has(kk):
					acc.append(kk)
			return acc, []):
		assert_true(ResourceLoader.exists(world.containers_dir + "hide_" + String(h) + ".png"), "cachette %s" % h)
	BiomeAssets.set_world(null)


func test_objets_du_biome() -> void:
	var n := 0
	for it: ItemData in LootDB.all_items():
		if String(it.id).begins_with("mall_"):
			n += 1
			assert_not_null(it.icon, "icône %s" % it.id)
	assert_between(n, 10, 20, "10 à 15 objets propres au biome")
	for k: StringName in KEYS:
		var it := LootDB.get_item(k)
		assert_not_null(it, "clef %s" % k)
		if it != null:
			assert_true(it.is_key())


func test_decors_dans_l_atlas() -> void:
	var Prop := load("res://scripts/biomes/mall/mall_prop.gd")
	for k: StringName in world.prop_kinds:
		assert_true(Prop.has_piece("prop_" + String(k)), "pièce prop_%s" % k)



# --- Aménagement par gabarits (mobilier, cloisons, décors muraux) -------------------------

const FurnishChecks := preload("res://tests/furnish_checks.gd")


func test_amenagement_conteneurs_accessibles_et_abords_libres() -> void:
	for f in _all_floors():
		var starts: Array[Vector2i] = _entries(f)
		var bad := FurnishChecks.containers_reachable(f, starts, _big_cells(f))
		bad.append_array(FurnishChecks.gates_clear(f, _big_cells(f)))
		bad.append_array(FurnishChecks.partitions_ok(f))
		bad.append_array(FurnishChecks.wall_decor_ok(f))
		assert_eq(bad.size(), 0, "%s : %s" % [_tag(f), str(bad.slice(0, 4))])
		if not bad.is_empty():
			return


func test_amenagement_chaque_piece_recoit_son_gabarit() -> void:
	var tpl: Dictionary = preload("res://scripts/biomes/mall/mall_templates.gd").templates()
	var empty := 0
	var total := 0
	var seen := {}
	for f in _all_floors():
		var e := FurnishChecks.empty_templated_rooms(f, tpl)
		empty += e.size()
		for r in f.rooms:
			if not r.outdoor and r.tags.size() > 0 and tpl.has(StringName(r.tags[0])):
				total += 1
				seen[StringName(r.tags[0])] = true
	gut.p("Salles aménagées vides : %d / %d" % [empty, total])
	assert_gt(total, 0)
	assert_lt(float(empty), float(total) * 0.03, "presque toutes les salles reçoivent leur gabarit")
	for role: StringName in [&"shop_clothes", &"supermarket", &"stockroom", &"cinema_hall", &"office", &"shop_electronics"]:
		assert_true(seen.has(role), "gabarit %s utilisé" % role)


func test_amenagement_murs_libres_pour_tourelles() -> void:
	var worst := 0.0
	for f in _all_floors():
		worst = maxf(worst, FurnishChecks.wall_decor_ratio(f))
	gut.p("Part maximale des faces de murs décorées : %.2f" % worst)
	assert_lt(worst, 0.5, "la majorité des murs reste libre")


func test_amenagement_deterministe() -> void:
	for s in 3:
		var a: Array = MallGenerator.generate_run(_seed(s), world, 2)
		var b: Array = MallGenerator.generate_run(_seed(s), world, 2)
		assert_eq(a.size(), b.size())
		for i in a.size():
			assert_eq(FurnishChecks.signature(a[i]), FurnishChecks.signature(b[i]), "aménagement identique (seed %d)" % s)


## Emprises des grands décors posés par règles (fontaine, voitures…).
func _big_cells(f: FloorLayout) -> Dictionary:
	var out := {}
	for s in f.prop_spawns:
		for q in Pop.spawn_footprint(s):
			out[q] = true
	return out
