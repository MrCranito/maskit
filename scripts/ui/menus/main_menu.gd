class_name MainMenu
extends Control
## Menu principal d'Exfil Rush : fond animé, logo + slogan, héros avec son skin
## (HeroPreview), compteur de gemmes, boutons Jouer / Arsenal / Boutique / Options / Crédits.
## « Jouer » → choix de la carte → arsenal de départ → raid.
## Navigation : souris, tactile, clavier et manette (focus, ui_up/ui_down).

var play_button: Button = null
var arsenal_button: Button = null
var shop_button: Button = null
var options_button: Button = null
var credits_button: Button = null
var buttons: Array[Button] = []
var logo: ExfilLogo = null
var hero: HeroPreview = null
var gem_counter: GemCounter = null
var _modal: ModalPanel = null
var _stash_label: Label = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	add_child(MenuBackground.new())
	_build()
	_intro()
	MenuKit.fade_in(self)
	play_button.grab_focus.call_deferred()


func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 20)
	safe.add_child(row)

	# Gauche : logo en haut, héros en bas
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 0)
	row.add_child(left)
	var logo_box := HBoxContainer.new()
	logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(logo_box)
	logo = ExfilLogo.new(int(Balance.get_value("menu", "logo_size", 84)))
	logo_box.add_child(logo)
	# Héros : centré sous le logo, hauteur bornée (lisible sans agrandir la planche à l'excès)
	var hero_box := CenterContainer.new()
	hero_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(hero_box)
	hero = HeroPreview.new()
	var hh: float = Balance.get_float("menu", "main_hero_height", 380.0)
	hero.custom_minimum_size = Vector2(hh * 0.9, hh)
	hero_box.add_child(hero)

	# Droite : gemmes + boutons
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(top)
	gem_counter = GemCounter.new(26)
	gem_counter.pressed.connect(func() -> void: _go_shop(&"gems"))
	top.add_child(gem_counter)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(spacer)
	var panel := MenuKit.panel(Color(MenuKit.NIGHT, 0.86), 24, 20)
	right.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var w: float = Balance.get_float("menu", "main_button_width", 340.0)
	var h: float = Balance.get_float("menu", "main_button_height", 78.0)
	play_button = MenuKit.button("Jouer", MenuKit.Style.PRIMARY, 38, Vector2(w, h + 14))
	arsenal_button = MenuKit.button("Arsenal", MenuKit.Style.SECONDARY, 26, Vector2(w, h - 8))
	shop_button = MenuKit.button("Boutique", MenuKit.Style.SECONDARY, 26, Vector2(w, h - 8))
	options_button = MenuKit.button("Options", MenuKit.Style.GHOST, 21, Vector2((w - 12) * 0.5, 64))
	credits_button = MenuKit.button("Crédits", MenuKit.Style.GHOST, 21, Vector2((w - 12) * 0.5, 64))
	col.add_child(play_button)
	col.add_child(arsenal_button)
	col.add_child(shop_button)
	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 12)
	small.add_child(options_button)
	small.add_child(credits_button)
	col.add_child(small)
	buttons = [play_button, arsenal_button, shop_button, options_button, credits_button]
	_stash_label = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	_stash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_stash_label)
	_update_stash_label()
	Profile.changed.connect(_update_stash_label)
	play_button.pressed.connect(_on_play)
	arsenal_button.pressed.connect(_on_arsenal)
	shop_button.pressed.connect(func() -> void: _go_shop(&""))
	options_button.pressed.connect(open_options)
	credits_button.pressed.connect(open_credits)
	# Navigation manette / clavier
	_link(play_button, credits_button, arsenal_button)
	_link(arsenal_button, play_button, shop_button)
	_link(shop_button, arsenal_button, options_button)
	_link(options_button, shop_button, play_button)
	_link(credits_button, shop_button, play_button)
	options_button.focus_neighbor_right = options_button.get_path_to(credits_button)
	credits_button.focus_neighbor_left = credits_button.get_path_to(options_button)

	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	var ver := MenuKit.label("v" + (version if not version.is_empty() else "0.1"),
		14, Color(MenuKit.TEXT_DIM, 0.6), MenuKit.nunito(600))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.position += Vector2(MenuKit.safe_margins(self).x, -8)
	add_child(ver)


func _link(b: Button, up: Button, down: Button) -> void:
	b.focus_neighbor_top = b.get_path_to(up)
	b.focus_neighbor_bottom = b.get_path_to(down)


func _update_stash_label() -> void:
	if _stash_label == null:
		return
	var n: int = Profile.weapons.size()
	_stash_label.text = "%d arme%s en réserve" % [n, "s" if n > 1 else ""]


func _intro() -> void:
	logo.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(logo, "modulate:a", 1.0, 0.45)
	tw.tween_property(logo, "position:x", 0.0, 0.5).from(-30.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	hero.modulate.a = 0.0
	tw.tween_property(hero, "modulate:a", 1.0, 0.5).set_delay(0.15)
	for i: int in buttons.size():
		var b: Button = buttons[i]
		b.modulate.a = 0.0
		tw.tween_property(b, "modulate:a", 1.0, 0.25).set_delay(0.1 + 0.06 * i)


func _on_play() -> void:
	MenuKit.sfx(&"confirm")
	MenuKit.go_to(self, MenuKit.MAP_SELECT_SCENE)


func _on_arsenal() -> void:
	MenuKit.sfx(&"click")
	MenuKit.go_to(self, MenuKit.ARSENAL_SCENE)


func _go_shop(tab: StringName) -> void:
	MenuKit.sfx(&"click")
	if tab != &"":
		ShopScreen.last_tab = tab
	MenuKit.go_to(self, MenuKit.SHOP_SCENE)


func open_options() -> ModalPanel:
	MenuKit.sfx(&"click")
	return _open_modal(OptionsPanel.new(), options_button)


func open_credits() -> ModalPanel:
	MenuKit.sfx(&"click")
	return _open_modal(CreditsPanel.new(), credits_button)


func _open_modal(m: ModalPanel, return_focus: Control) -> ModalPanel:
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = m
	add_child(m)
	m.closed.connect(func() -> void:
		if is_instance_valid(return_focus):
			return_focus.grab_focus())
	return m


func _unhandled_input(event: InputEvent) -> void:
	# Aucun bouton focalisé (clic dans le vide) : la manette/le clavier reprend sur « Jouer ».
	if is_instance_valid(_modal):
		return
	if (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")) \
			and get_viewport().gui_get_focus_owner() == null:
		play_button.grab_focus()
		get_viewport().set_input_as_handled()
