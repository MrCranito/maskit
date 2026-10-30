extends DoorNode
## Porte blindée des bunkers des Terres gelées (même logique que DoorNode : collision,
## ouverture au contact, verrou par clef). Seul le dessin change :
## - porte dans un mur horizontal (face 3/4 visible) : vantail d'acier gris-vert givré qui
##   pivote (ouvert = vu de côté, sombre), encadrement de béton, voyant (rouge fermé, vert
##   ouvert, ambre pulsé + cadenas si verrouillée), bande rouge et blanche pour les scellées ;
## - porte dans un mur vertical (vue de dessus) : battant qui se rabat contre le mur.

const OUT := Color(0.05, 0.06, 0.1)
const CONCRETE := Color(0.5, 0.54, 0.6)
const CONCRETE_LIGHT := Color(0.74, 0.78, 0.84)
const CAP := Color(0.62, 0.68, 0.76)
const STEEL := Color(0.4, 0.46, 0.46)
const STEEL_DARK := Color(0.26, 0.3, 0.32)
const VAULT := Color(0.32, 0.34, 0.4)
const STRIPE_R := Color(0.85, 0.18, 0.14)
const STRIPE_W := Color(0.9, 0.92, 0.95)
const LED_RED := Color(1.0, 0.22, 0.16)
const LED_GREEN := Color(0.35, 1.0, 0.5)
const LED_AMBER := Color(1.0, 0.7, 0.2)
const DARK := Color(0.03, 0.04, 0.08, 0.9)
const FROST := Color(0.8, 0.92, 1.0, 0.35)


func _draw() -> void:
	var t := 1.0 - pow(1.0 - get_open_progress(), 3.0)
	if vertical:
		_draw_v(t)
	else:
		_draw_h(t)


func _led_color() -> Color:
	if is_locked():
		var pulse := 0.5 + 0.5 * sin(_anim_time * 4.0)
		return LED_AMBER.lerp(LED_RED, pulse * 0.5)
	return LED_GREEN if is_open() else LED_RED


func _stripes(r: Rect2) -> void:
	draw_rect(r, STRIPE_W)
	var x := r.position.x - r.size.y
	var step := 10.0
	while x < r.end.x:
		var pts := PackedVector2Array()
		for p: Vector2 in [Vector2(x, r.end.y), Vector2(x + step * 0.5, r.end.y), Vector2(x + step * 0.5 + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)]:
			pts.append(Vector2(clampf(p.x, r.position.x, r.end.x), p.y))
		draw_colored_polygon(pts, STRIPE_R)
		x += step


func _draw_h(t: float) -> void:
	var h := wall_height
	var half := TS * 0.5
	var locked := is_locked() or kind == KIND_VAULT
	# Dessus du mur (béton enneigé) + voyant.
	var cap := Rect2(-half, -TS, TS, TS - h)
	draw_rect(cap, CAP)
	draw_rect(Rect2(cap.position, Vector2(TS, 2.5)), CONCRETE_LIGHT)
	draw_rect(cap, OUT, false, 1.5)
	var led := _led_color()
	draw_circle(Vector2(0.0, -TS + (TS - h) * 0.5), 3.4, OUT)
	draw_circle(Vector2(0.0, -TS + (TS - h) * 0.5), 2.4, led)
	# Ouverture sombre.
	var opening := Rect2(-half + 8.0, -h + 7.0, TS - 16.0, h - 7.0)
	draw_rect(opening, DARK)
	# Vantail : pivote vers l'intérieur (se rétrécit en largeur, s'assombrit).
	var leaf_w := opening.size.x * (1.0 - t * 0.85)
	if leaf_w > 1.0:
		var col := VAULT if locked else STEEL
		col = col.darkened(t * 0.5)
		var leaf := Rect2(opening.position.x, opening.position.y, leaf_w, opening.size.y)
		draw_rect(leaf, col)
		draw_rect(Rect2(leaf.position, Vector2(leaf.size.x, 3.0)), col.lightened(0.25))
		draw_rect(Rect2(leaf.position.x, leaf.end.y - 5.0, leaf.size.x, 5.0), col.darkened(0.35))
		# Renforts horizontaux et hublot.
		for k: int in 2:
			var yy := leaf.position.y + leaf.size.y * (0.35 + 0.3 * k)
			draw_rect(Rect2(leaf.position.x + 2.0, yy, leaf.size.x - 4.0, 2.5), col.darkened(0.3))
		if t < 0.3:
			draw_rect(Rect2(leaf.get_center().x - 5.0, leaf.position.y + 8.0, 10.0, 8.0), Color(0.3, 0.6, 0.8))
			draw_rect(Rect2(leaf.get_center().x - 5.0, leaf.position.y + 8.0, 10.0, 8.0), OUT, false, 1.2)
		if locked:
			_stripes(Rect2(leaf.position.x + 2.0, leaf.position.y + leaf.size.y * 0.55, leaf.size.x - 4.0, 7.0))
		draw_rect(leaf, OUT, false, 1.2)
	# Encadrement de béton.
	for jx: float in [-half, half - 8.0]:
		draw_rect(Rect2(jx, -h, 8.0, h), CONCRETE)
		draw_line(Vector2(jx + 1.0, -h), Vector2(jx + 1.0, 0.0), CONCRETE_LIGHT, 1.5)
	draw_rect(Rect2(-half, -h, TS, 7.0), CONCRETE)
	draw_rect(Rect2(-half, -h, TS, 2.0), FROST)
	draw_rect(Rect2(-half, -h, TS, h), OUT, false, 2.0)
	draw_rect(opening, OUT, false, 1.5)
	if is_locked():
		_draw_padlock(Vector2(0.0, -h * 0.5))


func _draw_v(t: float) -> void:
	var top := -TS + 3.0
	var length := TS - 6.0
	var locked := is_locked() or kind == KIND_VAULT
	draw_rect(Rect2(-7.0, top, 14.0, length), DARK)
	# Battant qui se rabat (vue de dessus) : rotation autour du gond nord.
	var col := VAULT if locked else STEEL
	var ang := t * PI * 0.5
	var p0 := Vector2(0.0, top + 2.0)
	var p1 := p0 + Vector2(sin(ang), cos(ang)) * (length - 4.0)
	var n := Vector2(cos(ang), -sin(ang)) * 5.0
	var pts := PackedVector2Array([p0 - n, p0 + n, p1 + n, p1 - n])
	draw_colored_polygon(PackedVector2Array([p0 - n + Vector2(2, 3), p0 + n + Vector2(2, 3), p1 + n + Vector2(2, 3), p1 - n + Vector2(2, 3)]), Color(0.02, 0.03, 0.1, 0.45))
	draw_colored_polygon(pts, col)
	draw_polyline(PackedVector2Array([p0 - n, p0 + n, p1 + n, p1 - n, p0 - n]), OUT, 1.4)
	if locked and t < 0.5:
		draw_line(p0 + (p1 - p0) * 0.4, p0 + (p1 - p0) * 0.6, STRIPE_R, 4.0)
	for y: float in [-TS, -6.0]:
		draw_rect(Rect2(-10.0, y, 20.0, 6.0), CONCRETE)
		draw_rect(Rect2(-10.0, y, 20.0, 6.0), OUT, false, 1.4)
	var led := _led_color()
	draw_circle(Vector2(8.0, -TS + 3.0), 3.0, OUT)
	draw_circle(Vector2(8.0, -TS + 3.0), 2.0, led)
	if is_locked():
		_draw_padlock(Vector2(0.0, -TS * 0.5))
