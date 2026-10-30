class_name HealthGauge
extends Control
## Jauge de vie continue du HUD (direction D) : piste encre à coin biseauté, remplissage dont la
## couleur passe du vert à l'ambre puis au rouge, crans discrets à 25/50/75 %, et :
##   - traînée de dégâts : la partie perdue reste visible (rose clair) un instant puis descend ;
##   - soin : le segment gagné s'allume en vert et le remplissage y monte ;
##   - PV bas (≤ [hud] hp_low_ratio) : le remplissage clignote.
## Ne tourne (_process) que pendant une animation ou sous le seuil bas.

const GREEN := Color(0.36, 0.89, 0.55)
const AMBER := Color(1.0, 0.72, 0.28)
const RED := Color(1.0, 0.3, 0.38)
const TRACK := Color(1.0, 1.0, 1.0, 0.12)
const TRAIL := Color(1.0, 0.86, 0.88, 0.8)
const HEAL := Color(0.62, 1.0, 0.74, 0.95)
const TICK := Color(0.024, 0.027, 0.05, 0.75)

## Émis quand le blink bas change (le HUD accorde l'icône et le chiffre).
signal low_changed(low: bool)

var max_value: float = 100.0
## PV réels (cible).
var value: float = 100.0
## PV affichés par le remplissage (monte vers `value` lors d'un soin).
var shown: float = 100.0
## Traînée de dégâts (≥ shown) ; descend après le maintien.
var trail: float = 100.0
var cut: float = 6.0

var _hold_left: float = 0.0
var _blink_t: float = 0.0
var _heal_glow: float = 0.0
var _low: bool = false
var _low_ratio: float = 0.25
var _mid_ratio: float = 0.5
var _hold: float = 0.4
var _trail_speed: float = 1.0
var _heal_speed: float = 1.0
var _blink_speed: float = 8.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_ratio = Balance.get_float("hud", "hp_low_ratio", 0.25)
	_mid_ratio = Balance.get_float("hud", "hp_mid_ratio", 0.5)
	_hold = Balance.get_float("hud", "hp_trail_hold", 0.4)
	_trail_speed = 1.0 / maxf(Balance.get_float("hud", "hp_trail_time", 0.5), 0.01)
	_heal_speed = 1.0 / maxf(Balance.get_float("hud", "hp_heal_time", 0.35), 0.01)
	_blink_speed = Balance.get_float("hud", "hp_blink_speed", 8.0)
	set_process(false)


## Nouvelle valeur. `instant` : aucune animation (apparition du joueur).
func set_values(current: float, maximum: float, instant: bool = false) -> void:
	max_value = maxf(maximum, 1.0)
	var v: float = clampf(current, 0.0, max_value)
	if instant:
		value = v
		shown = v
		trail = v
		_hold_left = 0.0
		_heal_glow = 0.0
	elif v < value:
		# Dégâts : la traînée garde l'ancien niveau, le remplissage tombe tout de suite.
		trail = maxf(trail, shown)
		shown = minf(shown, v)
		value = v
		_hold_left = _hold
	elif v > value:
		# Soin : le remplissage monte vers la nouvelle valeur, segment gagné en vert.
		value = v
		_heal_glow = 1.0
	else:
		value = v
	trail = maxf(trail, shown)
	_update_low()
	_refresh_process()
	queue_redraw()


func ratio() -> float:
	return value / max_value


func is_low() -> bool:
	return _low


## Couleur du remplissage pour un ratio de PV : vert → ambre (mi-vie) → rouge (seuil bas).
func fill_color_for(r: float) -> Color:
	if r <= _low_ratio:
		return RED
	if r <= _mid_ratio:
		return RED.lerp(AMBER, (r - _low_ratio) / maxf(_mid_ratio - _low_ratio, 0.001))
	return AMBER.lerp(GREEN, clampf((r - _mid_ratio) / maxf(1.0 - _mid_ratio - 0.15, 0.001), 0.0, 1.0))


func fill_color() -> Color:
	return fill_color_for(ratio())


func is_animating() -> bool:
	return trail > shown + 0.01 or value > shown + 0.01 or _heal_glow > 0.0


func _update_low() -> void:
	var low: bool = value > 0.0 and ratio() <= _low_ratio
	if low != _low:
		_low = low
		_blink_t = 0.0
		low_changed.emit(low)


func _refresh_process() -> void:
	set_process(is_animating() or _low)


## Opacité du clignotement (1 hors seuil bas).
func blink_alpha() -> float:
	return 0.45 + 0.55 * absf(cos(_blink_t * _blink_speed * 0.5)) if _low else 1.0


func _process(delta: float) -> void:
	if _hold_left > 0.0:
		_hold_left -= delta
	elif trail > shown:
		trail = maxf(trail - max_value * _trail_speed * delta, shown)
	if value > shown:
		shown = minf(shown + max_value * _heal_speed * delta, value)
		trail = maxf(trail, shown)
	elif _heal_glow > 0.0:
		_heal_glow = maxf(_heal_glow - delta * 2.5, 0.0)
	if _low:
		_blink_t += delta
	_refresh_process()
	queue_redraw()


func _shape() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var c := minf(cut, h)
	return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h - c), Vector2(w - c, h), Vector2(0, h)])


## Segment [a, b] (PV) de la jauge, découpé dans la forme biseautée.
func _segment(a: float, b: float, col: Color) -> void:
	if b <= a or col.a <= 0.0:
		return
	var x0: float = a / max_value * size.x
	var x1: float = b / max_value * size.x
	var rect := PackedVector2Array([Vector2(x0, -1), Vector2(x1, -1), Vector2(x1, size.y + 1), Vector2(x0, size.y + 1)])
	for poly: PackedVector2Array in Geometry2D.intersect_polygons(_shape(), rect):
		draw_colored_polygon(poly, col)


func _draw() -> void:
	draw_colored_polygon(_shape(), TRACK)
	_segment(shown, trail, TRAIL)
	if value > shown:
		_segment(shown, value, Color(HEAL, 0.55 + 0.4 * _heal_glow))
	var fc := fill_color()
	fc.a = blink_alpha()
	if _heal_glow > 0.0:
		fc = fc.lerp(HEAL, _heal_glow * 0.6)
	_segment(0.0, shown, fc)
	# Reflet en haut du remplissage.
	if shown > 0.0:
		draw_rect(Rect2(0, 0, minf(shown / max_value * size.x, size.x - cut * 0.5), maxf(size.y * 0.22, 2.0)), Color(1, 1, 1, 0.22 * fc.a))
	# Crans 25 / 50 / 75 %.
	for i in [1, 2, 3]:
		var x: float = size.x * 0.25 * float(i)
		draw_rect(Rect2(x - 1.0, 0, 2.0, size.y), TICK)
