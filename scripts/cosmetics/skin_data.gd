class_name SkinData
extends Resource
## Skin purement cosmétique (aucun effet sur les stats). Un .tres par skin : data/skins/<id>.tres.
## - kind "character" : apparence du héros (planches de sprites dédiées dans `sprite_dir`,
##   sinon recoloration de la planche par défaut via `colors`).
## - kind "weapon" : skin d'UNE arme précise (`weapon_id`, ex. rifle_ak47 « Tigre »), sinon des
##   armes d'une catégorie (`weapon_category`, « any » = toutes) ; rendu par WeaponSkin.apply()
##   (texture dédiée rendue sous Blender si elle existe, sinon recoloration par shader).
## - source : où on l'obtient : « shop » (boutique, gemmes), « pass » (pass de combat, piste
##   premium : absent de la boutique), « default » (offert). Un skin du pass garde un prix
##   (`price_gems` = valeur indicative) : il n'est possédé qu'une fois récupéré dans le pass.

const DIR := "res://data/skins/"
const KIND_CHARACTER := &"character"
const KIND_WEAPON := &"weapon"
const ANY_CATEGORY := &"any"
const SOURCE_SHOP := &"shop"
const SOURCE_PASS := &"pass"
const SOURCE_DEFAULT := &"default"
## Textures dédiées (rendues par art/blender/build_weapon_skins.py) : <dossier><skin_id>.png.
const HELD_SKIN_DIR := "res://assets/sprites/weapons/skins/"
const ICON_SKIN_DIR := "res://assets/ui/weapons/skins/"

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
## Skin d'arme : arme précise (WeaponData.id) ; vide = toute la catégorie. Prioritaire sur la catégorie.
@export var weapon_id: StringName = &""
## Provenance : shop, pass ou default.
@export var source: StringName = SOURCE_SHOP

@export_group("Rendu")
## Skin de personnage : dossier contenant hero_frames.tres + hero_meta.json (vide = planche par défaut recolorée).
@export var sprite_dir: String = ""
## Couleurs principales (recoloration) : primaire, secondaire, accent.
@export var color_primary: Color = Color.WHITE
@export var color_secondary: Color = Color.WHITE
@export var color_accent: Color = Color.WHITE
## Motif d'arme : none, stripes, camo, digital, gold, neon, carbon, tiger, flames, rust (WeaponSkin.PATTERNS).
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


## Skins d'un type vendus en boutique (source shop), même tri que all_of_kind.
static func shop_skins(k: StringName) -> Array[SkinData]:
	var out: Array[SkinData] = []
	for s: SkinData in all_of_kind(k):
		if s.is_in_shop():
			out.append(s)
	return out


## Skins d'armes d'une arme précise (weapon_id), triés par rareté puis prix.
static func for_weapon(wid: StringName) -> Array[SkinData]:
	var out: Array[SkinData] = []
	for s: SkinData in all_of_kind(KIND_WEAPON):
		if s.weapon_id == wid:
			out.append(s)
	out.sort_custom(func(a: SkinData, b: SkinData) -> bool:
		return a.rarity < b.rarity if a.rarity != b.rarity else a.price_gems < b.price_gems)
	return out


func is_in_shop() -> bool:
	return source == SOURCE_SHOP and price_gems > 0


func is_pass() -> bool:
	return source == SOURCE_PASS


## S'applique à cette arme ? Skin par arme : seulement si `wid` est cette arme.
## Skin de catégorie : catégorie ou « any ».
func applies_to(category: StringName, wid: StringName = &"") -> bool:
	if kind != KIND_WEAPON:
		return false
	if not String(weapon_id).is_empty():
		return weapon_id == wid
	return weapon_category == ANY_CATEGORY or weapon_category == category


## Texture dédiée de l'arme tenue (null = recoloration par shader).
func held_texture() -> Texture2D:
	var p := HELD_SKIN_DIR + String(id) + ".png"
	return load(p) as Texture2D if kind == KIND_WEAPON and ResourceLoader.exists(p) else null


## Icône dédiée (menus) (null = icône de l'arme recolorée par shader).
func icon_texture() -> Texture2D:
	var p := ICON_SKIN_DIR + String(id) + ".png"
	return load(p) as Texture2D if kind == KIND_WEAPON and ResourceLoader.exists(p) else null
