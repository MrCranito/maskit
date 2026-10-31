extends Node
## Scénario des captures de l'occultation (voir occlusion_capture.gd). IA gelée (images
## reproductibles). Cherche, dans les images d'ids des tranches d'occultation du paquet
## pré-rendu (o_*.png), une case praticable dont le corps d'un personnage est recouvert par un
## grand bâtiment situé plus au sud ; y place le joueur, puis un ennemi sur une case voisine
## elle aussi masquée. Images : <out>/<prefix>_<map>.png (+ <prefix>_<map>_zoom.png, recadrée).

const MAPS := {
	"dust": "res://data/maps/perm_dust_creek.tres",
	"station": "res://data/maps/perm_station_kagami.tres",
	"mall": "res://data/maps/perm_galeries_lumiere.tres",
}
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030
const TS := float(FloorLayout.TILE_SIZE)

var out: String = ""
var prefix: String = "shot"
var map_key: String = "dust"
var no_fade := false
var no_ground := false  ## état de la PR #56 : bâtiment estompé à 0,3 sur son toit, sans sol
var _ids: Dictionary = {}  ## fichier de tuile → Image d'ids


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
		elif a.begins_with("--map="):
			map_key = a.substr(6)
		elif a == "--no-fade":
			no_fade = true
		elif a == "--no-ground":
			no_ground = true
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(n: String, focus: Vector2 = Vector2.INF) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img == null or out == "":
		return
	DirAccess.make_dir_recursive_absolute(out)
	var p := out.path_join("%s_%s.png" % [prefix, n])
	img.save_png(p)
	print("capture ", p)
	if focus != Vector2.INF:
		# Recadrage (×2) autour du joueur : lisible dans la description de la PR.
		var vp := get_tree().root.get_viewport()
		var sp := vp.get_canvas_transform() * focus
		var w := img.get_width() / 2
		var h := img.get_height() / 2
		var x := clampi(int(sp.x) - w / 2, 0, img.get_width() - w)
		var y := clampi(int(sp.y) - h / 2 - 40, 0, img.get_height() - h)
		var crop := img.get_region(Rect2i(x, y, w, h))
		crop.resize(w * 2, h * 2, Image.INTERPOLATE_LANCZOS)
		crop.save_png(out.path_join("%s_%s_zoom.png" % [prefix, n]))


