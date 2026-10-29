class_name CutBox
extends StyleBox
## Boîte de la direction « D » : angles vifs, coins biseautés (haut-gauche et bas-droit par
## défaut), fond plein, bordure fine optionnelle, barre d'accent optionnelle à gauche.
## S'utilise partout où un StyleBox est attendu (panneaux, boutons, puces).

enum { CUT_TOP_LEFT = 1, CUT_TOP_RIGHT = 2, CUT_BOTTOM_RIGHT = 4, CUT_BOTTOM_LEFT = 8 }

@export var bg_color: Color = Color(0.024, 0.027, 0.05, 0.85)
@export var draw_center: bool = true
@export var border_color: Color = Color(0, 0, 0, 0)
@export var border_width: float = 0.0
## Taille du biseau (px).
@export var cut: float = 10.0
## Coins biseautés (combinaison des constantes CUT_*).
@export var corners: int = CUT_TOP_LEFT | CUT_BOTTOM_RIGHT
## Barre verticale à gauche (0 = aucune).
@export var accent_width: float = 0.0
@export var accent_color: Color = Color.WHITE
## Agrandit la zone dessinée au-delà du rect (contour de focus).
@export var grow: float = 0.0


static func make(bg: Color, cut_px: float = 10.0, border: Color = Color(0, 0, 0, 0), border_w: float = 0.0,
		margin_h: float = 14.0, margin_v: float = 8.0) -> CutBox:
	var b := CutBox.new()
	b.bg_color = bg
	b.cut = cut_px
	b.border_color = border
	b.border_width = border_w
	b.content_margin_left = margin_h
	b.content_margin_right = margin_h
	b.content_margin_top = margin_v
	b.content_margin_bottom = margin_v
	return b


func points(rect: Rect2) -> PackedVector2Array:
	var r := rect.grow(grow)
	var c := minf(cut, minf(r.size.x, r.size.y) * 0.5)
	var p := PackedVector2Array()
	var tl := r.position
	var br := r.end
	var tr := Vector2(br.x, tl.y)
	var bl := Vector2(tl.x, br.y)
	if corners & CUT_TOP_LEFT:
		p.append(tl + Vector2(0, c))
		p.append(tl + Vector2(c, 0))
	else:
		p.append(tl)
	if corners & CUT_TOP_RIGHT:
		p.append(tr - Vector2(c, 0))
		p.append(tr + Vector2(0, c))
	else:
		p.append(tr)
	if corners & CUT_BOTTOM_RIGHT:
		p.append(br - Vector2(0, c))
		p.append(br - Vector2(c, 0))
	else:
		p.append(br)
	if corners & CUT_BOTTOM_LEFT:
		p.append(bl + Vector2(c, 0))
		p.append(bl - Vector2(0, c))
	else:
		p.append(bl)
	return p


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 1.0 or rect.size.y <= 1.0:
		return
	var pts := points(rect)
	if draw_center and bg_color.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([bg_color]))
	if accent_width > 0.0 and accent_color.a > 0.0:
		var r := rect.grow(grow)
		var top := r.position.y + (cut if corners & CUT_TOP_LEFT else 0.0)
		var bottom := r.end.y - (cut if corners & CUT_BOTTOM_LEFT else 0.0)
		RenderingServer.canvas_item_add_rect(to_canvas_item,
			Rect2(r.position.x, top, accent_width, maxf(0.0, bottom - top)), accent_color)
	if border_width > 0.0 and border_color.a > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		RenderingServer.canvas_item_add_polyline(to_canvas_item, loop, PackedColorArray([border_color]), border_width, true)
