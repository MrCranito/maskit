extends GutTest
## Biome « Station sous-marine » (Abysse Nérée) : monde, générateur (20 seeds x 5
## difficultés), constructeur de décor, ennemis, conteneurs, objets.

const WORLD_PATH := "res://data/worlds/world_04_underwater.tres"
const SEEDS := 20
const DIFFS := 5
const MAX_MS_PER_FLOOR := 50.0
const T := FloorLayout.Tile
const ENEMY_KINDS: Array[StringName] = [&"uw_diver", &"uw_mutant", &"uw_heavy", &"uw_eel", &"uw_guardian"]
const KEYS: Array[StringName] = [&"key_uw_lab", &"key_uw_trench"]
const HIDE_KINDS: Array[StringName] = [&"uw_locker", &"uw_pipes", &"uw_lab_table"]
const Station := preload("res://scripts/biomes/underwater/uw_station.gd")
const Pop := preload("res://scripts/biomes/underwater/uw_populator.gd")

var world: WorldData
## runs[seed][diff] = Array[FloorLayout]
var runs: Array = []


func before_all() -> void:
	world = load(WORLD_PATH) as WorldData
	for s in SEEDS:
		var per_diff: Array = []
		for d in DIFFS:
			per_diff.append(UnderwaterGenerator.generate_run(_seed(s), world, d))
		runs.append(per_diff)


func after_all() -> void:
	# Le dossier de conteneurs est un état statique partagé : on rend la main au Far West.
	BiomeAssets.set_world(null)


func _seed(i: int) -> int:
	return 4242 + i * 7919


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


func _flood(f: FloorLayout, through_locked: bool) -> Dictionary:
	var all := f.flood_reachable(f.player_spawn, through_locked)
	for s in f.stairs:
		all.merge(f.flood_reachable(s.cell, through_locked))
	return all


func _tag(f: FloorLayout) -> String:
	return "étage %d (%dx%d)" % [f.floor_index, f.size.x, f.size.y]


## Cases occupées par un grand décor (bassin d'amarrage : 3x2 cases).
func _big_prop_cells(f: FloorLayout) -> Dictionary:
	var out := {}
	for s in f.prop_spawns:
		if s.kind == &"moon_pool":
			for y in range(s.cell.y - 1, s.cell.y + 1):
				for x in range(s.cell.x - 1, s.cell.x + 2):
					out[Vector2i(x, y)] = true
	return out


# --- Monde ---------------------------------------------------------------------------

func test_monde_charge() -> void:
	assert_not_null(world, "world_04_underwater.tres se charge")
	assert_eq(world.biome, &"underwater")
	assert_ne(world.display_name, "")
	assert_eq(world.floors_min, -2)
	assert_eq(world.floors_max, 0)
	assert_eq(world.boss_kind, &"uw_guardian")
	assert_true(ResourceLoader.exists(world.generator_path), "générateur")
	assert_true(ResourceLoader.exists(world.builder_path), "constructeur")
	assert_true(DirAccess.dir_exists_absolute(world.containers_dir), "dossier des conteneurs")
	for i: int in [0, -1, -2]:
		assert_true(world.floor_names.has(i), "nom d'étage %d" % i)
	for key: String in ["void", "floor", "wall", "extraction", "shadow"]:
		assert_true(world.palette.get(key) is Color, "couleur %s" % key)
	assert_eq(BiomeRegistry.world_path(&"underwater"), WORLD_PATH)


func test_roster_ennemis_connus() -> void:
	for type: Variant in world.enemy_roster:
		for k: Variant in (world.enemy_roster[type] as Dictionary):
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "EnemyData %s" % k)
			if StringName(k) == &"uw_guardian":
				assert_eq(StringName(type), &"boss", "le Gardien n'apparaît que dans son antre")


# --- Structure ------------------------------------------------------------------------

