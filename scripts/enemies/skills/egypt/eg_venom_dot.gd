class_name EgVenomDot
extends Node2D
## Venin (Vipère des sables) : poison attaché au joueur mordu — dégâts par seconde pendant
## `venom_time` s, ralentissement, bulles vertes au-dessus de la tête. Une nouvelle morsure
## renouvelle la durée et ajoute une dose (au plus `venom_max_stacks`).

const NODE_NAME := "EgVenom"
const COL := Color(0.55, 0.95, 0.30)

var dps: float = 3.0
var left: float = 4.0
var stacks: int = 1
var max_stacks: int = 3
var slow: float = 0.2
var source: Node = null
var _tick: float = 0.0
var _t: float = 0.0


## Empoisonne `p` (paramètres venom_dps, venom_time, venom_slow, venom_max_stacks).
static func apply(p: Node2D, params: Dictionary, src: Node) -> EgVenomDot:
	if p == null or not is_instance_valid(p) or not EnemySkills.is_player_target(p):
		return null
	var v := p.get_node_or_null(NODE_NAME) as EgVenomDot
	if v == null:
		v = EgVenomDot.new()
		v.name = NODE_NAME
		p.add_child(v)
	else:
		v.stacks = mini(v.stacks + 1, v.max_stacks)
	v.dps = float(params.get("venom_dps", v.dps))
	v.left = maxf(v.left, float(params.get("venom_time", v.left)))
	v.slow = float(params.get("venom_slow", v.slow))
	v.max_stacks = int(params.get("venom_max_stacks", v.max_stacks))
	v.source = src
	return v


static func is_poisoned(p: Node) -> bool:
	return p != null and p.get_node_or_null(NODE_NAME) != null


func _ready() -> void:
	z_index = 20
	position = Vector2(0, -78)


func _physics_process(delta: float) -> void:
	_t += delta
	left -= delta
	var p := get_parent() as Node2D
	if left <= 0.0 or p == null or (p.has_method("is_alive") and not bool(p.call("is_alive"))):
		queue_free()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		EnemySkills.hit_player(p, dps * float(stacks) * 0.5, source if is_instance_valid(source) else null,
			&"slow" if slow > 0.0 else &"", 0.6, slow)
	queue_redraw()


func _draw() -> void:
	for k: int in stacks + 1:
		var y := -fmod(_t * 18.0 + float(k) * 9.0, 26.0)
		draw_circle(Vector2(float(k - 1) * 8.0, y), 3.5, Color(COL, 0.85 * (1.0 + y / 26.0)))
