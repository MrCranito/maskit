class_name NetSession
extends Node
## Connexion au serveur relais (WebSocket) et salon coop. Un seul nœud, sous la racine
## (« /root/Net »), qui survit aux changements de scène (salon → raid → menu).
## Autoload conseillé (project.godot) :  Net="*res://scripts/net/net_session.gd"
## Sans autoload, NetSession.instance() le crée à la demande. Tant qu'aucun salon n'est ouvert,
## le nœud n'existe pas ou ne traite rien (set_process(false)) : aucun coût en solo.
##
## Cycle : OFFLINE → CONNECTING → ONLINE (hello/welcome, version vérifiée) → IN_ROOM
##   (créé ou rejoint) ; coupure en salon → RECONNECTING (tentatives toutes les
##   [net] reconnect_interval s pendant [net] reconnect_window s, reprise par jeton) → IN_ROOM,
##   sinon salon perdu.
## Ping applicatif toutes les [net] ping_interval s (latence affichée) ; silence du serveur plus
## de [net] silence_timeout s = connexion considérée comme morte (4G qui décroche).

signal status_changed(status: int)
## Erreur à afficher (code serveur ou local : unreachable, version, bad_code, not_found, full…).
signal error_received(code: String, message: String)
## Salon créé (hôte) ou rejoint (invité).
signal room_ready(code: String, role: StringName)
signal peer_joined(name: String)
signal peer_left(reason: String)
signal peer_lost(grace: float)
signal peer_back
## Salon fermé : reason = host_left, host_timeout, expired, lost (reprise impossible), timeout.
signal room_closed(reason: String)
## Message JSON du coéquipier (salon).
signal lobby_message(d: Dictionary)
## Paquet binaire de jeu du coéquipier.
signal game_packet(data: PackedByteArray)
signal connection_lost
signal reconnected

enum Status { OFFLINE, CONNECTING, ONLINE, IN_ROOM, RECONNECTING }

const NODE_NAME := "Net"
const ROLE_HOST := &"host"
const ROLE_GUEST := &"guest"

var status: int = Status.OFFLINE
var url: String = ""
var room_code: String = ""
var role: StringName = &""
var token: String = ""
var player_name: String = "Raider"
var peer_name: String = ""
## Le coéquipier est-il présent et connecté au relais ?
var peer_present: bool = false
var peer_connected: bool = false
## Latence aller-retour lissée (ms), -1 = inconnue.
var rtt_ms: float = -1.0
## Infos de salon du coéquipier (pseudo, skin, prêt, arsenal…) et les nôtres.
var peer_info: Dictionary = {}
var local_info: Dictionary = {}
## Raid coop demandé : Raid._ready l'attache (NetHooks.attach_raid) puis le remet à false.
var raid_pending: bool = false
## Paramètres du raid lancé (seed, carte…).
var raid_info: Dictionary = {}
## Dernière carte du salon ({path, seed, name, difficulty}) : choisie par l'hôte, annoncée à
## l'invité ; conservée quand on quitte l'écran du salon (menu principal, raid, « Rejouer »).
var lobby_map: Dictionary = {}
## « Rejouer ensemble » demandé depuis l'écran de fin : le raid quitté ne ferme pas le salon.
var replay_requested: bool = false
## Octets envoyés / reçus (debug F3, tests de budget).
var bytes_sent: int = 0
var bytes_received: int = 0

var _ws: WebSocketPeer = null
var _pending: Dictionary = {}       ## Action à faire après welcome (create / join / resume).
var _deadline: float = 0.0          ## Délai de connexion.
var _ping_left: float = 0.0
var _last_rx: float = 0.0
var _reconnect_until: float = 0.0
var _reconnect_left: float = 0.0
var _queue: Array[PackedByteArray] = []
var _early: Array[PackedByteArray] = []
var _was_open: bool = false
var _leaving: bool = false
var _clock: float = 0.0

# Réglages [net]
var connect_timeout: float = 6.0
var ping_interval: float = 2.0
var reconnect_window: float = 20.0
var reconnect_interval: float = 1.5
var silence_timeout: float = 8.0
var max_queue: int = 512
var max_outbound: int = 48 * 1024


