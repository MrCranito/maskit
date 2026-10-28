class_name TurretPlacer
extends RefCounted
## Placement des tourelles murales d'un étage (CONVENTIONS « Refonte Exfil Rush », ligne Tourelles).
## Ne dépend que du format FloorLayout (tiles, rooms, doors, stairs, spawns…) ; réglages dans
## balance.cfg [turrets].
##
## Branchement dans raid.gd (après la construction du décor et des ennemis de l'étage) :
##     TurretPlacer.spawn_for_floor(self, layout, floor_root, run_seed, difficulty, current_floor)
## Les tourelles détruites / endommagées sont mémorisées dans la meta `turret_states` du raid et
## restaurées quand on revient sur l'étage (même seed → mêmes emplacements).

const CONTAINER_NAME := "Turrets"
const META_STATES := &"turret_states"
const DIRS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP]
const DEFAULT_ROOM_WEIGHTS := {
	&"combat": 1.0, &"super_loot": 1.8, &"boss": 1.2, &"corridor": 0.8, &"trap": 0.6, &"loot": 0.3,
}


## Emplacements de tourelles (pur, déterministe pour une même seed). Chaque spot :
## {cell: Vector2i (case WALL), normal: Vector2i (mur → salle), room_id: int, turret_id: StringName}.
## `world_id` : id du monde (« world_02_space_station ») ou du biome (« space_station »).
static func find_spots(layout: FloorLayout, seed_value: int, difficulty: int, floor_index: int, world_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if layout == null or layout.size.x <= 0:
		return out
	var biome := TurretData.biome_of(world_id)
	var types := TurretData.for_biome(biome, difficulty)
	var wanted := turret_count(layout, difficulty, floor_index)
	if types.is_empty() or wanted <= 0:
		return out
	var cands := _candidates(layout, seed_value, floor_index)
	var spacing := Balance.get_float("turrets", "min_spacing", 6.0)
	var max_room := int(Balance.get_value("turrets", "max_per_room", 2))
	var per_room: Dictionary = {}
	for c: Dictionary in cands:
		if out.size() >= wanted:
			break
		var cell: Vector2i = c["cell"]
		var rid: int = c["room_id"]
		if int(per_room.get(rid, 0)) >= max_room:
			continue
		var ok := true
		for s: Dictionary in out:
			if Vector2(cell).distance_to(Vector2(s["cell"] as Vector2i)) < spacing:
				ok = false
				break
		if not ok:
			continue
		per_room[rid] = int(per_room.get(rid, 0)) + 1
		c["turret_id"] = _pick_type(types, seed_value, floor_index, cell)
		out.append(c)
	return out


## Nombre visé de tourelles : base par difficulté + profondeur d'étage + taille (cases praticables).
static func turret_count(layout: FloorLayout, difficulty: int, floor_index: int) -> int:
	var base_arr: Variant = Balance.get_value("turrets", "count_by_difficulty", [1, 2, 3, 4, 5])
	var base := 2
	if base_arr is Array and not (base_arr as Array).is_empty():
		var a: Array = base_arr
		base = int(a[clampi(difficulty, 0, a.size() - 1)])
	var depth := absi(floor_index) * int(Balance.get_value("turrets", "count_per_floor_depth", 1))
	var walk := 0
	for t: int in layout.tiles:
		if t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET:
			walk += 1
	var per := maxf(Balance.get_float("turrets", "walkable_cells_per_extra", 400.0), 1.0)
	var size_bonus := int(float(walk) / per)
	var n := base + depth + size_bonus
	return clampi(n, 0, int(Balance.get_value("turrets", "max_per_floor", 10)))


## Murs candidats triés par priorité pondérée (Efraimidis-Spirakis : clé = u^(1/poids)).
## L'ordre ne dépend que de la seed et de l'étage (pas de la difficulté) : à seed égale, les
## emplacements d'une difficulté plus haute contiennent ceux d'une difficulté plus basse.
static func _candidates(L: FloorLayout, seed_value: int, floor_index: int) -> Array[Dictionary]:
	var weights: Variant = Balance.get_value("turrets", "room_weights", DEFAULT_ROOM_WEIGHTS)
	var rw: Dictionary = weights if weights is Dictionary else DEFAULT_ROOM_WEIGHTS
	var corridor_len := int(Balance.get_value("turrets", "corridor_min_length", 8))
	var door_clear := int(Balance.get_value("turrets", "door_clearance", 2))
	var stairs_clear := int(Balance.get_value("turrets", "stairs_clearance", 2))
	var extract_clear := Balance.get_float("turrets", "extraction_clearance", 4.0)
	var spawn_clear := Balance.get_float("turrets", "spawn_clearance", 9.0)
	var blocked := _blocked_cells(L)
	var near_exit := _near_cells(L, door_clear, stairs_clear)
	var spawn_room := L.room_at(L.player_spawn)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, floor_index, "turrets"])
	var out: Array[Dictionary] = []
	for y: int in L.size.y:
		for x: int in L.size.x:
			var c := Vector2i(x, y)
			if L.get_tile(c) != FloorLayout.Tile.WALL:
				continue
			for n: Vector2i in DIRS:
				var spot := _evaluate(L, c, n, rw, corridor_len, near_exit, extract_clear,
					spawn_clear, blocked, spawn_room)
				if spot.is_empty():
					continue
				# Tirage fait pour CHAQUE candidat dans l'ordre de balayage (déterministe).
				var u := maxf(rng.randf(), 1e-6)
				spot["_key"] = pow(u, 1.0 / float(spot["_w"]))
				out.append(spot)
				break
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["_key"]) > float(b["_key"]))
	for s: Dictionary in out:
		s.erase("_key")
		s.erase("_w")
	return out


