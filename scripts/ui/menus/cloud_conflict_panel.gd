class_name CloudConflictPanel
extends ModalPanel
## Conflit de sauvegarde cloud : la même partie a avancé sur deux appareils. Deux cartes côte à
## côte (ce téléphone / le cloud : niveau, gemmes, or, armes, raids, date) et un bouton sous
## chacune. Le choix est définitif ; le voile ne ferme pas la fenêtre (il faut trancher).

var local_info: Dictionary = {}
var remote_info: Dictionary = {}
var keep_local_button: Button = null
var keep_remote_button: Button = null
var _chosen: bool = false


func _init(p_local: Dictionary = {}, p_remote: Dictionary = {}) -> void:
	super._init("Deux sauvegardes", Vector2(760, 0))
	local_info = p_local
	remote_info = p_remote


func _build_body() -> void:
	close_button.visible = false
	var intro := MenuKit.label("Cette partie a avancé sur un autre appareil. Laquelle garder ? L'autre sera remplacée.",
		19, MenuKit.TEXT_DIM, MenuKit.nunito(650))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.custom_minimum_size = Vector2(680, 0)
	body.add_child(intro)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	body.add_child(row)
	keep_local_button = MenuKit.button("Garder ce téléphone", MenuKit.Style.SECONDARY, 20, Vector2(300, 62))
	keep_remote_button = MenuKit.button("Garder le cloud", MenuKit.Style.PRIMARY, 20, Vector2(300, 62))
	row.add_child(_card("Ce téléphone", local_info, keep_local_button))
	row.add_child(_card("Le cloud", remote_info, keep_remote_button))
	keep_local_button.pressed.connect(func() -> void: _choose(true))
	keep_remote_button.pressed.connect(func() -> void: _choose(false))


func _card(title: String, info: Dictionary, button: Button) -> Control:
	var p := MenuKit.panel(Color(MenuKit.NIGHT_DEEP, 0.75), 16, 18)
	p.custom_minimum_size = Vector2(320, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	p.add_child(col)
	var t := MenuKit.title(title, 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	col.add_child(_line("Niveau de raider", str(info.get("raider_level", 1))))
	col.add_child(_line("Gemmes", str(info.get("gems", 0))))
	col.add_child(_line("Or", str(info.get("gold", 0))))
	col.add_child(_line("Armes en réserve", str(info.get("weapons", 0))))
	col.add_child(_line("Raids", str(info.get("raids", 0))))
	var when := format_date(str(info.get("updated_at", "")))
	var device := str(info.get("device", ""))
	var foot := MenuKit.label(when + ((" · " + device) if not device.is_empty() else ""), 15,
		MenuKit.TEXT_DIM, MenuKit.nunito(500))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(foot)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(button)
	return p


static func _line(k: String, v: String) -> Control:
	var h := HBoxContainer.new()
	var l := MenuKit.label(k, 18, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(MenuKit.label(v, 18, MenuKit.TEXT, MenuKit.nunito(800)))
	return h


## « 30/10/2026 à 11:05 » à partir d'une date ISO du serveur (UTC → heure locale) ; vide = « Maintenant ».
static func format_date(iso: String) -> String:
	if iso.is_empty():
		return "Maintenant"
	var unix := Time.get_unix_time_from_datetime_string(iso.substr(0, 19))
	if unix <= 0:
		return iso
	var d := Time.get_datetime_dict_from_unix_time(unix + Time.get_time_zone_from_system().get("bias", 0) * 60)
	return "%02d/%02d/%d à %02d:%02d" % [d["day"], d["month"], d["year"], d["hour"], d["minute"]]


func _choose(keep_local: bool) -> void:
	MenuKit.sfx(&"confirm")
	keep_local_button.disabled = true
	keep_remote_button.disabled = true
	var cs: Node = get_node_or_null(^"/root/CloudSync")
	if cs != null:
		cs.call("resolve_conflict", keep_local)
	_chosen = true
	close()


## Ni le voile ni Échap ne ferment la fenêtre tant que rien n'est choisi.
func close() -> void:
	if _chosen:
		super.close()


func _unhandled_input(event: InputEvent) -> void:
	# Pas de fermeture par Échap : le joueur doit choisir.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
