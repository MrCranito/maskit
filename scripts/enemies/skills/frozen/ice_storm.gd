extends Node2D
## Tempête de glace (ice_storm : Drone de froid, Titan de glace) : tourbillon de neige et de grésil
## qui dérive vers le joueur le plus proche pendant `duration` s. Dedans : statut « slow »
## (vitesse × (1 − slow)), petits dégâts (dps) et vision réduite (nuage opaque).
## Dessin unique (_draw des calques) ; l'animation ne fait que tourner deux calques.
## Danger créé par l'hôte (comme la tornade du Far West) : non relayé à l'invité en coop.

const GROUP := &"ice_storms"
const SNOW := Color(0.86, 0.94, 1.0)
const FROST := Color(0.45, 0.78, 1.0)
const DEEP := Color(0.16, 0.30, 0.62)

var radius: float = 120.0
var duration: float = 6.0
var drift_speed: float = 55.0
var slow: float = 0.35
var slow_time: float = 0.4
var dps: float = 3.0
var opacity: float = 0.75
var tick: float = 0.25
var source: Node = null
var _t: float = 0.0
var _tick_left: float = 0.0
var _swirl: Node2D = null
var _core: Node2D = null
var _targets: Array[Node2D] = []


static func spawn(parent: Node, pos: Vector2, params: Dictionary, src: Node) -> Node2D:
	var n: Node2D = (load("res://scripts/enemies/skills/frozen/ice_storm.gd") as GDScript).new()
	for key: String in ["radius", "duration", "drift_speed", "slow", "slow_time", "dps", "opacity", "tick"]:
		if params.has(key):
			n.set(key, float(params[key]))
	n.source = src
	n.position = pos
	parent.add_child(n)
	n.global_position = pos
	return n


func _ready() -> void:
	add_to_group(GROUP)
	z_index = 55  # au-dessus des personnages et des toits, sous le brouillard
	scale = Vector2(1.0, 0.55)  # disque au sol vu en 3/4
	_swirl = _layer(1.0, 0.0)
	_core = _layer(0.55, 1.3)


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
		l.draw_circle(Vector2.from_angle(a) * r * 0.35, r * 0.72, Color(SNOW if k % 2 == 0 else FROST, opacity * 0.30))
	l.draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(DEEP, opacity * 0.8), 3.0, true)
	for k2: int in 12:
		var a2 := ph + TAU * float(k2) / 12.0
		l.draw_arc(Vector2.ZERO, r * (0.45 + 0.07 * float(k2 % 4)), a2, a2 + 0.8, 10, Color(1, 1, 1, opacity * 0.6), 3.0)
	# flocons / grêlons
	for k3: int in 14:
		var a3 := ph * 2.0 + float(k3) * 2.4
		var rr := r * (0.15 + 0.8 * fposmod(float(k3) * 0.37, 1.0))
		l.draw_circle(Vector2.from_angle(a3) * rr, 3.0 + float(k3 % 3), Color(1, 1, 1, opacity))


func is_inside(pos: Vector2) -> bool:
	var d := pos - global_position
	return Vector2(d.x, d.y / 0.55).length() <= radius


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	modulate.a = clampf(minf(_t / 0.4, (duration - _t) / 0.6), 0.0, 1.0)
	_swirl.rotation += delta * 2.0
	_core.rotation -= delta * 3.1
	EnemySkills.player_targets(get_tree(), _targets)
	var best: Node2D = null
	for p: Node2D in _targets:
		if best == null or p.global_position.distance_to(global_position) < best.global_position.distance_to(global_position):
			best = p
	if best != null and drift_speed > 0.0:
		global_position = global_position.move_toward(best.global_position, drift_speed * delta)
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = tick
	for p2: Node2D in _targets:
		if is_inside(p2.global_position):
			EnemySkills.hit_player(p2, dps * tick, source if is_instance_valid(source) else null, &"slow", slow_time, slow)
