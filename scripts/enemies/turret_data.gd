class_name TurretData
extends Resource
## Données d'un type de tourelle murale (data/turrets/<id>.tres). Toutes les valeurs propres à
## la tourelle vivent ici ; l'échelle par difficulté et les réglages globaux sont dans
## balance.cfg [turrets]. Catalogue : TurretData.all(), for_biome(), get_by_id().
##
## Sprites (rendus Blender, assets/sprites/turrets/src/build_turrets.py) :
##   assets/sprites/turrets/<sprite_id>_{base,head,wreck}.png + <sprite_id>.json

const DIR := "res://data/turrets/"
const SPRITE_DIR := "res://assets/sprites/turrets/"

## Familles : rafales légères, canon lent à gros projectile, laser de précision (long télégraphe).
const KIND_BURST := &"burst"
const KIND_CANNON := &"cannon"
const KIND_LASER := &"laser"

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: StringName = KIND_BURST
## Biomes où la tourelle peut apparaître (WorldData.biome : far_west, space_station, mall).
@export var biomes: Array[StringName] = []
## Préfixe des sprites dans assets/sprites/turrets/ (ex. far_west_burst).
@export var sprite_id: String = ""

@export_group("Résistance")
@export var max_hp: float = 60.0
## Rayon du corps physique (px), centré devant le mur.
@export var body_radius: float = 18.0

@export_group("Détection")
## Portée de détection et de tir (px).
@export var range: float = 420.0
## Ouverture totale du cône (degrés), centré sur la normale du mur (vers la salle).
@export_range(20.0, 180.0) var cone_deg: float = 120.0
## Vitesse de rotation de la tête en poursuite (degrés/s).
@export var turn_speed_deg: float = 110.0
## Vitesse de balayage au repos (degrés/s).
@export var scan_speed_deg: float = 28.0
## Rayon (px) dans lequel la tourelle prévient les ennemis quand elle repère le joueur (0 = aucun).
@export var alert_neighbors_radius: float = 320.0

@export_group("Tir")
## Temps de verrouillage (télégraphe laser) avant chaque rafale (s).
@export var lock_time: float = 0.7
## Délai entre deux rafales (s).
@export var cooldown: float = 1.6
## Projectiles par rafale et intervalle entre eux (s).
@export var burst_count: int = 4
@export var burst_interval: float = 0.1
## Projectiles tirés à chaque coup (éventail) et ouverture de l'éventail (degrés).
@export var pellets: int = 1
@export var spread_deg: float = 4.0
@export var damage: float = 6.0
@export var projectile_speed: float = 520.0
## Style du projectile ennemi (EnemyProjectile : &"" orbe, bullet, laser, acid).
@export var projectile_style: StringName = &"bullet"
## La tête continue de suivre le joueur pendant la rafale (false : tir là où le laser visait).
@export var track_while_firing: bool = true
## Échelle du projectile (gros boulet du canon > 1 ; agrandit aussi sa zone de contact).
@export var projectile_scale: float = 1.0
## Sons (AudioManager.SFX) : tir et destruction.
@export var shot_sfx: StringName = &"gun_shot_alt"
@export var destroy_sfx: StringName = &"explosion"
## Couleur du laser de visée.
@export var laser_color: Color = Color(1.0, 0.18, 0.12)
## Échelle de l'éclair de bouche.
@export var muzzle_flash_scale: float = 1.0
## Couleur de l'éclair de bouche / de l'explosion.
@export var flash_color: Color = Color(1.0, 0.72, 0.3)

@export_group("Apparition")
## Difficulté minimale (0..4) pour que ce type apparaisse.
@export var min_difficulty: int = 0
## Poids relatif parmi les tourelles du biome.
@export var spawn_weight: float = 1.0
## Couleurs des débris à la destruction.
@export var debris_colors: Array[Color] = [Color(0.3, 0.3, 0.36), Color(0.6, 0.6, 0.66), Color(1.0, 0.55, 0.2)]


func base_path() -> String:
	return SPRITE_DIR + sprite_id + "_base.png"


func head_path() -> String:
	return SPRITE_DIR + sprite_id + "_head.png"


func wreck_path() -> String:
	return SPRITE_DIR + sprite_id + "_wreck.png"


func meta_path() -> String:
	return SPRITE_DIR + sprite_id + ".json"


func is_for_biome(biome: StringName) -> bool:
	return biomes.has(biome)


# --- Catalogue -------------------------------------------------------------------------

static var _cache: Array[TurretData] = []
static var _loaded: bool = false


static func all() -> Array[TurretData]:
	if not _loaded:
		_loaded = true
		_cache.clear()
		var files: PackedStringArray = DirAccess.get_files_at(DIR)
		var names: Array[String] = []
		for f: String in files:
			var file := f.trim_suffix(".remap")
			if file.ends_with(".tres") and not names.has(file):
				names.append(file)
		names.sort()
		for file: String in names:
			var d := load(DIR + file) as TurretData
			if d != null and not String(d.id).is_empty():
				_cache.append(d)
	return _cache


static func reload() -> void:
	_loaded = false
	all()


static func get_by_id(turret_id: StringName) -> TurretData:
	for d: TurretData in all():
		if d.id == turret_id:
			return d
	return null


## Types disponibles pour le biome à cette difficulté (triés par id : déterministe).
static func for_biome(biome: StringName, difficulty: int = 4) -> Array[TurretData]:
	var out: Array[TurretData] = []
	for d: TurretData in all():
		if d.is_for_biome(biome) and d.min_difficulty <= difficulty:
			out.append(d)
	return out


## Biomes connus (union des biomes des tourelles), triés.
static func known_biomes() -> Array[StringName]:
	var out: Array[StringName] = []
	for d: TurretData in all():
		for b: StringName in d.biomes:
			if not out.has(b):
				out.append(b)
	out.sort()
	return out


## Biome d'un identifiant de monde ou de biome (« world_02_space_station » → space_station).
## Chaîne inconnue → far_west.
static func biome_of(world_or_biome: String) -> StringName:
	var known := known_biomes()
	if known.has(StringName(world_or_biome)):
		return StringName(world_or_biome)
	var best: StringName = &""
	for b: StringName in known:
		if world_or_biome.contains(String(b)) and String(b).length() > String(best).length():
			best = b
	return best if best != &"" else &"far_west"
