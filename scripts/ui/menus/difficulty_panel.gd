class_name DifficultyPanel
extends ModalPanel
## Choix de la difficulté (Facile → Cauchemar) puis « Partir en raid ».
## La valeur est écrite dans GameState.difficulty (sauvegardée) ; le raid la lit.

signal launch_requested

const COLORS: Array[Color] = [
	Color(0.36, 0.78, 0.42),
	Color(0.36, 0.62, 0.95),
	Color(0.96, 0.66, 0.22),
	Color(0.92, 0.3, 0.2),
	Color(0.62, 0.22, 0.85),
]
const DESCRIPTIONS: Array[String] = [
	"Peu d'ennemis, idéal pour découvrir la ville.",
	"L'expérience prévue : prudence et butin correct.",
	"Plus d'ennemis, mieux armés. Butin plus rare.",
	"Gardes nombreux et féroces. Butin rare fréquent.",
	"La ville ne pardonne rien. Butin légendaire.",
]

var difficulty_buttons: Array[Button] = []
var launch_button: Button = null
var _desc: Label = null
var _mask_name: String = ""


func _init(mask_name: String = "") -> void:
	super._init("Difficulté", Vector2(900, 470))
	_mask_name = mask_name


func _build_body() -> void:
	close_button.text = "Retour"
	if not _mask_name.is_empty():
		var who := MenuKit.label("Masque : " + _mask_name, 20, MenuKit.TEXT_DIM, MenuKit.nunito(800))
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(who)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var group := ButtonGroup.new()
	for i: int in GameState.DIFFICULTY_NAMES.size():
		var b := _difficulty_button(i, group)
		row.add_child(b)
		difficulty_buttons.append(b)
	_desc = MenuKit.label("", 20, MenuKit.TEXT, MenuKit.nunito(700))
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.custom_minimum_size = Vector2(0, 30)
	body.add_child(_desc)
	launch_button = MenuKit.button("Partir en raid", MenuKit.Style.PRIMARY, 32, Vector2(380, 84))
	launch_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	launch_button.pressed.connect(func() -> void:
		MenuKit.sfx(&"confirm_big")
		MenuKit.vibrate(40)
		launch_requested.emit())
	body.add_child(launch_button)
	# Navigation : boutons de difficulté ↔ « Partir » ↔ « Retour »
	for b: Button in difficulty_buttons:
		b.focus_neighbor_bottom = b.get_path_to(launch_button)
	launch_button.focus_neighbor_bottom = launch_button.get_path_to(close_button)
	close_button.focus_neighbor_top = close_button.get_path_to(launch_button)
	set_difficulty(GameState.difficulty, false)


func _difficulty_button(i: int, group: ButtonGroup) -> Button:
	var c: Color = COLORS[i]
	var b := MenuKit.button(GameState.DIFFICULTY_NAMES[i], MenuKit.Style.SECONDARY, 21, Vector2(150, 70))
	b.toggle_mode = true
	b.button_group = group
	var on := MenuKit.panel_style(c.darkened(0.35), c.lightened(0.3), 16, 3, 10)
	on.shadow_color = Color(c, 0.5)
	on.shadow_size = 12
	on.shadow_offset = Vector2.ZERO
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", MenuKit.TEXT)
	# Pastilles d'intensité (1 à 5 crânes stylisés : points)
	b.text = GameState.DIFFICULTY_NAMES[i] + "\n" + "●".repeat(i + 1)
	b.add_theme_constant_override("line_spacing", -4)
	b.toggled.connect(func(pressed: bool) -> void:
		if pressed:
			set_difficulty(i))
	b.focus_entered.connect(func() -> void: _show_desc(i))
	return b


## Sélectionne une difficulté (0..4) et met à jour GameState.
func set_difficulty(i: int, with_sound: bool = true) -> void:
	var v: int = clampi(i, 0, difficulty_buttons.size() - 1)
	GameState.set_difficulty(v)
	if not difficulty_buttons[v].button_pressed:
		difficulty_buttons[v].set_pressed_no_signal(true)
	_show_desc(v)
	if with_sound:
		MenuKit.sfx(&"tick")


func _show_desc(i: int) -> void:
	_desc.text = DESCRIPTIONS[clampi(i, 0, DESCRIPTIONS.size() - 1)]
	_desc.add_theme_color_override("font_color", COLORS[i].lightened(0.35))


func _focus_first() -> void:
	if is_inside_tree() and not difficulty_buttons.is_empty():
		launch_button.grab_focus()
