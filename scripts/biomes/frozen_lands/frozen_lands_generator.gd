class_name FrozenLandsGenerator
extends RefCounted
## Générateur des Terres gelées (biome frozen_lands).
##
## API (contrat docs/CONVENTIONS.md, « Cartes et biomes ») :
##   FrozenLandsGenerator.generate_run(seed, world, difficulty) -> Array[FloorLayout]
##       Un seul étage (0) : la surface de la base sur son plateau de glace (fl_plan.gd), format
##       portrait 76×112, pré-rendue dans Blender (tools/prerender/fl_scene.py). Le sous-sol
##       « laboratoires enfouis » est prévu plus tard (world.floors_min = 0 pour l'instant).
##   FrozenLandsGenerator.generate_floor(seed, world, difficulty, floor_index) -> FloorLayout
##
## Structure : base militaire en croix autour du laboratoire circulaire aux cristaux (salle du
## boss, ouverte sur les 4 axes) ; bunkers à toit plat (fermés par des portes, toit qui s'efface),
## laboratoires et baraquements, hangars, postes de garde hexagonaux, dômes d'observation,
## héliport et ponton (extraction), rampe d'accès au sud (apparition). Salles scellées
## (super_loot) : labo cryogénique (fl_key_lab) et armurerie du bunker (fl_key_bunker), une seule
## porte verrouillée. Déterministe (seed). Réglages : [frozen_lands] de data/balance.cfg.

const Plan := preload("res://scripts/biomes/frozen_lands/fl_plan.gd")
const Pop := preload("res://scripts/biomes/frozen_lands/fl_populator.gd")

const DIFFICULTY_MIN := 0
const DIFFICULTY_MAX := 4
const KEYS: Array[StringName] = [&"fl_key_lab", &"fl_key_bunker"]


static func generate_run(seed_value: int, world: WorldData, difficulty: int) -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	if world == null:
		push_error("FrozenLandsGenerator: world est null.")
		return out
	var L := generate_floor(seed_value, world, difficulty, 0)
	if L != null:
		out.append(L)
	return out


static func generate_floor(seed_value: int, world: WorldData, difficulty: int, floor_index: int) -> FloorLayout:
	if world == null or floor_index != 0:
		return null
	var res: Plan.Result = Plan.build(seed_value)
	if res == null:
		return null
	var L := res.layout
	Pop.populate(L, world, seed_value, clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX))
	return L


## Recherche d'un étage dans le résultat de generate_run (null si absent).
static func find_floor(floors: Array[FloorLayout], floor_index: int) -> FloorLayout:
	for f in floors:
		if f.floor_index == floor_index:
			return f
	return null
