extends GutTest
## Biome Les Terres gelées : générateur (plan en croix sur plateau de glace, 16 seeds × 5
## difficultés), constructeur de décor, portes, extraction, salles scellées, conteneurs, cachettes,
## butin, paquet pré-rendu.

const WORLD_PATH := "res://data/worlds/world_05_frozen_lands.tres"
const Gen := preload("res://scripts/biomes/frozen_lands/frozen_lands_generator.gd")
const Builder := preload("res://scripts/biomes/frozen_lands/frozen_lands_builder.gd")
const Plan := preload("res://scripts/biomes/frozen_lands/fl_plan.gd")
const Prop := preload("res://scripts/biomes/frozen_lands/fl_prop.gd")
const SEEDS := 16
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
	return 5000 + i * 7919


func _all_floors() -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	for per_diff: Array in runs:
		for floors: Array in per_diff:
			for f: FloorLayout in floors:
				out.append(f)
	return out


func _surfaces() -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	for per_diff: Array in runs:
		out.append(per_diff[1][0])
	return out


func _flood(f: FloorLayout, through_locked: bool) -> Dictionary:
	return f.flood_reachable(f.player_spawn, through_locked)


func _tag(f: FloorLayout) -> String:
	return "étage %d (%dx%d)" % [f.floor_index, f.size.x, f.size.y]


# --- Monde ----------------------------------------------------------------------------

func test_monde_charge() -> void:
	assert_not_null(world)
	assert_eq(world.biome, &"frozen_lands")
	assert_eq(world.display_name, "Les Terres gelées")
	assert_true(ResourceLoader.exists(world.generator_path), "générateur")
	assert_true(ResourceLoader.exists(world.builder_path), "constructeur")
	assert_true(DirAccess.dir_exists_absolute(world.containers_dir), "dossier des conteneurs")
	assert_true(world.floor_names.has(0), "nom de l'étage 0")
	assert_eq(BiomeRegistry.world_path(&"frozen_lands"), WORLD_PATH)
	for k: Variant in world.enemy_roster:
		for kind: Variant in world.enemy_roster[k]:
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % kind), "EnemyData %s" % kind)
			assert_true(String(kind).begins_with("ss_"), "roster provisoire ss_* : %s" % kind)
	assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % world.boss_kind), "boss")
	for e: StringName in world.elite_kinds:
		assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % e), "élite %s" % e)
	var card := MapCard.find(&"perm_terres_gelees")
	assert_not_null(card, "carte perm_terres_gelees")
	if card != null:
		assert_eq(card.world_path, WORLD_PATH)
		assert_true(card.description.begins_with("Un continent prisonnier des glaces"))
		assert_not_null(card.get_thumbnail(), "vignette assets/ui/maps/frozen_lands.png")


# --- Structure -----------------------------------------------------------------------------

func test_un_etage_plan_portrait() -> void:
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		assert_eq(floors.size(), 1, "surface seule (sous-sol plus tard)")
		var g: FloorLayout = floors[0]
		assert_eq(g.floor_index, 0)
		assert_eq(g.size, Vector2i(Plan.W, Plan.H), "plan en croix")
		assert_gt(g.size.y, g.size.x, "format portrait")
		assert_true(g.has_meta(&"render_contract"), "contrat de rendu")
		var c: Dictionary = g.get_meta(&"render_contract")
		assert_eq(String(c.get("kind", "")), "fl_base")
		assert_true(c.has("lab") and c.has("decor") and c.has("heliport") and c.has("dock"))
		var kinds := {}
		for d: Dictionary in c["decor"]:
			kinds[d["kind"]] = true
		assert_true(kinds.has("ship") and kinds.has("wreck") and kinds.has("iceberg"), "navire, épave, icebergs")


func test_plateau_de_glace_entoure_d_eau() -> void:
	for f in _surfaces():
		var snow := f.tiles.count(T.STREET)
		var water := f.tiles.count(T.VOID)
		assert_gt(snow, 1000, "%s : plateau de neige" % _tag(f))
		assert_gt(water, 1200, "%s : eau autour" % _tag(f))
		# Les quatre coins de la grille sont de l'eau, le centre est le laboratoire.
		for c: Vector2i in [Vector2i(1, 1), Vector2i(f.size.x - 2, 1), Vector2i(1, f.size.y - 2), Vector2i(f.size.x - 2, f.size.y - 2)]:
			assert_eq(f.get_tile(c), T.VOID, "coin %s dans l'eau" % c)
		var lab := f.room_at(Vector2i(int(Plan.LAB_C.x), int(Plan.LAB_C.y)))
		assert_not_null(lab)
		if lab != null:
			assert_eq(lab.type, FloorLayout.ROOM_BOSS, "salle du boss = labo aux cristaux")
			assert_eq(lab.tags[0], "crystal_lab")
			assert_true(lab.tags.has("round") and lab.tags.has("open"))