func test_trois_etages_meme_grille() -> void:
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		assert_eq(floors.size(), 3, "3 étages (0, -1, -2)")
		var prev := -99
		for f: FloorLayout in floors:
			assert_gt(f.floor_index, prev, "trié par floor_index")
			prev = f.floor_index
			assert_eq(f.size, (floors[0] as FloorLayout).size, "même grille")
		assert_not_null(_floor(floors, 0))
		assert_not_null(_floor(floors, -1))
		assert_not_null(_floor(floors, -2))


func test_types_de_salles() -> void:
	var boss_floors := 0
	for per_diff: Array in runs:
		for f: FloorLayout in per_diff[0]:
			var count := {}
			for r in f.rooms:
				count[r.type] = int(count.get(r.type, 0)) + 1
				assert_gt(r.tags.size(), 0, "Room.tags[0] = rôle")
			assert_lte(int(count.get(FloorLayout.ROOM_SUPER_LOOT, 0)), 1, "%s : une super_loot au plus" % _tag(f))
			match f.floor_index:
				0:
					assert_eq(int(count.get(FloorLayout.ROOM_SPAWN, 0)), 1, "un spawn à l'étage 0")
					assert_gte(f.extraction_cells.size(), 1, "extraction à l'étage 0")
				-1:
					assert_eq(int(count.get(FloorLayout.ROOM_SUPER_LOOT, 0)), 1, "salle des échantillons")
				-2:
					assert_eq(int(count.get(FloorLayout.ROOM_SUPER_LOOT, 0)), 1, "chambre forte de la fosse")
					if int(count.get(FloorLayout.ROOM_BOSS, 0)) > 0:
						boss_floors += 1
			for t: StringName in [FloorLayout.ROOM_COMBAT, FloorLayout.ROOM_CORRIDOR]:
				assert_gt(int(count.get(t, 0)), 0, "%s : salles %s" % [_tag(f), t])
	assert_gte(boss_floors, SEEDS * 8 / 10, "antre du Gardien dans la plupart des Fosses")


func test_super_loot_verrouillees_gardees_et_cle_existe() -> void:
	for f in _all_floors():
		for r in f.rooms:
			if r.type != FloorLayout.ROOM_SUPER_LOOT:
				continue
			var doors := 0
			for d in f.doors:
				if d.room_a == r.id or d.room_b == r.id:
					doors += 1
					assert_eq(d.state, FloorLayout.DoorState.LOCKED, "%s : %s verrouillée" % [_tag(f), r.name])
					assert_true(String(d.key_id).begins_with("key_uw_"), "clef préfixée du biome")
					var key := LootDB.get_item(d.key_id)
					assert_not_null(key, "objet clef %s" % d.key_id)
					if key != null:
						assert_true(key.is_key())
			assert_eq(doors, 1, "%s : %s a une seule porte" % [_tag(f), r.name])
			var guards := 0
			var chests := 0
			for e in f.enemy_spawns:
				if e.room_id == r.id:
					guards += 1
			for c in f.container_spawns:
				if c.room_id == r.id:
					chests += 1
			assert_gte(guards, 2, "%s : %s gardée" % [_tag(f), r.name])
			assert_gte(chests, 1, "%s : %s contient du butin" % [_tag(f), r.name])


func test_clefs_uniques_dans_le_run() -> void:
	for per_diff: Array in runs:
		var keys := {}
		for f: FloorLayout in per_diff[0]:
			for d in f.doors:
				if d.state == FloorLayout.DoorState.LOCKED:
					assert_false(keys.has(d.key_id), "clef %s unique" % d.key_id)
					keys[d.key_id] = true
		assert_true(keys.has(&"key_uw_lab"))
		assert_true(keys.has(&"key_uw_trench"))
	for k: StringName in KEYS:
		assert_not_null(LootDB.get_item(k), "clef %s (ItemData)" % k)


# --- Connectivité -----------------------------------------------------------------

