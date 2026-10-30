class_name CurrencyArt
extends RefCounted
## Images peintes de la monnaie (rendus 3D « toon peint » de art/blender/build_currency.py) :
## gemme, pièce d'or et illustrations des packs de gemmes, dans assets/ui/currency/.
## Chaque accès renvoie null si l'image manque : les icônes retombent alors sur leur dessin en code.

const DIR := "res://assets/ui/currency/"
## Nombre d'illustrations de packs (gems_pack_1 … gems_pack_N) ; au-delà, la dernière est reprise.
const PACK_IMAGES := 4
## Les images gardent une marge pour leur lueur : les icônes les dessinent un peu plus grandes que
## leur boîte pour occuper la même place que l'ancien dessin (le débordement est la lueur).
const ICON_ZOOM := 1.2

## false : ignore les images (tests du repli, comparaison avant/après).
static var enabled: bool = true
static var _cache: Dictionary = {}


static func texture(id: String) -> Texture2D:
	if not enabled:
		return null
	if _cache.has(id):
		return _cache[id]
	var path := DIR + id + ".png"
	var t: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_cache[id] = t
	return t


static func gem() -> Texture2D:
	return texture("gem")


static func coin() -> Texture2D:
	return texture("coin")


## Illustration du pack de gemmes d'indice `i` (0 = le plus petit), de plus en plus généreuse.
static func pack(i: int) -> Texture2D:
	return texture("gems_pack_%d" % clampi(i + 1, 1, PACK_IMAGES))


## Dessine `tex` centrée dans `rect` en gardant ses proportions.
static func draw_fit(ci: CanvasItem, tex: Texture2D, rect: Rect2, modulate: Color = Color.WHITE) -> void:
	var ts := tex.get_size()
	var k: float = minf(rect.size.x / ts.x, rect.size.y / ts.y)
	var sz := ts * k
	ci.draw_texture_rect(tex, Rect2(rect.position + (rect.size - sz) * 0.5, sz), false, modulate)
