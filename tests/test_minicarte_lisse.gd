extends GutTest
## Mini-carte lisse (PR « mini-carte lisse ») : brume d'exploration sans copie ni relecture par
## image, plan vectoriel des étages sans pré-rendu dessiné une seule fois, image de fond des
## paquets assez définie, bouton sac direction D (jauge, plein, « +N »), coin haut droit sans
## chevauchement aux trois résolutions avec et sans encoche.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
## Viewports réels (hauteur 720, stretch « expand ») : 1280×720, téléphone 2000×923 et 2400×1080.
const VIEWPORTS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1560, 720), Vector2i(1600, 720)]
## Encarts simulés (px fenêtre) : sans encoche, encoche à droite (paysage), encoche à gauche.
const INSETS: Array[Vector4] = [Vector4(-1, -1, -1, -1), Vector4(0, 0, 110, 40), Vector4(110, 0, 0, 40)]

var _raid: Raid = null
var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""
	_raid = (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child_autofree(_raid)
	await wait_physics_frames(3)


func after_each() -> void:
	get_tree().paused = false
	HudSafeArea.debug_insets = Vector4(-1, -1, -1, -1)
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


# --- Brume ------------------------------------------------------------------------------

func test_brume_partagee_avec_le_brouillard_sans_relecture() -> void:
	var mm := _raid.minimap
	var fog := _raid.fog as FogOfWar
	if fog == null or fog.get_explored_texture() == null:
		pending("Pas de texture de brouillard dans cet environnement")
		return
	assert_true(mm.uses_shared_fog_texture(), "la mini-carte lit la texture d'exploration du brouillard")
	assert_same(mm._fog_tex, fog.get_explored_texture(), "aucune copie")
	assert_same(mm.view.content.get_node(^"Fog").texture, fog.get_explored_texture())
	await wait_physics_frames(4)
	mm._tick()
	assert_eq(mm.last_fog_cells_scanned, 0, "aucune case relue à chaque rafraîchissement")
	assert_eq(mm.last_fog_update_usec, 0)
	assert_gt(mm.explored_count(), 0, "cases explorées autour du joueur")


func test_brume_ne_touche_que_les_cases_decouvertes() -> void:
	var fog := _raid.fog as FogOfWar
	if fog == null or fog._explored_image == null:
		pending("Pas d'image d'exploration")
		return
	var before := fog._explored_image.get_data()
	var state_before := fog.get_state()
	# Déplace le joueur assez loin pour découvrir de nouvelles cases.
	var l := _raid.layout
	var target := Vector2i(-1, -1)
	for y in l.size.y:
		for x in l.size.x:
			var c := Vector2i(x, y)
			if (l.get_tile(c) == FloorLayout.Tile.STREET or l.get_tile(c) == FloorLayout.Tile.FLOOR) \
					and not fog.is_cell_explored(c) and c.distance_to(l.player_spawn) > 14.0:
				target = c
				break
		if target.x >= 0:
			break
	if target.x < 0:
		pending("Rien à découvrir")
		return
	_raid.place_player(target)
	fog.update_from(_raid.player.global_position)
	fog._recompute(target)
	var after := fog._explored_image.get_data()
	var state_after := fog.get_state()
	var changed := 0
	for i in after.size():
		if after[i] != before[i]:
			changed += 1
			assert_true(state_before[i] == 0 and state_after[i] == 1, "seule une case nouvellement découverte change (%d)" % i)
	assert_gt(changed, 0, "des cases découvertes")


func test_mesure_repli_relecture_locale() -> void:
	# Repli sans texture de brouillard : relecture bornée autour du joueur, durée mesurée.
	var mm := _raid.minimap
	mm._fog_img = Image.create(_raid.layout.size.x, _raid.layout.size.y, false, Image.FORMAT_L8)
	mm._fog_tex = ImageTexture.create_from_image(mm._fog_img)
	mm._update_fog(_raid.player.global_position)
	var side := mm._scan_radius * 2 + 1
	assert_lte(mm.last_fog_cells_scanned, side * side, "relecture bornée au voisinage du joueur")
	assert_gt(mm.last_fog_cells_scanned, 0)
	gut.p("Repli mini-carte : %d cases relues en %d µs" % [mm.last_fog_cells_scanned, mm.last_fog_update_usec])
	mm.rebuild()


func test_parametres_de_brume_depuis_balance() -> void:
	var mat := MiniMap.fog_material()
	assert_eq(mat.shader, MiniMap.FOG_SHADER)
	assert_almost_eq(float(mat.get_shader_parameter(&"threshold")), Balance.get_float("minimap", "fog_threshold", 0.42), 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter(&"rim_px")), Balance.get_float("minimap", "fog_rim_px", 1.4), 0.0001)
	assert_same(MiniMap.fog_material(), mat, "matériau partagé (mini-carte + carte plein écran)")


