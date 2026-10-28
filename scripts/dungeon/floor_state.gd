class_name FloorState
extends RefCounted
## Mémoire d'un étage quitté pendant un raid (restaurée au retour par les escaliers).
## Pur données : ennemis vivants, état des portes, exploration du brouillard.

## Un dictionnaire par ennemi vivant : {data: EnemyData, position: Vector2,
## spawn_position: Vector2, hp: float}.
var enemies: Array[Dictionary] = []
## Case de porte (Vector2i) → FloorLayout.DoorState.
var doors: Dictionary = {}
## Cases (meta `turret_cell`) des tourelles détruites : elles ne réapparaissent pas au retour.
var destroyed_turrets: Array[Vector2i] = []
## Exploration du brouillard (FogOfWar.get_state()), vide si pas de brouillard.
var fog: PackedByteArray = PackedByteArray()


func get_enemy_count() -> int:
	return enemies.size()


func get_open_door_count() -> int:
	var n := 0
	for c: Vector2i in doors:
		if int(doors[c]) == FloorLayout.DoorState.OPEN:
			n += 1
	return n
