class_name MaskData
extends Resource
## Données d'un masque (classe jouable). Une ressource par masque : data/masks/<id>.tres.
## Les multiplicateurs s'appliquent aux valeurs de base du joueur (balance.cfg [player])
## et à l'arme tenue (dégâts, cadence) via Player.apply_mask().
## Le pouvoir actif (power_id) est implémenté en phase 7.

const DIR := "res://data/masks/"
const DEFAULT_ID: StringName = &"kitsune"
## Ordre d'affichage dans les menus.
const IDS: Array[StringName] = [&"kitsune", &"colosse", &"spectre", &"alchimiste", &"marionnettiste"]

@export var id: StringName = &""
@export var display_name: String = ""
## Description courte (une ligne, sur la carte du menu).
@export var tagline: String = ""
## Description complète (panneau de détail).
@export_multiline var description: String = ""
## Couleur d'aura : teinte le héros et ses effets.
@export var aura_color: Color = Color(0.9, 0.2, 0.2)
## Force de la teinte d'aura sur le sprite du héros (0 = aucune, 1 = couleur pleine).
@export_range(0.0, 1.0) var aura_tint_strength: float = 0.2
## Opacité de la lueur au sol sous le héros.
@export_range(0.0, 1.0) var aura_glow_alpha: float = 0.35
@export var portrait: Texture2D = null

@export_group("Stats")
@export var max_hp_mult: float = 1.0
@export var speed_mult: float = 1.0
@export var damage_mult: float = 1.0
@export var fire_rate_mult: float = 1.0

@export_group("Pouvoir")
## Identifiant du pouvoir actif (phase 7).
@export var power_id: StringName = &""
@export var power_name: String = ""


static func path_for(mask_id: StringName) -> String:
	return DIR + String(mask_id) + ".tres"


static func exists(mask_id: StringName) -> bool:
	return not String(mask_id).is_empty() and ResourceLoader.exists(path_for(mask_id))


## Charge un masque ; repli sur le masque par défaut si l'id est inconnu.
static func load_mask(mask_id: StringName) -> MaskData:
	var target: StringName = mask_id if exists(mask_id) else DEFAULT_ID
	if not exists(target):
		return null
	return load(path_for(target)) as MaskData


## Tous les masques, dans l'ordre d'affichage (les fichiers absents sont ignorés).
static func load_all() -> Array[MaskData]:
	var out: Array[MaskData] = []
	for mask_id: StringName in IDS:
		if exists(mask_id):
			var m := load(path_for(mask_id)) as MaskData
			if m != null:
				out.append(m)
	return out


## Statistiques affichées dans les menus : [{label, value}] (value = multiplicateur).
func get_stat_entries() -> Array[Dictionary]:
	return [
		{"label": "Vie", "value": max_hp_mult},
		{"label": "Vitesse", "value": speed_mult},
		{"label": "Dégâts", "value": damage_mult},
		{"label": "Cadence", "value": fire_rate_mult},
	]
