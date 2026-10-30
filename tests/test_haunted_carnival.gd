extends GutTest
## Biome « Carnaval hanté » : monde, générateur (12 seeds × 5 difficultés), constructeur de décor,
## conteneurs et butin, paquets pré-rendus (assets/prerender/haunted_carnival/<seed>/).

const WORLD_PATH := "res://data/worlds/world_04_haunted_carnival.tres"
const SEEDS := 12
const DIFFS := 5
const MAX_MS_PER_FLOOR := 50.0
const T := FloorLayout.Tile
const KEYS := [&"key_hc_director"]
const Pop := preload("res://scripts/biomes/haunted_carnival/hc_populator.gd")
const Plan := preload("res://scripts/biomes/haunted_carnival/hc_plan.gd")
const Builder := preload("res://scripts/biomes/haunted_carnival/hc_builder.gd")

var world: WorldData
var runs: Array = []


func before_all() -> void:
	world = load(WORLD_PATH) as WorldData
	for s in SEEDS:
		var per: Array = []
		for d in DIFFS:
			per.append(HauntedCarnivalGenerator.generate_run(_seed(s), world, d))
		runs.append(per)


func _seed(i: int) -> int:
	return 2025 + i * 7001


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
	assert_eq(world.biome, &"haunted_carnival")
	assert_eq(world.display_name, "Carnaval hanté")
	assert_true(ResourceLoader.exists(world.generator_path), "générateur")
	assert_true(ResourceLoader.exists(world.builder_path), "constructeur")
	assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % world.boss_kind), "boss du monde")
	for e: StringName in world.elite_kinds:
		assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % e), "élite %s" % e)
	assert_true(world.floor_names.has(0))
	assert_eq(BiomeRegistry.world_path(&"haunted_carnival"), WORLD_PATH)
	var card := MapCard.find(&"perm_carnaval_hante")
	assert_not_null(card, "carte perm_carnaval_hante")
	if card != null:
		assert_eq(card.world_path, WORLD_PATH)
		assert_true(card.description.contains("rires"))


# --- Composition de la maquette ----------------------------------------------------

func test_composition_du_parc() -> void:
	for f in _grounds():
		assert_eq(f.size, Vector2i(Plan.W, Plan.H), "plan portrait")
		assert_eq(f.floor_index, 0)
		assert_eq(_rooms_role(f, "big_top").size(), 1, "chapiteau")
		var bt := _rooms_role(f, "big_top")[0]
		assert_eq(bt.type, FloorLayout.ROOM_BOSS, "chapiteau = salle du boss")
		assert_eq(_rooms_role(f, "entrance").size(), 1, "parvis")
		assert_true(_rooms_role(f, "entrance")[0].rect.has_point(f.player_spawn), "arrivée sur le parvis")
		assert_eq(_rooms_role(f, "wheel_yard").size(), 1, "esplanade de la grande roue")
		assert_eq(_rooms_role(f, "ride_yard").size(), 3, "trois cours de manèges")
		assert_eq(_rooms_role(f, "caravan_director").size(), 1, "roulotte du Directeur")
		var stands := 0
		var caravans := 0
		var tents := 0
		for r in f.rooms:
			if r.tags.size() > 0 and String(r.tags[0]).begins_with("stand_"):
				stands += 1
			if r.tags.size() > 0 and String(r.tags[0]).begins_with("caravan_"):
				caravans += 1
			if r.tags.size() > 0 and String(r.tags[0]).begins_with("tent_"):
				tents += 1
		assert_gte(stands, 12, "rangées de stands")
		assert_eq(caravans, 4, "roulottes")
		assert_eq(tents, 2, "tentes")
		assert_gte(f.extraction_cells.size(), 2, "extraction")
		for e in f.extraction_cells:
			assert_eq(String(f.room_at(e).tags[0]), "service_yard", "extraction aux sorties de secours")
		# Grande roue et manèges : disques murés.
		for c in Plan.disc_cells(Plan.WHEEL["c"], Plan.WHEEL["r"]):
			assert_eq(f.get_tile(c), T.WALL, "grande roue murée %s" % c)
		var ct: Dictionary = f.get_meta(&"render_contract", {})
		assert_true(ct.has("modules") and ct.has("rides") and ct.has("coaster") and ct.has("tent"), "contrat de rendu")
		assert_eq((ct["rides"] as Array).size(), 4, "grande roue + 3 manèges")


