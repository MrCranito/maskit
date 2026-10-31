extends Node
## Scénario de spots_capture.gd. Sorties : <out>/plan_<étage>.png, <out>/dump.txt,
## <out>/spot_<lettre>.png (joueur posé sur le candidat, IA gelée).

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261031
const S := 8  # pixels par case sur le plan

var out: String = ""
var map_path: String = "res://data/maps/perm_dust_creek.tres"
## Candidats : [{"id": "A", "floor": 0, "cell": Vector2i}]
var spots: Array = []
var _dump: PackedStringArray = []


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--map="):
			map_path = a.substr(6)
		elif a.begins_with("--spots="):
			for part: String in a.substr(8).split(";", false):
				var f := part.split(":")
				spots.append({"id": f[0], "floor": int(f[1]), "cell": Vector2i(int(f[2]), int(f[3]))})
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(n: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(out.path_join(n + ".png"))
		print("capture ", n)


func _p(s: String) -> void:
	_dump.append(s)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(out)
	GameState.set_current_map(load(map_path) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 60000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("SpotsCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	_p("map=%s map_seed=%d run_seed=%d" % [map_path, raid.map_seed, SEED])
	var keys: Array = raid.floors.keys()
	keys.sort()
	for idx: int in keys:
		_describe(raid.floors[idx] as FloorLayout)
	var f := FileAccess.open(out.path_join("dump.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_dump))
	f.close()
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	for sp: Dictionary in spots:
		var fi: int = sp["floor"]
		if fi != raid.current_floor:
			raid.go_to_floor(fi, (raid.floors[fi] as FloorLayout).player_spawn)
			await _sleep(1.5)
			if is_instance_valid(raid.enemies_container):
				raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
		_clear_extractions(raid)
		var cell: Vector2i = sp["cell"]
		var mk := SpotMarker.new()
		mk.label = "PERMANENTE " + String(sp["id"])
		mk.position = FloorLayout.cell_to_world(cell) + Vector2(32, 32)
		mk.z_index = 4000
		raid.add_child(mk)
		raid.place_player(_beside(raid.layout, cell))
		await _sleep(1.2)
		await _shot("spot_" + String(sp["id"]))
		mk.queue_free()
	get_tree().quit(0)


func _describe(L: FloorLayout) -> void:
	var dist := ExtractionPlan.walk_distances(L)
	_p("")
	_p("=== floor %d size=%s spawn=%s" % [L.floor_index, L.size, L.player_spawn])
	for st: FloorLayout.Stairs in L.stairs:
		_p("  stairs %s up=%s -> floor %d" % [st.cell, st.up, st.target_floor])
	for r: FloorLayout.Room in L.rooms:
		var c := r.rect.get_center()
		_p("  room #%d [%s] %s rect=%s outdoor=%s dist=%s" % [r.id, r.type, r.name, r.rect, r.outdoor, dist.get(c, "?")])
	for s: ExtractionPlan.Spec in L.extraction_specs:
		_p("  zone %s [%s %s] cells0=%s dist=%.0f closes=%.0f" % [s.name, s.kind, s.option, s.cells[0], s.distance, s.closes_at])
	_plan_image(L, dist)


func _plan_image(L: FloorLayout, dist: Dictionary) -> void:
	var img := Image.create(L.size.x * S, L.size.y * S, false, Image.FORMAT_RGBA8)
	var cols := {
		FloorLayout.Tile.VOID: Color(0.02, 0.03, 0.05),
		FloorLayout.Tile.STREET: Color(0.78, 0.62, 0.40),
		FloorLayout.Tile.FLOOR: Color(0.55, 0.42, 0.30),
		FloorLayout.Tile.WALL: Color(0.18, 0.16, 0.20),
		FloorLayout.Tile.DOOR: Color(0.9, 0.3, 0.2),
		FloorLayout.Tile.STAIRS_UP: Color(0.3, 0.6, 1.0),
		FloorLayout.Tile.STAIRS_DOWN: Color(0.2, 0.3, 0.9),
	}
	for y in L.size.y:
		for x in L.size.x:
			var t := L.get_tile(Vector2i(x, y))
			var c: Color = cols.get(t, Color.MAGENTA)
			if t == FloorLayout.Tile.DOOR:
				var d := L.get_door_at(Vector2i(x, y))
				if d != null and d.state == FloorLayout.DoorState.LOCKED:
					c = Color(1.0, 0.85, 0.1)
			img.fill_rect(Rect2i(x * S, y * S, S, S), c)
	# Salles spéciales : contour
	for r: FloorLayout.Room in L.rooms:
		var rc := Color(0, 0, 0, 0)
		match r.type:
			FloorLayout.ROOM_EXTRACTION: rc = Color(0.2, 1.0, 0.4)
			FloorLayout.ROOM_SUPER_LOOT: rc = Color(1.0, 0.85, 0.1)
			FloorLayout.ROOM_BOSS: rc = Color(1.0, 0.2, 0.2)
		if rc.a > 0:
			_rect_outline(img, Rect2i(r.rect.position * S, r.rect.size * S), rc)
	for c2: Vector2i in L.extraction_cells:
		img.fill_rect(Rect2i(c2.x * S + 1, c2.y * S + 1, S - 2, S - 2), Color(0.2, 1.0, 0.4))
	_mark(img, L.player_spawn, Color.WHITE)
	for sp: Dictionary in spots:
		if int(sp["floor"]) == L.floor_index:
			_mark(img, sp["cell"], Color(0.72, 0.6, 1.0), 3)
	# Grille repère tous les 10 cases
	for gx in range(0, L.size.x, 10):
		for py in L.size.y * S:
			if py % 4 == 0:
				img.set_pixel(gx * S, py, Color(1, 1, 1, 0.5))
	for gy in range(0, L.size.y, 10):
		for px in L.size.x * S:
			if px % 4 == 0:
				img.set_pixel(px, gy * S, Color(1, 1, 1, 0.5))
	img.save_png(out.path_join("plan_%d.png" % L.floor_index))


func _rect_outline(img: Image, r: Rect2i, c: Color) -> void:
	for w in 2:
		img.fill_rect(Rect2i(r.position.x, r.position.y + w, r.size.x, 1), c)
		img.fill_rect(Rect2i(r.position.x, r.end.y - 1 - w, r.size.x, 1), c)
		img.fill_rect(Rect2i(r.position.x + w, r.position.y, 1, r.size.y), c)
		img.fill_rect(Rect2i(r.end.x - 1 - w, r.position.y, 1, r.size.y), c)


func _mark(img: Image, cell: Vector2i, c: Color, rad: int = 2) -> void:
	img.fill_rect(Rect2i((cell.x - rad) * S, (cell.y - rad) * S, (2 * rad + 1) * S, (2 * rad + 1) * S), Color(0, 0, 0))
	img.fill_rect(Rect2i((cell.x - rad + 1) * S - S / 2, (cell.y - rad + 1) * S - S / 2, (2 * rad) * S, (2 * rad) * S), c)


## Anciennes zones retirées (pas de canalisation ni de lueur pendant le repérage).
func _clear_extractions(raid: Raid) -> void:
	for z: ExtractionZone in raid.extraction_zones:
		z.queue_free()
	raid.extraction_zones.clear()
	if raid.minimap != null:
		raid.minimap.rebuild()


## Case praticable à 3 cases du candidat (le joueur ne cache pas le marqueur).
func _beside(L: FloorLayout, c0: Vector2i) -> Vector2i:
	for d: Vector2i in [Vector2i(0, 3), Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, -3), Vector2i(2, 2), Vector2i(-2, 2)]:
		var t := L.get_tile(c0 + d)
		if t == FloorLayout.Tile.STREET or t == FloorLayout.Tile.FLOOR:
			return c0 + d
	return c0


## Marqueur violet du candidat (anneau 2×2 cases + libellé).
class SpotMarker extends Node2D:
	var label: String = ""

	func _draw() -> void:
		var col := Color(0.72, 0.61, 1.0)
		draw_circle(Vector2.ZERO, 120.0, Color(0.49, 0.30, 1.0, 0.28))
		draw_arc(Vector2.ZERO, 120.0, 0.0, TAU, 64, col, 8.0, true)
		draw_arc(Vector2.ZERO, 64.0, 0.0, TAU, 48, col, 4.0, true)
		var f := ThemeDB.fallback_font
		draw_string(f, Vector2(-150, -140), label, HORIZONTAL_ALIGNMENT_CENTER, 300, 34, Color.WHITE)
