extends DoorNode
## Porte coulissante à sas de la Station Orbitale (même logique que DoorNode : collision,
## ouverture au contact, verrou par clef). Seul le dessin change :
## - porte dans un mur horizontal (face 3/4 visible) : deux vantaux métalliques à bande
##   jaune et noire qui glissent dans les montants, linteau avec voyant (rouge fermé, vert
##   ouvert, ambre pulsé + cadenas si verrouillée) ;
## - porte dans un mur vertical (vue de dessus) : deux demi-lames qui rentrent dans le mur.
## Sas verrouillé (super_loot) : bandes rouges et noires, vantaux plus sombres.

const OUT := Color(0.05, 0.06, 0.1)
const FRAME := Color(0.27, 0.3, 0.38)
const FRAME_LIGHT := Color(0.58, 0.66, 0.78)
const CAP := Color(0.2, 0.22, 0.3)
const PANEL := Color(0.52, 0.57, 0.66)
const PANEL_DARK := Color(0.34, 0.37, 0.45)
const VAULT_PANEL := Color(0.3, 0.32, 0.4)
const HAZ_Y := Color(0.93, 0.73, 0.16)
const HAZ_R := Color(0.86, 0.18, 0.14)
const HAZ_K := Color(0.1, 0.1, 0.13)
const LED_RED := Color(1.0, 0.22, 0.16)
const LED_GREEN := Color(0.35, 1.0, 0.5)
const LED_AMBER := Color(1.0, 0.7, 0.2)
const VOID_DARK := Color(0.03, 0.04, 0.08, 0.9)


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


func _hazard(r: Rect2, stripe: Color, step: float = 10.0) -> void:
	draw_rect(r, HAZ_K)
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var pts := PackedVector2Array()
		for p: Vector2 in [Vector2(x, r.end.y), Vector2(x + step * 0.5, r.end.y), Vector2(x + step * 0.5 + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)]:
			pts.append(Vector2(clampf(p.x, r.position.x, r.end.x), p.y))
		draw_colored_polygon(pts, stripe)
		x += step


func _draw_h(t: float) -> void:
	var h := wall_height
	var half := TS * 0.5
	var locked := is_locked() or kind == KIND_VAULT
	# Linteau (dessus du mur) + voyant.
	var cap := Rect2(-half, -TS, TS, TS - h)
	draw_rect(cap, CAP)
	draw_rect(Rect2(cap.position, Vector2(TS, 2.0)), FRAME_LIGHT)
	draw_rect(cap, OUT, false, 1.5)
	var led := _led_color()
	draw_circle(Vector2(0.0, -TS + (TS - h) * 0.5), 3.4, OUT)
	draw_circle(Vector2(0.0, -TS + (TS - h) * 0.5), 2.4, led)
	# Ouverture : noir bleuté (le couloir derrière) visible quand les vantaux s'écartent.
	var opening := Rect2(-half + 7.0, -h + 6.0, TS - 14.0, h - 6.0)
	draw_rect(opening, VOID_DARK)
	# Vantaux : chacun glisse vers son montant.
	var leaf_w := opening.size.x * 0.5 * (1.0 - t)
	if leaf_w > 0.5:
		var col := VAULT_PANEL if locked else PANEL
		var stripe := HAZ_R if locked else HAZ_Y
		var left := Rect2(opening.position.x, opening.position.y, leaf_w, opening.size.y)
		var right := Rect2(opening.end.x - leaf_w, opening.position.y, leaf_w, opening.size.y)
		for r: Rect2 in [left, right]:
			draw_rect(r, col)
			draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)), col.lightened(0.25))
			draw_rect(Rect2(r.position.x, r.end.y - 6.0, r.size.x, 6.0), col.darkened(0.35))
			_hazard(Rect2(r.position.x, r.position.y + r.size.y * 0.42, r.size.x, 8.0), stripe)
			draw_rect(r, OUT, false, 1.2)
		# Joint central lumineux + fenêtres hublot.
		draw_line(Vector2(left.end.x, left.position.y), Vector2(left.end.x, left.end.y), OUT, 2.0)
		if t < 0.05:
			for cx: float in [left.end.x - 9.0, right.position.x + 9.0]:
				draw_rect(Rect2(cx - 4.0, opening.position.y + 7.0, 8.0, 10.0), Color(0.25, 0.65, 0.85))
				draw_rect(Rect2(cx - 4.0, opening.position.y + 7.0, 8.0, 10.0), OUT, false, 1.2)
	# Montants (vantaux escamotés dedans) et cadre.
	for jx: float in [-half, half - 7.0]:
		draw_rect(Rect2(jx, -h, 7.0, h), FRAME)
		draw_line(Vector2(jx + 1.0, -h), Vector2(jx + 1.0, 0.0), FRAME_LIGHT, 1.5)
	draw_rect(Rect2(-half, -h, TS, 6.0), FRAME)
	draw_rect(Rect2(-half, -h, TS, h), OUT, false, 2.0)
	draw_rect(opening, OUT, false, 1.5)
	# Seuil à bandes au sol.
	_hazard(Rect2(-half + 7.0, -4.0, TS - 14.0, 4.0), HAZ_R if locked else HAZ_Y, 8.0)
	if is_locked():
		_draw_padlock(Vector2(0.0, -h * 0.5))


func _draw_v(t: float) -> void:
	var top := -TS + 3.0
	var length := TS - 6.0
	var locked := is_locked() or kind == KIND_VAULT
	# Rail au sol (fente) et montants.
	draw_rect(Rect2(-7.0, top, 14.0, length), VOID_DARK)
	var leaf := length * 0.5 * (1.0 - t)
	if leaf > 0.5:
		var col := VAULT_PANEL if locked else PANEL
		var stripe := HAZ_R if locked else HAZ_Y
		for r: Rect2 in [Rect2(-6.0, top, 12.0, leaf), Rect2(-6.0, top + length - leaf, 12.0, leaf)]:
			draw_rect(Rect2(r.position + Vector2(2, 3), r.size), Color(0.02, 0.03, 0.1, 0.45))
			draw_rect(r, col)
			draw_rect(Rect2(r.position.x, r.position.y, 3.0, r.size.y), col.lightened(0.3))
			draw_rect(Rect2(r.end.x - 3.0, r.position.y, 3.0, r.size.y), col.darkened(0.3))
			draw_rect(r, OUT, false, 1.4)
		var mid := top + length * 0.5
		if leaf > 6.0:
			_hazard(Rect2(-6.0, mid - minf(leaf, 10.0), 12.0, minf(leaf, 10.0) * 2.0 * (1.0 - t)), stripe, 8.0)
	for y: float in [-TS, -6.0]:
		draw_rect(Rect2(-10.0, y, 20.0, 6.0), FRAME)
		draw_rect(Rect2(-10.0, y, 20.0, 6.0), OUT, false, 1.4)
	var led := _led_color()
	draw_circle(Vector2(8.0, -TS + 3.0), 3.0, OUT)
	draw_circle(Vector2(8.0, -TS + 3.0), 2.0, led)
	if is_locked():
		_draw_padlock(Vector2(0.0, -TS * 0.5))
