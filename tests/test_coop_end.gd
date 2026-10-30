extends GutTest
## Fin de raid coop : l'écran de fin (RaidEndScreen) finit toujours par s'afficher, chez l'hôte
## comme chez l'invité, quel que soit l'ordre des fins (mort, extraction, abandon, déconnexion).
## Le raid tourne sans réseau : la session n'est pas connectée (envois ignorés) et les paquets
## du coéquipier sont injectés directement dans CoopRaid._on_packet.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"

var _raid: Raid = null
var _coop: CoopRaid = null
var _session: NetSession = null
var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""


func after_each() -> void:
	get_tree().paused = false
	NetHooks.reset()
	if is_instance_valid(_session):
		_session.queue_free()
	_session = null
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


## Raid coop hors ligne : `host` = rôle local.
func _start(host: bool) -> void:
	_session = NetSession.new()
	_session.name = "TestNet"
	_session.role = NetSession.ROLE_HOST if host else NetSession.ROLE_GUEST
	_session.peer_name = "Moreau"
	_session.peer_present = true
	_session.peer_connected = true
	_session.peer_info = {"name": "Moreau", "skin": ""}
	add_child(_session)
	_raid = (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child_autofree(_raid)
	await wait_physics_frames(2)
	_coop = CoopRaid.new()
	_coop.name = "Coop"
	_coop.setup(_raid, _session)
	_raid.add_child(_coop)
	# Le coéquipier est là : bonjour + un état (l'avatar a une position).
	_inject_hello()
	_inject_state(0)
	await wait_physics_frames(2)
	assert_false(_coop.waiting, "attente du coéquipier terminée")


func _inject_hello() -> void:
	var w := NetProtocol.Writer.new()
	w.begin(NetProtocol.Msg.RAID_HELLO)
	w.u32(_raid.run_seed & 0xFFFFFFFF)
	w.i8(_raid.current_floor)
	w.u8(1)
	w.end()
	_coop._on_packet(w.bytes())


func _inject_state(flags: int) -> void:
	var st := NetProtocol.PlayerState.new()
	st.time_ms = NetProtocol.now_ms()
	st.floor_index = _raid.current_floor
	st.position = _raid.player.global_position + Vector2(40, 0)
	st.flags = flags
	st.hp_ratio = 1.0
	var w := NetProtocol.Writer.new()
	NetProtocol.write_state(w, st)
	_coop._on_packet(w.bytes())


func _inject_evt(op: int, value: float = 0.0) -> void:
	var w := NetProtocol.Writer.new()
	w.begin(NetProtocol.Msg.PLAYER_EVT)
	w.u8(op)
	w.f32(value)
	w.end()
	_coop._on_packet(w.bytes())


func _end_screen_shown() -> bool:
	return is_instance_valid(_raid.end_screen) and _raid.end_screen.is_inside_tree()


# --- Scénarios --------------------------------------------------------------------------

func test_guest_dies_then_host_extracts() -> void:
	await _start(false)
	_raid._finish_death()
	assert_true(_coop.spectating, "invité mort : spectateur de l'hôte")
	assert_false(_end_screen_shown())
	_inject_evt(NetProtocol.PlayerOp.EXTRACTED)
	await wait_process_frames(2)
	assert_true(_end_screen_shown(), "l'hôte s'extrait : écran de fin chez l'invité")


func test_guest_extracts_then_host_dies() -> void:
	await _start(false)
	await _raid._finish_extraction()
	assert_true(_coop.spectating)
	_inject_evt(NetProtocol.PlayerOp.DEAD)
	await wait_process_frames(2)
	assert_true(_end_screen_shown(), "l'hôte meurt : écran de fin chez l'invité")


func test_guest_spectating_host_state_flags_first() -> void:
	# L'état continu (drapeau EXTRACTED) arrive avant l'événement fiable.
	await _start(false)
	_raid._finish_death()
	_inject_state(NetProtocol.F_EXTRACTED)
	_inject_evt(NetProtocol.PlayerOp.EXTRACTED)
	await wait_process_frames(2)
	assert_true(_end_screen_shown())


func test_guest_spectating_host_leaves_room() -> void:
	await _start(false)
	_raid._finish_death()
	_session.room_closed.emit("host_left")
	await wait_process_frames(2)
	assert_true(_end_screen_shown(), "salon fermé par l'hôte : écran de fin")


func test_guest_ends_after_host() -> void:
	await _start(false)
	_inject_evt(NetProtocol.PlayerOp.EXTRACTED)
	await _raid._finish_extraction()
	await wait_process_frames(2)
	assert_false(_coop.spectating)
	assert_true(_end_screen_shown(), "hôte déjà extrait : écran de fin direct")


func test_guest_dies_while_host_downed_then_host_bleeds_out() -> void:
	await _start(false)
	_inject_evt(NetProtocol.PlayerOp.DOWNED)
	_raid._finish_death()
	assert_true(_coop.spectating)
	_inject_evt(NetProtocol.PlayerOp.DEAD)
	await wait_process_frames(2)
	assert_true(_end_screen_shown())


func test_guest_abandon_shows_end_screen() -> void:
	await _start(false)
	_raid.abandon_raid()
	await wait_process_frames(2)
	assert_true(_end_screen_shown())


func test_guest_quits_spectating() -> void:
	await _start(false)
	_raid._finish_death()
	_coop.quit_spectating()
	await wait_process_frames(2)
	assert_true(_end_screen_shown())


func test_host_dies_then_guest_extracts() -> void:
	await _start(true)
	_raid._finish_death()
	assert_true(_coop.spectating)
	_inject_evt(NetProtocol.PlayerOp.EXTRACTED)
	await wait_process_frames(2)
	assert_true(_end_screen_shown(), "l'invité s'extrait : écran de fin chez l'hôte")


func test_host_spectating_guest_disconnects() -> void:
	await _start(true)
	await _raid._finish_extraction()
	_session.peer_left.emit("timeout")
	await wait_process_frames(2)
	assert_true(_end_screen_shown())


func test_guest_downed_bleeds_out_then_host_extracts() -> void:
	await _start(false)
	var p := _raid.player as Player
	p.take_damage(99999.0, null)  # invité : dégâts locaux bloqués
	NetHooks.applying_remote = true
	p.take_damage(99999.0, null)
	NetHooks.applying_remote = false
	assert_true(p.net_downed, "invité à terre (l'hôte peut le relever)")
	_coop._bleed_out()
	await wait_seconds(Balance.get_float("raid", "death_screen_delay", 2.0) + 0.5)
	assert_true(_raid.is_raid_over())
	assert_true(_coop.spectating)
	_inject_evt(NetProtocol.PlayerOp.EXTRACTED)
	await wait_process_frames(2)
	assert_true(_end_screen_shown())


# --- Salon gardé ouvert à la fin (bug : écran de fin absent chez l'invité) ---------------------

## Avant : l'hôte qui finissait (ou quittait le mode spectateur) quittait le salon 0,6 s plus
## tard ; le salon fermé coupait le raid de l'invité encore en jeu (panneau « Hôte déconnecté »,
## jamais d'écran de fin). Maintenant le salon reste ouvert tant que l'écran de fin est affiché.
func test_host_final_keeps_room_while_guest_plays() -> void:
	await _start(true)
	_session.status = NetSession.Status.IN_ROOM
	_session.room_code = "ABCDEF"
	await _raid._finish_extraction()
	assert_true(_coop.spectating, "hôte extrait : spectateur de l'invité")
	_coop.quit_spectating()
	await wait_seconds(1.2)
	assert_true(_end_screen_shown())
	assert_true(_session.in_room(), "le salon n'est pas quitté : l'invité continue son raid")
	assert_true(_coop.keeps_world_running())
	assert_false(get_tree().paused, "le raid de l'hôte tourne derrière l'écran de fin")
	assert_string_contains(_raid.end_screen.get_note(), "Moreau")
	# L'invité finit à son tour : la note disparaît.
	_inject_evt(NetProtocol.PlayerOp.EXTRACTED)
	await wait_process_frames(2)
	assert_eq(_raid.end_screen.get_note(), "")
	assert_false(_coop.keeps_world_running())


func test_guest_final_keeps_room() -> void:
	await _start(false)
	_session.status = NetSession.Status.IN_ROOM
	_session.room_code = "ABCDEF"
	_inject_evt(NetProtocol.PlayerOp.DEAD)
	await _raid._finish_extraction()
	# Écran de fin de l'invité : arbre en pause, minuterie qui tourne quand même.
	await get_tree().create_timer(1.2, true).timeout
	assert_true(_end_screen_shown())
	assert_true(_session.in_room(), "salon gardé jusqu'à la sortie de l'écran de fin")
