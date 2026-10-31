extends Node
## Scénario des captures de apk_capture.gd. IA gelée, seed fixe : images reproductibles.
## - dust / mall : décor pré-rendu (Dust Creek, Galeries Lumière), zoom autour du joueur ;
## - enemy : premier ennemi de Dust Creek posé à côté du joueur, zoom ×2 centré sur lui ;
## - menu : menu principal.

const MAPS := {
	"dust": "res://data/maps/perm_dust_creek.tres",
	"mall": "res://data/maps/perm_galeries_lumiere.tres",
	"enemy": "res://data/maps/perm_dust_creek.tres",
}
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261031

var out: String = ""
var prefix: String = "shot"
var only: PackedStringArray = PackedStringArray(["dust", "mall", "enemy", "menu"])


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(n: String, focus: Vector2 = Vector2.INF) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img == null or out == "":
		return
	DirAccess.make_dir_recursive_absolute(out)
	img.save_png(out.path_join("%s_%s.png" % [prefix, n]))
	print("capture ", n)
	var vp := get_tree().root.get_viewport()
	var sp := Vector2(img.get_width(), img.get_height()) * 0.5
	if focus != Vector2.INF:
		sp = vp.get_canvas_transform() * focus
	var w := img.get_width() / 2
	var h := img.get_height() / 2
	var x := clampi(int(sp.x) - w / 2, 0, img.get_width() - w)
	var y := clampi(int(sp.y) - h / 2, 0, img.get_height() - h)
	var crop := img.get_region(Rect2i(x, y, w, h))
	crop.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	crop.save_png(out.path_join("%s_%s_zoom.png" % [prefix, n]))


func _run() -> void:
	for n: String in only:
		if n == "menu":
			get_tree().change_scene_to_file(MenuKit.MAIN_MENU_SCENE)
			await _sleep(2.5)
			await _shot("menu")
		elif MAPS.has(n):
			await _raid_shot(n)
	get_tree().quit(0)


func _raid_shot(n: String) -> void:
	GameState.set_current_map(load(MAPS[n]) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 40000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("ApkCapture: raid introuvable")
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	await _sleep(2.0)
	if n != "enemy":
		await _sleep(1.5)
		await _shot(n, raid.player.global_position)
		return
	var enemy: Node2D = null
	for e: Node in get_tree().get_nodes_in_group(&"enemies"):
		if e is Node2D and raid.enemies_container.is_ancestor_of(e):
			enemy = e as Node2D
			break
	if enemy == null:
		push_error("ApkCapture: aucun ennemi")
		return
	# Joueur sur une case praticable à ~2 cases de l'ennemi (ligne de vue dégagée).
	var ec := FloorLayout.world_to_cell(enemy.global_position)
	var pc := ec
	for d: Vector2i in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(-1, 1), Vector2i(1, 1)]:
		if FloorLayout.is_walkable_tile(raid.layout.get_tile(ec + d)):
			pc = ec + d
			break
	raid.place_player(pc)
	await _sleep(2.5)
	print("ennemi ", enemy.name, " en ", ec, ", joueur en ", pc)
	await _shot(n, enemy.global_position)
