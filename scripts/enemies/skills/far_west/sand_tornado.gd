extends Node2D
## Tornade de sable (compétence fw_sand_tornado du Shérif Sable-Fou) : nuage tourbillonnant qui
## dérive vers le joueur pendant `duration` s. Dedans : statut « slow » (vitesse × (1 − slow)),
## petits dégâts (dps) et vision réduite (le nuage opaque masque ce qu'il recouvre, joueur compris).
## Dessin unique (_draw) ; l'animation ne fait que tourner/pulser deux calques (pas de redessin).

const GROUP := &"fw_sand_tornado"
const SAND := Color(0.84, 0.64, 0.40)
const SAND_DARK := Color(0.55, 0.38, 0.24)

var radius: float = 130.0
var duration: float = 7.0
var drift_speed: float = 70.0
var slow: float = 0.45
var slow_time: float = 0.4
var dps: float = 4.0
var opacity: float = 0.82
var source: Node = null
var _t: float = 0.0
var _tick: float = 0.0
var _swirl: Node2D = null
var _core: Node2D = null


static func spawn(parent: Node, pos: Vector2, params: Dictionary, src: Node) -> Node2D:
	var n: Node2D = (load("res://scripts/enemies/skills/far_west/sand_tornado.gd") as GDScript).new()
	n.radius = float(params.get("radius", n.radius))
	n.duration = float(params.get("duration", n.duration))
	n.drift_speed = float(params.get("drift_speed", n.drift_speed))
	n.slow = float(params.get("slow", n.slow))
	n.dps = float(params.get("dps", n.dps))
	n.opacity = float(params.get("opacity", n.opacity))
	n.source = src
	n.position = pos
	parent.add_child(n)
	n.global_position = pos
	return n


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 55  # au-dessus des personnages et des toits, sous le brouillard (80)
	scale = Vector2(1.0, 0.55)  # disque au sol vu en 3/4
	_swirl = _layer(1.0, 0.0)
	_core = _layer(0.55, 1.7)


func _layer(scale_r: float, phase: float) -> Node2D:
	var l := Node2D.new()
	l.set_meta(&"r", radius * scale_r)
	l.set_meta(&"phase", phase)
	l.draw.connect(_draw_layer.bind(l))
	add_child(l)
	return l


func _draw_layer(l: Node2D) -> void:
	var r: float = l.get_meta(&"r")
	var ph: float = l.get_meta(&"phase")
	for k: int in 7:
		var a := ph + TAU * float(k) / 7.0
		l.draw_circle(Vector2.from_angle(a) * r * 0.35, r * 0.72, Color(SAND if k % 2 == 0 else SAND_DARK, opacity * 0.35))
	for k2: int in 10:
		var a2 := ph + TAU * float(k2) / 10.0
		l.draw_arc(Vector2.ZERO, r * (0.55 + 0.05 * float(k2 % 3)), a2, a2 + 0.9, 10, Color(1.0, 0.9, 0.7, opacity * 0.5), 3.0)


func is_inside(pos: Vector2) -> bool:
	var d := pos - global_position
	return Vector2(d.x, d.y / 0.55).length() <= radius


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	var fade := clampf(minf(_t / 0.4, (duration - _t) / 0.6), 0.0, 1.0)
	modulate.a = fade
	_swirl.rotation += delta * 2.2
	_core.rotation -= delta * 3.4
	var targets: Array[Node2D] = []
	EnemySkills.player_targets(get_tree(), targets)
	var best: Node2D = null
	for p: Node2D in targets:
		if best == null or p.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
			best = p
	if best != null and drift_speed > 0.0:
		global_position = global_position.move_toward(best.global_position, drift_speed * delta)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	for p2: Node2D in targets:
		if is_inside(p2.global_position):
			EnemySkills.hit_player(p2, dps * 0.25, source if is_instance_valid(source) else null, &"slow", slow_time, slow)
