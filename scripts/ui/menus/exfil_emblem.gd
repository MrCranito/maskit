class_name ExfilEmblem
extends Control
## Emblème d'Exfil Rush : un viseur (anneau + graduations) dont une flèche de sortie
## s'échappe vers le haut à droite en brisant l'anneau. Dessin statique (redessiné au
## redimensionnement seulement). `arrow_progress` (0..1) sert à l'animation du splash.

@export var ring_color: Color = MenuKit.TEXT
@export var arrow_color: Color = MenuKit.RED
var arrow_progress: float = 1.0:
	set(v):
		arrow_progress = clampf(v, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	resized.connect(func() -> void: pivot_offset = size * 0.5)


func _draw() -> void:
	var s: float = minf(size.x, size.y)
	var c: Vector2 = size * 0.5
	var r: float = s * 0.36
	var w: float = maxf(3.0, s * 0.075)
	var dark := Color(0.04, 0.03, 0.09, 0.95)
	# Anneau ouvert en haut à droite (là où sort la flèche)
	var gap_from: float = -PI * 0.42
	var gap_to: float = -PI * 0.08
	var a0: float = gap_to
	var a1: float = gap_from + TAU
	draw_arc(c, r, a0, a1, 48, dark, w + s * 0.05, true)
	draw_arc(c, r, a0, a1, 48, ring_color, w, true)
	# Graduations du viseur (gauche, bas, haut) + point central
	for ang: float in [PI, PI * 0.5, -PI * 0.5]:
		var d := Vector2.from_angle(ang)
		var p0: Vector2 = c + d * (r - s * 0.16)
		var p1: Vector2 = c + d * (r + s * 0.12)
		draw_line(p0, p1, dark, w * 0.75 + s * 0.04, true)
		draw_line(p0, p1, ring_color, w * 0.75, true)
	draw_circle(c, s * 0.055, dark)
	draw_circle(c, s * 0.035, ring_color)
	# Flèche de sortie : du centre vers l'extérieur, à travers l'ouverture
	if arrow_progress <= 0.0:
		return
	var dir := Vector2.from_angle(-PI * 0.25)
	var start: Vector2 = c + dir * s * 0.02
	var full_end: Vector2 = c + dir * s * 0.5
	var end: Vector2 = start.lerp(full_end, arrow_progress)
	var head: float = s * 0.2
	var shaft_end: Vector2 = end - dir * head * 0.6
	var n := Vector2(-dir.y, dir.x)
	var aw: float = s * 0.085
	var shaft := PackedVector2Array([start + n * aw * 0.5, shaft_end + n * aw * 0.5,
		shaft_end - n * aw * 0.5, start - n * aw * 0.5])
	var tip := PackedVector2Array([end, shaft_end + n * head * 0.62 - dir * head * 0.15,
		shaft_end - n * head * 0.62 - dir * head * 0.15])
	for poly: PackedVector2Array in [shaft, tip]:
		var o := PackedVector2Array()
		for p: Vector2 in poly:
			o.append(p + Vector2(s * 0.02, s * 0.03))
		draw_colored_polygon(o, dark)
	draw_colored_polygon(shaft, arrow_color)
	draw_colored_polygon(tip, arrow_color.lightened(0.12))