## Session existante (sans la créer) : null en solo.
static func current() -> NetSession:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null or ml.root == null:
		return null
	return ml.root.get_node_or_null(NodePath(NODE_NAME)) as NetSession


## Session existante ou nouvelle (ajoutée à la racine, persistante).
static func instance() -> NetSession:
	var s := current()
	if s != null:
		return s
	var ml := Engine.get_main_loop() as SceneTree
	s = NetSession.new()
	s.name = NODE_NAME
	if ml != null and ml.root != null:
		ml.root.add_child.call_deferred(s)
	return s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	connect_timeout = Balance.get_float("net", "connect_timeout", connect_timeout)
	ping_interval = Balance.get_float("net", "ping_interval", ping_interval)
	reconnect_window = Balance.get_float("net", "reconnect_window", reconnect_window)
	reconnect_interval = Balance.get_float("net", "reconnect_interval", reconnect_interval)
	silence_timeout = Balance.get_float("net", "silence_timeout", silence_timeout)
	set_process(_ws != null)


## URL du relais : --net-url=… (ligne de commande), variable RAIDERSGO_NET_URL, puis
## balance.cfg [net] : url_prod si renseignée, hors éditeur (APK de test compris) ou si use_prod ;
## sinon url_dev (relais local de développement).
static func server_url() -> String:
	for a: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--net-url="):
			return a.substr(10)
	var env := OS.get_environment("RAIDERSGO_NET_URL")
	if env != "":
		return env
	var dev := String(Balance.get_value("net", "url_dev", "ws://127.0.0.1:8787"))
	var prod := String(Balance.get_value("net", "url_prod", ""))
	var use_prod := bool(Balance.get_value("net", "use_prod", false)) or not OS.has_feature("editor")
	return prod if use_prod and prod != "" else dev


func is_online() -> bool:
	return status == Status.ONLINE or status == Status.IN_ROOM


func in_room() -> bool:
	return status == Status.IN_ROOM or status == Status.RECONNECTING


func is_host() -> bool:
	return role == ROLE_HOST


# --- Actions --------------------------------------------------------------------------

func create_room(p_name: String) -> void:
	player_name = p_name
	_request({"t": "create", "name": p_name})


func join_room(code: String, p_name: String) -> void:
	player_name = p_name
	var c := LobbyCode.normalize(code)
	if not LobbyCode.is_valid(c):
		error_received.emit("bad_code", describe_error("bad_code"))
		return
	_request({"t": "join", "code": c, "name": p_name})


## Quitte le salon et ferme la connexion (hôte : le salon est fermé pour l'invité).
func leave() -> void:
	_leaving = true
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_json({"t": "leave"})
		_ws.close(1000, "leave")
	_reset_room()
	_ws = null
	_set_status(Status.OFFLINE)
	set_process(false)
	_leaving = false


## Paquets de jeu reçus avant que le raid ne les écoute (chargement de la scène).
func take_early_packets() -> Array[PackedByteArray]:
	var out := _early.duplicate()
	_early.clear()
	return out


## Message de salon (JSON) pour le coéquipier.
func send_lobby(d: Dictionary) -> void:
	if status == Status.IN_ROOM:
		_send_json({"t": "relay", "d": d})


## Paquet de jeu. `reliable` = gardé en file pendant une reconnexion (événements) ; l'état
## continu ne l'est pas (périmé de toute façon).
func send_game(data: PackedByteArray, reliable: bool = true) -> void:
	if data.is_empty():
		return
	if status == Status.IN_ROOM and _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if not reliable and _ws.get_current_outbound_buffered_amount() > max_outbound:
			return  # Lien saturé : on saute un état.
		_ws.put_packet(data)
		bytes_sent += data.size()
	elif reliable and status == Status.RECONNECTING and _queue.size() < max_queue:
		_queue.append(data)


func _request(msg: Dictionary) -> void:
	if status == Status.ONLINE:
		_send_json(msg)
		return
	_pending = msg
	if status == Status.OFFLINE:
		_open_socket()


func _open_socket() -> void:
	url = server_url()
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 256 * 1024
	_ws.outbound_buffer_size = 256 * 1024
	var err := _ws.connect_to_url(url)
	_was_open = false
	if err != OK:
		_ws = null
		if status != Status.RECONNECTING:
			_set_status(Status.OFFLINE)
			error_received.emit("unreachable", describe_error("unreachable"))
		return
	if status != Status.RECONNECTING:
		_set_status(Status.CONNECTING)
	_deadline = _clock + connect_timeout
	set_process(true)


