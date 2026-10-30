extends GutTest
## Tests du générateur de villes Far West (DungeonGenerator) sur 30 seeds et
## toutes les difficultés (0 Facile … 4 Cauchemar). Les runs sont générés une
## fois dans before_all puis vérifiés par chaque test.

const WORLD_PATH := "res://data/worlds/world_01_far_west.tres"
const SEEDS := 30
const DIFFS := 5
const MAX_MS_PER_FLOOR := 50.0
## Passes de chronométrage de test_performances (on garde le meilleur temps de chaque étage).
const PERF_PASSES := 3
const T := FloorLayout.Tile
const Cfg := preload("res://scripts/dungeon/gen/gen_config.gd")

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


## Kinds de boss du monde : WorldData.boss_kind + kinds du roster dont les données sont « boss ».
func _boss_kinds() -> Array[StringName]:
	var out: Array[StringName] = []
	if world.boss_kind != &"":
		out.append(world.boss_kind)
	for type: Variant in world.enemy_roster:
		for k: Variant in (world.enemy_roster[type] as Dictionary):
			var kind := StringName(str(k))
			var p := "res://data/enemies/%s.tres" % kind
			if not out.has(kind) and ResourceLoader.exists(p) and (load(p) as EnemyData).boss:
				out.append(kind)
	return out


func test_boss_seulement_super_loot_ou_boss() -> void:
	var bosses := _boss_kinds()
	for type: Variant in world.enemy_roster:
		for b: StringName in bosses:
			if (world.enemy_roster[type] as Dictionary).has(b):
				assert_true(type == &"super_loot" or type == &"boss", "boss %s interdit en %s" % [b, type])
	var bad := 0
	for f in _all_floors():
		for sp in f.enemy_spawns:
			if bosses.has(sp.kind):
				var r := f.get_room(sp.room_id)
				if r == null or not (r.type == FloorLayout.ROOM_SUPER_LOOT or r.type == FloorLayout.ROOM_BOSS):
					bad += 1
	assert_eq(bad, 0, "boss hors super_loot/boss")


# --- Structure ----------------------------------------------------------------

func test_etages_presents_et_tailles() -> void:
	for per_diff: Array in runs:
		var floors: Array = per_diff[0]
		var g := _floor(floors, 0)
		assert_not_null(g, "étage 0 présent")
		assert_not_null(_floor(floors, -1), "sous-sol présent (la mine est obligatoire)")
		assert_between(g.size.x, 40, 70, "largeur étage 0")
		assert_between(g.size.y, 70, 110, "hauteur étage 0")
		assert_gt(g.size.y, g.size.x, "carte au format portrait")
		var prev := -99
		for f: FloorLayout in floors:
			assert_gt(f.floor_index, prev, "generate_run trié par floor_index")
			prev = f.floor_index
			assert_eq(f.size, g.size, "tous les étages ont la même grille")


