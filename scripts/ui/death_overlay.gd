class_name DeathOverlay
extends CanvasLayer
## Séquence de mort (créée par Raid à EventBus.player_died, avant l'écran de fin), pendant
## [death] outro_time secondes réelles :
##   - impact : flash rouge, secousse, bref ralenti (Engine.time_scale, pas en coop) ;
##   - le monde se désature et s'assombrit (shader écran), sauf un halo autour du héros ;
##     vignette rouge sur les bords ;
##   - le héros s'effondre (chute sur le côté, rebond) et une flaque sombre s'étale sous lui ;
##   - la caméra se rapproche ;
##   - bandeau encre en biais, gros titre « ÉLIMINÉ » (Anton) et « par <tueur> ».
## Solo : le calque reste sous l'écran de fin. Coop (spectateur) : il s'efface ensuite.
## Pendant de ExtractionOverlay ; réglages : balance.cfg [death].

const SHADER: Shader = preload("res://assets/shaders/death_screen.gdshader")
## Rouge de la mort (vignette, flash, accent du bandeau, nom du tueur).
const RED := Color(1.0, 0.3, 0.38)
const RED_DEEP := Color(0.62, 0.04, 0.09)
const INK := Color(0.024, 0.027, 0.05, 0.78)

var player: Node2D = null
var killer: String = ""
var _screen: ColorRect = null
var _mat: ShaderMaterial = null
var _flash: ColorRect = null
var _band: Control = null
var _title: Label = null
var _sub: HBoxContainer = null
var _amount: float = 0.0
var _band_t: float = 0.0
var _cam: Camera2D = null
var _cam_zoom: Vector2 = Vector2.ONE
var _slowmo: bool = false


## Durée de la séquence avant l'écran de fin ([death] outro_time, 0 = écran de fin immédiat).
static func outro_time() -> float:
	return maxf(Balance.get_float("death", "outro_time", 2.4), 0.0)


## Crée la séquence sous `parent` (le raid) pour `p` (le joueur abattu) et la lance.
static func play(parent: Node, p: Node2D) -> DeathOverlay:
	var o := DeathOverlay.new()
	o.player = p
	var k: Variant = p.get(&"last_hit_by") if is_instance_valid(p) else null
	o.killer = str(k) if k != null else ""
	parent.add_child(o)
	return o


func _ready() -> void:
	name = "DeathOverlay"
	layer = int(Balance.get_value("death", "overlay_layer", 35))
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_run()


func _exit_tree() -> void:
	_end_slowmo()


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Monde désaturé / assombri (lit l'écran rendu sous ce calque, HUD compris).
	_screen = ColorRect.new()
	_screen.name = "Screen"
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"darken", Balance.get_float("death", "darken", 0.6))
	_mat.set_shader_parameter(&"vignette", Balance.get_float("death", "vignette", 0.75))
	_mat.set_shader_parameter(&"focus_radius", Balance.get_float("death", "focus_radius", 0.14))
	_mat.set_shader_parameter(&"vignette_color", RED_DEEP)
	_mat.set_shader_parameter(&"amount", 0.0)
	_screen.material = _mat
	root.add_child(_screen)
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.color = Color(RED, 0.0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	# Bandeau encre en biais, liseré rouge (direction D : grand bandeau translucide incliné).
	_band = Control.new()
	_band.name = "Band"
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.set_anchors_preset(Control.PRESET_FULL_RECT)
	_band.draw.connect(_draw_band)
	root.add_child(_band)
	var col := VBoxContainer.new()
	col.name = "Titles"
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	# Titres un peu au-dessus du milieu : le héros (centre écran) reste visible dessous.
	var off: float = Balance.get_float("death", "title_offset", -90.0)
	col.offset_top = off
	col.offset_bottom = off
	_title = MenuKit.title("ÉLIMINÉ", int(Balance.get_value("death", "title_size", 112)), MenuKit.TEXT)
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 12)
	_title.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.02, 0.85))
	_title.modulate.a = 0.0
	col.add_child(_title)
	_sub = HBoxContainer.new()
	_sub.name = "Killer"
	_sub.alignment = BoxContainer.ALIGNMENT_CENTER
	_sub.add_theme_constant_override("separation", 10)
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.modulate.a = 0.0
	col.add_child(_sub)
	if killer.is_empty():
		_sub.add_child(MenuKit.label("Le raid est perdu", 26, MenuKit.TEXT_DIM, MenuKit.nunito(500), 6))
	else:
		_sub.add_child(MenuKit.label("par", 26, MenuKit.TEXT_DIM, MenuKit.nunito(500), 6))
		var k := MenuKit.label(killer.to_upper(), 34, RED, MenuKit.display(), 8)
		k.name = "KillerName"
		_sub.add_child(k)


