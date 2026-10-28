class_name WeaponData
extends Resource
## Données d'une arme. Chaque arme du jeu est une ressource .tres de ce type
## (data/weapons/<id>.tres), pour pouvoir ajouter des armes sans toucher au code.
## Une arme = un modèle avec une rareté fixe (ex. « Pistolet 9 mm » Commun,
## « Aigle du désert doré » Légendaire). Voir docs/CONVENTIONS.md, « Arsenal ».

enum Rarity { COMMUN, PEU_COMMUN, RARE, EPIQUE, LEGENDAIRE }

## Couleurs de rareté (charte du projet).
const RARITY_COLORS: Array[Color] = [
	Color(0.62, 0.62, 0.62),  # Commun : gris
	Color(0.30, 0.80, 0.30),  # Peu commun : vert
	Color(0.25, 0.55, 1.00),  # Rare : bleu
	Color(0.65, 0.30, 0.95),  # Épique : violet
	Color(1.00, 0.58, 0.10),  # Légendaire : orange
]
const RARITY_NAMES: Array[String] = ["Commun", "Peu commun", "Rare", "Épique", "Légendaire"]

## Catégories (champ `category`) — arsenal de la planche docs/reference/arsenal.jpg.
const CAT_PISTOL := &"pistol"
const CAT_SMG := &"smg"
const CAT_RIFLE := &"rifle"
const CAT_SNIPER := &"sniper"
const CAT_ROCKET := &"rocket_launcher"
## « Autres » : grenades, mine, C4, drone (emplacement d'équipement, voir `slot`).
const CAT_GADGET := &"gadget"
## Anciennes catégories (plus utilisées par le catalogue, gardées pour compatibilité).
const CAT_REVOLVER := &"revolver"
const CAT_SHOTGUN := &"shotgun"
const CAT_LMG := &"lmg"
const CAT_GRENADE := &"grenade_launcher"
const CATEGORIES: Array[StringName] = [CAT_PISTOL, CAT_SMG, CAT_RIFLE, CAT_SNIPER, CAT_ROCKET, CAT_GADGET]
const CATEGORY_NAMES: Dictionary = {
	CAT_PISTOL: "Pistolet", CAT_SMG: "Mitraillette", CAT_RIFLE: "Fusil d'assaut",
	CAT_SNIPER: "Fusil de sniper", CAT_ROCKET: "Lance-roquettes", CAT_GADGET: "Équipement",
	CAT_REVOLVER: "Revolver", CAT_SHOTGUN: "Fusil à pompe", CAT_LMG: "Mitrailleuse",
	CAT_GRENADE: "Lance-grenades",
}
## Titres de section (écran d'arsenal), dans l'ordre de CATEGORIES.
const CATEGORY_TITLES: Dictionary = {
	CAT_PISTOL: "Pistolets", CAT_SMG: "Mitraillettes", CAT_RIFLE: "Fusils d'assaut",
	CAT_SNIPER: "Fusils de sniper", CAT_ROCKET: "Lance-roquettes", CAT_GADGET: "Autres",
}

## Emplacement : arme (3 emplacements) ou équipement (1 emplacement).
const SLOT_WEAPON := &"weapon"
const SLOT_GADGET := &"gadget"
## Types d'équipement (champ `gadget_kind`).
const GADGET_FRAG := &"frag"
const GADGET_SMOKE := &"smoke"
const GADGET_MINE := &"mine"
const GADGET_C4 := &"c4"
const GADGET_DRONE := &"drone"

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Ancien champ (« firearm », « bow »…) : gardé pour compatibilité.
@export var family: String = "firearm"
## Catégorie (CAT_*) : pilote le sprite par défaut, les animations et le comportement.
@export var category: StringName = CAT_PISTOL
@export_range(0, 4) var rarity: int = Rarity.COMMUN

## SLOT_WEAPON ou SLOT_GADGET.
@export var slot: StringName = SLOT_WEAPON