## Village de la maquette (docs/reference/farwest_maquette_carte.png) : 16 à 24 bâtiments, surtout
## de petites maisons, 4 à 6 bâtiments importants (+ entrée de mine), voie ferrée traversant toute
## la carte avec un train à l'arrêt (obstacle, passages), rochers, rues de terre, palissades.
func test_rez_de_chaussee_village() -> void:
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		var major := 0
		var small := 0
		var archs: Array[StringName] = []
		for b in g.buildings:
			archs.append(b.archetype)
			if b.archetype == &"shack" or b.archetype == &"shed":
				small += 1
				assert_lte(b.rect.size.x * b.rect.size.y, 7 * 7, "%s : petite maison" % b.name)
			elif b.archetype != &"mine":
				major += 1
			assert_between(b.room_ids.size(), 1, 4, "%s : 1 à 4 salles" % b.name)
			var street_doors := 0
			for di in b.door_ids:
				var d := g.doors[di]
				var ra := g.get_room(d.room_a)
				var rb := g.get_room(d.room_b)
				if (ra != null and ra.outdoor) or (rb != null and rb.outdoor):
					street_doors += 1
			assert_between(street_doors, 1, 2, "%s : 1-2 entrées sur la rue" % b.name)
		assert_between(g.buildings.size(), 15, 28, "16 à 24 bâtiments (tolérance)")
		assert_between(major, 4, 6, "4 à 6 bâtiments importants")
		assert_gt(small, major, "majorité de petites maisons")
		for a: StringName in [&"saloon", &"bank", &"sheriff", &"mine"]:
			assert_true(archs.has(a), "bâtiment %s présent" % a)
		# Bâtiments séparés par au moins une case (les appentis sont collés à leur bâtiment).
		for i in g.buildings.size():
			for j in range(i + 1, g.buildings.size()):
				var bi := g.buildings[i]
				var bj := g.buildings[j]
				if bi.archetype == &"shed" or bj.archetype == &"shed":
					assert_false(bi.rect.intersects(bj.rect), "appentis sans chevauchement")
				else:
					assert_false(bi.rect.grow(1).intersects(bj.rect), "bâtiments espacés")
		var rail: FloorLayout.Room = null
		for r in g.rooms:
			if r.tags.size() > 0 and r.tags[0] == "railway":
				rail = r
		assert_not_null(rail, "voie ferrée")
		if rail:
			assert_gte(rail.rect.size.x, g.size.x - 2, "la voie traverse toute la carte")
		var kinds := {}
		var train_cells := 0
		for s in g.landmark_spawns:
			kinds[s.kind] = true
			for q in FloorLayout.spawn_cells(s):
				assert_eq(g.get_tile(q), T.WALL, "grand décor posé sur des murs")
			if String(s.kind) in ["lm_loco", "lm_tender", "lm_boxcar", "lm_boxcar_b", "lm_tankcar", "lm_flatcar", "lm_caboose"]:
				train_cells += s.size.x
		assert_true(kinds.has(&"lm_loco"), "locomotive")
		assert_gt(train_cells, g.size.x / 3, "train long")
		assert_true(kinds.has(&"lm_windmill") or kinds.has(&"prop_water_tower"), "éolienne / château d'eau")
		assert_true(kinds.has(&"lm_well"), "puits")
		var rocks := 0
		for k: StringName in kinds:
			if String(k).begins_with("lm_rock") or k == &"lm_mesa":
				rocks += 1
		assert_gte(rocks, 3, "rochers variés")


## Champs du contrat de rendu (FloorLayout : paths, fences, rock_formations, landmarks, rails, train ;
## Building : roof_style, stories, porch_side), cohérents avec la grille.
func test_contrat_rendu_village() -> void:
	var styles := [&"tin_blue", &"tin_rust", &"shingle", &"red", &"plank"]
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		assert_gt(g.paths.size(), 200, "rues de terre battue")
		for c: Vector2i in g.paths:
			assert_eq(g.get_tile(c), T.STREET, "rue praticable")
			if g.get_tile(c) != T.STREET:
				return
		assert_gte(g.fences.size(), 2, "palissades")
		for pl: Array in g.fences:
			assert_gt(pl.size(), 0)
			for k in pl.size():
				var c2: Vector2i = pl[k]
				assert_eq(g.get_tile(c2), T.WALL, "palissade = obstacle")
				if k > 0:
					var d: Vector2i = c2 - (pl[k - 1] as Vector2i)
					assert_eq(absi(d.x) + absi(d.y), 1, "polyligne de cases contiguës")
		assert_gte(g.rock_formations.size(), 6, "formations rocheuses (coins, bords, milieu)")
		var big := 0
		for rf: Dictionary in g.rock_formations:
			var cells: Array = rf["cells"]
			if cells.size() >= 16:
				big += 1
			assert_gt(float(rf["height"]), 0.0)
			for c3: Vector2i in cells:
				assert_eq(g.get_tile(c3), T.WALL, "rocher = obstacle")
		assert_gte(big, 2, "formations massives")
		var lk := {}
		for lm: Dictionary in g.landmarks:
			lk[lm["kind"]] = true
			for c4 in FloorLayout.spawn_cells(_lm_spawn(lm)):
				assert_eq(g.get_tile(c4), T.WALL, "repère = obstacle")
		assert_true(lk.has(&"well"), "puits")
		assert_true(lk.has(&"windmill") or lk.has(&"water_tower"), "éolienne / château d'eau")
		var main := false
		for rl: Dictionary in g.rails:
			if rl["kind"] == &"main":
				main = true
		assert_true(main, "voie principale")
		assert_gte(g.train.size(), 4, "train")
		for t: Dictionary in g.train:
			var tr: Rect2i = t["rect"]
			for y in range(tr.position.y, tr.end.y):
				for x in range(tr.position.x, tr.end.x):
					assert_eq(g.get_tile(Vector2i(x, y)), T.WALL, "wagon = obstacle")
		for b in g.buildings:
			assert_true(styles.has(b.roof_style), "%s : style de toit" % b.name)
			assert_between(b.stories, 1, 2)
			assert_eq(absi(b.porch_side.x) + absi(b.porch_side.y), 1, "porch_side unitaire")
			if b.archetype == &"saloon" or b.archetype == &"hotel":
				assert_eq(b.stories, 2, "%s : deux niveaux" % b.name)
			# La porte de façade est sur le côté porch_side.
			var ok := false
			for di in b.door_ids:
				var dc := g.doors[di].cell
				var o := dc + b.porch_side
				if not b.rect.has_point(o) and g.get_tile(o) == T.STREET:
					ok = true
			assert_true(ok, "%s : porte sur le côté du porche" % b.name)


