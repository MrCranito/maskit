extends GutTest
## Biome Station Orbitale Kagami : générateur (20 seeds × 5 difficultés), constructeur de
## décor, ennemis, conteneurs, cachettes et butin.

const WORLD_PATH := "res://data/worlds/world_02_space_station.tres"
const Gen := preload("res://scripts/biomes/space_station/space_station_generator.gd")
const Builder := preload("res://scripts/biomes/space_station/space_station_builder.gd")
const Kinds := preload("res://scripts/biomes/space_station/enemy_kinds.gd")
const Prop := preload("res://scripts/biomes/space_station/ss_prop.gd")
const SEEDS := 20
const DIFFS := 5
const MAX_MS_PER_FLOOR := 50.0
const T := FloorLayout.Tile

var world: WorldData
var runs: Array = []


func before_all() -> void:
	world = load(WORLD_PATH) as WorldData
	for s in SEEDS:
		var per_diff: Array = []
		for d in DIFFS:
			per_diff.append(Gen.generate_run(_seed(s), world, d))
		runs.append(per_diff)


func _seed(i: int) -> int:
	return 2000 + i * 7919


func _all_floors() -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	for per_diff: Array in runs:
		for floors: Array in per_diff:
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
	return "pont %d (%dx%d)" % [f.floor_index, f.size.x, f.size.y]


# --- Monde ----------------------------------------------------------------------------

func test_monde_charge() -> void:
	assert_not_null(world)
	assert_eq(world.biome, &"space_station")
	assert_eq(world.display_name, "Station Orbitale Kagami")
	assert_true(ResourceLoader.exists(world.generator_path), "générateur")
	assert_true(ResourceLoader.exists(world.builder_path), "constructeur")
	assert_true(DirAccess.dir_exists_absolute(world.containers_dir), "dossier des conteneurs")
	for i: int in [-1, 0, 1]:
		assert_true(world.floor_names.has(i), "nom du pont %d" % i)
	assert_eq(BiomeRegistry.world_path(&"space_station"), WORLD_PATH)
	for k: Variant in world.enemy_roster:
		for kind: Variant in world.enemy_roster[k]:
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % kind), "EnemyData %s" % kind)
	assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % world.boss_kind), "boss")


func test_boss_seulement_salle_boss() -> void:
	var bad := 0
	var bosses := 0
	for f in _all_floors():
		for sp in f.enemy_spawns:
			if sp.kind == world.boss_kind:
				bosses += 1
				var r := f.get_room(sp.room_id)
				if r == null or r.type != FloorLayout.ROOM_BOSS:
					bad += 1
	assert_eq(bad, 0, "boss hors de la salle du réacteur")
	assert_gt(bosses, 0, "le boss apparaît")


# --- Structure -----------------------------------------------------------------------------

func test_trois_ponts_meme_grille() -> void:
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		assert_eq(floors.size(), 3, "ponts -1, 0, 1")
		var g := _floor(floors, 0)
		assert_not_null(g)
		var prev := -99
		for f: FloorLayout in floors:
			assert_gt(f.floor_index, prev, "trié par floor_index")
			prev = f.floor_index
			assert_eq(f.size, g.size, "même grille")
		assert_between(g.size.x, 60, 70)
		assert_between(g.size.y, 38, 48)


func test_roles_et_types_de_salles() -> void:
	var seen_types := {}
	for f in _all_floors():
		var spawn := 0
		var boss := 0
		var sup := 0
		for r in f.rooms:
			assert_false(r.tags.is_empty() or r.tags[0] == "", "%s : rôle (tags[0]) de %s" % [_tag(f), r.name])
			assert_false(r.name.is_empty(), "nom de salle")
			seen_types[r.type] = true
			if r.type == FloorLayout.ROOM_SPAWN:
				spawn += 1
			if r.type == FloorLayout.ROOM_BOSS:
				boss += 1
			if r.type == FloorLayout.ROOM_SUPER_LOOT:
				sup += 1
		assert_lte(sup, 1, "%s : au plus une salle scellée" % _tag(f))
		match f.floor_index:
			0:
				assert_eq(spawn, 1, "hangar d'arrivée")
				assert_gte(f.extraction_cells.size(), 1, "capsules de sauvetage")
			-1:
				assert_eq(boss, 1, "salle du réacteur")
	for t: StringName in [&"spawn", &"combat", &"loot", &"trap", &"rest", &"super_loot", &"boss", &"extraction", &"corridor"]:
		assert_true(seen_types.has(t), "type de salle %s présent" % t)


