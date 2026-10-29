class_name PlayCard
extends Button
## Grand bouton « JOUER » du lobby (bas droite) : bouton d'action principal net, sans vignette
## de carte ni rouge. Gros « JOUER » incliné + flèche, une ligne discrète en dessous
## (« Dust Creek · Facile »). Fond lumineux (variante `style`) avec reflet haut, lueur douce,
## reflet qui passe de temps en temps ; à l'appui le contenu s'enfonce (bordure basse épaisse
## → fine). Mène au choix des cartes. Carte : GameState.current_map, sinon la rotation.
## Le bouton Coop du lobby reprend la même forme en version secondaire (secondary_styles()).

## Variantes de couleur : « go » (vert-jaune lumineux, retenue : ressort le mieux sur le camp au
## coucher du soleil, distinct de l'or des monnaies) ou « amber » (or/ambre chaud).
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
	custom_minimum_size = Vector2(340, 124)
	text = ""
	var p := palette()
	var base: Color = p["base"]
	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.set_corner_radius_all(RADIUS)
	normal.border_color = (p["deep"] as Color)
	normal.border_width_bottom = DEPTH
	normal.shadow_color = Color(p["glow"] as Color, 0.4)
	normal.shadow_size = 16
	normal.anti_aliasing = true
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = base.lightened(0.08)
	hover.shadow_color = Color(p["glow"] as Color, 0.55)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = base.darkened(0.06)
	pressed.border_width_bottom = 2
	pressed.expand_margin_top = -(DEPTH - 2)   # le bouton s'enfonce
	pressed.shadow_size = 8
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(MenuKit.TEXT, 0.55)
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(RADIUS + 3)
	focus.set_expand_margin_all(4)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("hover_pressed", pressed)
	add_theme_stylebox_override("focus", focus)
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	# reflet haut (verre) : dégradé blanc → transparent sur la moitié haute
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.38))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 32
	var sheen := TextureRect.new()
	sheen.name = "Sheen"
	sheen.texture = gt
	sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sheen.stretch_mode = TextureRect.STRETCH_SCALE
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.anchor_right = 1.0
	sheen.anchor_bottom = 0.5
	add_child(sheen)

	_content = VBoxContainer.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_bottom = -DEPTH
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(_content as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_content as VBoxContainer).add_theme_constant_override("separation", -4)
	add_child(_content)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 12)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(top)
	var ink: Color = p["ink"]
	title_label = MenuKit.label("JOUER", 52, ink, RaidersLogo.slant_font(), 0)
	title_label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	title_label.add_theme_constant_override("shadow_offset_y", 2)
	title_label.add_theme_constant_override("shadow_offset_x", 0)
	top.add_child(title_label)
	arrow = MenuGlyph.new(&"play", ink, 30)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(arrow)
	map_label = MenuKit.label("", 16, Color(ink, 0.72), MenuKit.nunito(900), 0)
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content.add_child(map_label)

	# reflet qui balaie le bouton de temps en temps (doux)
	_glint = ColorRect.new()
	_glint.color = Color(1, 1, 1, 0.22)
	_glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glint.size = Vector2(38, custom_minimum_size.y * 1.8)
	_glint.rotation = 0.42
	_glint.position = Vector2(-120, -40)
	add_child(_glint)
	button_down.connect(func() -> void: _content.position.y = DEPTH - 2)
	button_up.connect(func() -> void: _content.position.y = 0)


func _ready() -> void:
	MenuKit.add_feedback(self, 1.03)
	refresh()
	var tw := create_tween().set_loops()
	tw.tween_interval(Balance.get_float("menu", "play_glint_interval", 4.5))
	tw.tween_property(_glint, "position:x", custom_minimum_size.x + 80.0, 0.8).from(-120.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
