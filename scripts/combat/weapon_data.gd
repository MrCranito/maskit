class_name WeaponData
extends Resource
## Données d'une arme. Chaque arme du jeu est une ressource .tres de ce type,
## pour pouvoir ajouter des armes sans toucher au code.

enum Rarity { COMMUN, PEU_COMMUN, RARE, EPIQUE, LEGENDAIRE }

## Couleurs de rareté (charte du projet).
const RARITY_COLORS: Array[Color] = [
	Color(0.62, 0.62, 0.62),  # Commun : gris
	Color(0.30, 0.80, 0.30),  # Peu commun : vert
	Color(0.25, 0.55, 1.00),  # Rare : bleu
	Color(0.65, 0.30, 0.95),  # Épique : violet
	Color(1.00, 0.58, 0.10),  # Légendaire : orange
]

@export var id: StringName = &""
@export var display_name: String = ""
## Famille d'arme : "bow", "sword", "crossbow", ...
@export var family: String = "bow"
@export_range(0, 4) var rarity: int = Rarity.COMMUN
@export var damage: float = 10.0
## Tirs par seconde.
@export var fire_rate: float = 2.0
@export var projectile_speed: float = 700.0
## Portée de ciblage automatique (pixels).
@export var range: float = 500.0
@export var projectile_lifetime: float = 1.2
@export var projectile_count: int = 1
## Écart angulaire total entre le premier et le dernier projectile d'une salve.
@export var spread_degrees: float = 0.0
## Nombre de cibles supplémentaires traversées.
@export var pierce: int = 0
@export var projectile_color: Color = Color(1.0, 0.22, 0.15)
## Affixes (brûlure, gel, ricochet...) : implémentés en phase 8.
@export var affixes: Array[StringName] = []


func get_rarity_color() -> Color:
	return RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]


## Délai entre deux tirs, en secondes.
func get_fire_interval() -> float:
	return 1.0 / maxf(fire_rate, 0.01)
