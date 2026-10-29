extends Node
## Autoload LootManager : état du butin pendant un raid.
## - Mémorise l'état des conteneurs (ouverts / vidés / contenu restant) par étage,
##   pour qu'un étage revisité ne se remplisse pas à nouveau.
## - Ennemis tués : le cadavre RESTE AU SOL (EnemyCorpse, fouillable : table de l'archétype
##   data/loot_tables/enemy_<kind>.tres, sinon table du biome) et certains font TOMBER du butin
##   (GroundLoot : chance par archétype, table enemy_drop) ; la clef spéciale rare (0,5 % à 2 %)
##   tombe au sol. Cadavres et butin au sol sont conservés par étage (changement d'étage) ;
##   nombre de cadavres limité par étage ([enemy_loot] max_corpses_per_floor).
## - Autres unités (tourelles si [turrets] drop_loot_on_destroy) : ancienne sacoche.
## - Clefs : une porte verrouillée touchée s'ouvre si l'inventaire contient sa clef.
## Les tirages eux-mêmes sont dans LootRoller / roll_enemy_loot (logique pure, testable).

signal key_used(key: ItemData, door: Node)
signal corpse_placed(corpse: Node2D)

const SECTION_ENEMY := "enemy_loot"

## persist_key → {"state": int, "entries": Array}
var container_states: Dictionary = {}
## Étage → Array de records de cadavres (EnemyCorpse.to_record()).
var corpse_records: Dictionary = {}
## Étage → Array de records de butin au sol (GroundLoot.to_record()).
var ground_records: Dictionary = {}
var _loot_root: Node2D = null
var _layout: FloorLayout = null
var _run_seed: int = 0
var _difficulty: int = 1
var _drop_counter: int = 0
var _next_id: int = 0
## Cadavres de l'étage courant (ordre d'apparition) : limite de nœuds.
var _corpses: Array[Node2D] = []
## Table de butin des ennemis du biome courant (enemy_<biome>, repli « enemy »).
var enemy_table: StringName = &"enemy"


func _ready() -> void:
	EventBus.raid_started.connect(_on_raid_started)
	EventBus.enemy_died.connect(_on_enemy_died)


func _on_raid_started(seed_value: int) -> void:
	container_states.clear()
	corpse_records.clear()
	ground_records.clear()
	_corpses.clear()
	_run_seed = seed_value
	_drop_counter = 0
	_next_id = 0
	var inv: Inventory = GameState.get("raid_inventory") as Inventory
	if inv != null and not inv.is_empty():
		inv.clear()


## Appelé par LootSpawner à chaque construction d'étage.
func register_floor(layout: FloorLayout, loot_root: Node2D, run_seed: int, difficulty: int) -> void:
	enemy_table = BiomeRegistry.enemy_table_kind(_current_biome())
	_layout = layout
	_loot_root = loot_root
	_run_seed = run_seed
	_difficulty = difficulty
	_corpses.clear()


## Étage courant (carte des couverts de l'IA, cf. EnemyTactics).
func current_layout() -> FloorLayout:
	return _layout


func current_floor() -> int:
	return _layout.floor_index if _layout != null else 0


func _has_floor_root() -> bool:
	return _loot_root != null and is_instance_valid(_loot_root) and _loot_root.is_inside_tree()


static func _current_biome() -> StringName:
	var path: String = String(GameState.get("world_path"))
	if path == "" or not ResourceLoader.exists(path):
		return &"far_west"
	var w: Resource = load(path)
	var b: Variant = w.get("biome") if w != null else null
	return StringName(str(b)) if b != null else &"far_west"


func save_container_state(key: String, state: int, entries: Array) -> void:
	var copy: Array = []
	for e: Dictionary in entries:
		copy.append({"item": e["item"], "count": int(e["count"])})
	container_states[key] = {"state": state, "entries": copy}


func get_container_state(key: String) -> Dictionary:
	return container_states.get(key, {})


# --- Ennemis tués : cadavre + butin au sol ------------------------------------------------

func _on_enemy_died(enemy: Node2D, pos: Vector2) -> void:
	if enemy is TargetDummy:
		return
	_drop_counter += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_run_seed, current_floor(), _drop_counter, "drop"])
	if enemy is Enemy:
		var e := enemy as Enemy
		var loot := roll_enemy_loot(e.data, rng, _difficulty, current_floor(), door_keys_of(_layout), enemy_table)
		e.corpse_entries.assign(loot["corpse"])
		var ground: Array = loot["ground"]
		if not ground.is_empty():
			_spawn_ground(ground, pos, rng, e.get_parent() as Node2D)
		return
	# Autres unités (tourelles) : ancienne sacoche.
	if not _has_floor_root():
		return
	var entries := roll_enemy_drop(rng, _difficulty, current_floor(), door_keys_of(_layout), enemy_table)
	if entries.is_empty():
		return
	var bag := LootContainer.create(&"drop", pos)
	bag.has_preset = true
	bag.preset_entries = entries
	bag.difficulty = _difficulty
	_loot_root.call_deferred("add_child", bag)


