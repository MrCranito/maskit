extends GutTest
## Biome « Les Pyramides d'Égypte » (world_06_egypt_pyramids) : monde, générateur (16 seeds ×
## 5 difficultés), connectivité, trésor verrouillé, sanctuaire du boss, constructeur de décor,
## conteneurs et objets du biome, paquets pré-rendus (assets/prerender/egypt_pyramids/<seed>/).

const WORLD_PATH := "res://data/worlds/world_06_egypt_pyramids.tres"
const SEEDS := 16
const DIFFS := 5
const MAX_MS_PER_FLOOR := 50.0
const T := FloorLayout.Tile
const KEY := &"key_eg_treasury"
const Pop := preload("res://scripts/biomes/egypt_pyramids/eg_populator.gd")
const Plan := preload("res://scripts/biomes/egypt_pyramids/eg_plan.gd")

var world: WorldData
var runs: Array = []


func before_all() -> void:
	world = load(WORLD_PATH) as WorldData
	for s in SEEDS:
		var per: Array = []
		for d in DIFFS:
			per.append(EgyptGenerator.generate_run(_seed(s), world, d))
		runs.append(per)


func _seed(i: int) -> int:
	return 7001 + i * 4409


func _grounds() -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	for per: Array in runs:
		out.append(per[1][0])
	return out


func _all_floors() -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	for per: Array in runs:
		for floors: Array in per:
			for f: FloorLayout in floors:
				out.append(f)
	return out


func _rooms_role(f: FloorLayout, role: String) -> Array[FloorLayout.Room]:
	var out: Array[FloorLayout.Room] = []
	for r in f.rooms:
		if r.tags.size() > 0 and r.tags[0] == role:
			out.append(r)
	return out


# --- Monde ------------------------------------------------------------------------

func test_monde_charge() -> void:
	assert_not_null(world)
	assert_eq(world.biome, &"egypt_pyramids")
	assert_eq(world.display_name, "Les Pyramides d'Égypte")
	assert_true(ResourceLoader.exists(world.generator_path), "générateur")
	assert_true(ResourceLoader.exists(world.builder_path), "constructeur")
	assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % world.boss_kind), "boss du monde")
	for e: StringName in world.elite_kinds:
		assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % e), "élite %s" % e)
	assert_eq(world.floors_min, 0)
	assert_eq(world.floors_max, 0)
	assert_true(world.floor_names.has(0))
	assert_eq(BiomeRegistry.world_path(&"egypt_pyramids"), WORLD_PATH)
	for rt: Variant in world.enemy_roster:
		for k: Variant in world.enemy_roster[rt]:
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % k), "roster %s : %s" % [rt, k])
	for role: Variant in Pop.ROLE_ROSTER:
		for k2: Variant in Pop.ROLE_ROSTER[role]:
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % k2), "roster de rôle %s : %s" % [role, k2])


func test_carte_et_vignette() -> void:
	var card := load("res://data/maps/perm_pyramides_egypte.tres") as MapCard
	assert_not_null(card)
	assert_eq(card.id, &"perm_pyramides_egypte")
	assert_eq(card.world_path, WORLD_PATH)
	assert_eq(card.category, MapCard.CATEGORY_PERMANENT)
	assert_true(ResourceLoader.exists("res://assets/ui/maps/egypt_pyramids.png"), "vignette du biome")


# --- Structure (plan façon maquette) ----------------------------------------------------

