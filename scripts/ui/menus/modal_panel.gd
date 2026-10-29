class_name ModalPanel
extends Control
## Fenêtre modale plein écran : voile bleu nuit + panneau centré (titre Rye, contenu,
## bouton « Fermer »). Ouverture/fermeture animées par Tween. Échap / bouton B = fermer.
## Sous-classes : OptionsPanel, CreditsPanel. Fonctionne aussi pendant la pause.

signal closed

var panel_title: String = ""
var panel_size: Vector2 = Vector2(640, 520)
var body: VBoxContainer = null
var close_button: Button = null
var _panel: PanelContainer = null


func _init(title_text: String = "", size_px: Vector2 = Vector2(640, 520)) -> void:
	panel_title = title_text
	panel_size = size_px


func _ready() -> void:
	add_to_group(&"menu_modals")   # TouchScroller : pas de défilement sous une fenêtre
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.color = Color(MenuKit.NIGHT_DEEP, 0.72)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			close())
	add_child(veil)

	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(center)
	_panel = MenuKit.panel(Color(MenuKit.NIGHT, 0.97), 22, 26)
	var vp_h: float = get_viewport_rect().size.y
	_panel.custom_minimum_size = Vector2(panel_size.x, minf(panel_size.y, vp_h - 40.0))
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_panel.add_child(col)
	var head := MenuKit.title(panel_title, 40)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var sep := ColorRect.new()
	sep.color = Color(MenuKit.GOLD, 0.45)
	sep.custom_minimum_size = Vector2(0, 2)
	col.add_child(sep)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	close_button = MenuKit.button("Fermer", MenuKit.Style.SECONDARY, 24, Vector2(220, 62))
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	col.add_child(close_button)
	_build_body()

	# Apparition
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)
	modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.25)
	MenuKit.sfx(&"panel_open", -4.0)
	_focus_first.call_deferred()


## À surcharger : remplit `body`.
func _build_body() -> void:
	pass


func _focus_first() -> void:
	if not is_inside_tree():
		return
	var first: Control = _find_focusable(body)
	(first if first != null else close_button).grab_focus()


static func _find_focusable(n: Node) -> Control:
	for c: Node in n.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and (c as Control).visible:
			return c
		var deep: Control = _find_focusable(c)
		if deep != null:
			return deep
	return null


func close() -> void:
	if get_meta(&"_closing", false):
		return
	set_meta(&"_closing", true)
	MenuKit.sfx(&"panel_close", -4.0)
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
	tw.tween_property(_panel, "scale", Vector2(0.95, 0.95), 0.14)
	tw.chain().tween_callback(func() -> void:
		closed.emit()
		queue_free())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
