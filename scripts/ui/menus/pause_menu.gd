class_name PauseMenu
extends Control
## Pause en jeu : bouton pause rond (en haut à droite, à gauche de l'emplacement du
## bouton sac) + menu Reprendre / Options / Abandonner le raid (avec confirmation :
## l'arsenal emporté et le butin sont perdus → abandon_raid() de la scène de raid).
## Met l'arbre en pause (get_tree().paused) ; ce nœud tourne en PROCESS_MODE_ALWAYS.
## Touche Échap / Start (action « ui_cancel » ou « pause ») : ouvre / ferme.
##
## Installation (une ligne dans Raid._build_ui(), après la création de ui_layer) :
##   PauseMenu.attach(ui_layer)
## ou instancier res://scenes/ui/menus/pause_menu.tscn dans n'importe quel CanvasLayer.

const SCENE_PATH := "res://scenes/ui/menus/pause_menu.tscn"

signal paused_changed(paused: bool)

var pause_button: Button = null
var overlay: Control = null
var resume_button: Button = null
var options_button: Button = null
var quit_button: Button = null
var abandon_button: Button = null
var is_open: bool = false
var _modal: ModalPanel = null
var _panel: Control = null


## Ajoute le menu pause au CanvasLayer d'UI (ou à tout nœud) et le renvoie.
static func attach(parent: Node) -> PauseMenu:
	var existing := parent.get_node_or_null(^"PauseMenu") as PauseMenu
	if existing != null:
		return existing
	var pm: PauseMenu
	if ResourceLoader.exists(SCENE_PATH):
		pm = (load(SCENE_PATH) as PackedScene).instantiate() as PauseMenu
	else:
		pm = PauseMenu.new()
	pm.name = "PauseMenu"
	parent.add_child(pm)
	return pm


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	_build_button()
	_build_overlay()


func _build_button() -> void:
	var m: Vector4 = MenuKit.safe_margins(self)
	var s: float = Balance.get_float("menu", "pause_button_size", 64.0)
	var top: float = Balance.get_float("hud", "margin", 16.0)
	# Emplacement réservé au bouton sac (même taille) tout à droite.
	var bag_gap: float = Balance.get_float("menu", "pause_bag_slot", 76.0)
	pause_button = Button.new()
	pause_button.name = "PauseButton"
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.custom_minimum_size = Vector2(s, s)
	pause_button.text = ""
	pause_button.tooltip_text = "Pause (Échap)"
	var st := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.88), Color(0.85, 0.88, 0.95, 0.6), int(s * 0.5), 2, 12)
	st.shadow_size = 4
	var st_h := st.duplicate() as StyleBoxFlat
	st_h.bg_color = Color(0.16, 0.2, 0.34, 0.95)
	var st_p := st.duplicate() as StyleBoxFlat
	st_p.bg_color = MenuKit.RED_DARK
	pause_button.add_theme_stylebox_override("normal", st)
	pause_button.add_theme_stylebox_override("hover", st_h)
	pause_button.add_theme_stylebox_override("pressed", st_p)
	pause_button.add_theme_stylebox_override("hover_pressed", st_p)
	pause_button.anchor_left = 1.0
	pause_button.anchor_right = 1.0
	pause_button.offset_right = -(maxf(m.z, top) + bag_gap)
	pause_button.offset_left = pause_button.offset_right - s
	pause_button.offset_top = maxf(m.y, top)
	pause_button.offset_bottom = pause_button.offset_top + s
	# Icône pause dessinée (deux barres blanches nettes, lisibles à toute taille)
	pause_button.draw.connect(func() -> void:
		var sz: Vector2 = pause_button.size
		var bw: float = sz.x * 0.13
		var bh: float = sz.y * 0.4
		var c: Color = MenuKit.GOLD if pause_button.is_hovered() else MenuKit.TEXT
		for k: int in 2:
			var x: float = sz.x * 0.5 + (k * 2 - 1) * sz.x * 0.11 - bw * 0.5
			pause_button.draw_rect(Rect2(x, (sz.y - bh) * 0.5, bw, bh), c))
	pause_button.mouse_entered.connect(pause_button.queue_redraw)
	pause_button.mouse_exited.connect(pause_button.queue_redraw)
	pause_button.pressed.connect(toggle)
	MenuKit.add_feedback(pause_button, 1.08)
	add_child(pause_button)


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	var veil := ColorRect.new()
	veil.color = Color(MenuKit.NIGHT_DEEP, 0.7)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := MenuKit.panel(Color(MenuKit.NIGHT, 0.96), 24, 26)
	center.add_child(p)
	_panel = p
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	p.add_child(col)
	var t := MenuKit.title("Pause", 52)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var card: MapCard = GameState.current_map as MapCard
	var info := MenuKit.label("%s  ·  %s" % [card.display_name if card != null else "Raid",
		GameState.difficulty_name(GameState.difficulty)], 18, MenuKit.TEXT_DIM, MenuKit.nunito(700))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(info)
	var w := Vector2(Balance.get_float("menu", "main_button_width", 340.0), 74)
	resume_button = MenuKit.button("Reprendre", MenuKit.Style.PRIMARY, 30, w)
	options_button = MenuKit.button("Options", MenuKit.Style.SECONDARY, 26, w)
	abandon_button = MenuKit.button("Abandonner le raid", MenuKit.Style.GHOST, 22, w - Vector2(0, 10))
	abandon_button.add_theme_color_override("font_color", Color(1.0, 0.66, 0.6))
	abandon_button.add_theme_color_override("font_hover_color", Color(1.0, 0.75, 0.7))
	quit_button = abandon_button  # compatibilité
	for b: Button in [resume_button, options_button, abandon_button]:
		col.add_child(b)
	resume_button.pressed.connect(close)
	options_button.pressed.connect(open_options)
	abandon_button.pressed.connect(ask_abandon)
	var warn := MenuKit.label("Abandonner = mort : arsenal et butin perdus.", 15, Color(1.0, 0.6, 0.5, 0.85), MenuKit.nunito(700))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(warn)


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	get_tree().paused = true
	overlay.visible = true
	overlay.modulate.a = 0.0
	var panel: Control = _panel
	var tw := create_tween().set_parallel()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.15)
	if panel != null:
		panel.pivot_offset = panel.size * 0.5
		tw.tween_property(panel, "scale", Vector2.ONE, 0.22).from(Vector2(0.9, 0.9)) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	MenuKit.sfx(&"panel_open", -4.0)
	resume_button.grab_focus()
	paused_changed.emit(true)


