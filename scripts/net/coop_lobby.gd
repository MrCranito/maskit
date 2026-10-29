class_name CoopLobby
extends Control
## Salon coop en ligne (res://scenes/ui/menus/coop_lobby.tscn) :
##  - accueil : pseudo, « Créer un salon », « Rejoindre » (saisie du code à 6 caractères) ;
##  - salon : code (copier / partager), cartes des deux joueurs (pseudo, skin, arsenal, prêt),
##    carte choisie par l'hôte (écran de cartes CoopMapSelect), arsenal de chacun (écran
##    d'arsenal CoopLoadout), « Lancer le raid » (hôte, quand les deux sont prêts).
## Le lancement est synchronisé : l'hôte envoie {k:"start", seed, carte} ; chacun appelle
## GameState.begin_raid() et charge le raid ; Raid._ready attache CoopRaid (NetHooks).
## Messages d'erreur : serveur injoignable, code invalide, salon introuvable / plein, version.

const CFG_PATH := "user://coop.cfg"
const OK_COLOR := Color(0.45, 0.9, 0.5)

var session: NetSession = null
var name_edit: LineEdit = null
var code_edit: LineEdit = null
var create_button: Button = null
var join_button: Button = null
var back_button: Button = null
var copy_button: Button = null
var share_button: Button = null
var map_button: Button = null
var arsenal_button: Button = null
var launch_button: Button = null
var leave_button: Button = null
var status_label: Label = null
var code_label: Label = null
var map_label: Label = null
var hint_label: Label = null
var server_pill: Label = null

## Carte choisie (hôte) ou annoncée par l'hôte (invité).
var map_card: MapCard = null
var map_seed: int = 0
var local_ready: bool = false
var launching: bool = false

var _home: Control = null
var _room: Control = null
var _cards: HBoxContainer = null
var _overlay: Control = null
var _status_tween: Tween = null
var _ping_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	var bg := MenuBackground.new()
	bg.dim = Balance.get_float("menu", "screen_dim", 0.45) + 0.1
	add_child(bg)
	session = NetSession.instance()
	_build()
	session.status_changed.connect(_on_status_changed)
	session.error_received.connect(_on_error)
	session.room_ready.connect(_on_room_ready)
	session.peer_joined.connect(func(_n: String) -> void: _on_peer_joined())
	session.peer_left.connect(_on_peer_left)
	session.peer_lost.connect(func(_g: float) -> void: _refresh_room())
	session.peer_back.connect(func() -> void: _refresh_room())
	session.room_closed.connect(_on_room_closed)
	session.lobby_message.connect(_on_lobby_message)
	_show_room(session.in_room())
	_on_status_changed(session.status)
	MenuKit.fade_in(self)


# --- Construction -------------------------------------------------------------------

