class_name MaskSelect
extends Control
## Sélection du masque : cartes des 5 masques (portrait, nom, description courte, stats),
## aperçu du héros 3D animé teinté par l'aura, panneau de détail, bouton « Choisir »
## → GameState.selected_mask_id (sauvegardé), puis choix de la difficulté et
## « Partir en raid » → res://scenes/dungeon/raid.tscn.
## Échap / bouton B : retour au menu principal.

## Mis par le menu principal (« Jouer ») : focus direct sur « Choisir ».
static var open_on_selected: bool = false

var masks: Array[MaskData] = []
var cards: Array[MaskCard] = []
var preview: HeroPreview = null
var choose_button: Button = null
var back_button: Button = null
var difficulty_panel: DifficultyPanel = null
## Masque affiché (pas forcément encore choisi).
var current: MaskData = null
## Scène lancée par « Partir en raid » (modifiable pour les tests).
var raid_scene: String = MenuKit.RAID_SCENE

var _background: MenuBackground = null
var _name: Label = null
var _desc: Label = null
var _power: Label = null
var _detail_panel: PanelContainer = null
var _detail_style: StyleBoxFlat = null
var _cards_row: HBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	_background = MenuBackground.new()
	_background.dim = Balance.get_float("menu", "mask_select_dim", 0.35)
	add_child(_background)
	masks = MaskData.load_all()
	_build()
	var start: MaskData = GameState.get_selected_mask()
	show_mask(start if start != null else (masks[0] if not masks.is_empty() else null), false)
	_refresh_equipped()
	MenuKit.fade_in(self)
	_initial_focus.call_deferred()


func _initial_focus() -> void:
	if open_on_selected:
		choose_button.grab_focus()
	else:
		for c: MaskCard in cards:
			if c.mask == current:
				c.grab_focus()
				return
	open_on_selected = false


func _build() -> void:
	var safe := MenuKit.safe_container(self)
	add_child(safe)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(root)

	# En-tête : retour + titre
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	back_button = MenuKit.button("‹  Retour", MenuKit.Style.GHOST, 22, Vector2(160, 56))
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var t := MenuKit.title("Choisis ton masque", 46)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	var hint := MenuKit.label("Chaque masque donne un pouvoir.", 18, MenuKit.TEXT_DIM, MenuKit.nunito(700), 4)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(hint)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(body)

	# Gauche : aperçu + détail + Choisir
	_detail_panel = PanelContainer.new()
	_detail_style = MenuKit.panel_style(Color(MenuKit.NIGHT, 0.9), MenuKit.BORDER, 22, 2, 16)
	_detail_panel.add_theme_stylebox_override("panel", _detail_style)
	_detail_panel.custom_minimum_size = Vector2(Balance.get_float("menu", "detail_width", 330.0), 0)
	body.add_child(_detail_panel)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", 4)
	_detail_panel.add_child(dcol)
	preview = HeroPreview.new()
	preview.custom_minimum_size = Vector2(0, Balance.get_float("menu", "preview_height", 230.0))
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dcol.add_child(preview)
	_name = MenuKit.title("", 34)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dcol.add_child(_name)
	_desc = MenuKit.label("", 16, MenuKit.TEXT_DIM, MenuKit.nunito(650))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.custom_minimum_size = Vector2(0, 66)
	dcol.add_child(_desc)
	_power = MenuKit.label("", 15, MenuKit.GOLD, MenuKit.nunito(800))
	_power.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dcol.add_child(_power)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	dcol.add_child(gap)
	choose_button = MenuKit.button("Choisir", MenuKit.Style.PRIMARY, 30, Vector2(0, 74))
	choose_button.pressed.connect(choose_current)
	dcol.add_child(choose_button)

	# Droite : cartes. Le viewport fait au moins 1280 px de large (stretch « expand ») :
	# les 5 cartes se partagent la largeur disponible, plafonnée par [menu] card_width.
	var right := CenterContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(right)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Balance.get_value("menu", "card_gap", 12)))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(row)
	_cards_row = row
	right.resized.connect(func() -> void: _fit_cards(right.size.x))
	for m: MaskData in masks:
		var c := MaskCard.new(m)
		c.pressed.connect(func() -> void:
			if current == m:
				choose_current()
			else:
				show_mask(m))
		c.focus_entered.connect(func() -> void: show_mask(m))
		row.add_child(c)
		cards.append(c)
	# Navigation : cartes ↔ Choisir ; boucle horizontale.
	for i: int in cards.size():
		var c: MaskCard = cards[i]
		c.focus_neighbor_left = c.get_path_to(cards[i - 1] if i > 0 else choose_button)
		c.focus_neighbor_right = c.get_path_to(cards[(i + 1) % cards.size()])
		c.focus_neighbor_top = c.get_path_to(back_button)
		c.focus_neighbor_bottom = c.get_path_to(choose_button)
	if not cards.is_empty():
		choose_button.focus_neighbor_right = choose_button.get_path_to(cards[0])
		choose_button.focus_neighbor_top = choose_button.get_path_to(cards[0])
		back_button.focus_neighbor_bottom = back_button.get_path_to(cards[0])


