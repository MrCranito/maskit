class_name AccountLink
extends Node
## Obtention d'une identité Apple / Google pour lier (ou retrouver) le compte joueur.
## Deux chemins, même résultat : un jeton (`id_token` natif) ou un code d'autorisation PKCE.
##  - Mobile : plugins natifs, détectés par Engine.has_singleton :
##      Android « GodotGoogleSignIn » (Credential Manager, github.com/NiqueWrld/GodotGoogleSignIn) ;
##      iOS/macOS « Godot Apple Plugins » (ASAuthorizationController, migueldeicaza/GodotApplePlugins).
##  - PC / éditeur : navigateur système + redirection vers un petit serveur local
##    (http://127.0.0.1:<port>/cb, à autoriser dans Supabase → Authentication → URL Configuration),
##    avec PKCE (vérificateur aléatoire, défi SHA-256). Sert aussi de repli si un plugin manque.
## Signaux : `token_ready(provider, id_token, access_token, nonce)` (natif),
## `code_ready(code)` (PKCE), `failed(message)`.

signal token_ready(provider: StringName, id_token: String, access_token: String, nonce: String)
signal code_ready(code: String)
signal failed(message: String)

const CALLBACK_PATH := "/cb"

var port: int = 48791
var google_web_client_id: String = ""
var code_verifier: String = ""
var _server: TCPServer = null
var _deadline_ms: int = 0
var _google: Object = null
var _apple: Object = null
var _pending: StringName = &""


func _ready() -> void:
	set_process(false)


func cancel() -> void:
	_stop_server()
	_pending = &""


func is_busy() -> bool:
	return _pending != &"" or _server != null


# --- Natif ------------------------------------------------------------------------------------

## Un plugin natif est-il disponible pour ce fournisseur sur cet appareil ?
static func native_available(provider: StringName) -> bool:
	match provider:
		&"google":
			return Engine.has_singleton("GodotGoogleSignIn")
		&"apple":
			return ClassDB.class_exists(&"ASAuthorizationController") or Engine.has_singleton("ASAuthorizationController")
	return false


## Le fournisseur a-t-il un sens sur cette plateforme (bouton affiché) ?
static func provider_offered(provider: StringName) -> bool:
	if native_available(provider):
		return true
	# Sans plugin : navigateur + serveur local, uniquement sur PC / éditeur.
	return OS.get_name() in ["Windows", "Linux", "macOS"]


## Lance la connexion native (jeton) si un plugin existe, sinon le flux PKCE par navigateur.
func start(provider: StringName, challenge_url: String) -> void:
	if is_busy():
		failed.emit("Une connexion est déjà en cours")
		return
	if native_available(provider):
		_pending = provider
		if provider == &"google":
			_start_google()
		else:
			_start_apple()
		return
	start_browser(challenge_url)


func _start_google() -> void:
	if _google == null:
		_google = Engine.get_singleton("GodotGoogleSignIn")
		_google.connect("sign_in_success", _on_google_success)
		_google.connect("sign_in_failed", _on_native_failed)
	if not bool(_google.call("isInitialized")):
		if google_web_client_id.is_empty():
			_pending = &""
			failed.emit("Identifiant client Google manquant (data/cloud.cfg [auth] google_web_client_id)")
			return
		_google.call("initialize", google_web_client_id)
	_google.call("signInWithAccountChooser")


func _on_google_success(id_token: String, _email: String, _display_name: String) -> void:
	_pending = &""
	token_ready.emit(&"google", id_token, "", "")


func _start_apple() -> void:
	if _apple == null:
		_apple = ClassDB.instantiate(&"ASAuthorizationController") if ClassDB.class_exists(&"ASAuthorizationController") \
			else Engine.get_singleton("ASAuthorizationController")
		_apple.connect("authorization_completed", _on_apple_completed)
		_apple.connect("authorization_failed", _on_native_failed)
	_apple.call("signin_with_scopes", ["email"])


