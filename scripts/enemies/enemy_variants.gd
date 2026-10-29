class_name EnemyVariants
extends RefCounted
## Variantes d'apparition, appliquées une fois par étage neuf (LootSpawner) :
##  - un kind du générateur peut devenir une variante de la même famille (pistolero → tireur
##    embusqué, bandit → dynamiteur…) selon les poids de [enemy_variants] <kind> ; tirage
##    déterministe par case d'apparition (même raid → mêmes ennemis, étage revisité inchangé) ;
##  - garde d'élite : le premier ennemi de chaque salle de type elite_room_types (super_loot)
##    devient elite_kind (chef de bande), pour les biomes de elite_biomes.
## Les ennemis déjà traités (meta variant_rolled sur leurs données) sont ignorés.
## Le jour où le roster du monde liste directement ces kinds, il suffit de vider les poids.

const SECTION := "enemy_variants"
const DATA_DIR := "res://data/enemies/"


static func apply_to_floor(layout: FloorLayout, enemies: Array[Node], run_seed: int) -> int:
	if layout == null or enemies.is_empty():
		return 0
	var changed := 0
	var biome := _biome()
	var elite_kind := StringName(str(Balance.get_value(SECTION, "elite_kind", "gang_boss")))
	var elite_rooms: Array = Balance.get_value(SECTION, "elite_room_types", ["super_loot"]) as Array
	var elite_biomes: Array = Balance.get_value(SECTION, "elite_biomes", ["far_west"]) as Array
	var elite_ok := elite_biomes.has(String(biome)) and ResourceLoader.exists(DATA_DIR + String(elite_kind) + ".tres")
	var guarded := {}
	var sorted := enemies.duplicate()
	sorted.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	for n: Node in sorted:
		var e := n as Enemy
		if e == null or not e.is_alive() or e.data == null or e.data.has_meta(&"variant_rolled"):
			continue
		var cell := FloorLayout.world_to_cell(e.spawn_position)
		var room := layout.room_at(cell)
		if elite_ok and room != null and elite_rooms.has(String(room.type)) and not guarded.has(room.id):
			guarded[room.id] = true
			if e.data.kind != elite_kind:
				e.set_variant(load(DATA_DIR + String(elite_kind) + ".tres") as EnemyData)
				changed += 1
			continue
		var pick := roll_kind(e.data.kind, hash([run_seed, layout.floor_index, cell.x, cell.y, "variant"]))
		if pick != e.data.kind and ResourceLoader.exists(DATA_DIR + String(pick) + ".tres"):
			e.set_variant(load(DATA_DIR + String(pick) + ".tres") as EnemyData)
			changed += 1
	return changed


## Kind tiré pour `kind` (lui-même s'il n'a pas de variantes), déterministe pour `seed_value`.
static func roll_kind(kind: StringName, seed_value: int) -> StringName:
	var v: Variant = Balance.get_value(SECTION, String(kind), {})
	if not (v is Dictionary) or (v as Dictionary).is_empty():
		return kind
	var weights := {}
	for k: Variant in v:
		var w := float(v[k])
		if w > 0.0:
			weights[StringName(str(k))] = w
	if weights.is_empty():
		return kind
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return LootRoller.pick_weighted(weights, rng)


static func _biome() -> StringName:
	var path: String = String(GameState.get("world_path"))
	if path == "" or not ResourceLoader.exists(path):
		return &"far_west"
	var w: Resource = load(path)
	var b: Variant = w.get("biome") if w != null else null
	return StringName(str(b)) if b != null else &"far_west"
