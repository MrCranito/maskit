extends Node
## Autoload LootManager : état du butin pendant un raid.
## - Mémorise l'état des conteneurs (ouverts / vidés / contenu restant) par étage,
##   pour qu'un étage revisité ne se remplisse pas à nouveau.
## - Sacoches d'ennemis : à la mort d'un ennemi, chance de laisser un petit butin
##   (table `enemy`) et, très rarement, une clef spéciale d'une porte de l'étage.
## - Clefs : une porte verrouillée touchée s'ouvre si l'inventaire contient sa clef
##   (la clef est consommée).
## Les tirages eux-mêmes sont dans LootRoller (logique pure, testable).

signal key_used(key: ItemData, door: Node)

## persist_key → {"state": int, "entries": Array}
var container_states: Dictionary = {}
## Nœud qui reçoit les sacoches de l'étage courant (enregistré par LootSpawner).
var _loot_root: Node2D = null
var _layout: FloorLayout = null
var _run_seed: int = 0
var _difficulty: int = 1
var _drop_counter: int = 0


func _ready() -> void:
	EventBus.raid_started.connect(_on_raid_started)
	EventBus.enemy_died.connect(_on_enemy_died)


func _on_raid_started(seed_value: int) -> void:
	# Nouveau raid (ou rechargement après la mort) : butin non extrait perdu.
	container_states.clear()
	_run_seed = seed_value
	_drop_counter = 0
	var inv: Inventory = GameState.get("raid_inventory") as Inventory
	if inv != null and not inv.is_empty():
		inv.clear()


## Appelé par LootSpawner à chaque construction d'étage.
func register_floor(layout: FloorLayout, loot_root: Node2D, run_seed: int, difficulty: int) -> void:
	_layout = layout
	_loot_root = loot_root
	_run_seed = run_seed
	_difficulty = difficulty


func save_container_state(key: String, state: int, entries: Array) -> void:
	var copy: Array = []
	for e: Dictionary in entries:
		copy.append({"item": e["item"], "count": int(e["count"])})
	container_states[key] = {"state": state, "entries": copy}


func get_container_state(key: String) -> Dictionary:
	return container_states.get(key, {})


# --- Sacoches d'ennemis --------------------------------------------------------------

func _on_enemy_died(enemy: Node2D, pos: Vector2) -> void:
	if _loot_root == null or not is_instance_valid(_loot_root) or not _loot_root.is_inside_tree():
		return
	if enemy is TargetDummy:
		return
	_drop_counter += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_run_seed, _layout.floor_index if _layout != null else 0, _drop_counter, "drop"])
	var entries := roll_enemy_drop(rng, _difficulty, _layout.floor_index if _layout != null else 0, door_keys_of(_layout))
	if entries.is_empty():
		return
	var bag := LootContainer.create(&"drop", pos)
	bag.has_preset = true
	bag.preset_entries = entries
	bag.difficulty = _difficulty
	_loot_root.call_deferred("add_child", bag)


## Clefs utiles sur cet étage (portes verrouillées), triées.
static func door_keys_of(layout: FloorLayout) -> Array[StringName]:
	var out: Array[StringName] = []
	if layout == null:
		return out
	for d: FloorLayout.Door in layout.doors:
		if d.state == FloorLayout.DoorState.LOCKED and d.key_id != &"" and not out.has(d.key_id) and LootDB.has_item(d.key_id):
			out.append(d.key_id)
	out.sort()
	return out


## Butin d'un ennemi (logique pure) : clef rare (0,5 % à 2 %) + éventuellement la table `enemy`.
static func roll_enemy_drop(rng: RandomNumberGenerator, difficulty: int, floor_index: int, keys: Array[StringName]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key_chance := LootDB.arr_at("key_drop_chance", difficulty, [0.005, 0.008, 0.011, 0.015, 0.02])
	if not keys.is_empty() and rng.randf() < key_chance:
		var k := LootDB.get_item(keys[rng.randi_range(0, keys.size() - 1)])
		if k != null:
			out.append({"item": k, "count": 1})
	if rng.randf() < LootDB.getf("enemy_drop_chance", 0.25):
		var ctx := LootRoller.Context.make(difficulty, floor_index, &"combat")
		out.append_array(LootRoller.roll(LootDB.get_table(&"enemy"), rng, ctx))
	LootRoller.sort_entries(out)
	return out


# --- Clefs et portes -------------------------------------------------------------------

## Branché sur DoorNode.locked_bumped : ouvre la porte avec la clef de l'inventaire.
func on_locked_door_bumped(door: Node) -> void:
	try_unlock_with_inventory(door, GameState.get("raid_inventory") as Inventory)


func try_unlock_with_inventory(door: Node, inv: Inventory) -> bool:
	if door == null or inv == null or not door.has_method("try_unlock"):
		return false
	var key_id: StringName = StringName(str(door.get("key_id"))) if door.get("key_id") != null else &""
	if key_id == &"" or not inv.has_item(key_id):
		return false
	if not bool(door.call("try_unlock", key_id)):
		return false
	inv.remove_item(key_id, 1)
	# DoorNode affiche « Clef requise » juste après locked_bumped : on le masque.
	_hide_locked_label.call_deferred(door)
	var am := get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", &"door_unlock", (door as Node2D).global_position if door is Node2D else Vector2.INF)
	key_used.emit(LootDB.get_item(key_id), door)
	return true


static func _hide_locked_label(door: Node) -> void:
	if door != null and is_instance_valid(door):
		var label := door.get_node_or_null(^"LockedLabel") as CanvasItem
		if label != null:
			label.visible = false
