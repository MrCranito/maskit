extends Node2D
## Tempête de sable (Pharaon éternel) : nuage tourbillonnant qui dérive vers le joueur pendant
## `duration` s. Dedans : ralentissement, petits dégâts, aveuglement léger ; le nuage opaque masque
## ce qu'il recouvre. Dessin unique, l'animation ne fait que tourner deux calques.

const GROUP := &"eg_sandstorms"
const SAND := Color(0.86, 0.66, 0.40)
const SAND_DARK := Color(0.58, 0.40, 0.24)

var radius: float = 150.0
var duration: float = 8.0
var drift_speed: float = 60.0
var slow: float = 0.4
var dps: float = 5.0
var blind: float = 0.4
var opacity: float = 0.8
var source: Node = null
var _t: float = 0.0
var _tick: float = 0.0
var _a: Node2D = null
var _b: Node2D = null
var _targets: Array[Node2D] = []


static func spawn(parent: Node, pos: Vector2, params: Dictionary, src: Node) -> Node2D:
	var n: Node2D = (load("res://scripts/enemies/skills/egypt/eg_sandstorm.gd") as GDScript).new()
	n.radius = float(params.get("radius", n.radius))
	n.duration = float(params.get("duration", n.duration))
	n.drift_speed = float(params.get("drift_speed", n.drift_speed))
	n.slow = float(params.get("slow", n.slow))
	n.dps = float(params.get("dps", n.dps))
	n.blind = float(params.get("blind", n.blind))
	n.opacity = float(params.get("opacity", n.opacity))
	n.source = src
	parent.add_child(n)
	n.global_position = pos
	return n


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 55
	scale = Vector2(1.0, 0.55)
	_a = _layer(1.0, 0.0)
	_b = _layer(0.6, 1.9)


func _layer(k: float, ph: float) -> Node2D:
	var l := Node2D.new()
	l.set_meta(&"r", radius * k)
	l.set_meta(&"ph", ph)
	l.draw.connect(_draw_layer.bind(l))
	add_child(l)
	return l


func _draw_layer(l: Node2D) -> void:
	var r: float = l.get_meta(&"r")
	var ph: float = l.get_meta(&"ph")
	for k: int in 8:
		var a := ph + TAU * float(k) / 8.0
		l.draw_circle(Vector2.from_angle(a) * r * 0.35, r * 0.7, Color(SAND if k % 2 == 0 else SAND_DARK, opacity * 0.32))
	for k2: int in 12:
		var a2 := ph + TAU * float(k2) / 12.0
		l.draw_arc(Vector2.ZERO, r * (0.5 + 0.06 * float(k2 % 3)), a2, a2 + 0.8, 10, Color(1.0, 0.9, 0.7, opacity * 0.5), 3.0)


func is_inside(pos: Vector2) -> bool:
	var d := pos - global_position
	return Vector2(d.x, d.y / 0.55).length() <= radius


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	modulate.a = clampf(minf(_t / 0.5, (duration - _t) / 0.7), 0.0, 1.0)
	_a.rotation += delta * 2.0
	_b.rotation -= delta * 3.1
	EnemySkills.player_targets(get_tree(), _targets)
	var best: Node2D = null
	for p: Node2D in _targets:
		if best == null or p.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
			best = p
	if best != null and drift_speed > 0.0:
		global_position = global_position.move_toward(best.global_position, drift_speed * delta)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.25
	var src: Node = source if is_instance_valid(source) else null
	for p2: Node2D in _targets:
		if is_inside(p2.global_position):
			EnemySkills.hit_player(p2, dps * 0.25, src, &"slow", 0.45, slow)
			if blind > 0.0:
				EnemySkills.hit_player(p2, 0.0, src, &"blind", 0.45, blind)
