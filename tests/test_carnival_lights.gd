extends GutTest
## Éclairage du Carnaval hanté (scripts/biomes/haunted_carnival/hc_lights.gd) : lumières calculées
## depuis le plan (lampadaires, guirlandes, manèges, stands), couche « Lights » gardée sur le fond
## pré-rendu, fond éclairci, teinte de nuit propre à la carte, lumières fixes jamais masquées par
## le brouillard.

const WORLD := "res://data/worlds/world_04_haunted_carnival.tres"
const GEN := "res://scripts/biomes/haunted_carnival/hc_generator.gd"


class FakeFog extends Node2D:
	func is_cell_visible(_c: Vector2i) -> bool:
		return false


func _ground_floor() -> FloorLayout:
	var floors: Array = (load(GEN) as Script).call(&"generate_run", 42, load(WORLD), 1)
	for L: FloorLayout in floors:
		if L.floor_index == 0:
			return L
	return null


func test_lumieres_calculees_depuis_le_plan() -> void:
	var L := _ground_floor()
	assert_not_null(L)
	var lamps := 0
	for sp: FloorLayout.Spawn in L.prop_spawns:
		if sp.kind == HcLights.LAMP:
			lamps += 1
	assert_gt(lamps, 0, "des lampadaires sur le plan")
	var lights: Dictionary = HcLights.compute(L)
	var steady: Array = lights["steady"]
	var flicker: Array = lights["flicker"]
	var blink: Array = lights["blink"]
	assert_eq(steady.size() + flicker.size() >= lamps * 2, true, "flaque + tête par lampadaire")
	assert_gt(flicker.size(), 0, "quelques lampadaires grésillent")
	assert_gt(blink.size(), 0, "ampoules des manèges qui clignotent")
	assert_gt(steady.size(), lamps * 2 + 20, "guirlandes, stands, place, portail")
	var size := Vector2(L.size) * float(FloorLayout.TILE_SIZE)
	for l: Array in steady + flicker + blink:
		assert_eq(l.size(), 4)
		assert_gt(float(l[1]), 0.0, "rayon")
		assert_gt(float(l[3]), 0.0, "intensité")
		var p: Vector2 = l[0]
		assert_true(Rect2(Vector2.ZERO, size).grow(400.0).has_point(p), "lumière sur la carte (%s)" % p)
	assert_true(HcLights.compute(null)["steady"].is_empty())


func test_couche_gardee_sur_le_fond_pre_rendu() -> void:
	var L := _ground_floor()
	var b := HauntedCarnivalBuilder.build(L, load(WORLD))
	add_child_autofree(b)
	var lights := b.get_node_or_null(^"Lights") as AmbientLights
	assert_not_null(lights, "couche Lights")
	assert_gt(lights.light_count(), 0)
	b.prerender_hide()
	assert_true(lights.visible, "visible sur le fond pré-rendu (Glows est masqué)")
	var t := b.prerender_tint()
	assert_gt(t.r + t.g + t.b, 3.0, "fond pré-rendu éclairci")


func test_lumieres_fixes_jamais_masquees_par_le_brouillard() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var fog := FakeFog.new()
	fog.name = "FogOfWar"
	root.add_child(fog)
	var lit := [[Vector2(100, 100), 120.0, Color.WHITE, 1.0]]
	var al := AmbientLights.create(null, Rect2(), lit.duplicate(), [], [], lit.duplicate())
	root.add_child(al)
	al._refresh_visibility()
	assert_true(al.get_group(AmbientLights.GROUP_STEADY).all_visible, "fixe : toujours dessinée")
	assert_false(al.get_group(AmbientLights.GROUP_FLICKER).all_visible, "animée : masquée hors vue")


func test_teinte_de_nuit_propre_a_la_carte() -> void:
	var card := load("res://data/maps/perm_carnaval_hante.tres") as MapCard
	assert_true(card.is_night(), "étiquette Nuit gardée")
	var t: Variant = card.get_mod("night_tint")
	assert_true(t is Color, "teinte propre au carnaval")
	var def: Color = Balance.get_value("maps", "night_tint", Color(0.5, 0.55, 0.8))
	assert_gt((t as Color).r + (t as Color).g, def.r + def.g, "plus douce que la nuit noire par défaut")
	var other := MapCard.new()
	assert_null(other.get_mod("night_tint"), "les autres cartes gardent [maps] night_tint")
