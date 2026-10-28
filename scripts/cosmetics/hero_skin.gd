class_name HeroSkin
extends RefCounted
## Apparence du héros selon le skin de personnage porté (SkinData kind "character").
## STUB du contrat : implémentation complète par l'agent Art (planches par skin).

const DEFAULT_DIR := "res://assets/sprites/hero3d/"


## Dossier des planches du héros pour ce skin (hero_frames.tres + hero_meta.json).
static func sprite_dir_for(skin: SkinData) -> String:
	if skin != null and not skin.sprite_dir.is_empty() and ResourceLoader.exists(skin.sprite_dir.path_join("hero_frames.tres")):
		return skin.sprite_dir
	return DEFAULT_DIR


## SpriteFrames du héros pour ce skin (repli : planche par défaut).
static func frames_for(skin: SkinData) -> SpriteFrames:
	return load(sprite_dir_for(skin).path_join("hero_frames.tres")) as SpriteFrames


## Métadonnées (frame_size, feet_offset, display_height, fps…) pour ce skin.
static func meta_for(skin: SkinData) -> Dictionary:
	var p := sprite_dir_for(skin).path_join("hero_meta.json")
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {}


## Matériau de recoloration à appliquer au sprite (skins sans planche dédiée) ; null = aucun.
static func material_for(skin: SkinData) -> Material:
	return null


## Skin porté par le joueur (Profile), ou null.
static func current() -> SkinData:
	return Profile.get_character_skin()
