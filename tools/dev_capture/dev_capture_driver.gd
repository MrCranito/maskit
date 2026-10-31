extends Node
## Scénario des captures du mode développeur (voir dev_capture.gd).

var out: String = ""
var prefix: String = ""
var unlock: bool = false


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
		elif a.begins_with("--unlock="):
			unlock = a.substr(9) == "1"
	_run.call_deferred()


func _run() -> void:
	await _sleep(0.5)
	# Script chargé par chemin : l'outil tourne aussi sur une branche sans « Tout débloquer ».
	var dm: Script = load("res://scripts/core/dev_mode.gd")
	if unlock and dm.has_method(&"set_all_unlocked"):
		dm.call(&"set_all_unlocked", true)
	get_tree().change_scene_to_file(MenuKit.MAIN_MENU_SCENE)
	await _sleep(2.5)
	var mm := get_tree().current_scene as MainMenu
	if mm != null:
		mm.open_options()
		await _sleep(0.8)
		await _shot("options")
		# Bas de la fenêtre (section développeur) si elle défile.
		var modal: Node = mm.get("_modal")
		var sc := modal.find_child("OptionsScroll", true, false) as ScrollContainer if modal != null else null
		if sc != null:
			sc.scroll_vertical = 100000
			await _sleep(0.3)
			await _shot("options_bas")
	# Panneau F3 (section développeur) par-dessus le menu.
	_set_debug(true)
	await _sleep(0.4)
	if mm != null and is_instance_valid(mm.get("_modal")):
		(mm.get("_modal") as Node).queue_free()
	await _sleep(0.3)
	await _shot("panneau_f3")
	_set_debug(false)
	for step: Array in [["cartes", MenuKit.MAP_SELECT_SCENE], ["arsenal", MenuKit.ARSENAL_SCENE],
			["pass", MenuKit.BATTLE_PASS_SCENE]]:
		get_tree().change_scene_to_file(String(step[1]))
		await _sleep(2.0)
		await _shot(String(step[0]))
	get_tree().quit(0)


## Autoloads lus par nom (un script SceneTree ne voit pas leurs identifiants).
func _set_debug(on: bool) -> void:
	get_tree().root.get_node(^"GameState").set("debug_enabled", on)
	get_tree().root.get_node(^"EventBus").emit_signal(&"debug_toggled", on)


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