func test_types_de_salles_presents() -> void:
	for per: Array in runs:
		var types := {}
		for f: FloorLayout in per[2]:
			for r in f.rooms:
				types[r.type] = true
		for t: StringName in [FloorLayout.ROOM_SPAWN, FloorLayout.ROOM_COMBAT, FloorLayout.ROOM_LOOT, FloorLayout.ROOM_TRAP,
				FloorLayout.ROOM_REST, FloorLayout.ROOM_SUPER_LOOT, FloorLayout.ROOM_BOSS, FloorLayout.ROOM_EXTRACTION, FloorLayout.ROOM_CORRIDOR]:
			assert_true(types.has(t), "type %s présent" % t)


func test_boss_unique_dans_le_chapiteau() -> void:
	for per: Array in runs:
		for d in DIFFS:
			var bosses := 0
			for f: FloorLayout in per[d]:
				for e in f.enemy_spawns:
					if e.kind == world.boss_kind:
						bosses += 1
						assert_eq(f.get_room(e.room_id).type, FloorLayout.ROOM_BOSS, "boss dans la piste")
			assert_eq(bosses, 1, "un seul boss")


func test_super_loot_verrouillee_et_gardee() -> void:
	for f in _all_floors():
		for r in f.rooms:
			if r.type != FloorLayout.ROOM_SUPER_LOOT:
				continue
			var locked := 0
			for d in f.doors:
				if d.room_a == r.id or d.room_b == r.id:
					assert_eq(d.state, FloorLayout.DoorState.LOCKED, "%s verrouillée" % r.name)
					assert_eq(d.key_id, Plan.KEY_DIRECTOR)
					assert_true(LootDB.has_item(d.key_id), "clef %s existe" % d.key_id)
					locked += 1
			assert_gte(locked, 1)
			var guards := 0
			var chests := 0
			for e in f.enemy_spawns:
				if e.room_id == r.id:
					guards += 1
			for c in f.container_spawns:
				if c.room_id == r.id:
					chests += 1
			assert_gte(guards, 2, "%s gardée" % r.name)
			assert_gte(chests, 1, "%s a des coffres" % r.name)


# --- Connectivité -----------------------------------------------------------------------

func test_connectivite_tout_atteignable() -> void:
	for f in _all_floors():
		var reach := f.flood_reachable(f.player_spawn, true)
		var missing := 0
		for y in f.size.y:
			for x in f.size.x:
				if FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y))) and not reach.has(Vector2i(x, y)):
					missing += 1
		assert_eq(missing, 0, "cases inatteignables")


func test_super_loot_inatteignable_sans_clef() -> void:
	for f in _all_floors():
		var reach := f.flood_reachable(f.player_spawn, false)
		for r in f.rooms:
			if r.type != FloorLayout.ROOM_SUPER_LOOT:
				continue
			var leak := 0
			for y in range(r.rect.position.y, r.rect.end.y):
				for x in range(r.rect.position.x, r.rect.end.x):
					if reach.has(Vector2i(x, y)):
						leak += 1
			assert_eq(leak, 0, "%s atteignable sans clef" % r.name)


func test_spawns_valides() -> void:
	var bad: Array[String] = []
	for f in _all_floors():
		if not FloorLayout.is_walkable_tile(f.get_tile(f.player_spawn)):
			bad.append("spawn joueur")
		var used := {}
		for list: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns, f.hiding_spot_spawns]:
			for sp: FloorLayout.Spawn in list:
				var t := f.get_tile(sp.cell)
				if not (t == T.FLOOR or t == T.STREET):
					bad.append("%s hors sol" % sp.kind)
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


