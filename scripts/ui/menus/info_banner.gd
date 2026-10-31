class_name InfoBanner
extends PanelContainer
## Petit bandeau d'information du lobby (haut droite) : événement en cours / à venir et
## rotation des cartes (MapRotation, si la rotation n'est pas restreinte), puis astuces.
## Les messages défilent en fondu (Timer, pas de _process).

const TIPS: Array[String] = [
	"Ce que tu emportes, tu peux le perdre : garde tes plus belles armes en réserve.",
	"Reste sur la zone d'extraction pendant la canalisation : sortir l'interrompt.",
	"Les clefs rares tombent des ennemis : elles ouvrent les salles de super-butin.",
	"Cache-toi dans un tonneau ou une armoire pour laisser passer une patrouille.",
	"Un tir fait du bruit : les ennemis proches viennent voir.",
	"Les skins sont purement cosmétiques : aucun bonus en raid.",
]

var icon: MenuGlyph = null
var title_label: Label = null
var text_label: Label = null
## Messages : [{icon, title, text}].
var messages: Array[Dictionary] = []
var index: int = 0
var _timer: Timer = null
var _box: Control = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(Balance.get_float("menu", "play_card_width", 420.0), 64)
	var s := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.78), Color(1, 1, 1, 0.18), 16, 1, 10)
	s.border_width_left = 4
	s.border_color = MenuKit.GOLD
	s.content_margin_left = 12
	add_theme_stylebox_override("panel", s)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_box = row
	icon = MenuGlyph.new(&"bulb", MenuKit.GOLD, 30)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", -2)
	row.add_child(col)
	title_label = MenuKit.label("", 15, MenuKit.GOLD, MenuKit.nunito(900))
	col.add_child(title_label)
	text_label = MenuKit.label("", 14, MenuKit.TEXT, MenuKit.nunito(700))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(custom_minimum_size.x - 74, 0)
	col.add_child(text_label)


func _ready() -> void:
	build_messages()
	_show(0)
	_timer = Timer.new()
	_timer.wait_time = Balance.get_float("menu", "info_banner_interval", 6.0)
	_timer.timeout.connect(next)
	add_child(_timer)
	_timer.start()


## Construit la liste des messages (heure UTC courante).
func build_messages(unix_time: int = -1) -> void:
	var t: int = unix_time if unix_time >= 0 else MapRotation.now()
	messages.clear()
	if not MapRotation.is_restricted():
		var ev: Dictionary = MapRotation.active_event(t)
		if not ev.is_empty():
			var c: MapCard = ev["card"]
			messages.append({"icon": &"clock", "title": "Événement en cours",
				"text": "%s · fin dans %s" % [c.display_name, MapRotation.format_short(MapRotation.time_left(ev, t))]})
		else:
			var nx: Dictionary = MapRotation.next_event(t)
			if not nx.is_empty():
				messages.append({"icon": &"clock", "title": "Prochain événement",
					"text": "%s dans %s" % [(nx["card"] as MapCard).display_name,
						MapRotation.format_short(int(nx["starts_at"]) - t)]})
		var weekly: Array[MapCard] = []
		if MapRotation.is_enabled(MapCard.CATEGORY_WEEKLY):
			weekly = MapRotation.weekly_cards(t)
		if not weekly.is_empty():
			var names: PackedStringArray = []
			for c2: MapCard in weekly:
				names.append(c2.display_name)
			messages.append({"icon": &"flag", "title": "Rotation de la semaine", "text": ", ".join(names)})
	else:
		var card := PlayCard.displayed_card()
		if card != null:
			messages.append({"icon": &"flag", "title": "Carte disponible",
				"text": "%s · %s" % [card.display_name, card.biome_name()]})
	# Pass de combat : palier et récompenses à récupérer
	var bp := BattlePassSystem.get_instance()
	var n_claim: int = bp.claimable_count()
	if n_claim > 0:
		messages.push_front({"icon": &"star", "title": "Pass de combat",
			"text": "%d récompense%s à récupérer" % [n_claim, "s" if n_claim > 1 else ""]})
	else:
		messages.append({"icon": &"star", "title": bp.get_season().display_name,
			"text": "Palier %d sur %d · +XP à chaque raid" % [bp.tier(), bp.max_tier()]})
	var start: int = int(t / 600) % TIPS.size()
	for i: int in TIPS.size():
		messages.append({"icon": &"bulb", "title": "Astuce", "text": TIPS[(start + i) % TIPS.size()]})


## Message ponctuel (ex. « Bientôt disponible »), puis reprise du défilement.
func show_message(text: String, title: String = "Bientôt") -> void:
	messages.insert(0, {"icon": &"clock", "title": title, "text": text})
	_show(0)
	_box.modulate.a = 1.0
	if _timer != null:
		_timer.start()
	messages.remove_at(0)
	index = -1


func next() -> void:
	if messages.size() < 2:
		return
	var tw := create_tween()
	tw.tween_property(_box, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void: _show((index + 1) % messages.size()))
	tw.tween_property(_box, "modulate:a", 1.0, 0.3)


func _show(i: int) -> void:
	if messages.is_empty():
		return
	index = i
	var m: Dictionary = messages[i]
	icon.kind = m["icon"]
	icon.queue_redraw()
	title_label.text = String(m["title"])
	text_label.text = String(m["text"])
