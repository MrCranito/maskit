extends RefCounted
## Réglages du biome « centre commercial » : section [mall] de data/balance.cfg,
## avec repli sur la section [generator] (réglages communs des générateurs) puis
## sur la valeur par défaut. Lit le fichier directement (ConfigFile en cache) pour
## fonctionner aussi en --script et dans GUT (sans l'autoload Balance).

const PATH := "res://data/balance.cfg"
const SECTION := "mall"
const FALLBACK := "generator"

static var _cfg: ConfigFile = null


static func cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if _cfg.load(PATH) != OK:
			push_warning("Mall: impossible de charger %s" % PATH)
	return _cfg


static func reload() -> void:
	_cfg = null


static func value(key: String, def: Variant) -> Variant:
	var c := cfg()
	if c.has_section_key(SECTION, key):
		return c.get_value(SECTION, key)
	return c.get_value(FALLBACK, key, def)


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


static func range_i(rng: RandomNumberGenerator, key: String, dmin: int, dmax: int) -> int:
	var a := get_arr(key, [dmin, dmax])
	var lo := int(a[0]) if a.size() > 0 else dmin
	var hi := int(a[1]) if a.size() > 1 else dmax
	return rng.randi_range(mini(lo, hi), maxi(lo, hi))


static func by_index(key: String, idx: int, def: Array) -> float:
	var a := get_arr(key, def)
	if a.is_empty():
		return 0.0
	return float(a[clampi(idx, 0, a.size() - 1)])
