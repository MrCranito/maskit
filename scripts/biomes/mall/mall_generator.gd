class_name MallGenerator
extends RefCounted
## Générateur du biome « centre commercial abandonné » (Galeries Lumière).
##
## API (contrat docs/CONVENTIONS.md, « Cartes et biomes ») :
##   MallGenerator.generate_run(seed, world, difficulty) -> Array[FloorLayout]
##       4 étages triés par floor_index : -1 Parking, 0 Rez-de-chaussée, 1 Galerie haute,
##       2 Toits et bureaux (bornés par world.floors_min / floors_max ; 0 toujours présent).
##   MallGenerator.generate_floor(seed, world, difficulty, floor_index) -> FloorLayout (ou null)
##
## Tous les étages ont la même grille ; chaque escalier/escalator a target_cell == cell.
## Structure : scripts/biomes/mall/mall_layout.gd ; peuplement : mall_populator.gd ;
## réglages : section [mall] de data/balance.cfg (repli [generator]).
## Déterministe : RandomNumberGenerator initialisés depuis la seed uniquement.

const Layout := preload("res://scripts/biomes/mall/mall_layout.gd")
const Pop := preload("res://scripts/biomes/mall/mall_populator.gd")

const DIFFICULTY_MIN := 0
const DIFFICULTY_MAX := 4
const FLOOR_MIN := -1
const FLOOR_MAX := 2


static func generate_run(seed: int, world: WorldData, difficulty: int) -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	if world == null:
		push_error("MallGenerator: world est null.")
		return out
	var diff := clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX)
	var k := Layout.make_skeleton(seed)
	var lo := clampi(world.floors_min, FLOOR_MIN, 0)
	var hi := clampi(world.floors_max, 0, FLOOR_MAX)
	for idx in range(lo, hi + 1):
		var L := _structure(k, seed, idx, lo, hi)
		Pop.populate(L, world, seed, diff)
		out.append(L)
	return out


static func generate_floor(seed: int, world: WorldData, difficulty: int, floor_index: int) -> FloorLayout:
	if world == null:
		push_error("MallGenerator: world est null.")
		return null
	var lo := clampi(world.floors_min, FLOOR_MIN, 0)
	var hi := clampi(world.floors_max, 0, FLOOR_MAX)
	if floor_index < lo or floor_index > hi:
		return null
	var k := Layout.make_skeleton(seed)
	var L := _structure(k, seed, floor_index, lo, hi)
	Pop.populate(L, world, seed, clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX))
	return L


static func find_floor(floors: Array[FloorLayout], floor_index: int) -> FloorLayout:
	for f in floors:
		if f.floor_index == floor_index:
			return f
	return null


## Structure d'un étage ; les escaliers vers des étages absents du monde sont retirés.
static func _structure(k: Variant, seed: int, idx: int, lo: int, hi: int) -> FloorLayout:
	var L: FloorLayout
	match idx:
		-1:
			L = Layout.build_parking(k, seed)
		1:
			L = Layout.build_upper(k, seed)
		2:
			L = Layout.build_roof(k, seed)
		_:
			L = Layout.build_ground(k, seed)
	for i in range(L.stairs.size() - 1, -1, -1):
		var s := L.stairs[i]
		if s.target_floor < lo or s.target_floor > hi:
			L.set_tile(s.cell, FloorLayout.Tile.FLOOR if L.get_tile(s.cell + Vector2i.UP) == FloorLayout.Tile.FLOOR else FloorLayout.Tile.STREET)
			L.stairs.remove_at(i)
	return L
