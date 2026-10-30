extends Node
## Captures en jeu des Carnaval hanté (développement) : lance le raid sur le monde 04 avec la seed
## donnée, téléporte le joueur sur des cases, enregistre des PNG du viewport.
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##       res://tools/prerender/hc_capture.tscn -- <seed> <out_dir> [x,y;x,y;...] [zoom]
## Sans cases : vue d'ensemble (caméra dézoomée sur toute la carte) → M_overview.png.

var _args: PackedStringArray
var _raid: Node = null


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	var seed_value := int(_args[0])
	GameState.world_path = "res://data/worlds/world_04_haunted_carnival.tres"
	GameState.run_seed = seed_value
	GameState.difficulty = 1
	var card := MapCard.find(&"perm_carnaval_hante")
	if card != null:
		GameState.current_map = card
	var scn: PackedScene = load("res://scenes/dungeon/raid.tscn")
	_raid = scn.instantiate()
	get_tree().root.add_child.call_deferred(_raid)
	_run()


func _run() -> void:
	await get_tree().create_timer(2.5).timeout
	var out_dir := String(_args[1])
	DirAccess.make_dir_recursive_absolute(out_dir)
	var player: Node2D = _raid.get("player")
	var cam: Camera2D = player.get_node_or_null("Camera2D")
	var layout: FloorLayout = _raid.get("layout")
	var pre: Node = _raid.get("prerender")
	print("prerender attached: ", pre != null, " layout ", layout.size)
	var cells: Array = []
	if _args.size() > 2 and String(_args[2]) != "":
		for s in String(_args[2]).split(";"):
			var p := s.split(",")
			cells.append(Vector2i(int(p[0]), int(p[1])))
	var zoom := float(_args[3]) if _args.size() > 3 else 1.0
	if cells.is_empty():
		# Vue d'ensemble : caméra libre dézoomée.
		var fog: Node = _raid.get("fog")
		if fog != null and fog.has_method("reveal_all"):
			fog.call("reveal_all", true)
		var c2 := Camera2D.new()
		get_tree().root.add_child(c2)
		c2.make_current()
		var sz := Vector2(layout.size) * 64.0
		c2.position = sz * 0.5
		var vp := get_viewport().get_visible_rect().size
		var k := minf(vp.x / sz.x, vp.y / sz.y) * 0.98
		c2.zoom = Vector2(k, k)
		if pre != null:
			pre.set("stream_margin", 20000.0)
		await get_tree().create_timer(2.5).timeout
		if pre != null and pre.has_method("preload_visible"):
			pre.call("preload_visible")
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/M_overview.png")
		print("saved overview")
	var i := 1
	for c: Vector2i in cells:
		player.global_position = FloorLayout.cell_to_world(c)
		player.reset_physics_interpolation()
		if cam != null:
			cam.make_current()
			cam.zoom = Vector2(zoom, zoom)
			cam.reset_smoothing()
		await get_tree().create_timer(1.6).timeout
		if pre != null and pre.has_method("preload_visible"):
			pre.call("preload_visible")
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png(out_dir + "/M_ingame_%d.png" % i)
		print("saved ingame ", i, " at ", c)
		i += 1
	get_tree().quit()
