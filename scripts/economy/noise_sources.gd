class_name NoiseSources
extends RefCounted
## Sources de bruit hors joueur (leurre, plus tard : alarmes, objets lancés…).
##   NoiseSources.emit(pos, level, duration, radius) -> id : la source « crie » pendant `duration` s.
## Modèle « poussé » (aucune modification de l'IA nécessaire) : un petit nœud pilote (créé à la
## demande, supprimé quand il n'y a plus de source) parcourt toutes les `tick` s les ennemis du
## groupe `enemies` dans le rayon et leur donne un stimulus vers la source :
##   - ennemi en combat (alerte, poursuite, attaque…) : ignoré (il a mieux à faire) ;
##   - sinon : jauge de reconnaissance relevée au palier de suspicion (jamais jusqu'à l'alerte),
##     stimulus = position de la source → état Investigate : il marche vers le leurre, regarde
##     autour, puis abandonne (Return). Un mur atténue le bruit (hearing_wall_factor de l'ennemi).
## Modèle « tiré » (optionnel, pour l'IA) : NoiseSources.loudest_at(pos, rayon) → {pos, heard}.
## Équilibrage : balance.cfg [crafting] decoy_*.

const SECTION := "crafting"

class Source:
	var id: int = 0
	var position: Vector2 = Vector2.ZERO
	var level: float = 1.0
	var radius: float = 500.0
	var until_msec: int = 0

static var _sources: Array[Source] = []
static var _next_id: int = 1
static var _driver: Node = null


## Ajoute une source de bruit. radius < 0 : [crafting] decoy_radius. Renvoie son id.
static func emit(pos: Vector2, level: float, duration: float, radius: float = -1.0) -> int:
	var s := Source.new()
	s.id = _next_id
	_next_id += 1
	s.position = pos
	s.level = clampf(level, 0.0, 2.0)
	s.radius = radius if radius > 0.0 else float(RecipeBook._balance(SECTION, "decoy_radius", 520.0))
	s.until_msec = Time.get_ticks_msec() + int(maxf(duration, 0.0) * 1000.0)
	_sources.append(s)
	_ensure_driver()
	return s.id


## Coupe une source (leurre détruit).
static func stop(id: int) -> void:
	for i in range(_sources.size() - 1, -1, -1):
		if _sources[i].id == id:
			_sources.remove_at(i)


## Déplace une source (leurre qui roule encore).
static func move(id: int, pos: Vector2) -> void:
	for s: Source in _sources:
		if s.id == id:
			s.position = pos


static func clear() -> void:
	_sources.clear()
	if is_instance_valid(_driver):
		_driver.queue_free()
	_driver = null


## Sources encore actives (les expirées sont retirées).
static func active() -> Array[Source]:
	var now := Time.get_ticks_msec()
	for i in range(_sources.size() - 1, -1, -1):
		if _sources[i].until_msec <= now:
			_sources.remove_at(i)
	return _sources


static func count() -> int:
	return active().size()


## Source la plus audible depuis `pos` (sans tenir compte des murs) : {} si aucune,
## sinon {"id", "pos", "heard"} avec heard = level × (1 - d / rayon).
static func loudest_at(pos: Vector2, max_radius: float = INF) -> Dictionary:
	var best := {}
	var best_h := 0.0
	for s: Source in active():
		var r := minf(s.radius, max_radius)
		var d := pos.distance_to(s.position)
		if d >= r:
			continue
		var h := s.level * (1.0 - d / maxf(r, 1.0))
		if h > best_h:
			best_h = h
			best = {"id": s.id, "pos": s.position, "heard": h}
	return best


## Applique une source à un ennemi (voir l'en-tête). Renvoie true si l'ennemi est attiré.
static func lure(e: Node2D, src: Vector2, level: float, radius: float) -> bool:
	if e == null or not e.is_inside_tree():
		return false
	if e.has_method(&"is_alive") and not bool(e.call(&"is_alive")):
		return false
	if not e.has_method(&"add_awareness") or not e.has_method(&"is_in_combat"):
		return false
	if bool(e.call(&"is_in_combat")):
		return false
	var d := e.global_position.distance_to(src)
	if d >= radius:
		return false
	var att := 1.0 - d / maxf(radius, 1.0)
	if e.has_method(&"has_line_of_sight_to") and not bool(e.call(&"has_line_of_sight_to", src)):
		var wf: Variant = e.get(&"hearing_wall_factor")
		att *= float(wf) if (wf is float or wf is int) else 0.4
	var heard := level * att
	if heard < float(RecipeBook._balance(SECTION, "decoy_hearing_floor", 0.05)):
		return false
	var aw := float(e.get(&"awareness")) if e.get(&"awareness") != null else 0.0
	var sus_v: Variant = e.get(&"suspicion_threshold")
	var sus := float(sus_v) if (sus_v is float or sus_v is int) else 0.3
	var alert := 1.0
	var data: Variant = e.get(&"data")
	if data is Resource and (data as Resource).get(&"awareness_alert_threshold") != null:
		alert = float((data as Resource).get(&"awareness_alert_threshold"))
	var cap := maxf(alert - float(RecipeBook._balance(SECTION, "decoy_alert_margin", 0.08)), sus + 0.02)
	var target := clampf(maxf(aw, sus + 0.06) + float(RecipeBook._balance(SECTION, "decoy_gain", 0.15)) * heard, 0.0, cap)
	var stim: Variant = e.get(&"stimulus_position")
	var state: StringName = StringName(str(e.call(&"current_state_name"))) if e.has_method(&"current_state_name") else &""
	if state == &"Investigate" and stim is Vector2 and (stim as Vector2).distance_to(src) < 48.0:
		# Déjà en route vers le leurre : on entretient la jauge sans relancer la pause de suspicion.
		if e.has_method(&"set_awareness"):
			e.call(&"set_awareness", maxf(aw, target))
		return true
	e.call(&"add_awareness", maxf(target - aw, 0.001), src, false)
	return true


## Un passage : chaque source attire les ennemis de son rayon. Renvoie le nombre d'ennemis attirés.
static func pulse(tree: SceneTree) -> int:
	if tree == null:
		return 0
	var srcs := active()
	if srcs.is_empty():
		return 0
	var n := 0
	for node: Node in tree.get_nodes_in_group(&"enemies"):
		var e := node as Node2D
		if e == null:
			continue
		# La source la plus audible pour cet ennemi.
		var best: Source = null
		var best_h := 0.0
		for s: Source in srcs:
			var d := e.global_position.distance_to(s.position)
			if d < s.radius:
				var h := s.level * (1.0 - d / s.radius)
				if h > best_h:
					best_h = h
					best = s
		if best != null and lure(e, best.position, best.level, best.radius):
			n += 1
	return n


static func _ensure_driver() -> void:
	if is_instance_valid(_driver) and _driver.is_inside_tree():
		return
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return
	_driver = Driver.new()
	_driver.name = "NoiseSourcesDriver"
	var parent: Node = loop.current_scene if loop.current_scene != null else loop.root
	parent.add_child.call_deferred(_driver)


## Pilote : un passage toutes les `tick` s tant qu'il reste des sources, puis disparaît.
class Driver extends Node:
	var _left: float = 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE

	func _physics_process(delta: float) -> void:
		_left -= delta
		if _left > 0.0:
			return
		_left = float(RecipeBook._balance(NoiseSources.SECTION, "decoy_tick", 0.25))
		if NoiseSources.count() == 0:
			queue_free()
			return
		NoiseSources.pulse(get_tree())
