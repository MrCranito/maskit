extends GutTest
## Biome Station Orbitale Kagami : générateur (20 seeds × 5 difficultés), constructeur de
## décor, ennemis, conteneurs, cachettes et butin.

const WORLD_PATH := "res://data/worlds/world_02_space_station.tres"
const Gen := preload("res://scripts/biomes/space_station/space_station_generator.gd")
const Builder := preload("res://scripts/biomes/space_station/space_station_builder.gd")
const Kinds := preload("res://scripts/biomes/space_station/enemy_kinds.gd")
const Prop := preload("res://scripts/biomes/space_station/ss_prop.gd")
const Cross := preload("res://scripts/biomes/space_station/ss_cross.gd")
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
	# (Refonte n°3) Pont 0 = station en croix (portrait 64×116) ; ponts 1 et -1 = grille commune.
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		assert_eq(floors.size(), 3, "ponts -1, 0, 1")
		var g := _floor(floors, 0)
		assert_not_null(g)
		var prev := -99
		for f: FloorLayout in floors:
			assert_gt(f.floor_index, prev, "trié par floor_index")
			prev = f.floor_index
		assert_eq(_floor(floors, 1).size, _floor(floors, -1).size, "même grille (ponts 1 / -1)")
		assert_eq(g.size, Vector2i(Cross.W, Cross.H), "pont en croix")
		assert_gt(g.size.y, g.size.x, "format portrait")
		var o := _floor(floors, 1)
		assert_between(o.size.x, 60, 70)
		assert_between(o.size.y, 38, 48)


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
		assert_lte(sup, 2 if f.floor_index == 0 else 1, "%s : salles scellées (labo + armurerie au pont 0)" % _tag(f))
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
				# Emprise complète (mobilier de plusieurs cases posé par les gabarits).
				for q in FloorLayout.spawn_cells(s):
					blocked[q] = true
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
		assert_gte(ps.y, g.size.y - 16, "hangar au sud (bas de la croix)")
		assert_between(ps.x, g.size.x / 2 - 4, g.size.x / 2 + 4, "hangar centré")
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



# --- Aménagement par gabarits (mobilier, cloisons, décors muraux) -------------------------

const FurnishChecks := preload("res://tests/furnish_checks.gd")


func test_amenagement_conteneurs_accessibles_et_abords_libres() -> void:
	for f in _all_floors():
		var starts: Array[Vector2i] = _entries(f)
		var bad := FurnishChecks.containers_reachable(f, starts, {})
		bad.append_array(FurnishChecks.gates_clear(f, {}))
		bad.append_array(FurnishChecks.partitions_ok(f))
		bad.append_array(FurnishChecks.wall_decor_ok(f))
		assert_eq(bad.size(), 0, "%s : %s" % [_tag(f), str(bad.slice(0, 4))])
		if not bad.is_empty():
			return


func test_amenagement_chaque_piece_recoit_son_gabarit() -> void:
	var tpl: Dictionary = preload("res://scripts/biomes/space_station/ss_templates.gd").TEMPLATES
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
	for role: StringName in [&"quarters", &"mess_hall", &"lab", &"infirmary", &"storage", &"workshop", &"bridge"]:
		assert_true(seen.has(role), "gabarit %s utilisé" % role)


func test_amenagement_murs_libres_pour_tourelles() -> void:
	var worst := 0.0
	for f in _all_floors():
		worst = maxf(worst, FurnishChecks.wall_decor_ratio(f))
	gut.p("Part maximale des faces de murs décorées : %.2f" % worst)
	assert_lt(worst, 0.5, "la majorité des murs reste libre")


func test_amenagement_deterministe() -> void:
	for s in 3:
		var a: Array = Gen.generate_run(_seed(s), world, 2)
		var b: Array = Gen.generate_run(_seed(s), world, 2)
		assert_eq(a.size(), b.size())
		for i in a.size():
			assert_eq(FurnishChecks.signature(a[i]), FurnishChecks.signature(b[i]), "aménagement identique (seed %d)" % s)


# --- Pont en croix (maquette cartes.png, colonne « Station spatiale ») -------------------------

func _deck0s() -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	for per_diff: Array in runs:
		out.append(_floor(per_diff[1], 0))
	return out


func _rooms_with(f: FloorLayout, role: String) -> Array[FloorLayout.Room]:
	var out: Array[FloorLayout.Room] = []
	for r in f.rooms:
		if r.tags.size() > 0 and r.tags[0] == role:
			out.append(r)
	return out


