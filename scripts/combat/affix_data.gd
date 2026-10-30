class_name AffixData
extends Resource
## Affixe d'arme tiré au hasard à chaque drop (phase 8). Une ressource par affixe :
## data/affixes/<id>.tres. `kind` choisit l'effet codé (KIND_*) ; les valeurs sont dans la
## ressource, donc une variante (« Brûlure intense ») s'ajoute sans toucher au code : nouveau
## .tres avec le même `kind` et d'autres valeurs.
##
## Champs utilisés selon `kind` (les autres sont ignorés) :
##   burn      : ratio = dégâts de brûlure TOTAUX en part des dégâts du coup, duration (s)
##   freeze    : slow = ralentissement (0..1, vitesse × (1 − slow)), duration (s)
##   ricochet  : count = rebonds, radius = portée de recherche d'un autre ennemi (px),
##               damage_mult = dégâts conservés à chaque rebond
##   multishot : count = projectiles en plus par tir, spread_deg = éventail ajouté (°)
##   lifesteal : ratio = part des dégâts infligés rendue en PV au tireur
##   shockwave : radius (px), ratio = dégâts de l'onde en part des dégâts du coup
## `chance` : probabilité de déclenchement par impact (1 = toujours ; sans objet pour multishot).
## Les affixes FIXES d'un modèle (WeaponData.affixes : salvo, homing) ne passent pas par ici.

const KIND_BURN := &"burn"
const KIND_FREEZE := &"freeze"
const KIND_RICOCHET := &"ricochet"
const KIND_MULTISHOT := &"multishot"
const KIND_LIFESTEAL := &"lifesteal"
const KIND_SHOCKWAVE := &"shockwave"
const KINDS: Array[StringName] = [KIND_BURN, KIND_FREEZE, KIND_RICOCHET, KIND_MULTISHOT, KIND_LIFESTEAL, KIND_SHOCKWAVE]

@export var id: StringName = &""
@export var display_name: String = ""
## Effet en quelques mots (cartes d'arme, lisible sur mobile).
@export var description: String = ""
@export var kind: StringName = KIND_BURN
## Poids de tirage (0 = jamais tiré).
@export var weight: float = 1.0
## Catégories d'armes autorisées (WeaponData.CAT_*) ; vide = toutes les armes (jamais les équipements).
@export var categories: Array[StringName] = []
## Couleur de la pastille (UI) et des effets en jeu.
@export var color: Color = Color(1, 1, 1)

@export_group("Valeurs")
@export var ratio: float = 0.0
@export var duration: float = 0.0
@export var slow: float = 0.0
@export var count: int = 0
@export var radius: float = 0.0
@export var damage_mult: float = 1.0
@export var spread_deg: float = 0.0
@export_range(0.0, 1.0) var chance: float = 1.0


## Effet court affiché : `description` où {ratio}, {slow} (en %), {duration}, {count}, {radius},
## {damage_mult} (en %), {spread_deg}, {chance} (en %) sont remplacés par les valeurs de la
## ressource (une seule source pour les chiffres).
func effect_text() -> String:
	return description.format({
		"ratio": _pct(ratio), "slow": _pct(slow), "duration": _num(duration), "count": str(count),
		"radius": str(roundi(radius)), "damage_mult": _pct(damage_mult), "spread_deg": _num(spread_deg),
		"chance": _pct(chance),
	})


static func _pct(v: float) -> String:
	return str(roundi(v * 100.0))


## Nombre court à la française (« 1,5 », « 3 »).
static func _num(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(roundi(v))
	return String.num(v, 1).replace(".", ",")


## Cet affixe peut-il apparaître sur cette arme ? (jamais sur un équipement)
func allows(w: WeaponData) -> bool:
	if w == null or w.is_gadget() or weight <= 0.0:
		return false
	return categories.is_empty() or categories.has(w.category)
