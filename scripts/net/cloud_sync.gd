extends Node
## Autoload CloudSync : compte joueur et sauvegarde cloud (Supabase, API REST via HTTPRequest).
##
## Principe « local d'abord » : SaveManager écrit toujours user://save.json ; CloudSync pousse
## ce fichier au serveur un peu après chaque écriture (regroupement), et le récupère à la
## connexion. Chaque joueur a un compte invité (connexion anonyme Supabase) créé au premier
## lancement, dont le jeton est conservé dans user://cloud_session.json (chiffré). La liaison
## Apple / Google (pour retrouver son compte sur un autre téléphone) viendra ensuite.
##
## Version : SaveManager.data["_cloud"] = {"version": int, "dirty": bool}. `version` = version
## serveur de la dernière sauvegarde synchronisée, `dirty` = modifications locales pas encore
## envoyées. Le serveur (fonction push_save) refuse un envoi dont la version de base n'est plus
## la sienne : c'est un conflit (joué sur deux appareils), tranché par le joueur (CloudConflictPanel).
##
## Rien ici ne crédite de gemmes : les achats vérifiés sont lus depuis le serveur (pull_state :
## gems_granted, entitlements) et exposés en lecture seule.

signal status_changed(status: StringName)
## Conflit entre la sauvegarde locale et celle du cloud : l'interface doit appeler resolve_conflict().
signal conflict_detected(local_info: Dictionary, remote_info: Dictionary)
## La sauvegarde du cloud vient d'être appliquée localement (les écrans doivent se rafraîchir).
signal remote_applied

const CFG_PATH := "res://data/cloud.cfg"
const SESSION_PATH := "user://cloud_session.json"
const META_KEY := "_cloud"

## disabled = pas de cloud (cloud.cfg) ; offline = pas de réseau / serveur injoignable ;
## syncing = envoi ou réception en cours ; synced = à jour ; conflict = en attente du joueur.
const STATUS_DISABLED := &"disabled"
const STATUS_OFFLINE := &"offline"
const STATUS_SYNCING := &"syncing"
const STATUS_SYNCED := &"synced"
const STATUS_CONFLICT := &"conflict"

enum Action { NOTHING, PUSH, PULL, CONFLICT }

var status: StringName = STATUS_DISABLED
var user_id: String = ""
var is_anonymous: bool = true
## Gemmes créditées par le serveur (achats vérifiés) et droits (ex. "pass_premium_s1"), lecture seule.
var gems_granted: int = 0
var entitlements: Array[String] = []
var last_error: String = ""
## Dernière sauvegarde distante en conflit : {"save": Dictionary, "version": int, "updated_at": String, "device": String}.
var pending_remote: Dictionary = {}

var _cfg := ConfigFile.new()
var _url: String = ""
var _key: String = ""
var _access_token: String = ""
var _refresh_token: String = ""
var _expires_at: int = 0
var _push_timer: Timer = null
var _retry_timer: Timer = null
var _applying: bool = false
var _busy: bool = false
var _booted: bool = false
var _push_wanted: bool = false


func _ready() -> void:
	_cfg.load(CFG_PATH)
	_url = str(_cfg.get_value("supabase", "url", "")).trim_suffix("/")
	_key = str(_cfg.get_value("supabase", "publishable_key", ""))
	_push_timer = Timer.new()
	_push_timer.one_shot = true
	_push_timer.timeout.connect(_on_push_timer)
	add_child(_push_timer)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(func() -> void: sync())
	add_child(_retry_timer)
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm != null and sm.has_signal(&"saved"):
		sm.connect(&"saved", _on_local_saved)
	if not enabled():
		_set_status(STATUS_DISABLED)
		return
	_set_status(STATUS_OFFLINE)
	OnlineMode.notifier.changed.connect(_on_online_mode)
	# Après le chargement local différé de Profile / BattlePass.
	_boot.call_deferred()


func enabled() -> bool:
	# Jamais en headless (tests GUT, CI) : pas de réseau.
	return bool(_cfg.get_value("supabase", "enabled", true)) and not _url.is_empty() and not _key.is_empty() \
		and DisplayServer.get_name() != "headless"