func _lm_spawn(lm: Dictionary) -> FloorLayout.Spawn:
	var r: Rect2i = lm["rect"]
	var s := FloorLayout.Spawn.new()
	s.size = r.size
	s.cell = Vector2i(r.position.x + (r.size.x - 1) / 2, r.end.y - 1)
	return s


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


## Cases occupées par décors (emprise complète), conteneurs et cachettes.
func _blocked(f: FloorLayout) -> Dictionary:
	var blocked := {}
	for s in f.prop_spawns:
		for q in FloorLayout.spawn_cells(s):
			blocked[q] = true
	for l: Array in [f.container_spawns, f.hiding_spot_spawns]:
		for s2: FloorLayout.Spawn in l:
			blocked[s2.cell] = true
	return blocked


## Composante accessible depuis les entrées en évitant `blocked`.
func _reach(f: FloorLayout, blocked: Dictionary) -> Dictionary:
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
	return seen


## Décors (emprises comprises), conteneurs et cachettes ne coupent aucun passage.
func test_decors_ne_bloquent_pas() -> void:
	for f in _all_floors():
		var blocked := _blocked(f)
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
	# Aménagement par gabarits : bar (ou comptoir) + piano au saloon, barreaux des cellules
	# peints sur les murs du bureau du shérif (décor mural), rails au sol dans la mine.
	var piano_ok := 0
	var saloons := 0
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		for b in g.buildings:
			var kinds := {}
			for sp in g.prop_spawns:
				if b.room_ids.has(sp.room_id):
					kinds[sp.kind] = true
			var decals := {}
			for dc in g.decor_spawns:
				if b.room_ids.has(dc.room_id):
					decals[dc.kind] = true
			match b.archetype:
				&"saloon":
					saloons += 1
					assert_true(kinds.has(&"saloon_bar") or kinds.has(&"counter"), "%s : bar" % b.name)
					if kinds.has(&"piano"):
						piano_ok += 1
				&"sheriff":
					var bars := 0
					for c: Vector2i in g.wall_decor_cells:
						if g.wall_decor_cells[c] == &"kit_wall_bars" and b.rect.has_point(c):
							bars += 1
					assert_gt(bars, 0, "%s : barreaux des cellules" % b.name)
				&"mine":
					assert_true(decals.has(&"prop_rail_track"), "%s : rails" % b.name)
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
		var md := {}
		for dc2 in mine.decor_spawns:
			md[dc2.kind] = true
		assert_true(md.has(&"prop_rail_track") and mk.has(&"mine_cart"), "rails et chariots dans la mine")
	assert_gt(float(piano_ok) / maxf(1.0, float(saloons)), 0.8, "piano dans la plupart des saloons")


