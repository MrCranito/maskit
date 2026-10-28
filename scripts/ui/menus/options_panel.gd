class_name OptionsPanel
extends ModalPanel
## Options : volume de la musique, volume des effets (AudioManager), vibrations on/off,
## économie d'énergie (30 images/s, moins de chauffe et de batterie).
## Les valeurs sont sauvegardées dans SaveManager.data["settings"] (MenuKit.set_setting).

var music_slider: HSlider = null
var sfx_slider: HSlider = null
var vibration_toggle: Button = null
var power_toggle: Button = null


func _init() -> void:
	super._init("Options", Vector2(620, 520))


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

	# Économie d'énergie : limite à 30 images/s (moins de chauffe sur téléphone).
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	body.add_child(row2)
	var l2 := MenuKit.label("Économie d'énergie", 26, MenuKit.TEXT, MenuKit.nunito(800))
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(l2)
	power_toggle = MenuKit.button("", MenuKit.Style.SECONDARY, 22, Vector2(200, 60))
	power_toggle.toggle_mode = true
	power_toggle.button_pressed = bool(MenuKit.get_setting(&"power_saving", false))
	power_toggle.text = "30 i/s" if power_toggle.button_pressed else "60 i/s"
	var on2 := MenuKit.panel_style(Color(0.18, 0.5, 0.3), Color(0.6, 1.0, 0.7, 0.8), 16, 2, 10)
	on2.border_width_bottom = 5
	power_toggle.add_theme_stylebox_override("pressed", on2)
	power_toggle.add_theme_stylebox_override("hover_pressed", on2)
	power_toggle.add_theme_color_override("font_pressed_color", MenuKit.TEXT)
	power_toggle.toggled.connect(func(on: bool) -> void:
		power_toggle.text = "30 i/s" if on else "60 i/s"
		MenuKit.set_setting(&"power_saving", on)
		GameState.apply_power_saving(on)
		MenuKit.sfx(&"toggle"))
	row2.add_child(power_toggle)


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