func _draw_band() -> void:
	if _band_t <= 0.0:
		return
	var s := _band.size
	var cy: float = s.y * 0.5 + Balance.get_float("death", "title_offset", -90.0) + 4.0
	var h: float = Balance.get_float("death", "band_height", 190.0)
	var k: float = h * 0.22   # biais
	var w: float = s.x * _band_t
	var x0: float = (s.x - w) * 0.5
	var pts := PackedVector2Array([Vector2(x0 + k, cy - h * 0.5), Vector2(x0 + w + k, cy - h * 0.5),
		Vector2(x0 + w - k, cy + h * 0.5), Vector2(x0 - k, cy + h * 0.5)])
	_band.draw_colored_polygon(pts, INK)
	_band.draw_line(pts[0], pts[1], Color(RED, 0.9), 3.0)
	_band.draw_line(pts[3], pts[2], Color(RED, 0.5), 2.0)


func _set_amount(v: float) -> void:
	_amount = v
	if _mat != null:
		_mat.set_shader_parameter(&"amount", v)


func _set_band(v: float) -> void:
	_band_t = v
	_band.queue_redraw()


func _process(_delta: float) -> void:
	# Halo net qui suit le héros à l'écran (caméra qui zoome).
	if _mat == null:
		return
	var vp := get_viewport()
	var vs: Vector2 = vp.get_visible_rect().size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	_mat.set_shader_parameter(&"aspect", vs.x / vs.y)
	if is_instance_valid(player) and player.is_inside_tree():
		var sp: Vector2 = player.get_global_transform_with_canvas().origin
		_mat.set_shader_parameter(&"focus", sp / vs)


## Tween en temps réel (insensible au ralenti), poursuivi même en pause.
func _tw() -> Tween:
	return create_tween().set_ignore_time_scale(true).set_process_mode(Tween.TWEEN_PROCESS_IDLE)