func _run() -> void:
	if no_fade:
		var cfg: ConfigFile = Balance.get(&"_config")
		cfg.set_value("prerender", "occluder_fade", false)
	if no_ground:
		var cfg2: ConfigFile = Balance.get(&"_config")
		cfg2.set_value("prerender", "occluder_ground", false)
		cfg2.set_value("prerender", "occluder_fade_alpha", 0.3)
	GameState.set_current_map(load(MAPS.get(map_key, MAPS["dust"])) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 40000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("OcclusionCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	await _sleep(1.5)
	var pb := raid.prerender
	if pb == null:
		push_error("OcclusionCapture: pas de fond pré-rendu")
		get_tree().quit(1)
		return
	var spots := _hidden_cells(raid, pb)
	if spots.is_empty():
		push_error("OcclusionCapture: aucune case derrière un bâtiment")
		get_tree().quit(1)
		return
	# Bâtiment le plus grand (nombre de cases masquées), case la plus centrale de ce groupe.
	var by_bid := {}
	for s: Dictionary in spots:
		(by_bid.get_or_add(int(s["bid"]), []) as Array).append(s)
	var best_bid := -1
	for b: int in by_bid:
		if best_bid < 0 or (by_bid[b] as Array).size() > (by_bid[best_bid] as Array).size():
			best_bid = b
	var group: Array = by_bid[best_bid]
	var sum := Vector2.ZERO
	for s: Dictionary in group:
		sum += Vector2(s["cell"])
	var mid := sum / float(group.size())
	var pc: Vector2i = group[0]["cell"]
	for s: Dictionary in group:
		if Vector2(s["cell"]).distance_to(mid) < Vector2(pc).distance_to(mid):
			pc = s["cell"]
	print("bâtiment ", best_bid, " : ", group.size(), " cases masquées, joueur en ", pc)
	raid.place_player(pc)
	# Ennemi : case masquée du même bâtiment à 2..4 cases du joueur.
	var ec := Vector2i(-1, -1)
	for s: Dictionary in group:
		var c: Vector2i = s["cell"]
		var d := Vector2(c).distance_to(Vector2(pc))
		if d >= 2.0 and d <= 4.5 and (ec.x < 0 or absf(d - 3.0) < absf(Vector2(ec).distance_to(Vector2(pc)) - 3.0)):
			ec = c
	if ec.x >= 0:
		for e: Node in get_tree().get_nodes_in_group(&"enemies"):
			if e is Node2D and raid.enemies_container.is_ancestor_of(e):
				(e as Node2D).global_position = FloorLayout.cell_to_world(ec)
				print("ennemi en ", ec)
				break
	raid.place_player(pc)
	await _sleep(1.5)
	await _shot(map_key, raid.player.global_position)
	get_tree().quit(0)


## Cases praticables dont deux points du corps (pieds - 24, pieds - 56) sont recouverts par une
## tranche de bâtiment triée au sud des pieds : {cell, bid}.
func _hidden_cells(raid: Raid, pb: PrerenderBackdrop) -> Array[Dictionary]:
	var res: Array[Dictionary] = []
	var L := raid.layout
	var roofs: Array = []
	if raid.world_root != null and raid.world_root.has_method("get_roofs"):
		roofs = raid.world_root.call("get_roofs")
	var blocks := pb.collision_rects()
	var tiles := {}
	for t: Dictionary in pb.meta["tiles"]:
		tiles[pb.pack_dir + String(t["file"])] = t["px"]
	for e: Dictionary in pb.meta.get("occluders", []):
		var img := Image.load_from_file(ProjectSettings.globalize_path(pb.pack_dir + String(e["ids"])))
		if img != null:
			_ids[pb.pack_dir + String(e["tile"])] = {"img": img, "px": tiles.get(pb.pack_dir + String(e["tile"]), [0, 0, 0, 0])}
	for y in L.size.y:
		for x in L.size.x:
			var c := Vector2i(x, y)
			var t := L.get_tile(c)
			if not FloorLayout.is_walkable_tile(t) or t == FloorLayout.Tile.DOOR:
				continue
			var feet := FloorLayout.cell_to_world(c)
			var inside := false
			for r: Node in roofs:
				if r.has_method("contains_world") and bool(r.call("contains_world", feet)):
					inside = true
					break
			if inside:
				continue
			var blocked := false
			for b: Rect2 in blocks:
				if b.grow(-2.0).has_point(feet):
					blocked = true
					break
			if blocked:
				continue
			var a := _id_at(pb, feet + Vector2(0, -24))
			var b2 := _id_at(pb, feet + Vector2(0, -56))
			if a.y < 0 or a.y != b2.y:
				continue
			if float(mini(a.x, b2.x) + 1) * TS <= feet.y + 8.0:
				continue
			res.append({"cell": c, "bid": a.y})
	return res


## (rangée, bâtiment) de la tranche qui recouvre `p` (monde), (-1, -1) si aucune.
func _id_at(pb: PrerenderBackdrop, p: Vector2) -> Vector2i:
	var g := (p - pb.origin) / pb.px_scale
	for k: String in _ids:
		var px: Array = _ids[k]["px"]
		var lx := int(g.x - float(px[0]))
		var ly := int(g.y - float(px[1]))
		var img: Image = _ids[k]["img"]
		if lx < 0 or ly < 0 or lx >= img.get_width() or ly >= img.get_height():
			continue
		var col := img.get_pixel(lx, ly)
		var row := int(round(col.r * 255.0)) - 1
		var bid := int(round(col.g * 255.0)) - 1
		if row < 0:
			return Vector2i(-1, -1)
		return Vector2i(row, bid)
	return Vector2i(-1, -1)