# --- Plan vectoriel -----------------------------------------------------------------------

func _small_layout() -> FloorLayout:
	var l := FloorLayout.new()
	l.size = Vector2i(8, 6)
	l.tiles = PackedByteArray()
	l.tiles.resize(48)
	l.tiles.fill(FloorLayout.Tile.WALL)
	for y in range(1, 5):
		for x in range(1, 7):
			l.tiles[y * 8 + x] = FloorLayout.Tile.FLOOR
	l.tiles[3 * 8 + 7] = FloorLayout.Tile.DOOR
	l.tiles[1 * 8 + 1] = FloorLayout.Tile.STAIRS_UP
	return l


func test_plan_vectoriel_geometrie_fusionnee() -> void:
	var g := MinimapPlan.Geometry.build(_small_layout())
	assert_eq(g.floor_rects.size(), 3, "pièce 6×4 (avec escalier) + porte : rectangles fusionnés")
	var area := 0.0
	for r: Rect2 in g.floor_rects:
		area += r.get_area()
	assert_almost_eq(area, 25.0 * pow(float(FloorLayout.TILE_SIZE), 2.0), 0.1, "24 cases de pièce + 1 porte")
	# Contour de la pièce : 4 longues lignes + les deux bords de la porte (fusionnés).
	assert_eq(g.edges.size() % 2, 0)
	assert_lte(g.edges.size() / 2, 10, "segments fusionnés le long de la grille")
	assert_eq(g.doors.size(), 1)
	assert_eq(g.stairs.size(), 1)


func test_plan_vectoriel_dessine_une_seule_fois_sans_image() -> void:
	var mm := _raid.minimap
	# Force le plan vectoriel (étage sans pré-rendu).
	mm.bg_texture = null
	mm.plan_geometry = MinimapPlan.Geometry.build(_raid.layout)
	mm.view.setup(null, Rect2(Vector2.ZERO, Vector2(_raid.layout.size) * MiniMap.TS), mm._fog_tex,
		Vector2(_raid.layout.size), PackedVector2Array(), 4.0, mm.plan_geometry)
	var plan := mm.view.plan
	assert_not_null(plan, "plan vectoriel dans la vue")
	await wait_process_frames(3)
	var n := plan.draw_count
	assert_eq(n, 1, "dessiné une fois à l'entrée dans l'arbre")
	for i in 5:
		mm._tick()
		await wait_process_frames(2)
	assert_eq(plan.draw_count, n, "pas de redessin quand la carte suit le joueur")
	for c: Node in mm.view.content.get_children():
		if c is Sprite2D and c.name != "Fog":
			fail_test("aucune image de fond créée pour un étage vectoriel")


# --- Fond des paquets pré-rendus ------------------------------------------------------------

func test_fond_pre_rendu_assez_defini_avec_mipmaps() -> void:
	var cfg := ConfigFile.new()
	var root := "res://assets/prerender/"
	var n := 0
	for biome: String in DirAccess.get_directories_at(root):
		for s: String in DirAccess.get_directories_at(root + biome):
			var dir := root + biome + "/" + s + "/"
			if not ResourceLoader.exists(dir + "minimap.webp"):
				continue
			var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "map.json"))
			var tex := load(dir + "minimap.webp") as Texture2D
			var ip: Array = (meta as Dictionary)["image_px"]
			var ppc := float((meta as Dictionary)["ppc"])
			var px_per_cell := float(tex.get_width()) / float(ip[0]) * ppc
			assert_gte(px_per_cell, 16.0, "%s : ≥ 16 px par case (%.1f)" % [dir, px_per_cell])
			assert_eq(cfg.load(dir + "minimap.webp.import"), OK)
			assert_true(bool(cfg.get_value("params", "mipmaps/generate", false)), "%s : mipmaps" % dir)
			n += 1
	assert_gt(n, 0)


