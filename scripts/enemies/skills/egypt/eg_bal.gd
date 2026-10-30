extends RefCounted
## Valeurs par défaut des compétences du bestiaire d'Égypte : section [bestiary_egypt] de
## data/balance.cfg (clé « <préfixe>_<paramètre> »). Les paramètres d'un data/enemies/eg_*.tres
## (champ skills) remplacent ensuite ces valeurs. Seuls les nombres sont lus dans balance.cfg.

const SECTION := "bestiary_egypt"


static func defaults(prefix: String, base: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in base:
		var v: Variant = base[k]
		if (v is float or v is int) and not (v is bool):
			out[k] = Balance.get_float(SECTION, "%s_%s" % [prefix, k], float(v))
		else:
			out[k] = v
	return out


static func get_f(key: String, def: float) -> float:
	return Balance.get_float(SECTION, key, def)
