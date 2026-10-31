extends Node
## Scénario des captures de la mort (voir death_capture.gd) : <out>/vie_100.png, vie_degats.png
## (traînée), vie_basse.png (sous 25 %), vie_soin.png, puis mort_1.png (impact), mort_2.png
## (chute, monde assombri), mort_3.png (titre + tueur), fin.png (écran de fin).
## IA gelée ; attentes en temps réel (le ralenti de la mort ralentit les minuteurs).

const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030

var out: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	for i in 2:
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
			push_error("DeathCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	var player := raid.player as Player
	await _sleep(1.5)
	await _shot("vie_100")
	player.take_damage(38.0, null)
	await _sleep(0.12)
	await _shot("vie_degats")
	await _sleep(1.2)
	player._invulnerable_left = 0.0
	player.take_damage(44.0, null)
	await _sleep(1.3)
	await _shot("vie_basse")
	player.heal(30.0)
	await _sleep(0.12)
	await _shot("vie_soin")
	await _sleep(1.2)
	player.hp = 0.0
	player.last_hit_by = "Pistolero"
	player._die()
	var d := DeathOverlay.outro_time()
	await _sleep(0.12)
	await _shot("mort_1")
	await _sleep(d * 0.3)
	await _shot("mort_2")
	await _sleep(d * 0.45)
	await _shot("mort_3")
	await _sleep(d * 0.25 + 1.2)
	await _shot("fin")
	get_tree().quit(0)
