class_name LootVisuals
extends RefCounted
## Petits utilitaires visuels partagés (textures avec mipmaps pour les icônes
## 512 px, polices du projet). Tout est mis en cache.

const FONT_TITLE_PATH := "res://assets/fonts/anton/Anton-Regular.ttf"
const FONT_TEXT_PATH := "res://assets/fonts/space_grotesk/SpaceGrotesk-Variable.ttf"

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


## Police de texte (Space Grotesk) à la graisse demandée, ramenée dans 300..700.
static func text_font(weight: int = 600) -> Font:
	weight = clampi(weight, 300, 700)
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


# --- Armes : icône d'inventaire et pictogramme de repli -----------------------------

## Icône à afficher pour un objet : arme → WeaponCatalog.icon_for (assets/ui/weapons/),
## sinon l'icône de l'objet. null = dessiner le pictogramme (draw_weapon_glyph).
static func item_icon(item: ItemData) -> Texture2D:
	if item == null:
		return null
	if item.is_weapon() and item.icon == null:
		return weapon_icon(WeaponCatalog.get_weapon(item.weapon_id))
	var art := item_art(item)
	return art if art != null else icon(item.icon)


## Dossier des icônes peintes des objets (art/blender/build_item_icons.py) : <id>.png.
const ITEM_ART_DIR := "res://assets/ui/items/"


## Icône peinte de l'objet (couleurs définitives, pas de teinte), null si elle n'existe pas.
static func item_art(item: ItemData) -> Texture2D:
	if item == null:
		return null
	if _art_cache.has(item.id):
		return _art_cache[item.id]
	var p := ITEM_ART_DIR + String(item.id) + ".png"
	var tex: Texture2D = load_icon(p) if ResourceLoader.exists(p) else null
	_art_cache[item.id] = tex
	return tex


static var _art_cache: Dictionary = {}


## Teinte à appliquer à l'icône : blanc pour une icône peinte, sinon la teinte de l'objet (SVG blanc).
static func item_tint(item: ItemData) -> Color:
	if item == null:
		return Color.WHITE
	return Color.WHITE if item_art(item) != null else item.tint


static func weapon_icon(w: WeaponData) -> Texture2D:
	if w == null:
		return null
	return icon(WeaponCatalog.icon_for(w))


## Dessine une icône d'arme (rapport ~2:1) centrée dans `rect` sans la déformer ;
## pictogramme de la catégorie si l'icône n'existe pas encore.
static func draw_weapon(ci: CanvasItem, rect: Rect2, w: WeaponData, color: Color = Color.WHITE) -> void:
	if w == null:
		return
	var tex := weapon_icon(w)
	if tex != null:
		var ts := tex.get_size()
		var k := minf(rect.size.x / maxf(ts.x, 1.0), rect.size.y / maxf(ts.y, 1.0))
		var sz := ts * k
		ci.draw_texture_rect(tex, Rect2(rect.position + (rect.size - sz) * 0.5, sz), false, color)
	else:
		var key: StringName = w.gadget_kind if w.is_gadget() and GLYPHS.has(w.gadget_kind) else w.category
		draw_weapon_glyph(ci, rect, key, color.lerp(w.get_rarity_color().lightened(0.55), 0.35))


