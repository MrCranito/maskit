class_name GemIcon
extends Control
## Gemme taillée : image peinte (CurrencyArt.gem) si elle existe, sinon dessinée en code
## (losange à facettes violet). Dessin statique : redessiné seulement au redimensionnement.

@export var tint: Color = MenuKit.GEM
## false : toujours le dessin en code (comparaisons, tests du repli).
@export var use_art: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # image 256 px affichée en 24-60 px
	resized.connect(queue_redraw)


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var tex := CurrencyArt.gem() if use_art else null
	if tex != null:
		# L'image garde une marge pour sa lueur : légèrement agrandie pour occuper la même place.
		var k: float = s * CurrencyArt.ICON_ZOOM
		CurrencyArt.draw_fit(self, tex, Rect2(size * 0.5 - Vector2(k, k) * 0.5, Vector2(k, k)))
		return
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var top_l: Vector2 = p.call(0.2, 0.3)
	var top_r: Vector2 = p.call(0.8, 0.3)
	var crown_l: Vector2 = p.call(0.33, 0.12)
	var crown_r: Vector2 = p.call(0.67, 0.12)
	var mid: Vector2 = p.call(0.5, 0.3)
	var tip: Vector2 = p.call(0.5, 0.92)
	var outline := PackedVector2Array([crown_l, crown_r, top_r, tip, top_l])
	draw_colored_polygon(outline, tint.darkened(0.35))
	# Facettes
	draw_colored_polygon(PackedVector2Array([crown_l, crown_r, mid]), tint.lightened(0.55))
	draw_colored_polygon(PackedVector2Array([crown_l, mid, top_l]), tint.lightened(0.25))
	draw_colored_polygon(PackedVector2Array([crown_r, top_r, mid]), tint)
	draw_colored_polygon(PackedVector2Array([top_l, mid, tip]), tint.lightened(0.1))
	draw_colored_polygon(PackedVector2Array([mid, top_r, tip]), tint.darkened(0.15))
	var closed := outline.duplicate()
	closed.append(crown_l)
	draw_polyline(closed, Color(0.03, 0.05, 0.12, 0.9), maxf(1.5, s * 0.06), true)
	draw_circle(p.call(0.4, 0.2), s * 0.04, Color(1, 1, 1, 0.9))