func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	safe.add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	root.add_child(top)
	back_button = MenuKit.back_button()
	back_button.name = "BackButton"
	back_button.pressed.connect(go_back)
	top.add_child(back_button)
	var title := MenuKit.title("Coop en ligne", 46)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	server_pill = MenuKit.label("", 18, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	server_pill.custom_minimum_size = Vector2(150, 0)
	server_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	server_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(server_pill)

	var body := Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_home = _build_home()
	body.add_child(_home)
	_room = _build_room()
	body.add_child(_room)

	status_label = MenuKit.label("", 20, MenuKit.BAD, MenuKit.nunito(800), 3)
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(0, 30)
	root.add_child(status_label)


func _build_home() -> Control:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	cc.add_child(v)

	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 14)
	v.add_child(name_row)
	var nl := MenuKit.label("Pseudo", 24, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(nl)
	name_edit = _line_edit(load_name(), 26, Vector2(320, 60))
	name_edit.name = "NameEdit"
	name_edit.max_length = 16
	name_edit.text_changed.connect(func(_t: String) -> void: save_name(name_edit.text))
	name_row.add_child(name_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)

	var p1 := MenuKit.panel(MenuKit.NIGHT_PANEL, 20, 24)
	p1.custom_minimum_size = Vector2(420, 260)
	row.add_child(p1)
	var v1 := VBoxContainer.new()
	v1.add_theme_constant_override("separation", 14)
	v1.alignment = BoxContainer.ALIGNMENT_CENTER
	p1.add_child(v1)
	v1.add_child(_centered(MenuKit.title("Héberger", 32)))
	var d1 := MenuKit.label("Crée un salon et donne le code\nà ton coéquipier.", 19, MenuKit.TEXT_DIM)
	d1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v1.add_child(d1)
	create_button = MenuKit.button("Créer un salon", MenuKit.Style.PRIMARY, 28, Vector2(340, 80))
	create_button.name = "CreateButton"
	create_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	create_button.pressed.connect(create_room)
	v1.add_child(create_button)

	var p2 := MenuKit.panel(MenuKit.NIGHT_PANEL, 20, 24)
	p2.custom_minimum_size = Vector2(420, 260)
	row.add_child(p2)
	var v2 := VBoxContainer.new()
	v2.add_theme_constant_override("separation", 14)
	v2.alignment = BoxContainer.ALIGNMENT_CENTER
	p2.add_child(v2)
	v2.add_child(_centered(MenuKit.title("Rejoindre", 32)))
	code_edit = _line_edit("", 40, Vector2(300, 74))
	code_edit.name = "CodeEdit"
	code_edit.placeholder_text = "CODE"
	code_edit.max_length = 7
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	code_edit.text_changed.connect(_on_code_changed)
	code_edit.text_submitted.connect(func(_t: String) -> void: join_room())
	v2.add_child(code_edit)
	join_button = MenuKit.button("Rejoindre", MenuKit.Style.SECONDARY, 28, Vector2(340, 80))
	join_button.name = "JoinButton"
	join_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join_button.pressed.connect(join_room)
	v2.add_child(join_button)

	hint_label = MenuKit.label("Coop à deux, par Internet. Chacun garde le butin qu'il ramasse.", 17, MenuKit.TEXT_DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint_label)
	return cc


func _build_room() -> Control:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 18)

	# Colonne gauche : code et actions.
	var left := MenuKit.panel(MenuKit.NIGHT_PANEL, 20, 20)
	left.custom_minimum_size = Vector2(330, 0)
	h.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)
	lv.add_child(_centered(MenuKit.label("CODE DU SALON", 18, MenuKit.TEXT_DIM, MenuKit.nunito(900))))
	code_label = MenuKit.title("", 58, MenuKit.GOLD)
	code_label.name = "CodeLabel"
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(code_label)
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 10)
	lv.add_child(crow)
	copy_button = MenuKit.button("Copier", MenuKit.Style.SECONDARY, 22, Vector2(140, 60))
	copy_button.name = "CopyButton"
	copy_button.pressed.connect(copy_code)
	crow.add_child(copy_button)
	share_button = MenuKit.button("Partager", MenuKit.Style.SECONDARY, 22, Vector2(150, 60))
	share_button.name = "ShareButton"
	share_button.pressed.connect(share_code)
	crow.add_child(share_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(spacer)
	map_label = MenuKit.label("", 19, MenuKit.TEXT, MenuKit.nunito(800))
	map_label.name = "MapLabel"
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(map_label)
	map_button = MenuKit.button("Choisir la carte", MenuKit.Style.SECONDARY, 22, Vector2(290, 62))
	map_button.name = "MapButton"
	map_button.pressed.connect(open_map_select)
	lv.add_child(map_button)
	leave_button = MenuKit.button("Quitter le salon", MenuKit.Style.GHOST, 20, Vector2(290, 58))
	leave_button.name = "LeaveButton"
	leave_button.pressed.connect(leave_room)
	lv.add_child(leave_button)

	# Droite : joueurs + actions.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 14)
	h.add_child(right)
	_cards = HBoxContainer.new()
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 16)
	right.add_child(_cards)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	right.add_child(actions)
	arsenal_button = MenuKit.button("Mon arsenal", MenuKit.Style.SECONDARY, 26, Vector2(280, 78))
	arsenal_button.name = "ArsenalButton"
	arsenal_button.pressed.connect(open_loadout)
	actions.add_child(arsenal_button)
	launch_button = MenuKit.button("Lancer le raid", MenuKit.Style.PRIMARY, 30, Vector2(340, 78))
	launch_button.name = "LaunchButton"
	launch_button.pressed.connect(launch)
	actions.add_child(launch_button)
	return h


func _line_edit(text: String, size: int, min_size: Vector2) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = min_size
	e.add_theme_font_override("font", MenuKit.nunito(900))
	e.add_theme_font_size_override("font_size", size)
	e.add_theme_color_override("font_color", MenuKit.TEXT)
	e.add_theme_color_override("font_placeholder_color", Color(MenuKit.TEXT_DIM, 0.5))
	var st := MenuKit.panel_style(Color(0.04, 0.06, 0.12, 0.95), MenuKit.BORDER, 14, 1, 10)
	e.add_theme_stylebox_override("normal", st)
	var fs := st.duplicate() as StyleBoxFlat
	fs.border_color = MenuKit.GOLD
	fs.set_border_width_all(2)
	e.add_theme_stylebox_override("focus", fs)
	return e


