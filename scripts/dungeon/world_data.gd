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
## Boss du monde : UN SEUL par raid (salle boss de l'étage le plus profond / dangereux).
@export var boss_kind: StringName = &""
## Les 2 élites du monde (gardes des salles au trésor, renforts du boss, rares ailleurs).
@export var elite_kinds: Array[StringName] = []

@export_group("Modules du biome")
## Générateur : script avec `static func generate_run(seed, world, difficulty) -> Array[FloorLayout]`.
@export var generator_path: String = "res://scripts/dungeon/dungeon_generator.gd"
## Constructeur de décor : script avec `static func build(layout, world) -> Node2D`
## (même API que WorldBuilder : get_doors, get_stairs_areas, signal stairs_entered,
## get_room_at_world, set_stairs_cooldown).
@export var builder_path: String = "res://scripts/dungeon/world_builder.gd"
## Dossier des sprites de conteneurs et cachettes (<kind>.svg|png, <kind>_open.*, hide_<kind>.*).
@export var containers_dir: String = "res://assets/sprites/far_west/containers/"
## Noms d'étage affichés : floor_index (int) → String (ex. {0: "Rez-de-chaussée"}).
@export var floor_names: Dictionary = {}
## Musique d'exploration / de combat (noms AudioManager).
@export var music_explore: StringName = &"western_explore"
@export var music_combat: StringName = &"western_combat"


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
