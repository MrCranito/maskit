class_name SpaceStationGenerator
extends RefCounted
## Générateur de la Station Orbitale Kagami (biome space_station).
##
## API (contrat docs/CONVENTIONS.md, « Cartes et biomes ») :
##   SpaceStationGenerator.generate_run(seed, world, difficulty) -> Array[FloorLayout]
##       Ponts triés par floor_index : -1 « Salle des machines », 0 « Pont principal »,
##       1 « Pont de commandement » (bornés par world.floors_min / floors_max ; le pont 0
##       est toujours présent).
##   SpaceStationGenerator.generate_floor(seed, world, difficulty, floor_index) -> FloorLayout
##       Même pont que dans generate_run (null si absent).
##
## Structure : coursives fermées de 2-3 cases en grille (squelette commun aux ponts),
## modules rectangulaires ou octogonaux derrière des portes à sas, hangar d'arrivée ouvert,
## baie des capsules de sauvetage (extraction), cages d'ascenseur aux mêmes coordonnées
## sur deux ponts (Stairs.target_cell == cell). Salles scellées (super_loot) : une seule
## porte verrouillée par une clef du biome (key_space_lab, key_space_armory,
## key_space_reactor). Boss (« Colosse du réacteur ») dans la salle du réacteur (pont -1).
## Déterministe (RandomNumberGenerator issus de la seed). Réglages : [space_station].

const Deck := preload("res://scripts/biomes/space_station/ss_deck.gd")
const Pop := preload("res://scripts/biomes/space_station/ss_populator.gd")

const DIFFICULTY_MIN := 0
const DIFFICULTY_MAX := 4
const KEYS: Array[StringName] = [&"key_space_lab", &"key_space_armory", &"key_space_reactor"]


static func generate_run(seed_value: int, world: WorldData, difficulty: int) -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	if world == null:
		push_error("SpaceStationGenerator: world est null.")
		return out
	var plan: Deck.Plan = Deck.make_plan(seed_value)
	for idx: int in [-1, 0, 1]:
		if idx != 0 and (idx < world.floors_min or idx > world.floors_max):
			continue
		var L := _deck(plan, world, seed_value, difficulty, idx)
		if L != null:
			out.append(L)
	# Escaliers vers un pont absent (monde limité) : retirés pour rester cohérent.
	var present := {}
	for f in out:
		present[f.floor_index] = true
	for f2 in out:
		for i in range(f2.stairs.size() - 1, -1, -1):
			var st := f2.stairs[i]
			if not present.has(st.target_floor):
				f2.set_tile(st.cell, FloorLayout.Tile.FLOOR)
				f2.stairs.remove_at(i)
	return out


static func generate_floor(seed_value: int, world: WorldData, difficulty: int, floor_index: int) -> FloorLayout:
	if world == null:
		return null
	if floor_index < -1 or floor_index > 1:
		return null
	if floor_index != 0 and (floor_index < world.floors_min or floor_index > world.floors_max):
		return null
	var plan: Deck.Plan = Deck.make_plan(seed_value)
	var L := _deck(plan, world, seed_value, difficulty, floor_index)
	if L == null:
		return null
	for i in range(L.stairs.size() - 1, -1, -1):
		var st := L.stairs[i]
		if st.target_floor != 0 and (st.target_floor < world.floors_min or st.target_floor > world.floors_max):
			L.set_tile(st.cell, FloorLayout.Tile.FLOOR)
			L.stairs.remove_at(i)
	return L


static func _deck(plan: Deck.Plan, world: WorldData, seed_value: int, difficulty: int, idx: int) -> FloorLayout:
	var d: Deck.Deck = Deck.build(plan, idx, seed_value)
	if d == null:
		return null
	Pop.populate(d.layout, world, seed_value, clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX))
	return d.layout


## Recherche d'un pont dans le résultat de generate_run (null si absent).
static func find_floor(floors: Array[FloorLayout], floor_index: int) -> FloorLayout:
	for f in floors:
		if f.floor_index == floor_index:
			return f
	return null