# --- Aménagement par gabarits ---------------------------------------------------------------

const Pop := preload("res://scripts/dungeon/gen/populator.gd")
const Tpl := preload("res://scripts/dungeon/gen/fw_templates.gd")


## Conteneurs et cachettes : au moins une case voisine accessible depuis les entrées.
func test_conteneurs_accessibles() -> void:
	for f in _all_floors():
		var reach := _reach(f, _blocked(f))
		var bad := 0
		for l: Array in [f.container_spawns, f.hiding_spot_spawns]:
			for s: FloorLayout.Spawn in l:
				var ok := false
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					if reach.has(s.cell + d):
						ok = true
				if not ok:
					bad += 1
		assert_eq(bad, 0, "%s : conteneurs / cachettes inaccessibles" % _tag(f))


## Rien de bloquant (décor, conteneur, cachette, cloison) sur une porte, un escalier, une case
## d'extraction ou la case intérieure juste devant une porte / un escalier.
func test_abords_portes_escaliers_extraction_libres() -> void:
	for f in _all_floors():
		var blocked := _blocked(f)
		for p: Vector2i in f.partition_cells:
			blocked[p] = true
		var bad := 0
		var gates: Array[Vector2i] = []
		for d in f.doors:
			gates.append(d.cell)
			gates.append(d.cell + (Vector2i.LEFT if d.vertical else Vector2i.UP))
			gates.append(d.cell + (Vector2i.RIGHT if d.vertical else Vector2i.DOWN))
		for st in f.stairs:
			gates.append(st.cell)
			for dd: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if FloorLayout.is_walkable_tile(f.get_tile(st.cell + dd)):
					gates.append(st.cell + dd)
		for e in f.extraction_cells:
			gates.append(e)
		gates.append(f.player_spawn)
		for g in gates:
			if blocked.has(g):
				bad += 1
		assert_eq(bad, 0, "%s : abord de porte / escalier / extraction encombré" % _tag(f))


## Chaque salle intérieure dont le rôle a un gabarit reçoit du mobilier (ou des cloisons), et
## chaque rôle de gabarit est rencontré sur l'ensemble des runs.
func test_chaque_piece_recoit_son_gabarit() -> void:
	var seen_roles := {}
	var empty := 0
	var total := 0
	for f in _all_floors():
		var per_room := {}
		for s in f.prop_spawns:
			per_room[s.room_id] = int(per_room.get(s.room_id, 0)) + 1
		for p: Vector2i in f.partition_cells:
			var r0 := f.room_at(p)
			if r0 != null:
				per_room[r0.id] = int(per_room.get(r0.id, 0)) + 1
		for r in f.rooms:
			if not Pop.has_template(r):
				continue
			var role := StringName(r.tags[0])
			seen_roles[role] = true
			# Couloirs : tapis et cadres seulement (pas de mobilier).
			if role == &"corridor" or role == &"upper_corridor":
				continue
			total += 1
			if int(per_room.get(r.id, 0)) == 0:
				empty += 1
	gut.p("Salles aménagées sans mobilier : %d / %d" % [empty, total])
	assert_lt(float(empty), float(total) * 0.03, "presque toutes les salles reçoivent leur gabarit")
	for role: StringName in [&"saloon_hall", &"bank_hall", &"bank_vault", &"sheriff_office", &"jail_cell", &"store_shop",
			&"hotel_reception", &"bedroom", &"stable_main", &"stable_box", &"church_nave", &"ore_room", &"storage"]:
		assert_true(seen_roles.has(role), "gabarit %s utilisé" % role)


