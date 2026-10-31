extends Node
## ScÃƒÂ©nario des captures de la mini-carte (voir minimap_capture.gd). Images <out>/<tag>_<ÃƒÂ©tape>.png :
## _hud (ÃƒÂ©cran entier), _coin_x2 (sac + pause + mini-carte, Ãƒâ€”2), _carte (plein ÃƒÂ©cran),
## _carte_zoom_x2 (zoom max, centre Ãƒâ€”2), _sac_plein_x2 (sac presque plein puis plein).

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030

var out: String = ""
var tag: String = "capture"
var map_path: String = "res://data/maps/perm_dust_creek.tres"
var floor_index: int = 0
var notch: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--map="):
			map_path = a.substr(6)
		elif a.begins_with("--floor="):
			floor_index = int(a.substr(8))
		elif a == "--notch":
			notch = true
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _grab() -> Image:
	for i in 3:
		await get_tree().process_frame
	return get_tree().root.get_viewport().get_texture().get_image()


func _save(img: Image, n: String) -> void:
	if img == null or out == "":
		return
	DirAccess.make_dir_recursive_absolute(out)
	var p := out.path_join("%s_%s.png" % [tag, n])
	img.save_png(p)
	print("capture ", p)


## Recadre `r` (px du viewport) dans l'image (px de la fenÃƒÂªtre) et l'agrandit Ãƒâ€”2 (plus proche voisin).
func _crop_x2(img: Image, r: Rect2) -> Image:
	var k := Vector2(img.get_size()) / get_tree().root.get_visible_rect().size
	var rr := Rect2i(Vector2i((r.position * k).floor()), Vector2i((r.size * k).ceil()))
	rr = rr.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var c := img.get_region(rr)
	c.resize(rr.size.x * 2, rr.size.y * 2, Image.INTERPOLATE_NEAREST)
	return c


func _run() -> void:
	if notch:
		HudSafeArea.debug_insets = Vector4(90, 0, 90, 40)
	GameState.set_current_map(load(map_path) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 40000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("MinimapCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	await _sleep(1.0)
	if floor_index != 0:
		if not raid.has_floor(floor_index):
			push_error("MinimapCapture: pas d'ÃƒÂ©tage %d" % floor_index)
			get_tree().quit(1)
			return
		raid.go_to_floor(floor_index, raid.layout.player_spawn)
		await _sleep(1.0)
		if is_instance_valid(raid.enemies_container):
			raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
		# Arrivée : à côté d'un escalier de l'étage.
		for y in raid.layout.size.y:
			for x in raid.layout.size.x:
				var tt := raid.layout.get_tile(Vector2i(x, y))
				if tt == FloorLayout.Tile.STAIRS_UP or tt == FloorLayout.Tile.STAIRS_DOWN:
					var w := _walkable_near(raid.layout, Vector2i(x, y))
					if w.x >= 0:
						raid.place_player(w)
						break
	print("MinimapCapture: étage ", raid.current_floor, " fond pré-rendu = ", raid.prerender != null)
	# Explore : parcours en largeur depuis le joueur, arrêts à 6, 12, 18, 24 cases (zone connexe).
	var path := _bfs_stops(raid.layout, raid.get_player_cell(), [6, 12, 18, 24, 30])
	for c: Vector2i in path:
		raid.place_player(c)
		await _sleep(0.5)
	var lh := raid.ui_layer.get_node_or_null(^"InventoryHud") as InventoryHud
	var inv := GameState.raid_inventory
	for id: StringName in [&"gold_nugget", &"pocket_watch", &"bandage", &"canned_beans", &"whisky"]:
		var it := LootDB.get_item(id)
		if it != null:
			inv.add_item(it, 1)
	await _sleep(0.6)
	var mm := raid.minimap
	var corner := mm.get_global_rect()
	if lh != null:
		corner = corner.merge(lh.bag_button.get_global_rect())
	var pb := raid.ui_layer.get_node_or_null(^"PauseMenu/PauseButton") as Control
	if pb != null:
		corner = corner.merge(pb.get_global_rect())
	corner = corner.grow(12.0)
	var img := await _grab()
	_save(img, "hud")
	_save(_crop_x2(img, corner), "coin_x2")
	mm.open_full_map()
	await _sleep(0.6)
	var fm := mm.full_map
	img = await _grab()
	_save(img, "carte")
	fm.zoom.set_scale_at(fm.zoom.view_size * 0.5, fm.zoom.min_scale() * 100.0)
	fm.zoom.center_on(fm.player_position())
	fm._apply_zoom()
	await _sleep(0.3)
	img = await _grab()
	_save(img, "carte_zoom")
	var vr := fm.view.get_global_rect()
	var c2 := Rect2(vr.get_center() - Vector2(170, 110), Vector2(340, 220))
	_save(_crop_x2(img, c2), "carte_zoom_x2")
	fm.close()
	await _sleep(0.3)
	# Sac presque plein puis plein (jauge orange / rouge).
	if lh != null:
		var filler := LootDB.get_item(&"gold_nugget")
		var ids := [&"pocket_watch", &"canned_beans", &"whisky", &"sheriff_badge", &"raw_diamond", &"dynamite",
			&"treasure_map", &"money_bag", &"lasso", &"revolver_ammo", &"black_powder", &"gold_bar", &"cavalry_medal",
			&"bandage", &"medkit", &"key_bank_vault", &"mall_cash_bundle"]
		var i := 0
		while inv.used_slots() < inv.capacity() - 3 and i < 200:
			var it := LootDB.get_item(ids[i % ids.size()])
			inv.add_item(it if it != null else filler, 1)
			i += 1
		await _sleep(0.15)
		img = await _grab()
		_save(_crop_x2(img, corner), "sac_presque_plein_x2")
		i = 0
		while inv.used_slots() < inv.capacity() and i < 400:
			var it2 := LootDB.get_item(ids[i % ids.size()])
			inv.add_item(it2 if it2 != null else filler, 1)
			i += 1
		await _sleep(0.12)
		img = await _grab()
		_save(_crop_x2(img, corner), "sac_plein_x2")
		await _sleep(0.6)
		img = await _grab()
		_save(_crop_x2(img, corner), "sac_plein_repos_x2")
	get_tree().quit(0)


static func _walkable(t: int) -> bool:
	return t == FloorLayout.Tile.STREET or t == FloorLayout.Tile.FLOOR


func _walkable_near(l: FloorLayout, c: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(0, 2)]:
		if _walkable(l.get_tile(c + d)):
			return c + d
	return Vector2i(-1, -1)


## Cases atteintes à chaque distance demandée (parcours en largeur sur les cases praticables).
func _bfs_stops(l: FloorLayout, from: Vector2i, dists: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {from: 0}
	var q: Array[Vector2i] = [from]
	var qi := 0
	var last := from
	while qi < q.size():
		var c: Vector2i = q[qi]
		qi += 1
		var d: int = seen[c]
		last = c
		if dists.has(d) and (out.is_empty() or seen[out[-1]] != d):
			out.append(c)
		for dd: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := c + dd
			if not seen.has(n) and l.in_bounds(n) and (_walkable(l.get_tile(n)) or l.get_tile(n) == FloorLayout.Tile.DOOR):
				seen[n] = d + 1
				q.append(n)
	if out.is_empty():
		out.append(last)
	return out