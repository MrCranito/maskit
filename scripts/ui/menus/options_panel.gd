class_name OptionsPanel
extends ModalPanel
## Options : volume de la musique, volume des effets (AudioManager), vibrations on/off,
## images par seconde (Max = fréquence de l'écran jusqu'à 120, 60, ou éco 30 : moins de chauffe).
## Les valeurs sont sauvegardées dans SaveManager.data["settings"] (MenuKit.set_setting).

var music_slider: HSlider = null
var sfx_slider: HSlider = null
var vibration_toggle: Button = null
## Images par seconde (FrameRate) : Max → 60 → éco.
var fps_button: Button = null
## Section « Sauvegarde cloud » (CloudSync) : état + compte, Synchroniser, liaison Apple/Google,
## Restaurer mes achats, Supprimer mon compte.
var cloud_status_label: Label = null
var sync_button: Button = null
var link_row: HBoxContainer = null
var link_buttons: Array[Button] = []
var link_hint: Label = null
var restore_button: Button = null
var delete_button: Button = null


func _init() -> void:
	super._init("Options", Vector2(640, 660))


func _build_body() -> void:
	body.add_theme_constant_override("separation", 9)
	var am: Node = get_node_or_null(^"/root/AudioManager")
	var music_v: float = float(am.get("music_volume")) if am != null else 0.7
	var sfx_v: float = float(am.get("sfx_volume")) if am != null else 1.0
	music_slider = _slider_row("Musique", music_v, func(v: float) -> void:
		if am != null:
			am.set("music_volume", v)
		MenuKit.set_setting(&"music_volume", v))
	sfx_slider = _slider_row("Effets sonores", sfx_v, func(v: float) -> void:
		if am != null:
			am.set("sfx_volume", v)
		MenuKit.set_setting(&"sfx_volume", v)
		MenuKit.sfx(&"tick", -6.0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	var l := MenuKit.label("Vibrations", 26, MenuKit.TEXT, MenuKit.nunito(800))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	# Gros interrupteur tactile (bouton bascule stylé, vert = activé)
	vibration_toggle = MenuKit.button("", MenuKit.Style.SECONDARY, 20, Vector2(200, 52))
	vibration_toggle.toggle_mode = true
	vibration_toggle.button_pressed = bool(MenuKit.get_setting(&"vibration", true))
	vibration_toggle.text = "Activées" if vibration_toggle.button_pressed else "Désactivées"
	var on := MenuKit.panel_style(Color(0.18, 0.5, 0.3), Color(0.6, 1.0, 0.7, 0.8), 16, 2, 10)
	on.border_width_bottom = 5
	vibration_toggle.add_theme_stylebox_override("pressed", on)
	vibration_toggle.add_theme_stylebox_override("hover_pressed", on)
	vibration_toggle.add_theme_color_override("font_pressed_color", MenuKit.TEXT)
	vibration_toggle.toggled.connect(func(on: bool) -> void:
		vibration_toggle.text = "Activées" if on else "Désactivées"
		MenuKit.set_setting(&"vibration", on)
		MenuKit.sfx(&"toggle")
		MenuKit.vibrate())
	row.add_child(vibration_toggle)

	# Images par seconde : Max (fréquence de l'écran, 120 sur écran 120 Hz) → 60 → éco (30).
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	body.add_child(row2)
	var l2 := MenuKit.label("Images par seconde", 26, MenuKit.TEXT, MenuKit.nunito(800))
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(l2)
	fps_button = MenuKit.button(FrameRate.label_for(FrameRate.saved_mode()), MenuKit.Style.SECONDARY, 20, Vector2(220, 52))
	fps_button.pressed.connect(func() -> void:
		var mode := FrameRate.next_mode(FrameRate.saved_mode())
		FrameRate.apply(mode, true)
		fps_button.text = FrameRate.label_for(mode)
		MenuKit.sfx(&"toggle"))
	row2.add_child(fps_button)
	_build_account()


## Compte et sauvegarde cloud (CloudSync) : état, compte (invité ou lié), Synchroniser,
## liaison Apple / Google, Restaurer mes achats, Supprimer mon compte (exigé par les stores).
func _build_account() -> void:
	var cs: Node = get_node_or_null(^"/root/CloudSync")
	if cs == null or cs.get("status") == &"disabled":
		return
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.12)
	sep.custom_minimum_size = Vector2(0, 1)
	body.add_child(sep)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	col.add_child(MenuKit.label("Sauvegarde cloud", 26, MenuKit.TEXT, MenuKit.nunito(800)))
	cloud_status_label = MenuKit.label("", 16, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	cloud_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(cloud_status_label)
	sync_button = MenuKit.button("Synchroniser", MenuKit.Style.SECONDARY, 20, Vector2(220, 52))
	sync_button.pressed.connect(func() -> void:
		MenuKit.sfx(&"click")
		cs.call("sync"))
	row.add_child(sync_button)

	# Liaison Apple / Google (compte invité) — retrouver sa progression sur un autre appareil
	link_row = HBoxContainer.new()
	link_row.add_theme_constant_override("separation", 12)
	body.add_child(link_row)
	var lbl := MenuKit.label("Lier mon compte", 20, MenuKit.TEXT, MenuKit.nunito(700))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	link_row.add_child(lbl)
	for p: StringName in [&"apple", &"google"]:
		if bool(cs.call("link_available", p)):
			var b := MenuKit.button("Apple" if p == &"apple" else "Google", MenuKit.Style.SECONDARY, 19, Vector2(140, 48))
			b.pressed.connect(func() -> void:
				MenuKit.sfx(&"click")
				_set_link_hint("Connexion %s en cours…" % ("Apple" if p == &"apple" else "Google"))
				cs.call("link_account", p))
			link_row.add_child(b)
			link_buttons.append(b)
	link_hint = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(500))
	link_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	link_hint.visible = false
	body.add_child(link_hint)

	# Restaurer mes achats / Supprimer mon compte
	var row3 := HBoxContainer.new()
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	row3.add_theme_constant_override("separation", 12)
	body.add_child(row3)
	restore_button = MenuKit.button("Restaurer mes achats", MenuKit.Style.SECONDARY, 17, Vector2(240, 48))
	restore_button.pressed.connect(func() -> void:
		MenuKit.sfx(&"click")
		restore_button.disabled = true
		var ok: bool = await cs.call("restore_purchases")
		if is_instance_valid(restore_button):
			restore_button.disabled = false
			_set_link_hint("Achats restaurés" if ok else "Restauration impossible (hors ligne ?)"))
	row3.add_child(restore_button)
	delete_button = MenuKit.button("Supprimer mon compte", MenuKit.Style.SECONDARY, 17, Vector2(240, 48))
	delete_button.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	delete_button.pressed.connect(_confirm_delete)
	row3.add_child(delete_button)

	cs.connect(&"status_changed", func(_s: StringName) -> void: _refresh_account(cs))
	cs.connect(&"link_finished", func(ok: bool, msg: String) -> void:
		_set_link_hint(msg)
		MenuKit.sfx(&"confirm" if ok else &"error")
		_refresh_account(cs))
	_refresh_account(cs)


func _set_link_hint(text: String) -> void:
	if is_instance_valid(link_hint):
		link_hint.text = text
		link_hint.visible = not text.is_empty()


func _refresh_account(cs: Node) -> void:
	if not is_instance_valid(cloud_status_label):
		return
	var anon := bool(cs.get("is_anonymous"))
	var who := ("Compte invité %s" if anon else "Compte %s lié · %s") % (
		[str(cs.call("short_id"))] if anon else [str(cs.call("provider_label", StringName(str(cs.get("provider"))))), str(cs.call("short_id"))])
	cloud_status_label.text = "%s · %s" % [str(cs.call("status_label", cs.get("status"))), who]
	sync_button.disabled = cs.get("status") == &"syncing"
	if is_instance_valid(link_row):
		link_row.visible = anon and not link_buttons.is_empty()
	for b: Button in link_buttons:
		b.disabled = bool(cs.call("is_linking"))


## Suppression du compte : confirmation explicite, puis CloudSync.delete_account (serveur + local).
func _confirm_delete() -> void:
	MenuKit.sfx(&"click")
	var cs: Node = get_node_or_null(^"/root/CloudSync")
	var c := ConfirmPanel.new("Supprimer mon compte",
		"Ta progression, ton arsenal, tes gemmes et tes skins seront supprimés définitivement, sur cet appareil et dans le cloud. Les achats ne sont pas remboursés.",
		"Supprimer", true)
	get_parent().add_child(c)
	c.confirmed.connect(func() -> void:
		if cs == null:
			return
		delete_button.disabled = true
		cs.connect(&"account_deleted", func(ok: bool, msg: String) -> void:
			if not ok:
				if is_instance_valid(delete_button):
					delete_button.disabled = false
				_set_link_hint(msg)
				return
			var tree := get_tree()
			if tree != null and tree.current_scene != null:
				tree.reload_current_scene(), CONNECT_ONE_SHOT)
		cs.call("delete_account"))


func _slider_row(text: String, value: float, on_change: Callable) -> HSlider:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	body.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var l := MenuKit.label(text, 26, MenuKit.TEXT, MenuKit.nunito(800))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var pct := MenuKit.label("%d %%" % roundi(value * 100.0), 22, MenuKit.GOLD, MenuKit.nunito(800))
	top.add_child(pct)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.focus_mode = Control.FOCUS_ALL
	s.custom_minimum_size = Vector2(0, 36)
	_style_slider(s)
	s.value_changed.connect(func(v: float) -> void:
		pct.text = "%d %%" % roundi(v * 100.0)
		on_change.call(v))
	box.add_child(s)
	return s


static func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.03, 0.04, 0.09)
	track.set_corner_radius_all(8)
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	var fill := StyleBoxFlat.new()
	fill.bg_color = MenuKit.RED
	fill.set_corner_radius_all(8)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	var fill_hi := fill.duplicate() as StyleBoxFlat
	fill_hi.bg_color = MenuKit.RED.lightened(0.2)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MenuKit.GOLD
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(10)
	focus.set_expand_margin_all(4)
	s.add_theme_stylebox_override("focus", focus)
	s.add_theme_icon_override("grabber", _knob(Color(1, 0.97, 0.92)))
	s.add_theme_icon_override("grabber_highlight", _knob(MenuKit.GOLD))


static func _knob(c: Color) -> Texture2D:
	var size: int = 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r: float = size * 0.5 - 1.0
	for y: int in size:
		for x: int in size:
			var d: float = Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length()
			var a: float = clampf(r - d + 0.5, 0.0, 1.0)
			var col: Color = c if d < r - 3.0 else Color(0.2, 0.05, 0.08)
			img.set_pixel(x, y, Color(col, a))
	return ImageTexture.create_from_image(img)
