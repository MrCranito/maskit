extends Node
## Charge data/balance.cfg et expose les valeurs d'équilibrage.

const BALANCE_PATH := "res://data/balance.cfg"

var _config := ConfigFile.new()


func _ready() -> void:
	reload()


func reload() -> void:
	var err := _config.load(BALANCE_PATH)
	if err != OK:
		push_error("Balance: impossible de charger %s (erreur %d)" % [BALANCE_PATH, err])


func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return _config.get_value(section, key, default)


func get_float(section: String, key: String, default: float = 0.0) -> float:
	return float(_config.get_value(section, key, default))


## Clés d'une section (vide si la section n'existe pas).
func get_section_keys(section: String) -> PackedStringArray:
	if not _config.has_section(section):
		return PackedStringArray()
	return _config.get_section_keys(section)
