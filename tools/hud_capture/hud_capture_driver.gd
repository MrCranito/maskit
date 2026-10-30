extends Node
## Scénario des captures du HUD (voir hud_capture.gd). Images <out>/<tag>_<étape>.png.

const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030

var out: String = ""
var tag: String = "hud"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
	_run.call_deferred()


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(n: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out)
		var p := out.path_join("%s_%s.png" % [tag, n])
		img.save_png(p)
		print("capture ", p)


func _run() -> void:
	GameState.set_current_map(load(MAP_PATH) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("HudCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	var player := raid.player as Player
	var move_stick := get_tree().get_first_node_in_group(TouchJoystick.GROUP_MOVE) as TouchJoystick
	var aim_stick := get_tree().get_first_node_in_group(TouchJoystick.GROUP_AIM) as TouchJoystick
	for s: TouchJoystick in [move_stick, aim_stick]:
		if s != null:
			s.set_enabled(true)
	player.set_joysticks(move_stick, aim_stick)
	await _sleep(1.5)
	# Soins en emplacements rapides (affectés automatiquement au ramassage).
	GameState.raid_inventory.add_item(LootDB.get_item(&"bandage"), 3)
	GameState.raid_inventory.add_item(LootDB.get_item(&"medkit"), 1)
	player.set_gadget(WeaponCatalog.get_weapon(&"gadget_frag"))
	var sets: Array = [[&"pistol_p9"], [&"pistol_p9", &"smg_mp5"], [&"rifle_ak47", &"smg_mp5", &"shotgun_870"]]
	for k in sets.size():
		var list: Array[WeaponData] = []
		for id: StringName in sets[k]:
			var w := WeaponCatalog.get_weapon(id)
			if w == null:
				w = WeaponCatalog.get_starter()
			list.append(w)
		player.set_weapons(list)
		await _sleep(0.5)
		await _shot("%d_armes" % (k + 1))
	# Quelques tirs (chargeur bas : Recharger s'allume), puis rechargement en cours.
	aim_stick.output = Vector2.RIGHT
	await _sleep(0.9)
	aim_stick.output = Vector2.ZERO
	await _sleep(0.3)
	await _shot("chargeur_bas")
	player.reload()
	await _sleep(0.25)
	await _shot("rechargement")
	await _sleep(3.0)
	# Déplacement sans viser : l'arme suit la marche.
	var dirs := {"droite": Vector2.RIGHT, "bas": Vector2.DOWN, "gauche": Vector2.LEFT, "haut": Vector2.UP}
	for n: String in dirs:
		move_stick.output = dirs[n]
		await _sleep(0.45)
		await _shot("marche_%s" % n)
	move_stick.output = Vector2.ZERO
	await _sleep(0.3)
	get_tree().quit(0)
