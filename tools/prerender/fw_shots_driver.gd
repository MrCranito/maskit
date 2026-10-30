extends Node
## Scénario des captures en jeu de Dust Creek (voir fw_shots.gd).

var out_dir := ""
var raid: Node = null


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = String(a[0]) if a.size() > 0 else "/tmp/fw_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.world_path = "res://data/worlds/world_01_far_west.tres"
	GameState.difficulty = 1
	GameState.run_seed = int(a[1]) if a.size() > 1 else 7
	GameState.current_map = load("res://data/maps/perm_dust_creek.tres")
	GameState.begin_raid()
	_run()


func _run() -> void:
	await get_tree().process_frame
	var scene := load("res://scenes/dungeon/raid.tscn") as PackedScene
	raid = scene.instantiate()
	get_tree().root.add_child(raid)
	await _wait(1.0)
	var L: FloorLayout = raid.get("layout")
	var player: Node2D = raid.get("player")
	print("raid seed ", raid.get("run_seed"), " map_seed ", raid.get("map_seed"), " prerender ", raid.get("prerender") != null)
	var views: Array = [["M_ingame_1", L.player_spawn + Vector2i(0, -4)]]
	# intérieur : la plus grande pièce de bâtiment (saloon / banque)
	var best := Vector2i(-1, -1)
	var best_a := 0
	for r in L.rooms:
		if r.building_id >= 0 and r.rect.get_area() > best_a and r.type != FloorLayout.ROOM_SUPER_LOOT:
			best_a = r.rect.get_area()
			best = r.rect.get_center()
	views.append(["M_ingame_2", best])
	# train : case praticable juste au sud du milieu du convoi
	if not L.train.is_empty():
		var t: Rect2i = L.train[L.train.size() / 2]["rect"]
		var c := Vector2i(t.get_center().x, t.end.y + 1)
		while c.y < L.size.y - 1 and not FloorLayout.is_walkable_tile(L.get_tile(c)):
			c.y += 1
		views.append(["M_ingame_3", c])
	for v: Array in views:
		var c2: Vector2i = v[1]
		if c2.x < 0:
			continue
		raid.call("place_player", c2)
		if player != null:
			player.set("hp", 9999.0)
		await _wait(1.2)
		var pb: Node = raid.get("prerender")
		if pb != null and pb.has_method("preload_visible"):
			pb.call("preload_visible")
		await _wait(0.8)
		await _shot(String(v[0]))
	get_tree().quit()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(out_dir.path_join(name + ".png"))
		print("capture ", name)