func test_salles_attendues_par_pont() -> void:
	var expect := {0: ["hangar", "pod_bay", "mess_hall", "infirmary", "lab", "quarters", "elevator"],
		1: ["bridge", "radar", "officer_quarters", "elevator"], -1: ["reactor", "elevator"]}
	for per_diff: Array in runs:
		for f: FloorLayout in per_diff[0]:
			var roles := {}
			for r in f.rooms:
				roles[r.tags[0]] = true
			for role: String in expect[f.floor_index]:
				assert_true(roles.has(role), "%s : salle %s" % [_tag(f), role])


func test_super_loot_verrouillees_gardees_cle_du_biome() -> void:
	var keys_seen := {}
	for f in _all_floors():
		for r in f.rooms:
			if r.type != FloorLayout.ROOM_SUPER_LOOT:
				continue
			var n := 0
			for d in f.doors:
				if d.room_a == r.id or d.room_b == r.id:
					n += 1
					assert_eq(d.state, FloorLayout.DoorState.LOCKED, "porte verrouillée")
					assert_true(String(d.key_id).begins_with("key_space_"), "clef préfixée : %s" % d.key_id)
					var it := LootDB.get_item(d.key_id)
					assert_not_null(it, "objet clef %s" % d.key_id)
					if it != null:
						assert_true(it.is_key())
					keys_seen[d.key_id] = true
			assert_eq(n, 1, "%s : %s a une seule porte" % [_tag(f), r.name])
			var guards := 0
			for e in f.enemy_spawns:
				if e.room_id == r.id:
					guards += 1
			assert_gte(guards, 2, "%s gardée" % r.name)
	for k: StringName in Gen.KEYS:
		assert_true(keys_seen.has(k), "clef %s utilisée" % k)


# --- Connectivité ----------------------------------------------------------------------------

func test_connectivite_tout_atteignable() -> void:
	for f in _all_floors():
		var reach := _flood(f, true)
		var missing := 0
		for y in f.size.y:
			for x in f.size.x:
				if FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y))) and not reach.has(Vector2i(x, y)):
					missing += 1
		assert_eq(missing, 0, "%s : cases inatteignables" % _tag(f))


func test_super_loot_inatteignable_sans_clef() -> void:
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


func test_decors_ne_bloquent_pas() -> void:
	for f in _all_floors():
		var blocked := {}
		for l: Array in [f.prop_spawns, f.container_spawns, f.hiding_spot_spawns]:
			for s: FloorLayout.Spawn in l:
				blocked[s.cell] = true
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


## Les salles fermées ne communiquent que par des portes (coursives et salles « open » exceptées).
func test_salles_fermees_par_des_portes() -> void:
	for f in _all_floors():
		var bad := 0
		var orphan := 0
		for y in f.size.y:
			for x in f.size.x:
				var a := Vector2i(x, y)
				if not FloorLayout.is_walkable_tile(f.get_tile(a)) or f.get_tile(a) == T.DOOR:
					continue
				var ra := f.room_at(a)
				if ra == null:
					orphan += 1
					continue
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var b := a + d
					if not FloorLayout.is_walkable_tile(f.get_tile(b)) or f.get_tile(b) == T.DOOR:
						continue
					var rb := f.room_at(b)
					if rb == null or rb.id == ra.id:
						continue
					var closed_a := not ra.tags.has("corridor") and not ra.tags.has("conduit") and not ra.tags.has("open")
					var closed_b := not rb.tags.has("corridor") and not rb.tags.has("conduit") and not rb.tags.has("open")
					if closed_a or closed_b:
						bad += 1
		assert_eq(orphan, 0, "%s : cases hors salle" % _tag(f))
		assert_eq(bad, 0, "%s : salle fermée ouverte sans porte" % _tag(f))