## Le joueur a choisi « Hors ligne » au lobby (OnlineMode) : aucune tentative réseau, les
## modifications restent « à pousser » et partent au retour en ligne.
func paused_by_player() -> bool:
	return not OnlineMode.is_online()


func _on_online_mode(online: bool) -> void:
	if not enabled():
		return
	if online:
		sync()
	else:
		_push_timer.stop()
		_retry_timer.stop()
		if status != STATUS_CONFLICT:
			_set_status(STATUS_OFFLINE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _push_timer != null and not _push_timer.is_stopped():
			_push_timer.stop()
			_on_push_timer()


# --- Informations pour l'interface ------------------------------------------------------

## Identifiant court du compte (6 derniers caractères), pour l'écran Options.
func short_id() -> String:
	return user_id.right(6).to_upper() if not user_id.is_empty() else "–"


static func status_label(s: StringName) -> String:
	match s:
		STATUS_SYNCED:
			return "Sauvegarde cloud à jour"
		STATUS_SYNCING:
			return "Synchronisation…"
		STATUS_CONFLICT:
			return "Conflit de sauvegarde"
		STATUS_OFFLINE:
			return "Mode hors ligne : sauvegarde locale" if not OnlineMode.is_online() else "Hors ligne : sauvegarde locale"
	return "Sauvegarde locale uniquement"


## Résumé lisible d'une sauvegarde (écran de conflit) : niveau, gemmes, armes, date.
static func describe_save(save: Dictionary, updated_at: String = "", device: String = "") -> Dictionary:
	var p: Variant = save.get("profile", {})
	var prof: Dictionary = p if p is Dictionary else {}
	var st: Variant = prof.get("stats", {})
	var stats: Dictionary = st if st is Dictionary else {}
	var weapons: Variant = prof.get("weapons", [])
	return {
		"raider_level": RaiderProgress.level_for_xp(int(prof.get("raider_xp", 0))),
		"gems": int(prof.get("gems", 0)),
		"gold": int(prof.get("gold", 0)),
		"weapons": (weapons as Array).size() if weapons is Array else 0,
		"raids": int(stats.get("raids", 0)),
		"updated_at": updated_at,
		"device": device,
	}


# --- Décision de synchronisation (pure, testée) ----------------------------------------------

## Que faire à la connexion, d'après la version locale, les modifications locales non envoyées,
## et l'état du serveur. Voir l'en-tête : la version locale 0 = appareil jamais synchronisé.
static func decide(local_version: int, local_dirty: bool, local_has_data: bool,
		remote_exists: bool, remote_version: int) -> Action:
	if not remote_exists:
		return Action.PUSH if local_has_data else Action.NOTHING
	if local_version <= 0:
		return Action.PULL
	if local_version == remote_version:
		return Action.PUSH if local_dirty else Action.NOTHING
	if local_version < remote_version:
		return Action.CONFLICT if local_dirty else Action.PULL
	return Action.PUSH


# --- Métadonnées dans la sauvegarde ---------------------------------------------------------

func _save_data() -> Dictionary:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	return (sm.get("data") as Dictionary) if sm != null else {}


func _meta() -> Dictionary:
	var m: Variant = _save_data().get(META_KEY, {})
	return m if m is Dictionary else {}


func local_version() -> int:
	return int(_meta().get("version", 0))


func is_dirty() -> bool:
	return bool(_meta().get("dirty", false))


func _write_meta(version: int, dirty: bool) -> void:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm == null:
		return
	(sm.get("data") as Dictionary)[META_KEY] = {"version": version, "dirty": dirty}
	_applying = true
	sm.call("save")
	_applying = false


## La sauvegarde sans les métadonnées cloud (ce qui est envoyé au serveur).
static func payload_of(data: Dictionary) -> Dictionary:
	var out := data.duplicate(true)
	out.erase(META_KEY)
	return out


static func has_content(data: Dictionary) -> bool:
	return data.has("profile") or data.has("battle_pass")


# --- Cycle de vie ---------------------------------------------------------------------------

func _on_local_saved() -> void:
	if _applying or not enabled():
		return
	var m := _meta()
	if not bool(m.get("dirty", false)):
		# « À pousser » est persisté tout de suite : si le jeu est tué avant l'envoi, le prochain
		# lancement saura qu'il y a des modifications locales (détection des conflits).
		_write_meta(int(m.get("version", 0)), true)
	if _booted and status != STATUS_CONFLICT and not paused_by_player():
		_push_timer.start(float(_cfg.get_value("sync", "push_delay", 2.0)))


func _on_push_timer() -> void:
	if _busy:
		_push_wanted = true
		return
	push()


func _boot() -> void:
	_booted = true
	await sync()


## Connexion (création du compte invité au premier lancement) puis réconciliation locale/cloud.
func sync() -> void:
	if not enabled() or _busy:
		return
	if paused_by_player():
		if status != STATUS_CONFLICT:
			_set_status(STATUS_OFFLINE)
		return
	_busy = true
	_set_status(STATUS_SYNCING)
	var ok := await _ensure_session()
	if ok:
		ok = await _reconcile()
	_busy = false
	if not ok and status != STATUS_CONFLICT:
		_set_status(STATUS_OFFLINE)
		_retry_timer.start(float(_cfg.get_value("sync", "retry_delay", 20.0)))
	elif _push_wanted:
		_push_wanted = false
		push()


## Envoie la sauvegarde locale (si des modifications sont en attente).
func push() -> void:
	if not enabled() or _busy or status == STATUS_CONFLICT or paused_by_player():
		return
	_busy = true
	var ok := await _ensure_session()
	if ok:
		ok = await _push_local(local_version())
	_busy = false
	if not ok and status != STATUS_CONFLICT:
		_set_status(STATUS_OFFLINE)
		_retry_timer.start(float(_cfg.get_value("sync", "retry_delay", 20.0)))


## Tranche un conflit : keep_local = garder ce téléphone (et écraser le cloud), sinon prendre le cloud.
func resolve_conflict(keep_local: bool) -> void:
	if pending_remote.is_empty():
		return
	var remote := pending_remote
	pending_remote = {}
	_busy = true
	_set_status(STATUS_SYNCING)
	var ok := true
	if keep_local:
		ok = await _push_local(int(remote.get("version", 0)))
	else:
		_apply_remote(remote.get("save", {}) as Dictionary, int(remote.get("version", 0)))
		_set_status(STATUS_SYNCED)
	_busy = false
	if not ok and status != STATUS_CONFLICT:
		_set_status(STATUS_OFFLINE)
		_retry_timer.start(float(_cfg.get_value("sync", "retry_delay", 20.0)))


func has_conflict() -> bool:
	return status == STATUS_CONFLICT and not pending_remote.is_empty()


## Oublie le compte local (debug / tests) : un nouveau compte invité sera créé au prochain lancement.
func forget_session() -> void:
	_access_token = ""
	_refresh_token = ""
	_expires_at = 0
	user_id = ""
	DirAccess.remove_absolute(SESSION_PATH)


# --- Réconciliation -------------------------------------------------------------------------

func _reconcile() -> bool:
	var res := await _rpc("pull_state", {})
	if not bool(res.get("ok", false)):
		return false
	var body: Variant = res.get("body")
	var state: Dictionary = body if body is Dictionary else {}
	gems_granted = int(state.get("gems_granted", 0))
	entitlements.clear()
	for e: Variant in (state.get("entitlements", []) as Array):
		entitlements.append(str(e))
	var remote: Variant = state.get("save")
	var remote_exists := remote is Dictionary
	var remote_version := int((remote as Dictionary).get("version", 0)) if remote_exists else 0
	var data := _save_data()
	var action := decide(local_version(), is_dirty(), has_content(data), remote_exists, remote_version)
	match action:
		Action.PUSH:
			return await _push_local(remote_version if remote_exists else 0)
		Action.PULL:
			_apply_remote((remote as Dictionary).get("save", {}) as Dictionary, remote_version)
			_set_status(STATUS_SYNCED)
			return true
		Action.CONFLICT:
			var r: Dictionary = remote
			pending_remote = {"save": r.get("save", {}), "version": remote_version,
				"updated_at": str(r.get("updated_at", "")), "device": str(r.get("device", ""))}
			_set_status(STATUS_CONFLICT)
			conflict_detected.emit(describe_save(payload_of(data)), describe_save(
				pending_remote["save"] as Dictionary, pending_remote["updated_at"], pending_remote["device"]))
			return true
	_set_status(STATUS_SYNCED)
	return true


func _push_local(base_version: int) -> bool:
	var data := _save_data()
	var payload := payload_of(data)
	var json := JSON.stringify(payload)
	if json.length() > int(_cfg.get_value("sync", "max_bytes", 900000)):
		last_error = "Sauvegarde trop volumineuse"
		push_warning("CloudSync: %s (%d octets)" % [last_error, json.length()])
		return false
	var res := await _rpc("push_save", {"p_save": payload, "p_base_version": base_version,
		"p_device": _device_name(), "p_client_ver": _client_version()})
	if not bool(res.get("ok", false)):
		return false
	var body: Variant = res.get("body")
	var r: Dictionary = body if body is Dictionary else {}
	if bool(r.get("ok", false)):
		_write_meta(int(r.get("version", base_version + 1)), false)
		_set_status(STATUS_SYNCED)
		return true
	if str(r.get("reason", "")) == "conflict":
		pending_remote = {"save": r.get("save", {}), "version": int(r.get("version", 0)),
			"updated_at": str(r.get("updated_at", "")), "device": str(r.get("device", ""))}
		_set_status(STATUS_CONFLICT)
		conflict_detected.emit(describe_save(payload), describe_save(
			pending_remote["save"] as Dictionary, pending_remote["updated_at"], pending_remote["device"]))
		return true
	last_error = str(r.get("reason", "erreur serveur"))
	push_warning("CloudSync: push refusé (%s)" % last_error)
	return false


func _apply_remote(save: Dictionary, version: int) -> void:
	var sm: Node = get_node_or_null(^"/root/SaveManager")
	if sm == null:
		return
	var d := save.duplicate(true)
	d[META_KEY] = {"version": version, "dirty": false}
	_applying = true
	sm.call("replace_data", d)
	_applying = false
	remote_applied.emit()
	# Dans les menus, la scène se reconstruit pour afficher la sauvegarde restaurée.
	var tree := get_tree()
	var cur: Node = tree.current_scene if tree != null else null
	if cur != null and cur.scene_file_path.begins_with("res://scenes/ui/menus/"):
		tree.reload_current_scene()


# --- Compte (Supabase Auth) ------------------------------------------------------------------

func _ensure_session() -> bool:
	if _access_token.is_empty():
		_load_session()
	var now := int(Time.get_unix_time_from_system())
	var margin := int(_cfg.get_value("sync", "token_margin", 120.0))
	if not _refresh_token.is_empty() and (_access_token.is_empty() or _expires_at - margin <= now):
		var ok := await _refresh_session()
		if ok:
			return true
		# Jeton révoqué ou compte supprimé : on repart sur un compte invité neuf.
		if not str(last_error).begins_with("réseau"):
			forget_session()
	if not _access_token.is_empty() and _expires_at - margin > now:
		return true
	return await _sign_in_anonymous()


func _sign_in_anonymous() -> bool:
	var res := await _request("/auth/v1/signup", HTTPClient.METHOD_POST,
		{"data": {"device": _device_name()}}, false)
	if not bool(res.get("ok", false)):
		if int(res.get("code", 0)) == 422 or int(res.get("code", 0)) == 400:
			push_warning("CloudSync: connexion anonyme refusée : activer « Allow anonymous sign-ins » dans Supabase (Authentication → Sign In / Providers).")
		return false
	return _store_session(res.get("body"))


func _refresh_session() -> bool:
	var res := await _request("/auth/v1/token?grant_type=refresh_token", HTTPClient.METHOD_POST,
		{"refresh_token": _refresh_token}, false)
	if not bool(res.get("ok", false)):
		return false
	return _store_session(res.get("body"))


func _store_session(body: Variant) -> bool:
	if not (body is Dictionary) or not (body as Dictionary).has("access_token"):
		last_error = "réponse d'authentification invalide"
		return false
	var b: Dictionary = body
	_access_token = str(b.get("access_token", ""))
	_refresh_token = str(b.get("refresh_token", _refresh_token))
	_expires_at = int(Time.get_unix_time_from_system()) + int(b.get("expires_in", 3600))
	var u: Variant = b.get("user", {})
	if u is Dictionary:
		user_id = str((u as Dictionary).get("id", user_id))
		is_anonymous = bool((u as Dictionary).get("is_anonymous", true))
	_save_session()
	return true


func _session_key() -> String:
	return "raidersgo-" + OS.get_unique_id()


func _save_session() -> void:
	var f := FileAccess.open_encrypted_with_pass(SESSION_PATH, FileAccess.WRITE, _session_key())
	if f == null:
		f = FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"access_token": _access_token, "refresh_token": _refresh_token,
		"expires_at": _expires_at, "user_id": user_id, "is_anonymous": is_anonymous}))


