extends GutTest
## Tests du WorldBuilder sur make_sample() (et sur une carte générée si le générateur existe).

var _layout: FloorLayout
var _root: WorldBuilder


func before_each() -> void:
	_layout = FloorLayout.make_sample()
	_root = WorldBuilder.build(_layout, null)
	add_child_autofree(_root)


func test_root_api() -> void:
	assert_true(_root is Node2D)
	assert_true(_root.y_sort_enabled, "Racine triée en Y")
	assert_true(_root.has_signal("stairs_entered"))
	assert_true(_root.has_method("get_doors"))
	assert_true(_root.has_method("get_stairs_areas"))
	assert_true(_root.has_method("get_room_at_world"))
	assert_true(_root.has_method("set_stairs_cooldown"))


func test_doors_built() -> void:
	var doors := _root.get_doors()
	assert_eq(doors.size(), _layout.doors.size(), "Une porte par layout.doors")
	var locked := 0
	for d: DoorNode in doors:
		assert_true(d.is_in_group(&"doors"))
		assert_eq(d.position, Vector2((d.cell.x + 0.5) * 64.0, (d.cell.y + 1.0) * 64.0))
		if d.is_locked():
			locked += 1
			assert_eq(d.key_id, &"key_bank_vault")
	assert_eq(locked, 1, "Coffre-fort verrouillé")
	var saloon_door: DoorNode = null
	for d: DoorNode in doors:
		if d.cell == Vector2i(6, 12):
			saloon_door = d
	assert_not_null(saloon_door)
	assert_eq(saloon_door.kind, DoorNode.KIND_SALOON, "Porte battante sur la rue du saloon")


func test_wall_collisions_merged() -> void:
	var body := _root.get_wall_body()
	assert_not_null(body)
	assert_eq(body.collision_layer, 1, "Couche world")
	var shapes := body.get_child_count()
	var solid := 0
	for t: int in _layout.tiles:
		if FloorLayout.is_opaque_tile(t):
			solid += 1
	assert_gt(shapes, 4)
	assert_lt(shapes, solid / 4, "Rectangles fusionnés (pas une forme par case)")


func test_walls_cover_all_solid_cells() -> void:
	var space := _root.get_world_2d().direct_space_state
	await wait_physics_frames(2)
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = 1
	for c: Vector2i in [Vector2i(0, 0), Vector2i(2, 5), Vector2i(10, 4), Vector2i(20, 7), Vector2i(39, 29)]:
		q.position = FloorLayout.cell_to_world(c)
		assert_gt(space.intersect_point(q).size(), 0, "Case %s solide" % c)
	for c2: Vector2i in [Vector2i(5, 14), Vector2i(6, 6), Vector2i(31, 25)]:
		q.position = FloorLayout.cell_to_world(c2)
		assert_eq(space.intersect_point(q).size(), 0, "Case %s praticable" % c2)


func test_one_roof_per_building() -> void:
	var roofs := _root.get_roofs()
	assert_eq(roofs.size(), _layout.buildings.size())
	for r: BuildingRoof in roofs:
		assert_eq(r.z_index, 50)
		assert_false(r.z_as_relative)


func test_roof_fades_when_player_inside() -> void:
	var p := Node2D.new()
	p.add_to_group(&"player")
	p.position = FloorLayout.cell_to_world(Vector2i(6, 6))  # Salle du saloon
	add_child_autofree(p)
	await wait_seconds(0.5)
	var saloon_roof: BuildingRoof = _root.get_roofs()[0]
	assert_true(saloon_roof.is_player_inside())
	assert_lt(saloon_roof.modulate.a, 0.2, "Toit effacé")
	assert_almost_eq(_root.get_roofs()[1].modulate.a, 1.0, 0.01, "Autre toit visible")
	p.position = FloorLayout.cell_to_world(Vector2i(3, 14))
	await wait_seconds(0.5)
	assert_almost_eq(saloon_roof.modulate.a, 1.0, 0.01, "Toit revenu")


func test_stairs_areas() -> void:
	var areas := _root.get_stairs_areas()
	assert_eq(areas.size(), _layout.stairs.size())
	var st: Variant = areas[0].get_meta(&"stairs")
	assert_true(st is FloorLayout.Stairs)
	assert_eq((st as FloorLayout.Stairs).cell, Vector2i(13, 4))
	assert_eq(areas[0].collision_mask & 2, 2, "Détecte le joueur")