@export_group("Équipement")
## Type d'équipement (GADGET_*) si slot = gadget.
@export var gadget_kind: StringName = &""
## Utilisations par raid.
@export var charges: int = 0
## Distance de lancer / de pose (px).
@export var throw_range: float = 0.0
## Délai avant effet (s) : mèche de grenade, armement de mine.
@export var fuse_time: float = 0.0
## Rayon d'effet (fumée, détection de mine, rayon d'action du drone) en px.
@export var effect_radius: float = 0.0
## Durée de l'effet (fumée, drone) en s.
@export var effect_duration: float = 0.0

@export_group("Tir")
@export var damage: float = 10.0
## Tirs par seconde.
@export var fire_rate: float = 2.0
@export var projectile_speed: float = 700.0
## Portée (pixels) : aide à la visée et durée de vie implicite.
@export var range: float = 500.0
@export var projectile_lifetime: float = 1.2
@export var projectile_count: int = 1
## Écart angulaire total entre le premier et le dernier projectile d'une salve.
@export var spread_degrees: float = 0.0
## Imprécision aléatoire (±°) appliquée à chaque tir.
@export var inaccuracy_deg: float = 0.0
## Nombre de cibles supplémentaires traversées.
@export var pierce: int = 0
@export var projectile_color: Color = Color(1.0, 0.22, 0.15)
## Style visuel du projectile : bullet, pellet, tracer (sniper), rocket, grenade.
@export var projectile_style: StringName = &"bullet"
## Affixes (brûlure, gel, ricochet...).
@export var affixes: Array[StringName] = []

@export_group("Chargeur")
## Balles par chargeur (0 = illimité, pas de rechargement).
@export var magazine_size: int = 12
## Durée du rechargement (s).
@export var reload_time: float = 1.2
## Tir automatique quand on maintient (sinon une pression = un tir… au stick : cadence).
@export var automatic: bool = false

@export_group("Explosion")
## Rayon d'explosion (px) à l'impact ou en fin de course (0 = pas d'explosion).
@export var explosion_radius: float = 0.0
## Dégâts d'explosion (au centre, décroissants jusqu'au bord).
@export var explosion_damage: float = 0.0

@export_group("Ressenti")
## Recul visuel de l'arme (px) et force de secousse caméra (px).
@export var recoil_px: float = 5.0
@export var shake_px: float = 2.5
## Multiplicateur de vitesse de déplacement quand l'arme est tenue (armes lourdes < 1).
@export var move_speed_mult: float = 1.0
## Taille de l'éclair de bouche (1 = normal).
@export var muzzle_flash_scale: float = 1.0
## Éjection de douilles visibles.
@export var eject_shells: bool = true

@export_group("Visuel")
## Sprite tenu : res://assets/sprites/weapons/<sprite_id>.png + .json (grip, muzzle, scale).
## Vide = sprite de la catégorie (`category`).
@export var sprite_id: StringName = &""
## Icône d'inventaire (vide = icône de la catégorie, voir WeaponCatalog.icon_for).
@export var icon: Texture2D = null

@export_group("Arsenal")
## Arme de base : toujours disponible, jamais perdue à la mort, invendable.
@export var permanent: bool = false
## Valeur marchande indicative (dollars).
@export var value: int = 50


func get_rarity_color() -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


func get_rarity_name() -> String:
	return RARITY_NAMES[clampi(rarity, 0, RARITY_NAMES.size() - 1)]


func get_category_name() -> String:
	return String(CATEGORY_NAMES.get(category, "Arme"))


## Délai entre deux tirs, en secondes.
func get_fire_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.01)


func is_gadget() -> bool:
	return slot == SLOT_GADGET


func is_explosive() -> bool:
	return explosion_radius > 0.0


## Identifiant du sprite tenu (sprite_id, sinon la catégorie).
func get_sprite_id() -> StringName:
	return sprite_id if not String(sprite_id).is_empty() else category


## Dégâts par seconde théoriques (affichage).
func get_dps() -> float:
	return (damage * maxi(projectile_count, 1) + explosion_damage) * fire_rate