func test_composition_de_la_surface() -> void:
	for f in _grounds():
		assert_eq(f.floor_index, 0)
		assert_eq(f.size, Vector2i(Plan.W, Plan.H), "plan portrait")
		assert_eq(_rooms_role(f, "sanctuary").size(), 1, "sanctuaire")
		assert_eq(_rooms_role(f, "treasury").size(), 1, "chambre du trésor")
		assert_eq(_rooms_role(f, "hypostyle").size(), 1, "salle hypostyle")
		assert_eq(_rooms_role(f, "court").size(), 4, "4 pavillons d'angle à cour")
		assert_eq(_rooms_role(f, "inner_court").size(), 1, "cour à piliers du grand temple")
		assert_gte(_rooms_role(f, "gate").size(), 6, "portails (couloirs de 2 cases)")
		var av := _rooms_role(f, "avenue")
		assert_eq(av.size(), 1, "avenue des sphinx")
		if av.size() == 1:
			assert_true(av[0].rect.has_point(f.player_spawn), "arrivée sur l'avenue")
			assert_eq(av[0].type, FloorLayout.ROOM_SPAWN)
		var sanct := _rooms_role(f, "sanctuary")[0]
		assert_eq(sanct.type, FloorLayout.ROOM_BOSS, "sanctuaire = salle du boss")
		assert_true(Plan.SANCTUARY.grow(-1).encloses(sanct.rect), "sanctuaire au cœur du grand temple")
		var kinds := {}
		for lm: Dictionary in f.landmarks:
			kinds[String(lm["kind"])] = int(kinds.get(String(lm["kind"]), 0)) + 1
		assert_eq(int(kinds.get("pyramid_big", 0)), 3, "3 grandes pyramides")
		assert_eq(int(kinds.get("pyramid_small", 0)), 3, "3 petites pyramides")
		assert_eq(int(kinds.get("sphinx", 0)), 2, "2 sphinx")
		assert_gte(int(kinds.get("obelisk", 0)), 4, "obélisques")
		assert_gte(int(kinds.get("palm", 0)), 8, "palmiers")
		var chambers := 0
		for r in f.rooms:
			if not r.outdoor:
				chambers += 1
		assert_gte(chambers, 30, "chambres des temples")
		# Plan en croix : temple nord et porte-pylône accolés au grand temple ; ailes et pavillons
		# détachés par des passages de sable.
		for r0: Rect2i in [Plan.NORTH, Plan.GATEHOUSE]:
			assert_true(r0.intersects(Plan.ENCLOSURE), "accolé au grand temple : %s" % r0)
		for r1: Rect2i in [Plan.WING_W, Plan.WING_E]:
			assert_false(r1.grow(1).intersects(Plan.ENCLOSURE), "aile détachée : %s" % r1)
		assert_gte(Plan.SANCTUARY.size.x, 12, "grand sanctuaire")
		assert_gte(f.extraction_cells.size(), 4, "extraction (campement + dunes)")
		var c: Dictionary = f.get_meta(&"render_contract", {})
		assert_true(c.has("modules") and c.has("columns") and c.has("torches") and c.has("landmarks"), "contrat de rendu")
		var types := {}
		for r2 in f.rooms:
			types[r2.type] = true
		for t: StringName in [FloorLayout.ROOM_SPAWN, FloorLayout.ROOM_COMBAT, FloorLayout.ROOM_LOOT, FloorLayout.ROOM_TRAP,
				FloorLayout.ROOM_REST, FloorLayout.ROOM_SUPER_LOOT, FloorLayout.ROOM_BOSS, FloorLayout.ROOM_EXTRACTION, FloorLayout.ROOM_CORRIDOR]:
			assert_true(types.has(t), "type %s présent" % t)


func test_structure_independante_de_la_difficulte() -> void:
	for i in 4:
		var a := EgyptGenerator.generate_floor(_seed(i), world, 0, 0)
		var b := EgyptGenerator.generate_floor(_seed(i), world, 4, 0)
		assert_eq(PrerenderBackdrop.layout_md5(a), PrerenderBackdrop.layout_md5(b), "seed %d" % _seed(i))
		assert_eq(a.doors.size(), b.doors.size())


# --- Connectivité, trésor, boss -----------------------------------------------------------

func test_connectivite_tout_atteignable() -> void:
	for f in _all_floors():
		var reach := f.flood_reachable(f.player_spawn, true)
		var missing := 0
		for y in f.size.y:
			for x in f.size.x:
				if FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y))) and not reach.has(Vector2i(x, y)):
					missing += 1
		assert_eq(missing, 0, "cases inatteignables")


