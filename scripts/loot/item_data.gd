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
## Type key : équipement que la clef devient dans la réserve à l'extraction (clef de trappe).
@export var weapon_id: StringName = &""
## Type weapon : affixes tirés au drop de CET exemplaire (objet dupliqué par Affixes.make_item ;
## vide sur les objets data/items/wpn_*.tres partagés).
@export var weapon_affixes: Array[StringName] = []


func is_weapon() -> bool:
	return type == TYPE_WEAPON and not String(weapon_id).is_empty()


## Arme ou équipement que l'objet devient dans la réserve à l'extraction (&"" : objet gardé
## tel quel) : armes du sac, clef de trappe → gadget.
func reserve_weapon_id() -> StringName:
	return weapon_id if is_weapon() or (type == TYPE_KEY and not String(weapon_id).is_empty()) else &""


## Exemplaire d'arme représenté (affixes compris), null si ce n'est pas une arme.
func get_weapon() -> WeaponData:
	if not is_weapon():
		return null
	return Affixes.make_weapon(WeaponCatalog.get_weapon(weapon_id), weapon_affixes)


## Clé d'exemplaire (regroupement du sac) : l'id, + les affixes d'une arme.
func instance_key() -> String:
	return Affixes.key_for(id, weapon_affixes) if not weapon_affixes.is_empty() else String(id)


func is_stackable() -> bool:
	return stack_max > 1


func is_key() -> bool:
	return type == TYPE_KEY


func is_usable() -> bool:
	return type == TYPE_CONSUMABLE and heal_amount > 0.0
