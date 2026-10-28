class_name WeaponSkin
extends RefCounted
## Application d'un skin d'arme (SkinData kind "weapon") sur le sprite d'une arme tenue ou
## d'une icône (Sprite2D, TextureRect, Control dessiné…). Purement visuel : aucun effet en jeu.
## Shader : assets/shaders/weapon_skin.gdshader (recoloration qui garde l'ombrage + motif
## procédural + lueur optionnelle). Un ShaderMaterial par appel (peu d'objets concernés).

const SHADER: Shader = preload("res://assets/shaders/weapon_skin.gdshader")
const PATTERNS := {
	&"none": 0, &"stripes": 1, &"camo": 2, &"digital": 3, &"gold": 4, &"neon": 5, &"carbon": 6,
}


## Applique `skin` à `item`. skin null = apparence d'origine (matériau retiré).
static func apply(item: CanvasItem, skin: SkinData) -> void:
	if item == null:
		return
	if skin == null or skin.kind != SkinData.KIND_WEAPON:
		item.material = null
		return
	item.material = make_material(skin, _aspect_of(item))


## Matériau du skin (aspect = largeur / hauteur de l'image, pour des motifs non déformés).
static func make_material(skin: SkinData, aspect: float = 2.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter(&"color_primary", skin.color_primary)
	m.set_shader_parameter(&"color_secondary", skin.color_secondary)
	m.set_shader_parameter(&"color_accent", skin.color_accent)
	m.set_shader_parameter(&"pattern", pattern_index(skin.pattern))
	m.set_shader_parameter(&"aspect", maxf(aspect, 0.1))
	m.set_shader_parameter(&"glow", skin.glow)
	return m


static func pattern_index(p: StringName) -> int:
	return int(PATTERNS.get(p, 0))


## Skin équipé pour cette arme (Profile), puis appliqué.
static func apply_equipped(item: CanvasItem, w: WeaponData) -> void:
	if w == null:
		apply(item, null)
		return
	apply(item, Profile.get_weapon_skin(w.category))


static func _aspect_of(item: CanvasItem) -> float:
	var tex: Texture2D = null
	if item is Sprite2D:
		tex = (item as Sprite2D).texture
	elif item is TextureRect:
		tex = (item as TextureRect).texture
	if tex != null and tex.get_height() > 0:
		return float(tex.get_width()) / float(tex.get_height())
	if item is Control and (item as Control).size.y > 0.0:
		return (item as Control).size.x / (item as Control).size.y
	return 2.0
