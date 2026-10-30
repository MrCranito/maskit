extends Node
## Scénario des captures d'affixes (voir affix_capture.gd). Images dans --out :
## loadout.png, arsenal.png, sac.png, statuts.png, tir.png, fin_extraction.png.

const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const LOADOUT_SCENE := "res://scenes/ui/menus/loadout.tscn"
const ARSENAL_SCENE := "res://scenes/ui/menus/arsenal.tscn"
const SEED := 20261030

var out: String = ""
var _aug: int = -1
var _scar: int = -1


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
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
		var p := out.path_join("%s.png" % n)
		img.save_png(p)
		print("capture ", p)


func _setup_profile() -> void:
	Profile.from_dict({})
	_aug = Profile.add_weapon(&"rifle_aug", [&"burn", &"shockwave"])
	_scar = Profile.add_weapon(&"rifle_scarh", [&"multishot", &"ricochet"])
	Profile.add_weapon(&"rifle_m4a1", [&"freeze"])
	Profile.add_weapon(&"rifle_m4a1")
	Profile.add_weapon(&"smg_p90", [&"lifesteal"])
	Profile.add_weapon(&"pistol_p9")
	Profile.add_weapon(&"rifle_ak47")
	Profile.set_loadout([_aug, _scar] as Array[int])
	Profile.save()


func _run() -> void:
	_setup_profile()
	# 1. Arsenal de départ (fiche de l'AUG à affixes).
	GameState.set_current_map(load(MAP_PATH) as Resource, false)
	get_tree().change_scene_to_file(LOADOUT_SCENE)
	await _sleep(1.5)
	await _shot("loadout")
	var lo := get_tree().current_scene as ArsenalScreen
	if lo != null:
		for t: WeaponTile in lo.tiles:
			if t.weapon.id == &"pistol_p9":
				lo.show_weapon_detail(t.weapon, false)
		await _sleep(0.4)
		await _shot("loadout_sans_affixe")
	# 2. Arsenal (collection) : section des fusils d'assaut, fiche du M4A1 « Gel ».
	get_tree().change_scene_to_file(ARSENAL_SCENE)
	await _sleep(1.5)
	var ars := get_tree().current_scene as ArsenalScreen
	if ars != null:
		for t: WeaponTile in ars.tiles:
			if t.weapon.id == &"rifle_m4a1" and t.weapon.has_rolled_affixes():
				ars.show_weapon_detail(t.weapon, false)
				if ars.sections.has(WeaponData.CAT_RIFLE):
					var grid: Control = ars.sections[WeaponData.CAT_RIFLE]
					ars._scroll.scroll_vertical = int(grid.position.y) - 60
				break
	await _sleep(0.6)
	await _shot("arsenal")
	# 3. Raid : sac avec des armes à affixes.
	GameState.run_seed = SEED
	GameState.begin_raid()
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("AffixCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	await _sleep(1.5)
	var bag: Inventory = GameState.raid_inventory
	bag.add_item(Affixes.make_item(LootDB.get_item(&"wpn_sniper_m82"), [&"freeze", &"lifesteal"]), 1)
	bag.add_item(Affixes.make_item(LootDB.get_item(&"wpn_smg_vector"), [&"ricochet"]), 1)
	bag.add_item(LootDB.get_item(&"wpn_rifle_ak47"), 1)
	bag.add_item(LootDB.get_item(&"gold_nugget"), 2)
	var hud := raid.ui_layer.get_node_or_null(^"InventoryHud") as InventoryHud
	if hud != null:
		hud.inventory_screen.open()
		await _sleep(0.4)
		for i in bag.capacity():
			var s := bag.get_slot(i)
			if not s.is_empty() and (s["item"] as ItemData).weapon_id == &"sniper_m82":
				hud.inventory_screen.selected = i
				hud.inventory_screen._refresh()
		await _sleep(0.3)
		await _shot("sac")
		hud.inventory_screen.close()
		await _sleep(0.4)
	# 4. Statuts : brûlure et gel sur les ennemis les plus proches (anneaux au sol).
	var player := raid.player as Player
	var near: Array = []
	for e: Node in get_tree().get_nodes_in_group(&"enemies"):
		if e is Node2D:
			near.append(e)
	near.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	if near.size() >= 1:
		AffixStatus.apply_burn(near[0], 30.0, 30.0, player)
	if near.size() >= 2:
		AffixStatus.apply_slow(near[1], 0.4, 30.0)
		AffixStatus.apply_burn(near[1], 30.0, 30.0, player)
	if near.size() >= 1:
		player.global_position = (near[0] as Node2D).global_position + Vector2(-160, 40)
		await _sleep(0.8)
		await _shot("statuts")
	# 5. Tir : SCAR-H multi-tir + ricochet (deux balles par tir).
	var move_stick := TouchJoystick.new()
	var aim_stick := TouchJoystick.new()
	aim_stick.side = &"right"
	player.set_joysticks(move_stick, aim_stick)
	var scar := Profile.get_weapon_data(_scar)
	if scar == null:
		scar = Affixes.make_weapon(WeaponCatalog.get_weapon(&"rifle_scarh"), [&"multishot", &"ricochet"])
	player.set_weapons([scar] as Array[WeaponData])
	await _sleep(0.5)
	aim_stick.output = Vector2.RIGHT
	await _sleep(0.12)
	await _shot("tir")
	aim_stick.output = Vector2.ZERO
	await _sleep(0.6)
	# 6. Extraction : écran de fin avec les armes à affixes.
	raid._finish_extraction()
	await _sleep(2.5)
	await _shot("fin_extraction")
	get_tree().quit(0)