# --- Bouton sac ----------------------------------------------------------------------------

func test_bouton_sac_jauge_plein_et_plus() -> void:
	var inv := Inventory.new(6, 4)
	var b := InventoryBagButton.new()
	add_child_autofree(b)
	b.bind(inv)
	assert_eq(b.count_text(), "0/24")
	assert_eq(b.gauge_color(), MenuKit.GOLD, "jauge claire au départ")
	var ids := [&"gold_nugget", &"pocket_watch", &"bandage", &"canned_beans", &"whisky", &"sheriff_badge",
		&"raw_diamond", &"dynamite", &"treasure_map", &"money_bag", &"lasso", &"revolver_ammo"]
	var k := 0
	while inv.used_slots() < 19 and k < 400:
		var it2 := LootDB.get_item(ids[k % ids.size()])
		if it2 != null:
			inv.add_item(it2, 1)
		k += 1
	if inv.used_slots() < 19:
		pending("Pas assez d'objets distincts pour remplir le sac")
		return
	assert_true(b.is_plus_visible(), "« +N » après un ajout")
	assert_eq(b.gauge_color(), InventoryBagButton.WARN, "orange à partir de [hud] bag_warn_ratio")
	while not b.is_full() and k < 2000:
		var it3 := LootDB.get_item(ids[k % ids.size()])
		if it3 != null:
			inv.add_item(it3, 1)
		k += 1
	if not b.is_full():
		pending("Sac impossible à remplir avec ces objets")
		return
	assert_eq(b.count_text(), "PLEIN")
	assert_eq(b.gauge_color(), InventoryBagButton.DANGER, "rouge plein")


func test_bouton_sac_taille_tactile() -> void:
	# ≥ 64 px physiques en 2000×923 (viewport 1560×720 : facteur 923 / 720).
	assert_gte(InventoryBagButton.SIZE.x * 923.0 / 720.0, 64.0)
	assert_gte(InventoryBagButton.SIZE.y * 923.0 / 720.0, 64.0)


# --- Coin haut droit : pause, sac, mini-carte, bandeau ----------------------------------------

func test_coin_haut_droit_sans_chevauchement() -> void:
	var win := get_tree().root
	var saved := win.size
	var lh := _raid.ui_layer.get_node(^"InventoryHud") as InventoryHud
	var pb := _raid.ui_layer.get_node_or_null(^"PauseMenu/PauseButton") as Control
	var banner := _raid.ui_layer.get_node_or_null(^"Banner") as Control
	for vp: Vector2i in VIEWPORTS:
		win.size = vp
		for ins: Vector4 in INSETS:
			HudSafeArea.debug_insets = ins
			win.size_changed.emit()
			lh._place_safe()
			_raid.minimap.place()
			await wait_process_frames(2)
			var real := Vector2(win.get_visible_rect().size)
			if not real.is_equal_approx(Vector2(vp)):
				pending("Fenêtre non redimensionnable ici (%s)" % real)
				win.size = saved
				return
			var safe := HudSafeArea.safe_rect(_raid.minimap)
			var rects := {"sac": lh.bag_button.get_global_rect(), "mini-carte": _raid.minimap.get_global_rect()}
			if pb != null:
				rects["pause"] = pb.get_global_rect()
			if banner != null and ins.x < 0.0:
				rects["bandeau"] = banner.get_global_rect()
			var keys: Array = rects.keys()
			for kk: String in keys:
				if kk != "bandeau":
					assert_true(safe.grow(0.5).encloses(rects[kk]), "%s dans la zone sûre (%s, %s)" % [kk, vp, ins])
			for i in keys.size():
				for j in range(i + 1, keys.size()):
					assert_false((rects[keys[i]] as Rect2).intersects(rects[keys[j]]),
						"%s / %s ne se chevauchent pas (%s, %s)" % [keys[i], keys[j], vp, ins])
	win.size = saved
	HudSafeArea.debug_insets = Vector4(-1, -1, -1, -1)
	win.size_changed.emit()
