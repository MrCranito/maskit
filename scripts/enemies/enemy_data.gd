class_name EnemyData
extends Resource
## Données d'un type d'ennemi (une ressource .tres par archétype, dans data/enemies/).
## Toutes les valeurs d'équilibrage propres à un ennemi vivent ici.

enum AttackType { MELEE, RANGED }

## Identifiant du visuel : planches assets/sprites/enemies/<kind>/ (EnemyArt) ou visuel « sprite »
## déclaré par le biome (scripts/biomes/<biome>/enemy_kinds.gd).
@export var kind: StringName = &"fw_bandit"
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

@export_group("Discrétion")
## Vitesse de remplissage de la jauge de reconnaissance par la VUE (jauge/s) :
## joueur en mouvement, tout près. Modulée par la distance et l'immobilité (balance.cfg).
@export var sight_gain: float = 1.5
## Rayon (px) dans lequel l'ennemi entend le bruit du joueur (atténuation linéaire).
@export var hearing_radius: float = 380.0
## Remplissage de la jauge (jauge/s) pour un bruit perçu de 1 (tir à bout portant).
@export var hearing_gain: float = 2.2
## Décroissance de la jauge (jauge/s) quand rien n'est perçu.
@export var awareness_decay: float = 0.15
## Niveau de jauge à partir duquel l'ennemi a « repéré » le joueur (Alert puis Chase).
@export_range(0.1, 1.0) var awareness_alert_threshold: float = 1.0

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

@export_group("Tir multiple et zone")
## Nombre de projectiles par tir (distance). 1 = tir simple (comportement historique).
@export_range(1, 16) var projectile_count: int = 1
## Ouverture totale (degrés) de l'éventail quand projectile_count > 1.
@export_range(0.0, 180.0) var projectile_spread_deg: float = 0.0
## Durée de vie (s) des projectiles de cet ennemi (≤ 0 = valeur de balance.cfg).
## Courte durée = courte portée (fusil à canon scié).
@export var projectile_lifetime: float = 0.0
## Apparence des projectiles : &"" = orbe orange (défaut), &"bullet" = balle jaune-orangé.
@export var projectile_style: StringName = &""
## Rayon (px) du coup de zone au sol autour de l'ennemi (mêlée). 0 = coup simple à portée.
@export var aoe_radius: float = 0.0

@export_group("Visuel")
## Teinte d'aura de masque (alpha 0 = aucune).
@export var aura_color: Color = Color(1, 1, 1, 0)

@export_group("Tactique")
## Comportement de combat : &"rusher" (fonce, mêlée), &"gunner" (tireur, garde ses distances),
## &"sniper" (longue portée, très à couvert), &"grenadier" (lance des explosifs), &"heavy"
## (avance droit, encaisse), &"elite" (chef à 2 phases). &"" = déduit du type d'attaque.
@export var tactic: StringName = &""
## Distance (px) de combat souhaitée [min, max]. 0 = déduite de attack_range / retreat_distance.
@export var preferred_range_min: float = 0.0
@export var preferred_range_max: float = 0.0
## Cherche un couvert (case libre voisine d'un obstacle : rocher, chariot, caisse, mur).
@export var use_cover: bool = false
## Peut contourner le joueur quand plusieurs alliés l'engagent.
@export var can_flank: bool = true
## Course en zigzag (px d'écart latéral, 0 = ligne droite) et période (s) d'un aller-retour.
@export var zigzag_amplitude: float = 0.0
@export var zigzag_period: float = 0.6
## Sous cette fraction de PV, bat en retraite une fois (0 = jamais).
@export_range(0.0, 1.0) var retreat_hp_ratio: float = 0.0
## Vitesse de déplacement latéral pendant l'échange de tirs (fraction de move_speed).
@export_range(0.0, 1.5) var strafe_ratio: float = 0.55

@export_group("Schéma d'attaque")
## &"single", &"burst" (rafale), &"fan" (éventail), &"aimed" (tir précis avec ligne de visée),
## &"lob" (explosif en cloche), &"lunge" (ruée + combo), &"slam" (zone au sol), &"melee".
## &"" = déduit (projectile_count > 1 → fan, aoe → slam, distance → single, sinon melee).
@export var attack_pattern: StringName = &""
## Rafale : nombre de tirs et intervalle (s).
@export_range(1, 12) var burst_count: int = 1
@export var burst_interval: float = 0.14
## Imprécision (degrés, ± aléatoire) de chaque tir.
@export var aim_spread_deg: float = 0.0
## Ligne de visée rouge pendant le télégraphe (tireur embusqué).
@export var telegraph_line: bool = false
## Ruée (mêlée) : distance (px) et vitesse (px/s) ; combo : nombre de coups et intervalle (s).
@export var lunge_distance: float = 0.0
@export var lunge_speed: float = 0.0
@export_range(1, 5) var combo_hits: int = 1
@export var combo_interval: float = 0.28
## Explosif lancé : rayon (px), dégâts (0 = attack_damage), temps de vol (s), mèche au sol (s).
@export var throw_radius: float = 0.0
@export var throw_damage: float = 0.0
@export var throw_flight_time: float = 0.7
@export var throw_fuse: float = 0.9

