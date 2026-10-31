extends Node
## Scénario des captures de l'arène de test (voir arena_capture.gd).

var out: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	_run.call_deferred()


func _run() -> void:
	await _sleep(0.5)
	# Choix des cartes : vignette « Arène de test » sélectionnée.
	get_tree().change_scene_to_file(MenuKit.MAP_SELECT_SCENE)
	await _sleep(2.0)
	var ms: Node = get_tree().current_scene
	for e: Dictionary in TestArena.rotation_entries():
		ms.call("select_entry", e, false)
		var t: Variant = ms.call("_tile_for", e)
		var sc: ScrollContainer = ms.get("_scroll")
		if t is Control and sc != null:
			sc.ensure_control_visible(t as Control)
	await _sleep(0.6)
	await _shot("cartes_arene")
	# Arène : un fusil d'assaut en main.
	var c := TestArena.card()
	GameState.set_current_map(c)
	GameState.raid_inventory = Inventory.from_balance()
	var rifle: WeaponData = null
	for w: WeaponData in WeaponCatalog.all():
		if w.category == WeaponData.CAT_RIFLE and w.rarity >= 3:
			rifle = w
			break
	var held: Array[WeaponData] = []
	if rifle != null:
		held.append(rifle)
	GameState.raid_weapons = held
	get_tree().change_scene_to_file(MenuKit.RAID_SCENE)
	await _sleep(2.5)
	var raid := get_tree().current_scene as Raid
	if raid == null or raid.test_arena == null:
		push_error("arena_capture : arène absente")
		get_tree().quit(1)
		return
	await _shot("arene")
	# Mannequins touchés (compteurs), ennemis apparus, panneau ouvert.
	for i: int in raid.test_arena.dummies.size():
		var d: ArenaDummy = raid.test_arena.dummies[i]
		for k: int in 6 + i * 4:
			d.take_damage(18.0 + 7.0 * k, null)
	await _sleep(0.4)
	await _shot("arene_mannequins")
	for a: Dictionary in TestArena.archetypes().slice(0, 3):
		raid.test_arena.spawn_enemy(a["kind"], 1)
	raid.test_arena.panel.set_open(true)
	await _sleep(0.8)
	await _shot("arene_panneau")
	get_tree().quit(0)


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