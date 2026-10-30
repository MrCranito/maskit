extends Node
## Scénario des captures du brouillard (voir fog_capture.gd).
## Dust Creek, seed fixe, rez-de-chaussée ; IA gelée (images reproductibles).
## Images : <out>/<prefix>_1_depart.png (au départ), <prefix>_2_interieur.png (dans le
## bâtiment le plus proche), <prefix>_3_ruelle.png (ruelle la plus proche, après
## exploration : montre le souvenir des zones explorées hors vue et l'inconnu).

const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030

var out: String = ""
var style: String = ""
var prefix: String = "shot"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--style="):
			style = a.substr(8)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
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


func _go(raid: Raid, cell: Vector2i, wait: float) -> void:
	raid.place_player(cell)
	await _sleep(wait)


func _run() -> void:
	if style != "":
		var cfg: ConfigFile = Balance.get(&"_config")
		cfg.set_value("fog", "fog_style", style)
	var card := load(MAP_PATH) as Resource
	GameState.set_current_map(card, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("FogCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	var L := raid.layout
	var spawn := L.player_spawn
	await _sleep(2.0)
	await _shot("1_depart")
	# Intérieur : centre de la plus grande salle intérieure la plus proche du départ.
	var best: FloorLayout.Room = null
	var best_d := 1e30
	for r: FloorLayout.Room in L.rooms:
		if r.outdoor or r.rect.get_area() < 12:
			continue
		var d := Vector2(r.rect.get_center()).distance_to(Vector2(spawn))
		if d < best_d:
			best_d = d
			best = r
	# Exploration : quelques salles extérieures proches, puis l'intérieur, puis retour.
	var outs: Array[Vector2i] = []
	for r: FloorLayout.Room in L.rooms:
		if r.outdoor and Vector2(r.rect.get_center()).distance_to(Vector2(spawn)) < 26.0:
			var c := _walkable_near(L, r.rect.get_center())
			if c.x >= 0:
				outs.append(c)
	for k in mini(outs.size(), 6):
		await _go(raid, outs[k], 0.35)
	if best != null:
		var ic := _walkable_near(L, best.rect.get_center())
		if ic.x >= 0:
			await _go(raid, ic, 1.6)
			await _shot("2_interieur")
	# Ruelle : salle extérieure étroite (≤ 4 cases de large) la plus proche, hors départ.
	var alley: FloorLayout.Room = null
	var alley_d := 1e30
	for r: FloorLayout.Room in L.rooms:
		if not r.outdoor or mini(r.rect.size.x, r.rect.size.y) > 4 or r.rect.has_point(spawn):
			continue
		var d := Vector2(r.rect.get_center()).distance_to(Vector2(spawn))
		if d > 8.0 and d < alley_d:
			alley_d = d
			alley = r
	var ac := _walkable_near(L, alley.rect.get_center()) if alley != null else Vector2i(-1, -1)
	if ac.x >= 0:
		print("ruelle : ", alley.name, " ", ac)
		await _go(raid, ac, 2.0)
	else:
		await _go(raid, spawn, 2.0)
	await _shot("3_ruelle")
	get_tree().quit(0)


func _walkable_near(L: FloorLayout, c: Vector2i) -> Vector2i:
	for rad in 4:
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var p := c + Vector2i(dx, dy)
				if L.in_bounds(p) and FloorLayout.is_walkable_tile(L.get_tile(p)) and L.get_tile(p) != FloorLayout.Tile.DOOR:
					return p
	return Vector2i(-1, -1)
