extends Node
## Scénario de hatch_capture.gd (voir ce fichier pour les sorties).

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"

var out: String = ""
var map_path: String = "res://data/maps/perm_dust_creek.tres"
var seed_value: int = 20261031


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--map="):
			map_path = a.substr(6)
		elif a.begins_with("--seed="):
			seed_value = int(a.substr(7))
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


## Case praticable à quelques cases de la zone, hors zone et dans la même salle (la zone reste
## dans le champ de vision), sinon la zone elle-même.
func _near(raid: Raid, z: ExtractionZone) -> Vector2i:
	var c0: Vector2i = z.cells[0]
	var room := raid.layout.room_at(c0)
	for r in [3, 2, 4, 5]:
		for d: Vector2i in [Vector2i(0, r), Vector2i(-r, 0), Vector2i(r, 0), Vector2i(0, -r)]:
			var c := c0 + d
			var t := raid.layout.get_tile(c)
			if (t == FloorLayout.Tile.STREET or t == FloorLayout.Tile.FLOOR) and raid.get_extraction_zone_at(c) == null \
					and raid.layout.room_at(c) == room:
				return c
	return c0


func _freeze(raid: Raid) -> void:
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED


func _find(raid: Raid, pred: Callable) -> ExtractionZone:
	for z: ExtractionZone in raid.extraction_zones:
		if is_instance_valid(z) and pred.call(z):
			return z
	return null


func _map(raid: Raid, n: String) -> void:
	if raid.minimap == null:
		return
	raid.minimap.open_full_map()
	await _sleep(0.6)
	await _shot(n)
	raid.minimap.toggle_full_map()
	await _sleep(0.3)


func _run() -> void:
	GameState.set_current_map(load(map_path) as Resource, false)
	GameState.run_seed = seed_value
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("HatchCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	_freeze(raid)
	await _sleep(1.0)
	print("étages : ", raid.floors.keys(), " · zones : ", raid._debug_zones_text())
	var perm := _find(raid, func(z: ExtractionZone) -> bool: return z.is_permanent())
	if perm != null:
		raid.place_player(_near(raid, perm))
		await _sleep(1.2)
		await _shot("permanente")
	var hatch := _find(raid, func(z: ExtractionZone) -> bool: return z.is_hatch())
	if hatch != null:
		GameState.raid_inventory.remove_item(HatchKeys.ITEM_ID, 99)
		raid.place_player(_near(raid, hatch))
		await _sleep(1.2)
		await _shot("trappe_fermee")
		raid.place_player(hatch.cells[0])
		await _sleep(0.6)
		await _shot("trappe_sans_clef")
		raid.place_player(_near(raid, hatch))
		await _sleep(0.4)
		GameState.raid_inventory.add_item(LootDB.get_item(HatchKeys.ITEM_ID), 1)
		raid.place_player(hatch.cells[0])
		await _sleep(1.6)
		await _shot("trappe_ouverte")
		raid.place_player(_near(raid, hatch))
		await _sleep(0.3)
	raid.raid_clock = 140.0
	await _sleep(0.4)
	await _map(raid, "carte")
	var others: Array = raid.floors.keys().filter(func(k: int) -> bool: return k != raid.current_floor)
	if not others.is_empty():
		var fi: int = others[0]
		raid.go_to_floor(fi, (raid.floors[fi] as FloorLayout).player_spawn)
		await _sleep(1.5)
		_freeze(raid)
		await _sleep(0.5)
		await _map(raid, "carte_autre_etage")
		await _shot("autre_etage")
	get_tree().quit(0)
