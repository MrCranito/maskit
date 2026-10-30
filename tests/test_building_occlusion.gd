extends GutTest
## Fondu des bâtiments du fond pré-rendu (PrerenderBackdrop) quand une unité passe derrière :
## le bâtiment s'estompe quand le joueur ou un ennemi visible est caché par une de ses tranches,
## redevient opaque ensuite ; un ennemi caché par le brouillard (invisible) ne déclenche rien.

const TS := float(FloorLayout.TILE_SIZE)

var _keep: Transform2D


func before_each() -> void:
	PrerenderBackdrop.threaded_loading_override = 0
	_keep = get_viewport().canvas_transform


func after_each() -> void:
	PrerenderBackdrop.threaded_loading_override = -1
	get_viewport().canvas_transform = _keep


## Fond Dust Creek dont les tuiles autour d'un bâtiment sont chargées ; [backdrop, tranche].
func _setup(biome: StringName = &"far_west") -> Array:
	var seeds := PrerenderBackdrop.available_seeds(biome)
	if seeds.is_empty():
		return []
	var b := PrerenderBackdrop.create(seeds[0], null, biome)
	if b == null:
		return []
	add_child_autofree(b)
	b.set_process(false)
	b.ensure_occluder_holder()
	# Caméra sur la première tranche de bâtiment du paquet (chargement par morceaux).
	var target := Vector2.ZERO
	for e: Dictionary in b.meta["occluders"]:
		for sl: Array in e["slices"]:
			if int(sl[1]) >= 0:
				target = b.origin + Vector2(float(sl[2]), float(sl[3])) * b.px_scale
				break
		if target != Vector2.ZERO:
			break
	get_viewport().canvas_transform = Transform2D(0.0, -target + Vector2(300, 300))
	b._stream()
	# Tranche de bâtiment la plus haute (dépasse le plus vers le nord) parmi celles chargées.
	var best: Dictionary = {}
	for sl: Dictionary in b.loaded_slices():
		if int(sl["bid"]) < 0:
			continue
		var r: Rect2 = sl["rect"]
		if best.is_empty() or float(sl["sort_y"]) - r.position.y > float(best["sort_y"]) - (best["rect"] as Rect2).position.y:
			best = sl
	return [b, best]


## Pieds d'une unité « derrière » la tranche : au nord de sa limite de tri, corps dans son emprise.
func _behind(sl: Dictionary) -> Vector2:
	var r: Rect2 = sl["rect"]
	return Vector2(r.get_center().x, minf(float(sl["sort_y"]) - 12.0, r.end.y - 4.0))


