extends DoorNode
## Porte des temples égyptiens (même comportement que DoorNode, autre dessin) :
##   stone  : dalle de grès à deux battants gravés de hiéroglyphes (chambres) ;
##   bronze : porte de bronze à cartouche doré (sanctuaire) ;
##   sealed : dalle scellée du trésor (sceau de cire rouge, œil d'Horus) — verrouillée.

const KIND_STONE := &"stone"
const KIND_BRONZE := &"bronze"
const KIND_SEALED := &"sealed"

const C_OUT := Color(0.18, 0.1, 0.06)
const C_FRAME := Color(0.58, 0.42, 0.26)
const C_FRAME_LIGHT := Color(0.9, 0.72, 0.46)
const C_STONE := Color(0.72, 0.56, 0.36)
const C_STONE_DARK := Color(0.46, 0.32, 0.2)
const C_BRONZE := Color(0.62, 0.42, 0.2)
const C_GOLD := Color(1.0, 0.82, 0.36)
const C_SEAL := Color(0.7, 0.14, 0.1)
const C_DARK := Color(0.12, 0.07, 0.05, 0.9)


func _draw() -> void:
	var t := 1.0 - pow(1.0 - _open_t, 3.0)
	if vertical:
		_eg_vertical(t)
	else:
		_eg_horizontal(t)


func _eg_horizontal(t: float) -> void:
	var h := wall_height
	var half := TS * 0.5
	var cap := Rect2(-half, -TS, TS, TS - h)
	draw_rect(cap, C_STONE_DARK)
	draw_line(cap.position + Vector2(0, 1), Vector2(cap.end.x, cap.position.y + 1), C_FRAME_LIGHT.darkened(0.2), 2.0)
	draw_rect(cap, C_OUT, false, 1.5)
	var op := Rect2(-half + 6.0, -h + 7.0, TS - 12.0, h - 7.0)
	draw_rect(op, Color(C_DARK, C_DARK.a * (1.0 - t * 0.5)))
	match kind:
		KIND_BRONZE:
			_leaves(op, t, C_BRONZE, true)
		KIND_SEALED:
			_slab(op, t)
		_:
			_leaves(op, t, C_STONE, false)
	# Chambranle : montants en grès clair, linteau gravé.
	draw_rect(Rect2(-half, -h, 6.0, h), C_FRAME)
	draw_rect(Rect2(half - 6.0, -h, 6.0, h), C_FRAME)
	draw_rect(Rect2(-half, -h, TS, 7.0), C_FRAME)
	for i: int in 5:
		var x := -half + 8.0 + float(i) * 11.0
		draw_rect(Rect2(x, -h + 2.0, 4.0, 3.0), C_OUT)
	draw_line(Vector2(-half + 1.0, -h), Vector2(-half + 1.0, 0.0), C_FRAME_LIGHT, 2.0)
	draw_rect(Rect2(-half, -h, TS, h), C_OUT, false, 2.0)
	if is_locked():
		_seal(Vector2(0.0, -h * 0.5))


## Deux battants qui pivotent vers l'intérieur (vus en 3/4).
func _leaves(op: Rect2, t: float, col: Color, gilded: bool) -> void:
	var w := op.size.x * 0.5
	var ang := t * deg_to_rad(80.0)
	for side: float in [-1.0, 1.0]:
		var a := Vector2(op.get_center().x + side * w, 0.0)
		var dir := Vector2(-side * cos(ang), -sin(ang)) * w
		var b := a + dir
		var up := Vector2(0.0, op.size.y - 1.0)
		var poly := PackedVector2Array([a, b, b - up, a - up])
		var facing := absf(dir.normalized().x)
		var c := col.lerp(col.darkened(0.35), 1.0 - facing)
		if facing > 0.05:
			draw_colored_polygon(poly, c)
			# Bandes gravées / cartouches.
			for k: int in 3:
				var f := 0.2 + float(k) * 0.3
				var p := a.lerp(b, f) - up * 0.15
				var q := a.lerp(b, f) - up * 0.85
				draw_line(p, q, c.darkened(0.3), 2.0)
				if gilded:
					draw_circle(a.lerp(b, f) - up * 0.5, 3.0, C_GOLD)
			draw_polyline(PackedVector2Array([a, b, b - up, a - up, a]), C_OUT, 1.6)
		draw_line(a - up, b - up, C_OUT, 5.0)
		draw_line(a - up, b - up, c.lightened(0.25), 2.5)
		draw_line(b, b - up, C_OUT, 4.0)


## Dalle scellée : glisse vers le haut (dans le linteau) à l'ouverture.
func _slab(op: Rect2, t: float) -> void:
	var vis := 1.0 - t
	if vis <= 0.01:
		return
	var r := Rect2(op.position.x, op.end.y - op.size.y * vis, op.size.x, op.size.y * vis)
	draw_rect(r, C_STONE)
	for k: int in 3:
		var yy := r.position.y + 6.0 + float(k) * (r.size.y - 12.0) / 2.0
		draw_line(Vector2(r.position.x + 3.0, yy), Vector2(r.end.x - 3.0, yy), C_STONE_DARK, 1.5)
	# Œil d'Horus.
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.45)
	if r.size.y > 20.0:
		draw_arc(c, 8.0, PI * 1.1, PI * 1.9, 10, C_OUT, 3.0)
		draw_circle(c, 3.5, C_OUT)
		draw_circle(c, 2.0, C_GOLD)
	draw_rect(r, C_OUT, false, 1.5)


func _seal(p: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_time * 3.0)
	draw_circle(p, 15.0 + pulse * 3.0, Color(1.0, 0.5, 0.2, 0.16 + 0.12 * pulse))
	draw_circle(p, 8.0, C_OUT)
	draw_circle(p, 6.5, C_SEAL)
	draw_circle(p, 3.0, C_GOLD)
	draw_line(p + Vector2(-4, 4), p + Vector2(4, -4), C_OUT, 1.5)


func _eg_vertical(t: float) -> void:
	var top := -TS + 4.0
	var length := TS - 8.0
	draw_rect(Rect2(-9.0, -TS, 18.0, TS), Color(C_STONE_DARK, 0.75))
	match kind:
		KIND_SEALED:
			var vis := 1.0 - t
			if vis > 0.02:
				draw_rect(Rect2(-6.0, top, 12.0, length * vis), C_STONE)
				var y := top
				while y < top + length * vis - 1.0:
					draw_line(Vector2(-6.0, y), Vector2(6.0, y), C_STONE_DARK, 1.0)
					y += 6.0
				draw_rect(Rect2(-6.0, top, 12.0, length * vis), C_OUT, false, 1.5)
		_:
			var ang := t * deg_to_rad(85.0)
			var hl := length * 0.5
			var col := C_BRONZE if kind == KIND_BRONZE else C_STONE
			_draw_slab(Vector2(0.0, top), Vector2(sin(ang), cos(ang)) * hl, col, 9.0)
			_draw_slab(Vector2(0.0, -4.0), Vector2(sin(ang), -cos(ang)) * hl, col, 9.0)
	for y2: float in [-TS + 2.0, -2.0]:
		draw_rect(Rect2(-11.0, y2 - 5.0, 22.0, 10.0), C_FRAME)
		draw_rect(Rect2(-11.0, y2 - 5.0, 22.0, 10.0), C_OUT, false, 1.5)
	if is_locked():
		_seal(Vector2(0.0, -TS * 0.5))
