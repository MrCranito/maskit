class_name DecoyDevice
extends Node2D
## Leurre posé au sol (gadget_decoy) : boîtier à antenne qui crépite et émet une source de
## bruit (NoiseSources) pendant `effect_duration` s dans `effect_radius` px ; les ennemis
## non engagés viennent enquêter (voir NoiseSources). Créé par GadgetDevice quand un objet de
## kind « decoy » s'immobilise (ou DecoyDevice.spawn).
## Rendu : boîtier dessiné une fois ; ondes sonores = anneaux dessinés une fois, animés par
## Tween (échelle + transparence) : aucun redessin par frame.

const RING_COUNT := 3

var weapon: WeaponData = null
var duration: float = 10.0
var radius: float = 520.0
var level: float = 1.0
var noise_id: int = -1

var _left: float = 0.0
var _beep_left: float = 0.0
var _rings: Array[Node2D] = []
var _body: Node2D = null
var _ending: bool = false


static func spawn(parent: Node, pos: Vector2, w: WeaponData) -> DecoyDevice:
	var d := DecoyDevice.new()
	d.weapon = w
	if w != null:
		d.duration = w.effect_duration if w.effect_duration > 0.0 else d.duration
		d.radius = w.effect_radius if w.effect_radius > 0.0 else d.radius
	# Position AVANT l'entrée dans l'arbre : _ready() émet la source de bruit à cet endroit.
	d.position = (parent as Node2D).to_local(pos) if parent is Node2D and parent.is_inside_tree() else pos
	parent.add_child(d)
	return d


func _init() -> void:
	z_as_relative = false
	# Au-dessus des décors et occulteurs (z 10-12), sous la fumée (40) : toujours lisible.
	z_index = 34
	name = "Decoy"
	add_to_group(&"decoys")


func _ready() -> void:
	level = Balance.get_float("crafting", "decoy_level", 1.0)
	_left = duration
	noise_id = NoiseSources.emit(global_position, level, duration, radius)
	for i in RING_COUNT:
		var r := Node2D.new()
		r.draw.connect(_draw_ring.bind(r))
		r.modulate.a = 0.0
		add_child(r)
		_rings.append(r)
	_body = Node2D.new()
	_body.draw.connect(_draw_body)
	var k: float = Balance.get_float("crafting", "decoy_body_scale", 1.6)
	_body.scale = Vector2(k, k)
	add_child(_body)
	# Debug (F3) : rayon d'attraction.
	if bool(GameState.get("debug_enabled")):
		var dbg := Node2D.new()
		dbg.name = "DebugRadius"
		dbg.draw.connect(func() -> void:
			dbg.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(1.0, 0.8, 0.3, 0.5), 2.0, true))
		add_child(dbg)
	_play_rings()
	_play(&"tick")


func _exit_tree() -> void:
	if noise_id >= 0:
		NoiseSources.stop(noise_id)
		noise_id = -1


func is_active() -> bool:
	return not _ending and _left > 0.0


func time_left() -> float:
	return maxf(_left, 0.0)


func _physics_process(delta: float) -> void:
	if _ending:
		return
	_left -= delta
	_beep_left -= delta
	if _beep_left <= 0.0:
		_beep_left = Balance.get_float("crafting", "decoy_beep_interval", 0.6)
		_play(&"tick")
	if _left <= 0.0:
		_finish()


## Ondes : chaque anneau grandit et s'efface en boucle, décalé des autres.
func _play_rings() -> void:
	var period: float = Balance.get_float("crafting", "decoy_ring_period", 1.2)
	for i in _rings.size():
		var r := _rings[i]
		var start := func() -> void:
			if not is_instance_valid(r) or _ending:
				return
			var tw := r.create_tween().set_loops()
			tw.tween_callback(func() -> void:
				r.scale = Vector2(0.25, 0.25)
				r.modulate.a = 0.9)
			tw.tween_property(r, "scale", Vector2.ONE, period).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(r, "modulate:a", 0.0, period)
		if i == 0:
			start.call()
		else:
			get_tree().create_timer(period * float(i) / float(_rings.size()), false).timeout.connect(start)


func _finish() -> void:
	_ending = true
	if noise_id >= 0:
		NoiseSources.stop(noise_id)
		noise_id = -1
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)


func _play(sfx: StringName) -> void:
	var am: Node = get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", sfx, global_position, -6.0)


func _draw_ring(r: Node2D) -> void:
	var rad: float = Balance.get_float("crafting", "decoy_ring_radius", 46.0)
	r.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	r.draw_arc(Vector2.ZERO, rad + 2.0, 0.0, TAU, 48, Color(0.12, 0.05, 0.02, 0.55), 7.0, true)
	r.draw_arc(Vector2.ZERO, rad, 0.0, TAU, 48, Color(1.0, 0.9, 0.4, 1.0), 4.5, true)
	r.draw_arc(Vector2.ZERO, rad - 6.0, 0.0, TAU, 48, Color(1.0, 0.5, 0.15, 0.7), 2.5, true)


func _draw_body() -> void:
	draw_shape(_body)


## Boîtier du leurre (au sol, en main ou en vol), centré sur l'origine.
static func draw_shape(c: CanvasItem, light: Color = Color(1.0, 0.8, 0.25)) -> void:
	var dark := Color(0.06, 0.07, 0.1)
	c.draw_set_transform(Vector2(0, 7), 0.0, Vector2(1.0, 0.45))
	c.draw_circle(Vector2.ZERO, 12.0, Color(0.05, 0.07, 0.15, 0.5), true, -1.0, true)
	c.draw_set_transform(Vector2.ZERO)
	c.draw_rect(Rect2(-10, -9, 20, 16), dark)
	c.draw_rect(Rect2(-9, -8, 18, 14), Color(0.55, 0.36, 0.2))
	c.draw_rect(Rect2(-9, -8, 18, 4), Color(0.78, 0.58, 0.36))
	c.draw_circle(Vector2(-2.5, 0), 4.2, Color(0.16, 0.16, 0.18), true, -1.0, true)
	c.draw_circle(Vector2(-2.5, 0), 2.2, Color(0.35, 0.35, 0.38), true, -1.0, true)
	c.draw_circle(Vector2(5, -3), 1.8, light, true, -1.0, true)
	c.draw_rect(Rect2(-9, -8, 18, 14), dark, false, 1.4)
	c.draw_line(Vector2(6, -8), Vector2(10, -18), dark, 1.6, true)
	c.draw_circle(Vector2(10, -18), 2.0, Color(0.95, 0.3, 0.2), true, -1.0, true)
