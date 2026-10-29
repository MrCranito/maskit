class_name RecipeData
extends Resource
## Recette d'artisanat (atelier) : data/recipes/<id>.tres. Ajouter une recette = ajouter un .tres.
## Résultat : un objet (`result_item_id`, va dans Profile.items) OU un équipement
## (`result_weapon_id`, gadget ajouté à la réserve d'armes Profile.weapons), × `result_count`.
## Ingrédients : {clé: quantité}. Clé = id d'objet (data/items) ou « @groupe » : n'importe quel
## objet du groupe (balance.cfg [crafting] group_<groupe>, ex. @mechanism = rouages, circuits,
## piles, composants). Coût en or éventuel. Fabrication instantanée (craft_time = 0).

## Catégories d'affichage (onglets de l'atelier).
const CAT_HEAL := &"heal"
const CAT_GADGET := &"gadget"

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: StringName = CAT_HEAL
## Objet produit (data/items/<id>.tres) ; vide si la recette produit un équipement.
@export var result_item_id: StringName = &""
## Équipement produit (data/weapons/<id>.tres, slot gadget) ; vide si la recette produit un objet.
@export var result_weapon_id: StringName = &""
@export var result_count: int = 1
## {id d'objet ou « @groupe »: quantité}
@export var ingredients: Dictionary = {}
## Pièces d'or demandées en plus des ingrédients.
@export var gold_cost: int = 0
## Durée de fabrication (s) : 0 = instantané.
@export var craft_time: float = 0.0
## Ordre d'affichage.
@export var sort_order: int = 0


func is_weapon_result() -> bool:
	return not String(result_weapon_id).is_empty()


## WeaponData produit (null si la recette donne un objet).
func get_result_weapon() -> WeaponData:
	return WeaponCatalog.get_weapon(result_weapon_id) if is_weapon_result() else null


## ItemData produit (objet, ou objet « arme » wpn_<id> pour un équipement).
func get_result_item() -> ItemData:
	if is_weapon_result():
		return LootDB.weapon_item(get_result_weapon())
	return LootDB.get_item(result_item_id)


## Nom du résultat (objet ou équipement).
func result_name() -> String:
	var w := get_result_weapon()
	if w != null:
		return w.display_name
	var it := LootDB.get_item(result_item_id)
	return it.display_name if it != null else display_name


## Rareté du résultat (couleur de la carte).
func result_rarity() -> int:
	var w := get_result_weapon()
	if w != null:
		return w.rarity
	var it := LootDB.get_item(result_item_id)
	return it.rarity if it != null else 0
