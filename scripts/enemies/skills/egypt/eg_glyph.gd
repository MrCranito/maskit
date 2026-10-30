extends Node2D
## Frappe au sol différée du bestiaire d'Égypte (pièges et mécanismes anciens, pluie de flèches,
## éruption solaire, malédiction, crachat de venin) : un cercle marqué d'un motif (télégraphe)
## pendant `delay` s, puis la frappe (dégâts + statut aux joueurs dans `radius`), puis, si
## `linger` > 0, une flaque qui reste (dégâts par seconde + ralentissement).
## Un seul nœud par frappe, dessiné en code (placeholder), libéré à la fin.

const GROUP := &"eg_glyphs"
const OUTLINE := Color(0.08, 0.05, 0.06)
const DANGER := Color(1.0, 0.30, 0.12)
const COLORS := {
	&"spikes": Color(0.80, 0.70, 0.52), &"arrows": Color(0.90, 0.80, 0.55), &"sun": Color(1.0, 0.76, 0.28),
	&"curse": Color(0.36, 1.0, 0.78), &"venom": Color(0.55, 0.95, 0.30),
}

var style: StringName = &"spikes"
var radius: float = 60.0
var delay: float = 1.0
var damage: float = 10.0
var status: StringName = &""
var status_time: float = 0.0
var status_strength: float = 1.0
var linger: float = 0.0
var linger_dps: float = 0.0
var linger_slow: float = 0.0
var venom: bool = false
var venom_params: Dictionary = {}
var source: Node = null
## Nombre de joueurs touchés par la frappe (tests, debug).
var hits: int = 0
var struck: bool = false

var _t: float = 0.0
var _tick: float = 0.0
var _targets: Array[Node2D] = []


static func spawn(parent: Node, pos: Vector2, params: Dictionary, p_source: Node) -> Node2D:
	if parent == null:
		return null
	var n: Node2D = (load("res://scripts/enemies/skills/egypt/eg_glyph.gd") as GDScript).new()
	n.style = StringName(str(params.get("style", "spikes")))
	n.radius = float(params.get("radius", 60.0))
	n.delay = maxf(float(params.get("delay", 1.0)), 0.05)
	n.damage = float(params.get("damage", 10.0))
	n.status = StringName(str(params.get("status", "")))
	n.status_time = float(params.get("status_time", 0.0))
	n.status_strength = float(params.get("status_strength", 1.0))
	n.linger = float(params.get("linger", 0.0))
	n.linger_dps = float(params.get("linger_dps", 0.0))
	n.linger_slow = float(params.get("linger_slow", 0.0))
	n.venom = bool(params.get("venom", false))
	n.venom_params = params
	n.source = p_source
	parent.add_child(n)
	n.global_position = pos
	return n


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"fog_hideable")
	z_index = 3


func _physics_process(delta: float) -> void:
	_t += delta
	if not struck and _t >= delay:
		_strike()
	if struck:
		var after := _t - delay
		if after >= maxf(linger, 0.45):
			queue_free()
			return
		if linger > 0.0 and after > 0.1:
			_tick -= delta
			if _tick <= 0.0:
				_tick = 0.25
				_pool_tick()
	queue_redraw()


func _strike() -> void:
	struck = true
	var src: Node = source if is_instance_valid(source) else null
	if is_inside_tree():
		hits = EnemySkills.hit_players_in_radius(get_tree(), global_position, radius, damage, src, status,
			status_time, status_strength)
		if venom and hits > 0:
			EnemySkills.player_targets(get_tree(), _targets)
			for p: Node2D in _targets:
				if p.global_position.distance_to(global_position) <= radius:
					EgVenomDot.apply(p, venom_params, src)
		var fx := CombatFx.get_or_create(get_tree())
		if fx != null:
			for i: int in 3:
				fx.dust_puff(global_position + Vector2(randf_range(-radius, radius) * 0.4, randf_range(-6, 6)),
					Vector2(randf_range(-30, 30), -14.0), 6.0, 0.4)


func _pool_tick() -> void:
	EnemySkills.player_targets(get_tree(), _targets)
	var src: Node = source if is_instance_valid(source) else null
	for p: Node2D in _targets:
		if p.global_position.distance_to(global_position) <= radius:
			EnemySkills.hit_player(p, linger_dps * 0.25, src, &"slow" if linger_slow > 0.0 else &"", 0.4, linger_slow)


