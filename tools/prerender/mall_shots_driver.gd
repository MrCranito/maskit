extends Node
## Scénario des captures en jeu des Galeries Lumière (voir mall_shots.gd).

var out_dir := ""

var raid: Node = null


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	out_dir = String(a[0]) if a.size() > 0 else "/tmp/mall_shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var seed_v := int(a[1]) if a.size() > 1 else 2025
	GameState.world_path = "res://data/worlds/world_03_mall.tres"
	GameState.difficulty = 1
	GameState.run_seed = seed_v
	GameState.current_map = load("res://data/maps/perm_galeries_lumiere.tres")
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
	# Points de vue : parking d'arrivée, atrium (fontaine), boutique à plafond.
	var views: Array = [["M_ingame_1", L.player_spawn + Vector2i(0, -3)]]
	var atrium: Vector2i = Vector2i(-1, -1)
	var shop: Vector2i = Vector2i(-1, -1)
	for r in L.rooms:
		if r.tags.size() > 0 and r.tags[0] == "atrium":
			atrium = r.rect.get_center() + Vector2i(0, 4)
		elif shop.x < 0 and r.building_id >= 0 and r.rect.get_area() >= 9 and r.type != FloorLayout.ROOM_SUPER_LOOT:
			shop = r.rect.get_center()
	views.append(["M_ingame_2", atrium])
	views.append(["M_ingame_3", shop])
	for v: Array in views:
		var c: Vector2i = v[1]
		if c.x < 0:
			continue
		if not FloorLayout.is_walkable_tile(L.get_tile(c)):
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0)]:
				if FloorLayout.is_walkable_tile(L.get_tile(c + d)):
					c += d
					break
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
