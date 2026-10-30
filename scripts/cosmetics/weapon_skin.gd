class_name WeaponSkin
extends RefCounted
## Skins d'armes (SkinData kind "weapon") : équipement par arme et rendu. Purement visuel.
##
## Équipement : Profile.skin_weapons (Dictionary sauvegardé par le profil) avec des clés
##   - <weapon_id> (ex. "rifle_ak47") : skin de CETTE arme — prioritaire ;
##   - <category> / "any" : anciens skins de catégorie (Profile.equip_weapon_skin).
## Rendu (apply) :
##   1. texture dédiée rendue sous Blender si elle existe (assets/sprites/weapons/skins/<id>.png
##      pour l'arme tenue, assets/ui/weapons/skins/<id>.png pour les icônes ; mêmes dimensions
##      que les images d'origine : grip et muzzle inchangés) ;
##   2. sinon recoloration par assets/shaders/weapon_skin.gdshader (ombrage gardé + motif).
## L'arme est reconnue par `weapon_id`, sinon par le chemin de sa texture (…/weapons/<id>.png) :
## le joueur (WeaponView) appelle apply(item, Profile.get_weapon_skin(category)) et le skin
## propre à l'arme équipée l'emporte automatiquement.

const SHADER: Shader = preload("res://assets/shaders/weapon_skin.gdshader")
const PATTERNS := {
	&"none": 0, &"stripes": 1, &"camo": 2, &"digital": 3, &"gold": 4, &"neon": 5, &"carbon": 6,
	&"tiger": 7, &"flames": 8, &"rust": 9,
}
const META_BASE_TEX := &"wsk_base_texture"
const META_SKIN := &"wsk_skin_id"


## Forçage (tests) : -1 = balance.cfg, 0 = désactivé, 1 = activé.
static var enabled_override: int = -1


## Skins d'armes activés ? (balance.cfg [shop] weapon_skins_enabled).
static func is_enabled() -> bool:
	if enabled_override >= 0:
		return enabled_override == 1
	return bool(Balance.get_value("shop", "weapon_skins_enabled", false))


# --- Équipement (par arme) ---------------------------------------------------------------

static func _profile() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null(^"Profile") if ml != null else null


static func _equipped_dict() -> Dictionary:
	var p := _profile()
	if p == null:
		return {}
	var d: Variant = p.get("skin_weapons")
	return d if d is Dictionary else {}


## Id du skin équipé sur cette arme précise ("" = aucun).
static func equipped_id(weapon_id: StringName) -> StringName:
	return StringName(str(_equipped_dict().get(String(weapon_id), "")))


## Skin à afficher pour cette arme : skin de l'arme, sinon de sa catégorie, sinon « any ».
static func equipped_for(w: WeaponData) -> SkinData:
	if w == null:
		return null
	var d := _equipped_dict()
	for key: String in [String(w.id), String(w.category), String(SkinData.ANY_CATEGORY)]:
		var sid := str(d.get(key, ""))
		if sid.is_empty():
			continue
		var s := SkinData.get_skin(StringName(sid))
		if s != null and s.applies_to(w.category, w.id):
			return s
	return null


## Ids des skins équipés sur ces armes (même ordre, « » = aucun) : envoyés au coéquipier pour qu'il
## voie nos armes telles que nous les voyons. Skins d'armes désactivés : que des « ».
static func skin_ids_for(weapons: Array) -> Array[String]:
	var out: Array[String] = []
	for w: Variant in weapons:
		var s: SkinData = equipped_for(w as WeaponData) if w is WeaponData and is_enabled() else null
		out.append(String(s.id) if s != null else "")
	return out


## Dictionnaire id d'arme → id de skin (WeaponView.set_skin_ids) à partir de deux listes parallèles.
static func skin_map(weapon_ids: Array, skins: Array) -> Dictionary:
	var d: Dictionary = {}
	for i: int in mini(weapon_ids.size(), skins.size()):
		var wid := str(weapon_ids[i])
		var sid := str(skins[i])
		if not wid.is_empty() and not sid.is_empty():
			d[wid] = sid
	return d


## Équipe un skin possédé sur son arme (skin par arme) ou sa catégorie. Renvoie false sinon.
static func equip(skin_id: StringName) -> bool:
	var s := SkinData.get_skin(skin_id)
	var p := _profile()
	if s == null or s.kind != SkinData.KIND_WEAPON or p == null or not bool(p.call("owns_skin", skin_id)):
		return false
	if String(s.weapon_id).is_empty():
		return bool(p.call("equip_weapon_skin", skin_id, s.weapon_category))
	var d := _equipped_dict()
	d[String(s.weapon_id)] = String(skin_id)
	p.set("skin_weapons", d)
	p.call("save")
	return true


## Retire le skin propre à cette arme (apparence d'origine, ou skin de catégorie s'il y en a un).
static func unequip(weapon_id: StringName) -> void:
	var p := _profile()
	if p == null:
		return
	var d := _equipped_dict()
	d.erase(String(weapon_id))
	p.set("skin_weapons", d)
	p.call("save")


static func is_equipped(s: SkinData) -> bool:
	if s == null or s.kind != SkinData.KIND_WEAPON:
		return false
	var key: String = String(s.weapon_id) if not String(s.weapon_id).is_empty() else String(s.weapon_category)
	return str(_equipped_dict().get(key, "")) == String(s.id)