func test_tresor_verrouille_garde_et_inatteignable_sans_clef() -> void:
	for f in _grounds():
		var reach := f.flood_reachable(f.player_spawn, false)
		for r in f.rooms:
			if r.type != FloorLayout.ROOM_SUPER_LOOT:
				continue
			var locked := 0
			for d in f.doors:
				if d.room_a == r.id or d.room_b == r.id:
					assert_eq(d.state, FloorLayout.DoorState.LOCKED, "%s verrouillée" % r.name)
					assert_eq(d.key_id, KEY)
					assert_true(LootDB.has_item(d.key_id), "clef existe comme objet")
					locked += 1
			assert_eq(locked, 1, "une seule porte scellée")
			var guards := 0
			var chests := 0
			for e in f.enemy_spawns:
				if e.room_id == r.id:
					guards += 1
			for c in f.container_spawns:
				if c.room_id == r.id:
					chests += 1
					assert_eq(c.kind, &"eg_gold_chest", "coffres dorés au trésor")
			assert_gte(guards, 2, "trésor gardé")
			assert_gte(chests, 1, "trésor avec coffres")
			for y in range(r.rect.position.y, r.rect.end.y):
				for x in range(r.rect.position.x, r.rect.end.x):
					assert_false(reach.has(Vector2i(x, y)), "trésor atteignable sans clef")
	var key := LootDB.get_item(KEY)
	assert_not_null(key)
	if key != null:
		assert_true(key.is_key())


func test_boss_unique_dans_le_sanctuaire() -> void:
	for per: Array in runs:
		for d in DIFFS:
			var bosses := 0
			for f: FloorLayout in per[d]:
				for e in f.enemy_spawns:
					if e.kind == world.boss_kind:
						bosses += 1
						assert_eq(f.get_room(e.room_id).type, FloorLayout.ROOM_BOSS, "boss dans le sanctuaire")
			assert_eq(bosses, 1, "un seul boss généré")


func test_portes_visibles_camera_inclinee() -> void:
	# Chambres à toit (toit rendu incliné vers le nord) : aucune porte dans leur mur nord.
	for f in _grounds():
		var bad: Array = []
		for d in f.doors:
			if d.vertical:
				continue
			var south := f.room_at(d.cell + Vector2i.DOWN)
			if south != null and south.building_id >= 0 and d.cell.y == f.buildings[south.building_id].rect.position.y:
				bad.append(d.cell)
		assert_eq(bad, [], "porte dans le mur nord d'une chambre à toit")


# --- Spawns ------------------------------------------------------------------------------

func test_spawns_valides() -> void:
	var bad: Array[String] = []
	for f in _all_floors():
		if not FloorLayout.is_walkable_tile(f.get_tile(f.player_spawn)):
			bad.append("spawn joueur")
		for e in f.extraction_cells:
			if f.get_tile(e) != T.STREET and f.get_tile(e) != T.FLOOR:
				bad.append("extraction %s" % e)
		var used := {}
		for list: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns, f.hiding_spot_spawns]:
			for sp: FloorLayout.Spawn in list:
				var t := f.get_tile(sp.cell)
				if t != T.FLOOR and t != T.STREET:
					bad.append("%s hors sol praticable" % sp.kind)
				if used.has(sp.cell):
					bad.append("deux choses en %s" % sp.cell)
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
			if absi(e2.cell.x - f.player_spawn.x) + absi(e2.cell.y - f.player_spawn.y) < 8:
				bad.append("ennemi trop près de l'arrivée %s" % e2.cell)
	assert_eq(bad.size(), 0, "spawns invalides : %s" % str(bad.slice(0, 5)))


