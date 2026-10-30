extends DoorNode
## Porte du Carnaval hanté (même comportement que DoorNode, autre dessin) :
##   curtain : rideau de toile rayée (stands, tentes, chapiteau) qui se relève ;
##   caravan : porte de roulotte en bois peint, petite fenêtre ronde ;
##   gate    : grille de fer forgé (sorties de secours, kiosques) ;
##   sealed  : porte de la roulotte du Directeur, cadenassée de chaînes.
## Verrouillée : cadenas doré et chaînes (au lieu du cadenas standard).

const KIND_CURTAIN := &"curtain"
const KIND_CARAVAN := &"caravan"
const KIND_GATE := &"gate"
const KIND_SEALED := &"sealed"

const C_OUT := Color(0.08, 0.05, 0.1)
const C_FRAME := Color(0.34, 0.24, 0.3)
const C_FRAME_LIGHT := Color(0.72, 0.58, 0.62)
const C_RED := Color(0.74, 0.14, 0.18)
const C_WHITE := Color(0.9, 0.84, 0.8)
const C_WOOD := Color(0.5, 0.3, 0.26)
const C_WOOD_DARK := Color(0.3, 0.17, 0.16)
const C_IRON := Color(0.3, 0.3, 0.38)
const C_GOLD := Color(1.0, 0.78, 0.3)
const C_GLASS := Color(0.5, 0.35, 0.7, 0.7)

## Couleur d'accent (toile, lampe) choisie par le constructeur.
var accent: Color = Color(0.74, 0.14, 0.18)


func _draw() -> void:
	var t := 1.0 - pow(1.0 - _open_t, 3.0)
	if vertical:
		_hc_vertical(t)
	else:
		_hc_horizontal(t)


func _hc_horizontal(t: float) -> void:
	var h := wall_height
	var half := TS * 0.5
	var cap := Rect2(-half, -TS, TS, TS - h)
	draw_rect(cap, Color(0.22, 0.16, 0.26))
	draw_rect(cap, C_OUT, false, 1.5)
	var op := Rect2(-half + 5.0, -h + 6.0, TS - 10.0, h - 6.0)
	draw_rect(op, Color(0.06, 0.04, 0.1, 0.85 * (1.0 - t * 0.6)))
	match kind:
		KIND_CURTAIN:
			_curtain(op, t)
		KIND_CARAVAN:
			_caravan(op, t)
		KIND_GATE:
			_gate(op, t)
		_:
			_sealed(op, t)
	draw_rect(Rect2(-half, -h, 5.0, h), C_FRAME)
	draw_rect(Rect2(half - 5.0, -h, 5.0, h), C_FRAME)
	draw_rect(Rect2(-half, -h, TS, 6.0), C_FRAME)
	draw_line(Vector2(-half + 1.0, -h), Vector2(-half + 1.0, 0.0), C_FRAME_LIGHT, 2.0)
	draw_rect(Rect2(-half, -h, TS, h), C_OUT, false, 2.0)
	if is_locked():
		_padlock(Vector2(0.0, -h * 0.45))


func _curtain(op: Rect2, t: float) -> void:
	# Toile rayée rouge / blanc qui se relève (reste une frise festonnée en haut).
	var vis := 1.0 - t
	var y1 := op.position.y + op.size.y * vis
	var x := op.position.x
	var i := 0
	while x < op.end.x - 0.5:
		var w := minf(8.0, op.end.x - x)
		draw_rect(Rect2(x, op.position.y, w, maxf(y1 - op.position.y, 0.0)), accent if i % 2 == 0 else C_WHITE)
		x += 8.0
		i += 1
	if vis > 0.1:
		draw_line(Vector2(op.position.x, y1), Vector2(op.end.x, y1), C_OUT, 2.0)
	# Frise festonnée.
	var k := 0
	var fx := op.position.x
	while fx < op.end.x:
		draw_circle(Vector2(fx + 4.0, op.position.y + 2.0), 4.5, accent if k % 2 == 0 else C_WHITE)
		fx += 8.0
		k += 1
	draw_rect(Rect2(op.position.x - 2.0, op.position.y - 4.0, op.size.x + 4.0, 5.0), C_WOOD_DARK)
	draw_rect(Rect2(op.position.x - 2.0, op.position.y - 4.0, op.size.x + 4.0, 5.0), C_OUT, false, 1.2)