func _load_session() -> void:
	if not FileAccess.file_exists(SESSION_PATH):
		return
	var f := FileAccess.open_encrypted_with_pass(SESSION_PATH, FileAccess.READ, _session_key())
	if f == null:
		f = FileAccess.open(SESSION_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return
	var s: Dictionary = parsed
	_access_token = str(s.get("access_token", ""))
	_refresh_token = str(s.get("refresh_token", ""))
	_expires_at = int(s.get("expires_at", 0))
	user_id = str(s.get("user_id", ""))
	is_anonymous = bool(s.get("is_anonymous", true))


# --- HTTP --------------------------------------------------------------------------------------

## Appel d'une fonction Postgres exposée par PostgREST (/rest/v1/rpc/<name>), authentifié.
func _rpc(fn: String, args: Dictionary) -> Dictionary:
	var res := await _request("/rest/v1/rpc/" + fn, HTTPClient.METHOD_POST, args, true)
	if not bool(res.get("ok", false)) and int(res.get("code", 0)) == 401 and not _refresh_token.is_empty():
		if await _refresh_session():
			res = await _request("/rest/v1/rpc/" + fn, HTTPClient.METHOD_POST, args, true)
	return res


## Retour : {"ok": bool, "code": int, "body": Variant (JSON décodé ou texte)}.
func _request(path: String, method: HTTPClient.Method, body: Variant, auth: bool) -> Dictionary:
	var hr := HTTPRequest.new()
	hr.timeout = float(_cfg.get_value("sync", "timeout", 15.0))
	hr.accept_gzip = true
	add_child(hr)
	var headers := PackedStringArray(["Content-Type: application/json", "apikey: " + _key])
	if auth and not _access_token.is_empty():
		headers.append("Authorization: Bearer " + _access_token)
	var err := hr.request(_url + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		hr.queue_free()
		last_error = "réseau : impossible de lancer la requête (%d)" % err
		return {"ok": false, "code": 0, "body": null}
	var r: Array = await hr.request_completed
	hr.queue_free()
	var result := int(r[0])
	var code := int(r[1])
	var raw: PackedByteArray = r[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		last_error = "réseau : erreur %d" % result
		return {"ok": false, "code": code, "body": null}
	var text := raw.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	var ok := code >= 200 and code < 300
	if not ok:
		last_error = "HTTP %d" % code
		if parsed is Dictionary:
			last_error += " : " + str((parsed as Dictionary).get("msg", (parsed as Dictionary).get("message",
				(parsed as Dictionary).get("error_description", (parsed as Dictionary).get("error", "")))))
		push_warning("CloudSync: %s %s → %s" % [path, "POST", last_error])
	return {"ok": ok, "code": code, "body": parsed if parsed != null else text}


# --- Divers -------------------------------------------------------------------------------------

func _set_status(s: StringName) -> void:
	if status == s:
		return
	status = s
	status_changed.emit(s)


static func _device_name() -> String:
	var model := OS.get_model_name()
	return "%s (%s)" % [model if not model.is_empty() and model != "GenericDevice" else OS.get_name(), OS.get_name()]


static func _client_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.1"))
