extends Node
## Scénario des captures de menus (voir ui_capture.gd) : <out>/splash_<n>.png, menu.png,
## boutique*.png (onglets, onglet Gemmes avec le dernier pack choisi), icones.png (gemme et pièce :
## dessin en code puis images peintes), mort.png, extraction.png (écrans de fin sur un résumé d'exemple).

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
	# splash_0..4 : première image (= boot.png), ouverture, composition, fin ; instants en temps
	# de jeu (les captures ralentissent l'horloge murale)
	var t: float = 0.0
	for step: Array in [["splash_0", 0.0], ["splash_1", 0.45], ["splash_2", 0.7], ["splash_3", 1.2], ["splash_4", 2.4]]:
		if float(step[1]) > t:
			await _sleep(float(step[1]) - t)
			t = float(step[1])
		await _shot(step[0])
	get_tree().change_scene_to_file(MenuKit.MAIN_MENU_SCENE)
	await _sleep(2.0)
	await _shot("menu")
	if ResourceLoader.exists("res://scenes/ui/menus/shop.tscn"):
		get_tree().change_scene_to_file("res://scenes/ui/menus/shop.tscn")
		await _sleep(1.5)
		await _shot("boutique")
		for tab: StringName in [&"gems", &"packs"]:
			get_tree().current_scene.call(&"show_tab", tab)
			await _sleep(0.8)
			await _shot("boutique_" + String(tab))
		get_tree().current_scene.call(&"show_tab", &"gems")
		await _sleep(0.3)
		var offers: Variant = get_tree().current_scene.get(&"offers")
		if offers is ShopOffers:
			(offers as ShopOffers).select(Store.packs().size() - 1)
			await _sleep(0.6)
			await _shot("boutique_gems_dernier")
	await _icons()
	var cl := CoopLoadout.new()
	get_tree().root.add_child(cl)
	await _sleep(1.0)
	await _shot("arsenal_depart_coop")
	cl.queue_free()
	await _sleep(0.2)
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


## icones.png : gemme et pièce d'or, dessin en code (en haut) puis images peintes (en bas), en grand
## et aux tailles des compteurs (48, 32, 24 px).
func _icons() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	get_tree().root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = MenuKit.NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var y := 30.0
	for painted: bool in [false, true]:
		var x := 30.0
		for kind: int in 2:
			for px: float in [200.0, 48.0, 32.0, 24.0]:
				var c: Control = GemIcon.new() if kind == 0 else GoldCounter.CoinIcon.new()
				c.set(&"use_art", painted)
				c.position = Vector2(x, y + (200.0 - px) * 0.5)
				c.size = Vector2(px, px)
				bg.add_child(c)
				x += px + 30.0
			x += 40.0
		y += 260.0
	await _sleep(0.3)
	await _shot("icones")
	layer.queue_free()


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
