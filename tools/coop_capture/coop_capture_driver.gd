extends Node
## Scénario des captures coop (voir coop_capture.gd). Le coéquipier est simulé : session
## NetSession non connectée (envois ignorés), paquets injectés dans CoopRaid._on_packet.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"

var out: String = ""
var only: String = ""
## Suffixe des fichiers (« 1280x720 ») ; par défaut la taille du viewport.
var tag: String = ""
var _raid: Raid = null
var _coop: CoopRaid = null
var _session: NetSession = null


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
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
		var vp := get_tree().root.get_visible_rect().size
		var t := tag if tag != "" else "%dx%d" % [int(vp.x), int(vp.y)]
		img.save_png(out.path_join("%s_%s.png" % [n, t]))
		print("capture ", n)


func _want(group: String) -> bool:
	return only == "" or only.split(",").has(group)


func _run() -> void:
	if _want("fin"):
		await _end_screens()
	if _want("menu") and has_method(&"_menus"):
		await call(&"_menus")
	get_tree().quit(0)


# --- Raid coop simulé --------------------------------------------------------------------

func _session_new(host: bool) -> NetSession:
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
	s.peer_info = {"k": "info", "name": "Moreau", "skin": "char_gign", "ready": true, "where": "lobby"}
	return s


func _raid_start(host: bool) -> void:
	_session = _session_new(host)
	_raid = (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	get_tree().root.add_child(_raid)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_coop = CoopRaid.new()
	_coop.name = "Coop"
	_coop.setup(_raid, _session)
	_raid.add_child(_coop)
	var w := NetProtocol.Writer.new()
	w.begin(NetProtocol.Msg.RAID_HELLO)
	w.u32(_raid.run_seed & 0xFFFFFFFF)
	w.i8(_raid.current_floor)
	w.u8(1)
	w.end()
	_coop._on_packet(w.bytes())
	var st := NetProtocol.PlayerState.new()
	st.time_ms = NetProtocol.now_ms()
	st.floor_index = _raid.current_floor
	st.position = _raid.player.global_position + Vector2(60, 10)
	st.hp_ratio = 1.0
	var w2 := NetProtocol.Writer.new()
	NetProtocol.write_state(w2, st)
	_coop._on_packet(w2.bytes())
	await _sleep(1.0)


func _evt(op: int) -> void:
	var w := NetProtocol.Writer.new()
	w.begin(NetProtocol.Msg.PLAYER_EVT)
	w.u8(op)
	w.f32(0.0)
	w.end()
	_coop._on_packet(w.bytes())


func _raid_stop() -> void:
	_session.status = NetSession.Status.OFFLINE  # pas de « leave » réseau
	_raid.queue_free()
	_raid = null
	get_tree().paused = false
	await _sleep(0.4)


func _end_screens() -> void:
	# Avant (comportement de main) : l'hôte quitte le salon pendant que l'invité joue encore →
	# l'invité n'a pas d'écran de fin, seulement le panneau « Hôte déconnecté ».
	await _raid_start(false)
	_session.room_closed.emit("host_left")
	await _sleep(0.8)
	await _shot("avant_fin_invite_hote_parti")
	await _raid_stop()
	# Après : l'hôte a fini et reste sur son écran de fin (salon ouvert, raid en marche).
	await _raid_start(true)
	await _raid._finish_extraction()
	await _sleep(0.3)
	_coop.quit_spectating()
	await _sleep(2.4)
	await _shot("apres_fin_hote_coequipier_en_raid")
	await _raid_stop()
	# Après : l'invité finit à son tour et a bien son écran de fin.
	await _raid_start(false)
	_evt(NetProtocol.PlayerOp.EXTRACTED)
	await _raid._finish_extraction()
	await _sleep(2.4)
	await _shot("apres_fin_invite")
	await _raid_stop()