func test_croix_composition() -> void:
	for f in _deck0s():
		var dome := _rooms_with(f, "control_center")
		assert_eq(dome.size(), 1, "centre de contrôle")
		if dome.size() == 1:
			assert_true(dome[0].tags.has("round"), "centre de contrôle circulaire")
			var c := Vector2(dome[0].rect.get_center())
			assert_lt(absf(c.x - f.size.x * 0.5), 2.0, "centre de contrôle sur l'axe")
			assert_between(c.y, f.size.y * 0.35, f.size.y * 0.6, "au milieu de la croix")
		assert_eq(_rooms_with(f, "reactor_pod").size(), 2, "deux cylindres-réacteurs")
		var tubes := _rooms_with(f, "tube")
		assert_gte(tubes.size(), 4, "tubes de liaison")
		assert_eq(_rooms_with(f, "hangar").size(), 1, "hangar d'arrivée")
		var pods := _rooms_with(f, "pod_bay")
		assert_gte(pods.size(), 2, "sas d'extraction en bout de bras")
		for e in f.extraction_cells:
			assert_eq(f.room_at(e).tags[0], "pod_bay", "extraction dans un sas")
		# Croix symétrique : autant de cases praticables à l'ouest qu'à l'est (± 12 %).
		var west := 0
		var east := 0
		for y in f.size.y:
			for x in f.size.x:
				if FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y))):
					if x < f.size.x / 2:
						west += 1
					else:
						east += 1
		assert_lt(absf(float(west - east)) / float(west + east), 0.12, "croix symétrique")
		# Bras est-ouest plus large que les ailes nord et le bas (silhouette en croix).
		var span := func(y0: int, y1: int) -> int:
			var lo := 999
			var hi := -1
			for y in range(y0, y1):
				for x in f.size.x:
					if f.get_tile(Vector2i(x, y)) != T.VOID:
						lo = mini(lo, x)
						hi = maxi(hi, x)
			return hi - lo
		assert_gt(span.call(46, 62), span.call(10, 27), "bras plus large que les ailes")
		assert_gt(span.call(46, 62), span.call(69, 82), "bras plus large que le bas")
		assert_true(f.has_meta(&"render_contract"), "contrat de rendu joint")


func test_gravite_faible_dans_modules_endommages() -> void:
	for f in _deck0s():
		assert_false(f.low_gravity_cells.is_empty(), "zones de gravité faible")
		for c: Vector2i in f.low_gravity_cells:
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(c)), "gravité faible praticable")
			var r := f.room_at(c)
			assert_true(r != null and r.tags.has("damaged"), "dans un module endommagé")
			if r == null or not r.tags.has("damaged"):
				return


## Modules fermés (toit rendu incliné vers le nord) : aucune porte dans leur mur nord, sinon le
## toit la cacherait. Chaque salle d'un bâtiment est dans son emprise.
func test_portes_visibles_camera_inclinee() -> void:
	for f in _deck0s():
		var bad: Array = []
		for b in f.buildings:
			for rid in b.room_ids:
				assert_true(b.rect.encloses(f.get_room(rid).rect.grow(-0) .intersection(b.rect)), "salle dans l'emprise")
		for d in f.doors:
			if d.vertical:
				continue
			var south := f.room_at(d.cell + Vector2i.DOWN)
			if south != null and south.building_id >= 0:
				var b2 := f.buildings[south.building_id]
				if b2.archetype in [&"ss_module", &"ss_lift"] and d.cell.y == b2.rect.position.y:
					bad.append(d.cell)
		assert_eq(bad, [], "porte dans le mur nord d'un module à toit")


func test_constructeur_toits_logiques() -> void:
	var f := _deck0s()[0]
	var root := Builder.build(f, world)
	add_child_autofree(root)
	var roofs: Array = root.call("get_roofs")
	assert_eq(roofs.size(), f.buildings.size(), "un toit logique par module fermé")
	for r: BuildingRoof in roofs:
		assert_true(String(r.name).begins_with("Roof_"))
	assert_true(root.has_method("prerender_hide"))


# --- Paquets pré-rendus (assets/prerender/space_station/<seed>/) --------------------------------

func _packs() -> PackedInt32Array:
	return PrerenderBackdrop.available_seeds(&"space_station")


