extends GutTest
## Extractions d'un étage (scripts/dungeon/extraction_plan.gd) : une permanente au bout du
## parcours, 3 temporaires triées par distance du départ qui ferment dans l'ordre (la plus
## proche d'abord), trappes d'urgence verrouillées hors carte, canalisation impossible /
## interrompue sur une zone fermée, déterminisme par seed.

const WORLDS := {
	"far_west": ["res://data/worlds/world_01_far_west.tres", "res://scripts/dungeon/dungeon_generator.gd"],
	"space_station": ["res://data/worlds/world_02_space_station.tres", "res://scripts/biomes/space_station/space_station_generator.gd"],
	"mall": ["res://data/worlds/world_03_mall.tres", "res://scripts/biomes/mall/mall_generator.gd"],
}
const SEEDS := [1, 42, 777]

var _cache: Dictionary = {}


func _floors(key: String, sd: int) -> Array:
	var k := "%s_%d" % [key, sd]
	if not _cache.has(k):
		var w := load(WORLDS[key][0]) as WorldData
		var gen := load(WORLDS[key][1]) as Script
		var floors: Array = gen.call(&"generate_run", sd, w, 1)
		for L: FloorLayout in floors:
			ExtractionPlan.apply(L, hash([sd, L.floor_index, "extraction"]))
		_cache[k] = floors
	return _cache[k]


static func _temps(L: FloorLayout) -> Array:
	return L.extraction_specs.filter(func(s: Variant) -> bool: return s.kind == ExtractionPlan.KIND_TEMPORARY)


static func _of(L: FloorLayout, kind: StringName) -> Array:
	return L.extraction_specs.filter(func(s: Variant) -> bool: return s.kind == kind)


func test_permanente_temporaires_trappes_sur_les_trois_cartes() -> void:
	var want := int(Balance.get_value("extraction", "temporary_zones", 3))
	for key: String in WORLDS:
		var with_extraction := 0
		for sd: int in SEEDS:
			for L: FloorLayout in _floors(key, sd):
				if L.extraction_cells.is_empty():
					assert_true(L.extraction_specs.is_empty(), "%s %d étage %d : pas d'extraction" % [key, sd, L.floor_index])
					continue
				with_extraction += 1
				var perm := _of(L, ExtractionPlan.KIND_PERMANENT)
				assert_eq(perm.size(), 1, "%s %d étage %d : une permanente" % [key, sd, L.floor_index])
				assert_eq(perm[0].closes_at, INF, "la permanente ne ferme jamais")
				var n := _temps(L)
				assert_eq(n.size(), want, "%s %d étage %d : %d temporaires" % [key, sd, L.floor_index, want])
				var names := {}
				for i in n.size():
					var s: ExtractionPlan.Spec = n[i]
					assert_eq(s.rank, i)
					assert_eq(s.opens_at, 0.0, "ouverte dès le départ")
					assert_lt(s.closes_at, INF, "une temporaire ferme")
					assert_false(names.has(s.name), "noms uniques (%s)" % s.name)
					names[s.name] = true
					assert_true(s.option in ["B", "C", "D", "+"], "option de placement (%s)" % s.option)
					for c: Vector2i in s.cells:
						assert_true(FloorLayout.is_walkable_tile(L.get_tile(c)), "%s : case praticable" % s.name)
						assert_true(L.extraction_cells.has(c))
					if i > 0:
						var p: ExtractionPlan.Spec = n[i - 1]
						assert_gte(s.distance, p.distance, "triées par distance")
						assert_gt(s.closes_at, p.closes_at, "la plus proche ferme la première")
						assert_gte(s.closes_at - p.closes_at, Balance.get_float("extraction", "lifetime_min_gap", 75.0) - 0.01)
				# Trappes : hors des cases d'extraction (pas sur la carte).
				for h: ExtractionPlan.Spec in _of(L, ExtractionPlan.KIND_HATCH):
					for c2: Vector2i in h.cells:
						assert_false(L.extraction_cells.has(c2), "trappe hors des cases d'extraction")
						assert_true(FloorLayout.is_walkable_tile(L.get_tile(c2)))
					assert_eq(h.closes_at, INF)
		assert_gt(with_extraction, 0, "%s : des étages avec extraction" % key)


func test_permanente_au_bout_du_parcours() -> void:
	for key: String in WORLDS:
		for L: FloorLayout in _floors(key, 42):
			var perm := _of(L, ExtractionPlan.KIND_PERMANENT)
			if perm.is_empty() or perm[0].option != "A":
				continue
			var p: ExtractionPlan.Spec = perm[0]
			for s: ExtractionPlan.Spec in _temps(L):
				if s.option == "B":
					assert_lt(s.distance, p.distance, "%s étage %d : mi-parcours avant le bout" % [key, L.floor_index])


func test_trappes_presentes() -> void:
	var total := 0
	for key: String in WORLDS:
		for sd: int in SEEDS:
			for L: FloorLayout in _floors(key, sd):
				if not L.extraction_cells.is_empty():
					var h := _of(L, ExtractionPlan.KIND_HATCH)
					assert_lte(h.size(), ExtractionPlan.hatch_count(L))
					total += h.size()
	assert_gt(total, 0, "des trappes d'urgence sur les cartes")


