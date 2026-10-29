class_name PlayerStatus
extends Node2D
## Statuts infligés au joueur par les compétences ennemies (Player.apply_status) :
##   stun      : immobile, ne tire plus (étoiles au-dessus de la tête) ;
##   knockdown : renversé — comme stun, plus une poussée (cercle de poussière au sol) ;
##   root      : pris au piège (ne bouge plus mais peut tirer) — mâchoires au sol ;
##   blind     : aveuglé (flash blanc plein écran pour le joueur local, visée perturbée,
##               aide à la visée coupée) ;
##   burn      : en feu (petites flammes ; les dégâts viennent de la zone de feu).
##   slow      : ralenti (tempête de sable…) — vitesse × (1 − intensité), intensité bornée à 0,9.
## Enfant du joueur ; traitement par image seulement tant qu'un statut est actif.
## Réglages : balance.cfg [player_status].

const KINDS: Array[StringName] = [&"stun", &"knockdown", &"root", &"blind", &"burn", &"slow"]
const STAR := Color(1.0, 0.9, 0.35)
const OUTLINE := Color(0.08, 0.06, 0.1)
const ROOT_COLOR := Color(0.72, 0.74, 0.8)
const FIRE := Color(1.0, 0.55, 0.15)

## kind → temps restant (s).
var left: Dictionary = {}
## kind → intensité (0..1+).
var strength: Dictionary = {}
var head_height: float = 60.0
var _t: float = 0.0
var _flash: ColorRect = null
var _layer: CanvasLayer = null


func _ready() -> void:
	z_index = 12
	set_process(false)


## Applique (ou prolonge) un statut. Les durées ne se cumulent pas : on garde la plus longue.
func apply(kind: StringName, duration: float, power: float = 1.0) -> void:
	if not KINDS.has(kind) or duration <= 0.0:
		return
	var cap := Balance.get_float("player_status", "max_duration", 3.0)
	left[kind] = maxf(float(left.get(kind, 0.0)), minf(duration, cap))
	strength[kind] = maxf(float(strength.get(kind, 0.0)), power)
	if kind == &"blind":
		_show_flash(power)
	set_process(true)
	queue_redraw()


func has(kind: StringName) -> bool:
	return float(left.get(kind, 0.0)) > 0.0


func time_left(kind: StringName) -> float:
	return float(left.get(kind, 0.0))


func is_active() -> bool:
	return not left.is_empty()


## Déplacement bloqué (étourdi, renversé, pris au piège).
func blocks_move() -> bool:
	return has(&"stun") or has(&"knockdown") or has(&"root")


## Multiplicateur de vitesse de déplacement (statut « slow » : 1 − intensité).
func speed_mult() -> float:
	if not has(&"slow"):
		return 1.0
	return 1.0 - clampf(float(strength.get(&"slow", 0.0)), 0.0, 0.9)


## Tir bloqué (étourdi, renversé).
func blocks_fire() -> bool:
	return has(&"stun") or has(&"knockdown")


## Visée perturbée par l'aveuglement (angle aléatoire borné).
func perturb_aim(dir: Vector2) -> Vector2:
	if not has(&"blind"):
		return dir
	var max_deg := Balance.get_float("player_status", "blind_aim_jitter_deg", 14.0) * float(strength.get(&"blind", 1.0))
	return dir.rotated(deg_to_rad(randf_range(-max_deg, max_deg)))


func clear_all() -> void:
	left.clear()
	strength.clear()
	if _flash != null:
		_flash.color.a = 0.0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	for k: Variant in left.keys():
		var v := float(left[k]) - delta
		if v <= 0.0:
			left.erase(k)
			strength.erase(k)
		else:
			left[k] = v
	if _flash != null:
		var b := time_left(&"blind")
		var full := Balance.get_float("player_status", "blind_flash_alpha", 0.85)
		_flash.color.a = clampf(b / 0.6, 0.0, 1.0) * full if b > 0.0 else 0.0
	if left.is_empty():
		set_process(false)
	queue_redraw()


## Flash blanc plein écran (joueur local uniquement).
func _show_flash(_power: float) -> void:
	var p := get_parent()
	if p == null or p != GameState.player:
		return
	if _flash == null:
		_layer = CanvasLayer.new()
		_layer.layer = 60
		add_child(_layer)
		_flash = ColorRect.new()
		_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash.color = Color(1.0, 0.98, 0.92, 0.0)
		_layer.add_child(_flash)


func _draw() -> void:
	var head := Vector2(0, -head_height)
	if has(&"stun") or has(&"knockdown"):
		for i: int in 3:
			var ang := _t * 7.0 + TAU * float(i) / 3.0
			var p := head + Vector2(cos(ang) * 15.0, sin(ang) * 5.0)
			draw_circle(p, 3.6, Color(OUTLINE, 0.85))
			draw_circle(p, 2.5, STAR)
	if has(&"knockdown"):
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.4))
		draw_arc(Vector2.ZERO, 22.0 + 4.0 * sin(_t * 9.0), 0.0, TAU, 28, Color(0.95, 0.9, 0.8, 0.6), 3.0, true)
		draw_set_transform(Vector2.ZERO)
	if has(&"root"):
		draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.45))
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 24, Color(OUTLINE, 0.9), 5.0, true)
		draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 24, ROOT_COLOR, 2.5, true)
		for i: int in 8:
			var a := TAU * float(i) / 8.0
			draw_line(Vector2.from_angle(a) * 13.0, Vector2.from_angle(a) * 21.0, ROOT_COLOR, 2.0, true)
		draw_set_transform(Vector2.ZERO)
	if has(&"burn"):
		for i: int in 4:
			var x := -12.0 + 8.0 * float(i)
			var h := 10.0 + 6.0 * absf(sin(_t * 11.0 + float(i) * 1.7))
			var base := Vector2(x, -10.0 - 10.0 * float(i % 2))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-4, 0), base + Vector2(0, -h), base + Vector2(4, 0)]),
				Color(FIRE, 0.85))
			draw_circle(base + Vector2(0, -2), 2.5, Color(1.0, 0.9, 0.4, 0.9))
	if has(&"blind"):
		# Petits éclats au-dessus de la tête (visibles aussi par le coéquipier).
		for i: int in 4:
			var a := TAU * float(i) / 4.0 + _t * 3.0
			draw_line(head + Vector2.from_angle(a) * 6.0, head + Vector2.from_angle(a) * 13.0, Color(1, 1, 0.85, 0.9), 2.0, true)