func _run() -> void:
	var d: float = maxf(outro_time(), 0.3)
	# Impact : flash rouge, secousse.
	_flash.color.a = Balance.get_float("death", "flash_alpha", 0.45)
	_tw().tween_property(_flash, "color:a", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	if is_instance_valid(player) and player.has_method(&"add_shake"):
		player.call(&"add_shake", Balance.get_float("death", "shake", 9.0), 0.3)
	_start_slowmo()
	# Monde qui s'éteint.
	_tw().tween_method(_set_amount, 0.0, 1.0, d * 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fall()
	# Caméra qui se rapproche.
	_cam = get_viewport().get_camera_2d()
	if _cam != null:
		_cam_zoom = _cam.zoom
		_tw().tween_property(_cam, "zoom", _cam_zoom * Balance.get_float("death", "zoom", 1.3), d) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Bandeau puis titre qui claque, puis le tueur.
	var tb := _tw()
	tb.tween_interval(d * 0.16)
	tb.tween_method(_set_band, 0.0, 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var tt := _tw()
	tt.tween_interval(d * 0.2)
	tt.tween_callback(func() -> void:
		_title.pivot_offset = _title.size * 0.5
		_title.scale = Vector2(1.7, 1.7)
		_title.modulate = Color(RED.lightened(0.4), 0.0))
	tt.set_parallel(true)
	tt.tween_property(_title, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(_title, "modulate", Color.WHITE, 0.3)
	var ts := _tw()
	ts.tween_interval(d * 0.38)
	ts.tween_property(_sub, "modulate:a", 1.0, 0.3)
	# Fin : retour à la vitesse normale ; coop (spectateur), le calque s'efface.
	var te := _tw()
	te.tween_interval(d)
	te.tween_callback(_on_outro_done)


func _start_slowmo() -> void:
	var sc: float = Balance.get_float("death", "slowmo_scale", 0.3)
	var t: float = Balance.get_float("death", "slowmo_time", 0.7)
	if NetHooks.active or sc >= 1.0 or t <= 0.0:
		return
	_slowmo = true
	Engine.time_scale = clampf(sc, 0.05, 1.0)
	var tw := _tw()
	tw.tween_interval(t * 0.6)
	tw.tween_method(func(v: float) -> void:
		if _slowmo:
			Engine.time_scale = v, Engine.time_scale, 1.0, t * 0.4)
	tw.tween_callback(_end_slowmo)


func _end_slowmo() -> void:
	if _slowmo:
		_slowmo = false
		Engine.time_scale = 1.0


## Le héros s'effondre sur le côté (opposé à la visée), petit rebond, flaque sous lui.
func _fall() -> void:
	if not is_instance_valid(player):
		return
	var vis: Node2D = player.get(&"visual") as Node2D if player.get(&"visual") is Node2D else null
	if vis == null:
		return
	var aim: Variant = player.get(&"aim_direction")
	var side: float = -1.0 if aim is Vector2 and (aim as Vector2).x > 0.0 else 1.0
	var t: float = Balance.get_float("death", "fall_time", 0.45)
	var ang: float = deg_to_rad(Balance.get_float("death", "fall_angle", 88.0)) * side
	var base := vis.position
	var tw := _tw().set_parallel(true)
	# Recul vers le haut puis chute : rotation avec léger dépassement (TRANS_BACK).
	tw.tween_property(vis, "rotation", ang, t).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(vis, "position", base + Vector2(side * 14.0, 10.0), t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var sq := _tw()
	sq.tween_property(vis, "scale", vis.scale * Vector2(1.08, 0.92), t * 0.8)
	sq.tween_property(vis, "scale", vis.scale, 0.18)
	# Flaque sombre qui s'étale sous le corps (reste avec le cadavre).
	var pool := Node2D.new()
	pool.name = "DeathPool"
	pool.show_behind_parent = true
	pool.z_index = -1
	pool.position = Vector2(side * 18.0, 8.0)
	pool.scale = Vector2(0.15, 0.15)
	var r: float = Balance.get_float("death", "pool_radius", 34.0)
	pool.draw.connect(func() -> void:
		var pts := PackedVector2Array()
		for i in 20:
			var a := TAU * float(i) / 20.0
			var wob := 1.0 + 0.14 * sin(a * 3.0 + 1.3) + 0.06 * sin(a * 7.0)
			pts.append(Vector2(cos(a) * r * 1.25 * wob, sin(a) * r * 0.6 * wob))
		pool.draw_colored_polygon(pts, Color(0.2, 0.0, 0.03, 0.42))
		for i in pts.size():
			pts[i] *= 0.62
		pool.draw_colored_polygon(pts, Color(0.16, 0.0, 0.02, 0.4)))
	player.add_child(pool)
	var tp := _tw()
	tp.tween_interval(t * 0.6)
	tp.tween_property(pool, "scale", Vector2.ONE, 1.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _on_outro_done() -> void:
	_end_slowmo()
	# L'écran de fin reprend le titre : le bandeau et les textes s'effacent, le monde reste sombre.
	var tf := _tw().set_parallel(true)
	tf.tween_property(_title, "modulate:a", 0.0, 0.2)
	tf.tween_property(_sub, "modulate:a", 0.0, 0.2)
	tf.tween_method(_set_band, _band_t, 0.0, 0.2)
	if not NetHooks.active:
		return
	var tw := _tw().set_parallel(true)
	tw.tween_method(_set_amount, _amount, 0.0, 0.5)
	tw.tween_property(get_node(^"Root"), "modulate:a", 0.0, 0.5)
	if _cam != null and is_instance_valid(_cam):
		tw.tween_property(_cam, "zoom", _cam_zoom, 0.5)
	tw.chain().tween_callback(queue_free)


## Textes affichés (tests) : titre et ligne du tueur.
func get_title_text() -> String:
	return _title.text if _title != null else ""


func get_killer_text() -> String:
	var parts: PackedStringArray = []
	if _sub != null:
		for c: Node in _sub.get_children():
			if c is Label:
				parts.append((c as Label).text)
	return " ".join(parts)


func get_amount() -> float:
	return _amount
