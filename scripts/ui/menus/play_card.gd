class_name PlayCard
extends Button
## Bouton d'action principal du lobby (direction « D ») : posé dans le bandeau violet, sans fond,
## un énorme « DÉPLOYER » en Anton aligné à droite, la carte en cours au-dessus (« Dust Creek ·
## Facile »). Survol : léger voile blanc à coins coupés ; focus : contour blanc. Mène au choix des
## cartes. Carte : GameState.current_map, sinon la rotation.
## STYLES / palette() / secondary_styles() restent pour les écrans qui reprennent l'ancienne forme.

const STYLES := {
	&"amber": {"base": Color(0.98, 0.72, 0.2), "deep": Color(0.62, 0.34, 0.05), "ink": Color(0.2, 0.1, 0.01),
		"glow": Color(1.0, 0.7, 0.25)},
	&"go": {"base": Color(0.62, 0.9, 0.24), "deep": Color(0.22, 0.48, 0.1), "ink": Color(0.06, 0.18, 0.04),
		"glow": Color(0.7, 1.0, 0.35)},
}
const RADIUS := 22
const DEPTH := 7

## Variante active (captures : changer avant de construire le menu).
static var style: StringName = &"go"

var card: MapCard = null
var title_label: Label = null
var map_label: Label = null
var arrow: MenuGlyph = null
var _content: Control = null
var _glint: ColorRect = null


static func palette() -> Dictionary:
	return STYLES.get(style, STYLES[&"amber"])


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(Balance.get_float("menu", "deploy_width", 210.0), 110)
	text = ""
	var normal := CutBox.make(Color(0, 0, 0, 0), 14.0)
	var hover := CutBox.make(Color(1, 1, 1, 0.1), 14.0)
	var pressed := CutBox.make(Color(0, 0, 0, 0.18), 14.0)
	var focus := CutBox.new()
	focus.draw_center = false
	focus.border_color = Color(MenuKit.TEXT, 0.45)
	focus.border_width = 1.5
	focus.cut = 14.0
	focus.grow = 2.0
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("hover_pressed", pressed)
	add_theme_stylebox_override("focus", focus)

	_content = VBoxContainer.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_right = -6
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_content as VBoxContainer).alignment = BoxContainer.ALIGNMENT_END
	(_content as VBoxContainer).add_theme_constant_override("separation", -6)
	add_child(_content)
	map_label = MenuKit.label("", 15, Color(MenuKit.TEXT, 0.9), MenuKit.nunito(600), 0)
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content.add_child(map_label)
	title_label = MenuKit.label("DÉPLOYER", 56, MenuKit.TEXT, MenuKit.display(), 0)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_content.add_child(title_label)
	arrow = MenuGlyph.new(&"play", MenuKit.TEXT, 30)
	arrow.visible = false
	add_child(arrow)
	button_down.connect(func() -> void: _content.position.y = 2)
	button_up.connect(func() -> void: _content.position.y = 0)


func _ready() -> void:
	MenuKit.add_feedback(self, 1.03)
	refresh()


## Carte affichée : celle choisie (GameState.current_map), sinon la première de la rotation.
static func displayed_card() -> MapCard:
	var c: MapCard = GameState.current_map as MapCard
	if c != null:
		return c
	var offered := MapRotation.offered_cards(MapRotation.now())
	for e: Dictionary in offered:
		if e.get("card") is MapCard:
			return e["card"] as MapCard
	return null


func refresh() -> void:
	card = displayed_card()
	map_label.text = ("%s · %s" % [card.display_name, card.difficulty_name()]) if card != null else "Choisir une carte"


## Styles du bouton secondaire assorti (Coop) : bleu nuit, liseré de la couleur d'action,
## même rayon et même profondeur. Renvoie {normal, hover, pressed, focus}.
static func secondary_styles() -> Dictionary:
	var p := palette()
	var n := StyleBoxFlat.new()
	n.bg_color = Color(MenuKit.NIGHT, 0.94)
	n.set_corner_radius_all(RADIUS)
	n.border_color = Color(p["base"] as Color, 0.75)
	n.set_border_width_all(2)
	n.border_width_bottom = DEPTH
	n.shadow_color = Color(0, 0, 0.05, 0.45)
	n.shadow_size = 10
	n.anti_aliasing = true
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.12, 0.17, 0.3, 0.97)
	var pr := n.duplicate() as StyleBoxFlat
	pr.bg_color = Color(0.05, 0.07, 0.13, 0.97)
	pr.border_width_bottom = 2
	pr.expand_margin_top = -(DEPTH - 2)
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = Color(MenuKit.TEXT, 0.55)
	f.set_border_width_all(2)
	f.set_corner_radius_all(RADIUS + 3)
	f.set_expand_margin_all(4)
	return {"normal": n, "hover": h, "pressed": pr, "focus": f}
