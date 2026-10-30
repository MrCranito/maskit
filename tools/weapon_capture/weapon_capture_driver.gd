extends Node
## Scénario des captures d'armes (voir weapon_capture.gd).
## Images : <out>/arsenal_<n>.png (écran d'arsenal, défilé section par section), puis pour chaque
## arme de --weapons : <out>/tir_<id>.png (le joueur la tient et tire vers la droite, IA gelée).

const MAP_PATH := "res://data/maps/perm_dust_creek.tres"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const ARSENAL_SCENE := "res://scenes/ui/menus/arsenal.tscn"
const SEED := 20261030

var out: String = ""
var weapons: PackedStringArray = PackedStringArray()
## --dirs : en plus, <out>/dir_<id>_<k>.png (8 directions de tir, en marchant).
var dirs: bool = false


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--weapons="):
			weapons = a.substr(10).split(",", false)
		elif a == "--dirs":
			dirs = true
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


## `around` : recadre l'image sur ce nœud (carré de 30 % de la hauteur de l'écran).
## `flash` : attend que l'éclair de bouche soit visible et capture cette image-là.
func _shot(n: String, around: Node2D = null, flash: CanvasItem = null) -> void:
	if flash != null:
		var until := Time.get_ticks_msec() + 1500
		while not flash.visible and Time.get_ticks_msec() < until:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
	else:
		await _frames(3)
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null and is_instance_valid(around):
		var p: Vector2 = around.get_global_transform_with_canvas().origin
		var s := int(img.get_height() * 0.3)
		var r := Rect2i(Vector2i(p) - Vector2i(s / 2, s / 2), Vector2i(s, s))
		r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		img = img.get_region(r)
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out)
		var p := out.path_join("%s.png" % n)
		img.save_png(p)
		print("capture ", p)


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer and (n as ScrollContainer).is_visible_in_tree():
		return n as ScrollContainer
	for c: Node in n.get_children():
		var s := _find_scroll(c)
		if s != null:
			return s
	return null


func _run() -> void:
	# 1. Écran d'arsenal : une capture par écran, en défilant jusqu'en bas.
	get_tree().change_scene_to_file(ARSENAL_SCENE)
	await _sleep(1.5)
	var scroll := _find_scroll(get_tree().current_scene)
	var page := 0
	await _shot("arsenal_%d" % page)
	if scroll != null:
		var bar := scroll.get_v_scroll_bar()
		var step := int(scroll.size.y * 0.85)
		while scroll.scroll_vertical + int(scroll.size.y) < int(bar.max_value) and page < 8:
			scroll.scroll_vertical += step
			page += 1
			await _sleep(0.3)
			await _shot("arsenal_%d" % page)
	# 2. Raid : le joueur tire avec chaque arme demandée.
	if weapons.is_empty():
		get_tree().quit(0)
		return
	GameState.set_current_map(load(MAP_PATH) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("WeaponCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	if is_instance_valid(raid.enemies_container):
		raid.enemies_container.process_mode = Node.PROCESS_MODE_DISABLED
	var player := raid.player as Player
	var move_stick := TouchJoystick.new()
	var aim_stick := TouchJoystick.new()
	aim_stick.side = &"right"
	player.set_joysticks(move_stick, aim_stick)
	await _sleep(1.5)
	for id: String in weapons:
		var w := WeaponCatalog.get_weapon(StringName(id))
		if w == null:
			push_warning("WeaponCapture: arme inconnue %s" % id)
			continue
		var list: Array[WeaponData] = [w]
		player.set_weapons(list)
		aim_stick.output = Vector2.ZERO
		await _sleep(0.6)
		aim_stick.output = Vector2.RIGHT
		# Grenades en cloche : capture en vol ; balles et plombs : capture juste après le tir.
		await _sleep(0.35 if w.projectile_style == &"grenade" else 0.12)
		await _shot("tir_%s" % id)
		aim_stick.output = Vector2.ZERO
		await _sleep(0.8)
		if dirs:
			# 8 directions en marchant dans le sens du tir (prise en main, bouche du canon), sans HUD.
			if is_instance_valid(raid.hud):
				raid.hud.visible = false
			for k in 8:
				var d := Vector2.RIGHT.rotated(k * TAU / 8.0)
				move_stick.output = d * 0.6
				aim_stick.output = d
				await _sleep(0.12 if k % 2 == 0 else 0.18)
				var fl: CanvasItem = player.find_child("MuzzleFlash", true, false) as CanvasItem
				await _shot("dir_%s_%d" % [id, k], player, fl)
				# Retour au point de départ (reste dans la zone éclairée).
				aim_stick.output = Vector2.ZERO
				move_stick.output = -d * 0.6
				await _sleep(0.18)
				move_stick.output = Vector2.ZERO
				await _sleep(0.3)
			if is_instance_valid(raid.hud):
				raid.hud.visible = true
	get_tree().quit(0)
