extends Node2D
## Effet visuel bref du bestiaire d'Égypte (aucune collision, aucun dégât) : halo solaire,
## sable qui jaillit, aura de malédiction, rayon de soleil, résurrection. Dessiné en code
## (placeholders dans la palette : or, sable ocre, vert maudit), libéré à la fin.

const GROUP := &"eg_fx"
const SUN := Color(1.0, 0.78, 0.30)
const SUN_CORE := Color(1.0, 0.96, 0.70)
const SAND := Color(0.86, 0.66, 0.40)
const SAND_DARK := Color(0.56, 0.38, 0.22)
const CURSE := Color(0.36, 1.0, 0.78)
const CURSE_DARK := Color(0.10, 0.36, 0.30)

var style: StringName = &"sun"
var radius: float = 60.0
var duration: float = 0.6
var to: Vector2 = Vector2.ZERO
var _t: float = 0.0


## `style` : sun (halo qui s'étend), sand (gerbe de sable), curse (anneau vert qui se resserre),
## beam (rayon de `pos` vers `p_to`), rise (colonne de sable : résurrection / invocation).
static func spawn(parent: Node, p_style: StringName, pos: Vector2, p_radius: float, p_duration: float,
		p_to: Vector2 = Vector2.ZERO) -> Node2D:
	if parent == null:
		return null
	var n: Node2D = (load("res://scripts/enemies/skills/egypt/eg_fx.gd") as GDScript).new()
	n.style = p_style
	n.radius = p_radius
	n.duration = maxf(p_duration, 0.05)
	n.to = p_to
	parent.add_child(n)
	n.global_position = pos
	return n


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"fog_hideable")
	z_index = 5


func _process(delta: float) -> void:
	_t += delta
	if _t >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var w := clampf(_t / duration, 0.0, 1.0)
	var fade := 1.0 - w
	match style:
		&"sun":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
			draw_circle(Vector2.ZERO, radius * (0.4 + 0.6 * w), Color(SUN, 0.28 * fade))
			draw_arc(Vector2.ZERO, radius * (0.4 + 0.6 * w), 0.0, TAU, 48, Color(SUN_CORE, 0.9 * fade), 4.0, true)
			for k: int in 12:
				var a := TAU * float(k) / 12.0 + w
				draw_line(Vector2.from_angle(a) * radius * 0.3, Vector2.from_angle(a) * radius * (0.5 + 0.6 * w),
					Color(SUN, 0.7 * fade), 3.0, true)
		&"sand":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
			for k: int in 10:
				var a := TAU * float(k) / 10.0
				var r := radius * (0.3 + 0.8 * w)
				draw_circle(Vector2.from_angle(a) * r, radius * 0.22 * (1.0 - 0.5 * w),
					Color(SAND if k % 2 == 0 else SAND_DARK, 0.65 * fade))
		&"curse":
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
			draw_arc(Vector2.ZERO, radius * (1.0 - 0.6 * w), 0.0, TAU, 40, Color(CURSE, 0.9 * fade), 4.0, true)
			draw_circle(Vector2.ZERO, radius * (1.0 - 0.6 * w), Color(CURSE_DARK, 0.25 * fade))
		&"beam":
			var d := to_local(to)
			draw_line(Vector2.ZERO, d, Color(SUN, 0.45 * fade), radius, true)
			draw_line(Vector2.ZERO, d, Color(SUN_CORE, 0.9 * fade), radius * 0.35, true)
		&"rise":
			var h := 90.0 * sin(w * PI)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
			draw_circle(Vector2.ZERO, radius, Color(SAND_DARK, 0.45 * fade))
			draw_set_transform(Vector2.ZERO)
			for k: int in 6:
				var x := (float(k) - 2.5) * radius * 0.3
				draw_line(Vector2(x, 0), Vector2(x * 1.3, -h * (0.6 + 0.4 * float(k % 2))), Color(SAND, 0.75 * fade), 5.0, true)
