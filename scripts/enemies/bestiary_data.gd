class_name BestiaryData
extends Resource
## Bestiaire d'un monde qui n'a pas encore de carte (data/bestiary/<monde>.tres) : mêmes champs
## que WorldData (enemy_roster, elite_kinds, boss_kind), à recopier dans le WorldData du monde
## quand sa carte sera créée.

@export var world_id: StringName = &""
@export var display_name: String = ""
## Type de salle (FloorLayout.ROOM_*) → {kind ennemi : poids}. « combat » sert de repli.
@export var enemy_roster: Dictionary = {}
## Les 2 élites du monde.
@export var elite_kinds: Array[StringName] = []
## Le boss du monde (un seul par raid).
@export var boss_kind: StringName = &""
