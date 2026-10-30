extends Node
## Scénario des captures de la carte zoomable (voir map_zoom_capture.gd) :
## <out>/<tag>_carte_entiere.png, _recentre.png, _zoom_max.png, _extraction.png. IA gelée.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const SEED := 20261030

var out: String = ""
var tag: String = "capture"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(n: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out)
		img.save_png(out.path_join("%s_%s.png" % [tag, n]))
		print("capture ", n)


func _run() -> void:
	GameState.set_current_map(load(MAP_PATH) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("MapZoomCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	await _sleep(1.0)
	# Explore un peu : quelques cases praticables entre l'apparition et le centre de la carte.
	var spawn := raid.layout.player_spawn
	var mid := raid.layout.size / 2
	for k: float in [0.33, 0.66]:
		var c := Vector2i(Vector2(spawn).lerp(Vector2(mid), k))
		for r in 8:
			var t := raid.layout.get_tile(c + Vector2i(r, 0))
			if t == FloorLayout.Tile.STREET or t == FloorLayout.Tile.FLOOR:
				raid.place_player(c + Vector2i(r, 0))
				break
		await _sleep(0.8)
	raid.minimap.open_full_map()
	await _sleep(0.6)
	var fm := raid.minimap.full_map
	await _shot("carte_entiere")
	fm.recenter()
	await _sleep(0.2)
	await _shot("recentre")
	fm.zoom_step(10.0)
	await _sleep(0.2)
	await _shot("zoom_max")
	if not raid.extraction_zones.is_empty():
		fm.zoom.set_scale_at(fm.zoom.view_size * 0.5, fm.zoom.min_scale() * 2.0)
		fm.zoom.center_on((raid.extraction_zones[0] as Node2D).global_position)
		fm._apply_zoom()
		await _sleep(0.2)
		await _shot("extraction")
	fm.close()
	get_tree().quit(0)
