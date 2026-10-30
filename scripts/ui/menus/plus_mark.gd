class_name PlusMark
extends Control
## Gros « + » plein (deux barres à angles vifs, ombre portée encre) : emplacement de coéquipier
## (menu principal, salon coop). Remplit son rect ; épaisseur = `thickness` × côté.

var color: Color = MenuKit.TEXT
var thickness: float = 0.2


func _init(p_color: Color = MenuKit.TEXT) -> void:
	color = p_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var t := s * thickness
	var o := (size - Vector2(s, s)) * 0.5
	var sh := Vector2(0, maxf(2.0, s * 0.04))
	for pass_i: int in 2:
		var c := Color(0.0, 0.0, 0.03, 0.6) if pass_i == 0 else color
		var d := sh if pass_i == 0 else Vector2.ZERO
		draw_rect(Rect2(o + Vector2((s - t) * 0.5, 0) + d, Vector2(t, s)), c)
		draw_rect(Rect2(o + Vector2(0, (s - t) * 0.5) + d, Vector2(s, t)), c)