func test_connectivite_tout_atteignable() -> void:
	for f in _all_floors():
		var reach := _flood(f, true)
		var missing := 0
		for y in f.size.y:
			for x in f.size.x:
				if FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y))) and not reach.has(Vector2i(x, y)):
					missing += 1
		assert_eq(missing, 0, "%s : cases inatteignables" % _tag(f))
		# Depuis le seul spawn joueur aussi (un étage = un réseau unique de modules).
		assert_eq(f.flood_reachable(f.player_spawn, true).size(), reach.size(), "%s : réseau unique" % _tag(f))


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


func test_modules_accessibles_par_sas_uniquement() -> void:
	for f in _all_floors():
		var orphan := 0
		var bad := 0
		for y in f.size.y:
			for x in f.size.x:
				var a := Vector2i(x, y)
				var ta := f.get_tile(a)
				if not FloorLayout.is_walkable_tile(ta) or ta == T.DOOR:
					continue
				var ra := f.room_at(a)
				if ra == null:
					orphan += 1
					continue
				for d: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					var b := a + d
					var tb := f.get_tile(b)
					if not FloorLayout.is_walkable_tile(tb) or tb == T.DOOR:
						continue
					var rb := f.room_at(b)
					if rb != null and rb.id != ra.id and not (ra.type == FloorLayout.ROOM_CORRIDOR and rb.type == FloorLayout.ROOM_CORRIDOR):
						bad += 1
		assert_eq(orphan, 0, "%s : cases hors salle" % _tag(f))
		assert_eq(bad, 0, "%s : module ouvert sans sas" % _tag(f))


func test_portes_entre_deux_cases_marchables() -> void:
	for f in _all_floors():
		for d in f.doors:
			var n1 := d.cell + (Vector2i.LEFT if d.vertical else Vector2i.UP)
			var n2 := d.cell + (Vector2i.RIGHT if d.vertical else Vector2i.DOWN)
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(n1)) and FloorLayout.is_walkable_tile(f.get_tile(n2)), "%s : sas %s traversable" % [_tag(f), d.cell])
			assert_ne(d.room_a, -1)
			assert_ne(d.room_b, -1)


func test_decors_ne_bloquent_pas() -> void:
	for f in _all_floors():
		var blocked := _big_prop_cells(f)
		for l: Array in [f.prop_spawns, f.container_spawns, f.hiding_spot_spawns]:
			for s: FloorLayout.Spawn in l:
				# Emprise complète (mobilier de plusieurs cases posé par les gabarits).
				for q in FloorLayout.spawn_cells(s):
					blocked[q] = true
		var seen := {f.player_spawn: true}
		var stack: Array[Vector2i] = [f.player_spawn]
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
		assert_eq(missing, 0, "%s : passage coupé par un décor" % _tag(f))


# --- Étages et escaliers -------------------------------------------------------------

func test_escaliers_coherents() -> void:
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		for f: FloorLayout in floors:
			if f.floor_index > -2:
				assert_gt(f.stairs.filter(func(s: FloorLayout.Stairs) -> bool: return not s.up).size(), 0, "%s : descente" % _tag(f))
			if f.floor_index < 0:
				assert_gt(f.stairs.filter(func(s: FloorLayout.Stairs) -> bool: return s.up).size(), 0, "%s : montée" % _tag(f))
			for s in f.stairs:
				assert_eq(f.get_tile(s.cell), T.STAIRS_UP if s.up else T.STAIRS_DOWN, "tuile d'escalier")
				assert_eq(s.target_floor, f.floor_index + (1 if s.up else -1))
				assert_eq(s.target_cell, s.cell, "mêmes coordonnées")
				# Case d'arrivée praticable (Raid._arrival_offset).
				var free := 0
				for d: Vector2i in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]:
					if f.get_tile(s.cell + d) == T.FLOOR:
						free += 1
				assert_gt(free, 0, "%s : arrivée libre près de %s" % [_tag(f), s.cell])
				var other := _floor(floors, s.target_floor)
				assert_not_null(other, "étage cible %d" % s.target_floor)
				if other == null:
					continue
				var back: FloorLayout.Stairs = null
				for s2 in other.stairs:
					if s2.cell == s.target_cell:
						back = s2
				assert_not_null(back, "escalier retour")
				if back:
					assert_eq(back.target_floor, f.floor_index)
					assert_ne(back.up, s.up)