## Meubles signature par pièce (mobilier groupé et cohérent).
func test_meubles_signature() -> void:
	var expect := {&"church_nave": [&"altar", &"pew"], &"jail_cell": [&"bed"], &"bedroom": [&"bed"],
		&"saloon_hall": [&"poker_table"], &"stable_main": [&"hay_bale"], &"store_shop": [&"shelf"]}
	var hits := {}
	var counts := {}
	for f in _all_floors():
		var kinds_by_room := {}
		for s in f.prop_spawns:
			if not kinds_by_room.has(s.room_id):
				kinds_by_room[s.room_id] = {}
			(kinds_by_room[s.room_id] as Dictionary)[s.kind] = true
		for r in f.rooms:
			var role := StringName(r.tags[0]) if r.tags.size() > 0 else &""
			if not expect.has(role) or r.outdoor:
				continue
			counts[role] = int(counts.get(role, 0)) + 1
			var ks: Dictionary = kinds_by_room.get(r.id, {})
			var all := true
			for k: StringName in expect[role]:
				if not ks.has(k):
					all = false
			if all:
				hits[role] = int(hits.get(role, 0)) + 1
	for role2: StringName in expect:
		var n := int(counts.get(role2, 0))
		if n == 0:
			continue
		assert_gt(float(int(hits.get(role2, 0))) / float(n), 0.8, "%s : meubles %s dans la plupart des salles" % [role2, expect[role2]])


## Les salles du saloon / de la banque ont un bar ou un comptoir contre un mur.
func test_bar_et_comptoir_contre_un_mur() -> void:
	for f in _all_floors():
		for s in f.prop_spawns:
			if s.kind != &"saloon_bar" and s.kind != &"counter":
				continue
			var cells := FloorLayout.spawn_cells(s)
			var touches := false
			for q in cells:
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var t := f.get_tile(q + d)
					if t == T.WALL or t == T.VOID:
						touches = true
			assert_true(touches, "%s : %s en %s adossé (mur ou cloison)" % [_tag(f), s.kind, s.cell])
			if not touches:
				return


## Cloisons : uniquement dans des salles intérieures, jamais sur une case réservée, et le
## champ partition_cells correspond bien à des murs.
func test_cloisons_coherentes() -> void:
	var n := 0
	for f in _all_floors():
		for p: Vector2i in f.partition_cells:
			n += 1
			assert_eq(f.get_tile(p), T.WALL, "cloison = mur")
			var r := f.room_at(p)
			assert_true(r != null and not r.outdoor, "cloison dans une salle intérieure")
	assert_gt(n, 0, "des cloisons sont posées (stalles, guichets, piliers)")


## Décors muraux : uniquement sur des cases de mur dont le sud est praticable (face visible),
## et une partie des murs reste libre (tourelles).
func test_decors_muraux() -> void:
	var dec := 0
	var faces := 0
	for f in _all_floors():
		for c: Vector2i in f.wall_decor_cells:
			assert_eq(f.get_tile(c), T.WALL, "décor mural sur un mur")
			assert_true(FloorLayout.is_walkable_tile(f.get_tile(c + Vector2i.DOWN)), "face visible")
			dec += 1
		for y in f.size.y:
			for x in f.size.x:
				if f.get_tile(Vector2i(x, y)) == T.WALL and FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y + 1))):
					faces += 1
	gut.p("Faces de murs décorées : %d / %d" % [dec, faces])
	assert_gt(dec, 0)
	assert_lt(float(dec), float(faces) * 0.5, "la majorité des murs reste libre")


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
	for l: Array in [f.enemy_spawns, f.container_spawns, f.prop_spawns, f.hiding_spot_spawns, f.decor_spawns]:
		for s: FloorLayout.Spawn in l:
			parts.append("%s%s%d%s%s" % [s.cell, s.kind, s.room_id, s.offset, s.size])
	var wd := f.wall_decor_cells.keys()
	wd.sort()
	for c: Vector2i in wd:
		parts.append("W%s%s" % [c, f.wall_decor_cells[c]])
	parts.append(str(f.player_spawn))
	parts.append(str(f.extraction_cells))
	return ";".join(parts)