## Spot valide pour le mur `c` orienté vers `n`, ou {}.
static func _evaluate(L: FloorLayout, c: Vector2i, n: Vector2i, rw: Dictionary, corridor_len: int,
		near_exit: Dictionary, extract_clear: float, spawn_clear: float,
		blocked: Dictionary, spawn_room: FloorLayout.Room) -> Dictionary:
	var front := c + n
	if not _is_ground(L.get_tile(front)) or not _is_ground(L.get_tile(front + n)):
		return {}
	# Mur déjà habillé (étagère, affiche, lampe… : FloorLayout.wall_decor_cells) : pas de tourelle.
	if L.has_method(&"has_wall_decor") and bool(L.call(&"has_wall_decor", c)):
		return {}
	var side := Vector2i(n.y, n.x)
	# Mur droit (pas un pilier ni l'extrémité d'une cloison) et pas coincé dans un angle.
	if L.get_tile(c + side) != FloorLayout.Tile.WALL or L.get_tile(c - side) != FloorLayout.Tile.WALL:
		return {}
	if not _is_ground(L.get_tile(front + side)) and not _is_ground(L.get_tile(front - side)):
		return {}
	# Aucun meuble / conteneur / ennemi juste devant (zone 3 × 2 cases) : il masquerait la tourelle
	# et boucherait son champ de tir.
	for k: int in [1, 2]:
		for o: int in [-1, 0, 1]:
			if blocked.has(c + n * k + side * o):
				return {}
	# Portes, escaliers, extraction, apparition du joueur.
	if near_exit.has(c):
		return {}
	for e: Vector2i in L.extraction_cells:
		if Vector2(e).distance_to(Vector2(c)) < extract_clear:
			return {}
	if Vector2(L.player_spawn).distance_to(Vector2(c)) < spawn_clear:
		return {}
	var room := L.room_at(front)
	if room == null or room.type == FloorLayout.ROOM_SPAWN or (spawn_room != null and room.id == spawn_room.id):
		return {}
	var w := float(rw.get(room.type, rw.get(String(room.type), 0.0)))
	if room.type == FloorLayout.ROOM_CORRIDOR and maxi(room.rect.size.x, room.rect.size.y) < corridor_len:
		w = 0.0
	if w <= 0.0:
		return {}
	return {"cell": c, "normal": n, "room_id": room.id, "turret_id": &"", "_w": w}


## Cases au sol occupées par un point d'apparition (conteneur, cachette, décor, ennemi) :
## pas de tourelle juste devant.
static func _blocked_cells(L: FloorLayout) -> Dictionary:
	var out: Dictionary = {}
	var lists: Array = [L.container_spawns, L.prop_spawns, L.enemy_spawns]
	var hides: Variant = L.get("hiding_spot_spawns")
	if hides is Array:
		lists.append(hides)
	for lst: Variant in lists:
		for s: Variant in lst:
			if s is FloorLayout.Spawn:
				out[(s as FloorLayout.Spawn).cell] = true
	return out


