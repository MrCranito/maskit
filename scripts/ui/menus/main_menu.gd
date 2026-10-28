class_name MainMenu
extends Control
## Menu principal : fond animé (ciel + ville + poussière), titre Rye, masque porté,
## boutons Jouer / Masques / Options / Crédits. Musique western_hub.
## Navigation : souris, tactile, clavier et manette (focus, ui_up/ui_down).
## « Jouer » et « Masques » ouvrent la sélection du masque (Jouer : directement sur
## la carte du masque porté, prêt à valider).

var play_button: Button = null
var masks_button: Button = null
var options_button: Button = null
var credits_button: Button = null
var buttons: Array[Button] = []
var _title_box: Control = null
var _mask_badge: TextureRect = null
var _modal: ModalPanel = null


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
	row.add_theme_constant_override("separation", 24)
	safe.add_child(row)

	# Colonne gauche : titre + masque porté
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 4)
	row.add_child(left)
	_title_box = left
	var t1 := MenuKit.title("Les Royaumes", 74)
	var t2 := MenuKit.title("des Masques", 74)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(t1)
	left.add_child(t2)
	var sub := MenuKit.label("E X T R A C T I O N", 24, MenuKit.GOLD, MenuKit.nunito(900), 5)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(sub)
	var tag := MenuKit.label("Chaque masque donne un pouvoir. Chaque pouvoir change ton style de jeu.",
		19, MenuKit.TEXT, MenuKit.nunito(700), 5)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.custom_minimum_size = Vector2(420, 0)
	left.add_child(tag)
	left.add_child(_build_mask_badge())

	# Colonne droite : boutons dans un panneau bleu nuit
	var right := CenterContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	var panel := MenuKit.panel(Color(MenuKit.NIGHT, 0.82), 24, 22)
	right.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var w: float = Balance.get_float("menu", "main_button_width", 340.0)
	var h: float = Balance.get_float("menu", "main_button_height", 78.0)
	play_button = MenuKit.button("Jouer", MenuKit.Style.PRIMARY, 34, Vector2(w, h + 8))
	masks_button = MenuKit.button("Masques", MenuKit.Style.SECONDARY, 28, Vector2(w, h))
	options_button = MenuKit.button("Options", MenuKit.Style.SECONDARY, 28, Vector2(w, h))
	credits_button = MenuKit.button("Crédits", MenuKit.Style.GHOST, 24, Vector2(w, h - 14))
	buttons = [play_button, masks_button, options_button, credits_button]
	for b: Button in buttons:
		col.add_child(b)
	play_button.pressed.connect(_on_play)
	masks_button.pressed.connect(_on_masks)
	options_button.pressed.connect(open_options)
	credits_button.pressed.connect(open_credits)
	# Navigation verticale en boucle (manette / clavier)
	for i: int in buttons.size():
		var b: Button = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()

	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	var ver := MenuKit.label("v" + (version if not version.is_empty() else "0.1"),
		14, Color(MenuKit.TEXT_DIM, 0.6), MenuKit.nunito(600))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.position -= Vector2(MenuKit.safe_margins(self).z, 8)
	add_child(ver)


## Badge « masque porté » (portrait + nom), sous le titre.
func _build_mask_badge() -> Control:
	var mask: MaskData = GameState.get_selected_mask()
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := MenuKit.panel(Color(MenuKit.NIGHT, 0.78), 18, 10)
	holder.add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	_mask_badge = TextureRect.new()
	_mask_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mask_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mask_badge.custom_minimum_size = Vector2(64, 64)
	_mask_badge.texture = mask.portrait if mask != null else null
	row.add_child(_mask_badge)
	var txt := VBoxContainer.new()
	txt.alignment = BoxContainer.ALIGNMENT_CENTER
	txt.add_theme_constant_override("separation", -2)
	row.add_child(txt)
	txt.add_child(MenuKit.label("Masque porté", 15, MenuKit.TEXT_DIM, MenuKit.nunito(700)))
	var n := MenuKit.label(mask.display_name if mask != null else "-", 24,
		mask.aura_color.lightened(0.25) if mask != null else MenuKit.TEXT, MenuKit.nunito(900))
	txt.add_child(n)
	var diff := MenuKit.label("Difficulté : " + GameState.difficulty_name(GameState.difficulty), 15,
		MenuKit.TEXT_DIM, MenuKit.nunito(700))
	txt.add_child(diff)
	return holder


func _intro() -> void:
	_title_box.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(_title_box, "modulate:a", 1.0, 0.5)
	tw.tween_property(_title_box, "position:y", 0.0, 0.5).from(-12.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i: int in buttons.size():
		var b: Button = buttons[i]
		b.modulate.a = 0.0
		tw.tween_property(b, "modulate:a", 1.0, 0.3).set_delay(0.1 + 0.07 * i)


func _on_play() -> void:
	MenuKit.sfx(&"confirm")
	MaskSelect.open_on_selected = true
	MenuKit.go_to(self, MenuKit.MASK_SELECT_SCENE)


func _on_masks() -> void:
	MenuKit.sfx(&"click")
	MaskSelect.open_on_selected = false
	MenuKit.go_to(self, MenuKit.MASK_SELECT_SCENE)


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
