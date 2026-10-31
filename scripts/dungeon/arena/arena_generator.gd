class_name ArenaGenerator
extends RefCounted
## Générateur de l'« Arène de test » (mode dev) : un seul étage, une salle ouverte rectangulaire
## bordée de murs, quelques murets et couverts, aucun ennemi, aucun conteneur, aucune extraction.
## Appelé par le Raid via WorldData.generator_path (data/worlds/dev/world_test_arena.tres).
## Taille : balance.cfg [test_arena] width_cells / height_cells.

## Couverts (level design, en fractions de la salle intérieure) : centre et taille en cases.
## Les ennemis apparaissent en haut, derrière les murets ; les mannequins sont au milieu, visibles
## dès l'apparition du joueur (en bas).
const COVERS: Array[Dictionary] = [
	{"at": Vector2(0.24, 0.3), "size": Vector2i(4, 1)},
	{"at": Vector2(0.76, 0.3), "size": Vector2i(4, 1)},
	{"at": Vector2(0.5, 0.22), "size": Vector2i(1, 3)},
	{"at": Vector2(0.1, 0.72), "size": Vector2i(2, 2)},
	{"at": Vector2(0.9, 0.72), "size": Vector2i(2, 2)},
]
## Point d'apparition du joueur (fraction de la salle intérieure).
const PLAYER_SPAWN := Vector2(0.5, 0.8)


static func generate_run(_seed: int, _world: Resource, _difficulty: int) -> Array[FloorLayout]:
	var out: Array[FloorLayout] = []
	out.append(build_layout())
	return out


## Étage de l'arène (pur, testable sans Raid).
static func build_layout() -> FloorLayout:
	var size := Vector2i(maxi(int(Balance.get_value("test_arena", "width_cells", 30)), 12),
		maxi(int(Balance.get_value("test_arena", "height_cells", 22)), 10))
	var l := FloorLayout.new(size)
	l.floor_index = 0
	l.fill_rect(Rect2i(Vector2i.ZERO, size), FloorLayout.Tile.WALL)
	var inner := Rect2i(Vector2i.ONE, size - Vector2i(2, 2))
	l.fill_rect(inner, FloorLayout.Tile.STREET)
	l.add_room(inner, true, FloorLayout.ROOM_SPAWN, "Arène de test")
	for c: Dictionary in COVERS:
		var sz: Vector2i = c["size"]
		var center := cell_at(inner, c["at"] as Vector2)
		l.fill_rect(Rect2i(center - sz / 2, sz), FloorLayout.Tile.WALL)
	l.player_spawn = cell_at(inner, PLAYER_SPAWN)
	return l


## Case de la salle intérieure à la fraction `f` (0..1 sur chaque axe).
static func cell_at(inner: Rect2i, f: Vector2) -> Vector2i:
	return inner.position + Vector2i(roundi(f.x * float(inner.size.x - 1)), roundi(f.y * float(inner.size.y - 1)))


## Salle intérieure (hors murs d'enceinte) d'un étage d'arène.
static func inner_rect(l: FloorLayout) -> Rect2i:
	return Rect2i(Vector2i.ONE, l.size - Vector2i(2, 2))
