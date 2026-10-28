class_name UnderwaterDoor
extends DoorNode
## Sas étanche de la station sous-marine : porte ronde à volant dans un cadre d'acier riveté.
## Même comportement que DoorNode (collision, ouverture au contact, verrou, message) ;
## seul le dessin change. Verrouillée : bandes de danger, voyant rouge et cadenas.
## Ouverture : le battant rond pivote sur sa charnière gauche (ellipse qui s'écrase).

const KIND_HATCH := &"hatch"
const COL_STEEL := Color(0.42, 0.5, 0.56)
const COL_STEEL_D := Color(0.22, 0.27, 0.33)
const COL_STEEL_L := Color(0.72, 0.8, 0.84)
const COL_HATCH := Color(0.36, 0.52, 0.56)
const COL_HATCH_L := Color(0.6, 0.78, 0.8)
const COL_WHEEL := Color(0.78, 0.22, 0.16)
const COL_WHEEL_L := Color(1.0, 0.5, 0.36)
const COL_HAZ := Color(0.92, 0.72, 0.16)
const COL_HOLE := Color(0.02, 0.05, 0.09, 0.95)
const COL_LIGHT_OK := Color(0.4, 1.0, 0.6)
const COL_LIGHT_LOCK := Color(1.0, 0.22, 0.16)


func _draw() -> void:
	var t := 1.0 - pow(1.0 - _open_t, 3.0)
	if vertical:
		_draw_vertical_hatch(t)
	else:
		_draw_front_hatch(t)


## Porte dans un mur horizontal : vue de face (3/4).
func _draw_front_hatch(t: float) -> void:
	var h := wall_height
	var half := TS * 0.5
	# Linteau (dessus du mur au-dessus du sas).
	var cap := Rect2(-half, -TS, TS, TS - h)
	draw_rect(cap, COL_STEEL_D)
	draw_rect(Rect2(cap.position + Vector2(0, 2), Vector2(TS, 3)), COL_STEEL_L.darkened(0.2))
	draw_rect(cap, COL_OUTLINE, false, 1.5)
	# Cadre riveté.
	var frame := Rect2(-half, -h, TS, h)
	draw_rect(frame, COL_STEEL)
	draw_rect(Rect2(frame.position, Vector2(TS, 3)), COL_STEEL_L)
	if is_locked():
		# Bandes de danger sur le cadre.
		var x := -half
		var k := 0
		while x < half:
			draw_rect(Rect2(x, -h, minf(8.0, half - x), 5.0), COL_HAZ if k % 2 == 0 else COL_OUTLINE)
			draw_rect(Rect2(x, -6.0, minf(8.0, half - x), 6.0), COL_HAZ if k % 2 == 1 else COL_OUTLINE)
			x += 8.0
			k += 1
	var c := Vector2(0.0, -h * 0.5 + 1.0)
	var r := minf(h * 0.42, 22.0)
	for a: int in 8:
		var ang := float(a) * TAU / 8.0
		var p := c + Vector2(cos(ang), sin(ang)) * (r + 5.0)
		draw_circle(p, 1.8, COL_STEEL_D)
		draw_circle(p - Vector2(0.5, 0.5), 0.9, COL_STEEL_L)
	# Ouverture ronde sombre.
	draw_circle(c, r + 1.5, COL_OUTLINE)
	draw_circle(c, r, COL_HOLE)
	# Battant : disque qui pivote sur la charnière gauche.
	var squash := 1.0 - t * 0.88
	var hinge_x := c.x - r
	draw_set_transform(Vector2(hinge_x + r * squash, c.y), 0.0, Vector2(squash, 1.0))
	var lit := 1.0 - t * 0.5
	draw_circle(Vector2.ZERO, r + 1.5, COL_OUTLINE)
	draw_circle(Vector2.ZERO, r, COL_HATCH * lit)
	draw_arc(Vector2.ZERO, r - 3.0, PI * 1.05, PI * 1.7, 12, COL_HATCH_L * lit, 2.5)
	# Volant à rayons.
	var wr := r * 0.55
	draw_arc(Vector2.ZERO, wr, 0.0, TAU, 20, COL_OUTLINE, 5.0)
	draw_arc(Vector2.ZERO, wr, 0.0, TAU, 20, COL_WHEEL * lit, 3.0)
	for s: int in 4:
		var ang2 := float(s) * PI / 4.0 + _anim_spin()
		var d := Vector2(cos(ang2), sin(ang2)) * wr
		draw_line(-d, d, COL_OUTLINE, 4.0)
		draw_line(-d, d, COL_WHEEL_L * lit, 2.0)
	draw_circle(Vector2.ZERO, 3.5, COL_STEEL_D)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Charnières et voyant.
	for yy: float in [c.y - r * 0.6, c.y + r * 0.6]:
		draw_rect(Rect2(hinge_x - 5.0, yy - 3.0, 7.0, 6.0), COL_STEEL_D)
	var lamp := Vector2(half - 8.0, -h + 10.0)
	var lc := COL_LIGHT_LOCK if is_locked() else (COL_LIGHT_OK if t > 0.5 else COL_HAZ)
	draw_circle(lamp, 6.0, Color(lc, 0.25))
	draw_circle(lamp, 3.0, lc)
	draw_rect(frame, COL_OUTLINE, false, 2.0)
	if is_locked():
		_draw_padlock(Vector2(0.0, -h * 0.5))


func _anim_spin() -> float:
	return _open_t * PI * 0.5


## Porte dans un mur vertical : vue de dessus, cloison épaisse qui pivote, volant au milieu.
func _draw_vertical_hatch(t: float) -> void:
	var top := -TS + 4.0
	var length := TS - 8.0
	draw_rect(Rect2(-11.0, -TS, 22.0, TS), Color(COL_STEEL_D, 0.85))
	if is_locked():
		var y := -TS
		var k := 0
		while y < 0.0:
			draw_rect(Rect2(-11.0, y, 22.0, minf(8.0, -y)), Color(COL_HAZ if k % 2 == 0 else COL_OUTLINE, 0.9))
			y += 8.0
			k += 1
	var ang := t * deg_to_rad(95.0)
	var dir := Vector2(sin(ang), cos(ang)) * length
	var a := Vector2(0.0, top)
	var b := a + dir
	draw_line(a + Vector2(0, 4), b + Vector2(0, 4), Color(0.02, 0.04, 0.1, 0.5), 15.0)
	draw_line(a, b, COL_OUTLINE, 15.0)
	draw_line(a, b, COL_HATCH, 11.0)
	draw_line(a + Vector2(-3, 0), b + Vector2(-3, 0), COL_HATCH_L, 2.0)
	var mid := a.lerp(b, 0.5)
	draw_circle(mid, 8.0, COL_OUTLINE)
	draw_circle(mid, 6.5, COL_WHEEL)
	draw_circle(mid, 2.5, COL_STEEL_D)
	for y2: float in [-TS + 2.0, -2.0]:
		draw_rect(Rect2(-13.0, y2 - 5.0, 26.0, 10.0), COL_STEEL)
		draw_rect(Rect2(-13.0, y2 - 5.0, 26.0, 10.0), COL_OUTLINE, false, 1.5)
	if is_locked():
		_draw_padlock(Vector2(0.0, -TS * 0.5))
