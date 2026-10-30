extends GutTest
## Visibilité du coop : emplacement de coéquipier au menu principal, salon (cartes côte à côte,
## place vide « + »), « Rejouer ensemble » après un raid coop. Sans réseau : la session est
## simulée (statut IN_ROOM sans connexion, envois ignorés).

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"

var _session: NetSession = null
var _saved_gs: Dictionary = {}
var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	# Le salon fixe la carte (difficulté, seed) dans GameState : restauré après chaque test.
	_saved_gs = {"current_map": GameState.current_map, "difficulty": GameState.difficulty,
		"run_seed": GameState.run_seed, "world_path": GameState.world_path}
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""


func after_each() -> void:
	get_tree().paused = false
	for k: String in _saved_gs:
		GameState.set(k, _saved_gs[k])
	NetHooks.reset()
	if is_instance_valid(_session):
		_session.status = NetSession.Status.OFFLINE
		_session.free()
	_session = null
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


## Session globale (« /root/Net ») dans un salon, coéquipier présent ou non.
func _room(host: bool, with_peer: bool) -> NetSession:
	var old := NetSession.current()
	if old != null:
		old.free()
	_session = NetSession.new()
	_session.name = NetSession.NODE_NAME
	get_tree().root.add_child(_session)
	_session.role = NetSession.ROLE_HOST if host else NetSession.ROLE_GUEST
	_session.status = NetSession.Status.IN_ROOM
	_session.room_code = "K7QX2M"
	_session.peer_present = with_peer
	_session.peer_connected = with_peer
	_session.peer_name = "Moreau" if with_peer else ""
	_session.peer_info = {"k": "info", "name": "Moreau", "skin": "char_gign", "ready": true, "where": "lobby"} if with_peer else {}
	return _session


# --- Session ------------------------------------------------------------------------------

func test_session_keeps_peer_info_without_lobby_screen() -> void:
	var s := _room(true, true)
	s._note_lobby({"k": "info", "name": "Moreau", "skin": "char_sas", "where": "menu", "ready": false})
	assert_eq(s.peer_where(), "menu")
	assert_eq(String(s.peer_info["skin"]), "char_sas")
	s.set_local_where("end")
	assert_eq(String(s.local_info["where"]), "end")
	assert_false(bool(s.local_info["ready"]), "hors du salon, jamais prêt")
	assert_eq(s.party_size(), 2)


func test_lobby_status_texts() -> void:
	assert_eq(CoopLobby.status_text({"ready": true}, true, "lobby"), "Prêt")
	assert_eq(CoopLobby.status_text({"ready": false}, true, "lobby"), "Choisit son arsenal…")
	assert_eq(CoopLobby.status_text({}, true, "menu"), "Au menu principal")
	assert_eq(CoopLobby.status_text({}, true, "end"), "Sur l'écran de fin")
	assert_eq(CoopLobby.status_text({"ready": true}, false, "lobby"), "Connexion perdue…")


# --- Menu principal -----------------------------------------------------------------------

func test_main_menu_plus_slot_in_solo() -> void:
	var old := NetSession.current()
	if old != null:
		old.free()
	var m := (load(MenuKit.MAIN_MENU_SCENE) as PackedScene).instantiate() as MainMenu
	add_child_autofree(m)
	await wait_process_frames(3)
	assert_not_null(m.mate_plus, "bouton « + » à côté du héros")
	assert_true(m.mate_plus.visible)
	assert_gte(m.mate_plus.size.x * m.lobby.stage.scale.x, 88.0, "cible tactile confortable à l'écran")
	assert_true(m.lobby.mate == null or not m.lobby.mate.visible, "pas de coéquipier en solo")
	assert_false(MainMenu.in_coop_room(), "solo : DÉPLOYER garde le choix des cartes")


func test_main_menu_shows_teammate_side_by_side() -> void:
	_room(true, true)
	var m := (load(MenuKit.MAIN_MENU_SCENE) as PackedScene).instantiate() as MainMenu
	add_child_autofree(m)
	await wait_process_frames(3)
	assert_false(m.mate_plus.visible, "coéquipier là : plus de « + »")
	assert_not_null(m.lobby.mate)
	assert_true(m.lobby.mate.visible)
	assert_eq(m.lobby.mate.sheet_id, "gign", "le skin du coéquipier est affiché")
	assert_gt(m.lobby.mate.position.x, m.lobby.hero.position.x, "côte à côte, à droite du héros")
	assert_eq(m.mate_tag.text, "Moreau")
	assert_true(MainMenu.in_coop_room(), "salon ouvert : DÉPLOYER ramène au salon")
	# Le coéquipier quitte le salon : le « + » revient.
	_session.peer_present = false
	_session.peer_left.emit("left")
	await wait_process_frames(2)
	assert_true(m.mate_plus.visible)
	assert_false(m.lobby.mate.visible)


