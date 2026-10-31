class_name PerfOverlay
extends CanvasLayer
## Mesure de fluidité sur l'appareil (perf/fluidite), versions de test uniquement (DevMode) :
## images par seconde, temps d'image (moyenne, p99 et pire sur les 2 dernières secondes), saccades
## (images > [perf_overlay] hitch_ms, sur 10 s), temps de process et de physique, draw calls,
## résolution de rendu, cible de FrameRate, Engine.max_fps, fréquence de l'écran, synchro verticale,
## et courbe des temps d'image (ligne verte : 16,7 ms, orange : 33,3 ms).
## Bascule : F5, ou appui à TROIS doigts n'importe où (téléphone). Au-dessus de tous les écrans.
## Créé par GameState seulement si DevMode.is_available() (jamais en version publiée).

const LAYER := 120
const HISTORY := 240

var label: Label = null
var graph: Graph = null
var _box: PanelContainer = null
var _times: PackedFloat32Array = PackedFloat32Array()
var _hitches: Array[int] = []        ## horodatages (ms) des saccades
var _last_us: int = 0
var _refresh_left: float = 0.0
var _hitch_ms: float = 25.0


## Courbe des temps d'image (dessinée seulement quand l'overlay est affiché).
class Graph extends Control:
	var overlay: PerfOverlay = null

	func _draw() -> void:
		if overlay == null:
			return
		var t := overlay._times
		var h := size.y
		var scale := h / 50.0  # 50 ms en haut
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.6))
		draw_line(Vector2(0, h - 16.7 * scale), Vector2(size.x, h - 16.7 * scale), Color(0.3, 0.9, 0.4, 0.6), 1.0)
		draw_line(Vector2(0, h - 33.3 * scale), Vector2(size.x, h - 33.3 * scale), Color(1.0, 0.6, 0.2, 0.6), 1.0)
		if t.size() < 2:
			return
		var dx := size.x / float(HISTORY - 1)
		var pts := PackedVector2Array()
		var x0 := size.x - dx * float(t.size() - 1)
		for i: int in t.size():
			pts.append(Vector2(x0 + dx * i, h - minf(t[i], 50.0) * scale))
		draw_polyline(pts, Color(0.72, 0.6, 1.0, 0.95), 1.5)


## Crée le calque sous `parent` si le build le permet ; null sinon.
static func attach(parent: Node) -> PerfOverlay:
	if not DevMode.is_available():
		return null
	var p := PerfOverlay.new()
	p.name = "PerfOverlay"
	parent.add_child(p)
	return p


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_hitch_ms = Balance.get_float("perf_overlay", "hitch_ms", 25.0)
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.024, 0.027, 0.05, 0.78)
	st.set_content_margin_all(8)
	_box.add_theme_stylebox_override("panel", st)
	_box.position = Vector2(16, 96)  # sous la jauge de vie
	add_child(_box)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(col)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := LabelSettings.new()
	ls.font_size = 15
	ls.font_color = Color.WHITE
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0, 0.8)
	label.label_settings = ls
	col.add_child(label)
	graph = Graph.new()
	graph.overlay = self
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph.custom_minimum_size = Vector2(300, 70)
	col.add_child(graph)
	set_shown(bool(Balance.get_value("perf_overlay", "visible_at_start", false)))


func set_shown(on: bool) -> void:
	visible = on
	_box.visible = on
	_times.clear()
	_hitches.clear()
	_last_us = 0
	set_process(on)


func toggle() -> void:
	set_shown(not visible)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).physical_keycode == KEY_F5:
		toggle()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed \
			and (event as InputEventScreenTouch).index == 2:
		toggle()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		var ms := float(now - _last_us) / 1000.0
		_times.append(ms)
		if _times.size() > HISTORY:
			_times = _times.slice(_times.size() - HISTORY)
		if ms >= _hitch_ms:
			_hitches.append(Time.get_ticks_msec())
	_last_us = now
	graph.queue_redraw()
	_refresh_left -= delta / maxf(Engine.time_scale, 0.01)
	if _refresh_left <= 0.0:
		_refresh_left = 0.25
		label.text = build_text()


## Texte de l'overlay (public pour les tests).
func build_text() -> String:
	var cutoff := Time.get_ticks_msec() - 10000
	while not _hitches.is_empty() and _hitches[0] < cutoff:
		_hitches.pop_front()
	var recent: Array = Array(_times.slice(maxi(_times.size() - 120, 0)))
	var mean := 0.0
	for x: float in recent:
		mean += x
	mean = mean / float(recent.size()) if not recent.is_empty() else 0.0
	recent.sort()
	var p99: float = recent[mini(int(recent.size() * 0.99), recent.size() - 1)] if not recent.is_empty() else 0.0
	var worst: float = recent.back() if not recent.is_empty() else 0.0
	var vs := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	var lines: PackedStringArray = []
	lines.append("%d i/s · %.1f ms moy · p99 %.1f · pire %.1f" % [Engine.get_frames_per_second(), mean, p99, worst])
	lines.append("Saccades > %d ms (10 s) : %d" % [int(_hitch_ms), _hitches.size()])
	lines.append("Process %.1f ms · physique %.1f ms" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
	lines.append("Draw calls %d · nœuds %d · tex %d Mo" % [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0)])
	var vp := get_viewport()
	var ws := DisplayServer.window_get_size()
	lines.append("Rendu %dx%d (base %dx%d)" % [ws.x, ws.y, int(vp.get_visible_rect().size.x), int(vp.get_visible_rect().size.y)])
	lines.append("Cible %d i/s (%s) · max_fps %d · écran %.0f Hz · synchro %s" % [FrameRate.target_for(FrameRate.saved_mode()),
		FrameRate.saved_mode(), Engine.max_fps, FrameRate.screen_refresh(), "oui" if vs else "non"])
	lines.append("%s · %s" % [RenderingServer.get_current_rendering_method(), "debug" if OS.is_debug_build() else "release"])
	return "\n".join(lines)
