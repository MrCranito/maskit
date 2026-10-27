class_name DungeonGenerator
extends RefCounted
## Générateur procédural de villes Far West « salles et couloirs ».
##
## API :
##   DungeonGenerator.generate_run(seed: int, world: WorldData, difficulty: int) -> Array[FloorLayout]
##       Tableau TRIÉ par floor_index croissant : [étage -1 (mine), étage 0 (ville), étage 1 (étages)]
##       selon world.floors_min / floors_max. Chaque FloorLayout porte son `floor_index` :
##       c'est lui qui fait foi (indexer par `layout.floor_index`, pas par la position
##       dans le tableau). L'étage 0 est toujours présent. L'étage -1 n'existe que si
##       la ville a une entrée de mine, l'étage 1 que si elle a un saloon ou un hôtel.
##   DungeonGenerator.generate_floor(seed, world, difficulty, floor_index) -> FloorLayout
##       Même étage que dans generate_run (même seed → mêmes cartes) ; null si l'étage
##       n'existe pas pour ce monde/seed.
##
## Escaliers : chaque Stairs a target_cell == cell (même coordonnées sur les deux
## étages : les grilles de tous les étages ont la même taille).
## difficulty : 0 Facile … 4 Cauchemar (plus d'ennemis, plus de gardes).
## Déterministe : uniquement des RandomNumberGenerator initialisés depuis la seed.
## Réglages : section [generator] de data/balance.cfg.

const Cfg := preload("res://scripts/dungeon/gen/gen_config.gd")
const Town := preload("res://scripts/dungeon/gen/town_builder.gd")
const Mine := preload("res://scripts/dungeon/gen/mine_builder.gd")
const Pop := preload("res://scripts/dungeon/gen/populator.gd")

const DIFFICULTY_MIN := 0
const DIFFICULTY_MAX := 4


static func generate_run(seed: int, world: WorldData, difficulty: int) -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	if world == null:
		push_error("DungeonGenerator: world est null.")
		return out
	var diff := clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX)
	Town.set_names(world)
	var town := Town.build(seed, world)
	var ground := town.layout
	if world.floors_min <= -1 and not town.mine_stairs.is_empty():
		var mine := Mine.build(ground.size, town.mine_stairs, seed)
		Pop.populate(mine, world, seed, diff)
		out.append(mine)
	Pop.populate(ground, world, seed, diff)
	out.append(ground)
	if world.floors_max >= 1 and not town.upper_specs.is_empty():
		var upper := Town.build_upper(seed, town)
		Pop.populate(upper, world, seed, diff)
		out.append(upper)
	return out


static func generate_floor(seed: int, world: WorldData, difficulty: int, floor_index: int) -> FloorLayout:
	if world == null:
		push_error("DungeonGenerator: world est null.")
		return null
	if floor_index < world.floors_min or floor_index > world.floors_max:
		return null
	var diff := clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX)
	Town.set_names(world)
	# La structure de l'étage 0 conditionne les autres (escaliers) : on la refait.
	var town := Town.build(seed, world)
	var L: FloorLayout = null
	match floor_index:
		0:
			L = town.layout
		-1:
			if town.mine_stairs.is_empty():
				return null
			L = Mine.build(town.layout.size, town.mine_stairs, seed)
		1:
			if town.upper_specs.is_empty():
				return null
			L = Town.build_upper(seed, town)
		_:
			return null
	Pop.populate(L, world, seed, diff)
	return L


## Recherche d'un étage dans le résultat de generate_run (null si absent).
static func find_floor(floors: Array[FloorLayout], floor_index: int) -> FloorLayout:
	for f in floors:
		if f.floor_index == floor_index:
			return f
	return null