## Largeur des cartes : partage de la place disponible, plafonné par card_width.
func _fit_cards(avail: float) -> void:
	if cards.is_empty() or avail <= 0.0:
		return
	var gap: float = float(Balance.get_value("menu", "card_gap", 12))
	var max_w: float = Balance.get_float("menu", "card_width", 196.0)
	var w: float = floorf(minf(max_w, (avail - gap * (cards.size() - 1)) / cards.size()))
	for c: MaskCard in cards:
		c.custom_minimum_size.x = w
		c.size_flags_horizontal = Control.SIZE_FILL


## Affiche un masque (aperçu, détail, carte sélectionnée) sans le choisir.
func show_mask(m: MaskData, with_sound: bool = true) -> void:
	if m == null or m == current:
		return
	current = m
	for c: MaskCard in cards:
		c.set_selected(c.mask == m)
	preview.set_mask(m)
	_name.text = m.display_name
	_name.add_theme_color_override("font_color", m.aura_color.lerp(Color.WHITE, 0.55))
	_desc.text = m.description
	_power.text = "Pouvoir : " + m.power_name + "  (bientôt)" if not m.power_name.is_empty() else ""
	_detail_style.border_color = Color(m.aura_color, 0.75)
	_detail_style.shadow_color = Color(m.aura_color, 0.3)
	_background.set_glow_color(m.aura_color)
	_refresh_choose_label()
	if with_sound:
		MenuKit.sfx(&"click_soft", -4.0)


func _refresh_choose_label() -> void:
	var equipped: bool = current != null and current.id == GameState.selected_mask_id
	choose_button.text = "Partir avec ce masque" if equipped else "Choisir"
	choose_button.add_theme_font_size_override("font_size", 24 if equipped else 30)


func _refresh_equipped() -> void:
	for c: MaskCard in cards:
		c.set_equipped(c.mask.id == GameState.selected_mask_id)


## « Choisir » : équipe le masque affiché (sauvegardé) puis ouvre le choix de difficulté.
func choose_current() -> DifficultyPanel:
	if current == null:
		return null
	GameState.set_selected_mask(current.id)
	_refresh_equipped()
	_refresh_choose_label()
	MenuKit.sfx(&"confirm")
	MenuKit.vibrate(30)
	return open_difficulty()


func open_difficulty() -> DifficultyPanel:
	if is_instance_valid(difficulty_panel):
		return difficulty_panel
	difficulty_panel = DifficultyPanel.new(current.display_name if current != null else "")
	add_child(difficulty_panel)
	difficulty_panel.launch_requested.connect(launch_raid)
	difficulty_panel.closed.connect(func() -> void:
		if is_instance_valid(choose_button):
			choose_button.grab_focus())
	return difficulty_panel


func launch_raid() -> void:
	# Nouveau raid : nouvelle seed (le raid relit GameState.run_seed).
	GameState.run_seed = randi()
	MenuKit.go_to(self, raid_scene, Balance.get_float("menu", "fade_time", 0.3) * 1.5)


func go_back() -> void:
	MenuKit.sfx(&"back")
	MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not is_instance_valid(difficulty_panel):
		get_viewport().set_input_as_handled()
		go_back()
