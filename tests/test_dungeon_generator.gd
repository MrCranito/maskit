extends GutTest
## Tests du générateur de villes Far West (DungeonGenerator) sur 30 seeds et
## toutes les difficultés (0 Facile … 4 Cauchemar). Les runs sont générés une
## fois dans before_all puis vérifiés par chaque test.

const WORLD_PATH := "res://data/worlds/world_01_far_west.tres"
const SEEDS := 30
const DIFFS := 5
const MAX_MS_PER_FLOOR := 50.0
const T := FloorLayout.Tile

var world: WorldData
## runs[seed][diff] = Array[FloorLayout]
var runs: Array = []


func before_all() -> void:
	world = load(WORLD_PATH) as WorldData
	for s in SEEDS:
		var per_diff: Array = []
		for d in DIFFS:
			per_diff.append(DungeonGenerator.generate_run(_seed(s), world, d))
		runs.append(per_diff)


func _seed(i: int) -> int:
	return 1000 + i * 7919


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


## Points d'entrée d'un étage : spawn joueur + cases d'arrivée de chaque escalier
## (l'étage 1 contient plusieurs bâtiments séparés, chacun atteint par son escalier).
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
	return "étage %d (%dx%d)" % [f.floor_index, f.size.x, f.size.y]


# --- Monde ------------------------------------------------------------------

func test_monde_far_west_charge() -> void:
	assert_not_null(world, "world_01_far_west.tres doit se charger en WorldData")
	assert_eq(world.biome, &"far_west")
	assert_ne(world.display_name, "")
	for a: StringName in [&"saloon", &"bank", &"sheriff", &"store", &"hotel", &"stable", &"church", &"mine"]:
		assert_true(world.building_archetypes.has(a), "archétype %s" % a)
	for k: StringName in [&"crate", &"barrel", &"chest", &"cupboard", &"wardrobe", &"wagon", &"stagecoach", &"corpse"]:
		assert_true(world.container_kinds.has(k), "conteneur %s" % k)
	for key: String in ["sand", "wood", "adobe", "shadow", "sky_top", "street", "floor", "wall"]:
		assert_true(world.palette.get(key) is Color, "couleur %s" % key)


func test_colosse_seulement_super_loot_ou_boss() -> void:
	for type: Variant in world.enemy_roster:
		var has_colossus: bool = (world.enemy_roster[type] as Dictionary).has(&"sandstone_colossus")
		if has_colossus:
			assert_true(type == &"super_loot" or type == &"boss", "colosse interdit en %s" % type)
	var bad := 0
	for f in _all_floors():
		for sp in f.enemy_spawns:
			if sp.kind == &"sandstone_colossus":
				var r := f.get_room(sp.room_id)
				if r == null or not (r.type == FloorLayout.ROOM_SUPER_LOOT or r.type == FloorLayout.ROOM_BOSS):
					bad += 1
	assert_eq(bad, 0, "colosses hors super_loot/boss")


# --- Structure ----------------------------------------------------------------

func test_etages_presents_et_tailles() -> void:
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		var g := _floor(floors, 0)
		assert_not_null(g, "étage 0 présent")
		assert_not_null(_floor(floors, -1), "sous-sol présent (la mine est obligatoire)")
		assert_between(g.size.x, 55, 95, "largeur étage 0")
		assert_between(g.size.y, 36, 64, "hauteur étage 0")
		var prev := -99
		for f: FloorLayout in floors:
			assert_gt(f.floor_index, prev, "generate_run trié par floor_index")
			prev = f.floor_index
			assert_eq(f.size, g.size, "tous les étages ont la même grille")


func test_rez_de_chaussee_rue_et_batiments() -> void:
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		assert_between(g.buildings.size(), 5, 8, "5 à 8 bâtiments")
		var archs: Array[StringName] = []
		for b in g.buildings:
			archs.append(b.archetype)
			assert_between(b.room_ids.size(), 1, 4, "%s : 1 à 4 salles" % b.name)
			var street_doors := 0
			for di in b.door_ids:
				var d := g.doors[di]
				var ra := g.get_room(d.room_a)
				var rb := g.get_room(d.room_b)
				if (ra != null and ra.outdoor) or (rb != null and rb.outdoor):
					street_doors += 1
			assert_between(street_doors, 1, 2, "%s : 1-2 entrées sur la rue" % b.name)
		for a: StringName in [&"saloon", &"bank", &"sheriff", &"mine"]:
			assert_true(archs.has(a), "bâtiment %s présent" % a)
		var main_street: FloorLayout.Room = null
		for r in g.rooms:
			if r.name == "Rue principale":
				main_street = r
		assert_not_null(main_street)
		if main_street:
			assert_between(main_street.rect.size.y, 5, 7, "largeur de la rue principale")


func test_types_de_salles() -> void:
	for f in _all_floors():
		var spawn := 0
		var sup := 0
		for r in f.rooms:
			if r.type == FloorLayout.ROOM_SPAWN:
				spawn += 1
			if r.type == FloorLayout.ROOM_SUPER_LOOT:
				sup += 1
		assert_lte(sup, 2, "%s : au plus 2 super_loot" % _tag(f))
		if f.floor_index == 0:
			assert_eq(spawn, 1, "un seul spawn à l'étage 0")
			assert_gte(f.extraction_cells.size(), 1, "au moins une extraction")


