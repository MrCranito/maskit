extends SceneTree
## Captures du mode développeur : fenêtre Options (section dev), panneau F3, choix des cartes,
## arsenal et pass de combat avec « Tout débloquer ».
##   godot --path . --resolution 1280x720 -s res://tools/dev_capture/dev_capture.gd -- --out=C:/dossier [--unlock=1] [--prefix=xxx]
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.

var out: String = ""
var prefix: String = ""
var unlock: bool = false


func _init() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
		elif a.begins_with("--unlock="):
			unlock = a.substr(9) == "1"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	await _sleep(0.5)
	if unlock and DevMode.has_method(&"set_all_unlocked"):
		DevMode.call(&"set_all_unlocked", true)
	change_scene_to_file(MenuKit.MAIN_MENU_SCENE)
	await _sleep(2.5)
	var mm := current_scene as MainMenu
	if mm != null:
		mm.open_options()
		await _sleep(0.8)
		await _shot("options")
	# Panneau F3 (section développeur) par-dessus le menu.
	GameState.debug_enabled = true
	EventBus.debug_toggled.emit(true)
	await _sleep(0.4)
	if mm != null and is_instance_valid(mm.get("_modal")):
		(mm.get("_modal") as Node).queue_free()
	await _sleep(0.3)
	await _shot("panneau_f3")
	GameState.debug_enabled = false
	EventBus.debug_toggled.emit(false)
	for step: Array in [["cartes", MenuKit.MAP_SELECT_SCENE], ["arsenal", MenuKit.ARSENAL_SCENE],
			["pass", MenuKit.BATTLE_PASS_SCENE]]:
		change_scene_to_file(String(step[1]))
		await _sleep(2.0)
		await _shot(String(step[0]))
	quit(0)


func _sleep(s: float) -> void:
	await create_timer(s, true).timeout


func _shot(n: String) -> void:
	for i in 3:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out)
		img.save_png(out.path_join(prefix + n + ".png"))
		print("capture ", prefix + n)
