class_name OptionsPanel
extends ModalPanel
## Options : volume de la musique, volume des effets (AudioManager), vibrations on/off,
## images par seconde (Max = fréquence de l'écran jusqu'à 120, 60, ou éco 30 : moins de chauffe).
## Les valeurs sont sauvegardées dans SaveManager.data["settings"] (MenuKit.set_setting).
## Versions de test uniquement (DevMode.is_available : build debug ou éditeur, donc l'APK de la CI) :
## interrupteur « Argent illimité » (DevMode), seule façon de l'activer sur téléphone (pas de F3/F4),
## et interrupteur « Tout débloquer » (profil de développement virtuel, la vraie sauvegarde est gardée).

var music_slider: HSlider = null
var sfx_slider: HSlider = null
var vibration_toggle: Button = null
## Images par seconde (FrameRate) : Max → 60 → éco.
var fps_button: Button = null
## Interrupteur du mode dev « argent illimité » (null hors version de test).
var dev_toggle: Button = null
## Interrupteur « Tout débloquer » (DevMode.set_all_unlocked ; null hors version de test).
var unlock_toggle: Button = null
## Section « Sauvegarde cloud » (CloudSync) : état + compte, bouton Synchroniser.
var cloud_status_label: Label = null
var sync_button: Button = null


func _init() -> void:
	super._init("Options", Vector2(620, Balance.get_float("menu", "options_height_dev", 690.0)
		if DevMode.is_available() else Balance.get_float("menu", "options_height", 520.0)))


func _build_body() -> void:
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
	vibration_toggle = MenuKit.button("", MenuKit.Style.SECONDARY, 22, Vector2(200, 60))
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
	fps_button = MenuKit.button(FrameRate.label_for(FrameRate.saved_mode()), MenuKit.Style.SECONDARY, 22, Vector2(240, 60))
	fps_button.pressed.connect(func() -> void:
		var mode := FrameRate.next_mode(FrameRate.saved_mode())
		FrameRate.apply(mode, true)
		fps_button.text = FrameRate.label_for(mode)
		MenuKit.sfx(&"toggle"))
	row2.add_child(fps_button)
	_build_dev()
	_build_account()


## Versions de test : gemmes et or illimités (DevMode), le vrai solde n'est jamais touché.
func _build_dev() -> void:
	if not DevMode.is_available():
		return
	dev_toggle = _dev_row("DevRow", "DevToggle", "Argent illimité",
		"Version de test : gemmes et or ∞, ton vrai solde est gardé", DevMode.is_unlimited(),
		func(v: bool) -> bool: return DevMode.set_unlimited(v))
	unlock_toggle = _dev_row("UnlockRow", "UnlockToggle", "Tout débloquer",
		"Armes, objets, skins, pass, cartes : profil de test, ta sauvegarde est gardée",
		DevMode.is_all_unlocked(), func(v: bool) -> bool:
			var now := DevMode.set_all_unlocked(v)
			if now != v:
				MenuKit.sfx(&"error")
			return now)


## Ligne du mode développeur : titre, sous-titre, interrupteur violet. `apply(v) -> bool` renvoie
## l'état réellement obtenu (refus possible : bascule pendant un raid).
func _dev_row(row_name: String, toggle_name: String, title: String, sub: String, pressed: bool,
		apply: Callable) -> Button:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	col.add_child(MenuKit.label(title, 26, MenuKit.TEXT, MenuKit.nunito(800)))
	var sl := MenuKit.label(sub, 15, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sl)
	var t := MenuKit.button("", MenuKit.Style.SECONDARY, 22, Vector2(200, 60))
	t.name = toggle_name
	t.toggle_mode = true
	t.button_pressed = pressed
	t.text = "Activé" if pressed else "Désactivé"
	var on := MenuKit.panel_style(MenuKit.VIOLET, Color(MenuKit.GOLD, 0.9), 16, 2, 10)
	on.border_width_bottom = 5
	t.add_theme_stylebox_override("pressed", on)
	t.add_theme_stylebox_override("hover_pressed", on)
	t.add_theme_color_override("font_pressed_color", MenuKit.TEXT)
	t.toggled.connect(func(v: bool) -> void:
		var now: bool = apply.call(v)
		t.set_pressed_no_signal(now)
		t.text = "Activé" if now else "Désactivé"
		MenuKit.sfx(&"toggle"))
	row.add_child(t)
	return t


## Compte et sauvegarde cloud (CloudSync) : état, identifiant du compte invité, bouton Synchroniser.
## La liaison Apple / Google viendra ici.
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
	col.add_child(cloud_status_label)
	sync_button = MenuKit.button("Synchroniser", MenuKit.Style.SECONDARY, 22, Vector2(240, 60))
	sync_button.pressed.connect(func() -> void:
		MenuKit.sfx(&"click")
		cs.call("sync"))
	row.add_child(sync_button)
	cs.connect(&"status_changed", func(_s: StringName) -> void: _refresh_account(cs))
	_refresh_account(cs)


func _refresh_account(cs: Node) -> void:
	if not is_instance_valid(cloud_status_label):
		return
	var who := ("Compte invité %s" if bool(cs.get("is_anonymous")) else "Compte lié %s") % str(cs.call("short_id"))
	cloud_status_label.text = "%s · %s" % [str(cs.call("status_label", cs.get("status"))), who]
	sync_button.disabled = cs.get("status") == &"syncing"


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
	s.custom_minimum_size = Vector2(0, 44)
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
