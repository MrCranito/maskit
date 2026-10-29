class_name InteractController
extends Node
## Choisit la cible d'interaction la plus proche du joueur (groupe `interactables` :
## conteneurs, cachettes…) toutes les `interact_check_interval` s (pas à chaque frame)
## et émet EventBus.interact_target_changed(target) quand elle change.
## press() / release() : bouton tactile « action » ou touche E (maintenir pour fouiller).
## Contrat des cibles : get_interact_label() -> String, interact(player) ;
## optionnels : can_interact() -> bool, release_interact(player), get_interact_reach() -> float,
## get_interact_icon() -> String, is_searching() -> bool.

const GROUP_INTERACTABLES := &"interactables"

var target: Node2D = null
var interact_range: float = 78.0
var check_interval: float = 0.12

var _left: float = 0.0
var _held: bool = false
var _last_label: String = ""


func _ready() -> void:
	name = "InteractController"
	interact_range = LootDB.getf("interact_range", 78.0)
	check_interval = LootDB.getf("interact_check_interval", 0.12)
	EventBus.container_opened.connect(func(_c: Node2D, _e: Array) -> void: refresh())
	EventBus.floor_changed.connect(func(_i: int) -> void: _set_target(null))


func _get_player() -> Node2D:
	var p: Node2D = GameState.player
	if p != null and is_instance_valid(p) and p.is_inside_tree():
		return p
	return null


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = check_interval
	refresh()


## Recalcule la cible (et le libellé, qui peut changer : Fouiller → Ouvrir, Se cacher → Sortir).
func refresh() -> void:
	var p := _get_player()
	var best: Node2D = null
	if p != null and (not p.has_method("is_alive") or bool(p.call("is_alive"))):
		best = pick_target(p, get_tree().get_nodes_in_group(GROUP_INTERACTABLES), interact_range)
	if target != null and is_instance_valid(target) and target.has_method("is_searching") and bool(target.call("is_searching")):
		best = target  # Pas de changement de cible pendant une fouille.
	_set_target(best)


## Logique pure : la cible valide la plus proche à portée (portée + reach de la cible).
## Joueur caché : seule sa cachette est proposée (pour « Sortir »).
static func pick_target(player: Node2D, candidates: Array, max_range: float) -> Node2D:
	if player.has_method("is_hidden") and bool(player.call("is_hidden")):
		var spot: Variant = player.call("get_hide_spot") if player.has_method("get_hide_spot") else null
		if spot is Node2D and is_instance_valid(spot):
			return spot
		for c: Variant in candidates:
			if c is HidingSpot and (c as HidingSpot).occupant == player:
				return c
		return null
	# (Toits) Joueur perché : seules les cibles « de toit » (haut d'échelle) sont proposées.
	var on_roof := player.has_method("is_on_roof") and bool(player.call("is_on_roof"))
	var best: Node2D = null
	var best_d := INF
	var origin := player.global_position
	for c: Variant in candidates:
		if not (c is Node2D) or not is_instance_valid(c):
			continue
		var n := c as Node2D
		if not n.is_inside_tree() or not n.is_visible_in_tree():
			continue
		if n.has_method("can_interact") and not bool(n.call("can_interact")):
			continue
		if on_roof != (n.has_method("is_roof_target") and bool(n.call("is_roof_target"))):
			continue
		var reach := float(n.call("get_interact_reach")) if n.has_method("get_interact_reach") else 0.0
		var d := origin.distance_to(n.global_position)
		if d <= max_range + reach and d - reach < best_d:
			best_d = d - reach
			best = n
	return best


func _set_target(t: Node2D) -> void:
	if t != null and not is_instance_valid(t):
		t = null
	var label := String(t.call("get_interact_label")) if t != null and t.has_method("get_interact_label") else ""
	if t == target and label == _last_label:
		return
	if t != target and _held:
		_release_target()
	target = t
	_last_label = label
	EventBus.interact_target_changed.emit(t)


func get_target() -> Node2D:
	return target if target != null and is_instance_valid(target) else null


func get_label() -> String:
	return _last_label


func press() -> void:
	refresh()
	var t := get_target()
	var p := _get_player()
	if t == null or p == null:
		return
	_held = true
	t.call("interact", p)
	refresh()


func release() -> void:
	if not _held:
		return
	_held = false
	_release_target()


func _release_target() -> void:
	var t := get_target()
	if t != null and t.has_method("release_interact"):
		t.call("release_interact", _get_player())


func is_held() -> bool:
	return _held


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed("interact"):
		press()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("interact"):
		release()
