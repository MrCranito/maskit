class_name PassGlyph
extends MenuGlyph
## Pictogrammes supplémentaires (pass de combat, marchand, atelier, coop), même style que
## MenuGlyph (aplats + contour sombre) : ticket (pass), lock, check, cart (marchand),
## anvil (atelier), duo (coop), chest (inventaire). Les autres noms sont dessinés par MenuGlyph.


func _draw() -> void:
	var dark: Color = color.darkened(0.35)
	match kind:
		&"ticket":
			# ticket de saison : rectangle à encoches + étoile de shérif
			_poly([Vector2(0.06, 0.24), Vector2(0.94, 0.24), Vector2(0.94, 0.42), Vector2(0.86, 0.5),
				Vector2(0.94, 0.58), Vector2(0.94, 0.76), Vector2(0.06, 0.76), Vector2(0.06, 0.58),
				Vector2(0.14, 0.5), Vector2(0.06, 0.42)])
			var pts: Array = []
			for i: int in 10:
				var a: float = -PI / 2 + TAU * i / 10
				var r: float = 0.2 if i % 2 == 0 else 0.09
				pts.append(Vector2(0.5, 0.51) + Vector2(cos(a), sin(a)) * r)
			_poly(pts, MenuKit.NIGHT, false)
		&"lock":
			_arc(Vector2(0.5, 0.42), 0.2, PI, TAU, 0.1, dark)
			_line(Vector2(0.3, 0.42), Vector2(0.3, 0.5), 0.1, dark)
			_line(Vector2(0.7, 0.42), Vector2(0.7, 0.5), 0.1, dark)
			_poly([Vector2(0.18, 0.48), Vector2(0.82, 0.48), Vector2(0.82, 0.9), Vector2(0.18, 0.9)])
			_circle(Vector2(0.5, 0.66), 0.07, MenuKit.NIGHT, false)
		&"check":
			_line(Vector2(0.18, 0.52), Vector2(0.42, 0.76), 0.16)
			_line(Vector2(0.42, 0.76), Vector2(0.84, 0.26), 0.16)
		&"cart":
			# étal du marchand : auvent rayé + comptoir
			_poly([Vector2(0.08, 0.2), Vector2(0.92, 0.2), Vector2(0.86, 0.42), Vector2(0.14, 0.42)])
			for k: int in 3:
				var x0: float = 0.2 + 0.24 * k
				_poly([Vector2(x0, 0.2), Vector2(x0 + 0.12, 0.2), Vector2(x0 + 0.1, 0.42), Vector2(x0 - 0.02, 0.42)], MenuKit.RED, false)
			_poly([Vector2(0.18, 0.42), Vector2(0.82, 0.42), Vector2(0.82, 0.84), Vector2(0.18, 0.84)], dark)
			_circle(Vector2(0.5, 0.63), 0.11, Color(0.96, 0.74, 0.22))
		&"chest":
			# coffre (inventaire / réserve)
			_poly([Vector2(0.1, 0.42), Vector2(0.9, 0.42), Vector2(0.9, 0.88), Vector2(0.1, 0.88)])
			_poly([Vector2(0.1, 0.42), Vector2(0.16, 0.2), Vector2(0.84, 0.2), Vector2(0.9, 0.42)], dark)
			_line(Vector2(0.1, 0.52), Vector2(0.9, 0.52), 0.06, Color(0.62, 0.42, 0.24))
			_poly([Vector2(0.42, 0.44), Vector2(0.58, 0.44), Vector2(0.58, 0.64), Vector2(0.42, 0.64)], MenuKit.GOLD)
		&"anvil":
			# enclume + marteau (atelier)
			_poly([Vector2(0.06, 0.48), Vector2(0.78, 0.48), Vector2(0.94, 0.4), Vector2(0.94, 0.56),
				Vector2(0.66, 0.62), Vector2(0.62, 0.74), Vector2(0.76, 0.88), Vector2(0.26, 0.88),
				Vector2(0.4, 0.74), Vector2(0.36, 0.62), Vector2(0.14, 0.6)])
			_line(Vector2(0.36, 0.38), Vector2(0.7, 0.08), 0.08, Color(0.62, 0.42, 0.24))
			_poly([Vector2(0.18, 0.3), Vector2(0.36, 0.14), Vector2(0.48, 0.28), Vector2(0.3, 0.44)], dark)
		&"duo":
			# deux silhouettes (coop)
			_circle(Vector2(0.34, 0.3), 0.14, dark)
			_poly([Vector2(0.1, 0.84), Vector2(0.14, 0.58), Vector2(0.34, 0.48), Vector2(0.54, 0.58), Vector2(0.58, 0.84)], dark)
			_circle(Vector2(0.64, 0.34), 0.15)
			_poly([Vector2(0.38, 0.9), Vector2(0.42, 0.62), Vector2(0.64, 0.52), Vector2(0.86, 0.62), Vector2(0.9, 0.9)])
		_:
			super()
