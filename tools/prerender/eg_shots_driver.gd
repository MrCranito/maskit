extends Node
## Scénario des captures en jeu des Pyramides d'Égypte (voir eg_shots.gd).

var out_dir := ""

var raid: Node = null


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = String(a[0]) if a.size() > 0 else "/tmp/eg_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var seed_v := int(a[1]) if a.size() > 1 else 2026
	GameState.world_path = "res://data/worlds/world_06_egypt_pyramids.tres"
	GameState.difficulty = 1
	GameState.run_seed = seed_v
	GameState.current_map = load("res://data/maps/perm_pyramides_egypte.tres")
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
	# Points de vue : avenue (arrivée), temple d'angle (chambre à toit), sanctuaire.
	var views: Array = [["M_ingame_1", L.player_spawn + Vector2i(0, -6)]]
	var chamber: Vector2i = Vector2i(-1, -1)
	var sanct: Vector2i = Vector2i(-1, -1)
	for r in L.rooms:
		if r.tags.size() > 0 and r.tags[0] == "sanctuary":
			sanct = r.rect.get_center()
		elif chamber.x < 0 and r.building_id >= 0 and r.rect.get_area() >= 9 and r.type != FloorLayout.ROOM_SUPER_LOOT and r.tags[0] != "hypostyle":
			chamber = r.rect.get_center()
	views.append(["M_ingame_2", chamber])
	views.append(["M_ingame_3", sanct])
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
		await _wait(0.6)
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