@export_group("Élite")
## Élite (chef de bande) : barre de vie dorée, meilleur butin, phase 2 sous phase2_hp_ratio.
@export var elite: bool = false
@export_range(0.0, 1.0) var phase2_hp_ratio: float = 0.0
@export var phase2_speed_mult: float = 1.25
@export var phase2_cooldown_mult: float = 0.7
## Phase 2 : alterne avec ce schéma (ex. &"lob") une attaque sur deux.
@export var phase2_alt_pattern: StringName = &""

@export_group("Boss")
## Boss du monde : barre de vie en haut de l'écran, phases successives, arène scellée.
@export var boss: bool = false
## Titre affiché sous le nom sur la barre de boss (« Maître des terres arides »).
@export var boss_title: String = ""
## Phases du boss, dans l'ordre. Chaque phase est un dictionnaire :
##   "from": 1.0 / 0.7 / 0.3   fraction de PV à laquelle la phase COMMENCE (1.0 pour la première)
##   "name": "Phase 2"          libellé (bandeau à l'écran)
##   "skills": [...]            compétences actives pendant la phase (même format que `skills`) ;
##                              absent = garde les compétences de la phase précédente
##   "speed_mult", "cooldown_mult", "damage_mult" : multiplicateurs (1.0 par défaut)
##   "attack_pattern": &"burst" schéma d'attaque de base pendant la phase (absent = inchangé)
##   "on_enter": [ids]          compétences lancées immédiatement en entrant dans la phase
##   "invuln": 1.2              invulnérabilité (s) pendant la transition (rugissement)
## Vide = pas de phases (ennemi normal).
@export var phases: Array = []

@export_group("Réactions")
## Un coup ≥ stagger_ratio × max_hp étourdit brièvement (stagger_time s). 0 = jamais.
@export_range(0.0, 1.0) var stagger_ratio: float = 0.25
@export var stagger_time: float = 0.45
## Recul (px/s) imprimé par un coup reçu.
@export var knockback: float = 90.0

@export_group("Compétences")
## Compétences actives / passives (scripts/enemies/skills, registre EnemySkills) :
## [{"id": &"knife_throw", "cooldown": 5.0, ...}] — les clés remplacent les valeurs par défaut.
@export var skills: Array = []

@export_group("Butin")
## Table du cadavre (data/loot_tables). &"" = enemy_<kind> si elle existe, sinon celle du biome.
@export var loot_table: StringName = &""
## Chance de faire tomber du butin au sol à la mort (-1 = [enemy_loot] ground_drop_chance).
@export_range(-1.0, 1.0) var ground_drop_chance: float = -1.0
## Sons (AudioManager) : tir / coup, blessure, mort. &"" = déduit du schéma et du kind.
@export var sfx_attack: StringName = &""
@export var sfx_hurt: StringName = &""
@export var sfx_death: StringName = &""
## Nom du cadavre dans l'interface (« Pistolero abattu »). Vide = « <nom> abattu ».
@export var corpse_name: String = ""


func is_ranged() -> bool:
	return attack_type == AttackType.RANGED


## Tactique effective (déduite si vide).
func get_tactic() -> StringName:
	if tactic != &"":
		return tactic
	if is_area_attack():
		return &"heavy"
	return &"gunner" if is_ranged() else &"rusher"


## Schéma d'attaque effectif (déduit si vide).
func get_pattern() -> StringName:
	if attack_pattern != &"":
		return attack_pattern
	if is_area_attack():
		return &"slam"
	if is_ranged():
		return &"fan" if projectile_count > 1 else &"single"
	return &"melee"


## Son d'attaque effectif.
func get_sfx_attack() -> StringName:
	if sfx_attack != &"":
		return sfx_attack
	match get_pattern():
		&"fan":
			return &"shotgun_blast"
		&"aimed":
			return &"rifle_shot"
		&"burst", &"single":
			return &"revolver_shot" if projectile_style == &"bullet" else &"enemy_attack"
		&"lob":
			return &"blade_swing_heavy"
		&"slam":
			return &"golem_stomp"
	return &"blade_swing"


func get_sfx_hurt() -> StringName:
	return sfx_hurt if sfx_hurt != &"" else (&"outlaw_hurt" if projectile_style == &"bullet" else &"hit_flesh")


func get_sfx_death() -> StringName:
	if sfx_death != &"":
		return sfx_death
	return &"outlaw_death" if get_sfx_hurt() == &"outlaw_hurt" else &"enemy_death_generic"


## Distance de combat minimale souhaitée (px).
func range_min() -> float:
	if preferred_range_min > 0.0:
		return preferred_range_min
	if is_ranged():
		return maxf(retreat_distance, attack_range * 0.4)
	return 0.0


## Distance de combat maximale souhaitée (px).
func range_max() -> float:
	if preferred_range_max > 0.0:
		return preferred_range_max
	return attack_range * 0.9 if is_ranged() else attack_range


## Coup de zone au sol (mêlée avec aoe_radius > 0).
func is_area_attack() -> bool:
	return attack_type == AttackType.MELEE and aoe_radius > 0.0