func _send_json(d: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(d))


# --- Boucle ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	if status == Status.RECONNECTING and _ws == null:
		_tick_reconnect(delta)
		return
	if _ws == null:
		set_process(false)
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_was_open = true
			_last_rx = _clock
			_send_json({"t": "hello", "v": NetProtocol.VERSION, "app": "raidersgo"})
		while _ws.get_available_packet_count() > 0:
			var pkt := _ws.get_packet()
			_last_rx = _clock
			bytes_received += pkt.size()
			if _ws.was_string_packet():
				_on_text(pkt.get_string_from_utf8())
			elif game_packet.get_connections().is_empty():
				# Raid en cours de chargement : gardé pour CoopRaid (take_early_packets).
				if _early.size() < max_queue:
					_early.append(pkt)
			else:
				game_packet.emit(pkt)
			if _ws == null:
				return
		if is_online():
			_ping_left -= delta
			if _ping_left <= 0.0:
				_ping_left = ping_interval
				_send_json({"t": "ping", "ts": Time.get_ticks_msec()})
			if _clock - _last_rx > silence_timeout:
				_ws.close(4000, "silence")
				_on_socket_closed()
	elif st == WebSocketPeer.STATE_CONNECTING:
		if _clock > _deadline:
			_ws.close()
			_on_socket_closed()
	elif st == WebSocketPeer.STATE_CLOSED:
		_on_socket_closed()


func _on_socket_closed() -> void:
	_ws = null
	if _leaving:
		return
	if status == Status.IN_ROOM or status == Status.RECONNECTING:
		if status == Status.IN_ROOM:
			_reconnect_until = _clock + reconnect_window
			_reconnect_left = 0.0
			_set_status(Status.RECONNECTING)
			connection_lost.emit()
		return
	var was := status
	_set_status(Status.OFFLINE)
	_pending = {}
	if was == Status.CONNECTING:
		error_received.emit("unreachable", describe_error("unreachable"))
	set_process(false)


func _tick_reconnect(delta: float) -> void:
	if _clock > _reconnect_until:
		_reset_room()
		_set_status(Status.OFFLINE)
		set_process(false)
		room_closed.emit("unreachable")
		return
	_reconnect_left -= delta
	if _reconnect_left > 0.0:
		return
	_reconnect_left = reconnect_interval
	_pending = {"t": "resume", "code": room_code, "token": token}
	_open_socket()


func _on_text(text: String) -> void:
	var v: Variant = JSON.parse_string(text)
	if not (v is Dictionary):
		return
	var m: Dictionary = v
	match String(m.get("t", "")):
		"welcome":
			if status != Status.RECONNECTING:
				_set_status(Status.ONLINE)
			if not _pending.is_empty():
				_send_json(_pending)
				_pending = {}
		"created":
			_enter_room(String(m.get("code", "")), String(m.get("token", "")), ROLE_HOST)
			peer_present = false
		"joined":
			_enter_room(String(m.get("code", "")), String(m.get("token", "")), ROLE_GUEST)
			var peer: Dictionary = m.get("peer", {})
			peer_name = String(peer.get("name", "Hôte"))
			peer_present = true
			peer_connected = bool(peer.get("connected", true))
		"resumed":
			_set_status(Status.IN_ROOM)
			var p2: Variant = m.get("peer")
			peer_present = p2 is Dictionary
			peer_connected = peer_present and bool((p2 as Dictionary).get("connected", true))
			for q: PackedByteArray in _queue:
				_ws.put_packet(q)
				bytes_sent += q.size()
			_queue.clear()
			reconnected.emit()
		"peer_joined":
			peer_name = String(m.get("name", "Invité"))
			peer_present = true
			peer_connected = true
			peer_joined.emit(peer_name)
		"peer_left":
			peer_present = false
			peer_connected = false
			peer_info = {}
			peer_left.emit(String(m.get("reason", "left")))
		"peer_lost":
			peer_connected = false
			peer_lost.emit(float(m.get("grace_ms", 15000)) / 1000.0)
		"peer_back":
			peer_connected = true
			peer_back.emit()
		"room_closed":
			var reason := String(m.get("reason", "host_left"))
			_reset_room()
			_set_status(Status.ONLINE)
			room_closed.emit(reason)
		"relay":
			var d: Variant = m.get("d")
			if d is Dictionary:
				_note_lobby(d)
				lobby_message.emit(d)
		"pong":
			var sample := float(Time.get_ticks_msec() - int(m.get("ts", 0)))
			rtt_ms = sample if rtt_ms < 0.0 else lerpf(rtt_ms, sample, 0.3)
		"error":
			_on_error(String(m.get("code", "error")), String(m.get("message", "")))