## Cases à moins de door_clear (Chebyshev) d'une porte ou de stairs_clear d'un escalier.
static func _near_cells(L: FloorLayout, door_clear: int, stairs_clear: int) -> Dictionary:
	var out: Dictionary = {}
	var centers: Array[Vector2i] = []
	var radii: Array[int] = []
	for d: FloorLayout.Door in L.doors:
		centers.append(d.cell)
		radii.append(door_clear)
	for st: FloorLayout.Stairs in L.stairs:
		centers.append(st.cell)
		radii.append(stairs_clear)
	for i: int in centers.size():
		var r := radii[i]
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				out[centers[i] + Vector2i(dx, dy)] = true
	return out


static func _pick_type(types: Array[TurretData], seed_value: int, floor_index: int, cell: Vector2i) -> StringName:
	var total := 0.0
	for t: TurretData in types:
		total += maxf(t.spawn_weight, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, floor_index, cell, "turret_type"])
	var r := rng.randf() * total
	for t: TurretData in types:
		r -= maxf(t.spawn_weight, 0.0)
		if r <= 0.0:
			return t.id
	return types[types.size() - 1].id


static func _is_ground(t: int) -> bool:
	return t == FloorLayout.Tile.FLOOR or t == FloorLayout.Tile.STREET


## Instancie les tourelles de l'étage sous `parent` et les renvoie. Si `parent` s'appelle
## « Turrets » il sert de conteneur, sinon un enfant « Turrets » (y_sort, z 10 comme les
## personnages et les murs) est créé. Appel en double = tourelles existantes renvoyées.
## Restaure PV / destruction mémorisés dans la meta `turret_states` du raid.
static func spawn_for_floor(raid: Node, layout: FloorLayout, parent: Node2D, seed_value: int, difficulty: int, floor_index: int) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if layout == null or parent == null:
		return out
	var world_id := world_id_of(raid)
	var spots := find_spots(layout, seed_value, difficulty, floor_index, world_id)
	# Parent déjà conteneur de tourelles (raid.gd crée le sien) → utilisé tel quel.
	var root: Node2D = parent if String(parent.name) == CONTAINER_NAME else parent.get_node_or_null(CONTAINER_NAME) as Node2D
	if root != null and root.get_child_count() > 0:
		# Déjà peuplé (appel en double) : renvoie les tourelles existantes.
		for n: Node in root.get_children():
			if n is Turret and not n.is_queued_for_deletion():
				out.append(n as Node2D)
		return out
	if root == null:
		root = Node2D.new()
		root.name = CONTAINER_NAME
		root.y_sort_enabled = true
		root.z_index = 10
		parent.add_child(root)
	var states: Dictionary = {}
	if raid != null:
		var all: Dictionary = raid.get_meta(META_STATES, {})
		states = all.get(floor_index, {})
	var card: Variant = raid.get(&"map_card") if raid != null else null
	for s: Dictionary in spots:
		var data := TurretData.get_by_id(s["turret_id"])
		if data == null:
			continue
		var t := Turret.create(data, s["normal"], s["cell"], difficulty)
		t.set_meta(&"room_id", s["room_id"])
		t.bind_raid(raid, floor_index)
		root.add_child(t)
		if card is MapCard:
			var mc := card as MapCard
			t.apply_modifiers(mc.get_mod_f("enemy_hp_mult"), mc.get_mod_f("enemy_damage_mult"), 1.0, mc.get_mod_f("awareness_mult"))
		var cell: Vector2i = s["cell"]
		if states.has(cell):
			var hp := float(states[cell])
			if hp <= 0.0:
				t.set_destroyed_silently()
			else:
				t.hp = minf(hp, t.max_hp)
				t.refresh_health_bar()
		out.append(t)
	return out


## Monde du raid : propriété `world` (WorldData) du raid, sinon meta `world_id`, sinon
## GameState.world_path, sinon Far West.
static func world_id_of(raid: Node) -> String:
	if raid != null:
		var w: Variant = raid.get(&"world")
		if w is Resource:
			var b: Variant = (w as Resource).get(&"biome")
			if b != null and String(b) != "":
				return String(b)
			var wid: Variant = (w as Resource).get(&"id")
			if wid != null and String(wid) != "":
				return String(wid)
		if raid.has_meta(&"world_id"):
			return String(raid.get_meta(&"world_id"))
	var path: String = GameState.world_path
	if path != "" and ResourceLoader.exists(path):
		var wr := load(path) as Resource
		if wr != null and wr.get(&"biome") != null:
			return String(wr.get(&"biome"))
	return "far_west"
