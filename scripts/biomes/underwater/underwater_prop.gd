class_name UnderwaterProp
extends Node2D
## Décor de la station sous-marine (console, aquarium, pompe, corail…). Sprite 3D peint
## (Blender, même caméra 3/4 que le héros) pris dans l'atlas unique
## `assets/sprites/underwater/atlas.png` (pièce `prop_<kind>`, ombre bleu nuit peinte dedans),
## petite collision couche world pour les décors qui bloquent. Origine = point d'appui au sol.
## Aucun traitement par image. Régénérer l'atlas : art/blender/underwater/uw_props.py.

const ATLAS: Texture2D = preload("res://assets/sprites/underwater/atlas.png")
const AtlasMeta := preload("res://assets/sprites/underwater/atlas_meta.gd")
const LAYER_WORLD := 1
## Densité de l'atlas : 2 px par unité monde.
const PX_PER_WORLD := 2.0
const TS := float(FloorLayout.TILE_SIZE)

## kind → définition :
##  block : taille (unités monde) de la collision au sol (Vector2.ZERO = traversable)
##  block_offset : décalage du centre de la collision (défaut : juste au-dessus des pieds)
##  glow : couleur de la lueur additive (point chaud de l'atlas), glow_r : rayon
const DEFS := {
	&"moon_pool": {"block": Vector2(176, 104), "block_offset": Vector2(0, -48), "glow": Color(0.2, 0.6, 0.75), "glow_r": 130.0},
	&"console": {"block": Vector2(52, 18), "glow": Color(0.35, 0.95, 1.0), "glow_r": 60.0},
	&"server_rack": {"block": Vector2(34, 16), "glow": Color(0.4, 1.0, 0.55), "glow_r": 40.0},
	&"bunk_bed": {"block": Vector2(66, 28)},
	&"mess_table": {"block": Vector2(64, 40)},
	&"med_bed": {"block": Vector2(66, 26), "glow": Color(0.35, 0.95, 1.0), "glow_r": 36.0},
	&"aquarium_tank": {"block": Vector2(54, 20), "glow": Color(0.3, 0.85, 0.95), "glow_r": 80.0},
	&"specimen_tank": {"block": Vector2(28, 18), "glow": Color(0.45, 1.0, 0.55), "glow_r": 80.0},
	&"lab_bench": {"block": Vector2(58, 22), "glow": Color(0.6, 1.0, 0.75), "glow_r": 40.0},
	&"pipes": {"block": Vector2(50, 12)},
	&"pump": {"block": Vector2(60, 24)},
	&"valve_wheel": {"block": Vector2(16, 10)},
	&"oxygen_rack": {"block": Vector2(46, 12)},
	&"diving_suit": {"block": Vector2(20, 12)},
	&"coral_cluster": {"block": Vector2(36, 14)},
	&"kelp": {"block": Vector2.ZERO},
	&"cable_spool": {"block": Vector2(30, 16)},
	&"crate_stack": {"block": Vector2(50, 18)},
	&"lamp_post": {"block": Vector2(10, 8), "glow": Color(1.0, 0.62, 0.26), "glow_r": 120.0},
	&"alarm_light": {"block": Vector2(10, 8), "glow": Color(1.0, 0.18, 0.12), "glow_r": 100.0},
	&"generator": {"block": Vector2(90, 30)},
	&"hydro_planter": {"block": Vector2(60, 24), "glow": Color(0.8, 0.45, 1.0), "glow_r": 80.0},
	&"desk": {"block": Vector2(56, 20), "glow": Color(0.35, 0.95, 1.0), "glow_r": 44.0},
}

static var _tex_cache: Dictionary = {}

var kind: StringName = &""
var is_placeholder: bool = false
var body: StaticBody2D = null
var _def: Dictionary = {}


static func create(p_kind: StringName, pos: Vector2) -> UnderwaterProp:
	var p := UnderwaterProp.new()
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


static func piece_region(piece: String) -> Rect2:
	var r: Array = AtlasMeta.PIECES[piece]["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


static func piece_feet(piece: String) -> Vector2:
	var f: Array = AtlasMeta.PIECES[piece]["feet"]
	return Vector2(float(f[0]), float(f[1]))


## Point chaud (unités monde, relatif au point d'appui) ou Vector2.INF.
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


func is_blocking() -> bool:
	return body != null


func _setup() -> void:
	set_process(false)
	var tex: Texture2D = get_texture(kind) if DEFS.has(kind) else null
	if tex == null:
		is_placeholder = true
		push_warning("UnderwaterProp: décor inconnu « %s »." % String(kind))
		_def = {}
		z_index = 10
		return
	_def = DEFS[kind]
	z_index = 1 if kind == &"moon_pool" else 10
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = tex
	sprite.centered = false
	sprite.scale = Vector2.ONE / PX_PER_WORLD
	sprite.offset = -piece_feet("prop_" + String(kind))
	add_child(sprite)
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
		cs.position = _def.get("block_offset", Vector2(0.0, -block.y * 0.5))
		body.add_child(cs)
		add_child(body)


## Lueur du décor : [position monde relative, rayon, couleur] ou [] si aucune.
func get_glow() -> Array:
	if is_placeholder or not _def.has("glow"):
		return []
	var off := piece_glow("prop_" + String(kind))
	if off == Vector2.INF:
		return []
	return [off, float(_def.get("glow_r", 60.0)), _def["glow"]]


func _draw() -> void:
	if is_placeholder:
		draw_rect(Rect2(-14.0, -26.0, 28.0, 26.0), Color(0.4, 0.5, 0.56))
		draw_rect(Rect2(-14.0, -26.0, 28.0, 26.0), Color(0.05, 0.07, 0.1), false, 2.0)
