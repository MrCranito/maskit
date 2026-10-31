extends Node
## Scénario des captures en jeu de la Station Kagami (voir ss_shots.gd).

var out_dir := ""

var raid: Node = null


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = String(a[0]) if a.size() > 0 else "/tmp/ss_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var seed_v := int(a[1]) if a.size() > 1 else 948725
	GameState.world_path = "res://data/worlds/world_02_space_station.tres"
	GameState.difficulty = 1
	GameState.run_seed = seed_v
	GameState.current_map = load("res://data/maps/perm_station_kagami.tres")
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
	# Points de vue : coursive sud (arrivée), centre de contrôle, module de l'aile nord.
	var views: Array = [["M_ingame_1", L.player_spawn + Vector2i(0, -10)]]
	var dome: Vector2i = Vector2i(-1, -1)
	var wing: Vector2i = Vector2i(-1, -1)
	for r in L.rooms:
		if r.tags.size() == 0:
			continue
		if r.tags[0] == "control_center":
			dome = r.rect.get_center() + Vector2i(0, 3)
		elif wing.x < 0 and r.rect.position.y < 28 and r.rect.get_area() >= 30 and r.tags[0] in ["mess_hall", "lab", "quarters", "hydroponics", "workshop", "storage"]:
			wing = r.rect.get_center()
	views.append(["M_ingame_2", dome])
	views.append(["M_ingame_3", wing])
	for v: Array in views:
		var c: Vector2i = v[1]
		if c.x < 0:
			continue
		raid.call("place_player", c)
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
