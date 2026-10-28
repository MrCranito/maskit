class_name FloorLayout
extends RefCounted
## Description pure-données d'un étage de carte (grille de tuiles + salles,
## bâtiments, portes, escaliers, points d'apparition). Produit par le
## générateur, consommé par le constructeur de monde, le brouillard et l'IA.
## Aucune dépendance à la scène : sérialisable et testable.

enum Tile {
	VOID = 0,          ## Hors carte (infranchissable, opaque)
	STREET = 1,        ## Sol extérieur (rue, ruelle, place)
	FLOOR = 2,         ## Sol intérieur (plancher)
	WALL = 3,          ## Mur (infranchissable, opaque)
	DOOR = 4,          ## Case porte (franchissable si ouverte ; opaque si fermée)
	STAIRS_UP = 5,     ## Escalier vers l'étage supérieur
	STAIRS_DOWN = 6,   ## Escalier vers l'étage inférieur
}

enum DoorState { OPEN = 0, CLOSED = 1, LOCKED = 2 }

## Taille d'une case en unités monde.
const TILE_SIZE := 64


static func cell_to_world(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE_SIZE


static func world_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE_SIZE), floori(p.y / TILE_SIZE))

## Types de salles
const ROOM_SPAWN := &"spawn"
const ROOM_COMBAT := &"combat"
const ROOM_LOOT := &"loot"
const ROOM_TRAP := &"trap"
const ROOM_REST := &"rest"
const ROOM_SUPER_LOOT := &"super_loot"
const ROOM_BOSS := &"boss"
const ROOM_EXTRACTION := &"extraction"
const ROOM_CORRIDOR := &"corridor"


class Room:
	var id: int = -1
	var rect: Rect2i                 ## En cases
	var outdoor: bool = false        ## Rue/ruelle/place (true) ou intérieur (false)
	var building_id: int = -1        ## -1 si extérieur
	var type: StringName = &"combat"
	var name: String = ""            ## Ex. « Salle principale du saloon »
	var tags: PackedStringArray = PackedStringArray()


class Building:
	var id: int = -1
	var archetype: StringName = &"saloon"  ## saloon, bank, sheriff, store, hotel, stable, church, mine
	var name: String = ""
	var rect: Rect2i                 ## Emprise extérieure (murs compris), en cases
	var room_ids: PackedInt32Array = PackedInt32Array()
	var door_ids: PackedInt32Array = PackedInt32Array()


class Door:
	var id: int = -1
	var cell: Vector2i
	var vertical: bool = false       ## true : porte dans un mur vertical (on la traverse horizontalement)
	var state: int = DoorState.CLOSED
	var key_id: StringName = &""     ## Clef requise si LOCKED
	var room_a: int = -1
	var room_b: int = -1


class Stairs:
	var cell: Vector2i
	var up: bool = true
	var target_floor: int = 0
	var target_cell: Vector2i


class Spawn:
	var cell: Vector2i
	var kind: StringName             ## Ennemi (golem…), conteneur (crate…) ou décor (cactus…)
	var room_id: int = -1


var floor_index: int = 0             ## 0 = rez-de-chaussée, 1 = étage, -1 = sous-sol
var size: Vector2i = Vector2i.ZERO   ## En cases
var tiles: PackedByteArray = PackedByteArray()
var rooms: Array[Room] = []
var buildings: Array[Building] = []
var doors: Array[Door] = []
var stairs: Array[Stairs] = []
var player_spawn: Vector2i = Vector2i.ZERO
var extraction_cells: Array[Vector2i] = []
var enemy_spawns: Array[Spawn] = []
var container_spawns: Array[Spawn] = []
var prop_spawns: Array[Spawn] = []
## Cachettes (kind : barrel, wardrobe, haystack, porch). Bloquantes comme les conteneurs.
## Peut rester vide (cartes écrites à la main, anciens générateurs).
var hiding_spot_spawns: Array[Spawn] = []


func _init(p_size: Vector2i = Vector2i.ZERO) -> void:
	resize(p_size)


func resize(p_size: Vector2i) -> void:
	size = p_size
	tiles = PackedByteArray()
	tiles.resize(maxi(size.x * size.y, 0))
	tiles.fill(Tile.VOID)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func get_tile(c: Vector2i) -> int:
	if not in_bounds(c):
		return Tile.VOID
	return tiles[c.y * size.x + c.x]


