extends Node2D
## Éruption de glace (ice_spikes : lignes de pics ; ice_icefall : pluie de stalactites) : cercles
## de danger (télégraphe) aux points `points` pendant `delay` s, puis des cristaux jaillissent :
## dégâts aux joueurs à moins de `radius` d'un point + statut (« root » pour les pics, « slow »
## pour la grêle). Les points peuvent éclore en cascade (`stagger` s entre deux points).
## Danger créé par l'hôte (dessin compris) : non relayé à l'invité en coop.

const WARN := Color(0.45, 0.85, 1.0)
const ICE := Color(0.62, 0.88, 1.0)
const ICE_DARK := Color(0.16, 0.34, 0.7)
const ICE_LIGHT := Color(0.94, 1.0, 1.0)

var points: PackedVector2Array = PackedVector2Array()
var radius: float = 40.0
var delay: float = 0.8
var stagger: float = 0.0
var damage: float = 14.0
var status: StringName = &"root"
var status_time: float = 0.8
var strength: float = 1.0
var linger: float = 1.2
var source: Node = null
var _t: float = 0.0
var _done: PackedByteArray = PackedByteArray()
var _hit_ids: Dictionary = {}
var _targets: Array[Node2D] = []


## `points` en coordonnées monde.
static func spawn(parent: Node, pts: PackedVector2Array, params: Dictionary, src: Node) -> Node2D:
	var n: Node2D = (load("res://scripts/enemies/skills/frozen/ice_shards.gd") as GDScript).new()
	for key: String in ["radius", "delay", "stagger", "damage", "status_time", "strength", "linger"]:
		if params.has(key):
			n.set(key, float(params[key]))
	n.status = StringName(str(params.get("status", "root")))
	n.source = src
	parent.add_child(n)
	n.global_position = Vector2.ZERO
	var local := PackedVector2Array()
	for p: Vector2 in pts:
		local.append(n.to_local(p))
	n.points = local
	n._done.resize(local.size())
	n._done.fill(0)
	return n


func _ready() -> void:
	z_index = 5


## Instant d'éclosion du point i.
func erupt_time(i: int) -> float:
	return delay + stagger * float(i)


func _physics_process(delta: float) -> void:
	_t += delta
	var last := erupt_time(points.size() - 1) if points.size() > 0 else 0.0
	if _t >= last + linger:
		queue_free()
		return
	for i: int in points.size():
		if _done[i] == 1 or _t < erupt_time(i):
			continue
		_done[i] = 1
		_erupt(to_global(points[i]))
	queue_redraw()


func _erupt(pos: Vector2) -> void:
	EnemySkills.player_targets(get_tree(), _targets)
	var src := source if is_instance_valid(source) else null
	for p: Node2D in _targets:
		var id := p.get_instance_id()
		if _hit_ids.has(id) or p.global_position.distance_to(pos) > radius:
			continue
		_hit_ids[id] = true
		EnemySkills.hit_player(p, damage, src, status, status_time, strength, pos)
	var am := get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", &"glass_break", pos, -8.0)


func _draw() -> void:
	for i: int in points.size():
		var c := points[i]
		var te := erupt_time(i)
		if _t < te:
			var w := clampf(_t / maxf(te, 0.05), 0.0, 1.0)
			draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, radius, Color(WARN, 0.10 + 0.15 * w))
			draw_circle(Vector2.ZERO, radius * w, Color(WARN, 0.18))
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(ICE_LIGHT, 0.55 + 0.4 * sin(_t * 18.0)), 2.5, true)
			draw_set_transform(Vector2.ZERO)
			continue
		var age := _t - te
		var grow := clampf(age / 0.12, 0.0, 1.0)
		var fade := clampf((linger - age) / 0.4, 0.0, 1.0)
		draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, radius * 0.9, Color(ICE_DARK, 0.25 * fade))
		draw_set_transform(Vector2.ZERO)
		# cristaux : 5 lames qui jaillissent du sol
		for k: int in 5:
			var off := Vector2((float(k) - 2.0) * radius * 0.28, (float(k % 2) - 0.5) * radius * 0.25)
			var h := radius * (0.9 + 0.5 * float((k * 7 + i) % 3) * 0.5) * grow
			var base := c + off
			var lean := (float(k) - 2.0) * 0.12
			var tip := base + Vector2(lean * h, -h)
			var wdt := radius * 0.16
			var poly := PackedVector2Array([base + Vector2(-wdt, 0), tip, base + Vector2(wdt, 0)])
			draw_colored_polygon(poly, Color(ICE, 0.95 * fade))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-wdt * 0.2, 0), tip, base + Vector2(wdt, 0)]),
				Color(ICE_LIGHT, 0.75 * fade))
			var outline := poly.duplicate()
			outline.append(poly[0])
			draw_polyline(outline, Color(ICE_DARK, fade), 2.0, true)
