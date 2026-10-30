extends GutTest
## Tests du brouillard de guerre (FogOfWar) sur FloorLayout.make_sample().

var _layout: FloorLayout
var _fog: FogOfWar
var _open_doors: Dictionary = {}


func before_each() -> void:
	_open_doors.clear()
	_layout = FloorLayout.make_sample()
	_fog = FogOfWar.new()
	add_child_autofree(_fog)
	_fog.setup(_layout)
	_fog.set_door_query(_door_open)


func _door_open(c: Vector2i) -> bool:
	return bool(_open_doors.get(c, false))


func _at(c: Vector2i) -> Vector2:
	return FloorLayout.cell_to_world(c)


func _count_visible_in(r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if _fog.is_cell_visible(Vector2i(x, y)):
				n += 1
	return n


func test_initial_state_unseen() -> void:
	assert_false(_fog.is_cell_visible(_layout.player_spawn))
	assert_false(_fog.is_cell_explored(_layout.player_spawn))
	assert_eq(_fog.z_index, 80, "Couche brouillard")


func test_street_visible_saloon_hidden_when_door_closed() -> void:
	_fog.update_from(_at(_layout.player_spawn))
	assert_true(_fog.is_cell_visible(_layout.player_spawn), "Case du joueur visible")
	for c: Vector2i in [Vector2i(5, 14), Vector2i(8, 15), Vector2i(3, 16), Vector2i(10, 13)]:
		assert_true(_fog.is_cell_visible(c), "Rue proche visible %s" % c)
	assert_true(_fog.is_cell_visible(Vector2i(6, 12)), "La porte (fermée) se voit")
	assert_true(_fog.is_cell_visible(Vector2i(4, 12)), "La face du mur se voit")
	assert_eq(_count_visible_in(Rect2i(3, 3, 7, 9)), 0, "Salle du saloon cachée (porte fermée)")
	assert_false(_fog.is_cell_visible(Vector2i(25, 14)), "Hors du rayon de vue")


func test_opening_door_reveals_part_of_room() -> void:
	_fog.update_from(_at(Vector2i(6, 14)))
	assert_eq(_count_visible_in(Rect2i(3, 3, 7, 9)), 0)
	_open_doors[Vector2i(6, 12)] = true
	_fog.update_from(_at(Vector2i(6, 14)))
	assert_eq(_count_visible_in(Rect2i(3, 3, 7, 9)), 0, "Pas de recalcul sans invalidate ni changement de case")
	_fog.invalidate()
	_fog.update_from(_at(Vector2i(6, 14)))
	var n := _count_visible_in(Rect2i(3, 3, 7, 9))
	assert_gt(n, 0, "Une partie de la salle devient visible")
	assert_lt(n, 7 * 9, "Depuis la rue, seule une partie de l'intérieur est visible")
	assert_false(_fog.is_cell_visible(Vector2i(12, 6)), "Arrière-salle toujours cachée")


func test_inside_cannot_see_through_building_walls() -> void:
	_open_doors[Vector2i(6, 12)] = true
	_fog.update_from(_at(Vector2i(6, 6)))
	assert_true(_fog.is_cell_visible(Vector2i(4, 4)), "Salle visible de l'intérieur")
	assert_true(_fog.is_cell_visible(Vector2i(2, 6)), "Mur d'enceinte visible")
	assert_false(_fog.is_cell_visible(Vector2i(1, 6)), "Pas de vue à travers le mur")
	assert_false(_fog.is_cell_visible(Vector2i(12, 6)), "Cloison + porte fermée")
	assert_false(_fog.is_cell_visible(Vector2i(16, 6)), "Rien hors du bâtiment à travers le mur")


func test_seen_then_left_is_explored() -> void:
	_fog.update_from(_at(_layout.player_spawn))
	var c := Vector2i(5, 15)
	assert_true(_fog.is_cell_visible(c))
	_fog.update_from(_at(Vector2i(32, 26)))
	assert_false(_fog.is_cell_visible(c), "Plus en vue")
	assert_true(_fog.is_cell_explored(c), "Mais explorée")
	assert_eq(_fog.get_cell_state(c), 1)
	assert_eq(_fog.get_cell_state(Vector2i(13, 22)), 0, "Intérieur du shérif jamais vu")


func test_state_roundtrip() -> void:
	_fog.update_from(_at(_layout.player_spawn))
	_fog.update_from(_at(Vector2i(20, 14)))
	var state := _fog.get_state()
	assert_eq(state.size(), _layout.size.x * _layout.size.y)
	var fog2 := FogOfWar.new()
	add_child_autofree(fog2)
	fog2.setup(_layout)
	assert_false(fog2.is_cell_explored(Vector2i(5, 15)))
	fog2.set_state(state)
	for y in _layout.size.y:
		for x in _layout.size.x:
			var c := Vector2i(x, y)
			if fog2.is_cell_explored(c) != _fog.is_cell_explored(c):
				fail_test("Exploration différente en %s" % c)
				return
	assert_true(fog2.is_cell_explored(Vector2i(5, 15)))
	assert_false(fog2.is_cell_visible(Vector2i(5, 15)), "set_state ne restaure que l'exploration")


func test_reveal_all() -> void:
	_fog.reveal_all(true)
	assert_true(_fog.is_cell_visible(Vector2i(26, 5)))
	_fog.reveal_all(false)
	assert_false(_fog.is_cell_visible(Vector2i(26, 5)))


func test_hideable_nodes() -> void:
	_fog.update_from(_at(_layout.player_spawn))
	var near := Node2D.new()
	near.add_to_group(FogOfWar.GROUP_HIDEABLE)
	near.position = _at(Vector2i(5, 14))
	var far := Node2D.new()
	far.add_to_group(FogOfWar.GROUP_HIDEABLE)
	far.position = _at(Vector2i(6, 6))
	var hero := Node2D.new()
	hero.add_to_group(FogOfWar.GROUP_HIDEABLE)
	hero.add_to_group(&"player")
	hero.position = _at(Vector2i(26, 5))
	add_child_autofree(near)
	add_child_autofree(far)
	add_child_autofree(hero)
	_fog.update_hideables()
	assert_true(near.visible, "Ennemi en vue affiché")
	assert_false(far.visible, "Ennemi derrière la porte caché")
	assert_true(hero.visible, "Le joueur n'est jamais caché")
	_open_doors[Vector2i(6, 12)] = true
	_fog.invalidate()
	_fog.update_from(_at(Vector2i(6, 12)))
	_fog.update_hideables()
	assert_true(far.visible, "Réaffiché une fois en vue")


func test_explored_out_of_view_hides_entities() -> void:
	# Une case explorée puis quittée retombe dans le brouillard : ses entités sont cachées.
	_fog.update_from(_at(_layout.player_spawn))
	var c := Vector2i(5, 15)
	var enemy := Node2D.new()
	enemy.add_to_group(FogOfWar.GROUP_HIDEABLE)
	enemy.position = _at(c)
	add_child_autofree(enemy)
	_fog.update_hideables()
	assert_true(enemy.visible, "En vue")
	_fog.update_from(_at(Vector2i(32, 26)))
	_fog.update_hideables()
	assert_true(_fog.is_cell_explored(c), "Mémoire conservée")
	assert_false(enemy.visible, "Exploré hors vue = brouillard, ennemi caché")


func test_visibility_polygon() -> void:
	_fog.update_from(_at(_layout.player_spawn))
	var poly := _fog.get_visibility_polygon()
	assert_gt(poly.size(), 8, "Polygone construit")
	assert_true(_fog.is_world_point_visible(_at(Vector2i(8, 15))), "Rue en vue")
	assert_false(_fog.is_world_point_visible(_at(Vector2i(6, 6))), "Saloon (porte fermée) hors du polygone")
	assert_false(_fog.is_world_point_visible(_at(Vector2i(13, 22))), "Shérif derrière son mur")
	assert_false(_fog.is_world_point_visible(_at(Vector2i(30, 14))), "Hors du rayon de vue")
	# Le polygone s'arrête sur la face des murs ; les cases de mur vues sont
	# révélées entières dans le masque (rangées fusionnées), pas au-delà.
	assert_true(_fog.is_world_point_visible(_at(Vector2i(4, 13)) + Vector2(0, -28)), "Jusqu'à la face du mur")
	assert_false(_fog.is_world_point_visible(_at(Vector2i(4, 11))), "Pas derrière le mur")
	var wall_seen := false
	for r: Rect2 in _fog._wall_rects:
		if r.has_point(_at(Vector2i(4, 12))):
			wall_seen = true
	assert_true(wall_seen, "Case de mur vue ajoutée au masque")


func test_polygon_follows_small_moves_and_invalidate() -> void:
	_fog.update_from(_at(Vector2i(6, 14)))
	var p0 := _fog.get_visibility_polygon().duplicate()
	_fog.update_from(_at(Vector2i(6, 14)) + Vector2(1.0, 0.0))
	assert_eq(_fog.get_visibility_polygon(), p0, "Mouvement < seuil : pas de recalcul")
	_open_doors[Vector2i(6, 12)] = true
	_fog.invalidate()
	_fog.update_from(_at(Vector2i(6, 14)))
	assert_true(_fog.is_world_point_visible(_at(Vector2i(6, 10))), "Porte ouverte : on voit à travers")
	assert_false(_fog.is_world_point_visible(_at(Vector2i(4, 4))), "Pas tout le saloon depuis la rue")


func test_render_nodes() -> void:
	_fog.update_from(_at(_layout.player_spawn))
	var vp := _fog.get_node_or_null("FogMask") as SubViewport
	assert_not_null(vp, "Masque de visibilité en SubViewport")
	assert_ne(vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "Masque jamais rafraîchi à chaque frame")
	assert_true(_fog.material is ShaderMaterial, "Shader de brouillard sur le nœud")


func test_entity_fade_in() -> void:
	_fog.update_from(_at(_layout.player_spawn))
	var e := Node2D.new()
	e.add_to_group(FogOfWar.GROUP_HIDEABLE)
	e.position = _at(Vector2i(6, 6))
	add_child_autofree(e)
	_fog.update_hideables()
	assert_false(e.visible)
	e.position = _at(Vector2i(5, 14))
	_fog.update_hideables()
	assert_true(e.visible)
	assert_lt(e.modulate.a, 0.5, "Fondu d'apparition")
	await wait_seconds(_fog.transition_time + 0.15)
	assert_almost_eq(e.modulate.a, 1.0, 0.001, "Fondu terminé")


func test_perf_90x60() -> void:
	var L := FloorLayout.new(Vector2i(90, 60))
	L.fill_rect(Rect2i(1, 1, 88, 58), FloorLayout.Tile.STREET)
	# Grille de bâtiments pour avoir des occlusions variées.
	for by in range(0, 6):
		for bx in range(0, 8):
			if (bx + by) % 3 == 0:
				continue
			var r := Rect2i(3 + bx * 11, 3 + by * 9, 7, 6)
			L.add_building(&"store", "b", r)
			L.carve_walled_rect(r, FloorLayout.Tile.FLOOR)
	var fog := FogOfWar.new()
	add_child_autofree(fog)
	fog.setup(L)
	var worst := 0.0
	var total := 0.0
	var n := 0
	var poly_worst := 0.0
	for k in 40:
		var c := Vector2i(2 + (k * 7) % 86, 2 + (k * 5) % 56)
		if not FloorLayout.is_walkable_tile(L.get_tile(c)):
			continue
		fog.invalidate()
		fog.update_from(FloorLayout.cell_to_world(c))
		worst = maxf(worst, fog.last_compute_ms)
		poly_worst = maxf(poly_worst, fog.last_polygon_ms)
		total += fog.last_compute_ms
		n += 1
	gut.p("FogOfWar recalcul 90x60 (case + polygone) : moyen %.3f ms, pire %.3f ms, polygone pire %.3f ms (%d rayons) (%d essais)" % [total / maxf(n, 1), worst, poly_worst, fog.last_ray_count, n])
	assert_lt(total / maxf(n, 1), 2.0, "Recalcul moyen < 2 ms")
	assert_lt(worst, 6.0, "Pas de pic aberrant")


# --- Styles de rendu ([fog] fog_style) ---------------------------------------------

## Crée un brouillard avec le style demandé (balance.cfg modifiée le temps du test).
func _fog_with_style(style: String) -> FogOfWar:
	var cfg: ConfigFile = Balance.get(&"_config")
	var old: Variant = cfg.get_value("fog", "fog_style", null)
	cfg.set_value("fog", "fog_style", style)
	var fog := FogOfWar.new()
	add_child_autofree(fog)
	fog.setup(_layout)
	fog.set_door_query(_door_open)
	cfg.set_value("fog", "fog_style", old)
	return fog


func test_default_style_from_balance() -> void:
	var expected := StringName(str(Balance.get_value("fog", "fog_style", "")))
	assert_true(FogOfWar.SHADERS.has(expected), "fog_style de balance.cfg est un style connu")
	assert_eq(_fog.fog_style, expected)
	assert_eq((_fog.material as ShaderMaterial).shader, FogOfWar.SHADERS[expected])


func test_both_styles_load_with_their_settings() -> void:
	for style: StringName in [FogOfWar.STYLE_DARKENED, FogOfWar.STYLE_MIST, FogOfWar.STYLE_NATURAL]:
		var fog := _fog_with_style(String(style))
		assert_eq(fog.fog_style, style, "Style %s chargé" % style)
		assert_eq(fog.style_section(), "fog_" + String(style))
		var mat := fog.material as ShaderMaterial
		assert_not_null(mat, "Matériau %s" % style)
		assert_eq(mat.shader, FogOfWar.SHADERS[style], "Shader du style %s" % style)
		var keys: PackedStringArray = Balance.get_section_keys(fog.style_section())
		assert_gt(keys.size(), 5, "Section [%s] présente dans balance.cfg" % fog.style_section())
		for key: String in keys:
			if FogOfWar.SCRIPT_STYLE_KEYS.has(key):
				continue
			assert_eq(mat.get_shader_parameter(StringName(key)), Balance.get_value(fog.style_section(), key), "%s.%s transmis au shader" % [style, key])
		assert_eq(fog.halo_px, float(Balance.get_value(fog.style_section(), "halo_px", 0.0)))
	assert_gt(_fog_with_style("mist").halo_px, 0.0, "La brume stylisée utilise le halo (dégradé)")
	var nat := _fog_with_style("natural")
	assert_gt(nat.halo_px, 0.0, "Le style naturel utilise le halo (pénombre)")
	assert_almost_eq(nat.edge_feather_px, float(Balance.get_value("fog_natural", "edge_feather_px", 0.0)), 0.01,
		"Bord large propre au style naturel")
	assert_gt(nat.edge_feather_px, float(Balance.get_value("fog", "edge_feather_px", 22.0)), "Bord plus doux que le réglage commun")


func test_unknown_style_falls_back() -> void:
	var fog := _fog_with_style("n_existe_pas")
	assert_eq(fog.fog_style, FogOfWar.STYLE_DARKENED, "Style inconnu → décor assombri")
	assert_eq((fog.material as ShaderMaterial).shader, FogOfWar.SHADERS[FogOfWar.STYLE_DARKENED])


func test_hideables_hidden_out_of_view_in_both_styles() -> void:
	for style: String in ["darkened", "mist", "natural"]:
		var fog := _fog_with_style(style)
		fog.update_from(_at(_layout.player_spawn))
		var seen := Node2D.new()
		seen.add_to_group(FogOfWar.GROUP_HIDEABLE)
		seen.position = _at(Vector2i(5, 14))
		var behind_door := Node2D.new()
		behind_door.add_to_group(FogOfWar.GROUP_HIDEABLE)
		behind_door.position = _at(Vector2i(6, 6))
		var behind_wall := Node2D.new()
		behind_wall.add_to_group(FogOfWar.GROUP_HIDEABLE)
		behind_wall.position = _at(Vector2i(13, 22))
		var far := Node2D.new()
		far.add_to_group(FogOfWar.GROUP_HIDEABLE)
		far.position = _at(Vector2i(30, 14))
		for n: Node2D in [seen, behind_door, behind_wall, far]:
			add_child_autofree(n)
		fog.update_hideables()
		assert_true(seen.visible, "%s : entité en vue affichée" % style)
		assert_false(behind_door.visible, "%s : cachée derrière une porte fermée" % style)
		assert_false(behind_wall.visible, "%s : cachée derrière un mur" % style)
		assert_false(far.visible, "%s : cachée hors du rayon de vue" % style)
		# Exploré puis quitté : retombe hors vue, l'entité est cachée.
		fog.update_from(_at(Vector2i(32, 26)))
		fog.update_hideables()
		assert_true(fog.is_cell_explored(Vector2i(5, 14)))
		assert_false(seen.visible, "%s : exploré hors vue = entité cachée" % style)
		for n: Node2D in [seen, behind_door, behind_wall, far]:
			n.remove_from_group(FogOfWar.GROUP_HIDEABLE)  # pas de croisement entre styles


func test_shaders_single_pass_budget() -> void:
	# Coût mobile : une passe, aucune boucle, au plus 6 lectures de texture par style.
	var common := FileAccess.get_file_as_string("res://assets/shaders/fog_common.gdshaderinc")
	assert_ne(common, "", "Partie commune lisible")
	for style: StringName in FogOfWar.SHADERS:
		var sh: Shader = FogOfWar.SHADERS[style]
		var code := sh.code
		assert_true(code.contains("fog_common.gdshaderinc"), "%s inclut la partie commune" % style)
		var full := _strip_comments(code + "\n" + common)
		var reads := full.count("texture(")
		assert_lte(reads, 6, "%s : %d lectures de texture (≤ 6)" % [style, reads])
		var rx := RegEx.create_from_string("\\b(for|while)\\s*\\(")
		assert_null(rx.search(full), "%s : aucune boucle" % style)


func _strip_comments(src: String) -> String:
	var out := PackedStringArray()
	for line: String in src.split("\n"):
		var i := line.find("//")
		out.append(line if i < 0 else line.substr(0, i))
	return "\n".join(out)
