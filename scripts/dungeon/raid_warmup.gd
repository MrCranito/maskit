class_name RaidWarmup
extends Node
## Préchauffe au chargement du raid (perf/fluidite) : rien de lourd ne doit se charger en
## synchrone pendant le jeu. Sans elle, le premier butin chargeait d'un bloc les ~145 objets
## de data/items et leurs icônes (LootDB) : gel de 0,3 à 1 s sur PC, plusieurs secondes sur mobile.
##  1. En arrière-plan (ResourceLoader.load_threaded_request) : objets (data/items), sons (SFX
##     de l'AudioManager), scène d'ennemi. Sous le rendu factice (--headless : tests, bot, serveur)
##     le chargement en fil n'est pas sûr pour les textures (voir PrerenderBackdrop
##     .threaded_loading_safe) : objets chargés tout de suite, en synchrone.
##  2. Une fois les objets chargés : LootDB rempli (accès instantané), puis icônes réduites
##     (LootVisuals.item_icon / weapon_icon, mipmaps) préparées [warmup] icons_per_frame par image.
##  3. Shaders : chaque shader des effets ponctuels (mort, flash de coup, skins, occultation, verre
##     dépoli) dessiné une image sur un carré de 2 px : compilé avant sa première vraie apparition.
## Les ressources préchargées restent référencées par `keep` jusqu'à la fin du raid.
## Réglages : [warmup] de data/balance.cfg.

const ITEMS_DIR := "res://data/items/"
const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
## Shaders compilés à l'avance (effets qui n'apparaissent qu'en cours de partie).
const SHADERS: Array[String] = [
	"res://assets/shaders/death_screen.gdshader",
	"res://assets/shaders/hit_flash.gdshader",
	"res://assets/shaders/enemy_flash.gdshader",
	"res://assets/shaders/weapon_skin.gdshader",
	"res://assets/shaders/prerender_occluder.gdshader",
	"res://assets/shaders/frosted_panel.gdshader",
]

## Ressources gardées en mémoire pendant le raid (évite un rechargement au prochain usage).
var keep: Array = []
var _pending: Array[String] = []
var _audio: Dictionary = {}          ## chemin → true (sons demandés)
var _items_done: bool = false
var _icons: Array = []               ## objets / armes dont l'icône reste à préparer
var _icons_per_frame: int = 2
var _shader_layer: CanvasLayer = null
var _shader_frames: int = 0
var _threaded: bool = true
var _started_ms: int = 0
var _timeout_s: float = 20.0


## Démarre la préchauffe sous `parent` (le raid). Sans effet si [warmup] enabled = false.
static func start(parent: Node) -> RaidWarmup:
	if not bool(Balance.get_value("warmup", "enabled", true)):
		LootDB.all_items()
		return null
	var w := RaidWarmup.new()
	w.name = "RaidWarmup"
	parent.add_child(w)
	return w


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_icons_per_frame = maxi(int(Balance.get_value("warmup", "icons_per_frame", 2)), 1)
	_timeout_s = Balance.get_float("warmup", "timeout", 20.0)
	_threaded = PrerenderBackdrop.threaded_loading_safe()
	_started_ms = Time.get_ticks_msec()
	if not _threaded:
		# Rendu factice : chargement synchrone tout de suite (pendant le chargement du raid).
		LootDB.all_items()
		_items_done = true
	else:
		for f: String in LootDB._list_resources(ITEMS_DIR):
			_request(ITEMS_DIR + f)
	_request(ENEMY_SCENE)
	var am: Node = get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("all_sfx_paths"):
		for p: String in am.call("all_sfx_paths"):
			if not _audio.has(p):
				_audio[p] = true
				_request(p)
	if _threaded and bool(Balance.get_value("warmup", "shaders", true)):
		_build_shader_quads()


func _request(path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	if ResourceLoader.has_cached(path):
		_store(path, ResourceLoader.get_cached_ref(path))
		return
	if _threaded:
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)
	else:
		_store(path, load(path))


func _store(path: String, r: Resource) -> void:
	if r == null:
		return
	keep.append(r)
	if _audio.has(path) and r is AudioStream:
		var am: Node = get_node_or_null(^"/root/AudioManager")
		if am != null and am.has_method("cache_stream"):
			am.call("cache_stream", path, r)


func is_done() -> bool:
	return _pending.is_empty() and _items_done and _icons.is_empty() and _shader_layer == null


func _process(_delta: float) -> void:
	# 1. Chargements en arrière-plan terminés.
	for i: int in range(_pending.size() - 1, -1, -1):
		var p := _pending[i]
		var st := ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_store(p, ResourceLoader.load_threaded_get(p))
			_pending.remove_at(i)
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending.remove_at(i)
	var timed_out := Time.get_ticks_msec() - _started_ms > int(_timeout_s * 1000.0)
	# 2. Objets prêts : LootDB rempli (cache chaud), puis icônes.
	if not _items_done and (timed_out or not _pending.any(func(p: String) -> bool: return p.begins_with(ITEMS_DIR))):
		_items_done = true
		_icons.append_array(LootDB.all_items())
		_icons.append_array(WeaponCatalog.all())
	for _i: int in _icons_per_frame:
		if _icons.is_empty():
			break
		var o: Variant = _icons.pop_back()
		if o is ItemData:
			LootVisuals.item_icon(o as ItemData)
		elif o is WeaponData:
			LootVisuals.weapon_icon(o as WeaponData)
	# 3. Carrés de préchauffe des shaders : retirés après quelques images dessinées.
	if _shader_layer != null:
		_shader_frames += 1
		if _shader_frames > 3:
			_shader_layer.queue_free()
			_shader_layer = null
	if is_done() or timed_out and _pending.is_empty():
		set_process(false)


func _build_shader_quads() -> void:
	_shader_layer = CanvasLayer.new()
	_shader_layer.name = "ShaderWarmup"
	_shader_layer.layer = -100  # sous tout le reste
	add_child(_shader_layer)
	var x := 0.0
	for path: String in SHADERS:
		var sh := load(path) as Shader
		if sh == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = sh
		var r := ColorRect.new()
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.position = Vector2(x, 0.0)
		r.size = Vector2(2.0, 2.0)
		r.material = mat
		_shader_layer.add_child(r)
		x += 2.0
