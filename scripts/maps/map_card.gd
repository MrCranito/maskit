class_name MapCard
extends Resource
## Carte jouable = un monde (biome) + une difficulté propre + des propriétés (modificateurs).
## Une ressource par carte dans data/maps/<id>.tres. Choisie à l'écran « Jouer »
## (scenes/ui/menus/map_select.tscn) ; la rotation (MapRotation) décide lesquelles sont
## disponibles à un instant donné selon la catégorie.
##
## Modificateurs (clé → valeur ; clé absente = valeur neutre, cf. DEFAULT_MODIFIERS) :
##   enemy_hp_mult       PV des ennemis (×)
##   enemy_damage_mult   dégâts des ennemis (×)
##   enemy_speed_mult    vitesse de déplacement des ennemis (×)
##   enemy_density_mult  nombre d'ennemis (×) : points d'apparition retirés (< 1) ou
##                       dupliqués sur une case voisine de la même salle (> 1), seedé
##   awareness_mult      vitesse de remplissage de la jauge de reconnaissance (vue + ouïe)
##   loot_rarity_bonus   bonus global de rareté du butin (0 = aucun ; 1 ≈ un cran de difficulté
##                       sur les objets rares, cf. [maps] loot_rarity_bonus_weights)
##   loot_quantity_mult  nombre d'objets par conteneur / sacoche (×)
##   view_radius_mult    rayon de vue du brouillard (×, [fog] view_radius)
##   player_damage_mult  dégâts de l'arme du joueur (×)
##   player_hp_mult      PV max du joueur (×)
##   night               true : teinte nuit sur le monde ([maps] night_tint)
##   night_tint          (Color, facultatif) teinte nuit propre à la carte (remplace [maps] night_tint)
##   fixed_seed          ≠ 0 : même carte générée pour tous les joueurs

const CATEGORY_PERMANENT := &"permanent"
const CATEGORY_WEEKLY := &"weekly"
const CATEGORY_MONTHLY := &"monthly"
const CATEGORY_EVENT := &"event"
const CATEGORIES: Array[StringName] = [CATEGORY_EVENT, CATEGORY_WEEKLY, CATEGORY_MONTHLY, CATEGORY_PERMANENT]
const CATEGORY_NAMES := {
	&"event": "Événement",
	&"weekly": "Hebdomadaire",
	&"monthly": "Mensuelle",
	&"permanent": "Toujours disponible",
}

const DIFFICULTY_NAMES: Array[String] = ["Facile", "Normal", "Difficile", "Infernal", "Cauchemar"]
const DIFFICULTY_COLORS: Array[Color] = [
	Color(0.36, 0.78, 0.42),
	Color(0.36, 0.62, 0.95),
	Color(0.96, 0.66, 0.22),
	Color(0.92, 0.3, 0.2),
	Color(0.62, 0.22, 0.85),
]

const BIOME_NAMES := {
	&"far_west": "Far West",
	&"space_station": "Station spatiale",
	&"mall": "Centre commercial",
}
## Vignettes par défaut (remplaçables par les agents biomes) : assets/ui/maps/<biome>.png
const THUMB_DIR := "res://assets/ui/maps/"
const DATA_DIR := "res://data/maps/"

const DEFAULT_MODIFIERS := {
	"enemy_hp_mult": 1.0,
	"enemy_damage_mult": 1.0,
	"enemy_speed_mult": 1.0,
	"enemy_density_mult": 1.0,
	"awareness_mult": 1.0,
	"loot_rarity_bonus": 0.0,
	"loot_quantity_mult": 1.0,
	"view_radius_mult": 1.0,
	"player_damage_mult": 1.0,
	"player_hp_mult": 1.0,
	"night": false,
	"fixed_seed": 0,
}

@export var id: StringName = &""
@export var display_name: String = ""
## Description courte (1-2 phrases), affichée dans le panneau de détail.
@export_multiline var description: String = ""
## Monde chargé par le raid (WorldData). Absent → carte grisée « Bientôt ».
@export_file("*.tres") var world_path: String = ""
## &"permanent", &"weekly", &"monthly" ou &"event".
@export var category: StringName = &"permanent"
## 0 Facile … 4 Cauchemar (passé au générateur et aux tables de butin).
@export_range(0, 4) var difficulty: int = 1
## Vignette propre (optionnelle) ; sinon assets/ui/maps/<biome>.png.
@export var thumbnail: Texture2D = null
@export var accent_color: Color = Color(0.98, 0.78, 0.45)
## Voir l'en-tête du script.
@export var modifiers: Dictionary = {}
## Étiquettes affichées (« Butin ×2 », « Nuit noire »…). Vide = générées depuis les modificateurs.
@export var tags: PackedStringArray = PackedStringArray()
## Récompense indicative (« Butin rare fréquent »).
@export var reward_text: String = ""
## Poids de tirage dans le pool de sa catégorie (rotation).
@export_range(0.0, 100.0) var weight: float = 1.0


# --- Lecture -----------------------------------------------------------------------

## Valeur d'un modificateur (valeur neutre si absent).
func get_mod(key: String) -> Variant:
	return modifiers.get(key, DEFAULT_MODIFIERS.get(key, null))


func get_mod_f(key: String) -> float:
	var v: Variant = get_mod(key)
	return float(v) if v != null else 1.0


func is_night() -> bool:
	return bool(get_mod("night"))


func get_fixed_seed() -> int:
	return int(get_mod("fixed_seed"))


