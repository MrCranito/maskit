extends RefCounted
## Valeurs par défaut des compétences du Carnaval hanté : balance.cfg [bestiary_carnival], clés
## « <préfixe>_<paramètre> ». La valeur passée ici n'est qu'un repli si la clé manque ; chaque
## data/enemies/cv_*.tres peut encore remplacer un paramètre (champ skills).

const SECTION := "bestiary_carnival"


static func read(prefix: String, keys: Dictionary) -> Dictionary:
	var out := {}
	for k: Variant in keys:
		out[k] = Balance.get_value(SECTION, "%s_%s" % [prefix, k], keys[k])
	return out


static func num(key: String, def: float) -> float:
	return Balance.get_float(SECTION, key, def)
