extends RefCounted
## Lecture de la section [generator] de data/balance.cfg.
## Lit le fichier directement (ConfigFile mis en cache) au lieu de l'autoload
## Balance, pour que le générateur fonctionne aussi en --script et dans GUT.
## Les valeurs par défaut ne servent que de filet si la clé manque.

const PATH := "res://data/balance.cfg"
const SECTION := "generator"

static var _cfg: ConfigFile = null


static func cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		var err := _cfg.load(PATH)
		if err != OK:
			push_warning("DungeonGenerator: impossible de charger %s (erreur %d)" % [PATH, err])
	return _cfg


static func reload() -> void:
	_cfg = null


static func geti(key: String, def: int) -> int:
	return int(cfg().get_value(SECTION, key, def))


static func getf(key: String, def: float) -> float:
	return float(cfg().get_value(SECTION, key, def))


static func get_arr(key: String, def: Array) -> Array:
	var v: Variant = cfg().get_value(SECTION, key, def)
	return v if v is Array else def


static func get_dict(key: String, def: Dictionary) -> Dictionary:
	var v: Variant = cfg().get_value(SECTION, key, def)
	return v if v is Dictionary else def


## Tirage entier dans [min, max] lus depuis deux clés.
static func range_i(rng: RandomNumberGenerator, key_min: String, key_max: String, dmin: int, dmax: int) -> int:
	var a := geti(key_min, dmin)
	var b := geti(key_max, dmax)
	return rng.randi_range(mini(a, b), maxi(a, b))


## Élément d'un tableau indexé par la difficulté (bornée), ou défaut.
static func by_index(key: String, idx: int, def: Array) -> float:
	var a := get_arr(key, def)
	if a.is_empty():
		return 0.0
	return float(a[clampi(idx, 0, a.size() - 1)])


## Gabarit de taille [w_min, w_max, h_min, h_max] d'un archétype (murs compris).
static func size_range(archetype: StringName) -> Array:
	var defaults := {
		&"saloon": [12, 16, 11, 14], &"bank": [11, 15, 10, 13], &"sheriff": [11, 14, 9, 12],
		&"store": [9, 13, 9, 11], &"hotel": [13, 17, 13, 15], &"stable": [12, 16, 10, 13],
		&"church": [9, 12, 12, 15], &"mine": [8, 11, 7, 9],
	}
	var def: Array = defaults.get(archetype, [10, 12, 9, 11])
	var a := get_arr("size_" + String(archetype), def)
	return a if a.size() == 4 else def