func _centered(c: Control) -> Control:
	if c is Label:
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return c


## Carte d'un joueur : rôle, aperçu du skin, pseudo, skin, arsenal, prêt.
func _player_card(info: Dictionary, role_text: String, present: bool, connected: bool) -> Control:
	var p := MenuKit.panel(MenuKit.NIGHT_PANEL, 20, 16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var pill := MenuKit.pill(role_text, MenuKit.RED if role_text == "HÔTE" else Color(0.2, 0.4, 0.7), 15)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pill)
	if not present:
		var wait := MenuKit.label("En attente d'un joueur…\nPartage le code !", 22, MenuKit.TEXT_DIM, MenuKit.nunito(800))
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wait.size_flags_vertical = Control.SIZE_EXPAND_FILL
		wait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(wait)
		return p
	var skin := SkinData.get_skin(StringName(String(info.get("skin", ""))))
	var prev := HeroPreview.new(false)
	prev.custom_minimum_size = Vector2(150, 170)
	prev.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prev.set_skin(skin)
	v.add_child(prev)
	var nm := MenuKit.title(String(info.get("name", "Raider")), 28)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var sk_name := skin.display_name if skin != null else "Soldat standard"
	var sk := MenuKit.label(sk_name, 17, MenuKit.rarity_color(skin.rarity if skin != null else 0), MenuKit.nunito(800))
	sk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sk)
	var names := PackedStringArray()
	for id: Variant in info.get("loadout", []):
		var w := WeaponCatalog.get_weapon(StringName(str(id)))
		names.append(w.display_name if w != null else str(id))
	var lo := MenuKit.label(" · ".join(names) if not names.is_empty() else "Arsenal non choisi", 16, MenuKit.TEXT_DIM)
	lo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(lo)
	var ready := bool(info.get("ready", false))
	var rt := "✓ Prêt" if ready else "Choisit son arsenal…"
	var rc := OK_COLOR if ready else MenuKit.TEXT_DIM
	if not connected:
		rt = "Connexion perdue…"
		rc = MenuKit.BAD
	var rl := MenuKit.label(rt, 22, rc, MenuKit.nunito(900))
	rl.name = "Ready"
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(rl)
	return p


# --- Pseudo ---------------------------------------------------------------------------

static func load_name() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) == OK:
		var n := String(cfg.get_value("coop", "name", ""))
		if n != "":
			return n
	return "Raider%d" % (randi() % 900 + 100)


static func save_name(n: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG_PATH)
	cfg.set_value("coop", "name", n.strip_edges())
	cfg.save(CFG_PATH)


## Saisie du code : majuscules, caractères invalides retirés, curseur en fin.
func _on_code_changed(t: String) -> void:
	var n := LobbyCode.normalize(t)
	if n != t:
		code_edit.text = n
		code_edit.caret_column = n.length()


func player_name() -> String:
	var n := name_edit.text.strip_edges() if name_edit != null else ""
	return n if n != "" else "Raider"


# --- Actions --------------------------------------------------------------------------

func create_room() -> void:
	if session.in_room():
		return
	MenuKit.sfx(&"confirm")
	save_name(player_name())
	_set_status("Connexion au serveur…", MenuKit.TEXT_DIM)
	session.create_room(player_name())


func join_room() -> void:
	if session.in_room():
		return
	var code := LobbyCode.normalize(code_edit.text)
	if not LobbyCode.is_valid(code):
		MenuKit.sfx(&"error")
		_set_status(NetSession.describe_error("bad_code"), MenuKit.BAD)
		return
	MenuKit.sfx(&"confirm")
	save_name(player_name())
	_set_status("Connexion au salon %s…" % code, MenuKit.TEXT_DIM)
	session.join_room(code, player_name())


func leave_room() -> void:
	MenuKit.sfx(&"back")
	session.leave()
	map_card = null
	local_ready = false
	_show_room(false)
	_set_status("", MenuKit.TEXT_DIM)


func go_back() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	if session.in_room():
		session.leave()
	MenuKit.sfx(&"back")
	MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE)


