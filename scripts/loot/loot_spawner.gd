class_name LootSpawner
extends RefCounted
## Place les conteneurs (layout.container_spawns) et les cachettes
## (layout.hiding_spot_spawns) d'un étage sous un nœud « Loot » trié en Y,
## enfant de `world_root`, et branche les portes verrouillées sur l'inventaire.
## Appel unique depuis Raid._build_floor :
##   LootSpawner.spawn_for_floor(layout, world_root, run_seed, difficulty)

const LOOT_ROOT_NAME := "Loot"
const GROUP_LOOT_ROOT := &"loot_root"


static func spawn_for_floor(layout: FloorLayout, world_root: Node2D, run_seed: int = 0, difficulty: int = 1) -> Node2D:
	if layout == null or world_root == null:
		return null
	var root := Node2D.new()
	root.name = LOOT_ROOT_NAME
	root.y_sort_enabled = true
	root.add_to_group(GROUP_LOOT_ROOT)
	world_root.add_child(root)

	var lm := _loot_manager(world_root)
	for s: FloorLayout.Spawn in layout.container_spawns:
		var c := make_container(layout, s, run_seed, difficulty)
		if lm != null:
			var saved: Dictionary = lm.call("get_container_state", c.persist_key)
			if not saved.is_empty():
				c.restore(saved)
		root.add_child(c)

	var hides: Variant = layout.get("hiding_spot_spawns")
	if hides is Array:
		for h: FloorLayout.Spawn in hides:
			var spot := HidingSpot.create(h.kind, _ground_pos(h.cell))
			spot.cell = h.cell
			root.add_child(spot)

	_connect_doors(world_root, lm)
	if lm != null:
		lm.call("register_floor", layout, root, run_seed, difficulty)
		# Cadavres et butin au sol d'un étage déjà visité.
		if lm.has_method("restore_floor"):
			lm.call("restore_floor", layout.floor_index, root)
	EnemyVariants.apply_to_floor(layout, _enemies_of(world_root), run_seed)
	return root


## Ennemis de l'étage (nœud « Enemies », frère du décor dans le nœud d'étage de Raid).
static func _enemies_of(world_root: Node2D) -> Array[Node]:
	var out: Array[Node] = []
	var floor_root := world_root.get_parent()
	if floor_root == null:
		return out
	var box := floor_root.get_node_or_null(^"Enemies")
	if box != null:
		out.assign(box.get_children())
	return out


static func make_container(layout: FloorLayout, s: FloorLayout.Spawn, run_seed: int, difficulty: int) -> LootContainer:
	var room := layout.get_room(s.room_id) if s.room_id >= 0 else layout.room_at(s.cell)
	var kind := s.kind
	# Coffre-fort de la banque : les coffres de la chambre forte deviennent des coffres-forts.
	if room != null and room.tags.size() > 0 and room.tags[0] == "bank_vault":
		kind = &"safe"
	var c := LootContainer.create(kind, _ground_pos(s.cell))
	c.cell = s.cell
	c.floor_index = layout.floor_index
	c.room_type = room.type if room != null else &"combat"
	c.difficulty = difficulty
	c.loot_seed = LootRoller.container_seed(run_seed, layout.floor_index, s.cell, kind)
	c.persist_key = "%d:%d:%d" % [layout.floor_index, s.cell.x, s.cell.y]
	return c


## Point d'appui au sol (même convention que les décors WorldProp).
static func _ground_pos(cell: Vector2i) -> Vector2:
	return FloorLayout.cell_to_world(cell) + Vector2(0.0, FloorLayout.TILE_SIZE * 0.25)


static func _connect_doors(world_root: Node2D, lm: Node) -> void:
	if lm == null:
		return
	var doors: Array = []
	if world_root.has_method("get_doors"):
		doors = world_root.call("get_doors")
	else:
		doors = world_root.get_tree().get_nodes_in_group(&"doors") if world_root.is_inside_tree() else []
	var cb := Callable(lm, "on_locked_door_bumped")
	for d: Variant in doors:
		if d is Node and (d as Node).has_signal("locked_bumped") and not (d as Node).is_connected("locked_bumped", cb):
			(d as Node).connect("locked_bumped", cb)


static func _loot_manager(n: Node) -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null:
		return null
	return ml.root.get_node_or_null(^"LootManager")
