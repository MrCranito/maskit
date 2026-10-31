extends Node
## Enregistreur du banc de profilage (perf_bench_main.gd) : temps d'image, temps de process, de
## physique et de rendu, draw calls, nœuds, objets, mémoire, nœuds créés par image (par classe),
## pics (images ≥ spike_ms ou ≥ 2,5 × la médiane glissante) avec ce qui s'est passé pendant l'image.
## Démarre quand le bot joue (raid chargé), mesure `frames` images puis écrit le JSON et quitte.

var bot: Node = null
var frames_wanted: int = 1800
var out_path: String = ""
var disable_classes: PackedStringArray = PackedStringArray()
var force_fire: bool = false
var spike_ms: float = 25.0

var _started: bool = false
var _last_us: int = 0
var _dt: PackedFloat32Array = PackedFloat32Array()
var _proc: PackedFloat32Array = PackedFloat32Array()
var _phys: PackedFloat32Array = PackedFloat32Array()
var _rend: PackedFloat32Array = PackedFloat32Array()
var _gpu: PackedFloat32Array = PackedFloat32Array()
var _draw: PackedInt32Array = PackedInt32Array()
var _nodes: PackedInt32Array = PackedInt32Array()
var _added_frame: Dictionary = {}     ## classe → nombre (image courante)
var _added_total: Dictionary = {}     ## classe → nombre (toute la mesure)
var _added_count: int = 0
var _removed_count: int = 0
var _spikes: Array = []
var _obj0: int = 0
var _mem0: float = 0.0
var _tex0: float = 0.0
var _tex_prev: float = 0.0
var _t0_ms: int = 0
var _vp_rid: RID
var mark_frames: bool = false
var _early: Node = null
var _phys_start_us: int = 0
var _phys_us: int = 0
var _proc_start_us: int = 0


## Nœud qui passe en premier (process et physique) : début des chronos internes.
class Early extends Node:
	var rec: Node = null

	func _ready() -> void:
		process_priority = -100000
		process_physics_priority = -100000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_d: float) -> void:
		rec.set("_proc_start_us", Time.get_ticks_usec())

	func _physics_process(_d: float) -> void:
		rec.set("_phys_start_us", Time.get_ticks_usec())


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		var v := kv[1] if kv.size() > 1 else ""
		match kv[0]:
			"frames": frames_wanted = maxi(int(v), 60)
			"out": out_path = v
			"disable": disable_classes = v.split(",", false)
			"fire": force_fire = true
			"spike-ms": spike_ms = float(v)
			"mark": mark_frames = true
	process_priority = 100000
	process_physics_priority = 100000
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	_early = Early.new()
	_early.set("rec", self)
	get_parent().add_child.call_deferred(_early)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(func(_n: Node) -> void: _removed_count += 1)


func _key(n: Node) -> String:
	var s: Script = n.get_script() as Script
	if s != null:
		var g := String(s.get_global_name())
		return g if not g.is_empty() else s.resource_path.get_file()
	return n.get_class()


func _on_node_added(n: Node) -> void:
	if not _started:
		return
	_added_count += 1
	var k := _key(n)
	_added_frame[k] = int(_added_frame.get(k, 0)) + 1
	_added_total[k] = int(_added_total.get(k, 0)) + 1
	if not disable_classes.is_empty():
		_maybe_disable.call_deferred(n)


func _maybe_disable(n: Node) -> void:
	if not is_instance_valid(n) or not disable_classes.has(_key(n)):
		return
	n.process_mode = Node.PROCESS_MODE_DISABLED
	if n is CanvasItem:
		(n as CanvasItem).visible = false
	elif n is CanvasLayer:
		(n as CanvasLayer).visible = false


func _disable_existing(n: Node) -> void:
	if disable_classes.has(_key(n)):
		_maybe_disable(n)
	for c in n.get_children():
		_disable_existing(c)


func _physics_process(_delta: float) -> void:
	if _phys_start_us > 0:
		_phys_us += Time.get_ticks_usec() - _phys_start_us
		_phys_start_us = 0
	# Tir continu forcé : si le bot ne vise rien, il tire droit devant (direction de marche).
	if not _started or not force_fire or bot == null:
		return
	var aim: Object = bot.get("aim_stick")
	var mv: Object = bot.get("move_stick")
	if aim != null and mv != null and (aim.get("output") as Vector2) == Vector2.ZERO:
		var m: Vector2 = mv.get("output")
		aim.set("output", m.normalized() if m != Vector2.ZERO else Vector2.RIGHT)


