extends Node
## Scénario des captures de menus (voir ui_capture.gd) : <out>/splash_<n>.png, menu.png,
## mort.png, extraction.png (écrans de fin construits sur un résumé d'exemple).

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
	get_tree().change_scene_to_file("res://scenes/ui/menus/splash.tscn")
	await _sleep(0.4)
	await _shot("splash_1")
	await _sleep(1.2)
	await _shot("splash_2")
	get_tree().change_scene_to_file(MenuKit.MAIN_MENU_SCENE)
	await _sleep(2.0)
	await _shot("menu")
	for ok: bool in [false, true]:
		var s := RaidEndScreen.create(ok, _summary(ok))
		get_tree().root.add_child(s)
		await _sleep(0.6)
		await _shot(("extraction" if ok else "mort") + "_anim")
		await _sleep(1.8)
		await _shot("extraction" if ok else "mort")
		s.queue_free()
		get_tree().paused = false
		await _sleep(0.3)
	get_tree().quit(0)


func _summary(ok: bool) -> Dictionary:
	var d := {
		"unlock_kills": [],
		"pass_xp": {"xp": 340, "tier_before": 4, "tier_after": 5, "total_before": 1450, "total_after": 1790,
			"breakdown": BattlePassSystem.raid_xp_breakdown({"success": ok, "value": 640, "kills": 7, "time": 412.0})},
		"raider": {"xp": 220, "level_before": 6, "level_after": 7, "unlocks": [],
			"total_before": RaiderProgress.xp_total_for(7) - 120, "total_after": RaiderProgress.xp_total_for(7) + 100},
		"stats": {"kills": 7, "time": 412.0, "floor": -1, "killer": "" if ok else "Le Shérif Sable-Fou"},
	}
	if ok:
		d.merge({"weapons": [&"rifle_m4a1", &"smg_mp5"], "items": {&"gold_nugget": 3, &"pocket_watch": 1}, "value": 640, "gems": 3})
	else:
		d.merge({"lost_weapons": [&"rifle_m4a1", &"smg_mp5"], "starter_given": false, "lost_items": 6, "lost_value": 420, "lost_estimate": 380})
	return d