## Silhouettes de profil (canon vers la droite) dans une boîte 100 × 50.
## r = rectangle [x0, y0, x1, y1], p = polygone, c = disque [cx, cy, r].
const GLYPHS := {
	&"pistol": [["r", 22, 12, 82, 22], ["p", [50, 22, 64, 22, 60, 44, 45, 44]], ["r", 40, 22, 52, 26]],
	&"revolver": [["r", 12, 15, 58, 21], ["r", 55, 10, 72, 27], ["p", [68, 22, 80, 20, 88, 42, 75, 44]], ["r", 46, 25, 58, 29]],
	&"smg": [["r", 6, 16, 22, 20], ["r", 20, 13, 74, 26], ["r", 74, 17, 92, 21], ["r", 44, 26, 53, 46], ["p", [61, 26, 69, 26, 67, 40, 59, 40]]],
	&"shotgun": [["p", [2, 18, 22, 13, 22, 26, 4, 33]], ["r", 22, 12, 42, 26], ["r", 42, 13, 97, 19], ["r", 46, 20, 86, 25]],
	&"rifle": [["p", [2, 14, 26, 13, 26, 25, 4, 31]], ["r", 26, 12, 66, 26], ["r", 66, 16, 97, 20], ["r", 38, 7, 56, 11], ["p", [44, 26, 54, 26, 58, 44, 49, 46]]],
	&"sniper": [["p", [2, 15, 26, 14, 26, 26, 2, 33]], ["r", 26, 14, 58, 25], ["r", 56, 17, 99, 20], ["r", 30, 5, 56, 11], ["r", 36, 11, 40, 14], ["r", 48, 11, 52, 14], ["p", [70, 20, 72, 20, 64, 40, 62, 40]]],
	&"lmg": [["p", [2, 14, 20, 14, 20, 28, 4, 32]], ["r", 20, 12, 70, 28], ["r", 70, 16, 97, 21], ["r", 34, 28, 52, 43], ["r", 40, 6, 58, 12]],
	&"rocket_launcher": [["r", 6, 14, 86, 28], ["p", [86, 12, 98, 16, 98, 26, 86, 30]], ["r", 2, 12, 8, 30], ["r", 40, 28, 48, 42], ["r", 52, 6, 62, 14]],
	# Équipement (clé = gadget_kind), dessiné au centre de la boîte.
	&"frag": [["c", 50, 30, 15], ["r", 44, 8, 56, 16], ["p", [56, 10, 66, 6, 68, 10, 58, 14]], ["c", 66, 4, 3]],
	&"smoke": [["r", 38, 12, 62, 46], ["r", 42, 6, 58, 12], ["p", [58, 8, 68, 4, 70, 8, 60, 12]], ["c", 30, 14, 6], ["c", 22, 8, 4]],
	&"mine": [["p", [24, 38, 76, 38, 70, 26, 30, 26]], ["r", 44, 18, 56, 26], ["c", 50, 17, 4]],
	&"c4": [["r", 26, 16, 74, 42], ["r", 30, 12, 46, 16], ["r", 54, 12, 70, 16], ["r", 40, 24, 60, 34]],
	&"drone": [["r", 40, 22, 60, 34], ["r", 22, 26, 78, 29], ["c", 22, 22, 9], ["c", 78, 22, 9], ["r", 47, 34, 53, 40]],
	&"gadget": [["c", 50, 30, 15], ["r", 44, 8, 56, 16]],
	&"grenade_launcher": [["p", [2, 18, 22, 15, 22, 28, 4, 34]], ["r", 22, 14, 52, 28], ["c", 40, 26, 11], ["r", 50, 12, 88, 26], ["r", 56, 28, 64, 42]],
}


static func draw_weapon_glyph(ci: CanvasItem, rect: Rect2, category: StringName, color: Color) -> void:
	var shapes: Array = GLYPHS.get(category, GLYPHS[&"pistol"])
	var k := minf(rect.size.x / 100.0, rect.size.y / 50.0)
	var origin := rect.position + (rect.size - Vector2(100.0, 50.0) * k) * 0.5
	var shadow := Color(0.02, 0.03, 0.07, 0.55)
	for pass_i in 2:
		var off := Vector2(1.5, 2.0) * maxf(k, 0.5) if pass_i == 0 else Vector2.ZERO
		var col := shadow if pass_i == 0 else color
		for s: Array in shapes:
			match String(s[0]):
				"r":
					ci.draw_rect(Rect2(origin + off + Vector2(s[1], s[2]) * k, Vector2(float(s[3]) - float(s[1]), float(s[4]) - float(s[2])) * k), col)
				"c":
					ci.draw_circle(origin + off + Vector2(s[1], s[2]) * k, float(s[3]) * k, col, true, -1.0, true)
				"p":
					var raw: Array = s[1]
					var pts := PackedVector2Array()
					for i in range(0, raw.size(), 2):
						pts.append(origin + off + Vector2(raw[i], raw[i + 1]) * k)
					ci.draw_colored_polygon(pts, col)