func test_cachettes_et_conteneurs_presents() -> void:
	for f in _all_floors():
		assert_gte(f.hiding_spot_spawns.size(), 4, "cachettes")
		assert_gte(f.container_spawns.size(), 12, "conteneurs")


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
	var a := HauntedCarnivalGenerator.generate_run(777, world, 2)
	var b := HauntedCarnivalGenerator.generate_run(777, world, 2)
	assert_eq(a.size(), b.size())
	for i in a.size():
		assert_eq(a[i].tiles, b[i].tiles)
		assert_eq(a[i].doors.size(), b[i].doors.size())
		assert_eq(a[i].enemy_spawns.size(), b[i].enemy_spawns.size())
		for j in a[i].container_spawns.size():
			assert_eq(a[i].container_spawns[j].cell, b[i].container_spawns[j].cell)
			assert_eq(a[i].container_spawns[j].kind, b[i].container_spawns[j].kind)
	var c := HauntedCarnivalGenerator.generate_floor(777, world, 2, 0)
	assert_eq(c.tiles, a[0].tiles)
	assert_null(HauntedCarnivalGenerator.generate_floor(777, world, 2, 1))


func test_plan_independant_de_la_difficulte() -> void:
	for i in 3:
		var a := HauntedCarnivalGenerator.generate_floor(_seed(i), world, 0, 0)
		var b := HauntedCarnivalGenerator.generate_floor(_seed(i), world, 4, 0)
		assert_eq(PrerenderBackdrop.layout_md5(a), PrerenderBackdrop.layout_md5(b))


func test_performance() -> void:
	HauntedCarnivalGenerator.generate_run(90000, world, 4)
	var t0 := Time.get_ticks_usec()
	var n := 0
	for s in 6:
		n += HauntedCarnivalGenerator.generate_run(90001 + s, world, 4).size()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	gut.p("Génération : %.1f ms par étage" % ms)
	assert_lt(ms, MAX_MS_PER_FLOOR, "génération : %.1f ms par étage" % ms)


## Bâtiments à toit (rendu incliné vers le nord) : aucune porte dans leur mur nord.
func test_portes_visibles_camera_inclinee() -> void:
	for f in _grounds():
		var bad: Array = []
		for d in f.doors:
			if d.vertical:
				continue
			var south := f.room_at(d.cell + Vector2i.DOWN)
			if south != null and south.building_id >= 0:
				var b2 := f.buildings[south.building_id]
				if d.cell.y == b2.rect.position.y:
					bad.append(d.cell)
		assert_eq(bad, [], "porte dans le mur nord d'un bâtiment à toit")


# --- Décor ------------------------------------------------------------------------------

func test_construction_du_decor() -> void:
	var f := _grounds()[0]
	BiomeAssets.set_world(world)
	var root := Builder.build(f, world)
	add_child_autofree(root)
	assert_true(root.y_sort_enabled)
	assert_true(root.has_signal("stairs_entered"))
	for m: String in ["get_doors", "get_stairs_areas", "get_room_at_world", "set_stairs_cooldown", "prerender_hide", "get_roofs"]:
		assert_true(root.has_method(m), m)
	assert_eq(root.get_doors().size(), f.doors.size())
	for d: DoorNode in root.get_doors():
		assert_true(d.is_in_group(&"doors"))
		assert_eq(d.is_locked(), f.get_door_at(d.cell).state == FloorLayout.DoorState.LOCKED)
	assert_eq(root.get_props().size(), f.prop_spawns.size(), "un décor par spawn")
	assert_eq(root.get_roofs().size(), f.buildings.size(), "un toit logique par bâtiment")
	var body: StaticBody2D = root.get_wall_body()
	assert_eq(body.collision_layer, 1)
	var r := root.get_room_at_world(FloorLayout.cell_to_world(f.player_spawn))
	assert_not_null(r)
	assert_eq(r.type, FloorLayout.ROOM_SPAWN)
	# Le chapiteau ovale : une case de la place hors de l'ovale appartient à la place.
	var corner := Plan.TENT_RECT.position
	assert_eq(String(root.get_room_at_world(FloorLayout.cell_to_world(corner)).tags[0]), "plaza")
	BiomeAssets.set_world(null)


