extends Node2D
## Décor du centre commercial : sprite 3D peint (Blender, même caméra 3/4 que le héros) pris
## dans l'atlas unique assets/sprites/mall/atlas.png (pièce prop_<kind>, ombre bleu nuit déjà
## peinte), petite collision couche world si le décor bloque. Origine = point d'appui au sol
## (tri en Y) ; les grands décors (fontaine, voitures, gondoles) sont centrés sur leur emprise.
## Aucun traitement par image. Régénérer : art/blender/mall/build_mall_props.py.

const ATLAS: Texture2D = preload("res://assets/sprites/mall/atlas.png")
const AtlasMeta := preload("res://assets/sprites/mall/atlas_meta.gd")
const LAYER_WORLD := 1
const PX_PER_WORLD := 2.0

## kind → block (taille de collision, unités monde ; ZERO = traversable), flat (posé au sol, z 1),
## glow (rayon de lueur additive, 0 = aucune), tint (couleur de la lueur).
const DEFS := {
	&"fountain": {"block": Vector2(290, 150)},
	&"planter": {"block": Vector2(88, 34)},
	&"palm_pot": {"block": Vector2(30, 18)},
	&"bench": {"block": Vector2(84, 16)},
	&"mannequin": {"block": Vector2(24, 14)},
	&"clothes_rack": {"block": Vector2(78, 14)},
	&"store_shelf": {"block": Vector2(176, 40)},
	&"checkout": {"block": Vector2(92, 30)},
	&"food_table": {"block": Vector2(50, 30)},
	&"cinema_seats": {"block": Vector2(166, 30)},
	&"popcorn_machine": {"block": Vector2(46, 24)},
	&"arcade_cabinet": {"block": Vector2(40, 26), "glow": 46.0, "tint": Color(0.5, 0.9, 1.0)},
	&"car_wreck": {"block": Vector2(136, 52)},
	&"traffic_cone": {"block": Vector2.ZERO},
	&"trash_bin": {"block": Vector2(22, 14)},
	&"neon_sign": {"block": Vector2(22, 12), "glow": 70.0, "tint": Color(1.0, 0.35, 0.75)},
	&"mall_map": {"block": Vector2(26, 12), "glow": 40.0, "tint": Color(1.0, 0.85, 0.55)},
	&"puddle": {"block": Vector2.ZERO, "flat": true},
	&"debris": {"block": Vector2.ZERO},
	&"desk": {"block": Vector2(80, 30), "glow": 40.0, "tint": Color(1.0, 0.8, 0.45)},
	&"filing_cabinet": {"block": Vector2(28, 22)},
	&"ac_unit": {"block": Vector2(66, 36)},
	&"roof_vent": {"block": Vector2(22, 18)},
	&"tv_wall": {"block": Vector2(82, 24), "glow": 54.0, "tint": Color(0.5, 0.85, 1.0)},
	&"toy_pile": {"block": Vector2(46, 20)},
	&"medicine_shelf": {"block": Vector2(82, 20), "glow": 36.0, "tint": Color(0.4, 1.0, 0.55)},
	&"generator": {"block": Vector2(84, 36)},
}
## Grands décors : collision centrée sur l'origine (centre de l'emprise) au lieu d'être posée devant.
const CENTERED := [&"fountain", &"store_shelf", &"car_wreck", &"cinema_seats"]

static var _tex_cache: Dictionary = {}

var kind: StringName = &""
var body: StaticBody2D = null
var _sprite: Sprite2D = null


static func create(p_kind: StringName, pos: Vector2) -> Node2D:
	var p: Node2D = (load("res://scripts/biomes/mall/mall_prop.gd") as GDScript).new()
	p.name = "Prop_%s" % String(p_kind)
	p.set("kind", p_kind)
	p.position = pos
	p.call("_setup")
	return p


static func has_piece(piece: String) -> bool:
	return AtlasMeta.PIECES.has(piece)


static func piece_region(piece: String) -> Rect2:
	var r: Array = AtlasMeta.PIECES[piece]["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


static func piece_feet(piece: String) -> Vector2:
	var f: Array = AtlasMeta.PIECES[piece]["feet"]
	return Vector2(float(f[0]), float(f[1]))


## Rectangle monde où dessiner `piece` pour que son point d'appui tombe sur `at`.
static func piece_dest(piece: String, at: Vector2, k: float = 1.0) -> Rect2:
	var reg := piece_region(piece)
	var s := k / PX_PER_WORLD
	return Rect2(at - piece_feet(piece) * s, reg.size * s)


## Point chaud (lueur) relatif au point d'appui (monde), ou Vector2.INF.
static func piece_glow(piece: String) -> Vector2:
	var e: Dictionary = AtlasMeta.PIECES[piece]
	if not e.has("glow"):
		return Vector2.INF
	var g: Array = e["glow"]
	return (Vector2(float(g[0]), float(g[1])) - piece_feet(piece)) / PX_PER_WORLD


static func get_texture(k: StringName) -> Texture2D:
	if _tex_cache.has(k):
		return _tex_cache[k]
	var tex: AtlasTexture = null
	var piece := "prop_" + String(k)
	if has_piece(piece):
		tex = AtlasTexture.new()
		tex.atlas = ATLAS
		tex.region = piece_region(piece)
	_tex_cache[k] = tex
	return tex


static func def_of(k: StringName) -> Dictionary:
	return DEFS.get(k, {"block": Vector2(24, 12)})


func _setup() -> void:
	var def := def_of(kind)
	var flat: bool = bool(def.get("flat", false))
	z_index = 1 if flat else 10
	var tex := get_texture(kind)
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.name = "Sprite"
		_sprite.texture = tex
		_sprite.centered = false
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_sprite.scale = Vector2.ONE / PX_PER_WORLD
		_sprite.offset = -piece_feet("prop_" + String(kind))
		add_child(_sprite)
	else:
		push_warning("MallProp: pièce absente de l'atlas : %s" % kind)
	var block: Vector2 = def.get("block", Vector2.ZERO)
	if block != Vector2.ZERO:
		body = StaticBody2D.new()
		body.name = "Body"
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = block
		cs.shape = rect
		cs.position = Vector2.ZERO if CENTERED.has(kind) else Vector2(0.0, -block.y * 0.5)
		body.add_child(cs)
		add_child(body)
	set_process(false)
	set_physics_process(false)


## Point de lueur (monde, relatif au nœud), ou Vector2.INF.
func get_glow_offset() -> Vector2:
	return piece_glow("prop_" + String(kind))
