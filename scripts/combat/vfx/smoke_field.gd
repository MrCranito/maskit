class_name SmokeField
extends Node2D
## Nuage de fumée (grenade fumigène). Grossit, reste épais, puis se dissipe.
## Bloque la VUE des ennemis et des tourelles (pas l'ouïe ni les projectiles) :
## `SmokeField.blocks_line(a, b)` — registre statique des nuages actifs, test
## segment/cercle sans physique (quelques nuages au plus : coût négligeable).
## Groupe `smoke_clouds`. Dessin : bouffées dessinées une fois, animées par échelle,
## rotation et opacité des deux couches (aucun redessin par frame).

const GROUP := &"smoke_clouds"

## Nuages actifs (registre partagé).
static var _active: Array[SmokeField] = []

var radius: float = 120.0
var duration: float = 8.0
var grow_time: float = 0.8
var fade_time: float = 1.5
## Fraction du rayon qui bloque la vue (le bord du nuage est translucide).
var block_frac: float = 0.85
var age: float = 0.0

var _layers: Array[Node2D] = []
var _color: Color = Color(0.82, 0.83, 0.86, 0.9)
var _seed: int = 0


## Crée et ajoute un nuage en `pos` sous `parent`.
static func spawn(parent: Node, pos: Vector2, p_radius: float, p_duration: float) -> SmokeField:
	var s := SmokeField.new()
	s.radius = maxf(p_radius, 10.0)
	s.duration = maxf(p_duration, 0.1)
	parent.add_child(s)
	s.global_position = pos
	return s


## Vrai si un nuage épais coupe le segment [a, b] (vue bloquée).
static func blocks_line(a: Vector2, b: Vector2) -> bool:
	for s: SmokeField in _active:
		if is_instance_valid(s) and s.segment_blocked(a, b):
			return true
	return false


static func active_count() -> int:
	return _active.size()


## Vrai si `p` est dans la partie épaisse d'un nuage.
static func point_in_smoke(p: Vector2) -> bool:
	for s: SmokeField in _active:
		if is_instance_valid(s):
			var r: float = s.get_block_radius()
			if r > 0.0 and s.global_position.distance_squared_to(p) <= r * r:
				return true
	return false


## Logique pure : distance² du point `c` au segment [a, b].
static func segment_distance_sq(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab: Vector2 = b - a
	var l2: float = ab.length_squared()
	if l2 <= 0.000001:
		return a.distance_squared_to(c)
	var t: float = clampf((c - a).dot(ab) / l2, 0.0, 1.0)
	return (a + ab * t).distance_squared_to(c)


func _init() -> void:
	add_to_group(GROUP)
	z_as_relative = false
	z_index = 40
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	grow_time = Balance.get_float("gadgets", "smoke_grow_time", 0.8)
	fade_time = Balance.get_float("gadgets", "smoke_fade_time", 1.5)
	block_frac = Balance.get_float("gadgets", "smoke_block_frac", 0.85)
	_seed = randi()
	for i: int in 2:
		var layer := Node2D.new()
		layer.name = "Puffs%d" % i
		layer.draw.connect(_draw_layer.bind(layer, i))
		add_child(layer)
		_layers.append(layer)
	_active.append(self)
	_apply_visual()


func _exit_tree() -> void:
	_active.erase(self)


## Rayon courant qui bloque la vue (0 pendant la dissipation finale).
func get_block_radius() -> float:
	var g: float = clampf(age / maxf(grow_time, 0.01), 0.0, 1.0)
	var fade: float = 1.0
	var left: float = duration - age
	if left < fade_time:
		fade = clampf(left / maxf(fade_time, 0.01), 0.0, 1.0)
	if fade < 0.35:
		return 0.0
	return radius * block_frac * (0.35 + 0.65 * g)


func segment_blocked(a: Vector2, b: Vector2) -> bool:
	var r: float = get_block_radius()
	if r <= 0.0:
		return false
	return segment_distance_sq(a, b, global_position) <= r * r


## Avance le temps (appelé par _process ; public pour les tests).
func advance(delta: float) -> void:
	age += delta
	if age >= duration:
		_active.erase(self)
		queue_free()
		return
	_apply_visual()


func _process(delta: float) -> void:
	advance(delta)


func _apply_visual() -> void:
	var g: float = clampf(age / maxf(grow_time, 0.01), 0.0, 1.0)
	g = 1.0 - (1.0 - g) * (1.0 - g)
	var left: float = duration - age
	var a: float = clampf(left / maxf(fade_time, 0.01), 0.0, 1.0)
	var sc: float = (0.35 + 0.65 * g) * (1.0 + (1.0 - a) * 0.25)
	for i: int in _layers.size():
		var layer: Node2D = _layers[i]
		layer.scale = Vector2(sc, sc * 0.8)
		layer.rotation = age * (0.05 if i == 0 else -0.08)
		layer.modulate.a = a


func _draw_layer(c: Node2D, layer: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + layer * 977
	var n: int = 9 if layer == 0 else 7
	var col: Color = _color if layer == 0 else Color(0.93, 0.93, 0.95, 0.75)
	if layer == 0:
		c.draw_circle(Vector2.ZERO, radius * 0.75, Color(col, 0.55), true, -1.0, true)
	for i: int in n:
		var ang: float = TAU * float(i) / float(n) + rng.randf_range(-0.3, 0.3)
		var d: float = radius * rng.randf_range(0.2, 0.6)
		var r: float = radius * rng.randf_range(0.3, 0.48)
		var p := Vector2(cos(ang), sin(ang)) * d
		c.draw_circle(p, r, Color(col, col.a * 0.7), true, -1.0, true)
		c.draw_circle(p + Vector2(-r * 0.2, -r * 0.25), r * 0.55, Color(1, 1, 1, 0.18), true, -1.0, true)
