class_name WorldData
extends Resource
## Description d'un monde (biome) : palette, ennemis par type de salle,
## archétypes de bâtiments, conteneurs et décors autorisés, étages.
## Consommé par DungeonGenerator (structure + spawns) et WorldBuilder (rendu).

## Identifiant technique (ex. &"world_01_far_west").
@export var id: StringName = &""
## Nom affiché (nom de la ville).
@export var display_name: String = ""
## Biome (ex. &"far_west").
@export var biome: StringName = &""
## Couleurs du biome : clé String → Color. Clés attendues par les constructeurs :
## void, street, floor, wall, stairs, extraction, + clés libres (sand, wood, adobe,
## sky_top, sky_bottom, shadow…).
@export var palette: Dictionary = {}
## Type de salle (StringName, cf. FloorLayout.ROOM_*) → { kind ennemi (StringName) : poids (float) }.
## Le type « combat » sert de repli pour les types absents.
@export var enemy_roster: Dictionary = {}
## Archétypes de bâtiments disponibles (saloon, bank, sheriff, store, hotel, stable, church, mine).
@export var building_archetypes: Array[StringName] = []
## Noms possibles par archétype : archétype (StringName) → PackedStringArray.
@export var building_names: Dictionary = {}
## Conteneurs fouillables autorisés dans ce monde.
@export var container_kinds: Array[StringName] = []
## Décors autorisés dans ce monde.
@export var prop_kinds: Array[StringName] = []
## Étages possibles : -1 = sous-sol, 0 = rez-de-chaussée, 1 = étage.
@export var floors_min: int = -1
@export var floors_max: int = 1
## Ennemi de boss du monde (salle boss du sous-sol).
@export var boss_kind: StringName = &""


## Poids des ennemis pour un type de salle (repli sur « combat »).
func get_roster(room_type: StringName) -> Dictionary:
	if enemy_roster.has(room_type):
		return enemy_roster[room_type]
	if enemy_roster.has(String(room_type)):
		return enemy_roster[String(room_type)]
	if enemy_roster.has(&"combat"):
		return enemy_roster[&"combat"]
	return enemy_roster.get("combat", {})


func has_archetype(a: StringName) -> bool:
	return building_archetypes.has(a)


func has_prop(k: StringName) -> bool:
	return prop_kinds.is_empty() or prop_kinds.has(k)


func has_container(k: StringName) -> bool:
	return container_kinds.is_empty() or container_kinds.has(k)


func get_color(key: String, fallback: Color = Color.MAGENTA) -> Color:
	var c: Variant = palette.get(key, null)
	return c if c is Color else fallback