## Le monde de la carte est-il présent dans le projet ?
func is_available() -> bool:
	return world_path != "" and ResourceLoader.exists(world_path)


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[clampi(difficulty, 0, DIFFICULTY_NAMES.size() - 1)]


func difficulty_color() -> Color:
	return DIFFICULTY_COLORS[clampi(difficulty, 0, DIFFICULTY_COLORS.size() - 1)]


func category_name() -> String:
	return String(CATEGORY_NAMES.get(category, String(category)))


## Biome du monde (d'après BiomeRegistry), &"" si inconnu.
func get_biome() -> StringName:
	for b: Dictionary in BiomeRegistry.BIOMES:
		if String(b["world"]) == world_path:
			return b["biome"]
	return &""


func biome_name() -> String:
	if BIOME_NAMES.has(get_biome()):
		return String(BIOME_NAMES[get_biome()])
	# Monde hors registre des biomes (arène de test du mode dev) : son nom affiché.
	var w: Resource = load(world_path) if is_available() else null
	var n: String = String(w.get("display_name")) if w != null and w.get("display_name") != null else ""
	return n if not n.is_empty() else "Monde inconnu"


## Vignette : propre à la carte, sinon celle du biome, sinon null.
func get_thumbnail() -> Texture2D:
	if thumbnail != null:
		return thumbnail
	var p := THUMB_DIR + String(get_biome()) + ".png"
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## Étiquettes : celles de la ressource, sinon déduites des modificateurs.
func get_tags() -> PackedStringArray:
	if not tags.is_empty():
		return tags
	var out := PackedStringArray()
	for e: Dictionary in describe_modifiers():
		out.append(String(e["short"]))
	return out


## Lignes détaillées des modificateurs non neutres :
## [{short, text, good: bool}] (good = favorable au joueur).
func describe_modifiers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_mult_line(out, "loot_quantity_mult", "Butin", "Quantité de butin", true)
	var rb: float = get_mod_f("loot_rarity_bonus")
	if not is_zero_approx(rb):
		out.append({"short": "Rareté +%d" % roundi(rb * 100.0) if rb > 0.0 else "Rareté %d" % roundi(rb * 100.0),
			"text": "Objets rares plus fréquents (+%d %%)" % roundi(rb * 100.0) if rb > 0.0
				else "Objets rares moins fréquents (%d %%)" % roundi(rb * 100.0),
			"good": rb > 0.0})
	_mult_line(out, "enemy_hp_mult", "PV ennemis", "Points de vie des ennemis", false)
	_mult_line(out, "enemy_damage_mult", "Dégâts ennemis", "Dégâts des ennemis", false)
	_mult_line(out, "enemy_speed_mult", "Ennemis rapides", "Vitesse des ennemis", false)
	_mult_line(out, "enemy_density_mult", "Ennemis", "Nombre d'ennemis", false)
	_mult_line(out, "awareness_mult", "Vigilance", "Vitesse de repérage des ennemis", false)
	_mult_line(out, "view_radius_mult", "Vue", "Rayon de vue", true)
	_mult_line(out, "player_hp_mult", "Tes PV", "Tes points de vie", true)
	_mult_line(out, "player_damage_mult", "Tes dégâts", "Tes dégâts", true)
	if is_night():
		out.append({"short": "Nuit", "text": "Nuit noire : tout est plongé dans l'ombre", "good": false})
	if get_fixed_seed() != 0:
		out.append({"short": "Carte fixe", "text": "Même carte pour tous les joueurs", "good": true})
	return out


## Ajoute « Libellé ×1,5 » / « Libellé +50 % » si le multiplicateur n'est pas neutre.
## `higher_is_good` : un multiplicateur > 1 aide le joueur.
func _mult_line(out: Array[Dictionary], key: String, short: String, text: String, higher_is_good: bool) -> void:
	var m: float = get_mod_f(key)
	if is_equal_approx(m, 1.0):
		return
	var pct: int = roundi((m - 1.0) * 100.0)
	var mult_txt: String = ("×%s" % _fmt_mult(m)) if m >= 2.0 else ("%+d %%" % pct)
	out.append({"short": "%s %s" % [short, mult_txt], "text": "%s %s" % [text, mult_txt],
		"good": (m > 1.0) == higher_is_good})


static func _fmt_mult(m: float) -> String:
	var s := "%.1f" % m
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s.replace(".", ",")


# --- Catalogue ---------------------------------------------------------------------

static var _cache: Array[MapCard] = []


## Toutes les cartes de data/maps/ (triées par id ; mises en cache).
static func load_all(force: bool = false) -> Array[MapCard]:
	if not _cache.is_empty() and not force:
		return _cache
	var out: Array[MapCard] = []
	var files: PackedStringArray = ResourceLoader.list_directory(DATA_DIR)
	var names: Array[String] = []
	for f: String in files:
		var base := f.trim_suffix(".remap")
		if base.ends_with(".tres") and not names.has(base):
			names.append(base)
	names.sort()
	for n: String in names:
		var c := load(DATA_DIR + n) as MapCard
		if c != null and c.id != &"":
			out.append(c)
	_cache = out
	return out


static func find(map_id: StringName) -> MapCard:
	for c: MapCard in load_all():
		if c.id == map_id:
			return c
	return null


static func by_category(cat: StringName) -> Array[MapCard]:
	var out: Array[MapCard] = []
	for c: MapCard in load_all():
		if c.category == cat:
			out.append(c)
	return out