func test_portes_traversables() -> void:
	for f in _all_floors():
		for d in f.doors:
			var n1 := d.cell + (Vector2i.LEFT if d.vertical else Vector2i.UP)
			var n2 := d.cell + (Vector2i.RIGHT if d.vertical else Vector2i.DOWN)
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(n1)) and FloorLayout.is_walkable_tile(f.get_tile(n2)), "%s : porte %s" % [_tag(f), d.cell])
			assert_ne(d.room_a, -1)
			assert_ne(d.room_b, -1)


# --- Ascenseurs ---------------------------------------------------------------------------------

func test_ascenseurs_coherents() -> void:
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		for f: FloorLayout in floors:
			assert_gte(f.stairs.size(), 1, "%s relié" % _tag(f))
			for s in f.stairs:
				assert_eq(f.get_tile(s.cell), T.STAIRS_UP if s.up else T.STAIRS_DOWN)
				assert_eq(s.target_floor, f.floor_index + (1 if s.up else -1))
				var other := _floor(floors, s.target_floor)
				assert_not_null(other)
				if other == null:
					continue
				var back: FloorLayout.Stairs = null
				for s2 in other.stairs:
					if s2.cell == s.target_cell:
						back = s2
				assert_not_null(back, "ascenseur retour")
				if back:
					assert_eq(back.target_floor, f.floor_index)
					assert_eq(back.target_cell, s.cell)
					assert_ne(back.up, s.up)
				var arrival := false
				for dir: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
					if other.get_tile(s.target_cell + dir) == T.FLOOR:
						arrival = true
				assert_true(arrival, "case d'arrivée libre")


# --- Spawns -----------------------------------------------------------------------------------------

func test_spawns_valides() -> void:
	for f in _all_floors():
		var stairs := {}
		for s in f.stairs:
			stairs[s.cell] = true
		var occupied := {}
		var bad := 0
		for list: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns, f.hiding_spot_spawns]:
			for sp: FloorLayout.Spawn in list:
				if f.get_tile(sp.cell) != T.FLOOR or stairs.has(sp.cell) or f.get_door_at(sp.cell) != null:
					bad += 1
				if occupied.has(sp.cell) or sp.cell == f.player_spawn or f.extraction_cells.has(sp.cell):
					bad += 1
				occupied[sp.cell] = true
				var r := f.room_at(sp.cell)
				if r == null or r.id != sp.room_id:
					bad += 1
		assert_eq(bad, 0, "%s : spawns invalides" % _tag(f))
		assert_true(FloorLayout.is_walkable_tile(f.get_tile(f.player_spawn)), "spawn joueur")
		for c in f.container_spawns:
			assert_true(world.container_kinds.has(c.kind), "conteneur du biome %s" % c.kind)
		for p in f.prop_spawns:
			assert_true(Prop.is_known_kind(p.kind), "décor %s" % p.kind)
		for h in f.hiding_spot_spawns:
			assert_true(Builder.HIDING_DEFS.has(h.kind), "cachette %s" % h.kind)
		for e in f.extraction_cells:
			assert_eq(f.get_tile(e), T.FLOOR, "extraction marchable")


func test_spawn_hangar_et_extraction_eloignee() -> void:
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		var ps := g.player_spawn
		assert_eq(g.room_at(ps).tags[0], "hangar")
		assert_lte(ps.x, 4, "hangar à l'ouest")
		for e in g.extraction_cells:
			assert_gt(absi(e.x - ps.x) + absi(e.y - ps.y), g.size.x / 2, "capsules loin du hangar")


func test_ennemis_croissent_avec_difficulte() -> void:
	for per_diff: Array in runs:
		var counts: Array[int] = []
		for floors: Array in per_diff:
			var n := 0
			for f: FloorLayout in floors:
				n += f.enemy_spawns.size()
			counts.append(n)
		for d in range(1, DIFFS):
			assert_gte(counts[d], counts[d - 1], "non décroissant : %s" % [counts])
		assert_gt(counts[DIFFS - 1], counts[0], "Cauchemar > Facile : %s" % [counts])


func test_cachettes_par_pont() -> void:
	for f in _all_floors():
		assert_gte(f.hiding_spot_spawns.size(), 2, "%s : cachettes" % _tag(f))


# --- Déterminisme et performances ------------------------------------------------------------------

