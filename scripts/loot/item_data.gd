class_name ItemData
extends Resource
## Objet ramassable (butin de raid). Une ressource par objet : data/items/<id>.tres.
## Ajouter un objet = ajouter un .tres (aucun code à toucher), puis le référencer
## dans une ou plusieurs tables (data/loot_tables/<conteneur>.tres).

enum Rarity { COMMON = 0, UNCOMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4 }

const TYPE_WEAPON := &"weapon"
const TYPE_AMMO := &"ammo"
const TYPE_CONSUMABLE := &"consumable"
const TYPE_VALUABLE := &"valuable"
const TYPE_KEY := &"key"
const TYPE_MATERIAL := &"material"
const TYPES: Array[StringName] = [TYPE_WEAPON, TYPE_AMMO, TYPE_CONSUMABLE, TYPE_VALUABLE, TYPE_KEY, TYPE_MATERIAL]

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Icône (SVG blanc, teinté par `tint` à l'affichage).
@export var icon: Texture2D = null
## Teinte de l'icône (blanc = icône telle quelle).
@export var tint: Color = Color.WHITE
## 0 Commun · 1 Peu commun · 2 Rare · 3 Épique · 4 Légendaire
@export_range(0, 4) var rarity: int = 0
## weapon, ammo, consumable, valuable, key, material
@export var type: StringName = TYPE_VALUABLE
## Taille maximale d'une pile dans une case.
@export var stack_max: int = 1
## Valeur marchande (dollars) d'une unité.
@export var value: int = 1
## Encombrement d'une unité (kg) : l'inventaire de raid a un poids maximal.
@export var weight: float = 0.5
## Quantité tirée quand l'objet sort d'une table de butin.
@export var drop_min: int = 1
@export var drop_max: int = 1
## Consommable : PV rendus à l'utilisation (0 = non utilisable).
@export var heal_amount: float = 0.0
## Type weapon : id de l'arme (data/weapons/<weapon_id>.tres) que cet objet représente.
## Un objet arme dans le sac peut être équipé ; extrait, il rejoint l'arsenal (Profile).
@export var weapon_id: StringName = &""


func is_weapon() -> bool:
	return type == TYPE_WEAPON and not String(weapon_id).is_empty()


func is_stackable() -> bool:
	return stack_max > 1


func is_key() -> bool:
	return type == TYPE_KEY


func is_usable() -> bool:
	return type == TYPE_CONSUMABLE and heal_amount > 0.0
