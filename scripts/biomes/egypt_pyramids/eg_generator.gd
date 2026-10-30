class_name EgyptGenerator
extends RefCounted
## Générateur du biome « Les Pyramides d'Égypte » (world_06_egypt_pyramids).
##
## API (contrat docs/CONVENTIONS.md, « Cartes et biomes ») :
##   EgyptGenerator.generate_run(seed, world, difficulty) -> Array[FloorLayout]
##       un seul étage (0 : la surface, complexe de temples façon maquette, pré-rendue dans
##       Blender par tools/prerender/eg_scene.py) ; bornes world.floors_min / floors_max.
##   EgyptGenerator.generate_floor(seed, world, difficulty, floor_index) -> FloorLayout (ou null)
## Plan : scripts/biomes/egypt_pyramids/eg_plan.gd ; peuplement : eg_populator.gd ;
## réglages : section [egypt_pyramids] de data/balance.cfg (repli [generator]).
## La structure (tuiles, portes) ne dépend pas de la difficulté : même paquet pré-rendu pour
## toutes les difficultés. Déterministe (RNG initialisés depuis la seed).

const Plan := preload("res://scripts/biomes/egypt_pyramids/eg_plan.gd")
const Pop := preload("res://scripts/biomes/egypt_pyramids/eg_populator.gd")

const DIFFICULTY_MIN := 0
const DIFFICULTY_MAX := 4


static func generate_run(seed: int, world: WorldData, difficulty: int) -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	if world == null:
		push_error("EgyptGenerator: world est null.")
		return out
	var L := generate_floor(seed, world, difficulty, 0)
	if L != null:
		out.append(L)
	return out


static func generate_floor(seed: int, world: WorldData, difficulty: int, floor_index: int) -> FloorLayout:
	if world == null:
		push_error("EgyptGenerator: world est null.")
		return null
	if floor_index != 0:
		return null
	var r: Variant = Plan.build(seed)
	if r == null:
		return null
	var L: FloorLayout = r.layout
	Pop.populate(L, world, seed, clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX))
	return L


static func find_floor(floors: Array[FloorLayout], floor_index: int) -> FloorLayout:
	for f in floors:
		if f.floor_index == floor_index:
			return f
	return null
