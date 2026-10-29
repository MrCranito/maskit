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
	# Maquette Hud : encre translucide, coin haut gauche coupé, sans contour
	var st := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.72), s * 0.22, Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
	st.corners = CutBox.CUT_TOP_LEFT
	var st_h := st.duplicate() as CutBox
	st_h.bg_color = Color(MenuKit.NIGHT_PANEL, 0.9)
	var st_p := st.duplicate() as CutBox
	st_p.bg_color = Color(MenuKit.VIOLET, 0.8)
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
		var c: Color = MenuKit.TEXT
		for k: int in 2:
			var x: float = sz.x * 0.5 + (k * 2 - 1) * sz.x * 0.11 - bw * 0.5
			pause_button.draw_rect(Rect2(x, (sz.y - bh) * 0.5, bw, bh), c))
	pause_button.mouse_entered.connect(pause_button.queue_redraw)
	pause_button.mouse_exited.connect(pause_button.queue_redraw)
	pause_button.pressed.connect(toggle)
	MenuKit.add_feedback(pause_button, 1.08)
	add_child(pause_button)


## Écran de pause (direction D, même grammaire que les écrans de fin de raid) : voile encre,
## à gauche carte · difficulté, « PAUSE » en Anton et le rappel des pertes ; à droite bandeau
## violet dépoli : Options, Abandonner le raid (encre), puis « REPRENDRE » en grand.
func _build_overlay() -> void:
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	var m: Vector4 = MenuKit.safe_margins(self)
	m.x = maxf(m.x, Balance.get_float("menu", "lobby_margin_left", 80.0))
	m.w = maxf(m.w, Balance.get_float("menu", "lobby_margin_bottom", 36.0))
	var vp: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var slab_w: float = clampf(vp.x * Balance.get_float("menu", "lobby_slab_ratio", 0.3),
		Balance.get_float("menu", "lobby_slab_min", 370.0), Balance.get_float("menu", "lobby_slab_max", 440.0))
	var g := Gradient.new()
	g.set_color(0, Color(MenuKit.NIGHT_DEEP, 0.97))
	g.add_point(0.55, Color(MenuKit.NIGHT_DEEP, 0.85))
	g.set_color(g.get_point_count() - 1, Color(MenuKit.NIGHT_DEEP, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 4
	var veil := TextureRect.new()
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(veil)
	var deco := MainMenu.LobbyDeco.new()
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(deco)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.position = Vector2(m.x, maxf(m.y, 24.0) + 6.0)
	overlay.add_child(left)
	var card: MapCard = GameState.current_map as MapCard
	var info := MenuKit.label("%s · %s" % [card.display_name if card != null else "Raid",
		GameState.difficulty_name(GameState.difficulty)], 18, MenuKit.GOLD, MenuKit.nunito(600), 0)
	info.uppercase = true
	left.add_child(info)
	left.add_child(MenuKit.label("PAUSE", int(Balance.get_value("menu", "raid_end_title_size", 132)), MenuKit.TEXT, MenuKit.display(), 0))
	var warn := MenuKit.label("Abandonner = mort : arsenal et butin perdus.", 18, Color(1.0, 0.44, 0.57), MenuKit.nunito(600), 0)
	warn.uppercase = true
	left.add_child(warn)

	var sl := MainMenu.LobbySlab.new()
	sl.name = "Slab"
	sl.cut = Balance.get_float("menu", "lobby_slab_cut", 94.0)
	sl.color = Color(MenuKit.VIOLET, Balance.get_float("menu", "lobby_slab_alpha", 0.66) - 0.04)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.anchor_left = 1.0
	sl.anchor_right = 1.0
	sl.anchor_bottom = 1.0
	sl.offset_left = -slab_w
	overlay.add_child(sl)
	MenuKit.frosted(sl)
	_panel = sl
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 16.0
	col.offset_top = maxf(m.y, 36.0) + 70.0
	col.offset_right = -maxf(m.z, 44.0)
	col.offset_bottom = -maxf(m.w, 40.0)
	col.add_theme_constant_override("separation", 10)
	sl.add_child(col)
	options_button = _ink_button("Options", MenuKit.TEXT)
	abandon_button = _ink_button("Abandonner le raid", Color(1.0, 0.6, 0.7))
	quit_button = abandon_button  # compatibilité
	col.add_child(options_button)
	col.add_child(abandon_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	resume_button = Button.new()
	resume_button.name = "ResumeButton"
	resume_button.text = "REPRENDRE"
	resume_button.focus_mode = Control.FOCUS_ALL
	resume_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	resume_button.add_theme_font_override("font", MenuKit.display())
	resume_button.add_theme_font_size_override("font_size", int(Balance.get_value("menu", "deploy_font_size", 84)))
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		resume_button.add_theme_color_override(k, MenuKit.TEXT)
	var hov := CutBox.make(Color(1, 1, 1, 0.1), 14.0, Color(0, 0, 0, 0), 0.0, 6.0, 0.0)
	var none := CutBox.make(Color(0, 0, 0, 0), 14.0, Color(0, 0, 0, 0), 0.0, 6.0, 0.0)
	var foc := CutBox.make(Color(0, 0, 0, 0), 14.0, Color(0, 0, 0, 0), 0.0, 6.0, 0.0)   # bouton principal : pas de cadre
	resume_button.add_theme_stylebox_override("normal", none)
	resume_button.add_theme_stylebox_override("pressed", none)
	resume_button.add_theme_stylebox_override("hover", hov)
	resume_button.add_theme_stylebox_override("hover_pressed", hov)
	resume_button.add_theme_stylebox_override("focus", foc)
	MenuKit.add_feedback(resume_button, 1.03)
	col.add_child(resume_button)
	resume_button.pressed.connect(close)
	options_button.pressed.connect(open_options)
	abandon_button.pressed.connect(ask_abandon)


## Bouton encre à coin haut gauche coupé, libellé Anton, aligné à droite dans le bandeau.
func _ink_button(txt: String, color: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size = Vector2(Balance.get_float("menu", "loadout_detail_width", 300.0), 66)
	b.add_theme_font_override("font", MenuKit.display())
	b.add_theme_font_size_override("font_size", 25)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, color)
	var mk := func(bg: Color, border: Color) -> CutBox:
		var c := CutBox.make(bg, 16.0, border, 2.0 if border.a > 0.0 else 0.0, 16.0, 0.0)
		c.corners = CutBox.CUT_TOP_LEFT
		return c
	b.add_theme_stylebox_override("normal", mk.call(MenuKit.NIGHT_DEEP, Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", mk.call(MenuKit.NIGHT_PANEL, Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0, 0, 0, 1), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover_pressed", mk.call(Color(0, 0, 0, 1), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), MenuKit.TEXT))
	MenuKit.add_feedback(b, 1.04)
	return b


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
		var l0: float = panel.offset_left
		tw.tween_property(panel, "offset_left", l0, 0.3).from(l0 + 120.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "offset_right", 0.0, 0.3).from(120.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