func copy_code() -> void:
	DisplayServer.clipboard_set(session.room_code)
	MenuKit.sfx(&"click")
	_set_status("Code copié : %s" % session.room_code, OK_COLOR)


## Partage : texte d'invitation copié ; sur mobile, ouvre aussi l'app Messages pré-remplie.
func share_code() -> void:
	var msg := "Rejoins-moi sur RaidersGo en coop ! Code du salon : %s" % session.room_code
	DisplayServer.clipboard_set(msg)
	MenuKit.sfx(&"click")
	if OS.has_feature("mobile"):
		OS.shell_open("sms:&body=" + msg.uri_encode())
	_set_status("Invitation copiée, colle-la à ton coéquipier.", OK_COLOR)


func open_map_select() -> void:
	if not session.is_host() or _overlay != null:
		return
	var ms := CoopMapSelect.new()
	ms.chosen.connect(_on_map_chosen)
	ms.closed.connect(func() -> void: _overlay = null)
	_overlay = ms
	add_child(ms)


func open_loadout() -> void:
	if _overlay != null:
		return
	var lo := CoopLoadout.new()
	lo.validated.connect(_on_loadout_validated)
	lo.closed.connect(func() -> void: _overlay = null)
	_overlay = lo
	add_child(lo)


func _on_map_chosen(card: MapCard) -> void:
	_overlay = null
	map_card = card
	GameState.set_current_map(card, true)
	map_seed = GameState.run_seed
	_send_map()
	_refresh_room()


func _on_loadout_validated() -> void:
	_overlay = null
	local_ready = true
	_send_info()
	_refresh_room()


## Hôte : lance le raid pour les deux.
func launch() -> void:
	if not can_launch():
		MenuKit.sfx(&"error")
		return
	session.send_lobby({"k": "start", "seed": map_seed, "path": map_card.resource_path})
	_start_raid(map_card.resource_path, map_seed)


func can_launch() -> bool:
	return session.is_host() and session.peer_present and session.peer_connected and map_card != null \
		and local_ready and bool(session.peer_info.get("ready", false)) and NetProtocol.compatible(session.peer_info) \
		and not launching


func _start_raid(path: String, seed_value: int) -> void:
	if launching:
		return
	launching = true
	var card := load(path) as MapCard if path != "" and ResourceLoader.exists(path) else null
	if card != null:
		GameState.set_current_map(card, false)
	GameState.run_seed = seed_value
	session.raid_info = {"seed": seed_value, "path": path}
	session.raid_pending = true
	GameState.begin_raid()
	MenuKit.sfx(&"confirm_big")
	MenuKit.vibrate(40)
	MenuKit.go_to(self, MenuKit.RAID_SCENE, Balance.get_float("menu", "fade_time", 0.3) * 1.5)


# --- Messages de salon ----------------------------------------------------------------

func _local_info() -> Dictionary:
	var ids: Array = []
	for w: WeaponData in Profile.get_loadout_weapons():
		ids.append(String(w.id))
	var g := Profile.get_loadout_gadget()
	return {
		"k": "info", "gv": NetProtocol.GAME_VERSION, "name": player_name(),
		"skin": String(Profile.skin_character), "ready": local_ready, "loadout": ids,
		"gadget": String(g.id) if g != null else "",
	}


func _send_info() -> void:
	session.local_info = _local_info()
	session.send_lobby(session.local_info)


func _send_map() -> void:
	if not session.is_host() or map_card == null:
		return
	session.send_lobby({"k": "map", "path": map_card.resource_path, "seed": map_seed,
		"name": map_card.display_name, "difficulty": map_card.difficulty})


func _on_lobby_message(d: Dictionary) -> void:
	match String(d.get("k", "")):
		"info":
			session.peer_info = d
			if not NetProtocol.compatible(d):
				_set_status(NetSession.describe_error("game_version"), MenuKit.BAD)
			_refresh_room()
		"map":
			if not session.is_host():
				var path := String(d.get("path", ""))
				map_card = load(path) as MapCard if path != "" and ResourceLoader.exists(path) else null
				map_seed = int(d.get("seed", 0))
				_refresh_room()
		"start":
			if not session.is_host():
				if not local_ready:
					Profile.set_loadout(Profile.loadout)
				_start_raid(String(d.get("path", "")), int(d.get("seed", 0)))


# --- Événements réseau ----------------------------------------------------------------

