extends Node
## Scénario des captures « armes visibles partout » (voir armes_capture.gd).
## Profil de test : AK-47 en arme principale avec le skin « Tigre » équipé, skin de perso par défaut.
## Coéquipier simulé (Moreau, skin GIGN) : M82 + RPG-7 avec skins d'armes à lui.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const SHOP_SCENE := "res://scenes/ui/menus/shop.tscn"
const PASS_SCENE := "res://scenes/ui/menus/battle_pass.tscn"
## Planche : [arme, skin d'arme du coéquipier ("" = aucun)].
const PLANCHE: Array = [
	["pistol_glock18", ""], ["pistol_deagle", "wsk_deagle_gold"], ["smg_mp5", "wsk_mp5_desert"],
	["smg_vector", "wsk_vector_neon"], ["rifle_ak47", ""], ["rifle_aug", "wsk_aug_flames"],
	["sniper_m82", "wsk_m82_night"], ["rocket_rpg7", "wsk_rpg7_rust"],
]
const MATE_LOADOUT: Array[String] = ["sniper_m82", "rocket_rpg7"]
const MATE_SKINS: Array[String] = ["wsk_m82_night", "wsk_rpg7_rust"]

var out: String = ""
var only: String = ""
var prefix: String = ""


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--prefix="):
			prefix = a.substr(9)
	_run.call_deferred()


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


func _want(group: String) -> bool:
	return only == "" or only.split(",").has(group)


func _run() -> void:
	_setup_profile()
	if _want("menu"):
		await _menus()
	if _want("salon"):
		await _lobby()
	if _want("boutique"):
		await _shop()
	if _want("galerie"):
		await _gallery()
	if _want("planche"):
		await _planche()
	if _want("raid"):
		await _raid()
	get_tree().quit(0)


func _setup_profile() -> void:
	Profile.weapons.clear()
	Profile.loadout.clear()
	var ak := Profile.add_weapon(&"rifle_ak47")
	var mp5 := Profile.add_weapon(&"smg_mp5")
	Profile.set_loadout([ak, mp5] as Array[int])
	Profile.skin_character = &""
	Profile.skin_weapons = {}
	for s: StringName in [&"wsk_ak47_tiger"]:
		if not Profile.skins_owned.has(s):
			Profile.skins_owned.append(s)
		WeaponSkin.equip(s)
	Profile.changed.emit()


# --- Session simulée --------------------------------------------------------------------

func _session(host: bool) -> NetSession:
	var s := NetSession.current()
	if s == null:
		s = NetSession.new()
		s.name = NetSession.NODE_NAME
		get_tree().root.add_child(s)
	s.role = NetSession.ROLE_HOST if host else NetSession.ROLE_GUEST
	s.status = NetSession.Status.IN_ROOM
	s.room_code = "K7QX2M"
	s.peer_name = "Moreau"
	s.peer_present = true
	s.peer_connected = true
	s.peer_info = {"k": "info", "name": "Moreau", "skin": "char_gign", "ready": true, "where": "lobby",
		"gv": NetProtocol.GAME_VERSION, "loadout": MATE_LOADOUT.duplicate(), "wskins": MATE_SKINS.duplicate()}
	return s


func _offline() -> void:
	var s := NetSession.current()
	if s != null:
		s.status = NetSession.Status.OFFLINE
		s.room_code = ""
		s.role = &""
		s.peer_present = false
		s.peer_connected = false
		s.peer_info = {}
		s.local_info = {}


func _scene(path: String, wait: float = 2.2) -> Node:
	get_tree().change_scene_to_file(path)
	await _sleep(wait)
	return get_tree().current_scene


# --- Menus ------------------------------------------------------------------------------

func _menus() -> void:
	_offline()
	await _scene(MenuKit.MAIN_MENU_SCENE)
	await _shot("menu_seul")
	var s := _session(true)
	s.peer_info["where"] = "menu"
	await _scene(MenuKit.MAIN_MENU_SCENE)
	await _shot("menu_avec_coequipier")
	_offline()


func _lobby() -> void:
	_session(true)
	await _scene(MenuKit.COOP_SCENE, 1.6)
	var lobby := get_tree().current_scene
	if lobby != null and lobby.has_method(&"_refresh_room"):
		lobby.call(&"_refresh_room")
	await _sleep(0.8)
	await _shot("salon_coop")
	_offline()


func _shop() -> void:
	if not ResourceLoader.exists(SHOP_SCENE):
		return
	var shop := await _scene(SHOP_SCENE, 1.5)
	if shop != null and shop.has_method(&"show_tab"):
		shop.call(&"show_tab", &"character")
		await _sleep(0.8)
	await _shot("boutique_personnages")
	if ResourceLoader.exists(PASS_SCENE):
		await _scene(PASS_SCENE, 1.5)
		await _shot("pass_de_combat")


# --- Galerie : héros des menus tenant chaque arme (skins d'armes imposés) ---------------------