# --- Spawns -------------------------------------------------------------------------

func test_spawns_valides() -> void:
	for f in _all_floors():
		var stairs := {}
		for s in f.stairs:
			stairs[s.cell] = true
		var occupied := _big_prop_cells(f)
		for s0 in f.prop_spawns:
			if s0.kind == &"moon_pool":
				occupied.erase(s0.cell)
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
		assert_eq(f.get_tile(f.player_spawn), T.FLOOR, "spawn joueur praticable")
		for e in f.extraction_cells:
			assert_eq(f.get_tile(e), T.FLOOR, "extraction praticable")


func test_spawn_dans_le_bassin_et_extraction_loin() -> void:
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		var r := g.room_at(g.player_spawn)
		assert_not_null(r)
		if r:
			assert_eq(r.type, FloorLayout.ROOM_SPAWN, "spawn dans le bassin d'amarrage")
			assert_eq(r.tags[0], "moon_pool")
		var pools := g.prop_spawns.filter(func(s: FloorLayout.Spawn) -> bool: return s.kind == &"moon_pool")
		assert_eq(pools.size(), 1, "un bassin d'amarrage")
		for e in g.extraction_cells:
			assert_gt(absi(e.x - g.player_spawn.x) + absi(e.y - g.player_spawn.y), g.size.x / 3, "extraction loin du spawn")
		var er := g.room_at(g.extraction_cells[0])
		assert_eq(er.type, FloorLayout.ROOM_EXTRACTION)


func test_ennemis_kinds_et_boss() -> void:
	for f in _all_floors():
		var boss := 0
		for e in f.enemy_spawns:
			assert_true(ENEMY_KINDS.has(e.kind), "kind %s du biome" % e.kind)
			if e.kind == &"uw_guardian":
				boss += 1
				assert_eq(f.get_room(e.room_id).type, FloorLayout.ROOM_BOSS, "Gardien dans son antre")
		var has_boss_room := f.rooms.any(func(r: FloorLayout.Room) -> bool: return r.type == FloorLayout.ROOM_BOSS)
		assert_eq(boss, 1 if has_boss_room else 0, "%s : un seul Gardien" % _tag(f))
		for c in f.container_spawns:
			assert_true(world.container_kinds.has(c.kind), "conteneur %s du biome" % c.kind)
		for h in f.hiding_spot_spawns:
			assert_true(HIDE_KINDS.has(h.kind), "cachette %s du biome" % h.kind)
		for p in f.prop_spawns:
			assert_true(world.prop_kinds.has(p.kind), "décor %s du biome" % p.kind)


func test_ennemis_croissent_avec_difficulte() -> void:
	for per_diff: Array in runs:
		var counts: Array[int] = []
		for floors: Array in per_diff:
			var n := 0
			for f: FloorLayout in floors:
				n += f.enemy_spawns.size()
			counts.append(n)
		for d in range(1, DIFFS):
			assert_gte(counts[d], counts[d - 1], "ennemis non décroissants : %s" % [counts])
		assert_gt(counts[DIFFS - 1], counts[0], "Cauchemar > Facile : %s" % [counts])


func test_cachettes_par_etage() -> void:
	for f in _all_floors():
		assert_gte(f.hiding_spot_spawns.size(), 2, "%s : cachettes" % _tag(f))


# --- Déterminisme et performances ------------------------------------------------------