func test_zones_ajoutees_sur_des_cases_libres() -> void:
	for key: String in WORLDS:
		for L: FloorLayout in _floors(key, 42):
			var busy := {}
			for list: Array in [L.prop_spawns, L.container_spawns, L.hiding_spot_spawns]:
				for sp: FloorLayout.Spawn in list:
					for c: Vector2i in FloorLayout.spawn_cells(sp):
						busy[c] = true
			for s: ExtractionPlan.Spec in L.extraction_specs:
				var free := true
				for c: Vector2i in s.cells:
					if busy.has(c):
						free = false
				# Les zones d'origine des générateurs sont déjà réservées par les populators.
				assert_true(free, "%s étage %d zone %s sans décor ni conteneur" % [key, L.floor_index, s.name])


func test_deterministe_par_seed() -> void:
	for key: String in WORLDS:
		var w := load(WORLDS[key][0]) as WorldData
		var gen := load(WORLDS[key][1]) as Script
		var a: Array = gen.call(&"generate_run", 777, w, 1)
		var b: Array = gen.call(&"generate_run", 777, w, 1)
		for i in a.size():
			ExtractionPlan.apply(a[i], hash([777, a[i].floor_index, "extraction"]))
			ExtractionPlan.apply(b[i], hash([777, b[i].floor_index, "extraction"]))
			assert_eq(_sig(a[i]), _sig(b[i]), "%s étage %d : mêmes zones (hôte / invité)" % [key, a[i].floor_index])


static func _sig(L: FloorLayout) -> String:
	var parts := PackedStringArray()
	for s: ExtractionPlan.Spec in L.extraction_specs:
		parts.append("%s|%s|%s|%s|%s" % [s.name, str(s.cells), s.opens_at, s.closes_at, s.kind])
	return ";".join(parts)


func test_fermeture_dans_l_ordre() -> void:
	var L: FloorLayout = null
	for f: FloorLayout in _floors("far_west", 1):
		if f.floor_index == 0:
			L = f
	var zones := ExtractionZone.create_from_specs(L.extraction_specs)
	for z in zones:
		add_child_autofree(z)
	var n := zones.filter(func(z: ExtractionZone) -> bool: return z.kind == ExtractionPlan.KIND_TEMPORARY)
	var perm := zones.filter(func(z: ExtractionZone) -> bool: return z.is_permanent())
	var hatches := zones.filter(func(z: ExtractionZone) -> bool: return z.is_hatch())
	for z: ExtractionZone in zones:
		z.update_clock(0.0)
	for z: ExtractionZone in n:
		assert_true(z.is_open(), "%s ouverte au départ" % z.zone_name)
	for h: ExtractionZone in hatches:
		assert_false(h.is_open(), "trappe verrouillée au départ")
	var warn := Balance.get_float("extraction", "close_warning", 30.0)
	var first: ExtractionZone = n[0]
	first.update_clock(first.closes_at - warn + 1.0)
	assert_eq(first.state, ExtractionZone.State.CLOSING, "avertissement avant fermeture")
	for i in n.size():
		var t: float = n[i].closes_at + 0.1
		for z3: ExtractionZone in zones:
			z3.update_clock(t)
		for j in n.size():
			assert_eq(n[j].is_open(), j > i, "t=%d : zone %d" % [int(t), j])
		assert_eq(n[i].get_timer_text(), "FERMÉE")
	assert_eq(perm.size(), 1)
	assert_true(perm[0].is_open(), "la permanente reste ouverte quand tout est fermé")
	assert_eq(perm[0].get_timer_text(), "", "pas de minuteur sur la permanente")


# --- Raid : canalisation sur zone fermée ---------------------------------------------------

func test_canalisation_impossible_puis_interrompue_sur_zone_fermee() -> void:
	var saved_profile: Dictionary = Profile.to_dict()
	var saved_sm: Dictionary = (SaveManager.data as Dictionary).duplicate(true)
	var raid := (load("res://scenes/dungeon/raid.tscn") as PackedScene).instantiate() as Raid
	add_child_autofree(raid)
	await wait_physics_frames(3)
	if raid.layout.extraction_specs.is_empty():
		pending("pas d'extraction sur cet étage")
		Profile.from_dict(saved_profile)
		SaveManager.data = saved_sm
		return
	assert_gte(raid.extraction_zones.size(), 4, "permanente + trois temporaires à l'étage")
	var z: ExtractionZone = raid.extraction_zones[0]
	assert_eq(z.kind, ExtractionPlan.KIND_TEMPORARY, "les temporaires d'abord")
	var cell: Vector2i = z.cells[0]
	raid.place_player(cell)
	# Canalisation en cours, puis la zone ferme : interrompue.
	raid.raid_clock = z.closes_at - 2.0
	raid._update_zone_clocks()
	raid._update_extraction(cell, 0.5)
	assert_true(raid.is_extracting(), "canalisation sur zone ouverte")
	raid.raid_clock = z.closes_at + 0.01
	raid._update_zone_clocks()
	assert_false(raid.is_extracting(), "interrompue à la fermeture")
	assert_string_contains(raid.get_toast_text(), "fermée")
	# Zone fermée : plus de canalisation possible.
	raid._update_extraction(cell, 0.5)
	raid._update_extraction(cell, Raid.extraction_channel_time())
	assert_false(raid.is_extracting(), "impossible sur zone fermée")
	assert_false(raid.is_raid_over())
	# Tout est fermé : seule la permanente reste ouverte (les trappes sont verrouillées).
	raid.raid_clock = 1.0e6
	raid._update_zone_clocks()
	var open := raid.get_open_extraction_zones()
	assert_eq(open.size(), 1, "seule la permanente reste ouverte")
	if open.size() == 1:
		assert_true(open[0].is_permanent())
	Profile.from_dict(saved_profile)
	SaveManager.data = saved_sm