func _sig(f: FloorLayout) -> String:
	var parts: PackedStringArray = []
	for d in f.doors:
		parts.append("D%s%d%s" % [d.cell, d.state, d.key_id])
	for l: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns, f.hiding_spot_spawns]:
		for s: FloorLayout.Spawn in l:
			parts.append("%s%s%d" % [s.cell, s.kind, s.room_id])
	parts.append(str(f.player_spawn))
	parts.append(str(f.extraction_cells))
	return ";".join(parts)


func test_determinisme() -> void:
	for s in 5:
		var a := Gen.generate_run(_seed(s), world, 2)
		var b := Gen.generate_run(_seed(s), world, 2)
		assert_eq(a.size(), b.size())
		for i in a.size():
			assert_eq(a[i].tiles, b[i].tiles)
			assert_eq(_sig(a[i]), _sig(b[i]))
		for idx: int in [-1, 0, 1]:
			var single := Gen.generate_floor(_seed(s), world, 2, idx)
			assert_eq(single.tiles, Gen.find_floor(a, idx).tiles, "generate_floor == generate_run (%d)" % idx)
			assert_eq(_sig(single), _sig(Gen.find_floor(a, idx)))
	assert_ne(Gen.generate_floor(_seed(0), world, 2, 0).tiles, Gen.generate_floor(_seed(1), world, 2, 0).tiles)


func test_performances() -> void:
	var worst := 0.0
	var total := 0.0
	var n := 0
	for s in 8:
		for idx: int in [-1, 0, 1]:
			var t0 := Time.get_ticks_usec()
			Gen.generate_floor(_seed(s), world, 4, idx)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			worst = maxf(worst, ms)
			total += ms
			n += 1
	gut.p("Pire génération de pont : %.1f ms" % worst)
	# Moyenne sous le budget ; pic toléré à 2x (machine de CI chargée, mesures bruitées).
	assert_lt(total / maxf(1.0, float(n)), MAX_MS_PER_FLOOR, "génération moyenne d'un pont < 50 ms")
	assert_lt(worst, MAX_MS_PER_FLOOR * 2.0, "pire génération d'un pont < 100 ms")


# --- Décor ---------------------------------------------------------------------------------------------

func test_constructeur_api_et_portes() -> void:
	var floors: Array = runs[0][2]
	for f: FloorLayout in floors:
		var root := Builder.build(f, world)
		add_child_autofree(root)
		assert_true(root.y_sort_enabled)
		assert_true(root.has_signal("stairs_entered"))
		for m: String in ["get_doors", "get_stairs_areas", "get_room_at_world", "set_stairs_cooldown"]:
			assert_true(root.has_method(m), m)
		var doors: Array[DoorNode] = root.get_doors()
		assert_eq(doors.size(), f.doors.size(), "une porte par door")
		var locked := 0
		for d: DoorNode in doors:
			assert_true(d.is_in_group(&"doors"))
			assert_eq(d.position, Vector2((d.cell.x + 0.5) * 64.0, (d.cell.y + 1.0) * 64.0))
			if d.is_locked():
				locked += 1
				assert_true(String(d.key_id).begins_with("key_space_"))
		var expected := 0
		for fd in f.doors:
			if fd.state == FloorLayout.DoorState.LOCKED:
				expected += 1
		assert_eq(locked, expected)
		var areas: Array[Area2D] = root.get_stairs_areas()
		assert_eq(areas.size(), f.stairs.size())
		for a: Area2D in areas:
			assert_true(a.get_meta(&"stairs") is FloorLayout.Stairs)
		assert_eq(root.get_wall_body().collision_layer, 1, "couche world")
		var solid := 0
		for t: int in f.tiles:
			if FloorLayout.is_opaque_tile(t):
				solid += 1
		assert_lt(root.get_wall_body().get_child_count(), solid / 4, "collisions fusionnées")
		var spawn_room: FloorLayout.Room = root.get_room_at_world(FloorLayout.cell_to_world(f.player_spawn))
		assert_not_null(spawn_room)
		assert_eq(root.get_props().size(), f.prop_spawns.size())
		root.set_stairs_cooldown(0.3)


func test_ouverture_porte_coulissante() -> void:
	var f: FloorLayout = Gen.find_floor(runs[1][1], 0)
	var root := Builder.build(f, world)
	add_child_autofree(root)
	var door: DoorNode = null
	for d: DoorNode in root.get_doors():
		if not d.is_locked() and not d.is_open():
			door = d
			break
	assert_not_null(door)
	door.open()
	assert_true(door.is_open())
	assert_eq(door.collision_layer, 0, "porte ouverte : plus de collision")


