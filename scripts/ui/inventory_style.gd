class_name InventoryStyle
extends RefCounted
## Charte graphique partagée de l'inventaire, de la fenêtre de butin et des boutons
## (DA : panneaux bleu nuit ~#121a2e aux coins arrondis, bordure fine claire,
## titres Rye blancs/or, texte Nunito, couleurs de rareté).

const NIGHT_BLUE := Color(0.071, 0.102, 0.18, 0.97)
const NIGHT_BLUE_DEEP := Color(0.04, 0.06, 0.11, 1.0)
const NIGHT_BLUE_LIGHT := Color(0.12, 0.16, 0.26, 1.0)
const BORDER_LIGHT := Color(0.85, 0.88, 0.95, 0.85)
const GOLD := Color(0.95, 0.76, 0.38)
const TEXT := Color(0.96, 0.96, 0.98)
const TEXT_SECONDARY := Color(0.74, 0.77, 0.84)
const DANGER := Color(0.86, 0.3, 0.26)
const DIM := Color(0.02, 0.03, 0.07, 0.62)


static func panel(radius: int = 18, margin: int = 16, bg: Color = NIGHT_BLUE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = BORDER_LIGHT
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


static func inset(radius: int = 12, margin: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = NIGHT_BLUE_DEEP
	s.border_color = Color(BORDER_LIGHT, 0.18)
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


## Bouton arrondi : fond `color` (or : texte bleu nuit ; sinon texte blanc).
static func button(text: String, color: Color, font_size: int = 18, min_size: Vector2 = Vector2(0, 52)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", LootVisuals.text_font(800))
	b.add_theme_font_size_override("font_size", font_size)
	var dark_text := color.get_luminance() > 0.55
	var fg := NIGHT_BLUE_DEEP if dark_text else TEXT
	for st: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(st, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.4))
	b.add_theme_stylebox_override("normal", _btn_box(color))
	b.add_theme_stylebox_override("hover", _btn_box(color.lightened(0.1)))
	b.add_theme_stylebox_override("pressed", _btn_box(color.darkened(0.18)))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(color.darkened(0.5), 0.6)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


static func _btn_box(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.border_color = c.lightened(0.35)
	s.set_border_width_all(1)
	s.border_width_bottom = 3
	s.set_corner_radius_all(12)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.anti_aliasing = true
	return s


static func label(text: String, size: int, color: Color = TEXT, weight: int = 600, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.label_settings = LootVisuals.label_settings(LootVisuals.text_font(weight), size, color, outline)
	return l


static func title(text: String, size: int, color: Color = GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LootVisuals.label_settings(LootVisuals.title_font(), size, color, 0)
	ls.shadow_color = Color(0, 0, 0, 0.5)
	ls.shadow_offset = Vector2(0, 2)
	ls.shadow_size = 1
	l.label_settings = ls
	return l


## Case d'icône (dessin) : fond sombre, bordure de rareté, lueur Épique/Légendaire.
static func draw_item_tile(ci: CanvasItem, rect: Rect2, item: ItemData, count: int, selected: bool, font: Font) -> void:
	var rc := LootDB.rarity_color(item.rarity) if item != null else Color(BORDER_LIGHT, 0.2)
	if item != null and item.rarity >= ItemData.Rarity.EPIC:
		for k in 3:
			var g := StyleBoxFlat.new()
			g.bg_color = Color(rc, 0.10 + 0.05 * k)
			g.set_corner_radius_all(14 + (3 - k) * 2)
			g.anti_aliasing = true
			ci.draw_style_box(g, rect.grow(float(3 - k) * 2.0))
	var bg := StyleBoxFlat.new()
	bg.bg_color = NIGHT_BLUE_DEEP if item == null else NIGHT_BLUE_DEEP.lerp(rc, 0.13)
	bg.border_color = GOLD if selected else (rc if item != null else Color(BORDER_LIGHT, 0.16))
	bg.set_border_width_all(3 if selected else (2 if item != null else 1))
	bg.set_corner_radius_all(12)
	bg.anti_aliasing = true
	ci.draw_style_box(bg, rect)
	if item == null:
		return
	# Liseré de rareté en bas de la case.
	var strip := StyleBoxFlat.new()
	strip.bg_color = Color(rc, 0.85)
	strip.corner_radius_bottom_left = 10
	strip.corner_radius_bottom_right = 10
	ci.draw_style_box(strip, Rect2(rect.position + Vector2(3, rect.size.y - 8), Vector2(rect.size.x - 6, 5)))
	var tex := LootVisuals.icon(item.icon)
	if tex != null:
		var pad := rect.size.x * 0.17
		ci.draw_texture_rect(tex, Rect2(rect.position + Vector2(pad, pad * 0.8), rect.size - Vector2(pad, pad) * 2.0), false, item.tint)
	if count > 1:
		var txt := "×%d" % count
		var fs := int(rect.size.y * 0.2)
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := rect.end - Vector2(w + 8.0, 12.0)
		ci.draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, NIGHT_BLUE_DEEP)
		ci.draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TEXT)
