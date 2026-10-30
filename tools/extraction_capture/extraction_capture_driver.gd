extends Node
## Scénario des captures de l'extraction (voir extraction_capture.gd) : <out>/canal_30.png,
## canal_90.png (canalisation), sortie_1.png, sortie_2.png (séquence de sortie), fin.png.
## IA gelée : la canalisation n'est pas interrompue.

const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030

var out: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(n: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out)
		img.save_png(out.path_join(n + ".png"))
		print("capture ", n)


func _run() -> void:
	GameState.set_current_map(load(MAP_PATH) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("ExtractionCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	if raid.layout.extraction_cells.is_empty():
		push_error("ExtractionCapture: pas de case d'extraction")
		get_tree().quit(1)
		return
	var cell: Vector2i = raid.layout.extraction_cells[0]
	await _sleep(1.5)
	raid.place_player(cell)
	var t := Raid.extraction_channel_time()
	# La boucle du raid fait avancer la canalisation tant que le joueur reste sur la case.
	await _sleep(t * 0.3)
	await _shot("canal_30")
	await _sleep(t * 0.6)
	await _shot("canal_90")
	var d := Raid.extraction_outro_time()
	await _sleep(t * 0.1 + d * 0.3)
	await _shot("sortie_1")
	await _sleep(d * 0.35)
	await _shot("sortie_2")
	await _sleep(d * 0.5 + 1.0)
	await _shot("fin")
	get_tree().quit(0)
