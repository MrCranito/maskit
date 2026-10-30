extends Node2D
## Trait cryogénique (ice_cryo_shot du Chasseur arctique, canon du Mécanicien) : projectile cyan
## qui gèle le joueur touché (dégâts + statut « slow », et « root » facultatif). Arrêté par les murs
## (rayon physique sur la couche 1). Danger créé par l'hôte : non relayé à l'invité en coop.

const CORE := Color(0.92, 1.0, 1.0)
const GLOW := Color(0.36, 0.9, 1.0)

var dir: Vector2 = Vector2.RIGHT
var speed: float = 760.0
var damage: float = 14.0
var lifetime: float = 1.2
var hit_radius: float = 20.0
var slow: float = 0.5
var slow_time: float = 2.0
var root_time: float = 0.0
var source: Node = null
var _t: float = 0.0
var _ray: PhysicsRayQueryParameters2D = null
var _targets: Array[Node2D] = []


static func spawn(parent: Node, pos: Vector2, direction: Vector2, params: Dictionary, src: Node) -> Node2D:
	var n: Node2D = (load("res://scripts/enemies/skills/frozen/ice_bolt.gd") as GDScript).new()
	n.dir = direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	for key: String in ["speed", "damage", "lifetime", "hit_radius", "slow", "slow_time", "root_time"]:
		if params.has(key):
			n.set(key, float(params[key]))
	n.source = src
	n.position = pos
	parent.add_child(n)
	n.global_position = pos
	n.rotation = n.dir.angle()
	return n


func _ready() -> void:
	z_index = 20
	_ray = PhysicsRayQueryParameters2D.new()
	_ray.collision_mask = 1


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	var from := global_position
	var to := from + dir * speed * delta
	_ray.from = from
	_ray.to = to
	var hit := get_world_2d().direct_space_state.intersect_ray(_ray)
	EnemySkills.player_targets(get_tree(), _targets)
	for p: Node2D in _targets:
		if Geometry2D.get_closest_point_to_segment(p.global_position, from, to).distance_to(p.global_position) <= hit_radius:
			var src := source if is_instance_valid(source) else null
			EnemySkills.hit_player(p, damage, src, &"slow", slow_time, slow)
			if root_time > 0.0:
				EnemySkills.hit_player(p, 0.0, src, &"root", root_time, 1.0)
			queue_free()
			return
	if not hit.is_empty():
		queue_free()
		return
	global_position = to


func _draw() -> void:
	draw_line(Vector2(-34, 0), Vector2(6, 0), Color(GLOW, 0.25), 16.0, true)
	draw_line(Vector2(-24, 0), Vector2(6, 0), Color(GLOW, 0.6), 8.0, true)
	draw_circle(Vector2(4, 0), 8.0, Color(GLOW, 0.55))
	draw_circle(Vector2(4, 0), 4.5, CORE)
	for k: int in 3:
		var a := TAU * float(k) / 3.0
		draw_line(Vector2(4, 0), Vector2(4, 0) + Vector2.from_angle(a) * 10.0, Color(CORE, 0.8), 2.0, true)