func test_stairs_signal_respects_cooldown() -> void:
	watch_signals(_root)
	var p := CharacterBody2D.new()
	p.add_to_group(&"player")
	p.collision_layer = 2
	var cs := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 10.0
	cs.shape = c
	p.add_child(cs)
	p.position = FloorLayout.cell_to_world(Vector2i(13, 4))
	add_child_autofree(p)
	await wait_physics_frames(4)
	assert_signal_not_emitted(_root, "stairs_entered", "Ignoré juste après le build")
	_root.set_stairs_cooldown(0.0)
	p.position = FloorLayout.cell_to_world(Vector2i(13, 7))
	await wait_physics_frames(3)
	p.position = FloorLayout.cell_to_world(Vector2i(13, 4))
	await wait_physics_frames(4)
	assert_signal_emitted(_root, "stairs_entered")


func test_room_at_world() -> void:
	var r := _root.get_room_at_world(FloorLayout.cell_to_world(Vector2i(12, 5)))
	assert_not_null(r)
	assert_eq(r.name, "Arrière-salle")
	var street := _root.get_room_at_world(FloorLayout.cell_to_world(Vector2i(20, 14)))
	assert_true(street.outdoor)
	assert_null(_root.get_room_at_world(Vector2(-100, -100)))


func test_props_built() -> void:
	var props := _root.get_props()
	assert_eq(props.size(), _layout.prop_spawns.size())
	var blocking := 0
	for p: WorldProp in props:
		assert_false(p.is_placeholder, "Décor %s connu" % p.kind)
		if p.is_blocking():
			blocking += 1
			assert_eq(p.body.collision_layer, 1)
	assert_gt(blocking, 0, "Chariot / bar bloquent")


func test_unknown_prop_is_placeholder() -> void:
	var p := WorldProp.create(&"licorne_inconnue", Vector2.ZERO)
	add_child_autofree(p)
	assert_true(p.is_placeholder)
	assert_false(p.is_blocking())


func test_all_world_prop_kinds_have_sprite() -> void:
	var world: Resource = load("res://data/worlds/world_01_far_west.tres") if ResourceLoader.exists("res://data/worlds/world_01_far_west.tres") else null
	var kinds: Array = [&"cactus", &"hitching_post", &"water_trough", &"wagon", &"wagon_wheel", &"barrel",
		&"saloon_bar", &"piano", &"poker_table", &"bed", &"desk", &"jail_bars", &"rail_track",
		&"mine_cart", &"lantern", &"wanted_poster"]
	if world != null:
		for k: Variant in world.get("prop_kinds"):
			if not kinds.has(k):
				kinds.append(k)
	for k: StringName in kinds:
		assert_true(WorldProp.is_known_kind(k), "Décor %s défini" % k)
		assert_not_null(WorldProp.get_texture(k), "Sprite %s" % k)


func test_extraction_marker() -> void:
	assert_eq(_root.get_tree().get_nodes_in_group(&"extraction_markers").size(), 1)


func test_build_performance() -> void:
	var t0 := Time.get_ticks_usec()
	var r := WorldBuilder.build(FloorLayout.make_sample(), null)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	r.free()
	gut.p("Build make_sample : %.1f ms" % ms)
	assert_lt(ms, 200.0, "Build < 200 ms")


func test_generated_floors_build() -> void:
	var gen_path := "res://scripts/dungeon/dungeon_generator.gd"
	var world_path := "res://data/worlds/world_01_far_west.tres"
	if not ResourceLoader.exists(gen_path) or not ResourceLoader.exists(world_path):
		pass_test("Générateur absent")
		return
	var gen: Script = load(gen_path)
	var floors: Array = gen.call("generate_run", 5, load(world_path), 3)
	assert_gt(floors.size(), 0)
	for L: FloorLayout in floors:
		var t0 := Time.get_ticks_usec()
		var r := WorldBuilder.build(L, load(world_path))
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		gut.p("Build étage %d : %.1f ms" % [L.floor_index, ms])
		assert_eq(r.get_doors().size(), L.doors.size())
		assert_eq(r.get_roofs().size(), L.buildings.size())
		assert_eq(r.get_stairs_areas().size(), L.stairs.size())
		assert_lt(ms, 400.0)
		r.free()
