class_name WorldProp
extends Node2D
## Décor du monde (cactus, chariot, bar du saloon…). Sprite 3D peint (Blender, même
## caméra 3/4 que le héros) pris dans l'atlas unique `assets/sprites/far_west/atlas.png`
## (pièce `prop_<kind>`, ombre bleu nuit déjà peinte dedans), petite collision couche
## world pour les décors qui bloquent. Origine du nœud = point d'appui au sol (tri en Y).
## Aucun traitement par image (set_process(false)). kind inconnu : placeholder + warning.
## Régénérer l'atlas : art/blender/build_props.py (voir son en-tête).

const ATLAS: Texture2D = preload("res://assets/sprites/far_west/atlas.png")
const AtlasMeta := preload("res://assets/sprites/far_west/atlas_meta.gd")
const LAYER_WORLD := 1
## Densité de l'atlas : 2 px par unité monde.
const PX_PER_WORLD := 2.0
const OUTLINE := Color(0.12, 0.07, 0.09)
## Lueur additive (lanternes, bougies) : couleur chaude, rayon (unités monde).
const GLOW_COLOR := Color(1.0, 0.62, 0.28, 0.55)
const GLOW_RADIUS := 70.0

## kind → définition :
##  block : taille (unités monde) de la collision au sol (Vector2.ZERO = traversable)
##  flat  : posé à plat au sol (z 1, non trié en Y)
const DEFS := {
	&"cactus": {"block": Vector2(22, 12)},
	&"hitching_post": {"block": Vector2.ZERO},
	&"water_trough": {"block": Vector2(56, 14)},
	&"wagon": {"block": Vector2(104, 26)},
	&"wagon_wheel": {"block": Vector2.ZERO},
	&"barrel": {"block": Vector2(24, 12)},
	&"saloon_bar": {"block": Vector2(144, 22)},
	&"piano": {"block": Vector2(64, 16)},
	&"poker_table": {"block": Vector2(48, 18)},
	&"bed": {"block": Vector2(46, 40)},
	&"desk": {"block": Vector2(60, 18)},
	&"jail_bars": {"block": Vector2(64, 10)},
	&"rail_track": {"block": Vector2.ZERO, "flat": true},
	&"mine_cart": {"block": Vector2(44, 16)},
	&"lantern": {"block": Vector2.ZERO},
	&"wanted_poster": {"block": Vector2(36, 8)},
	&"bench": {"block": Vector2(52, 12)},
	&"hay_bale": {"block": Vector2(40, 18)},
	&"safe": {"block": Vector2(36, 18)},
	&"shelf": {"block": Vector2(56, 14)},
	&"counter": {"block": Vector2(114, 20)},
	&"tumbleweed": {"block": Vector2.ZERO},
	&"pew": {"block": Vector2(90, 14)},
	&"ore_pile": {"block": Vector2(30, 12)},
	&"support_beam": {"block": Vector2(14, 10)},
	&"altar": {"block": Vector2(64, 18)},
	&"water_tower": {"block": Vector2(76, 30)},
}

static var _tex_cache: Dictionary = {}
static var _glow_material: CanvasItemMaterial = null

var kind: StringName = &""
var is_placeholder: bool = false
var body: StaticBody2D = null
var _def: Dictionary = {}
var _sprite: Sprite2D = null


## Crée un décor posé au sol à `pos` (monde). Le décor bloque si sa définition le prévoit.
static func create(p_kind: StringName, pos: Vector2) -> WorldProp:
	var p := WorldProp.new()
	p.name = "Prop_%s" % String(p_kind)
	p.kind = p_kind
	p.position = pos
	p._setup()
	return p


static func is_known_kind(k: StringName) -> bool:
	return DEFS.has(k) and has_piece("prop_" + String(k))


# --- Atlas ------------------------------------------------------------------------

static func has_piece(piece: String) -> bool:
	return AtlasMeta.PIECES.has(piece)


## Région (px) d'une pièce de l'atlas.
static func piece_region(piece: String) -> Rect2:
	var r: Array = AtlasMeta.PIECES[piece]["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## Point d'appui (px, depuis le coin de la région).
static func piece_feet(piece: String) -> Vector2:
	var f: Array = AtlasMeta.PIECES[piece]["feet"]
	return Vector2(float(f[0]), float(f[1]))


## Point chaud (lueur) en unités monde relatif au point d'appui, ou Vector2.INF.
static func piece_glow(piece: String) -> Vector2:
	var e: Dictionary = AtlasMeta.PIECES[piece]
	if not e.has("glow"):
		return Vector2.INF
	var g: Array = e["glow"]
	return (Vector2(float(g[0]), float(g[1])) - piece_feet(piece)) / PX_PER_WORLD


## Rectangle monde où dessiner la pièce pour que son point d'appui tombe sur `at`.
static func piece_dest(piece: String, at: Vector2, scale_k: float = 1.0) -> Rect2:
	var reg := piece_region(piece)
	var s := scale_k / PX_PER_WORLD
	return Rect2(at - piece_feet(piece) * s, reg.size * s)


## Texture (AtlasTexture partagée) d'un décor, ou null si inconnu.
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


## Matériau additif partagé des lueurs précalculées (une seule instance).
static func glow_material() -> CanvasItemMaterial:
	if _glow_material == null:
		_glow_material = CanvasItemMaterial.new()
		_glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _glow_material


func is_blocking() -> bool:
	return body != null


func _setup() -> void:
	set_process(false)
	var tex: Texture2D = get_texture(kind) if DEFS.has(kind) else null
	if not DEFS.has(kind) or tex == null:
		is_placeholder = true
		push_warning("WorldProp: décor inconnu « %s », placeholder." % String(kind))
		_def = {"block": Vector2.ZERO}
		z_index = 10
		return
	_def = DEFS[kind]
	var flat: bool = bool(_def.get("flat", false))
	z_index = 1 if flat else 10
	var piece := "prop_" + String(kind)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = tex
	_sprite.centered = false
	_sprite.scale = Vector2.ONE / PX_PER_WORLD
	_sprite.offset = -piece_feet(piece)
	add_child(_sprite)
	var block: Vector2 = _def.get("block", Vector2.ZERO)
	if block != Vector2.ZERO:
		body = StaticBody2D.new()
		body.name = "Body"
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = block
		cs.shape = rect
		cs.position = Vector2(0.0, -block.y * 0.5)
		body.add_child(cs)
		add_child(body)


## Position monde (relative au décor) de sa source de lumière, ou Vector2.INF.
func get_glow_offset() -> Vector2:
	if is_placeholder:
		return Vector2.INF
	return piece_glow("prop_" + String(kind))


func _draw() -> void:
	if is_placeholder:
		var box := Rect2(-14.0, -26.0, 28.0, 26.0)
		draw_rect(box, Color(0.62, 0.42, 0.26))
		draw_rect(Rect2(box.position, Vector2(28.0, 8.0)), Color(0.8, 0.6, 0.38))
		draw_line(box.position + Vector2(0, 8), box.end, OUTLINE, 1.5)
		draw_rect(box, OUTLINE, false, 2.0)