# --- Rendu ----------------------------------------------------------------------------------

## Applique `skin` à `item` (Sprite2D, TextureRect ou Control dessiné). skin null = apparence
## d'origine, sauf si l'arme a son propre skin équipé (`resolve_equipped`, reconnu par
## `weapon_id` ou par la texture). Skins d'armes désactivés : ne fait rien.
static func apply(item: CanvasItem, skin: SkinData, weapon_id: StringName = &"", resolve_equipped: bool = true) -> void:
	if item == null or not is_enabled():
		return
	var wid: StringName = weapon_id if not String(weapon_id).is_empty() else weapon_id_of(item)
	if not String(wid).is_empty():
		if resolve_equipped and (skin == null or String(skin.weapon_id).is_empty()):
			var own := SkinData.get_skin(equipped_id(wid))
			if own != null and own.applies_to(own.weapon_category, wid):
				skin = own
		if skin != null and not String(skin.weapon_id).is_empty() and skin.weapon_id != wid:
			skin = null   # skin d'une autre arme (ex. rangé par erreur sous la catégorie)
	_restore_texture(item)
	if skin == null or skin.kind != SkinData.KIND_WEAPON:
		item.material = null
		item.remove_meta(META_SKIN)
		return
	item.set_meta(META_SKIN, String(skin.id))
	var dedicated: Texture2D = _dedicated_for(item, skin)
	if dedicated != null:
		_set_texture(item, dedicated)
		# Texture finale : seulement la lueur de contour éventuelle (légendaires).
		item.material = make_material(skin, _aspect_of(item), 0.0) if skin.glow > 0.0 else null
		return
	item.material = make_material(skin, _aspect_of(item))


## Matériau du skin (aspect = largeur / hauteur de l'image, pour des motifs non déformés).
static func make_material(skin: SkinData, aspect: float = 2.0, strength: float = 1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"color_primary", skin.color_primary)
	m.set_shader_parameter(&"color_secondary", skin.color_secondary)
	m.set_shader_parameter(&"color_accent", skin.color_accent)
	m.set_shader_parameter(&"pattern", pattern_index(skin.pattern))
	m.set_shader_parameter(&"aspect", maxf(aspect, 0.1))
	m.set_shader_parameter(&"glow", skin.glow)
	m.set_shader_parameter(&"strength", strength)
	return m


static func pattern_index(p: StringName) -> int:
	return int(PATTERNS.get(p, 0))


## Skin équipé pour cette arme (par arme, puis catégorie), puis appliqué.
static func apply_equipped(item: CanvasItem, w: WeaponData) -> void:
	if w == null:
		apply(item, null, &"", false)
		return
	apply(item, equipped_for(w), w.id)


## Id d'arme déduit de la texture d'origine (…/weapons/<id>.png), "" si inconnu.
static func weapon_id_of(item: CanvasItem) -> StringName:
	var tex: Texture2D = item.get_meta(META_BASE_TEX) as Texture2D if item.has_meta(META_BASE_TEX) else _texture_of(item)
	if tex == null or tex.resource_path.is_empty():
		return &""
	var path := tex.resource_path
	if not path.contains("/weapons/") or path.contains("/skins/"):
		return &""
	return StringName(path.get_file().get_basename())


static func _texture_of(item: CanvasItem) -> Texture2D:
	if item is Sprite2D:
		return (item as Sprite2D).texture
	if item is TextureRect:
		return (item as TextureRect).texture
	return null


static func _set_texture(item: CanvasItem, tex: Texture2D) -> void:
	var base := _texture_of(item)
	if base == null:
		return
	if not item.has_meta(META_BASE_TEX):
		item.set_meta(META_BASE_TEX, base)
	if item is Sprite2D:
		(item as Sprite2D).texture = tex
	elif item is TextureRect:
		(item as TextureRect).texture = tex


static func _restore_texture(item: CanvasItem) -> void:
	if not item.has_meta(META_BASE_TEX):
		return
	var base := item.get_meta(META_BASE_TEX) as Texture2D
	item.remove_meta(META_BASE_TEX)
	if item is Sprite2D:
		(item as Sprite2D).texture = base
	elif item is TextureRect:
		(item as TextureRect).texture = base


## Texture dédiée adaptée à l'objet (arme tenue ou icône), à condition d'avoir les mêmes
## dimensions que l'image d'origine (grip/muzzle du JSON valables).
static func _dedicated_for(item: CanvasItem, skin: SkinData) -> Texture2D:
	var base := _texture_of(item)
	if base == null or String(skin.weapon_id).is_empty():
		return null
	var path := base.resource_path
	var t: Texture2D = null
	if path.contains("/sprites/weapons/"):
		t = skin.held_texture()
	elif path.contains("/ui/weapons/"):
		t = skin.icon_texture()
	if t != null and t.get_size() != base.get_size():
		return null
	return t


static func _aspect_of(item: CanvasItem) -> float:
	var tex: Texture2D = _texture_of(item)
	if tex != null and tex.get_height() > 0:
		return float(tex.get_width()) / float(tex.get_height())
	# Control dessiné (draw_texture_rect d'une icône 2:1) : aspect de l'icône.
	return 2.0
