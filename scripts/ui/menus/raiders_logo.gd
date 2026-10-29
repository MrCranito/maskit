class_name RaidersLogo
extends HBoxContainer
## Logo « RaidersGo » : emblème (viseur dont une flèche de sortie s'échappe) + « RAIDERS » en
## gros (Nunito Black incliné, gros contour, ombre rouge sombre) suivi de « GO » mis en valeur
## dans une étiquette rouge en forme de flèche, + slogan sur une bande inclinée.
## Même dessin que le logo de l'image de démarrage (art/blender/build_menu_2d.py).
## Tout est dessiné en code ; rien n'est redessiné à chaque frame.

const GAME_NAME := "RaidersGo"
const TITLE := "RAIDERS"
const GO := "GO"
const SLOGAN := "Tire. Pille. Tire-toi."

var emblem: RaidersEmblem = null
var title_label: Label = null
var go_label: Label = null
var go_tag: Control = null
var slogan_label: Label = null
var slogan_band: Control = null
var _title_size: int = 96

static var _slant_font: FontVariation = null


func _init(title_size: int = 96, with_emblem: bool = true, with_slogan: bool = true) -> void:
	_title_size = title_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if title_size < 0:
		return
	add_theme_constant_override("separation", int(title_size * 0.16))
	alignment = BoxContainer.ALIGNMENT_CENTER
	if with_emblem:
		emblem = RaidersEmblem.new()
		emblem.custom_minimum_size = Vector2(title_size * 1.25, title_size * 1.25)
		emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(emblem)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -int(title_size * 0.12))
	add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(title_size * 0.06))
	col.add_child(row)
	title_label = MenuKit.label(TITLE, title_size, MenuKit.TEXT, slant_font(), maxi(6, title_size / 7))
	title_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.09, 1.0))
	title_label.add_theme_color_override("font_shadow_color", Color(MenuKit.RED_DARK, 0.9))
	title_label.add_theme_constant_override("shadow_offset_x", maxi(3, title_size / 22))
	title_label.add_theme_constant_override("shadow_offset_y", maxi(4, title_size / 16))
	title_label.add_theme_constant_override("shadow_outline_size", maxi(6, title_size / 7))
	row.add_child(title_label)
	go_tag = GoTag.new()
	go_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(go_tag)
	go_label = MenuKit.label(GO, int(title_size * 0.78), MenuKit.TEXT, slant_font(), maxi(4, title_size / 10))
	go_label.add_theme_color_override("font_outline_color", Color(0.25, 0.0, 0.04, 1.0))
	go_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	go_tag.add_child(go_label)
	var gs: Vector2 = go_label.get_minimum_size()
	go_tag.custom_minimum_size = Vector2(gs.x + title_size * 0.62, title_size * 0.86)
	go_label.position = Vector2(title_size * 0.14, (title_size * 0.86 - gs.y) * 0.5)
	go_label.size = gs
	slogan_band = SloganBand.new()
	slogan_band.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	slogan_band.custom_minimum_size = Vector2(0, title_size * 0.42)
	slogan_band.visible = with_slogan
	col.add_child(slogan_band)
	slogan_label = MenuKit.label(SLOGAN, maxi(13, int(title_size * 0.27)), MenuKit.TEXT, MenuKit.nunito(900), 0)
	slogan_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slogan_band.add_child(slogan_label)
	slogan_label.position = Vector2(title_size * 0.32, 0)
	slogan_band.custom_minimum_size.x = slogan_label.get_minimum_size().x + title_size * 0.64
	slogan_label.size = Vector2(slogan_label.get_minimum_size().x, title_size * 0.42)


## Logotype plat de la direction « D » (lobby) : « RAIDERS » en Anton blanc, « GO » en violet
## clair, sans emblème, étiquette ni slogan.
static func wordmark(title_size: int) -> RaidersLogo:
	var l := RaidersLogo.new(-1)
	l._title_size = title_size
	l.add_theme_constant_override("separation", 0)
	l.title_label = MenuKit.label(TITLE, title_size, MenuKit.TEXT, MenuKit.display(), 0)
	l.add_child(l.title_label)
	l.go_label = MenuKit.label(GO, title_size, MenuKit.VIOLET_LIGHT, MenuKit.display(), 0)
	l.add_child(l.go_label)
	return l


## Nunito Black incliné (italique synthétique, effet de vitesse).
static func slant_font() -> FontVariation:
	if _slant_font != null:
		return _slant_font
	var fv := FontVariation.new()
	fv.base_font = MenuKit.NUNITO
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	fv.variation_opentype = {tag: 1000}
	fv.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.24, 1), Vector2.ZERO)
	fv.spacing_glyph = 1
	_slant_font = fv
	return fv


## Étiquette rouge en forme de flèche (pointe à droite) derrière « GO ».
class GoTag extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var h: float = size.y
		var k: float = h * 0.22
		var tip: float = h * 0.42
		var pts := PackedVector2Array([Vector2(k, 0), Vector2(size.x - tip, 0), Vector2(size.x, h * 0.5),
			Vector2(size.x - tip - k * 0.5, h), Vector2(0, h)])
		var shadow := PackedVector2Array()
		for p: Vector2 in pts:
			shadow.append(p + Vector2(h * 0.05, h * 0.08))
		draw_colored_polygon(shadow, Color(0.04, 0.03, 0.09, 0.9))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(0.04, 0.03, 0.09, 1.0), maxf(3.0, h * 0.09), true)
		draw_colored_polygon(pts, MenuKit.RED)
		draw_colored_polygon(PackedVector2Array([pts[0], pts[1], Vector2(size.x - tip * 0.7, h * 0.15),
			Vector2(k * 0.85, h * 0.15)]), Color(1, 0.55, 0.45, 0.45))


## Bande rouge inclinée (parallélogramme) derrière le slogan.
class SloganBand extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var h: float = size.y
		var k: float = h * 0.35
		var pts := PackedVector2Array([Vector2(k, 0), Vector2(size.x, 0), Vector2(size.x - k, h), Vector2(0, h)])
		var shadow := PackedVector2Array()
		for p: Vector2 in pts:
			shadow.append(p + Vector2(3, 4))
		draw_colored_polygon(shadow, Color(0.04, 0.03, 0.09, 0.85))
		draw_colored_polygon(pts, MenuKit.NIGHT_DEEP.lerp(MenuKit.RED_DARK, 0.35))
		draw_colored_polygon(PackedVector2Array([pts[0], pts[1], Vector2(size.x - k * 0.18, h * 0.18),
			Vector2(k * 0.82, h * 0.18)]), Color(1, 1, 1, 0.12))