func _on_status_changed(st: int) -> void:
	if server_pill == null:
		return
	server_pill.text = NetSession.status_text(st)
	var col := OK_COLOR if st == NetSession.Status.ONLINE or st == NetSession.Status.IN_ROOM else MenuKit.TEXT_DIM
	server_pill.add_theme_color_override("font_color", col)
	var busy := st == NetSession.Status.CONNECTING
	create_button.disabled = busy
	join_button.disabled = busy


func _on_error(code: String, message: String) -> void:
	MenuKit.sfx(&"error")
	_set_status(message if message != "" else code, MenuKit.BAD)


func _on_room_ready(_code: String, _role: StringName) -> void:
	local_ready = false
	if not session.is_host():
		map_card = null
	_set_status("", MenuKit.TEXT_DIM)
	_show_room(true)
	_send_info()


func _on_peer_joined() -> void:
	MenuKit.sfx(&"confirm")
	_send_info()
	_send_map()
	_set_status("%s a rejoint le salon !" % session.peer_name, OK_COLOR)
	_refresh_room()


func _on_peer_left(_reason: String) -> void:
	_set_status("Ton coéquipier a quitté le salon.", MenuKit.BAD)
	_refresh_room()


func _on_room_closed(reason: String) -> void:
	if launching:
		return
	map_card = null
	local_ready = false
	_show_room(false)
	var msg := "L'hôte a fermé le salon." if reason == "host_left" else "Le salon a été fermé (%s)." % _reason_text(reason)
	_set_status(msg, MenuKit.BAD)


static func _reason_text(reason: String) -> String:
	match reason:
		"host_timeout":
			return "connexion de l'hôte perdue"
		"expired":
			return "salon expiré"
		"unreachable":
			return "serveur injoignable"
	return reason


# --- Affichage ------------------------------------------------------------------------

func _show_room(on: bool) -> void:
	_home.visible = not on
	_room.visible = on
	if on:
		_refresh_room()
	elif create_button != null:
		create_button.grab_focus.call_deferred()


func _refresh_room() -> void:
	if _room == null or not session.in_room():
		return
	code_label.text = LobbyCode.pretty(session.room_code)
	for c: Node in _cards.get_children():
		c.queue_free()
	var me := _local_info()
	var host_info: Dictionary = me if session.is_host() else session.peer_info
	var guest_info: Dictionary = session.peer_info if session.is_host() else me
	if not session.is_host() and host_info.is_empty():
		host_info = {"name": session.peer_name}
	_cards.add_child(_player_card(host_info, "HÔTE", true, session.is_host() or session.peer_connected))
	var guest_present := not session.is_host() or session.peer_present
	_cards.add_child(_player_card(guest_info, "INVITÉ", guest_present, not session.is_host() or session.peer_connected))
	if map_card != null:
		map_label.text = "Carte : %s\nDifficulté : %s" % [map_card.display_name, GameState.difficulty_name(map_card.difficulty)]
	else:
		map_label.text = "Carte : à choisir par l'hôte" if session.is_host() else "L'hôte choisit la carte…"
	map_button.visible = session.is_host()
	arsenal_button.text = "Mon arsenal ✓" if local_ready else "Mon arsenal"
	launch_button.visible = session.is_host()
	launch_button.disabled = not can_launch()
	if not session.is_host() and status_label.text == "":
		_set_status("En attente du lancement par l'hôte…" if local_ready else "Valide ton arsenal pour être prêt.", MenuKit.TEXT_DIM)


func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)


func _process(delta: float) -> void:
	# Ping affiché (2×/s), seulement quand on est en ligne.
	_ping_left -= delta
	if _ping_left > 0.0 or server_pill == null:
		return
	_ping_left = 0.5
	if session.is_online() and session.rtt_ms >= 0.0:
		server_pill.text = "%s · %d ms" % [NetSession.status_text(session.status), roundi(session.rtt_ms)]
	if _room.visible and launch_button != null:
		launch_button.disabled = not can_launch()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _overlay == null:
		get_viewport().set_input_as_handled()
		go_back()


## La session survit à l'écran : toutes nos connexions (méthodes et lambdas) sont retirées.
func _exit_tree() -> void:
	if session == null or not is_instance_valid(session):
		return
	for sig: Dictionary in session.get_signal_list():
		var sname := StringName(sig["name"])
		for c: Dictionary in session.get_signal_connection_list(sname):
			var cb: Callable = c["callable"]
			if cb.get_object() == self:
				session.disconnect(sname, cb)