func _sig(f: FloorLayout) -> String:
	var parts: PackedStringArray = []
	for d in f.doors:
		parts.append("D%s%d%s" % [d.cell, d.state, d.key_id])
	for l: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns, f.hiding_spot_spawns]:
		for s: FloorLayout.Spawn in l:
			parts.append("%s%s%d" % [s.cell, s.kind, s.room_id])
	for st in f.stairs:
		parts.append("S%s%s" % [st.cell, st.up])
	parts.append(str(f.player_spawn))
	parts.append(str(f.extraction_cells))
	return ";".join(parts)


func test_determinisme() -> void:
	for s in 5:
		var a := UnderwaterGenerator.generate_run(_seed(s), world, 2)
		var b := UnderwaterGenerator.generate_run(_seed(s), world, 2)
		assert_eq(a.size(), b.size())
		for i in a.size():
			assert_eq(a[i].tiles, b[i].tiles, "tuiles identiques")
			assert_eq(_sig(a[i]), _sig(b[i]), "spawns/portes identiques")
		for idx: int in [0, -1, -2]:
			var single := UnderwaterGenerator.generate_floor(_seed(s), world, 2, idx)
			var ref := UnderwaterGenerator.find_floor(a, idx)
			assert_eq(single.tiles, ref.tiles, "generate_floor(%d) == generate_run" % idx)
			assert_eq(_sig(single), _sig(ref))
	assert_null(UnderwaterGenerator.generate_floor(_seed(0), world, 2, 1), "pas d'étage 1")
	var c := UnderwaterGenerator.generate_floor(_seed(0), world, 2, 0)
	var d2 := UnderwaterGenerator.generate_floor(_seed(1), world, 2, 0)
	assert_ne(c.tiles, d2.tiles, "seeds différentes → cartes différentes")


func test_performances() -> void:
	var worst := 0.0
	for s in 8:
		for idx: int in [0, -1, -2]:
			var t0 := Time.get_ticks_usec()
			UnderwaterGenerator.generate_floor(_seed(s), world, 4, idx)
			worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	# generate_floor(-2) refait la structure des étages 0 et -1 (escaliers) : on borne
	# donc le coût moyen par étage construit.
	gut.p("Pire generate_floor : %.1f ms" % worst)
	assert_lt(worst, MAX_MS_PER_FLOOR * 1.5, "génération d'un étage (structures amont comprises)")
	var t1 := Time.get_ticks_usec()
	for s2 in 8:
		UnderwaterGenerator.generate_run(_seed(s2), world, 4)
	var per_floor := (Time.get_ticks_usec() - t1) / 1000.0 / 24.0
	gut.p("Moyenne par étage (generate_run) : %.1f ms" % per_floor)
	assert_lt(per_floor, MAX_MS_PER_FLOOR, "< 50 ms par étage")


# --- Constructeur de décor ----------------------------------------------------------

func test_constructeur_api_et_contenu() -> void:
	var floors: Array = runs[0][2]
	for f: FloorLayout in floors:
		var t0 := Time.get_ticks_usec()
		var root := UnderwaterBuilder.build(f, world)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		gut.p("Construction de l'étage %d : %.1f ms" % [f.floor_index, ms])
		add_child_autofree(root)
		assert_true(root is Node2D)
		assert_true(root.y_sort_enabled, "racine triée en Y")
		for m: String in ["get_doors", "get_stairs_areas", "get_room_at_world", "set_stairs_cooldown"]:
			assert_true(root.has_method(m), "méthode %s" % m)
		assert_true(root.has_signal("stairs_entered"))
		var doors := root.get_doors()
		assert_eq(doors.size(), f.doors.size(), "un sas par porte")
		var locked := 0
		for d: DoorNode in doors:
			assert_true(d is UnderwaterDoor, "porte dessinée par le biome")
			assert_true(d.is_in_group(&"doors"))
			assert_eq(d.position, Vector2((d.cell.x + 0.5) * 64.0, (d.cell.y + 1.0) * 64.0))
			if d.is_locked():
				locked += 1
				assert_true(String(d.key_id).begins_with("key_uw_"))
		assert_eq(locked, 1 if f.floor_index < 0 else 0, "porte verrouillée de la salle super_loot")
		var areas := root.get_stairs_areas()
		assert_eq(areas.size(), f.stairs.size(), "une zone par escalier")
		for a: Area2D in areas:
			assert_true(a.has_meta(&"stairs"))
			assert_true(a.get_meta(&"stairs") is FloorLayout.Stairs)
		var body := root.get_wall_body()
		assert_eq(body.collision_layer, 1, "murs sur la couche world")
		var solid := 0
		for t: int in f.tiles:
			if FloorLayout.is_opaque_tile(t):
				solid += 1
		assert_lt(body.get_child_count(), solid / 4, "collisions fusionnées")
		assert_eq(root.get_props().size(), f.prop_spawns.size(), "un décor par spawn")
		for p: UnderwaterProp in root.get_props():
			assert_false(p.is_placeholder, "décor %s présent dans l'atlas" % p.kind)
		var r := root.get_room_at_world(FloorLayout.cell_to_world(f.player_spawn))
		assert_not_null(r, "salle au spawn")
		assert_lt(ms, 250.0, "construction rapide")
		root.set_stairs_cooldown(0.5)