func _gallery() -> void:
	_offline()
	var layer := CanvasLayer.new()
	get_tree().root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = MenuKit.NIGHT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var skins: Array[StringName] = [&"", &"char_gign", &"char_desert", &"char_cyber"]
	for i: int in PLANCHE.size():
		var hp := HeroPreview.new()
		hp.position = Vector2(10 + (i % 4) * 315, 10 + (i / 4) * 355)
		hp.size = Vector2(300, 340)
		bg.add_child(hp)
		hp.set_skin(SkinData.get_skin(skins[i % skins.size()]), false)
		var wid := StringName(String(PLANCHE[i][0]))
		var sk := String(PLANCHE[i][1])
		hp.set_weapon(WeaponCatalog.get_weapon(wid), {String(wid): sk} if sk != "" else {})
		if hp.hero != null:
			hp.hero.idle_amount = 0.0
	await _sleep(0.8)
	await _shot("galerie_menu_armes")
	layer.queue_free()
	await _sleep(0.2)


# --- Planche : coéquipiers tenant chaque arme ---------------------------------------------

func _avatar(parent: Node, label: String, wid: String, skin: String, char_skin: StringName) -> CoopAvatar:
	var a := CoopAvatar.create(label, char_skin)
	parent.add_child(a)
	var args: Array = [[wid] as Array[String], 0, "", 0, -1.0]
	if a.get_method_argument_count(&"apply_loadout") > 5:
		args.append([skin] as Array[String])
	a.callv(&"apply_loadout", args)
	return a


func _state(a: CoopAvatar, pos: Vector2, aim: Vector2) -> void:
	var st := NetProtocol.PlayerState.new()
	st.time_ms = NetProtocol.now_ms()
	st.position = pos
	st.aim = aim.normalized()
	st.hp_ratio = 1.0
	st.flags = NetProtocol.F_AIMING
	a.apply_state(st)
	a.aim_direction = aim.normalized()


func _planche() -> void:
	_offline()
	var root := Node2D.new()
	root.name = "Planche"
	var bg := ColorRect.new()
	bg.color = Color(0.72, 0.58, 0.42)
	bg.position = Vector2(-2000, -2000)
	bg.size = Vector2(4000, 4000)
	bg.z_index = -50
	root.add_child(bg)
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.5, 1.5)
	root.add_child(cam)
	get_tree().root.add_child(root)
	var old := get_tree().current_scene
	if old != null:
		old.queue_free()
	get_tree().current_scene = root
	cam.make_current()
	var avatars: Array[Array] = []
	for i: int in PLANCHE.size():
		var wid: String = PLANCHE[i][0]
		var sk: String = PLANCHE[i][1]
		var w := WeaponCatalog.get_weapon(StringName(wid))
		for row: int in 2:
			var label := (w.display_name if w != null else wid) + ("" if sk == "" else " ★")
			var a := _avatar(root, label if row == 0 else " ", wid, sk, &"char_gign" if row == 1 else &"")
			var pos := Vector2(-370 + (i % 4) * 245 + (110 if row == 1 else 0), -95 + (i / 4) * 230 + (row * 95))
			avatars.append([a, pos, Vector2(1, 0.15) if row == 0 else Vector2(-1, 0.35)])
	for k: int in 6:
		for e: Array in avatars:
			_state(e[0], e[1], e[2])
		await get_tree().physics_frame
	await _sleep(0.8)
	await _shot("planche_coequipiers")
	root.queue_free()
	await _sleep(0.3)


# --- Raid coop simulé ---------------------------------------------------------------------

func _raid() -> void:
	var session := _session(true)
	var raid := (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	get_tree().root.add_child(raid)
	var old := get_tree().current_scene
	if old != null and old != raid:
		old.queue_free()
	get_tree().current_scene = raid
	await get_tree().physics_frame
	await get_tree().physics_frame
	var coop := CoopRaid.new()
	coop.name = "Coop"
	coop.setup(raid, session)
	raid.add_child(coop)
	var w := NetProtocol.Writer.new()
	w.begin(NetProtocol.Msg.RAID_HELLO)
	w.u32(raid.run_seed & 0xFFFFFFFF)
	w.i8(raid.current_floor)
	w.u8(1)
	w.end()
	# Arsenal du coéquipier (skins d'armes à la fin du message : ignorés par une ancienne version).
	w.begin(NetProtocol.Msg.LOADOUT)
	w.text("Moreau")
	w.text("char_gign")
	w.u8(MATE_LOADOUT.size())
	for id: String in MATE_LOADOUT:
		w.text(id)
	w.u8(1)
	w.text("")
	w.u8(0)
	w.f32(100.0)
	for sk: String in MATE_SKINS:
		w.text(sk)
	w.end()
	coop._on_packet(w.bytes())
	var p := raid.player
	# Arsenal de départ du profil (le raid de capture ne passe pas par Profile.start_raid).
	p.loadout.set_weapons(Profile.get_loadout_weapons())
	p.call(&"_on_weapon_changed", false)
	var cam := p.get_node_or_null(^"Camera2D") as Camera2D
	if cam != null:
		cam.zoom = Vector2(2.4, 2.4)
	for k: int in 30:
		var st := NetProtocol.PlayerState.new()
		st.time_ms = NetProtocol.now_ms()
		st.floor_index = raid.current_floor
		st.position = p.global_position + Vector2(70, 18)
		st.aim = Vector2(1, -0.2).normalized()
		st.flags = NetProtocol.F_AIMING
		st.slot = 1
		st.hp_ratio = 1.0
		var w2 := NetProtocol.Writer.new()
		NetProtocol.write_state(w2, st)
		coop._on_packet(w2.bytes())
		await get_tree().physics_frame
	await _sleep(0.8)
	await _shot("raid_coop")
	session.status = NetSession.Status.OFFLINE
	raid.queue_free()
	get_tree().paused = false
	await _sleep(0.4)