## Table du cadavre d'un archétype : data.loot_table, sinon enemy_<kind>, sinon la table du biome.
static func corpse_table_for(data: EnemyData, biome_table: StringName = &"enemy") -> LootTable:
	if data != null and data.loot_table != &"":
		var t := LootDB.get_table(data.loot_table)
		if t != null:
			return t
	if data != null:
		var t2 := LootDB.get_table(StringName("enemy_" + String(data.kind)))
		if t2 != null:
			return t2
	var t3 := LootDB.get_table(biome_table)
	return t3 if t3 != null else LootDB.get_table(&"enemy")


static func _ecfg(key: String, def: Variant) -> Variant:
	return LootDB.cfg().get_value(SECTION_ENEMY, key, def)


## Butin d'un ennemi tué (logique pure) : {"corpse": Array d'entrées (fouille du cadavre),
## "ground": Array d'entrées (tombent au sol)}.
##  - cadavre : table de l'archétype (corpse_table_for), avec la chance de vide de la table ;
##  - au sol : avec la chance ground_drop_chance (archétype, sinon [enemy_loot]), 1 à
##    ground_drop_max objets de la table enemy_drop ; l'élite lâche toujours et davantage ;
##  - clef spéciale de l'étage (key_drop_chance × elite_key_mult pour l'élite) : au sol.
static func roll_enemy_loot(data: EnemyData, rng: RandomNumberGenerator, difficulty: int, floor_index: int,
		keys: Array[StringName], biome_table: StringName = &"enemy") -> Dictionary:
	var corpse: Array[Dictionary] = []
	var ground: Array[Dictionary] = []
	var elite := data != null and data.elite
	var ctx := LootRoller.Context.make(difficulty, floor_index, &"super_loot" if elite else &"combat")
	if bool(_ecfg("corpse_loot", true)):
		corpse = LootRoller.roll(corpse_table_for(data, biome_table), rng, ctx)
	var key_chance := LootDB.arr_at("key_drop_chance", difficulty, [0.005, 0.008, 0.011, 0.015, 0.02])
	if elite:
		key_chance *= float(_ecfg("elite_key_mult", 4.0))
	if not keys.is_empty() and rng.randf() < key_chance:
		var k := LootDB.get_item(keys[rng.randi_range(0, keys.size() - 1)])
		if k != null:
			ground.append({"item": k, "count": 1})
	var chance := float(_ecfg("ground_drop_chance", 0.35))
	if data != null and data.ground_drop_chance >= 0.0:
		chance = data.ground_drop_chance
	if rng.randf() < chance:
		var t := LootDB.get_table(StringName(str(_ecfg("ground_table", "enemy_drop"))))
		if t != null:
			var n := rng.randi_range(1, maxi(int(_ecfg("ground_drop_max", 2)), 1))
			if elite:
				n += int(_ecfg("elite_extra_ground", 2))
			var weights := LootRoller.effective_weights(t, LootRoller.Context.make(difficulty, floor_index, &"combat"))
			for i in n:
				if weights.is_empty():
					break
				var id := LootRoller.pick_weighted(weights, rng)
				weights.erase(id)
				var it := LootDB.get_item(id)
				ground.append({"item": it, "count": rng.randi_range(maxi(it.drop_min, 1), maxi(it.drop_max, it.drop_min))})
	LootRoller.sort_entries(ground)
	return {"corpse": corpse, "ground": ground}


func _spawn_ground(entries: Array, pos: Vector2, rng: RandomNumberGenerator, fallback_parent: Node2D) -> void:
	var parent: Node2D = _loot_root if _has_floor_root() else fallback_parent
	if parent == null:
		return
	var n := entries.size()
	var base := rng.randf() * TAU
	for i: int in n:
		var e: Dictionary = entries[i]
		var ang := base + TAU * float(i) / float(maxi(n, 1)) + rng.randf_range(-0.3, 0.3)
		var to := pos + Vector2.from_angle(ang) * rng.randf_range(26.0, 46.0)
		var g := GroundLoot.create(e["item"], int(e["count"]), parent.to_local(pos), parent.to_local(to))
		_next_id += 1
		g.loot_id = _next_id
		g.floor_index = current_floor()
		parent.call_deferred("add_child", g)
		if _has_floor_root() and parent == _loot_root:
			var list: Array = ground_records.get(current_floor(), [])
			list.append(g.to_record())
			ground_records[current_floor()] = list


## Met à jour la mémoire d'étage quand un butin au sol est (partiellement) ramassé.
func on_ground_loot_changed(g: Node) -> void:
	var gl := g as GroundLoot
	if gl == null:
		return
	var list: Array = ground_records.get(gl.floor_index, [])
	for i: int in list.size():
		if int((list[i] as Dictionary).get("id", -1)) == gl.loot_id:
			if gl.count <= 0:
				list.remove_at(i)
			else:
				list[i] = gl.to_record()
			break


