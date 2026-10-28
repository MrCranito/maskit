class_name LootTable
extends Resource
## Table de butin pondérée d'un type de conteneur : data/loot_tables/<kind>.tres.
## Les poids de base sont modulés par rareté selon la difficulté, la profondeur
## d'étage et le type de salle (super_loot) — cf. LootRoller et [loot] dans balance.cfg.

@export var kind: StringName = &"crate"
@export var display_name: String = "Caisse"
## Nombre de tirages (objets distincts) : uniforme dans [rolls_min, rolls_max].
@export var rolls_min: int = 1
@export var rolls_max: int = 2
## Probabilité que le conteneur soit vide.
@export_range(0.0, 1.0) var empty_chance: float = 0.1
## Durée de fouille (s) ; <= 0 : valeur par défaut [loot] search_time.
@export var search_time: float = -1.0
## item_id → poids de base.
@export var entries: Dictionary = {}


func get_search_time(default_time: float) -> float:
	return search_time if search_time > 0.0 else default_time