func test_murs_couvrent_les_cases_solides() -> void:
	var f: FloorLayout = _floor(runs[1][1], 0)
	var root := UnderwaterBuilder.build(f, world)
	add_child_autofree(root)
	await wait_physics_frames(2)
	var space := root.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = 1
	var checked := 0
	for y in range(0, f.size.y, 3):
		for x in range(0, f.size.x, 3):
			var c := Vector2i(x, y)
			var t := f.get_tile(c)
			q.position = FloorLayout.cell_to_world(c)
			if t == T.WALL:
				assert_gt(space.intersect_point(q).size(), 0, "case %s solide" % c)
				checked += 1
	assert_gt(checked, 20)


func test_tous_les_decors_dans_l_atlas() -> void:
	for k: StringName in world.prop_kinds:
		assert_true(UnderwaterProp.is_known_kind(k), "décor %s (DEFS + atlas)" % k)
	for piece: String in ["kit_ladder_up", "kit_hatch_down", "kit_pod", "kit_beacon", "kit_wall_lamp", "kit_wall_alarm", "kit_wall_coral", "glow", "decal_shaft"]:
		assert_true(UnderwaterProp.has_piece(piece), "pièce %s" % piece)


# --- Ennemis ------------------------------------------------------------------------

func test_ennemis_data_et_visuels() -> void:
	var extra := BiomeRegistry.extra_enemy_kinds()
	for k: StringName in ENEMY_KINDS:
		var d := load("res://data/enemies/%s.tres" % k) as EnemyData
		assert_not_null(d, "%s.tres" % k)
		if d == null:
			continue
		assert_eq(d.kind, k)
		assert_gt(d.max_hp, 0.0)
		assert_gt(d.hearing_radius, 0.0, "discrétion : ouïe")
		assert_gt(d.sight_gain, 0.0, "discrétion : vue")
		assert_gt(d.awareness_decay, 0.0)
		assert_true(extra.has(k), "BiomeRegistry charge le visuel %s" % k)
		var v := EnemyVisual.new()
		add_child_autofree(v)
		v.setup(k)
		assert_eq(v.kind, k, "%s : setup sans repli" % k)
		var sprite := v.get_node("Body/Sprite") as Sprite2D
		assert_not_null(sprite.texture, "%s : texture" % k)
		assert_lt(v.get_head_offset().y, -30.0)
		v.play_alert()
		v.play_attack_windup(0.3)
	assert_true((load("res://data/enemies/uw_mutant.tres") as EnemyData).is_ranged(), "scientifique muté : distance")
	assert_true((load("res://data/enemies/uw_heavy.tres") as EnemyData).is_area_attack(), "scaphandre : coup de zone")
	assert_true((load("res://data/enemies/uw_guardian.tres") as EnemyData).is_area_attack(), "Gardien : coup de zone")
	assert_gt((load("res://data/enemies/uw_eel.tres") as EnemyData).move_speed, 200.0, "anguille rapide")


