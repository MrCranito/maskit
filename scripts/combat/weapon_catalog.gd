class_name WeaponCatalog
extends RefCounted
## Accès au catalogue d'armes (data/weapons/*.tres), chargé une fois et mis en cache.

const DIR := "res://data/weapons/"
## Arme offerte quand l'arsenal est vide (perdue à la mort comme les autres).
const STARTER_ID: StringName = &"pistol_p9"
## Icônes d'inventaire par catégorie (repli si WeaponData.icon est vide).
const ICON_DIR := "res://assets/ui/weapons/"

static var _cache: Dictionary = {}
static var _loaded: bool = false


static func _load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for f: String in dir.get_files():
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var w := load(DIR + file) as WeaponData
		if w != null and not String(w.id).is_empty():
			_cache[w.id] = w


static func reload() -> void:
	_loaded = false
	_cache.clear()
	_load_all()


static func has_weapon(id: StringName) -> bool:
	_load_all()
	return _cache.has(id)


## Arme par id (null si inconnue).
static func get_weapon(id: StringName) -> WeaponData:
	_load_all()
	return _cache.get(id) as WeaponData


static func get_starter() -> WeaponData:
	return get_weapon(STARTER_ID)


## Toutes les armes, triées par catégorie puis rareté.
static func all() -> Array[WeaponData]:
	_load_all()
	var out: Array[WeaponData] = []
	for w: WeaponData in _cache.values():
		out.append(w)
	out.sort_custom(func(a: WeaponData, b: WeaponData) -> bool:
		var ca := WeaponData.CATEGORIES.find(a.category)
		var cb := WeaponData.CATEGORIES.find(b.category)
		if ca != cb:
			return ca < cb
		if a.rarity != b.rarity:
			return a.rarity < b.rarity
		return String(a.id) < String(b.id))
	return out


## Icône d'inventaire : WeaponData.icon, sinon assets/ui/weapons/<sprite_id>.png, sinon <category>.png.
static func icon_for(w: WeaponData) -> Texture2D:
	if w == null:
		return null
	if w.icon != null:
		return w.icon
	for cand: String in [String(w.get_sprite_id()), String(w.category)]:
		var p := ICON_DIR + cand + ".png"
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null
