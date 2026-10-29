class_name MenuGlyph
extends Control
## Pictogrammes du lobby dessinés en code (aplats + contour sombre, lisibles à 24–40 px) :
## rifle (arsenal), helmet (personnages), bag (boutique), gear (options), star (crédits),
## plus, coin, target (raids), exit (extractions), percent, clock, bulb, flag, play, chevron.
## Dessin statique : redessiné seulement au redimensionnement ou au changement de couleur.

@export var kind: StringName = &"star"
@export var color: Color = MenuKit.TEXT:
	set(v):
		color = v
		queue_redraw()

const INK := Color(0.04, 0.03, 0.09, 0.9)


func _init(p_kind: StringName = &"star", p_color: Color = MenuKit.TEXT, px: float = 32.0) -> void:
	kind = p_kind
	color = p_color
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)


## Point de la boîte normalisée (0..1) → pixels (glyphe carré centré).
func _p(x: float, y: float) -> Vector2:
	var s: float = minf(size.x, size.y)
	return (size - Vector2(s, s)) * 0.5 + Vector2(x, y) * s


func _poly(pts: Array, col: Color = color, outline: bool = true) -> void:
	var pv := PackedVector2Array()
	for q: Vector2 in pts:
		pv.append(_p(q.x, q.y))
	if outline:
		var closed := pv.duplicate()
		closed.append(pv[0])
		draw_polyline(closed, INK, maxf(2.0, minf(size.x, size.y) * 0.09), true)
	draw_colored_polygon(pv, col)


func _circle(c: Vector2, r: float, col: Color = color, outline: bool = true) -> void:
	var s: float = minf(size.x, size.y)
	if outline:
		draw_circle(_p(c.x, c.y), r * s + maxf(1.0, s * 0.045), INK)
	draw_circle(_p(c.x, c.y), r * s, col)


func _line(a: Vector2, b: Vector2, w: float, col: Color = color) -> void:
	var s: float = minf(size.x, size.y)
	draw_line(_p(a.x, a.y), _p(b.x, b.y), INK, w * s + maxf(2.0, s * 0.09), true)
	draw_line(_p(a.x, a.y), _p(b.x, b.y), col, w * s, true)


func _arc(c: Vector2, r: float, a0: float, a1: float, w: float, col: Color = color) -> void:
	var s: float = minf(size.x, size.y)
	draw_arc(_p(c.x, c.y), r * s, a0, a1, 32, INK, w * s + maxf(2.0, s * 0.09), true)
	draw_arc(_p(c.x, c.y), r * s, a0, a1, 32, col, w * s, true)