func test_roles_et_types_de_salles() -> void:
	var seen_types := {}
	for f in _all_floors():
		var spawn := 0
		var boss := 0
		var sup := 0
		var roles := {}
		for r in f.rooms:
			assert_false(r.tags.is_empty() or r.tags[0] == "", "%s : rôle (tags[0]) de %s" % [_tag(f), r.name])
			assert_false(r.name.is_empty(), "nom de salle")
			seen_types[r.type] = true
			roles[r.tags[0]] = true
			if r.type == FloorLayout.ROOM_SPAWN:
				spawn += 1
			if r.type == FloorLayout.ROOM_BOSS:
				boss += 1
			if r.type == FloorLayout.ROOM_SUPER_LOOT:
				sup += 1
		assert_eq(spawn, 1, "rampe d'accès")
		assert_eq(boss, 1, "laboratoire des cristaux")
		assert_between(sup, 1, 2, "labo cryo scellé (+ armurerie)")
		for role: String in ["crystal_lab", "guard_tower", "observatory", "heliport", "dock", "hangar", "lab", "barracks", "ramp", "gate", "yard", "walkway"]:
			assert_true(roles.has(role), "%s : salle « %s »" % [_tag(f), role])
		var towers := 0
		for r2 in f.rooms:
			if r2.tags[0] == "guard_tower":
				towers += 1
		assert_eq(towers, 4, "quatre postes de garde aux angles")
		assert_gte(f.extraction_cells.size(), 4, "extraction (héliport et/ou ponton)")
	for t: StringName in [&"spawn", &"combat", &"loot", &"trap", &"rest", &"super_loot", &"boss", &"extraction", &"corridor"]:
		assert_true(seen_types.has(t), "type de salle %s présent" % t)


func test_bunkers_fermes_toits() -> void:
	for f in _surfaces():
		assert_gte(f.buildings.size(), 6, "%s : bunkers, hangars, tourelles, dômes" % _tag(f))
		var archs := {}
		for b in f.buildings:
			archs[b.archetype] = true
			assert_gt(b.room_ids.size(), 0, "salle du bâtiment")
			assert_true(b.name != "")
		for a: StringName in [&"fl_bunker", &"fl_hangar", &"fl_tower", &"fl_dome"]:
			assert_true(archs.has(a), "archétype %s" % a)


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
					assert_true(String(d.key_id).begins_with("fl_key_"), "clef préfixée : %s" % d.key_id)
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
	assert_eq(bad, 0, "boss hors du laboratoire")
	assert_gt(bosses, 0, "le boss apparaît")


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
		assert_eq(missing, 0, "%s : passage coupé" % _tag(f))


## Les salles fermées ne communiquent que par des portes (passerelles, cour, neige et salles
## « open » exceptées).
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
					var closed_a := not ra.tags.has("corridor") and not ra.tags.has("open") and not ra.outdoor
					var closed_b := not rb.tags.has("corridor") and not rb.tags.has("open") and not rb.outdoor
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


## Porte jamais dans le mur nord d'un module à toit (masquée par le toit rendu incliné).
func test_portes_visibles_camera_inclinee() -> void:
	for f in _surfaces():
		var bad: Array = []
		for d in f.doors:
			if d.vertical:
				continue
			var south := f.room_at(d.cell + Vector2i.DOWN)
			if south != null and south.building_id >= 0:
				var b2 := f.buildings[south.building_id]
				if d.cell.y == b2.rect.position.y:
					bad.append(d.cell)
		assert_eq(bad, [], "porte dans le mur nord d'un module à toit")


# --- Spawns -----------------------------------------------------------------------------------------

func test_spawns_valides() -> void:
	for f in _all_floors():
		var occupied := {}
		var bad := 0
		for list: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns, f.hiding_spot_spawns]:
			for sp: FloorLayout.Spawn in list:
				var t := f.get_tile(sp.cell)
				if (t != T.FLOOR and t != T.STREET) or f.get_door_at(sp.cell) != null:
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
			assert_eq(f.get_tile(e), T.STREET, "extraction sur la neige (héliport / ponton)")