func test_conteneurs_et_cachettes_du_biome_apres_spawn() -> void:
	BiomeAssets.set_world(world)
	var f: FloorLayout = Gen.find_floor(runs[2][2], 0)
	var root := Builder.build(f, world)
	add_child_autofree(root)
	var loot := LootSpawner.spawn_for_floor(f, root, 1, 2)
	await wait_process_frames(1)
	var kinds := {}
	for n: Node in loot.get_children():
		if n is LootContainer:
			kinds[(n as LootContainer).kind] = true
			assert_true(world.container_kinds.has((n as LootContainer).kind), "kind du biome rétabli : %s" % (n as LootContainer).kind)
			assert_ne((n as LootContainer).get_display_name(), "Caisse", "nom du biome")
		elif n is HidingSpot:
			assert_true(Builder.HIDING_DEFS.has((n as HidingSpot).kind), "cachette du biome : %s" % (n as HidingSpot).kind)
	assert_gt(kinds.size(), 1, "plusieurs conteneurs différents")
	BiomeAssets.set_world(null)


# --- Ennemis, conteneurs, butin ---------------------------------------------------------------------------

func test_ennemis_setup_enemy_visual() -> void:
	var kinds: Dictionary = Kinds.KINDS
	assert_eq(kinds.size(), 5)
	var extra := BiomeRegistry.extra_enemy_kinds()
	for k: StringName in kinds:
		assert_true(extra.has(k), "BiomeRegistry charge %s" % k)
		var v := EnemyVisual.new()
		add_child_autofree(v)
		v.setup(k)
		assert_eq(v.kind, k, "setup %s" % k)
		assert_not_null(load(kinds[k]["path"]) as Texture2D, "texture %s" % k)
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_not_null(d, "EnemyData %s" % k)
		if d != null:
			assert_eq(d.kind, k)
			assert_gt(d.max_hp, 0.0)
			assert_gt(d.sight_gain, 0.0)
			assert_gt(d.hearing_radius, 0.0)
			assert_gt(d.awareness_decay, 0.0)
	var drone := load("res://data/enemies/space_drone.tres") as EnemyData
	assert_true(drone.is_ranged(), "drone : tir laser")
	assert_true((load("res://data/enemies/space_soldier.tres") as EnemyData).is_ranged(), "soldat : distance")
	assert_false((load("res://data/enemies/space_android.tres") as EnemyData).is_ranged(), "androïde : mêlée")
	assert_true((load("res://data/enemies/space_brute.tres") as EnemyData).is_area_attack(), "brute : zone")
	assert_true((load("res://data/enemies/space_reactor_colossus.tres") as EnemyData).is_area_attack(), "boss : zone")


func test_chaque_conteneur_a_table_et_sprites() -> void:
	for k: StringName in world.container_kinds:
		var t := LootDB.get_table(k)
		assert_not_null(t, "table %s" % k)
		if t != null:
			assert_false(t.entries.is_empty())
			for id: Variant in t.entries:
				assert_true(LootDB.has_item(StringName(id)), "%s : objet %s" % [k, id])
		for suffix: String in ["", "_open"]:
			assert_true(ResourceLoader.exists(world.containers_dir + String(k) + suffix + ".png"), "sprite %s%s" % [k, suffix])
		assert_true(Builder.CONTAINER_DEFS.has(k))
	for h: StringName in Builder.HIDING_DEFS:
		assert_true(ResourceLoader.exists(world.containers_dir + "hide_" + String(h) + ".png"), "sprite cachette %s" % h)


func test_objets_du_biome() -> void:
	var n := 0
	for it: ItemData in LootDB.all_items():
		if String(it.id).begins_with("space_") or String(it.id).begins_with("key_space_"):
			n += 1
			assert_not_null(it.icon, "%s : icône" % it.id)
			assert_false(it.description.is_empty())
	assert_between(n, 13, 25, "objets propres au biome")


func test_decors_du_monde_dans_l_atlas() -> void:
	for k: StringName in world.prop_kinds:
		assert_true(Prop.is_known_kind(k), "décor %s" % k)
