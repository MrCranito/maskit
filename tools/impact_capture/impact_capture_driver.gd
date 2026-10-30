extends Node
## Scénario des captures d'impacts (voir impact_capture.gd).
## Station Kagami, seed fixe ; trois ennemis du raid replacés en file devant le joueur (IA gelée,
## visuels toujours animés : flash, à-coup), puis rafales au ralenti (Engine.time_scale).
## Images : <out>/<prefix>_<arme>_<n>.png.

const MAP_PATH := "res://data/maps/perm_station_kagami.tres"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SEED := 20261030

var out: String = ""
var prefix: String = "shot"
var weapons: PackedStringArray = PackedStringArray(["lmg_m60", "pistol_glock18"])
var time_scale: float = 0.2


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
		elif a.begins_with("--weapons="):
			weapons = a.substr(10).split(",", false)
		elif a.begins_with("--time-scale="):
			time_scale = float(a.substr(13))
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _sleep(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await _frames(1)
	var img := get_tree().root.get_viewport().get_texture().get_image()
	if img != null and out != "":
		DirAccess.make_dir_recursive_absolute(out)
		var p := out.path_join("%s_%s.png" % [prefix, n])
		img.save_png(p)
		print("capture ", p)


## Direction la plus dégagée (raycast monde) depuis `from`, parmi 16.
func _free_direction(player: Node2D) -> Vector2:
	var space := player.get_world_2d().direct_space_state
	var best := Vector2.RIGHT
	var best_d := -1.0
	for i: int in 16:
		var d := Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
		var q := PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + d * 520.0, 1)
		var res := space.intersect_ray(q)
		var dist: float = 520.0 if res.is_empty() else player.global_position.distance_to(res["position"])
		if dist > best_d + 1.0:
			best_d = dist
			best = d
	return best


func _run() -> void:
	GameState.set_current_map(load(MAP_PATH) as Resource, false)
	GameState.run_seed = SEED
	get_tree().change_scene_to_file(RAID_SCENE)
	var until := Time.get_ticks_msec() + 30000
	while not (get_tree().current_scene is Raid and is_instance_valid((get_tree().current_scene as Raid).player)):
		if Time.get_ticks_msec() > until:
			push_error("ImpactCapture: raid introuvable")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var raid := get_tree().current_scene as Raid
	var player := raid.player as Player
	await _sleep(1.5)
	var dir := _free_direction(player)
	# Trois ennemis vivants, IA gelée, replacés en file devant le joueur.
	var picked: Array[Enemy] = []
	for n: Node in raid.enemies_container.get_children():
		var e := n as Enemy
		if e == null or not e.is_alive() or e.data == null or e.data.boss:
			continue
		picked.append(e)
		if picked.size() >= 3:
			break
	for i: int in picked.size():
		var e := picked[i]
		e.set_physics_process(false)
		if e.state_machine != null:
			e.state_machine.process_mode = Node.PROCESS_MODE_DISABLED
		e.hp = 1.0e6
		e.global_position = player.global_position + dir * (150.0 + 85.0 * float(i))
		e.reset_physics_interpolation()
		print("ennemi ", i, " : ", e.data.kind)
	var move_stick := TouchJoystick.new()
	var aim_stick := TouchJoystick.new()
	aim_stick.side = &"right"
	player.set_joysticks(move_stick, aim_stick)
	await _sleep(1.0)
	for id: String in weapons:
		var w := WeaponCatalog.get_weapon(StringName(id))
		if w == null:
			continue
		var list: Array[WeaponData] = [w]
		player.set_weapons(list)
		aim_stick.output = dir * 0.2
		await _sleep(0.6)
		Engine.time_scale = time_scale
		aim_stick.output = dir
		for k: int in 6:
			await _frames(4)
			await _shot("%s_%d" % [id, k])
		aim_stick.output = Vector2.ZERO
		Engine.time_scale = 1.0
		await _sleep(0.8)
	get_tree().quit(0)