func _on_error(code: String, message: String) -> void:
	if status == Status.RECONNECTING and (code == "not_found" or code == "bad_token"):
		# Reprise impossible : le salon n'existe plus ou notre place a expiré.
		_reset_room()
		_set_status(Status.ONLINE)
		room_closed.emit(code)
		return
	if code == "version":
		_pending = {}
	error_received.emit(code, describe_error(code) if describe_error(code) != "" else message)


## Messages de salon retenus même sans écran de salon ouvert (menu principal, écran de fin) :
## infos du coéquipier (pseudo, skin, prêt, où il est), carte de l'hôte ; « sync » = le
## coéquipier revient au salon et redemande nos infos.
func _note_lobby(d: Dictionary) -> void:
	match String(d.get("k", "")):
		"info":
			peer_info = d
		"map":
			if not is_host():
				lobby_map = d
		"sync":
			if not local_info.is_empty():
				send_lobby(local_info)


## Où en est-on (« lobby », « menu », « raid », « end ») : mémorisé et annoncé au coéquipier.
## Hors du salon, on n'est jamais prêt.
func set_local_where(where: String) -> void:
	if not in_room():
		return
	if local_info.is_empty():
		local_info = {"k": "info", "gv": NetProtocol.GAME_VERSION, "name": player_name}
	local_info["where"] = where
	if where != "lobby":
		local_info["ready"] = false
	send_lobby(local_info)


## Où est le coéquipier (« lobby » par défaut : anciennes versions sans ce champ).
func peer_where() -> String:
	return String(peer_info.get("where", "lobby"))


## Nombre de joueurs du salon (1 ou 2).
func party_size() -> int:
	return 2 if in_room() and peer_present else 1


func _enter_room(code: String, p_token: String, p_role: StringName) -> void:
	room_code = code
	token = p_token
	role = p_role
	_set_status(Status.IN_ROOM)
	room_ready.emit(code, p_role)


func _reset_room() -> void:
	room_code = ""
	token = ""
	role = &""
	peer_name = ""
	peer_present = false
	peer_connected = false
	peer_info = {}
	local_info = {}
	lobby_map = {}
	replay_requested = false
	raid_pending = false
	_queue.clear()
	_early.clear()
	_pending = {}


func _set_status(s: int) -> void:
	if s == status:
		return
	status = s
	status_changed.emit(s)


## Message clair pour chaque code d'erreur.
static func describe_error(code: String) -> String:
	match code:
		"unreachable":
			return "Serveur injoignable. Vérifie ta connexion Internet et réessaie."
		"version":
			return "Version différente du serveur : mets le jeu à jour."
		"game_version":
			return "Ton coéquipier n'a pas la même version du jeu."
		"bad_code":
			return "Code invalide : 6 caractères (lettres et chiffres)."
		"not_found":
			return "Salon introuvable : vérifie le code (il est peut-être fermé)."
		"full":
			return "Salon plein : il y a déjà deux joueurs."
		"server_full":
			return "Serveur plein, réessaie dans un instant."
		"rate":
			return "Trop de messages envoyés : connexion coupée."
		"bad_token":
			return "Reconnexion refusée : ta place dans le salon a expiré."
	return ""


static func status_text(s: int) -> String:
	match s:
		Status.OFFLINE:
			return "Hors ligne"
		Status.CONNECTING:
			return "Connexion…"
		Status.ONLINE:
			return "En ligne"
		Status.IN_ROOM:
			return "Dans le salon"
		Status.RECONNECTING:
			return "Reconnexion…"
	return "?"
