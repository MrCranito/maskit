class_name EnemyData
extends Resource
## Données d'un type d'ennemi (une ressource .tres par archétype, dans data/enemies/).
## Toutes les valeurs d'équilibrage propres à un ennemi vivent ici.

enum AttackType { MELEE, RANGED }

## Identifiant du sprite : res://assets/sprites/enemies/<kind>.svg
@export var kind: StringName = &"masked_grunt"
@export var display_name: String = ""
@export var max_hp: float = 40.0
## Vitesse de poursuite (px/s). La patrouille utilise une fraction (balance.cfg [enemy_ai]).
@export var move_speed: float = 140.0
## Rayon du corps physique (px).
@export var body_radius: float = 20.0

@export_group("Détection")
@export var detection_radius: float = 320.0
## Ouverture du cône de vision en degrés (360 = cercle complet).
@export_range(10.0, 360.0) var detection_angle_deg: float = 360.0
## Temps (s) sans voir le joueur avant d'abandonner la poursuite directe.
@export var lose_sight_time: float = 2.5
## Pause (s) de l'état Alerte (« ! ») avant la poursuite.
@export var alert_duration: float = 0.5
## Rayon (px) dans lequel un ennemi alerté prévient ses voisins.
@export var alert_neighbors_radius: float = 260.0
## Rayon (px) d'errance autour du point d'apparition.
@export var patrol_radius: float = 120.0

@export_group("Attaque")
@export var attack_type: AttackType = AttackType.MELEE
## Distance (px, centre à centre) à partir de laquelle l'ennemi attaque.
@export var attack_range: float = 60.0
@export var attack_damage: float = 8.0
## Délai (s) entre deux attaques.
@export var attack_cooldown: float = 1.2
## Télégraphe (s) avant que le coup ne parte : fenêtre d'esquive du joueur.
@export var attack_windup: float = 0.45
## Vitesse du projectile (px/s), attaques à distance uniquement.
@export var projectile_speed: float = 380.0
## Distance (px) sous laquelle l'ennemi recule pour garder ses distances (0 = jamais).
@export var retreat_distance: float = 0.0

@export_group("Visuel")
## Teinte d'aura de masque (alpha 0 = aucune).
@export var aura_color: Color = Color(1, 1, 1, 0)


func is_ranged() -> bool:
	return attack_type == AttackType.RANGED