func test_performances() -> void:
	# Mesure comme en jeu : generate_run (la ville est construite une fois par raid), ramené à un
	# étage, comme test_mall. Chaque run est chronométré PERF_PASSES fois et on garde son meilleur
	# temps : la charge de la machine ne fait qu'ajouter du temps, alors qu'une vraie régression
	# ralentit toutes les mesures. Budgets inchangés.
	var per_floor: Array[float] = []
	var total_us := 0
	var n := 0
	for s in 10:
		var best_us := -1
		var floors := 0
		for pass_i in PERF_PASSES:
			var t0 := Time.get_ticks_usec()
			floors = DungeonGenerator.generate_run(_seed(s), world, 4).size()
			var us := Time.get_ticks_usec() - t0
			best_us = us if best_us < 0 else mini(best_us, us)
		total_us += best_us
		n += floors
		per_floor.append(float(best_us) / 1000.0 / float(maxi(floors, 1)))
	var worst := 0.0
	for ms in per_floor:
		worst = maxf(worst, ms)
	var mean := float(total_us) / 1000.0 / float(maxi(n, 1))
	gut.p("Génération d'un raid (meilleur de %d passes) : %.1f ms par étage, pire run %.1f ms par étage" % [PERF_PASSES, mean, worst])
	# Moyenne sous le budget ; pic toléré à 2x (mesures bruitées).
	assert_lt(mean, MAX_MS_PER_FLOOR, "génération moyenne d'un étage < 50 ms")
	assert_lt(worst, MAX_MS_PER_FLOOR * 2.0, "pire génération d'un étage < 100 ms")


# --- Correctif « portes sur les toits » / échelles / train (rendu pré-calculé) -------------

## Côté (N/S/E/W) d'une porte du mur d'enceinte, "" pour une porte intérieure.
func _door_side(b: FloorLayout.Building, d: FloorLayout.Door) -> String:
	var r := b.rect
	if d.cell.y == r.end.y - 1 and not d.vertical:
		return "S"
	if d.cell.y == r.position.y and not d.vertical:
		return "N"
	if d.cell.x == r.position.x and d.vertical:
		return "W"
	if d.cell.x == r.end.x - 1 and d.vertical:
		return "E"
	return ""


## Toutes les portes extérieures du village sont sur la façade SUD (seule visible avec la caméra
## inclinée vers le nord) : aucune sur une façade nord (cachée sous le toit projeté) ni est / ouest
## (vue par la tranche), et la case devant chaque porte est une rue atteignable depuis l'apparition.
func test_portes_exterieures_facade_sud_et_atteignables() -> void:
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		var reach := _reach(g, _blocked(g))
		for b in g.buildings:
			var n_s := 0
			for di in b.door_ids:
				var d := g.doors[di]
				var side := _door_side(b, d)
				if side == "":
					continue
				assert_eq(side, "S", "%s : porte extérieure %s côté %s (façade nord/est/ouest interdite)" % [b.name, d.cell, side])
				n_s += 1
				var out := d.cell + Vector2i.DOWN
				assert_eq(g.get_tile(out), T.STREET, "%s : rue devant la porte %s" % [b.name, d.cell])
				assert_true(reach.has(out), "%s : porte %s atteignable" % [b.name, d.cell])
			assert_gte(n_s, 1, "%s : au moins une porte sur la façade sud" % b.name)
			assert_eq(b.porch_side, Vector2i.DOWN, "%s : façade au sud" % b.name)


## Passages entre les wagons : franchissables (rue, sans décor) et reliant le nord au sud de la voie.
func test_passages_du_train_franchissables() -> void:
	for per_diff: Array in runs:
		var g := _floor(per_diff[0], 0)
		var blocked := _blocked(g)
		var reach := _reach(g, blocked)
		var gaps := 0
		for i in range(g.train.size() - 1):
			var ra: Rect2i = g.train[i]["rect"]
			var rb: Rect2i = g.train[i + 1]["rect"]
			if rb.position.x <= ra.end.x:
				continue
			gaps += 1
			for x in range(ra.end.x, rb.position.x):
				for y in range(ra.position.y, ra.end.y):
					var c := Vector2i(x, y)
					assert_true(FloorLayout.is_walkable_tile(g.get_tile(c)) and not blocked.has(c), "passage %s libre" % c)
					assert_true(reach.has(c), "passage %s atteignable" % c)
		assert_gte(gaps, 2, "au moins deux passages entre les wagons")


