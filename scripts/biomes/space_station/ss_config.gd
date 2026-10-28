extends RefCounted
## Réglages de la Station Orbitale : section [space_station] de data/balance.cfg,
## avec repli sur [generator] (densités d'ennemis/conteneurs communes à tous les biomes).
## Lit le fichier directement (ConfigFile en cache) : fonctionne en --script et dans GUT.

const PATH := "res://data/balance.cfg"
const SECTION := "space_station"
const SHARED := "generator"

static var _cfg: ConfigFile = null


static func cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if _cfg.load(PATH) != OK:
			push_warning("SpaceStation: impossible de charger %s" % PATH)
	return _cfg


static func reload() -> void:
	_cfg = null


static func getv(key: String, def: Variant) -> Variant:
	var c := cfg()
	if c.has_section_key(SECTION, key):
		return c.get_value(SECTION, key)
	return c.get_value(SHARED, key, def)


static func geti(key: String, def: int) -> int:
	return int(getv(key, def))


static func getf(key: String, def: float) -> float:
	return float(getv(key, def))


static func get_arr(key: String, def: Array) -> Array:
	var v: Variant = getv(key, def)
	return v if v is Array else def


static func get_dict(key: String, def: Dictionary) -> Dictionary:
	var v: Variant = getv(key, def)
	return v if v is Dictionary else def


static func range_i(rng: RandomNumberGenerator, key: String, dmin: int, dmax: int) -> int:
	var a := get_arr(key, [dmin, dmax])
	if a.size() < 2:
		return rng.randi_range(dmin, dmax)
	return rng.randi_range(mini(int(a[0]), int(a[1])), maxi(int(a[0]), int(a[1])))


## Élément d'un tableau indexé (difficulté), borné.
static func by_index(key: String, idx: int, def: Array) -> float:
	var a := get_arr(key, def)
	if a.is_empty():
		return 0.0
	return float(a[clampi(idx, 0, a.size() - 1)])
