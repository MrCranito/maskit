class_name LootDB
extends RefCounted
## Accès statique (sans autoload, utilisable en tests et en --script) aux objets
## (data/items/*.tres), aux tables (data/loot_tables/*.tres) et à la section
## [loot] de data/balance.cfg. Tout est mis en cache au premier accès.

const ITEMS_DIR := "res://data/items/"
const TABLES_DIR := "res://data/loot_tables/"
const BALANCE_PATH := "res://data/balance.cfg"
const SECTION := "loot"

const RARITY_NAMES: Array[String] = ["Commun", "Peu commun", "Rare", "Épique", "Légendaire"]
## Codes couleur de rareté (CLAUDE.md) : gris, vert, bleu, violet, orange.
const RARITY_COLORS: Array[Color] = [
	Color(0.72, 0.74, 0.78),
	Color(0.38, 0.85, 0.42),
	Color(0.33, 0.62, 1.0),
	Color(0.74, 0.42, 1.0),
	Color(1.0, 0.6, 0.18),
]
const TYPE_NAMES := {
	&"weapon": "Arme", &"ammo": "Munitions", &"consumable": "Consommable",
	&"valuable": "Objet de valeur", &"key": "Clef", &"material": "Matériau",
}

static var _items: Dictionary = {}
static var _tables: Dictionary = {}
static var _items_loaded: bool = false
static var _cfg: ConfigFile = null


static func rarity_color(r: int) -> Color:
	return RARITY_COLORS[clampi(r, 0, RARITY_COLORS.size() - 1)]


static func rarity_name(r: int) -> String:
	return RARITY_NAMES[clampi(r, 0, RARITY_NAMES.size() - 1)]


static func type_name(t: StringName) -> String:
	return String(TYPE_NAMES.get(t, String(t)))


# --- Objets ----------------------------------------------------------------------

static func _load_items() -> void:
	if _items_loaded:
		return
	_items_loaded = true
	for f: String in _list_resources(ITEMS_DIR):
		var it := load(ITEMS_DIR + f) as ItemData
		if it == null:
			push_warning("LootDB: objet illisible %s" % f)
			continue
		if it.id == &"":
			it.id = StringName(f.get_basename())
		_items[it.id] = it


## Fichiers .tres d'un dossier (gère les .remap des exports).
static func _list_resources(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f: String in DirAccess.get_files_at(dir):
		var name := f.trim_suffix(".remap")
		if name.ends_with(".tres") and not out.has(name):
			out.append(name)
	out.sort()
	return out


static func get_item(id: StringName) -> ItemData:
	_load_items()
	return _items.get(id) as ItemData


static func has_item(id: StringName) -> bool:
	_load_items()
	return _items.has(id)


static func all_items() -> Array[ItemData]:
	_load_items()
	var out: Array[ItemData] = []
	var keys: Array = _items.keys()
	keys.sort()
	for k: Variant in keys:
		out.append(_items[k])
	return out


## Objet de sac représentant une arme : data/items/wpn_<id>.tres, sinon objet créé à la
## volée (ex. pistolet de départ, sans objet dédié) et mis en cache.
static func weapon_item(w: WeaponData) -> ItemData:
	if w == null:
		return null
	var iid := StringName("wpn_" + String(w.id))
	var it := get_item(iid)
	if it != null:
		return it
	it = ItemData.new()
	it.id = iid
	it.display_name = w.display_name
	it.description = w.description
	it.rarity = w.rarity
	it.type = ItemData.TYPE_WEAPON
	it.weapon_id = w.id
	it.stack_max = 1
	it.value = w.value
	it.weight = 1.0
	_items[iid] = it
	return it


static func all_keys() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for it: ItemData in all_items():
		if it.is_key():
			out.append(it)
	return out


# --- Tables -----------------------------------------------------------------------

static func get_table(kind: StringName) -> LootTable:
	if _tables.has(kind):
		return _tables[kind]
	var path := TABLES_DIR + String(kind) + ".tres"
	var t: LootTable = null
	if ResourceLoader.exists(path):
		t = load(path) as LootTable
	_tables[kind] = t
	return t


static func table_kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for f: String in _list_resources(TABLES_DIR):
		out.append(f.get_basename())
	return out


# --- Config [loot] ----------------------------------------------------------------

static func cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if _cfg.load(BALANCE_PATH) != OK:
			push_warning("LootDB: impossible de charger %s" % BALANCE_PATH)
	return _cfg


static func getf(key: String, def: float) -> float:
	return float(cfg().get_value(SECTION, key, def))


static func geti(key: String, def: int) -> int:
	return int(cfg().get_value(SECTION, key, def))


static func get_arr(key: String, def: Array) -> Array:
	var v: Variant = cfg().get_value(SECTION, key, def)
	return v if v is Array else def


static func get_dict(key: String, def: Dictionary) -> Dictionary:
	var v: Variant = cfg().get_value(SECTION, key, def)
	return v if v is Dictionary else def


## Valeur d'un tableau indexé (difficulté, rareté…), bornée.
static func arr_at(key: String, index: int, def: Array) -> float:
	var a := get_arr(key, def)
	if a.is_empty():
		return 0.0
	return float(a[clampi(index, 0, a.size() - 1)])


static func reload() -> void:
	_cfg = null
	_items.clear()
	_tables.clear()
	_items_loaded = false