func test_spawn_pont_sud_et_extraction_eloignee() -> void:
	for f in _surfaces():
		var ps := f.player_spawn
		assert_eq(f.room_at(ps).name, "Pont d'accès", "apparition au bout du pont d'accès")
		assert_gte(ps.y, Plan.BRIDGE_Y0, "pont au sud, au-dessus de l'eau")
		assert_between(ps.x, f.size.x / 2 - 4, f.size.x / 2 + 4, "pont centré")
		# Le pont est entouré d'eau (cases VOID à 3 cases de part et d'autre).
		assert_eq(f.get_tile(ps + Vector2i(-4, 0)), T.VOID, "eau à l'ouest du pont")
		assert_eq(f.get_tile(ps + Vector2i(4, 0)), T.VOID, "eau à l'est du pont")
		var ramp := f.room_at(Vector2i(Plan.SPINE_X0 + 1, Plan.BRIDGE_Y0 - 3))
		assert_true(ramp != null and ramp.tags[0] == "ramp", "rampe d'accès avant le pont")
		for e in f.extraction_cells:
			assert_gt(absi(e.x - ps.x) + absi(e.y - ps.y), 16, "extraction loin de l'entrée")
			var r := f.room_at(e)
			assert_true(r != null and r.type == FloorLayout.ROOM_EXTRACTION and (r.tags[0] == "heliport" or r.tags[0] == "dock"))


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


func test_cachettes() -> void:
	for f in _all_floors():
		assert_gte(f.hiding_spot_spawns.size(), 2, "%s : cachettes" % _tag(f))


func test_grands_decors_helico_cristaux() -> void:
	for f in _surfaces():
		var kinds := {}
		for p in f.prop_spawns:
			kinds[p.kind] = true
			if p.size != Vector2i.ONE:
				for q in FloorLayout.spawn_cells(p):
					assert_eq(f.get_tile(q), T.FLOOR, "empreinte de %s sur le sol" % p.kind)
		assert_true(kinds.has(&"fl_crystal_core"), "grand cristal au centre du labo")
		assert_true(kinds.has(&"fl_helicopter"), "hélicoptère dans le hangar")


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
		var single := Gen.generate_floor(_seed(s), world, 2, 0)
		assert_eq(single.tiles, a[0].tiles, "generate_floor == generate_run")
		assert_eq(_sig(single), _sig(a[0]))
	assert_ne(Gen.generate_floor(_seed(0), world, 2, 0).tiles, Gen.generate_floor(_seed(1), world, 2, 0).tiles)
	assert_null(Gen.generate_floor(_seed(0), world, 2, -1), "pas de sous-sol dans cette passe")


func test_performances() -> void:
	var worst := 0.0
	var total := 0.0
	var n := 0
	for s in 8:
		var t0 := Time.get_ticks_usec()
		Gen.generate_floor(_seed(s), world, 4, 0)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		n += 1
	gut.p("Pire génération : %.1f ms" % worst)
	assert_lt(total / maxf(1.0, float(n)), MAX_MS_PER_FLOOR, "génération moyenne < 50 ms")
	assert_lt(worst, MAX_MS_PER_FLOOR * 2.0, "pire génération < 100 ms")


# --- Décor ---------------------------------------------------------------------------------------------

func test_constructeur_api_et_portes() -> void:
	var f: FloorLayout = runs[0][2][0]
	var root := Builder.build(f, world)
	add_child_autofree(root)
	assert_true(root.y_sort_enabled)
	assert_true(root.has_signal("stairs_entered"))
	for m: String in ["get_doors", "get_stairs_areas", "get_room_at_world", "set_stairs_cooldown", "get_roofs", "prerender_hide", "get_props", "get_wall_body"]:
		assert_true(root.has_method(m), m)
	var doors: Array[DoorNode] = root.get_doors()
	assert_eq(doors.size(), f.doors.size(), "une porte par door")
	var locked := 0
	for d: DoorNode in doors:
		assert_true(d.is_in_group(&"doors"))
		assert_eq(d.position, Vector2((d.cell.x + 0.5) * 64.0, (d.cell.y + 1.0) * 64.0))
		if d.is_locked():
			locked += 1
			assert_true(String(d.key_id).begins_with("fl_key_"))
	var expected := 0
	for fd in f.doors:
		if fd.state == FloorLayout.DoorState.LOCKED:
			expected += 1
	assert_eq(locked, expected)
	assert_eq((root.get_stairs_areas() as Array).size(), f.stairs.size())
	assert_eq(root.get_wall_body().collision_layer, 1, "couche world")
	var solid := 0
	for t: int in f.tiles:
		if FloorLayout.is_opaque_tile(t):
			solid += 1
	assert_lt(root.get_wall_body().get_child_count(), solid / 4, "collisions fusionnées")
	var spawn_room: FloorLayout.Room = root.get_room_at_world(FloorLayout.cell_to_world(f.player_spawn))
	assert_not_null(spawn_room)
	assert_eq(root.get_props().size(), f.prop_spawns.size())
	var roofs: Array = root.get_roofs()
	assert_eq(roofs.size(), f.buildings.size(), "un toit logique par bunker")
	for r: BuildingRoof in roofs:
		assert_true(String(r.name).begins_with("Roof_"))
	root.set_stairs_cooldown(0.3)
	root.prerender_hide()
	assert_false((root.get_node("Water") as CanvasItem).visible)