func test_super_loot_verrouillees_et_gardees() -> void:
	for f in _all_floors():
		for r in f.rooms:
			if r.type != FloorLayout.ROOM_SUPER_LOOT:
				continue
			var locked := 0
			for d in f.doors:
				if (d.room_a == r.id or d.room_b == r.id):
					assert_eq(d.state, FloorLayout.DoorState.LOCKED, "%s : porte de %s verrouillée" % [_tag(f), r.name])
					assert_ne(d.key_id, &"", "clef requise")
					locked += 1
			assert_gte(locked, 1, "%s : %s a une porte" % [_tag(f), r.name])
			var guards := 0
			for e in f.enemy_spawns:
				if e.room_id == r.id:
					guards += 1
			assert_gte(guards, 2, "%s : %s gardée" % [_tag(f), r.name])


func test_coffre_banque_cle_unique() -> void:
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		var keys := {}
		for f: FloorLayout in per_diff[0]:
			for d in f.doors:
				if d.state == FloorLayout.DoorState.LOCKED:
					assert_false(keys.has(d.key_id), "clef %s unique dans le run" % d.key_id)
					keys[d.key_id] = true
		assert_true(keys.has(&"key_bank_vault"), "coffre-fort de la banque scellé")


# --- Connectivité ---------------------------------------------------------------

func test_connectivite_tout_atteignable() -> void:
	for f in _all_floors():
		var reach := _flood(f, true)
		var missing := 0
		for y in f.size.y:
			for x in f.size.x:
				if FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y))) and not reach.has(Vector2i(x, y)):
					missing += 1
		assert_eq(missing, 0, "%s : cases marchables inatteignables" % _tag(f))


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


## Décors et conteneurs bloquants ne coupent aucun passage.
func test_decors_ne_bloquent_pas() -> void:
	for f in _all_floors():
		var blocked := {}
		for s in f.prop_spawns:
			blocked[s.cell] = true
		for s2 in f.container_spawns:
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
		assert_eq(missing, 0, "%s : passage coupé par un décor/conteneur" % _tag(f))


## Deux cases marchables voisines appartenant à des salles différentes dont une
## est un intérieur de bâtiment : l'une des deux doit être une porte.
func test_interieurs_accessibles_par_portes_uniquement() -> void:
	for f in _all_floors():
		if f.floor_index == -1:
			continue
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
					var tb := f.get_tile(b)
					if not FloorLayout.is_walkable_tile(tb) or tb == T.DOOR:
						continue
					var rb := f.room_at(b)
					if rb != null and rb.id != ra.id and (not ra.outdoor or not rb.outdoor):
						bad += 1
		assert_eq(orphan, 0, "%s : cases marchables hors salle" % _tag(f))
		assert_eq(bad, 0, "%s : intérieur ouvert sans porte" % _tag(f))


func test_portes_entre_deux_cases_marchables() -> void:
	for f in _all_floors():
		for d in f.doors:
			var n1 := d.cell + (Vector2i.LEFT if d.vertical else Vector2i.UP)
			var n2 := d.cell + (Vector2i.RIGHT if d.vertical else Vector2i.DOWN)
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(n1)) and FloorLayout.is_walkable_tile(f.get_tile(n2)), "%s : porte %s traversable" % [_tag(f), d.cell])
			assert_ne(d.room_a, -1)
			assert_ne(d.room_b, -1)


# --- Étages et escaliers ----------------------------------------------------------

func test_escaliers_coherents() -> void:
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		for f: FloorLayout in floors:
			for s in f.stairs:
				assert_eq(f.get_tile(s.cell), T.STAIRS_UP if s.up else T.STAIRS_DOWN, "tuile d'escalier")
				assert_eq(s.target_floor, f.floor_index + (1 if s.up else -1))
				var other := _floor(floors, s.target_floor)
				assert_not_null(other, "étage cible %d existe" % s.target_floor)
				if other == null:
					continue
				assert_eq(s.target_cell, s.cell, "mêmes coordonnées")
				var back: FloorLayout.Stairs = null
				for s2 in other.stairs:
					if s2.cell == s.target_cell:
						back = s2
				assert_not_null(back, "escalier retour")
				if back:
					assert_eq(back.target_floor, f.floor_index)
					assert_eq(back.target_cell, s.cell)
					assert_ne(back.up, s.up)


func test_etage_superieur_seulement_saloon_hotel() -> void:
	for per_diff: Array in runs:
		var up := _floor(per_diff[0], 1)
		if up == null:
			continue
		var rects: Array[Rect2i] = []
		for b in up.buildings:
			assert_true(b.archetype == &"saloon" or b.archetype == &"hotel", "étage : saloon/hôtel seulement")
			rects.append(b.rect)
		for y in up.size.y:
			for x in up.size.x:
				var p := Vector2i(x, y)
				var inside := false
				for r in rects:
					if r.has_point(p):
						inside = true
				if not inside:
					assert_eq(up.get_tile(p), T.VOID, "étage 1 : VOID hors bâtiments")
					if up.get_tile(p) != T.VOID:
						return


