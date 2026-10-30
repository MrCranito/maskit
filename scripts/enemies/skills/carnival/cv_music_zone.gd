extends Node2D
## Zone de musique de manège (Manège fantôme ; phase 3 du Roi du cirque) : disque violet aux
## lumières tournantes qui suit son créateur. Les joueurs à l'intérieur sont ralentis (statut
## « slow » rafraîchi) et subissent de petits dégâts ; les créatures du parc à l'intérieur se
## soignent (soutien). Contrôles espacés (`tick`), aucune allocation par image.
## Coop : effet local à l'hôte (pas de copie visuelle chez l'invité).

const GROUP := &"cv_music_zones"
const FILL := Color(0.55, 0.22, 1.0, 0.13)
const EDGE := Color(0.78, 0.45, 1.0, 0.75)
const LIGHT_A := Color(1.0, 0.3, 0.45, 0.95)
const LIGHT_B := Color(0.85, 0.6, 1.0, 0.95)

var source: Node2D = null
var p: Dictionary = {}
var real: bool = true

var _t: float = 0.0
var _tick_left: float = 0.0
var _targets: Array[Node2D] = []
var healed: float = 0.0
var slowed: int = 0


static func spawn(parent: Node, pos: Vector2, params: Dictionary, p_source: Node2D) -> Node2D:
	if parent == null:
		return null
	var z: Node2D = load("res://scripts/enemies/skills/carnival/cv_music_zone.gd").new()
	z.p = params
	z.source = p_source
	z.name = "CvMusicZone"
	z.z_index = 3
	z.position = (parent as Node2D).to_local(pos) if parent is Node2D else pos
	parent.add_child(z)
	return z


func f(key: String, def: float) -> float:
	return float(p.get(key, def))


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"fog_hideable")


func _physics_process(delta: float) -> void:
	_t += delta
	var follow := bool(p.get("follow", true))
	var alive := is_instance_valid(source) and (not source.has_method("is_alive") or bool(source.call("is_alive")))
	if _t >= f("duration", 5.0) or (follow and not alive):
		queue_free()
		return
	if follow and alive:
		global_position = source.global_position
	queue_redraw()
	_tick_left -= delta
	if _tick_left > 0.0 or not real or not is_inside_tree():
		return
	var tick := f("tick", 0.25)
	_tick_left = tick
	var r := f("radius", 220.0)
	EnemySkills.player_targets(get_tree(), _targets)
	for pl: Node2D in _targets:
		if pl.global_position.distance_to(global_position) <= r:
			EnemySkills.hit_player(pl, f("dps", 3.0) * tick, source if is_instance_valid(source) else null,
				&"slow", tick + 0.2, f("slow", 0.4))
			slowed += 1
	var hps := f("heal_per_sec", 0.0)
	if hps <= 0.0:
		return
	for n: Node in get_tree().get_nodes_in_group(Enemy.GROUP_UNITS):
		var o := n as Enemy
		if o == null or not o.is_alive() or o.hp >= o.max_hp:
			continue
		if o.global_position.distance_to(global_position) <= r:
			var amount := minf(hps * tick, o.max_hp - o.hp)
			o.heal(amount)
			healed += amount


func _draw() -> void:
	var r := f("radius", 220.0)
	var dur := f("duration", 5.0)
	var fade := clampf(minf(_t / 0.25, (dur - _t) / 0.4), 0.0, 1.0)
	draw_circle(Vector2.ZERO, r, Color(FILL, FILL.a * fade))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(EDGE, EDGE.a * fade), 3.0, true)
	draw_arc(Vector2.ZERO, r * 0.62, 0.0, TAU, 48, Color(EDGE, 0.35 * fade), 2.0, true)
	# Lumières de manège qui tournent.
	var n := 16
	for i: int in n:
		var a := TAU * float(i) / float(n) + _t * 1.6
		var col: Color = LIGHT_A if i % 2 == 0 else LIGHT_B
		draw_circle(Vector2.from_angle(a) * r, 5.0, Color(col, col.a * fade))
	# Notes de musique qui montent.
	for i: int in 4:
		var a2 := TAU * float(i) / 4.0 - _t * 0.9
		var c := Vector2.from_angle(a2) * r * 0.45 + Vector2(0, -fmod(_t * 30.0 + i * 13.0, 40.0))
		draw_circle(c, 4.5, Color(LIGHT_B, 0.8 * fade))
		draw_line(c + Vector2(4, 0), c + Vector2(4, -14), Color(LIGHT_B, 0.8 * fade), 2.0, true)
