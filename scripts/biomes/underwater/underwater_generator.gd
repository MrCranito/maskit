class_name UnderwaterGenerator
extends RefCounted
## Générateur procédural de la station sous-marine « Abysse Nérée ».
##
## API (contrat des biomes, docs/CONVENTIONS.md) :
##   UnderwaterGenerator.generate_run(seed, world, difficulty) -> Array[FloorLayout]
##       Tableau TRIÉ par floor_index croissant : [-2 Fosse, -1 Laboratoires, 0 Pont d'amarrage]
##       (bornes world.floors_min / floors_max). L'étage 0 est toujours présent.
##   UnderwaterGenerator.generate_floor(seed, world, difficulty, floor_index) -> FloorLayout
##       Même étage que dans generate_run (null si l'étage n'existe pas).
##
## Structure : modules d'acier (salles) sur une grille de baies, reliés par des tubes
## vitrés de 3 cases (couloirs) avec un sas rond à chaque bout (cf. uw_station.gd).
## Étages reliés par ascenseurs / échelles : chaque Stairs a target_cell == cell et
## target_floor = floor_index ± 1 (toutes les grilles ont la même taille).
## Salles super_loot : salle des échantillons (-1, clef key_uw_lab) et chambre forte
## de la fosse (-2, clef key_uw_trench), annexes verrouillées gardées par l'élite ;
## antre du Gardien des Profondeurs (boss) au fond de la Fosse.
## Déterministe (RandomNumberGenerator seedés). Réglages : [underwater] de balance.cfg
## (repli sur [generator]).

const Station := preload("res://scripts/biomes/underwater/uw_station.gd")
const Pop := preload("res://scripts/biomes/underwater/uw_populator.gd")

const DIFFICULTY_MIN := 0
const DIFFICULTY_MAX := 4


static func generate_run(seed: int, world: WorldData, difficulty: int) -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	if world == null:
		push_error("UnderwaterGenerator: world est null.")
		return out
	var diff := clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX)
	var results := _structures(seed, world, mini(world.floors_min, 0))
	for idx: int in results:
		var res: Station.Result = results[idx]
		Pop.populate(res.layout, world, seed, diff, res.blocked)
	var keys: Array = results.keys()
	keys.sort()
	for k: int in keys:
		out.append((results[k] as Station.Result).layout)
	return out


static func generate_floor(seed: int, world: WorldData, difficulty: int, floor_index: int) -> FloorLayout:
	if world == null:
		push_error("UnderwaterGenerator: world est null.")
		return null
	if floor_index < mini(world.floors_min, 0) or floor_index > 0 or floor_index < world.floors_min:
		return null
	var diff := clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX)
	# Les étages supérieurs conditionnent les escaliers : on refait leur structure.
	var results := _structures(seed, world, floor_index)
	if not results.has(floor_index):
		return null
	var res: Station.Result = results[floor_index]
	Pop.populate(res.layout, world, seed, diff, res.blocked)
	return res.layout


## Structures des étages 0 → `down_to` (borné par world.floors_min) : {index: Result}.
static func _structures(seed: int, world: WorldData, down_to: int) -> Dictionary:
	var out := {}
	var lowest := mini(world.floors_min, 0)
	var last := maxi(down_to, lowest)
	var up: Array[Vector2i] = []
	var idx := 0
	while idx >= last:
		var res := Station.build(seed, idx, up, idx > lowest)
		if res == null:
			break
		out[idx] = res
		up = res.down_stairs
		idx -= 1
	return out


## Recherche d'un étage dans le résultat de generate_run (null si absent).
static func find_floor(floors: Array[FloorLayout], floor_index: int) -> FloorLayout:
	for f in floors:
		if f.floor_index == floor_index:
			return f
	return null