func test_ouverture_porte_bunker() -> void:
	var f: FloorLayout = runs[1][1][0]
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
	var f: FloorLayout = runs[2][2][0]
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


# --- Butin -------------------------------------------------------------------------------------------------

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
	assert_eq(BiomeRegistry.enemy_table_kind(&"frozen_lands"), &"enemy_frozen_lands", "table d'ennemis du biome")


func test_objets_du_biome() -> void:
	var n := 0
	for it: ItemData in LootDB.all_items():
		if String(it.id).begins_with("fl_"):
			n += 1
			assert_not_null(it.icon, "%s : icône" % it.id)
			assert_false(it.description.is_empty())
	assert_between(n, 12, 25, "objets propres au biome")
	for k: StringName in Gen.KEYS:
		var key := LootDB.get_item(k)
		assert_not_null(key)
		if key != null:
			assert_true(key.is_key())


func test_decors_du_monde_connus() -> void:
	for k: StringName in world.prop_kinds:
		assert_true(Prop.is_known_kind(k), "décor %s" % k)


# --- Tourelles -------------------------------------------------------------------------------------------

## Tourelles : toujours accrochées à un mur (case WALL rendue), face à une case praticable.
func test_tourelles_sur_murs_visibles() -> void:
	var placer: Script = load("res://scripts/dungeon/turret_placer.gd")
	for f in _surfaces():
		var spots: Array = placer.call("find_spots", f, 1234, 2, 0, "world_05_frozen_lands")
		assert_gt(spots.size(), 0, "des tourelles")
		for sp: Dictionary in spots:
			var c: Vector2i = sp["cell"]
			var n: Vector2i = sp["normal"]
			assert_eq(f.get_tile(c), T.WALL, "tourelle sur un mur")
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(c + n)), "face à une case praticable")


# --- Paquets pré-rendus (assets/prerender/frozen_lands/<seed>/) --------------------------------

func _packs() -> PackedInt32Array:
	return PrerenderBackdrop.available_seeds(&"frozen_lands")


func _pack_meta(s: int) -> Dictionary:
	var f := FileAccess.open(PrerenderBackdrop.pack_root(&"frozen_lands") + str(s) + "/map.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else {}


func test_paquets_correspondent_au_plan() -> void:
	var seeds := _packs()
	assert_gt(seeds.size(), 0, "au moins une carte des Terres gelées pré-rendue")
	for s in seeds:
		var m := _pack_meta(s)
		var L := Gen.generate_floor(s, world, 1, 0)
		assert_eq(String(m.get("tiles_md5", "")), PrerenderBackdrop.layout_md5(L), "seed %d : empreinte du plan" % s)
		assert_gte(int(m.get("ppc", 0)), 72, "seed %d : résolution ≥ 72 px/case" % s)
		assert_eq(int(m.get("tilt_deg", 0)), 38)
		assert_eq((m.get("interiors", []) as Array).size(), L.buildings.size(), "un intérieur par bunker")
		assert_true(m.has("collision") and m.has("occluders"), "collisions et occultation")
		var dir := PrerenderBackdrop.pack_root(&"frozen_lands") + str(s) + "/"
		for t: Dictionary in m["tiles"]:
			assert_true(ResourceLoader.exists(dir + String(t["file"])), "tuile %s" % t["file"])
		assert_true(ResourceLoader.exists(dir + "minimap.webp"), "mini-carte")
		assert_true(ResourceLoader.exists(dir + "footprint.png"), "emprise")
		assert_lt(int((m.get("collision_stats", {}) as Dictionary).get("unblocked_cells", 0)), 60, "rendu cohérent avec le plan")
		var b := PrerenderBackdrop.create(s, L, &"frozen_lands")
		assert_not_null(b, "fond accepté par le jeu")
		if b != null:
			b.free()


func test_paquets_collisions_gardent_les_passages() -> void:
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