# --- Spawns -------------------------------------------------------------------------

func test_spawns_valides() -> void:
	for f in _all_floors():
		var stairs := {}
		for s in f.stairs:
			stairs[s.cell] = true
		var occupied := {}
		var bad := 0
		for list: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns]:
			for sp: FloorLayout.Spawn in list:
				var t := f.get_tile(sp.cell)
				if not (t == T.FLOOR or t == T.STREET) or stairs.has(sp.cell) or f.get_door_at(sp.cell) != null:
					bad += 1
				if occupied.has(sp.cell) or sp.cell == f.player_spawn or f.extraction_cells.has(sp.cell):
					bad += 1
				occupied[sp.cell] = true
				var r := f.room_at(sp.cell)
				if r == null or r.id != sp.room_id:
					bad += 1
		assert_eq(bad, 0, "%s : spawns invalides" % _tag(f))
		assert_true(FloorLayout.is_walkable_tile(f.get_tile(f.player_spawn)), "spawn joueur marchable")
		for e in f.extraction_cells:
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(e)) and f.get_tile(e) != T.DOOR, "extraction marchable")


func test_spawn_joueur_et_extraction_eloignes() -> void:
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		var ps := g.player_spawn
		assert_true(ps.x <= 3 or ps.x >= g.size.x - 4 or ps.y <= 3 or ps.y >= g.size.y - 4, "spawn près d'un bord")
		for e in g.extraction_cells:
			assert_gt(absi(e.x - ps.x) + absi(e.y - ps.y), g.size.x / 2, "extraction loin du spawn")


func test_decors_coherents_avec_archetype() -> void:
	var expect := {&"saloon": [&"saloon_bar", &"piano"], &"sheriff": [&"jail_bars"], &"mine": [&"rail_track"]}
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		for b in g.buildings:
			if not expect.has(b.archetype):
				continue
			var kinds := {}
			for sp in g.prop_spawns:
				if b.room_ids.has(sp.room_id):
					kinds[sp.kind] = true
			for k: StringName in expect[b.archetype]:
				assert_true(kinds.has(k), "%s : décor %s" % [b.name, k])
		var outdoor := {}
		for sp2 in g.prop_spawns:
			var r := g.get_room(sp2.room_id)
			if r and r.outdoor:
				outdoor[sp2.kind] = true
		assert_true(outdoor.has(&"cactus") or outdoor.has(&"hitching_post"), "décors de rue")
		var mine := _floor(per_diff[0], -1)
		var mk := {}
		for sp3 in mine.prop_spawns:
			mk[sp3.kind] = true
		assert_true(mk.has(&"rail_track") and mk.has(&"mine_cart"), "rails et chariots dans la mine")


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


# --- Déterminisme et performances ---------------------------------------------------------

func test_determinisme() -> void:
	for s in 6:
		var a := DungeonGenerator.generate_run(_seed(s), world, 2)
		var b := DungeonGenerator.generate_run(_seed(s), world, 2)
		assert_eq(a.size(), b.size())
		for i in a.size():
			assert_eq(a[i].tiles, b[i].tiles, "tuiles identiques")
			assert_eq(_sig(a[i]), _sig(b[i]), "spawns/portes identiques")
		var single := DungeonGenerator.generate_floor(_seed(s), world, 2, 0)
		assert_eq(single.tiles, DungeonGenerator.find_floor(a, 0).tiles, "generate_floor == generate_run")
		assert_eq(_sig(single), _sig(DungeonGenerator.find_floor(a, 0)))
	var c := DungeonGenerator.generate_floor(_seed(0), world, 2, 0)
	var d2 := DungeonGenerator.generate_floor(_seed(1), world, 2, 0)
	assert_ne(c.tiles, d2.tiles, "seeds différentes → cartes différentes")


func _sig(f: FloorLayout) -> String:
	var parts: PackedStringArray = []
	for d in f.doors:
		parts.append("D%s%d%s" % [d.cell, d.state, d.key_id])
	for l: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns]:
		for s: FloorLayout.Spawn in l:
			parts.append("%s%s%d" % [s.cell, s.kind, s.room_id])
	parts.append(str(f.player_spawn))
	parts.append(str(f.extraction_cells))
	return ";".join(parts)


func test_performances() -> void:
	var worst := 0.0
	var total := 0.0
	var n := 0
	for s in 10:
		for idx: int in [-1, 0, 1]:
			var t0 := Time.get_ticks_usec()
			DungeonGenerator.generate_floor(_seed(s), world, 4, idx)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			worst = maxf(worst, ms)
			total += ms
			n += 1
	gut.p("Pire génération d'étage : %.1f ms" % worst)
	# Moyenne sous le budget ; pic toléré à 2x (machine de CI chargée, mesures bruitées).
	assert_lt(total / maxf(1.0, float(n)), MAX_MS_PER_FLOOR, "génération moyenne d'un étage < 50 ms")
	assert_lt(worst, MAX_MS_PER_FLOOR * 2.0, "pire génération d'un étage < 100 ms")