func set_tile(c: Vector2i, t: int) -> void:
	if in_bounds(c):
		tiles[c.y * size.x + c.x] = t


func fill_rect(r: Rect2i, t: int) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			set_tile(Vector2i(x, y), t)


## Remplit r avec `inner`, entouré d'un contour de murs.
func carve_walled_rect(r: Rect2i, inner: int) -> void:
	fill_rect(r, Tile.WALL)
	fill_rect(r.grow(-1), inner)


static func is_walkable_tile(t: int) -> bool:
	return t == Tile.STREET or t == Tile.FLOOR or t == Tile.DOOR \
		or t == Tile.STAIRS_UP or t == Tile.STAIRS_DOWN


## Opacité de la tuile seule (les portes sont gérées par l'état de la porte).
static func is_opaque_tile(t: int) -> bool:
	return t == Tile.WALL or t == Tile.VOID


func get_door_at(c: Vector2i) -> Door:
	for d in doors:
		if d.cell == c:
			return d
	return null


func get_room(id: int) -> Room:
	for r in rooms:
		if r.id == id:
			return r
	return null


## Salle qui contient la case c (la plus petite si chevauchement), ou null.
func room_at(c: Vector2i) -> Room:
	var best: Room = null
	for r in rooms:
		if r.rect.has_point(c):
			if best == null or r.rect.get_area() < best.rect.get_area():
				best = r
	return best


func add_room(rect: Rect2i, outdoor: bool, type: StringName, name: String, building_id: int = -1) -> Room:
	var r := Room.new()
	r.id = rooms.size()
	r.rect = rect
	r.outdoor = outdoor
	r.type = type
	r.name = name
	r.building_id = building_id
	rooms.append(r)
	if building_id >= 0:
		buildings[building_id].room_ids.append(r.id)
	return r


func add_building(archetype: StringName, name: String, rect: Rect2i) -> Building:
	var b := Building.new()
	b.id = buildings.size()
	b.archetype = archetype
	b.name = name
	b.rect = rect
	buildings.append(b)
	return b


func add_door(cell: Vector2i, vertical: bool, state: int, room_a: int, room_b: int, key_id: StringName = &"", building_id: int = -1) -> Door:
	var d := Door.new()
	d.id = doors.size()
	d.cell = cell
	d.vertical = vertical
	d.state = state
	d.key_id = key_id
	d.room_a = room_a
	d.room_b = room_b
	doors.append(d)
	set_tile(cell, Tile.DOOR)
	if building_id >= 0:
		buildings[building_id].door_ids.append(d.id)
	return d


func add_spawn(list: Array[Spawn], cell: Vector2i, kind: StringName, room_id: int = -1) -> Spawn:
	var s := Spawn.new()
	s.cell = cell
	s.kind = kind
	s.room_id = room_id
	list.append(s)
	return s


## Cases atteignables depuis `from` en traversant toutes les portes (même verrouillées
## si `through_locked`). Sert aux tests de connectivité.
func flood_reachable(from: Vector2i, through_locked: bool = true) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n := c + dir
			if seen.has(n) or not is_walkable_tile(get_tile(n)):
				continue
			if get_tile(n) == Tile.DOOR and not through_locked:
				var d := get_door_at(n)
				if d and d.state == DoorState.LOCKED:
					continue
			seen[n] = true
			queue.append(n)
	return seen