func _pack_meta(s: int) -> Dictionary:
	var f := FileAccess.open(PrerenderBackdrop.pack_root(&"space_station") + str(s) + "/map.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else {}


func test_paquets_station_correspondent_au_plan() -> void:
	var seeds := _packs()
	assert_gt(seeds.size(), 0, "au moins une carte de station pré-rendue")
	for s in seeds:
		var m := _pack_meta(s)
		var L := Gen.generate_floor(s, world, 1, 0)
		assert_eq(String(m.get("tiles_md5", "")), PrerenderBackdrop.layout_md5(L), "seed %d : empreinte du plan" % s)
		assert_gte(int(m.get("ppc", 0)), 72, "seed %d : résolution ≥ 72 px/case" % s)
		assert_eq(int(m.get("tilt_deg", 0)), 38)
		assert_eq((m.get("interiors", []) as Array).size(), L.buildings.size(), "un intérieur par module fermé")
		assert_true(m.has("collision") and m.has("occluders"), "collisions et occultation")
		var dir := PrerenderBackdrop.pack_root(&"space_station") + str(s) + "/"
		for t: Dictionary in m["tiles"]:
			assert_true(ResourceLoader.exists(dir + String(t["file"])), "tuile %s" % t["file"])
		assert_true(ResourceLoader.exists(dir + "minimap.webp"), "mini-carte")
		assert_true(ResourceLoader.exists(dir + "footprint.png"), "emprise")
		assert_lt(int((m.get("collision_stats", {}) as Dictionary).get("unblocked_cells", 0)), 60, "rendu cohérent avec le plan")
		var b := PrerenderBackdrop.create(s, L, &"space_station")
		assert_not_null(b, "fond accepté par le jeu")
		if b != null:
			b.free()


func test_paquets_station_collisions_gardent_les_passages() -> void:
	for s in _packs():
		var m := _pack_meta(s)
		var L := Gen.generate_floor(s, world, 1, 0)
		var cov := {}
		for r: Array in m.get("collision", []):
			var rr := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
			for y in range(floori(rr.position.y / 64.0), ceili(rr.end.y / 64.0)):
				for x in range(floori(rr.position.x / 64.0), ceili(rr.end.x / 64.0)):
					var cr := Rect2(x * 64.0, y * 64.0, 64.0, 64.0).intersection(rr)
					cov[Vector2i(x, y)] = float(cov.get(Vector2i(x, y), 0.0)) + cr.get_area() / 4096.0
		var prot: Array[Vector2i] = [L.player_spawn]
		for d in L.doors:
			prot.append(d.cell)
		for st in L.stairs:
			prot.append(st.cell)
		prot.append_array(L.extraction_cells)
		for c: Vector2i in prot:
			assert_lt(float(cov.get(c, 0.0)), 0.01, "seed %d : abord %s libre" % [s, c])
		var blocked := {}
		for c2: Vector2i in cov:
			if float(cov[c2]) >= 0.5:
				blocked[c2] = true
		var base := L.flood_reachable(L.player_spawn)
		var seen := {L.player_spawn: true}
		var stack: Array[Vector2i] = [L.player_spawn]
		while not stack.is_empty():
			var c3: Vector2i = stack.pop_back()
			for dv: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := c3 + dv
				if seen.has(n) or blocked.has(n) or not FloorLayout.is_walkable_tile(L.get_tile(n)):
					continue
				seen[n] = true
				stack.append(n)
		# Cases des conteneurs / cachettes : objets du jeu (on interagit depuis une case voisine).
		var objs := {}
		for l: Array in [L.container_spawns, L.hiding_spot_spawns]:
			for sp: FloorLayout.Spawn in l:
				for q in FloorLayout.spawn_cells(sp):
					objs[q] = true
		var lost: Array = []
		for c4: Vector2i in base:
			if not blocked.has(c4) and not seen.has(c4) and not objs.has(c4):
				lost.append(c4)
		assert_eq(lost, [], "seed %d : cases devenues inaccessibles" % s)


## Tourelles : toujours accrochées à un mur (case WALL rendue), face à une case praticable.
func test_tourelles_sur_murs_visibles() -> void:
	var placer: Script = load("res://scripts/dungeon/turret_placer.gd")
	for f in _deck0s():
		var spots: Array = placer.call("find_spots", f, 1234, 2, 0, "world_02_space_station")
		for sp: Dictionary in spots:
			var c: Vector2i = sp["cell"]
			var n: Vector2i = sp["normal"]
			assert_eq(f.get_tile(c), T.WALL, "tourelle sur un mur")
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(c + n)), "face à une case praticable")