func test_decors_ne_bloquent_pas() -> void:
	for f in _all_floors():
		var blocked := {}
		for s in f.prop_spawns:
			for q in Pop.spawn_footprint(s):
				blocked[q] = true
		for list: Array in [f.container_spawns, f.hiding_spot_spawns]:
			for s2: FloorLayout.Spawn in list:
				blocked[s2.cell] = true
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
		assert_eq(missing, 0, "passage coupé")
		# Chaque conteneur / cachette garde un voisin praticable.
		for list2: Array in [f.container_spawns, f.hiding_spot_spawns]:
			for s3: FloorLayout.Spawn in list2:
				var ok := false
				for d2: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if seen.has(s3.cell + d2):
						ok = true
				assert_true(ok, "%s accessible en %s" % [s3.kind, s3.cell])


func test_cachettes_et_conteneurs_presents() -> void:
	for f in _all_floors():
		assert_gte(f.hiding_spot_spawns.size(), 4, "cachettes")
		assert_gte(f.container_spawns.size(), 20, "conteneurs")


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
	var a := EgyptGenerator.generate_run(777, world, 2)
	var b := EgyptGenerator.generate_run(777, world, 2)
	assert_eq(a.size(), 1)
	assert_eq(a[0].tiles, b[0].tiles, "mêmes tuiles")
	assert_eq(a[0].doors.size(), b[0].doors.size())
	assert_eq(a[0].enemy_spawns.size(), b[0].enemy_spawns.size())
	for j in a[0].container_spawns.size():
		assert_eq(a[0].container_spawns[j].cell, b[0].container_spawns[j].cell)
		assert_eq(a[0].container_spawns[j].kind, b[0].container_spawns[j].kind)
	for j2 in a[0].prop_spawns.size():
		assert_eq(a[0].prop_spawns[j2].cell, b[0].prop_spawns[j2].cell)
	assert_null(EgyptGenerator.generate_floor(777, world, 2, 1))


func test_performance() -> void:
	var t0 := Time.get_ticks_usec()
	var n := 0
	for s in 6:
		n += EgyptGenerator.generate_run(90000 + s, world, 4).size()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	assert_lt(ms, MAX_MS_PER_FLOOR, "génération : %.1f ms par étage" % ms)


# --- Décor ------------------------------------------------------------------------------

func test_construction() -> void:
	var f := EgyptGenerator.generate_run(31337, world, 2)[0]
	BiomeAssets.set_world(world)
	var root := EgyptBuilder.build(f, world)
	add_child_autofree(root)
	assert_true(root.y_sort_enabled)
	assert_true(root.has_signal("stairs_entered"))
	for m: String in ["get_doors", "get_stairs_areas", "get_room_at_world", "set_stairs_cooldown", "get_roofs", "prerender_hide"]:
		assert_true(root.has_method(m), m)
	assert_eq(root.get_doors().size(), f.doors.size(), "une porte par layout.doors")
	for d: DoorNode in root.get_doors():
		assert_true(d.is_in_group(&"doors"))
		assert_eq(d.is_locked(), f.get_door_at(d.cell).state == FloorLayout.DoorState.LOCKED)
	assert_eq(root.get_stairs_areas().size(), 0, "pas d'escalier en surface")
	assert_eq(root.get_props().size(), f.prop_spawns.size(), "un décor par spawn")
	assert_eq(root.get_roofs().size(), f.buildings.size(), "un toit par chambre")
	for r: Node in root.get_roofs():
		assert_true(String(r.name).begins_with("Roof_"))
	var body := root.get_wall_body()
	assert_eq(body.collision_layer, 1, "murs sur la couche world")
	var solid := 0
	for t: int in f.tiles:
		if FloorLayout.is_opaque_tile(t):
			solid += 1
	assert_lt(body.get_child_count(), solid / 4, "collisions fusionnées")
	assert_not_null(root.get_room_at_world(FloorLayout.cell_to_world(f.player_spawn)), "salle au spawn")
	root.set_stairs_cooldown(0.4)
	BiomeAssets.set_world(null)