func _draw() -> void:
	var col: Color = COLORS.get(style, DANGER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
	if not struck:
		var w := clampf(_t / delay, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(_t * 16.0)
		draw_circle(Vector2.ZERO, radius, Color(DANGER, 0.08 + 0.08 * w))
		draw_circle(Vector2.ZERO, radius * w, Color(col, 0.16 + 0.14 * w))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(OUTLINE, 0.6), 5.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(col.lerp(DANGER, 0.5), 0.6 + 0.4 * pulse), 3.0, true)
		_draw_motif(col, w, 0.8 + 0.2 * w)
		return
	var a := _t - delay
	var fade := 1.0 - clampf(a / maxf(linger, 0.45), 0.0, 1.0)
	if linger > 0.0:
		draw_circle(Vector2.ZERO, radius, Color(col.darkened(0.35), 0.35 * fade + 0.1))
		for k: int in 6:
			var b := TAU * float(k) / 6.0 + _t * 0.7
			draw_circle(Vector2.from_angle(b) * radius * 0.55, radius * 0.12 * (0.6 + 0.4 * sin(_t * 5.0 + float(k))),
				Color(col, 0.55 * fade))
	var burst := clampf(a / 0.3, 0.0, 1.0)
	if burst < 1.0:
		draw_circle(Vector2.ZERO, radius * (0.6 + 0.5 * burst), Color(col, 0.45 * (1.0 - burst)))
		draw_set_transform(Vector2.ZERO)
		_draw_burst(col, burst)


## Motif du télégraphe (lisible : pointes, flèches, soleil, œil maudit, gouttes).
func _draw_motif(col: Color, w: float, s: float) -> void:
	match style:
		&"spikes":
			for k: int in 7:
				var p := Vector2.from_angle(TAU * float(k) / 7.0) * radius * 0.55 if k > 0 else Vector2.ZERO
				draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 6) * s, p + Vector2(7, 6) * s, p + Vector2(0, -8) * s]),
					Color(col, 0.7))
		&"arrows":
			for k: int in 5:
				var p := Vector2.from_angle(TAU * float(k) / 5.0 + 0.3) * radius * 0.5 if k > 0 else Vector2.ZERO
				draw_line(p + Vector2(0, -12), p + Vector2(0, 8), Color(col, 0.8), 3.0, true)
				draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 3), p + Vector2(5, 3), p + Vector2(0, 11)]), Color(col, 0.8))
		&"sun":
			draw_circle(Vector2.ZERO, radius * 0.28 * s, Color(col, 0.55))
			for k: int in 10:
				var b := TAU * float(k) / 10.0 + w * 0.8
				draw_line(Vector2.from_angle(b) * radius * 0.35, Vector2.from_angle(b) * radius * 0.75, Color(col, 0.7), 3.0, true)
		&"curse":
			draw_arc(Vector2(0, 0), radius * 0.45, PI * 0.15, PI * 0.85, 16, Color(col, 0.85), 3.0, true)
			draw_arc(Vector2(0, 0), radius * 0.45, PI * 1.15, PI * 1.85, 16, Color(col, 0.85), 3.0, true)
			draw_circle(Vector2.ZERO, radius * 0.16 * s, Color(col, 0.85))
			draw_line(Vector2(0, radius * 0.2), Vector2(0, radius * 0.6), Color(col, 0.7), 3.0, true)
		&"venom":
			for k: int in 4:
				var p := Vector2.from_angle(TAU * float(k) / 4.0 + 0.6) * radius * 0.45
				draw_circle(p, 6.0 * s, Color(col, 0.75))


func _draw_burst(col: Color, burst: float) -> void:
	var up := sin(burst * PI)
	match style:
		&"spikes", &"curse":
			for k: int in 9:
				var p := Vector2.from_angle(TAU * float(k) / 9.0) * radius * 0.6 * Vector2(1.0, 0.6) if k > 0 else Vector2.ZERO
				var h := 34.0 * up
				draw_colored_polygon(PackedVector2Array([p + Vector2(-7, 0), p + Vector2(7, 0), p + Vector2(0, -h)]),
					Color(col.lightened(0.2), 0.95))
				draw_polyline(PackedVector2Array([p + Vector2(-7, 0), p + Vector2(0, -h), p + Vector2(7, 0)]), Color(OUTLINE, 0.9), 2.0, true)
		&"arrows":
			for k: int in 6:
				var p := Vector2.from_angle(TAU * float(k) / 6.0 + 0.2) * radius * 0.55 * Vector2(1.0, 0.6)
				draw_line(p + Vector2(0, -30.0 * (1.0 - burst)), p, Color(OUTLINE, 0.9), 3.0, true)
		&"sun":
			draw_circle(Vector2(0, -20.0 * up), radius * 0.45 * up, Color(1.0, 0.96, 0.7, 0.8 * (1.0 - burst)))
		&"venom":
			for k: int in 6:
				var b := TAU * float(k) / 6.0
				draw_circle(Vector2.from_angle(b) * radius * 0.5 * burst * Vector2(1.0, 0.6) + Vector2(0, -12.0 * up), 5.0,
					Color(col, 0.9))