# --- Paquet pré-rendu (seed 642439) : plan, collisions « emprise rendue », occultation ----------

const PACK_SEED := 642439


func _pk_meta() -> Dictionary:
	var f := FileAccess.open(PrerenderBackdrop.PACK_ROOT + str(PACK_SEED) + "/map.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f != null else {}


func _pk_layout(seed_value: int) -> FloorLayout:
	var world: WorldData = load("res://data/worlds/world_01_far_west.tres")
	return DungeonGenerator.generate_floor(seed_value, world, 1, 0)


func test_paquet_correspond_au_plan() -> void:
	var m := _pk_meta()
	assert_false(m.is_empty(), "paquet présent")
	var L := _pk_layout(PACK_SEED)
	assert_eq(String(m.get("tiles_md5", "")), PrerenderBackdrop.layout_md5(L), "empreinte du plan identique (le jeu utilise le paquet)")
	assert_true(m.has("collision"), "couche « emprise rendue »")
	assert_true(m.has("occluders"), "tranches d'occultation")
	var n_sl := 0
	for e: Dictionary in m.get("occluders", []):
		assert_true(ResourceLoader.exists(PrerenderBackdrop.PACK_ROOT + str(PACK_SEED) + "/" + String(e["ids"])), "ids %s" % e["ids"])
		n_sl += (e["slices"] as Array).size()
	assert_gt(n_sl, 100, "tranches d'occultation (maisons, wagons, rochers)")
	# Chaque wagon a des tranches d'occultation sur ses rangées (on passe derrière).
	var rows := {}
	for e2: Dictionary in m.get("occluders", []):
		for sl: Array in e2["slices"]:
			rows[int(sl[0])] = true
	for t: Dictionary in L.train:
		var r: Rect2i = t["rect"]
		assert_true(rows.has(r.position.y) or rows.has(r.end.y - 1), "wagon %s occultant" % r)


## Obstacles rendus = cases bloquantes : chaque case praticable que le masque zénithal montre
## occupée (≥ 50 %) est couverte par la couche de collision (sauf cases rendues libres pour la
## connexité / abords protégés) ; chaque case murée d'obstacle (rocher, wagon, clôture) a un rendu.
func test_obstacles_rendus_egal_cases_bloquantes() -> void:
	var m := _pk_meta()
	var L := _pk_layout(PACK_SEED)
	var tex := load(PrerenderBackdrop.PACK_ROOT + str(PACK_SEED) + "/footprint.png") as Texture2D
	assert_not_null(tex, "masque d'emprise dans le paquet")
	if tex == null:
		return
	var img := tex.get_image()
	img.decompress()
	var M := int(m["margin"])
	var cov := _pk_collision_cov(m, L)
	var freed := {}
	for c: Array in (m.get("collision_stats", {}) as Dictionary).get("freed", []):
		freed[Vector2i(int(c[0]), int(c[1]))] = true
	var prot := _pk_protected(L)
	var bad: Array = []
	for y in L.size.y:
		for x in L.size.x:
			var c := Vector2i(x, y)
			if not FloorLayout.is_walkable_tile(L.get_tile(c)) or freed.has(c) or prot.has(c):
				continue
			var mc := _pk_mask_cov(img, c, M)
			if mc >= 0.5 and float(cov.get(c, 0.0)) < 0.4:
				bad.append(c)
	assert_eq(bad, [], "obstacle rendu sans collision")
	var empty: Array = []
	var cells := {}
	for rf: Dictionary in L.rock_formations:
		for c2: Vector2i in rf["cells"]:
			cells[c2] = true
	for t: Dictionary in L.train:
		for c3 in PkCells.of(t["rect"]):
			cells[c3] = true
	for fl: Array in L.fences:
		for c4: Vector2i in fl:
			cells[c4] = true
	for c5: Vector2i in cells:
		if _pk_mask_cov(img, c5, M) <= 0.0:
			empty.append(c5)
	assert_lte(empty.size(), 2, "cases murées sans rien de rendu : %s" % [empty])


## Passages entre wagons et abords (portes, escaliers, extraction) jamais couverts ; toutes les cases
## atteignables restent atteignables avec la couche de collision.
func test_collision_rendue_garde_les_passages() -> void:
	var m := _pk_meta()
	var L := _pk_layout(PACK_SEED)
	var cov := _pk_collision_cov(m, L)
	for c: Vector2i in _pk_protected(L):
		assert_lt(float(cov.get(c, 0.0)), 0.01, "abord protégé %s libre" % c)
	for k in range(L.train.size() - 1):
		var ra: Rect2i = L.train[k]["rect"]
		var rb: Rect2i = L.train[k + 1]["rect"]
		for x in range(ra.end.x, rb.position.x):
			for y in range(ra.position.y, ra.end.y):
				assert_lt(float(cov.get(Vector2i(x, y), 0.0)), 0.3, "passage du train %s franchissable" % Vector2i(x, y))
	var base := _pk_flood(L, {})
	var blocked := {}
	for c2: Vector2i in cov:
		if float(cov[c2]) >= 0.5:
			blocked[c2] = true
	var with := _pk_flood(L, blocked)
	var lost: Array = []
	for c3: Vector2i in base:
		if not blocked.has(c3) and not with.has(c3):
			lost.append(c3)
	assert_eq(lost, [], "cases devenues inaccessibles")


## Abords jamais bloqués par la couche « emprise rendue » (mêmes règles que compose.py).
static func _pk_protected(L: FloorLayout) -> Dictionary:
	var out := {}
	var around := func(c: Vector2i, r: int) -> void:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				out[c + Vector2i(dx, dy)] = true
	for d in L.doors:
		around.call(d.cell, 1)
		if not d.vertical:
			out[d.cell + Vector2i(0, 2)] = true
			out[d.cell + Vector2i(0, -2)] = true
	for st in L.stairs:
		around.call(st.cell, 1)
	for c: Vector2i in L.extraction_cells:
		around.call(c, 1)
	around.call(L.player_spawn, 1)
	return out


static func _pk_mask_cov(img: Image, c: Vector2i, M: int) -> float:
	var n := 0
	for dy in 4:
		for dx in 4:
			var px := img.get_pixel((c.x + M) * 4 + dx, (c.y + M) * 4 + dy)
			if px.r > 0.5 or px.g > 0.5:
				n += 1
	return n / 16.0


## Fraction de chaque case couverte par les rectangles de collision du paquet.
static func _pk_collision_cov(m: Dictionary, L: FloorLayout) -> Dictionary:
	var out := {}
	for r: Array in m.get("collision", []):
		var rr := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		for y in range(floori(rr.position.y / 64.0), ceili(rr.end.y / 64.0)):
			for x in range(floori(rr.position.x / 64.0), ceili(rr.end.x / 64.0)):
				var cr := Rect2(x * 64.0, y * 64.0, 64.0, 64.0).intersection(rr)
				out[Vector2i(x, y)] = float(out.get(Vector2i(x, y), 0.0)) + cr.get_area() / 4096.0
	return out


static func _pk_flood(L: FloorLayout, blocked: Dictionary) -> Dictionary:
	var seen := {L.player_spawn: true}
	var st: Array[Vector2i] = [L.player_spawn]
	while not st.is_empty():
		var c: Vector2i = st.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + d
			if seen.has(n) or blocked.has(n) or not FloorLayout.is_walkable_tile(L.get_tile(n)):
				continue
			seen[n] = true
			st.append(n)
	return seen


class PkCells:
	static func of(r: Rect2i) -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				out.append(Vector2i(x, y))
		return out
