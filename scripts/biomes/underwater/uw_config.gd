extends RefCounted
## Réglages du biome « Station sous-marine » : section [underwater] de data/balance.cfg,
## avec repli sur la section [generator] (densités d'ennemis, gardes…) puis sur les
## valeurs par défaut. Lit le fichier directement (ConfigFile en cache) pour que le
## générateur fonctionne aussi en --script et dans GUT, sans l'autoload Balance.

const PATH := "res://data/balance.cfg"
const SECTION := "underwater"
const FALLBACK := "generator"

static var _cfg: ConfigFile = null


static func cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		var err := _cfg.load(PATH)
		if err != OK:
			push_warning("UnderwaterGenerator: impossible de charger %s (erreur %d)" % [PATH, err])
	return _cfg


static func reload() -> void:
	_cfg = null


static func value(key: String, def: Variant) -> Variant:
	var c := cfg()
	if c.has_section_key(SECTION, key):
		return c.get_value(SECTION, key)
	if c.has_section_key(FALLBACK, key):
		return c.get_value(FALLBACK, key)
	return def


static func geti(key: String, def: int) -> int:
	return int(value(key, def))


static func getf(key: String, def: float) -> float:
	return float(value(key, def))


static func get_arr(key: String, def: Array) -> Array:
	var v: Variant = value(key, def)
	return v if v is Array else def


static func get_dict(key: String, def: Dictionary) -> Dictionary:
	var v: Variant = value(key, def)
	return v if v is Dictionary else def


## Valeur d'une autre section (ex. [loot] hiding_spots_min).
static func section_value(section: String, key: String, def: Variant) -> Variant:
	return cfg().get_value(section, key, def)


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