func close() -> void:
	if not is_open:
		return
	if is_instance_valid(_modal):
		_modal.close()
		return
	is_open = false
	overlay.visible = false
	get_tree().paused = false
	MenuKit.sfx(&"panel_close", -4.0)
	var f := get_viewport().gui_get_focus_owner()
	if f != null:
		f.release_focus()
	paused_changed.emit(false)


func open_options() -> ModalPanel:
	MenuKit.sfx(&"click")
	_modal = OptionsPanel.new()
	overlay.add_child(_modal)
	_modal.closed.connect(func() -> void:
		if is_instance_valid(options_button):
			options_button.grab_focus())
	return _modal


## Confirmation avant d'abandonner (voir abandon()).
func ask_abandon() -> ConfirmPanel:
	MenuKit.sfx(&"click")
	var m := ConfirmPanel.new("Abandonner le raid ?",
		"Tu perdras ton arsenal et ton butin.\nLes armes emportées ne reviendront pas.",
		"Abandonner", true)
	m.confirmed.connect(abandon)
	m.closed.connect(func() -> void:
		if is_instance_valid(abandon_button) and is_open:
			abandon_button.grab_focus())
	_modal = m
	overlay.add_child(m)
	return m


## Abandon confirmé : la scène de raid gère la mort (abandon_raid : écran de mort, Profile,
## retour au menu). Sans raid (tests, scène de debug) : retour direct au menu.
func abandon() -> void:
	var scene: Node = get_tree().current_scene
	get_tree().paused = false
	is_open = false
	overlay.visible = false
	paused_changed.emit(false)
	if scene != null and scene.has_method("abandon_raid"):
		scene.call("abandon_raid")
	else:
		quit_to_menu()


func quit_to_menu() -> void:
	MenuKit.sfx(&"back")
	MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	var pause_pressed: bool = event.is_action_pressed("ui_cancel") \
		or (InputMap.has_action(&"pause") and event.is_action_pressed(&"pause")) \
		or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed
			and (event as InputEventJoypadButton).button_index == JOY_BUTTON_START)
	if not pause_pressed:
		return
	if is_instance_valid(_modal):
		return  # la fenêtre d'options gère sa fermeture
	get_viewport().set_input_as_handled()
	toggle()


func _exit_tree() -> void:
	# Sécurité : ne jamais laisser l'arbre en pause si le menu disparaît.
	if is_open and is_inside_tree():
		get_tree().paused = false
