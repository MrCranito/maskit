class_name ExfilLogo
extends HBoxContainer
## Logo « Exfil Rush » : emblème (viseur dont la flèche de sortie s'échappe) + titre
## penché (Nunito Black incliné, gros contour) + slogan sur une bande rouge inclinée.
## Tout est dessiné en code ; rien n'est redessiné à chaque frame.

const TITLE := "EXFIL RUSH"
const SLOGAN := "Tire. Pille. Tire-toi."

var emblem: ExfilEmblem = null
var title_label: Label = null
var slogan_label: Label = null
var slogan_band: Control = null
var _title_size: int = 96

static var _slant_font: FontVariation = null


func _init(title_size: int = 96, with_emblem: bool = true) -> void:
	_title_size = title_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(title_size * 0.18))
	alignment = BoxContainer.ALIGNMENT_CENTER
	if with_emblem:
		emblem = ExfilEmblem.new()
		emblem.custom_minimum_size = Vector2(title_size * 1.25, title_size * 1.25)
		emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(emblem)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -int(title_size * 0.12))
	add_child(col)
	title_label = MenuKit.label(TITLE, title_size, MenuKit.TEXT, slant_font(), maxi(6, title_size / 7))
	title_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.09, 1.0))
	title_label.add_theme_color_override("font_shadow_color", Color(MenuKit.RED_DARK, 0.9))
	title_label.add_theme_constant_override("shadow_offset_x", maxi(3, title_size / 22))
	title_label.add_theme_constant_override("shadow_offset_y", maxi(4, title_size / 16))
	title_label.add_theme_constant_override("shadow_outline_size", maxi(6, title_size / 7))
	col.add_child(title_label)
	slogan_band = SloganBand.new()
	slogan_band.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	slogan_band.custom_minimum_size = Vector2(0, title_size * 0.42)
	col.add_child(slogan_band)
	slogan_label = MenuKit.label(SLOGAN, maxi(16, int(title_size * 0.27)), MenuKit.TEXT, MenuKit.nunito(900), 0)
	slogan_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slogan_band.add_child(slogan_label)
	slogan_label.position = Vector2(title_size * 0.32, 0)
	slogan_band.custom_minimum_size.x = slogan_label.get_minimum_size().x + title_size * 0.64
	slogan_label.size = Vector2(slogan_label.get_minimum_size().x, title_size * 0.42)


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
		draw_colored_polygon(pts, MenuKit.RED)
		draw_colored_polygon(PackedVector2Array([pts[0], pts[1], Vector2(size.x - k * 0.18, h * 0.18),
			Vector2(k * 0.82, h * 0.18)]), Color(1, 0.55, 0.45, 0.45))
