extends Node
## Scénario des captures d'éclairage (voir light_capture.gd).
## Carte à seed fixe, IA gelée. Pour chaque étage demandé : le joueur est placé au centre des
## plus grandes salles (hors couloirs) puis à l'arrivée de l'escalier.
## Images : <out>/<prefix>_<étage>_<n>.png.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030

var out: String = ""
var prefix: String = "shot"
var map_path: String = "res://data/maps/perm_station_kagami.tres"
var floor_list: PackedStringArray = PackedStringArray(["0", "-1", "1"])
var rooms_per_floor: int = 2


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
		elif a.begins_with("--map="):
			map_path = "res://data/maps/%s.tres" % a.substr(6)
		elif a.begins_with("--floors="):
			floor_list = a.substr(9).split(",", false)
		elif a.begins_with("--rooms="):
			rooms_per_floor = int(a.substr(8))
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(n: String) -> void:
	await _frames(3)
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out)
		var p := out.path_join("%s_%s.png" % [prefix, n])
		img.save_png(p)
		print("capture ", p)


func _freeze(raid: Raid) -> void:
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED


func _run() -> void:
	GameState.set_current_map(load(map_path) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("LightCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	_freeze(raid)
	await _sleep(2.0)
	for fs: String in floor_list:
		var fi := int(fs)
		if not raid.has_floor(fi):
			continue
		var L: FloorLayout = raid.floors[fi]
		if fi != raid.current_floor:
			var arrival := L.player_spawn
			if not L.stairs.is_empty():
				arrival = L.stairs[0].cell
			raid.go_to_floor(fi, arrival)
			_freeze(raid)
			await _sleep(1.5)
		var name_f := "f%s" % fs.replace("-", "m")
		await _shot("%s_arrivee" % name_f)
		var rooms: Array = []
		for r: FloorLayout.Room in L.rooms:
			if r.rect.size.x >= 5 and r.rect.size.y >= 5:
				rooms.append(r)
		rooms.sort_custom(func(a: FloorLayout.Room, b: FloorLayout.Room) -> bool:
			return a.rect.get_area() > b.rect.get_area())
		for i: int in mini(rooms_per_floor, rooms.size()):
			var r: FloorLayout.Room = rooms[i]
			var c := r.rect.get_center()
			for k: int in 8:
				var t := L.get_tile(c)
				if t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET:
					break
				c += Vector2i(1, 0)
			raid.place_player(c)
			await _sleep(1.6)
			await _shot("%s_salle%d" % [name_f, i])
	get_tree().quit(0)