func test_conteneurs_du_biome_gardent_leur_kind() -> void:
	var g := _grounds()[1]
	BiomeAssets.set_world(world)
	var root := Builder.build(g, world)
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
			assert_ne(lc.get_display_name(), "Caisse")
			n += 1
		elif ch is HidingSpot:
			assert_true(String((ch as HidingSpot).kind).begins_with("hc_"), "cachette du biome")
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
	BiomeAssets.set_world(null)


func test_objets_du_biome() -> void:
	var n := 0
	for it: ItemData in LootDB.all_items():
		if String(it.id).begins_with("hc_"):
			n += 1
			assert_not_null(it.icon, "icône %s" % it.id)
	assert_between(n, 8, 20, "objets propres au biome")
	for k: StringName in KEYS:
		var it := LootDB.get_item(k)
		assert_not_null(it, "clef %s" % k)
		if it != null:
			assert_true(it.is_key())


func test_tourelles_sur_murs_visibles() -> void:
	var placer: Script = load("res://scripts/dungeon/turret_placer.gd")
	for f in _grounds().slice(0, 4):
		var spots: Array = placer.call("find_spots", f, 1234, 2, 0, "world_04_haunted_carnival")
		for sp: Dictionary in spots:
			var c: Vector2i = sp["cell"]
			var nrm: Vector2i = sp["normal"]
			assert_eq(f.get_tile(c), T.WALL, "tourelle sur un mur")
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(c + nrm)), "face à une case praticable")


# --- Paquets pré-rendus ------------------------------------------------------------------

func _packs() -> PackedInt32Array:
	return PrerenderBackdrop.available_seeds(&"haunted_carnival")


func _meta(s: int) -> Dictionary:
	var fa := FileAccess.open(PrerenderBackdrop.pack_root(&"haunted_carnival") + str(s) + "/map.json", FileAccess.READ)
	return JSON.parse_string(fa.get_as_text()) if fa != null else {}


func test_paquets_correspondent_au_plan() -> void:
	var seeds := _packs()
	assert_gt(seeds.size(), 0, "au moins un carnaval pré-rendu")
	for s in seeds:
		var m := _meta(s)
		var L := HauntedCarnivalGenerator.generate_floor(s, world, 1, 0)
		assert_eq(String(m.get("tiles_md5", "")), PrerenderBackdrop.layout_md5(L), "seed %d : empreinte du plan" % s)
		assert_gte(int(m.get("ppc", 0)), 72, "seed %d : résolution ≥ 72 px/case" % s)
		assert_eq(int(m.get("tilt_deg", 0)), 38)
		assert_eq((m.get("interiors", []) as Array).size(), L.buildings.size(), "un intérieur par bâtiment à toit")
		assert_true(m.has("collision") and m.has("occluders"))
		var dir := PrerenderBackdrop.pack_root(&"haunted_carnival") + str(s) + "/"
		for t: Dictionary in m["tiles"]:
			assert_true(ResourceLoader.exists(dir + String(t["file"])), "tuile %s" % t["file"])
		assert_true(ResourceLoader.exists(dir + "minimap.webp"), "mini-carte")
		assert_true(ResourceLoader.exists(dir + "footprint.png"), "emprise")
		assert_lt(int((m.get("collision_stats", {}) as Dictionary).get("unblocked_cells", 0)), 60, "rendu cohérent avec le plan")
		var b := PrerenderBackdrop.create(s, L, &"haunted_carnival")
		assert_not_null(b, "fond accepté par le jeu")
		if b != null:
			b.free()


func test_paquets_collisions_gardent_les_passages() -> void:
	for s in _packs():
		var m := _meta(s)
		var L := HauntedCarnivalGenerator.generate_floor(s, world, 1, 0)
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