## Petite carte écrite à la main (rez-de-chaussée d'une ville Far West) pour
## développer constructeur de monde, brouillard et IA avant le générateur.
## Rue principale horizontale, saloon (2 salles + escalier), banque (hall +
## coffre-fort verrouillé), bureau du shérif, ruelle vers la sortie.
static func make_sample() -> FloorLayout:
	var L := FloorLayout.new(Vector2i(40, 30))
	# Rue principale (couloir extérieur) et ruelle
	L.fill_rect(Rect2i(1, 12, 38, 6), Tile.STREET)
	L.fill_rect(Rect2i(30, 18, 4, 11), Tile.STREET)
	var street := L.add_room(Rect2i(1, 12, 38, 6), true, ROOM_SPAWN, "Rue principale")
	var alley := L.add_room(Rect2i(30, 18, 4, 11), true, ROOM_EXTRACTION, "Ruelle du maréchal-ferrant")

	# Saloon au nord-ouest : grande salle + arrière-salle
	var saloon := L.add_building(&"saloon", "Saloon du Masque Rouge", Rect2i(2, 2, 14, 11))
	L.carve_walled_rect(Rect2i(2, 2, 14, 11), Tile.FLOOR)
	L.fill_rect(Rect2i(10, 3, 1, 9), Tile.WALL)  # cloison
	var hall := L.add_room(Rect2i(3, 3, 7, 9), false, ROOM_COMBAT, "Salle du saloon", saloon.id)
	var back := L.add_room(Rect2i(11, 3, 4, 9), false, ROOM_LOOT, "Arrière-salle", saloon.id)
	L.add_door(Vector2i(6, 12), false, DoorState.CLOSED, street.id, hall.id, &"", saloon.id)
	L.add_door(Vector2i(10, 7), true, DoorState.CLOSED, hall.id, back.id, &"", saloon.id)
	L.set_tile(Vector2i(13, 4), Tile.STAIRS_UP)
	var st := Stairs.new()
	st.cell = Vector2i(13, 4)
	st.up = true
	st.target_floor = 1
	st.target_cell = Vector2i(13, 4)
	L.stairs.append(st)

	# Banque au nord-est : hall + coffre-fort (super-loot verrouillé)
	var bank := L.add_building(&"bank", "Banque de Dust Creek", Rect2i(20, 3, 12, 10))
	L.carve_walled_rect(Rect2i(20, 3, 12, 10), Tile.FLOOR)
	L.fill_rect(Rect2i(20, 7, 12, 1), Tile.WALL)
	var lobby := L.add_room(Rect2i(21, 8, 10, 4), false, ROOM_COMBAT, "Hall de la banque", bank.id)
	var vault := L.add_room(Rect2i(21, 4, 10, 3), false, ROOM_SUPER_LOOT, "Coffre-fort", bank.id)
	L.add_door(Vector2i(25, 12), false, DoorState.CLOSED, street.id, lobby.id, &"", bank.id)
	L.add_door(Vector2i(25, 7), false, DoorState.LOCKED, lobby.id, vault.id, &"key_bank_vault", bank.id)

	# Bureau du shérif au sud-ouest
	var sheriff := L.add_building(&"sheriff", "Bureau du shérif", Rect2i(4, 17, 11, 9))
	L.carve_walled_rect(Rect2i(4, 17, 11, 9), Tile.FLOOR)
	var office := L.add_room(Rect2i(5, 18, 9, 7), false, ROOM_COMBAT, "Bureau", sheriff.id)
	L.add_door(Vector2i(9, 17), false, DoorState.OPEN, street.id, office.id, &"", sheriff.id)

	L.player_spawn = Vector2i(3, 14)
	L.extraction_cells = [Vector2i(31, 27), Vector2i(32, 27)]
	L.add_spawn(L.enemy_spawns, Vector2i(6, 6), &"masked_grunt", hall.id)
	L.add_spawn(L.enemy_spawns, Vector2i(8, 9), &"masked_grunt", hall.id)
	L.add_spawn(L.enemy_spawns, Vector2i(27, 10), &"masked_archer", lobby.id)
	L.add_spawn(L.enemy_spawns, Vector2i(18, 15), &"masked_brute", street.id)
	L.add_spawn(L.enemy_spawns, Vector2i(9, 21), &"masked_grunt", office.id)
	L.add_spawn(L.enemy_spawns, Vector2i(26, 5), &"golem", vault.id)
	L.add_spawn(L.container_spawns, Vector2i(12, 10), &"crate", back.id)
	L.add_spawn(L.container_spawns, Vector2i(23, 5), &"chest", vault.id)
	L.add_spawn(L.container_spawns, Vector2i(13, 22), &"cupboard", office.id)
	L.add_spawn(L.prop_spawns, Vector2i(15, 13), &"hitching_post", street.id)
	L.add_spawn(L.prop_spawns, Vector2i(36, 16), &"cactus", street.id)
	L.add_spawn(L.prop_spawns, Vector2i(33, 20), &"wagon", alley.id)
	L.add_spawn(L.prop_spawns, Vector2i(4, 4), &"saloon_bar", hall.id)
	return L