# --- Butin --------------------------------------------------------------------------

func test_conteneurs_tables_et_sprites() -> void:
	BiomeAssets.set_world(world)
	for k: StringName in world.container_kinds:
		var t := LootDB.get_table(k)
		assert_not_null(t, "table %s" % k)
		if t != null:
			assert_false(t.entries.is_empty())
			for id: Variant in t.entries:
				assert_true(LootDB.has_item(StringName(id)), "%s : objet %s" % [k, id])
		for open: bool in [false, true]:
			var p := BiomeAssets.find_sprite(String(k) + ("_open" if open else ""))
			assert_true(p.begins_with(world.containers_dir), "sprite %s (ouvert=%s) dans le dossier du biome" % [k, open])
			assert_true(ResourceLoader.exists(p))
	for h: StringName in HIDE_KINDS:
		assert_true(HidingSpot.DEFS.has(h), "cachette %s connue de HidingSpot" % h)
		assert_true(ResourceLoader.exists(world.containers_dir + "hide_%s.png" % h), "sprite de cachette %s" % h)
		assert_not_null(HidingSpot.get_texture(h))
	BiomeAssets.set_world(null)


func test_objets_du_biome() -> void:
	var n := 0
	for it: ItemData in LootDB.all_items():
		var id := String(it.id)
		if not (id.begins_with("uw_") or id.begins_with("key_uw_")):
			continue
		n += 1
		assert_not_null(it.icon, "%s : icône" % id)
		assert_ne(it.display_name, "")
		assert_between(it.rarity, 0, 4)
	assert_between(n, 10, 16, "10 à 15 objets propres au biome (+ clefs)")
	assert_true(LootDB.get_item(&"uw_oxygen_tank").is_usable(), "bouteille d'oxygène utilisable")



# --- Aménagement par gabarits (mobilier, cloisons, décors muraux) -------------------------

const FurnishChecks := preload("res://tests/furnish_checks.gd")


func test_amenagement_conteneurs_accessibles_et_abords_libres() -> void:
	for f in _all_floors():
		var starts: Array[Vector2i] = [f.player_spawn]
		var bad := FurnishChecks.containers_reachable(f, starts, _big_prop_cells(f))
		bad.append_array(FurnishChecks.gates_clear(f, _big_prop_cells(f)))
		bad.append_array(FurnishChecks.partitions_ok(f))
		bad.append_array(FurnishChecks.wall_decor_ok(f))
		assert_eq(bad.size(), 0, "%s : %s" % [_tag(f), str(bad.slice(0, 4))])
		if not bad.is_empty():
			return


func test_amenagement_chaque_piece_recoit_son_gabarit() -> void:
	var tpl: Dictionary = preload("res://scripts/biomes/underwater/uw_templates.gd").TEMPLATES
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
	for role: StringName in [&"quarters", &"mess", &"storage", &"bio_lab", &"engine", &"workshop"]:
		assert_true(seen.has(role), "gabarit %s utilisé" % role)


func test_amenagement_murs_libres_pour_tourelles() -> void:
	var worst := 0.0
	for f in _all_floors():
		worst = maxf(worst, FurnishChecks.wall_decor_ratio(f))
	gut.p("Part maximale des faces de murs décorées : %.2f" % worst)
	assert_lt(worst, 0.5, "la majorité des murs reste libre")


func test_amenagement_deterministe() -> void:
	for s in 3:
		var a: Array = UnderwaterGenerator.generate_run(_seed(s), world, 2)
		var b: Array = UnderwaterGenerator.generate_run(_seed(s), world, 2)
		assert_eq(a.size(), b.size())
		for i in a.size():
			assert_eq(FurnishChecks.signature(a[i]), FurnishChecks.signature(b[i]), "aménagement identique (seed %d)" % s)
