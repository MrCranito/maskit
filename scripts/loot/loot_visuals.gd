class_name LootVisuals
extends RefCounted
## Petits utilitaires visuels partagés (textures avec mipmaps pour les icônes
## 512 px, polices du projet). Tout est mis en cache.

const FONT_TITLE_PATH := "res://assets/fonts/rye/Rye-Regular.ttf"
const FONT_TEXT_PATH := "res://assets/fonts/nunito/Nunito-Variable.ttf"

static var _mip_cache: Dictionary = {}
static var _fonts: Dictionary = {}


## Texture réduite proprement (mipmaps) : les icônes CC-BY font 512 px et sont
## importées sans mipmaps → crénelées une fois affichées à 64 px.
static func icon(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	if _mip_cache.has(tex):
		return _mip_cache[tex]
	var out: Texture2D = tex
	if DisplayServer.get_name() != "headless":
		var img := tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.generate_mipmaps()
			out = ImageTexture.create_from_image(img)
	_mip_cache[tex] = out
	return out


static func load_icon(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return icon(load(path) as Texture2D)


static func title_font() -> Font:
	return _font("title", FONT_TITLE_PATH, 0)


## Nunito à la graisse demandée (400 normal, 700 gras, 800 extra-gras).
static func text_font(weight: int = 600) -> Font:
	return _font("text_%d" % weight, FONT_TEXT_PATH, weight)


static func _font(key: String, path: String, weight: int) -> Font:
	if _fonts.has(key):
		return _fonts[key]
	var f: Font = ThemeDB.fallback_font
	if ResourceLoader.exists(path):
		var base := load(path) as Font
		if base != null:
			if weight > 0:
				var v := FontVariation.new()
				v.base_font = base
				v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
				f = v
			else:
				f = base
	_fonts[key] = f
	return f


## LabelSettings prêtes à l'emploi (contour bleu nuit pour la lisibilité sur le décor).
static func label_settings(font: Font, size: int, color: Color, outline: int = 0) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = color
	if outline > 0:
		ls.outline_size = outline
		ls.outline_color = Color(0.05, 0.07, 0.13)
	return ls