## Remplace l'ennemi mort par son cadavre persistant (appelé par Enemy.finalize_death).
func place_corpse(enemy: Node2D) -> Node2D:
	var e := enemy as Enemy
	if e == null or e.visual == null or not e.visual.has_method("get_corpse_info"):
		return null
	if not bool(_ecfg("corpses_enabled", true)):
		return null
	var info: Dictionary = e.visual.call("get_corpse_info")
	if info.get("texture") == null:
		return null
	var persistent := _has_floor_root()
	var parent: Node2D = _loot_root if persistent else e.get_parent() as Node2D
	if parent == null:
		return null
	var nm := e.data.corpse_name if e.data.corpse_name != "" else "%s abattu" % (e.data.display_name if e.data.display_name != "" else "Ennemi")
	var c := EnemyCorpse.create_corpse(e.data.kind, parent.to_local(e.global_position), info, nm)
	c.has_preset = true
	c.preset_entries.assign(e.corpse_entries)
	c.difficulty = _difficulty
	_next_id += 1
	c.corpse_id = _next_id
	if persistent:
		c.floor_index = current_floor()
		c.persist_key = "corpse:%d:%d" % [current_floor(), c.corpse_id]
		var list: Array = corpse_records.get(current_floor(), [])
		list.append(c.to_record())
		corpse_records[current_floor()] = list
	parent.add_child(c)
	if e.is_in_group(&"fog_hideable"):
		c.visible = e.visible
	_corpses.append(c)
	_enforce_corpse_limit()
	corpse_placed.emit(c)
	return c


## Limite le nombre de cadavres de l'étage : retire d'abord les plus anciens déjà fouillés,
## puis les plus anciens (leur butin est perdu).
func _enforce_corpse_limit() -> void:
	var cap := int(_ecfg("max_corpses_per_floor", 30))
	var i := 0
	while _corpses.size() > cap and i < _corpses.size():
		var c: Node2D = _corpses[i]
		if not is_instance_valid(c):
			_corpses.remove_at(i)
			continue
		if c is EnemyCorpse and (c as EnemyCorpse).is_emptied():
			_remove_corpse(i)
			continue
		i += 1
	while _corpses.size() > cap:
		_remove_corpse(0)


func _remove_corpse(index: int) -> void:
	var c: Node2D = _corpses[index]
	_corpses.remove_at(index)
	if c is EnemyCorpse:
		var ec := c as EnemyCorpse
		var list: Array = corpse_records.get(ec.floor_index, [])
		for k: int in list.size():
			if int((list[k] as Dictionary).get("id", -1)) == ec.corpse_id:
				list.remove_at(k)
				break
		container_states.erase(ec.persist_key)
	if is_instance_valid(c):
		c.queue_free()


func get_corpse_count() -> int:
	var n := 0
	for c: Node2D in _corpses:
		if is_instance_valid(c):
			n += 1
	return n


## Recrée cadavres et butin au sol d'un étage revisité (appelé par LootSpawner).
func restore_floor(floor_index: int, root: Node2D) -> void:
	_corpses.clear()
	for r: Dictionary in corpse_records.get(floor_index, []):
		var c := EnemyCorpse.from_record(r)
		c.floor_index = floor_index
		var saved := get_container_state(c.persist_key)
		if not saved.is_empty():
			c.restore(saved)
		root.add_child(c)
		_corpses.append(c)
	for g: Dictionary in ground_records.get(floor_index, []):
		var it: ItemData = g.get("item") as ItemData
		if it == null or int(g.get("count", 0)) <= 0:
			continue
		var gl := GroundLoot.create(it, int(g["count"]), g["pos"], g["pos"], false)
		gl.loot_id = int(g.get("id", 0))
		gl.floor_index = floor_index
		root.add_child(gl)


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


## Ancienne sacoche (tourelles) : clef rare (0,5 % à 2 %) + éventuellement la table `enemy`.
static func roll_enemy_drop(rng: RandomNumberGenerator, difficulty: int, floor_index: int, keys: Array[StringName], table: StringName = &"enemy") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key_chance := LootDB.arr_at("key_drop_chance", difficulty, [0.005, 0.008, 0.011, 0.015, 0.02])
	if not keys.is_empty() and rng.randf() < key_chance:
		var k := LootDB.get_item(keys[rng.randi_range(0, keys.size() - 1)])
		if k != null:
			out.append({"item": k, "count": 1})
	if rng.randf() < LootDB.getf("enemy_drop_chance", 0.25):
		var ctx := LootRoller.Context.make(difficulty, floor_index, &"combat")
		var t: LootTable = LootDB.get_table(table)
		out.append_array(LootRoller.roll(t if t != null else LootDB.get_table(&"enemy"), rng, ctx))
	LootRoller.sort_entries(out)
	return out


# --- Clefs et portes -------------------------------------------------------------------

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
	_hide_locked_label.call_deferred(door)
	var am := get_node_or_null(^"/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", &"door_unlock", (door as Node2D).global_position if door is Node2D else Vector2.INF)
	key_used.emit(LootDB.get_item(key_id), door)
	return true


static func _hide_locked_label(door: Variant) -> void:
	if is_instance_valid(door) and door is Node:
		var label := (door as Node).get_node_or_null(^"LockedLabel") as CanvasItem
		if label != null:
			label.visible = false