# --- Salon ---------------------------------------------------------------------------------

func test_lobby_cards_side_by_side_and_empty_slot() -> void:
	_room(true, false)
	var lobby := (load(MenuKit.COOP_SCENE) as PackedScene).instantiate() as CoopLobby
	add_child_autofree(lobby)
	await wait_process_frames(3)
	var cards := lobby._cards.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	assert_eq(cards.size(), 2)
	assert_not_null(cards[1].find_child("InviteButton", true, false), "place vide : « + »")
	assert_string_contains((cards[1].find_child("WaitLabel", true, false) as Label).text, "coéquipier")
	_session.peer_present = true
	_session.peer_connected = true
	_session.peer_info = {"k": "info", "name": "Moreau", "skin": "char_gign", "ready": true, "where": "lobby"}
	lobby._refresh_room()
	await wait_process_frames(2)
	cards = lobby._cards.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	assert_eq(cards.size(), 2)
	assert_not_null(cards[0].find_child("Hero", true, false), "hôte à gauche")
	assert_eq((cards[1].find_child("Name", true, false) as Label).text, "Moreau", "invité à droite")
	var ready: Node = cards[1].find_child("Ready", true, false)
	assert_not_null(ready, "état « prêt » visible")


func test_lobby_back_keeps_room_and_resume_restores_map() -> void:
	var s := _room(true, true)
	var card := load("res://data/maps/perm_dust_creek.tres") as MapCard
	if card == null:
		for f: String in DirAccess.get_files_at("res://data/maps"):
			if f.ends_with(".tres"):
				card = load("res://data/maps/" + f) as MapCard
				if card != null:
					break
	assert_not_null(card)
	s.lobby_map = {"k": "map", "path": card.resource_path, "seed": 12}
	var lobby := (load(MenuKit.COOP_SCENE) as PackedScene).instantiate() as CoopLobby
	add_child_autofree(lobby)
	await wait_process_frames(3)
	assert_eq(lobby.map_card, card, "carte du salon conservée au retour")
	assert_false(lobby.local_ready, "chacun revalide son arsenal")
	assert_eq(String(s.local_info.get("where", "")), "lobby")
	lobby.go_back()
	assert_true(s.in_room(), "retour au menu sans quitter le salon")
	assert_eq(String(s.local_info.get("where", "")), "menu")


# --- Rejouer ensemble ----------------------------------------------------------------------

func test_replay_together_keeps_room() -> void:
	var s := _room(true, true)
	var raid := (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child(raid)
	await wait_physics_frames(2)
	var coop := CoopRaid.new()
	coop.name = "Coop"
	coop.setup(raid, s)
	raid.add_child(coop)
	var w := NetProtocol.Writer.new()
	w.begin(NetProtocol.Msg.RAID_HELLO)
	w.u32(raid.run_seed & 0xFFFFFFFF)
	w.i8(raid.current_floor)
	w.u8(1)
	w.end()
	w.begin(NetProtocol.Msg.PLAYER_EVT)
	w.u8(NetProtocol.PlayerOp.EXTRACTED)
	w.f32(0.0)
	w.end()
	coop._on_packet(w.bytes())
	await wait_physics_frames(2)
	assert_false(coop.can_replay(), "raid pas fini : pas de « Rejouer »")
	await raid._finish_extraction()
	await get_tree().create_timer(0.6, true).timeout
	assert_true(is_instance_valid(raid.end_screen))
	assert_true(coop.can_replay(), "les deux ont fini, coéquipier dans le salon")
	assert_true(raid.end_screen.is_replay_enabled(), "bouton « Rejouer ensemble » actif")
	assert_eq(String(s.local_info.get("where", "")), "end")
	assert_true(coop.request_replay())
	assert_true(s.replay_requested)
	raid.free()
	assert_true(s.in_room(), "le raid quitté ne ferme pas le salon")
	# Le salon rouvert remet la demande à zéro.
	var lobby := (load(MenuKit.COOP_SCENE) as PackedScene).instantiate() as CoopLobby
	add_child_autofree(lobby)
	await wait_process_frames(2)
	assert_false(s.replay_requested)
	assert_true(s.in_room())


func test_replay_disabled_when_partner_left() -> void:
	var s := _room(false, true)
	var raid := (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child(raid)
	await wait_physics_frames(2)
	var coop := CoopRaid.new()
	coop.setup(raid, s)
	raid.add_child(coop)
	coop.partner_status = CoopRules.Status.DEAD
	coop.waiting = false
	raid._finish_death()
	await get_tree().create_timer(0.6, true).timeout
	assert_true(coop.can_replay())
	s.peer_present = false
	await get_tree().create_timer(0.6, true).timeout
	assert_false(coop.can_replay())
	assert_false(raid.end_screen.is_replay_enabled(), "coéquipier parti : bouton désactivé")
	assert_string_contains(raid.end_screen.get_note(), "quitté")
	raid.free()