func _unit(group: StringName, pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.add_to_group(group)
	add_child_autofree(n)
	n.global_position = pos
	return n


func _tick(b: PrerenderBackdrop) -> void:
	b._update_occluders()
	b._step_fades(10.0)


func test_batiment_s_estompe_derriere_puis_redevient_opaque() -> void:
	var s := _setup()
	assert_eq(s.size(), 2, "paquet Dust Creek présent")
	if s.size() != 2 or (s[1] as Dictionary).is_empty():
		return
	var b: PrerenderBackdrop = s[0]
	var sl: Dictionary = s[1]
	var bid: int = sl["bid"]
	var alpha := float(b._fade_alpha)
	assert_lt(alpha, 1.0, "opacité de fondu < 1 (balance.cfg)")
	var hero := _unit(&"player", _behind(sl))
	_tick(b)
	assert_almost_eq(b.fade_of(bid), alpha, 0.001, "joueur derrière → bâtiment estompé")
	assert_almost_eq((sl["sprite"] as Sprite2D).modulate.b, alpha, 0.01, "tranche semi-transparente")
	# Toutes les tranches du bâtiment s'estompent ensemble.
	for o: Dictionary in b.loaded_slices():
		if int(o["bid"]) == bid:
			assert_almost_eq((o["sprite"] as Sprite2D).modulate.b, alpha, 0.01)
	# Fondu progressif (pas de saut) : à mi-durée, entre les deux.
	hero.global_position = Vector2(sl["rect"].position.x - 2000.0, float(sl["sort_y"]) + 600.0)
	b._update_occluders()
	b._step_fades(float(b._fade_duration) * 0.5)
	var mid := b.fade_of(bid)
	assert_true(mid > alpha + 0.01 and mid < 0.99, "fondu doux (%.2f)" % mid)
	b._step_fades(10.0)
	assert_almost_eq(b.fade_of(bid), 1.0, 0.001, "joueur parti → bâtiment opaque")
	assert_almost_eq((sl["sprite"] as Sprite2D).modulate.b, 1.0, 0.01)


func test_unite_devant_le_batiment_ne_declenche_rien() -> void:
	var s := _setup()
	if s.size() != 2 or (s[1] as Dictionary).is_empty():
		pass_test("paquet absent")
		return
	var b: PrerenderBackdrop = s[0]
	var sl: Dictionary = s[1]
	# Au sud de la limite de tri : le personnage est dessiné par-dessus, pas de fondu.
	_unit(&"player", Vector2(sl["rect"].get_center().x, float(sl["sort_y"]) + 20.0))
	_tick(b)
	assert_almost_eq(b.fade_of(int(sl["bid"])), 1.0, 0.001)


func test_ennemi_visible_derriere_estompe() -> void:
	var s := _setup()
	if s.size() != 2 or (s[1] as Dictionary).is_empty():
		pass_test("paquet absent")
		return
	var b: PrerenderBackdrop = s[0]
	var sl: Dictionary = s[1]
	_unit(&"enemies", _behind(sl))
	_tick(b)
	assert_almost_eq(b.fade_of(int(sl["bid"])), float(b._fade_alpha), 0.001, "ennemi visible derrière → estompé")


func test_ennemi_cache_par_le_brouillard_ne_declenche_rien() -> void:
	var s := _setup()
	if s.size() != 2 or (s[1] as Dictionary).is_empty():
		pass_test("paquet absent")
		return
	var b: PrerenderBackdrop = s[0]
	var sl: Dictionary = s[1]
	var e := _unit(&"enemies", _behind(sl))
	e.visible = false  # FogOfWar.update_hideables cache les ennemis hors du champ de vision
	_tick(b)
	assert_almost_eq(b.fade_of(int(sl["bid"])), 1.0, 0.001, "ennemi invisible : le bâtiment reste opaque")
	assert_almost_eq((sl["sprite"] as Sprite2D).modulate.b, 1.0, 0.01)


func test_fondu_desactivable() -> void:
	var s := _setup()
	if s.size() != 2 or (s[1] as Dictionary).is_empty():
		pass_test("paquet absent")
		return
	var b: PrerenderBackdrop = s[0]
	var sl: Dictionary = s[1]
	b._fade_enabled = false
	_unit(&"player", _behind(sl))
	_tick(b)
	assert_almost_eq(b.fade_of(int(sl["bid"])), 1.0, 0.001)


func test_cartes_station_et_galeries() -> void:
	for biome: StringName in [&"space_station", &"mall"]:
		var s := _setup(biome)
		if s.size() != 2 or (s[1] as Dictionary).is_empty():
			continue
		var b: PrerenderBackdrop = s[0]
		var sl: Dictionary = s[1]
		var hero := _unit(&"player", _behind(sl))
		_tick(b)
		assert_almost_eq(b.fade_of(int(sl["bid"])), float(b._fade_alpha), 0.001, "%s : estompé" % biome)
		hero.queue_free()
		await get_tree().process_frame
		_tick(b)
		assert_almost_eq(b.fade_of(int(sl["bid"])), 1.0, 0.001, "%s : opaque" % biome)


# --- Vrai sol sous le bâtiment estompé (patchs « sol seul », passe gnd) --------------------

const PACKS := [&"far_west", &"space_station", &"mall"]


## Chaque bâtiment qui occulte (tranches id ≥ 0) a son patch « sol seul » dans le paquet.
func test_paquets_ont_un_sol_par_batiment() -> void:
	for biome: StringName in PACKS:
		var seeds := PrerenderBackdrop.available_seeds(biome)
		assert_false(seeds.is_empty(), "%s : paquet présent" % biome)
		if seeds.is_empty():
			continue
		var b := PrerenderBackdrop.create(seeds[0], null, biome)
		add_child_autofree(b)
		var ids := {}
		for e: Dictionary in b.meta["occluders"]:
			for sl: Array in e["slices"]:
				if int(sl[1]) >= 0:
					ids[int(sl[1])] = true
		assert_gt(ids.size(), 0, "%s : bâtiments qui occultent" % biome)
		for bid: int in ids:
			assert_true(b.has_ground(bid), "%s : sol seul du bâtiment %d" % [biome, bid])
		for e: Dictionary in b.meta.get("grounds", []):
			assert_true(ResourceLoader.exists(b.pack_dir + String(e["file"])), "%s : %s" % [biome, e["file"]])


func test_sol_visible_quand_le_batiment_s_estompe() -> void:
	var s := _setup()
	if s.size() != 2 or (s[1] as Dictionary).is_empty():
		pass_test("paquet absent")
		return
	var b: PrerenderBackdrop = s[0]
	var sl: Dictionary = s[1]
	var bid: int = sl["bid"]
	_tick(b)
	assert_eq(b.ground_alpha(bid), 0.0, "au repos : patch chargé mais non dessiné")
	var hero := _unit(&"player", _behind(sl))
	_tick(b)
	assert_almost_eq(b.ground_alpha(bid), 1.0, 0.001, "bâtiment estompé : vrai sol affiché dessous")
	hero.global_position = Vector2(-1.0e5, -1.0e5)
	_tick(b)
	assert_eq(b.ground_alpha(bid), 0.0, "bâtiment opaque : patch masqué")


## « Au-dessus » (bord nord, sous le toit projeté) et « sous le toit » (dans l'emprise) : pour
## chaque bâtiment avec intérieur des 3 cartes, le fondu se déclenche.
func test_fondu_au_dessus_et_sous_le_toit_partout() -> void:
	for biome: StringName in PACKS:
		var seeds := PrerenderBackdrop.available_seeds(biome)
		if seeds.is_empty():
			continue
		var b := PrerenderBackdrop.create(seeds[0], null, biome)
		add_child(b)
		b.set_process(false)
		b.ensure_occluder_holder()
		b.stream_margin = 1.0e7  # toutes les tuiles
		b._stream()
		b._update_occluders()
		var hero := Node2D.new()
		hero.add_to_group(&"player")
		add_child(hero)
		hero.global_position = Vector2(-1.0e5, -1.0e5)
		var n := 0
		for e: Dictionary in b.meta["interiors"]:
			var bid := int(e["id"])
			if not b._by_key.has(bid):
				continue
			var r: Array = e["rect"]
			var cx := (float(r[0]) + float(r[2]) * 0.5) * TS
			for feet: Vector2 in [Vector2(cx, (float(r[1]) + float(r[3]) * 0.5) * TS),
					Vector2(cx, float(r[1]) * TS - 8.0)]:
				hero.global_position = feet
				_tick(b)
				assert_almost_eq(b.fade_of(bid), float(b._fade_alpha), 0.001,
					"%s bâtiment %d : fondu avec l'unité en %s" % [biome, bid, feet])
				hero.global_position = Vector2(-1.0e5, -1.0e5)
				_tick(b)
				n += 1
		assert_gt(n, 0, "%s : bâtiments testés" % biome)
		hero.free()
		b.free()
