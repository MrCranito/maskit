class_name SkinData
extends Resource
## Skin purement cosmétique (aucun effet sur les stats). Un .tres par skin : data/skins/<id>.tres.
## - kind "character" : apparence du héros (planches de sprites dédiées dans `sprite_dir`,
##   sinon recoloration de la planche par défaut via `colors`).
## - kind "weapon" : recoloration/motif des armes d'une catégorie (`weapon_category`,
##   « any » = toutes) via WeaponSkin.apply().

const DIR := "res://data/skins/"
const KIND_CHARACTER := &"character"
const KIND_WEAPON := &"weapon"
const ANY_CATEGORY := &"any"

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: StringName = KIND_CHARACTER
## 0..4 (mêmes couleurs que les armes) : affichage seulement.
@export_range(0, 4) var rarity: int = 0
## Prix en gemmes (0 = offert / débloqué d'office).
@export var price_gems: int = 0
## Skin d'arme : catégorie concernée (WeaponData.CAT_*), ou « any ».
@export var weapon_category: StringName = ANY_CATEGORY

@export_group("Rendu")
## Skin de personnage : dossier contenant hero_frames.tres + hero_meta.json (vide = planche par défaut recolorée).
@export var sprite_dir: String = ""
## Couleurs principales (recoloration) : primaire, secondaire, accent.
@export var color_primary: Color = Color.WHITE
@export var color_secondary: Color = Color.WHITE
@export var color_accent: Color = Color.WHITE
## Motif d'arme : none, stripes, camo, digital, gold, neon, carbon.
@export var pattern: StringName = &"none"
## Lueur (néon, légendaires) : 0 = aucune.
@export_range(0.0, 1.0) var glow: float = 0.0
## Aperçu pour la boutique (sinon rendu en direct).
@export var preview: Texture2D = null


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
		if file.ends_with(".tres"):
			var s := load(DIR + file) as SkinData
			if s != null and not String(s.id).is_empty():
				_cache[s.id] = s


static func reload() -> void:
	_loaded = false
	_cache.clear()
	_load_all()


static func get_skin(id: StringName) -> SkinData:
	_load_all()
	return _cache.get(id) as SkinData


## Tous les skins d'un type (character / weapon), triés par prix puis nom.
static func all_of_kind(k: StringName) -> Array[SkinData]:
	_load_all()
	var out: Array[SkinData] = []
	for s: SkinData in _cache.values():
		if s.kind == k:
			out.append(s)
	out.sort_custom(func(a: SkinData, b: SkinData) -> bool:
		return a.price_gems < b.price_gems if a.price_gems != b.price_gems else a.display_name < b.display_name)
	return out


func applies_to(category: StringName) -> bool:
	return kind == KIND_WEAPON and (weapon_category == ANY_CATEGORY or weapon_category == category)
