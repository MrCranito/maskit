extends Node
## Scénario des captures des emplacements rapides (au-dessus du stick de déplacement) :
##   godot --path . --resolution 1560x720 -s res://tools/hud_capture/hud_capture.gd -- \
##       --scenario=quick --out=C:/dossier/captures --tag=1560x720
## Pour chaque étape : <out>/<tag>_<étape>.png (écran entier) et <tag>_<étape>_zoom.png (zone des
## emplacements agrandie ×3). Étapes : deux soins, PV pleins (soin grisé), un emplacement vide,
## deux vides, équipement Légendaire + whisky, puis utilisation (flash) et après (chiffre décrémenté).

const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030
const ZOOM := 3

var out: String = ""
var tag: String = "quick"
var _player: Node2D = null


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
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img == null or out == "":
		return
	DirAccess.make_dir_recursive_absolute(out)
	var p := out.path_join("%s_%s.png" % [tag, n])
	img.save_png(p)
	print("capture ", p)
	# Zone des emplacements rapides (rects du HUD, image en pixels de fenêtre).
	var hud := get_tree().root.find_child("WeaponHud", true, false) as Control
	if hud == null:
		return
	var vp := hud.get_viewport_rect().size
	var lay: Dictionary = WeaponHud.compute_layout(vp, HudSafeArea.margins(hud), 2)
	var zone := Rect2()
	for k: String in ["quick0", "quick1"]:
		if lay.has(k):
			zone = lay[k] if zone.size == Vector2.ZERO else zone.merge(lay[k])
	zone = zone.grow_individual(40, 60, 40, 30)
	var sx := float(img.get_width()) / vp.x
	var sy := float(img.get_height()) / vp.y
	var px := Rect2i(int(zone.position.x * sx), int(zone.position.y * sy), int(zone.size.x * sx), int(zone.size.y * sy))
	px = px.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(px)
	crop.resize(crop.get_width() * ZOOM, crop.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	var pz := out.path_join("%s_%s_zoom.png" % [tag, n])
	crop.save_png(pz)
	print("capture ", pz)


func _set_hp(v: float) -> void:
	_player.set("hp", v)
	EventBus.player_damaged.emit(0.0, v, float(_player.get("max_hp")))


func _fresh_inventory(entries: Array) -> Inventory:
	var inv := Inventory.from_balance()
	inv.quick_auto_assign = false
	for e: Array in entries:
		inv.add_item(LootDB.get_item(e[0]), int(e[1]))
	GameState.raid_inventory = inv
	return inv


func _run() -> void:
	GameState.set_current_map(load(MAP_PATH) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("QuickCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	var player := raid.player as Player
	_player = player
	var move_stick := get_tree().get_first_node_in_group(TouchJoystick.GROUP_MOVE) as TouchJoystick
	var aim_stick := get_tree().get_first_node_in_group(TouchJoystick.GROUP_AIM) as TouchJoystick
	for s: TouchJoystick in [move_stick, aim_stick]:
		if s != null:
			s.set_enabled(true)
	player.set_joysticks(move_stick, aim_stick)
	await _sleep(1.5)
	var list: Array[WeaponData] = [WeaponCatalog.get_weapon(&"rifle_ak47"), WeaponCatalog.get_weapon(&"smg_mp5")]
	player.set_weapons(list)
	player.set_gadget(WeaponCatalog.get_weapon(&"gadget_frag"))
	# 1. Deux soins, PV entamés.
	var inv := _fresh_inventory([[&"bandage", 3], [&"medkit", 1]])
	inv.assign_quick(0, LootDB.get_item(&"bandage"))
	inv.assign_quick(1, LootDB.get_item(&"medkit"))
	_set_hp(40.0)
	await _sleep(0.6)
	await _shot("1_soins")
	# 2. PV pleins : les soins ne servent à rien.
	_set_hp(float(player.max_hp))
	await _sleep(0.4)
	await _shot("2_pv_pleins")
	# 3. Un emplacement libre.
	_set_hp(40.0)
	inv.clear_quick(1)
	await _sleep(0.4)
	await _shot("3_un_vide")
	# 4. Deux emplacements libres.
	inv.clear_quick(0)
	await _sleep(0.4)
	await _shot("4_vides")
	# 5. Équipement Légendaire (drone) + whisky.
	inv = _fresh_inventory([[&"wpn_gadget_drone", 1], [&"whisky", 2]])
	inv.assign_quick(0, LootDB.get_item(&"wpn_gadget_drone"))
	inv.assign_quick(1, LootDB.get_item(&"whisky"))
	await _sleep(0.6)
	await _shot("5_equipement")
	# 6. Utilisation du whisky : flash + rebond du chiffre, puis état final.
	player.use_quick(1)
	await _shot("6_utilisation")
	await _sleep(0.8)
	await _shot("7_apres")
	get_tree().quit(0)