func _on_apple_completed(credential: Object) -> void:
	_pending = &""
	# Le jeton d'identité (JWT) est exposé selon la version du plugin sous l'un de ces noms.
	var raw: Variant = null
	for prop: StringName in [&"identity_token", &"identityToken", &"id_token"]:
		raw = credential.get(prop)
		if raw != null:
			break
	var token := ""
	if raw is PackedByteArray:
		token = (raw as PackedByteArray).get_string_from_utf8()
	elif raw is String:
		token = raw
	if token.is_empty():
		failed.emit("Le plugin Apple ne fournit pas le jeton d'identité")
		return
	token_ready.emit(&"apple", token, "", "")


func _on_native_failed(error: Variant) -> void:
	_pending = &""
	failed.emit(str(error))


# --- PKCE par navigateur (PC / éditeur) -------------------------------------------------------

func redirect_uri() -> String:
	return "http://127.0.0.1:%d%s" % [port, CALLBACK_PATH]


## Nouveau vérificateur PKCE (43 caractères base64url) ; renvoie le défi S256 correspondant.
func new_challenge() -> String:
	var rng := Crypto.new()
	code_verifier = base64url(rng.generate_random_bytes(32))
	return challenge_for(code_verifier)


static func challenge_for(verifier: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(verifier.to_utf8_buffer())
	return base64url(h.finish())


static func base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").rstrip("=")


## Ouvre `url` dans le navigateur et attend le retour sur http://127.0.0.1:<port>/cb?code=…
func start_browser(url: String, timeout_s: float = 180.0) -> void:
	_server = TCPServer.new()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		_server = null
		failed.emit("Port local %d indisponible (%d)" % [port, err])
		return
	_deadline_ms = Time.get_ticks_msec() + int(timeout_s * 1000.0)
	set_process(true)
	OS.shell_open(url)


func _process(_delta: float) -> void:
	if _server == null:
		set_process(false)
		return
	if Time.get_ticks_msec() > _deadline_ms:
		_stop_server()
		failed.emit("Connexion annulée (délai dépassé)")
		return
	if not _server.is_connection_available():
		return
	var peer := _server.take_connection()
	var request := ""
	var until := Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < until and not request.contains("\r\n"):
		if peer.get_available_bytes() > 0:
			request += peer.get_utf8_string(peer.get_available_bytes())
		else:
			OS.delay_msec(10)
	var q := parse_callback(request)
	var ok := q.has("code")
	var page := "<html><body style='font-family:sans-serif;background:#06070D;color:#fff;text-align:center;padding-top:20vh'><h1>%s</h1><p>%s</p></body></html>" % [
		"RaidersGo" , "Compte lié : tu peux revenir au jeu." if ok else "Échec : " + str(q.get("error_description", q.get("error", "réponse invalide")))]
	peer.put_data(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: %d\r\n\r\n%s" % [page.to_utf8_buffer().size(), page]).to_utf8_buffer())
	peer.disconnect_from_host()
	_stop_server()
	if ok:
		code_ready.emit(str(q["code"]))
	else:
		failed.emit(str(q.get("error_description", q.get("error", "réponse invalide"))))


## Paramètres de la première ligne d'une requête HTTP (« GET /cb?code=…&state=… HTTP/1.1 »).
static func parse_callback(request: String) -> Dictionary:
	var out := {}
	var line := request.get_slice("\r\n", 0)
	var parts := line.split(" ")
	if parts.size() < 2:
		return out
	var target := parts[1]
	if not target.begins_with(CALLBACK_PATH):
		return out
	var qi := target.find("?")
	if qi < 0:
		return out
	for kv: String in target.substr(qi + 1).split("&", false):
		var eq := kv.find("=")
		if eq > 0:
			out[kv.substr(0, eq).uri_decode()] = kv.substr(eq + 1).replace("+", " ").uri_decode()
	return out


func _stop_server() -> void:
	if _server != null:
		_server.stop()
		_server = null
	set_process(false)
