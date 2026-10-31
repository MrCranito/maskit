extends GutTest
## Éclairage d'ambiance animé (AmbientLights) : répartition néons / voyants, animations pures,
## masquage des lumières animées hors du champ de vision (brouillard), intégration station et
## parking du centre commercial.

const MALL_WORLD := "res://data/worlds/world_03_mall.tres"


## Brouillard factice : seules les cases de `visible_cells` sont visibles.
class FakeFog extends Node2D:
	var visible_cells: Dictionary = {}

	func is_cell_visible(c: Vector2i) -> bool:
		return visible_cells.has(c)


func _light(cell: Vector2i, radius: float = 130.0) -> Array:
	return [FloorLayout.cell_to_world(cell), radius, Color(0.7, 0.9, 1.0), 1.0]


func test_split_flicker_moves_some_ceiling_lights_only() -> void:
	var glows: Array = []
	for i: int in 14:
		glows.append(_light(Vector2i(i, 0), 130.0))
	glows.append(_light(Vector2i(0, 5), 34.0))  # voyant de porte : jamais défaillant
	var res: Array = AmbientLights.split_flicker(glows, 7, 115.0, 155.0, 0)
	var keep: Array = res[0]
	var fl: Array = res[1]
	assert_eq(fl.size(), 2, "un plafonnier sur 7")
	assert_eq(keep.size() + fl.size(), glows.size(), "aucune lumière perdue")
	for g: Array in fl:
		assert_false(keep.has(g), "un néon défaillant n'est plus dans la couche statique")
	assert_eq(AmbientLights.split_flicker(glows, 0, 115.0, 155.0, 0)[1].size(), 0, "0 = aucun")


func test_pick_leds_uses_wall_panels() -> void:
	var glows: Array = [_light(Vector2i(1, 1), 70.0), _light(Vector2i(2, 1), 70.0), _light(Vector2i(3, 1), 70.0),
		_light(Vector2i(4, 1), 150.0)]
	var leds: Array = AmbientLights.pick_leds(glows, 3, 60.0, 80.0, 16.0, 0)
	assert_eq(leds.size(), 1)
	assert_eq(float(leds[0][1]), 16.0, "petit point vif")


func test_animations_stay_in_range() -> void:
	var dips := 0
	for i: int in 400:
		var t := float(i) * 0.013
		var f := AmbientLights.flicker_value(t, 9.0, 0.15)
		assert_true(f == 1.0 or is_equal_approx(f, 0.15))
		if f < 1.0:
			dips += 1
		var b := AmbientLights.blink_value(t, 1.3, 0.55)
		assert_true(b == 0.0 or b == 1.0)
		var a := AmbientLights.alarm_value(t, 2.2, 0.25)
		assert_between(a, 0.25, 1.0)
	assert_between(dips, 1, 120, "le néon grésille de temps en temps, sans être éteint")


func test_animated_lights_hidden_outside_vision() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var fog := FakeFog.new()
	fog.name = "FogOfWar"
	root.add_child(fog)
	var world := Node2D.new()
	root.add_child(world)
	var seen := Vector2i(3, 3)
	fog.visible_cells[seen] = true
	var al := AmbientLights.create(null, Rect2(), [_light(seen), _light(Vector2i(20, 20))], [], [])
	world.add_child(al)
	await wait_process_frames(3)
	var g: AmbientLights.Group = al.get_group(AmbientLights.GROUP_FLICKER)
	assert_not_null(g)
	assert_false(g.all_visible, "brouillard trouvé : dessin filtré")
	assert_eq(Array(g.shown), [1, 0], "seule la lumière dans le champ de vision est dessinée")
	fog.visible_cells[Vector2i(20, 20)] = true
	await wait_seconds(0.35)
	assert_eq(Array(g.shown), [1, 1], "elle réapparaît quand le joueur la voit")


func test_space_station_floor_has_ambient_lights() -> void:
	var world := load("res://data/worlds/world_02_space_station.tres") as WorldData
	var gen := preload("res://scripts/biomes/space_station/space_station_generator.gd")
	var l: FloorLayout = gen.generate_floor(4242, world, 2, -1)
	var b := SpaceStationBuilder.build(l, world)
	autofree(b)
	var al := b.get_node_or_null(^"AmbientLights") as AmbientLights
	assert_not_null(al, "couche de lumières animées présente")
	assert_gt(al.light_count(), 0)
	assert_null(b.get_node_or_null(^"Alarms"), "les gyrophares passent par AmbientLights")
	var tint := b.get_node_or_null(^"AmbientTint") as CanvasModulate
	assert_not_null(tint)
	assert_gt(tint.color.v, 0.85, "ambiance de la salle des machines remontée")


func test_mall_parking_gets_ceiling_lights() -> void:
	var world := load(MALL_WORLD) as WorldData
	var l: FloorLayout = MallGenerator.generate_floor(777, world, 2, -1)
	var b := MallBuilder.build(l, world)
	autofree(b)
	var al := b.get_node_or_null(^"AmbientLights") as AmbientLights
	assert_not_null(al, "néons qui grésillent au parking")
	var glows: Node = b.get_node_or_null(^"Glows")
	assert_gt((glows.get("glows") as Array).size(), 10, "flaques de lumière au sol")
	var l0: FloorLayout = MallGenerator.generate_floor(777, world, 2, 1)
	var b0 := MallBuilder.build(l0, world)
	autofree(b0)
	assert_null(b0.get_node_or_null(^"AmbientLights"), "étages commerçants inchangés")
