class_name HauntedCarnivalGenerator
extends RefCounted
## Générateur du biome « Carnaval hanté » (parc d'attractions maudit, de nuit).
##
## API (contrat docs/CONVENTIONS.md, « Cartes et biomes ») :
##   HauntedCarnivalGenerator.generate_run(seed, world, difficulty) -> Array[FloorLayout]
##       Un seul étage (0, rez-de-chaussée pré-rendu : plan façon maquette hc_plan.gd).
##       Les bornes world.floors_min / floors_max sont respectées ; seul l'étage 0 existe
##       dans cette passe (les coulisses en sous-sol restent à faire).
##   HauntedCarnivalGenerator.generate_floor(seed, world, difficulty, floor_index) -> FloorLayout (ou null)
## Peuplement : hc_populator.gd ; réglages : section [haunted_carnival] de data/balance.cfg
## (repli [generator]). Déterministe : RandomNumberGenerator initialisés depuis la seed.

const Plan := preload("res://scripts/biomes/haunted_carnival/hc_plan.gd")
const Pop := preload("res://scripts/biomes/haunted_carnival/hc_populator.gd")

const DIFFICULTY_MIN := 0
const DIFFICULTY_MAX := 4


static func generate_run(seed: int, world: WorldData, difficulty: int) -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	if world == null:
		push_error("HauntedCarnivalGenerator: world est null.")
		return out
	var L := _ground(seed)
	if L == null:
		return out
	Pop.populate(L, world, seed, clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX))
	out.append(L)
	return out


static func generate_floor(seed: int, world: WorldData, difficulty: int, floor_index: int) -> FloorLayout:
	if world == null:
		push_error("HauntedCarnivalGenerator: world est null.")
		return null
	if floor_index != 0:
		return null
	var L := _ground(seed)
	if L == null:
		return null
	Pop.populate(L, world, seed, clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX))
	return L


static func find_floor(floors: Array[FloorLayout], floor_index: int) -> FloorLayout:
	for f in floors:
		if f.floor_index == floor_index:
			return f
	return null


static func _ground(seed: int) -> FloorLayout:
	var r: Variant = Plan.build(seed)
	return r.layout if r != null else null
