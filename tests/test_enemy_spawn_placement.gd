extends GutTest
## Non-régression : placement des ennemis sur les cartes pré-rendues (Raid.shuffle_enemy_spawns).
## Avant le correctif, le tirage d'une case « libre de sa salle » prenait n'importe quelle case de la
## boîte de la salle : sur le Carnaval hanté, la place du chapiteau (boîte de 50×45 cases qui
## englobe tout le parc) envoyait ses ennemis dans les stands fermés et dans l'arène du boss ; sur
## les Terres gelées, environ un ennemi sur quatre tombait dans l'emprise rendue (murs épais,
## décors solides) où il restait coincé, inatteignable et intouchable.

const MAPS := [
	["haunted_carnival", "res://data/worlds/world_04_haunted_carnival.tres", "res://scripts/biomes/haunted_carnival/hc_generator.gd"],
	["frozen_lands", "res://data/worlds/world_05_frozen_lands.tres", "res://scripts/biomes/frozen_lands/frozen_lands_generator.gd"],
	["egypt_pyramids", "res://data/worlds/world_06_egypt_pyramids.tres", "res://scripts/biomes/egypt_pyramids/eg_generator.gd"],
	["far_west", "res://data/worlds/world_01_far_west.tres", "res://scripts/dungeon/dungeon_generator.gd"],
	["space_station", "res://data/worlds/world_02_space_station.tres", "res://scripts/biomes/space_station/space_station_generator.gd"],
	["mall", "res://data/worlds/world_03_mall.tres", "res://scripts/biomes/mall/mall_generator.gd"],
]


## [layout pré-rendu (étage 0), emprise rendue] pour un biome, ou [] si pas de paquet.
func _floor(biome: StringName, world_path: String, gen_path: String, difficulty: int) -> Array:
	var seeds := PrerenderBackdrop.available_seeds(biome)
	if seeds.is_empty():
		return []
	var world := load(world_path) as WorldData
	var gen := load(gen_path) as Script
	var floors: Array = gen.call("generate_run", seeds[0], world, difficulty)
	var l: FloorLayout = null
	for f: FloorLayout in floors:
		if f.floor_index == 0:
			l = f
	if l == null:
		return []
	var pb := PrerenderBackdrop.create(seeds[0], l, biome)
	if pb == null:
		return []
	var rects := pb.collision_rects()
	pb.free()
	return [l, rects]


func test_aucun_ennemi_dans_l_emprise_rendue() -> void:
	for m: Array in MAPS:
		var r := _floor(StringName(m[0]), m[1], m[2], 3)
		if r.is_empty():
			continue
		var l: FloorLayout = r[0]
		var rects: Array[Rect2] = r[1]
		var solid := Raid.blocked_cells(rects, Balance.get_float("raid", "spawn_clearance", 12.0))
		for s in 4:
			Raid.shuffle_enemy_spawns(l, hash([s, "test"]), rects)
			var inside: Array = []
			for sp2: FloorLayout.Spawn in l.enemy_spawns:
				if solid.has(sp2.cell):
					inside.append(sp2.cell)
			assert_eq(inside, [], "%s, tirage %d : ennemis dans l'emprise rendue" % [m[0], s])


func test_ennemis_restent_dans_leur_salle() -> void:
	for m: Array in MAPS:
		var r := _floor(StringName(m[0]), m[1], m[2], 3)
		if r.is_empty():
			continue
		var l: FloorLayout = r[0]
		var before := {}
		for sp: FloorLayout.Spawn in l.enemy_spawns:
			before[sp] = sp.cell
		Raid.shuffle_enemy_spawns(l, 12345, r[1])
		var bad: Array = []
		var into_boss := 0
		for sp2: FloorLayout.Spawn in l.enemy_spawns:
			if sp2.cell == before[sp2] or sp2.room_id < 0:
				continue
			var room := l.get_room(sp2.room_id)
			var got := Raid.cell_room_id(l, sp2.cell)
			if got != sp2.room_id:
				bad.append([String(sp2.kind), sp2.cell, room.name if room != null else "?"])
			var gr := l.get_room(got)
			if gr != null and gr.type == FloorLayout.ROOM_BOSS and (room == null or room.type != FloorLayout.ROOM_BOSS):
				into_boss += 1
		assert_eq(bad, [], "%s : ennemis déplacés hors de leur salle" % m[0])
		assert_eq(into_boss, 0, "%s : aucun ennemi envoyé dans l'arène du boss" % m[0])


func test_tirage_deterministe() -> void:
	var a := _floor(&"haunted_carnival", MAPS[0][1], MAPS[0][2], 2)
	var b := _floor(&"haunted_carnival", MAPS[0][1], MAPS[0][2], 2)
	if a.is_empty():
		pending("pas de paquet pré-rendu du Carnaval")
		return
	Raid.shuffle_enemy_spawns(a[0], 777, a[1])
	Raid.shuffle_enemy_spawns(b[0], 777, b[1])
	var ca: Array = (a[0] as FloorLayout).enemy_spawns.map(func(s: FloorLayout.Spawn) -> Vector2i: return s.cell)
	var cb: Array = (b[0] as FloorLayout).enemy_spawns.map(func(s: FloorLayout.Spawn) -> Vector2i: return s.cell)
	assert_eq(ca, cb, "même graine → mêmes cases (hôte et invité en coop)")
	var moved := 0
	var base := _floor(&"haunted_carnival", MAPS[0][1], MAPS[0][2], 2)
	for i in ca.size():
		if ca[i] != (base[0] as FloorLayout).enemy_spawns[i].cell:
			moved += 1
	assert_gt(moved, ca.size() / 3, "le tirage déplace toujours une bonne part des ennemis (%d / %d)" % [moved, ca.size()])


func test_cases_bloquees() -> void:
	var cells := Raid.blocked_cells([Rect2(64, 64, 128, 64)] as Array[Rect2], 0.0)
	assert_true(cells.has(Vector2i(1, 1)) and cells.has(Vector2i(2, 1)), "centres couverts")
	assert_false(cells.has(Vector2i(0, 1)) or cells.has(Vector2i(1, 2)), "centres hors du rectangle")