func _draw() -> void:
	var dark: Color = color.darkened(0.35)
	match kind:
		&"rifle":
			_poly([Vector2(0.04, 0.42), Vector2(0.22, 0.38), Vector2(0.24, 0.5), Vector2(0.08, 0.6)], dark)
			_poly([Vector2(0.2, 0.36), Vector2(0.72, 0.36), Vector2(0.72, 0.5), Vector2(0.2, 0.5)])
			_poly([Vector2(0.7, 0.4), Vector2(0.97, 0.4), Vector2(0.97, 0.46), Vector2(0.7, 0.46)], dark)
			_poly([Vector2(0.4, 0.48), Vector2(0.5, 0.48), Vector2(0.47, 0.74), Vector2(0.37, 0.72)], dark)
			_poly([Vector2(0.26, 0.48), Vector2(0.34, 0.48), Vector2(0.32, 0.64), Vector2(0.24, 0.62)])
			_poly([Vector2(0.36, 0.28), Vector2(0.56, 0.28), Vector2(0.56, 0.36), Vector2(0.36, 0.36)], dark)
		&"helmet":
			_poly([Vector2(0.14, 0.62), Vector2(0.16, 0.4), Vector2(0.3, 0.2), Vector2(0.5, 0.14), Vector2(0.7, 0.2),
				Vector2(0.84, 0.4), Vector2(0.86, 0.62)])
			_poly([Vector2(0.2, 0.5), Vector2(0.8, 0.5), Vector2(0.76, 0.64), Vector2(0.24, 0.64)], MenuKit.GOLD)
			_poly([Vector2(0.28, 0.64), Vector2(0.72, 0.64), Vector2(0.66, 0.86), Vector2(0.34, 0.86)], dark)
			_circle(Vector2(0.15, 0.56), 0.08, dark)
			_circle(Vector2(0.85, 0.56), 0.08, dark)
		&"bag":
			_arc(Vector2(0.5, 0.36), 0.16, PI, TAU, 0.07)
			_poly([Vector2(0.16, 0.36), Vector2(0.84, 0.36), Vector2(0.9, 0.88), Vector2(0.1, 0.88)])
			_poly([Vector2(0.16, 0.36), Vector2(0.84, 0.36), Vector2(0.86, 0.5), Vector2(0.14, 0.5)], dark, false)
			_circle(Vector2(0.5, 0.64), 0.07, MenuKit.GOLD, false)
		&"gear":
			var n: int = 8
			var pts: Array = []
			for i: int in n * 2:
				var a: float = TAU * i / (n * 2) + PI / (n * 2)
				var r: float = 0.44 if i % 2 == 0 else 0.33
				pts.append(Vector2(0.5, 0.5) + Vector2(cos(a), sin(a)) * r)
			_poly(pts)
			_circle(Vector2(0.5, 0.5), 0.14, MenuKit.NIGHT, false)
		&"star":
			var pts: Array = []
			for i: int in 10:
				var a: float = -PI / 2 + TAU * i / 10
				var r: float = 0.46 if i % 2 == 0 else 0.2
				pts.append(Vector2(0.5, 0.54) + Vector2(cos(a), sin(a)) * r)
			_poly(pts)
		&"plus":
			_line(Vector2(0.5, 0.2), Vector2(0.5, 0.8), 0.16)
			_line(Vector2(0.2, 0.5), Vector2(0.8, 0.5), 0.16)
		&"coin":
			_circle(Vector2(0.5, 0.5), 0.4, Color(0.96, 0.74, 0.22))
			_circle(Vector2(0.5, 0.5), 0.28, Color(0.86, 0.58, 0.12), false)
			_line(Vector2(0.5, 0.3), Vector2(0.5, 0.7), 0.08, Color(1, 0.92, 0.6))
		&"target":
			_arc(Vector2(0.5, 0.5), 0.32, 0.0, TAU, 0.1)
			_line(Vector2(0.5, 0.04), Vector2(0.5, 0.26), 0.1)
			_line(Vector2(0.5, 0.74), Vector2(0.5, 0.96), 0.1)
			_line(Vector2(0.04, 0.5), Vector2(0.26, 0.5), 0.1)
			_line(Vector2(0.74, 0.5), Vector2(0.96, 0.5), 0.1)
			_circle(Vector2(0.5, 0.5), 0.07, MenuKit.RED)
		&"exit":
			_arc(Vector2(0.44, 0.56), 0.3, -PI * 0.08, PI * 1.58 + PI * 0.08, 0.1)
			_line(Vector2(0.48, 0.52), Vector2(0.84, 0.16), 0.12, MenuKit.RED)
			_poly([Vector2(0.94, 0.06), Vector2(0.9, 0.38), Vector2(0.62, 0.1)], MenuKit.RED)
		&"percent":
			_circle(Vector2(0.28, 0.28), 0.13)
			_circle(Vector2(0.72, 0.72), 0.13)
			_line(Vector2(0.8, 0.18), Vector2(0.2, 0.82), 0.1)
		&"clock":
			_circle(Vector2(0.5, 0.5), 0.42)
			_circle(Vector2(0.5, 0.5), 0.32, MenuKit.NIGHT, false)
			_line(Vector2(0.5, 0.5), Vector2(0.5, 0.28), 0.08)
			_line(Vector2(0.5, 0.5), Vector2(0.66, 0.6), 0.08)
		&"bulb":
			_circle(Vector2(0.5, 0.4), 0.28)
			_poly([Vector2(0.36, 0.62), Vector2(0.64, 0.62), Vector2(0.6, 0.82), Vector2(0.4, 0.82)], dark)
			_line(Vector2(0.42, 0.9), Vector2(0.58, 0.9), 0.06, dark)
		&"flag":
			_line(Vector2(0.2, 0.08), Vector2(0.2, 0.94), 0.08, MenuKit.TEXT_DIM)
			_poly([Vector2(0.24, 0.12), Vector2(0.86, 0.2), Vector2(0.74, 0.36), Vector2(0.88, 0.52), Vector2(0.24, 0.5)])
		&"play":
			_poly([Vector2(0.24, 0.12), Vector2(0.9, 0.5), Vector2(0.24, 0.88)])
		&"chevron":
			_line(Vector2(0.36, 0.2), Vector2(0.66, 0.5), 0.12)
			_line(Vector2(0.66, 0.5), Vector2(0.36, 0.8), 0.12)
		_:
			_circle(Vector2(0.5, 0.5), 0.3)
