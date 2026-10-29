class_name EcoItemTile
extends Button
## Case d'objet des écrans Marchand / Atelier : même dessin que l'inventaire de raid
## (InventoryStyle.draw_item_tile : fond bleu nuit, bordure et liseré de rareté, lueur Épique et
## Légendaire, quantité « ×N ») + une légende sous la case (prix, « 2/3 »…).
## Dessin statique : redessiné seulement quand l'objet, la quantité, la sélection ou la taille changent.

var item: ItemData = null
var count: int = 0
var caption: String = ""
var caption_color: Color = InventoryStyle.GOLD
var selected: bool = false
## Petit marqueur « matériau d'artisanat » (coin haut gauche).
var craft_mark: bool = false
var dimmed: bool = false

var _font: Font = null


func _init(p_item: ItemData = null, p_count: int = 0, p_caption: String = "") -> void:
	item = p_item
	count = p_count
	caption = p_caption


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	if custom_minimum_size == Vector2.ZERO:
		var side: float = Balance.get_float("economy", "tile_size", 92.0)
		custom_minimum_size = Vector2(side, side + (22.0 if not caption.is_empty() else 0.0))
	var empty := StyleBoxEmpty.new()
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(st, empty)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MenuKit.GOLD
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(14)
	focus.set_expand_margin_all(3)
	add_theme_stylebox_override("focus", focus)
	_font = LootVisuals.text_font(800)
	resized.connect(queue_redraw)
	MenuKit.add_feedback(self, 1.05)
	tooltip_text = item.display_name if item != null else ""


func set_data(p_item: ItemData, p_count: int, p_caption: String = caption) -> void:
	item = p_item
	count = p_count
	caption = p_caption
	tooltip_text = item.display_name if item != null else ""
	queue_redraw()


func set_selected(on: bool) -> void:
	if selected != on:
		selected = on
		queue_redraw()


func _draw() -> void:
	var side: float = minf(size.x, size.y - (22.0 if not caption.is_empty() else 0.0))
	var r := Rect2(Vector2((size.x - side) * 0.5, 0.0), Vector2(side, side))
	InventoryStyle.draw_item_tile(self, r, item, count, selected, _font)
	if dimmed:
		var veil := StyleBoxFlat.new()
		veil.bg_color = Color(0.02, 0.03, 0.08, 0.55)
		veil.set_corner_radius_all(12)
		draw_style_box(veil, r)
	if craft_mark:
		# Pastille « atelier » : petit marteau stylisé.
		var c := r.position + Vector2(13, 13)
		draw_circle(c, 9.0, Color(0.04, 0.06, 0.11, 0.9), true, -1.0, true)
		draw_arc(c, 9.0, 0.0, TAU, 18, Color(MenuKit.GOLD, 0.9), 1.5, true)
		draw_line(c + Vector2(-4, 4), c + Vector2(2, -2), MenuKit.GOLD, 2.2, true)
		draw_rect(Rect2(c + Vector2(0, -6), Vector2(6, 4)), MenuKit.GOLD)
	if not caption.is_empty():
		var fs := 15 if side >= 70.0 else 13
		var w := _font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2((size.x - w) * 0.5, side + 17.0)
		draw_string_outline(_font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, InventoryStyle.NIGHT_BLUE_DEEP)
		draw_string(_font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, caption_color)
