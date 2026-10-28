class_name HeroSkin
extends RefCounted
## Apparence du héros selon le skin de personnage porté (SkinData kind "character").
## Chaque skin a ses planches dédiées (même format que la planche par défaut) dans
## `sprite_dir` : hero_frames.tres + hero_meta.json + hero_<anim>.png + preview.png.
## Planches générées par art/blender/build_hero.py. Purement cosmétique.

const DEFAULT_DIR := "res://assets/sprites/hero3d/"
const DEFAULT_SKIN_ID := &"char_default"
## Animations fournies par les planches (<anim>_<dir>).
const ANIMS: Array[StringName] = [&"idle", &"run", &"backpedal", &"strafe_l", &"strafe_r", &"hit"]
const DIRECTIONS: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

## Recoloration de repli (skin sans planche dédiée) : teinte la tenue en conservant la luminance.
const RECOLOR_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.5;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float sat = max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
	vec3 t = tint.rgb * (l * 1.6);
	COLOR = vec4(mix(c.rgb, t, amount * smoothstep(0.08, 0.3, sat)), c.a) * COLOR;
}
"""

static var _frames_cache: Dictionary = {}
static var _meta_cache: Dictionary = {}
static var _shader: Shader = null


## Dossier des planches du héros pour ce skin (hero_frames.tres + hero_meta.json).
static func sprite_dir_for(skin: SkinData) -> String:
	if skin != null and not skin.sprite_dir.is_empty() and ResourceLoader.exists(skin.sprite_dir.path_join("hero_frames.tres")):
		return skin.sprite_dir
	return DEFAULT_DIR


## SpriteFrames du héros pour ce skin (repli : planche par défaut).
static func frames_for(skin: SkinData) -> SpriteFrames:
	var dir := sprite_dir_for(skin)
	if _frames_cache.has(dir):
		return _frames_cache[dir] as SpriteFrames
	var sf := load(dir.path_join("hero_frames.tres")) as SpriteFrames
	if sf == null and dir != DEFAULT_DIR:
		sf = load(DEFAULT_DIR.path_join("hero_frames.tres")) as SpriteFrames
	if sf != null:
		_frames_cache[dir] = sf
	return sf


## Métadonnées (frame_size, feet_offset, display_height, fps, frames, hand_height…) pour ce skin.
static func meta_for(skin: SkinData) -> Dictionary:
	var dir := sprite_dir_for(skin)
	if _meta_cache.has(dir):
		return _meta_cache[dir] as Dictionary
	var p := dir.path_join("hero_meta.json")
	if not FileAccess.file_exists(p):
		p = DEFAULT_DIR.path_join("hero_meta.json")
		if not FileAccess.file_exists(p):
			return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	var meta: Dictionary = d if d is Dictionary else {}
	_meta_cache[dir] = meta
	return meta


## Matériau de recoloration à appliquer au sprite (skins sans planche dédiée) ; null = aucun.
static func material_for(skin: SkinData) -> Material:
	if skin == null or sprite_dir_for(skin) != DEFAULT_DIR or skin.id == DEFAULT_SKIN_ID:
		return null
	if skin.color_primary == Color.WHITE:
		return null
	if _shader == null:
		_shader = Shader.new()
		_shader.code = RECOLOR_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter(&"tint", skin.color_primary)
	m.set_shader_parameter(&"amount", 0.55)
	return m


## Aperçu (image de face, idle) pour la boutique.
static func preview_for(skin: SkinData) -> Texture2D:
	if skin != null and skin.preview != null:
		return skin.preview
	var p := sprite_dir_for(skin).path_join("preview.png")
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


## Skin porté par le joueur (Profile), sinon le skin par défaut (ou null s'il manque).
static func current() -> SkinData:
	var s: SkinData = Profile.get_character_skin()
	if s != null:
		return s
	return SkinData.get_skin(DEFAULT_SKIN_ID)


## Vide les caches (après un changement de fichiers en éditeur).
static func clear_cache() -> void:
	_frames_cache.clear()
	_meta_cache.clear()
