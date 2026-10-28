extends RefCounted
## Vérifications communes de l'aménagement par gabarits (utilisées par les tests des 4 biomes).
## Chaque fonction renvoie la liste des problèmes trouvés (vide = OK).

const T := FloorLayout.Tile
const DIRS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## Cases occupées : décors (emprise Spawn.size, ou `extra` pour les grands décors), conteneurs,
## cachettes.
static func blocked(f: FloorLayout, extra: Dictionary = {}) -> Dictionary:
	var out := extra.duplicate()
	for s in f.prop_spawns:
		for q in FloorLayout.spawn_cells(s):
			out[q] = true
	for l: Array in [f.container_spawns, f.hiding_spot_spawns]:
		for s2: FloorLayout.Spawn in l:
			out[s2.cell] = true
	return out


static func reach(f: FloorLayout, starts: Array[Vector2i], blk: Dictionary) -> Dictionary:
	var seen := {}
	var stack: Array[Vector2i] = []
	for e in starts:
		seen[e] = true
		stack.append(e)
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var n := c + d
			if seen.has(n) or blk.has(n) or not FloorLayout.is_walkable_tile(f.get_tile(n)):
				continue
			seen[n] = true
			stack.append(n)
	return seen


## Conteneurs et cachettes : au moins une case voisine accessible.
static func containers_reachable(f: FloorLayout, starts: Array[Vector2i], extra: Dictionary = {}) -> Array[String]:
	var bad: Array[String] = []
	var r := reach(f, starts, blocked(f, extra))
	for l: Array in [f.container_spawns, f.hiding_spot_spawns]:
		for s: FloorLayout.Spawn in l:
			var ok := false
			for d in DIRS:
				if r.has(s.cell + d):
					ok = true
			if not ok:
				bad.append("%s inaccessible en %s" % [s.kind, s.cell])
	return bad


## Rien de bloquant (y compris cloisons) sur une porte, l'abord d'une porte, un escalier ou ses
## abords praticables, une extraction ou le spawn joueur.
static func gates_clear(f: FloorLayout, extra: Dictionary = {}) -> Array[String]:
	var blk := blocked(f, extra)
	for p: Vector2i in f.partition_cells:
		blk[p] = true
	var bad: Array[String] = []
	var gates: Array[Vector2i] = []
	for d in f.doors:
		gates.append(d.cell)
		gates.append(d.cell + (Vector2i.LEFT if d.vertical else Vector2i.UP))
		gates.append(d.cell + (Vector2i.RIGHT if d.vertical else Vector2i.DOWN))
	for st in f.stairs:
		gates.append(st.cell)
	for e in f.extraction_cells:
		gates.append(e)
	gates.append(f.player_spawn)
	for g in gates:
		if blk.has(g):
			bad.append("abord encombré %s" % g)
	return bad


## Cloisons : des murs, dans des salles intérieures.
static func partitions_ok(f: FloorLayout) -> Array[String]:
	var bad: Array[String] = []
	for p: Vector2i in f.partition_cells:
		if f.get_tile(p) != T.WALL:
			bad.append("cloison %s n'est pas un mur" % p)
		var r := f.room_at(p)
		if r == null or r.outdoor:
			bad.append("cloison %s hors salle intérieure" % p)
	return bad


## Décors muraux : sur des murs à face visible (case au sud praticable).
static func wall_decor_ok(f: FloorLayout) -> Array[String]:
	var bad: Array[String] = []
	for c: Vector2i in f.wall_decor_cells:
		if f.get_tile(c) != T.WALL or not FloorLayout.is_walkable_tile(f.get_tile(c + Vector2i.DOWN)):
			bad.append("décor mural %s mal placé" % c)
	return bad


## Proportion des faces de murs visibles décorées (doit rester faible : murs libres pour les
## tourelles).
static func wall_decor_ratio(f: FloorLayout) -> float:
	var faces := 0
	for y in f.size.y:
		for x in f.size.x:
			if f.get_tile(Vector2i(x, y)) == T.WALL and FloorLayout.is_walkable_tile(f.get_tile(Vector2i(x, y + 1))):
				faces += 1
	return float(f.wall_decor_cells.size()) / maxf(1.0, float(faces))


## Rôles (tags[0]) des salles intérieures qui n'ont reçu ni meuble ni cloison.
static func empty_templated_rooms(f: FloorLayout, templates: Dictionary) -> Array[String]:
	var per := {}
	for s in f.prop_spawns:
		per[s.room_id] = true
	for p: Vector2i in f.partition_cells:
		var r0 := f.room_at(p)
		if r0 != null:
			per[r0.id] = true
	var out: Array[String] = []
	for r in f.rooms:
		if r.outdoor or r.tags.is_empty() or not templates.has(StringName(r.tags[0])):
			continue
		if not per.has(r.id):
			out.append("%s (%s %s)" % [r.tags[0], r.name, r.rect.size])
	return out


## Signature déterministe de l'aménagement (spawns, décors au sol et muraux, cloisons, tuiles).
static func signature(f: FloorLayout) -> String:
	var parts: PackedStringArray = []
	for l: Array in [f.prop_spawns, f.container_spawns, f.hiding_spot_spawns, f.decor_spawns]:
		for s: FloorLayout.Spawn in l:
			parts.append("%s%s%d%s%s" % [s.cell, s.kind, s.room_id, s.offset, s.size])
	var wd := f.wall_decor_cells.keys()
	wd.sort()
	for c: Vector2i in wd:
		parts.append("W%s%s" % [c, f.wall_decor_cells[c]])
	parts.append(str(hash(f.tiles)))
	return ";".join(parts)
