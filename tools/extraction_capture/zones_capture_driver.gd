extends Node
## Scénario des captures des zones à durée de vie (voir zones_capture.gd) :
## <out>/<prefixe>zone_ouverte.png, carte.png, puis (sans --before) avertissement.png,
## fermee.png, urgence.png, carte_urgence.png. IA gelée.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030

var out: String = ""
var map_path: String = "res://data/maps/perm_dust_creek.tres"
var before: bool = false
var prefix: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--map="):
			map_path = a.substr(6)
		elif a == "--before":
			before = true
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(n: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out)
		img.save_png(out.path_join(prefix + n + ".png"))
		print("capture ", prefix + n)


## Case praticable à quelques cases au sud de la zone (hors zone), sinon la zone elle-même.
func _near(raid: Raid, z: ExtractionZone) -> Vector2i:
	var c0: Vector2i = z.cells[0]
	for r in [3, 4, 2, 5]:
		for d: Vector2i in [Vector2i(0, r), Vector2i(-r, 0), Vector2i(r, 0), Vector2i(0, -r)]:
			var c := c0 + d
			var t := raid.layout.get_tile(c)
			if (t == FloorLayout.Tile.STREET or t == FloorLayout.Tile.FLOOR) and not raid.layout.extraction_cells.has(c):
				return c
	return c0


func _goto(raid: Raid, z: ExtractionZone) -> void:
	raid.place_player(_near(raid, z))
	await _sleep(1.2)


func _map(raid: Raid, n: String) -> void:
	if raid.minimap == null:
		return
	raid.minimap.open_full_map()
	await _sleep(0.6)
	await _shot(n)
	raid.minimap.toggle_full_map()
	await _sleep(0.3)


func _run() -> void:
	if before:
		Balance._config.set_value("extraction", "timed_zones", false)
	GameState.set_current_map(load(map_path) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("ZonesCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	if raid.extraction_zones.is_empty():
		push_error("ZonesCapture: pas de zone d'extraction")
		get_tree().quit(1)
		return
	print("zones : ", raid._debug_zones_text())
	await _sleep(1.0)
	var first: ExtractionZone = raid.extraction_zones[0]
	await _goto(raid, first)
	await _shot("zone_ouverte")
	await _map(raid, "carte")
	if before:
		get_tree().quit(0)
		return
	raid.raid_clock = first.closes_at - 22.0
	await _sleep(0.6)
	await _shot("avertissement")
	raid.raid_clock = first.closes_at + 0.5
	await _sleep(0.8)
	await _shot("fermee")
	var em: ExtractionZone = null
	for z: ExtractionZone in raid.extraction_zones:
		if z.emergency:
			em = z
	raid.raid_clock = 1.0e5
	await _sleep(0.5)
	if em != null:
		await _goto(raid, em)
		await _shot("urgence")
	await _map(raid, "carte_urgence")
	get_tree().quit(0)