func test_conteneurs_du_biome_gardent_leur_kind() -> void:
	var g := EgyptGenerator.generate_run(2024, world, 1)[0]
	BiomeAssets.set_world(world)
	var root := EgyptBuilder.build(g, world)
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
			assert_true(String((ch as HidingSpot).kind).begins_with("eg_"), "cachette du biome")
	assert_eq(n, g.container_spawns.size())
	BiomeAssets.set_world(null)


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
	var hides := {}
	for d: Dictionary in Pop.HIDING.values():
		for kk: Variant in d:
			hides[kk] = true
	for h: Variant in hides:
		assert_true(ResourceLoader.exists(world.containers_dir + "hide_" + String(h) + ".png"), "cachette %s" % h)
	assert_not_null(LootDB.get_table(&"enemy_egypt_pyramids"), "table de butin des ennemis du biome")
	BiomeAssets.set_world(null)


func test_objets_du_biome() -> void:
	var n := 0
	for it: ItemData in LootDB.all_items():
		if String(it.id).begins_with("eg_"):
			n += 1
			assert_not_null(it.icon, "icône %s" % it.id)
	assert_between(n, 10, 20, "10 à 20 objets propres au biome")


func test_decors_dans_l_atlas() -> void:
	var Prop := load("res://scripts/biomes/egypt_pyramids/eg_prop.gd")
	for k: StringName in world.prop_kinds:
		assert_true(Prop.has_piece("prop_" + String(k)), "pièce prop_%s" % k)


# --- Paquets pré-rendus -------------------------------------------------------------------

func _packs() -> PackedInt32Array:
	return PrerenderBackdrop.available_seeds(&"egypt_pyramids")


func _meta(s: int) -> Dictionary:
	var fa := FileAccess.open(PrerenderBackdrop.pack_root(&"egypt_pyramids") + str(s) + "/map.json", FileAccess.READ)
	return JSON.parse_string(fa.get_as_text()) if fa != null else {}


func test_paquets_correspondent_au_plan() -> void:
	var seeds := _packs()
	assert_gt(seeds.size(), 0, "au moins une carte des pyramides pré-rendue")
	for s in seeds:
		var m := _meta(s)
		var L := EgyptGenerator.generate_floor(s, world, 1, 0)
		assert_eq(String(m.get("tiles_md5", "")), PrerenderBackdrop.layout_md5(L), "seed %d : empreinte du plan" % s)
		assert_gte(int(m.get("ppc", 0)), 72, "seed %d : résolution ≥ 72 px/case" % s)
		assert_eq(int(m.get("tilt_deg", 0)), 38)
		assert_eq((m.get("interiors", []) as Array).size(), L.buildings.size(), "un intérieur par chambre à toit")
		assert_true(m.has("collision") and m.has("occluders"), "collisions et occultation")
		var dir := PrerenderBackdrop.pack_root(&"egypt_pyramids") + str(s) + "/"
		for t: Dictionary in m["tiles"]:
			assert_true(ResourceLoader.exists(dir + String(t["file"])), "tuile %s" % t["file"])
		assert_true(ResourceLoader.exists(dir + "minimap.webp"), "mini-carte")
		assert_true(ResourceLoader.exists(dir + "footprint.png"), "emprise")
		assert_lt(int((m.get("collision_stats", {}) as Dictionary).get("unblocked_cells", 0)), 60, "rendu cohérent avec le plan")
		var b := PrerenderBackdrop.create(s, L, &"egypt_pyramids")
		assert_not_null(b, "fond accepté par le jeu")
		if b != null:
			b.free()


func test_paquets_collisions_gardent_les_passages() -> void:
	for s in _packs():
		var m := _meta(s)
		var L := EgyptGenerator.generate_floor(s, world, 1, 0)
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


func test_tourelles_sur_murs_visibles() -> void:
	var placer: Script = load("res://scripts/dungeon/turret_placer.gd")
	for f in _grounds().slice(0, 4):
		var spots: Array = placer.call("find_spots", f, 1234, 2, 0, "world_06_egypt_pyramids")
		for sp: Dictionary in spots:
			var c: Vector2i = sp["cell"]
			var n: Vector2i = sp["normal"]
			assert_eq(f.get_tile(c), T.WALL, "tourelle sur un mur")
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(c + n)), "face à une case praticable")