func _process(_delta: float) -> void:
	Engine.max_fps = 0
	if not _started:
		if bot != null and bool(bot.get("_playing")):
			_started = true
			_last_us = Time.get_ticks_usec()
			_t0_ms = Time.get_ticks_msec()
			_obj0 = int(Performance.get_monitor(Performance.OBJECT_COUNT))
			_mem0 = Performance.get_monitor(Performance.MEMORY_STATIC)
			_tex0 = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
			_tex_prev = _tex0
			if not disable_classes.is_empty():
				_disable_existing(get_tree().root)
		return
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_us) / 1000.0
	_last_us = now
	# Chronos internes : _process de tous les nœuds (premier → dernier), pas(s) physique(s) de l'image.
	var p := float(now - _proc_start_us) / 1000.0 if _proc_start_us > 0 else 0.0
	var ph := float(_phys_us) / 1000.0
	_phys_us = 0
	if mark_frames:
		print("PB_F ", _dt.size() + 1)
	var r := RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) + RenderingServer.get_frame_setup_time_cpu()
	var g := RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var nc := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	_dt.append(dt)
	_proc.append(p)
	_phys.append(ph)
	_rend.append(r)
	_gpu.append(g)
	_draw.append(dc)
	_nodes.append(nc)
	var n := _dt.size()
	var med := _median_recent(60)
	if n > 3 and (dt >= spike_ms or dt >= med * 2.5 and dt >= 12.0):
		var top: Array = []
		for k: String in _added_frame:
			top.append([k, _added_frame[k]])
		top.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		_spikes.append({"frame": n, "t_game": snappedf(n / 60.0, 0.01), "ms": snappedf(dt, 0.01),
			"process_ms": snappedf(p, 0.01), "physics_ms": snappedf(ph, 0.01), "render_ms": snappedf(r, 0.01),
			"tex_delta_kb": snappedf((tex - _tex_prev) / 1024.0, 0.1), "nodes": nc,
			"added": top.slice(0, 6), "floor": int(bot.get("raid").get("current_floor")) if bot.get("raid") != null else -1})
	_tex_prev = tex
	_added_frame.clear()
	if n >= frames_wanted or bool(bot.get("_done")):
		_finish()


func _median_recent(k: int) -> float:
	var n := _dt.size()
	if n < 5:
		return 1000.0
	var a: Array = Array(_dt.slice(maxi(n - 1 - k, 0), n - 1))
	a.sort()
	return float(a[a.size() / 2])


static func _stats(arr: PackedFloat32Array) -> Dictionary:
	if arr.is_empty():
		return {}
	var a: Array = Array(arr)
	a.sort()
	var s := 0.0
	for x: float in a:
		s += x
	var n := a.size()
	return {"mean": snappedf(s / n, 0.001), "p50": snappedf(a[n / 2], 0.001),
		"p95": snappedf(a[mini(int(n * 0.95), n - 1)], 0.001), "p99": snappedf(a[mini(int(n * 0.99), n - 1)], 0.001),
		"max": snappedf(a[n - 1], 0.001)}


func _finish() -> void:
	set_process(false)
	var over := func(th: float) -> int:
		var c := 0
		for x: float in _dt:
			if x >= th:
				c += 1
		return c
	var draws := PackedFloat32Array()
	for x: int in _draw:
		draws.append(float(x))
	var nodes := PackedFloat32Array()
	for x: int in _nodes:
		nodes.append(float(x))
	var top_added: Array = []
	for k: String in _added_total:
		top_added.append([k, _added_total[k]])
	top_added.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	_spikes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["ms"] > b["ms"])
	var secs := maxf(_dt.size() / 60.0, 0.001)
	var res := {
		"map": bot.get("map_id"), "seed": bot.get("seed_value"), "profile": bot.get("profile_name"),
		"disable": Array(disable_classes), "frames": _dt.size(), "wall_s": snappedf((Time.get_ticks_msec() - _t0_ms) / 1000.0, 0.01),
		"window": DisplayServer.window_get_size(), "renderer": RenderingServer.get_current_rendering_method(),
		"video": RenderingServer.get_video_adapter_name(),
		"frame_ms": _stats(_dt), "process_ms": _stats(_proc), "physics_ms": _stats(_phys),
		"render_cpu_ms": _stats(_rend), "render_gpu_ms": _stats(_gpu),
		"draw_calls": _stats(draws), "nodes": _stats(nodes),
		"frames_over_16ms": over.call(16.7), "frames_over_25ms": over.call(25.0), "frames_over_33ms": over.call(33.3),
		"frames_over_50ms": over.call(50.0),
		"nodes_added_per_s": snappedf(_added_count / secs, 0.1), "nodes_removed_per_s": snappedf(_removed_count / secs, 0.1),
		"nodes_added_top": top_added.slice(0, 15),
		"objects_delta": int(Performance.get_monitor(Performance.OBJECT_COUNT)) - _obj0,
		"static_mem_delta_mb": snappedf((Performance.get_monitor(Performance.MEMORY_STATIC) - _mem0) / 1048576.0, 0.01),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_delta_mb": snappedf((Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) - _tex0) / 1048576.0, 0.1),
		"spikes": _spikes.slice(0, 20), "spike_count": _spikes.size(),
		"bot_outcome": bot.get("outcome"),
		"series_frame_ms": Array(_dt).map(func(x: float) -> float: return snappedf(x, 0.01)),
	}
	var txt := JSON.stringify(res, "  ")
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(txt)
			f.close()
	print("PERF_BENCH ", JSON.stringify({"map": res["map"], "frame_ms": res["frame_ms"], "process_ms": res["process_ms"],
		"physics_ms": res["physics_ms"], "render_cpu_ms": res["render_cpu_ms"], "draw_calls": res["draw_calls"]["mean"],
		"over33": res["frames_over_33ms"], "spikes": res["spike_count"]}))
	get_tree().quit(0)