func _caravan(op: Rect2, t: float) -> void:
	var ang := t * deg_to_rad(95.0)
	_draw_leaf(Vector2(op.position.x, -3.0), Vector2(cos(ang), -sin(ang)) * op.size.x, op.size.y - 3.0, C_WOOD, false)
	if t < 0.3:
		var c := Vector2(op.get_center().x, op.position.y + op.size.y * 0.35)
		draw_circle(c, 7.0, C_OUT)
		draw_circle(c, 5.5, C_GLASS)
		draw_line(Vector2(op.position.x + 4.0, op.end.y - 10.0), Vector2(op.end.x - 4.0, op.end.y - 10.0), C_GOLD, 2.0)


func _gate(op: Rect2, t: float) -> void:
	var ang := t * deg_to_rad(95.0)
	var dir := Vector2(cos(ang), -sin(ang))
	var L := op.size.x
	var a := Vector2(op.position.x, -3.0)
	for k in 6:
		var p := a + dir * (L * (float(k) + 0.5) / 6.0)
		draw_line(p, p + Vector2(0, -(op.size.y - 4.0)), C_IRON, 2.5)
	draw_line(a, a + dir * L, C_IRON, 3.0)
	draw_line(a + Vector2(0, -(op.size.y - 4.0)), a + dir * L + Vector2(0, -(op.size.y - 4.0)), C_IRON, 3.0)


func _sealed(op: Rect2, t: float) -> void:
	_caravan(op, t)
	if t < 0.5:
		var c := op.get_center()
		draw_line(Vector2(op.position.x, c.y - 6.0), Vector2(op.end.x, c.y + 6.0), C_IRON, 3.0)
		draw_line(Vector2(op.position.x, c.y + 6.0), Vector2(op.end.x, c.y - 6.0), C_IRON, 3.0)


func _padlock(p: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_time * 3.0)
	draw_rect(Rect2(p + Vector2(-6.0, -2.0), Vector2(12.0, 11.0)), C_GOLD)
	draw_arc(p + Vector2(0, -3.0), 4.5, PI, TAU, 10, C_GOLD, 2.5)
	draw_rect(Rect2(p + Vector2(-6.0, -2.0), Vector2(12.0, 11.0)), C_OUT, false, 1.2)
	draw_circle(p + Vector2(0, 3.0), 6.0 + pulse * 3.0, Color(1.0, 0.7, 0.2, 0.12 + 0.08 * pulse))


func _hc_vertical(t: float) -> void:
	var top := -TS + 4.0
	var length := TS - 8.0
	draw_rect(Rect2(-9.0, -TS, 18.0, TS), Color(0.2, 0.14, 0.24, 0.75))
	match kind:
		KIND_CURTAIN:
			var vis := 1.0 - t
			if vis > 0.02:
				var y := top
				var i := 0
				while y < top + length * vis - 0.5:
					draw_rect(Rect2(-6.0, y, 12.0, minf(6.0, top + length * vis - y)), accent if i % 2 == 0 else C_WHITE)
					y += 6.0
					i += 1
				draw_rect(Rect2(-6.0, top, 12.0, length * vis), C_OUT, false, 1.5)
		KIND_GATE:
			var ang := t * deg_to_rad(95.0)
			_draw_slab(Vector2(0.0, top), Vector2(sin(ang), cos(ang)) * length, C_IRON, 6.0)
		_:
			var ang2 := t * deg_to_rad(95.0)
			_draw_slab(Vector2(0.0, top), Vector2(sin(ang2), cos(ang2)) * length, C_WOOD, 10.0)
	for y2: float in [-TS + 2.0, -2.0]:
		draw_rect(Rect2(-11.0, y2 - 5.0, 22.0, 10.0), C_FRAME)
		draw_rect(Rect2(-11.0, y2 - 5.0, 22.0, 10.0), C_OUT, false, 1.5)
	if is_locked():
		_padlock(Vector2(0.0, -TS * 0.5))
