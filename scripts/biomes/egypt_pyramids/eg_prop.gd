extends Node2D
## Décor des Pyramides d'Égypte : sprite 3D peint (Blender, même caméra 3/4 que le héros) pris
## dans l'atlas assets/sprites/egypt_pyramids/atlas.png (pièce prop_<kind>, ombre chaude déjà
## peinte), petite collision couche world si le décor bloque. Origine = point d'appui au sol
## (tri en Y) ; les grands décors sont centrés sur leur emprise. Aucun traitement par image.
## Régénérer : art/blender/egypt_pyramids/build_eg_props.py.

const ATLAS_PATH := "res://assets/sprites/egypt_pyramids/atlas.png"
const META_PATH := "res://assets/sprites/egypt_pyramids/atlas_meta.gd"
const LAYER_WORLD := 1
const PX_PER_WORLD := 2.0

## kind → block (collision au sol, unités monde ; ZERO = traversable), flat (posé au sol),
## glow (rayon de lueur additive), tint (couleur de la lueur).
const DEFS := {
	&"eg_brazier": {"block": Vector2(26, 16), "glow": 90.0, "tint": Color(1.0, 0.62, 0.25)},
	&"eg_statue": {"block": Vector2(36, 22)},
	&"eg_canopic_jars": {"block": Vector2(50, 16)},
	&"eg_sarcophagus_big": {"block": Vector2(110, 40)},
	&"eg_offering_table": {"block": Vector2(100, 36), "glow": 50.0, "tint": Color(1.0, 0.7, 0.3)},
	&"eg_embalming_table": {"block": Vector2(90, 36)},
	&"eg_weapon_rack": {"block": Vector2(54, 16)},
	&"eg_bench": {"block": Vector2(56, 16)},
	&"eg_scroll_shelf": {"block": Vector2(56, 18)},
	&"eg_spikes": {"block": Vector2.ZERO, "flat": true},
	&"eg_rubble": {"block": Vector2.ZERO},
	&"eg_cactus": {"block": Vector2(22, 14)},
	&"eg_bones": {"block": Vector2.ZERO, "flat": true},
	&"eg_tent": {"block": Vector2(110, 90)},
}
const CENTERED := [&"eg_sarcophagus_big", &"eg_offering_table", &"eg_tent"]

static var _tex_cache: Dictionary = {}
static var _atlas: Texture2D = null
static var _pieces: Dictionary = {}
static var _loaded: bool = false

var kind: StringName = &""
var body: StaticBody2D = null
var flipped: bool = false
var _tex: Texture2D = null


static func create(p_kind: StringName, pos: Vector2, shared: StaticBody2D = null, p_flip: bool = false) -> Node2D:
	var p: Node2D = (load("res://scripts/biomes/egypt_pyramids/eg_prop.gd") as GDScript).new()
	p.name = "Prop_%s" % String(p_kind)
	p.set("kind", p_kind)
	p.set("flipped", p_flip)
	p.position = pos
	p.call("_setup", shared)
	return p


static func make_shared_body() -> StaticBody2D:
	var b := StaticBody2D.new()
	b.name = "PropBodies"
	b.collision_layer = LAYER_WORLD
	b.collision_mask = 0
	return b


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if ResourceLoader.exists(ATLAS_PATH):
		_atlas = load(ATLAS_PATH) as Texture2D
	if ResourceLoader.exists(META_PATH):
		var scr := load(META_PATH) as Script
		if scr != null:
			var v: Variant = scr.get_script_constant_map().get("PIECES", {})
			if v is Dictionary:
				_pieces = v


static func atlas() -> Texture2D:
	_load()
	return _atlas


static func pieces() -> Dictionary:
	_load()
	return _pieces


static func has_piece(piece: String) -> bool:
	return pieces().has(piece)


static func piece_region(piece: String) -> Rect2:
	var r: Array = pieces()[piece]["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


static func piece_feet(piece: String) -> Vector2:
	var f: Array = pieces()[piece]["feet"]
	return Vector2(float(f[0]), float(f[1]))


static func piece_dest(piece: String, at: Vector2, k: float = 1.0) -> Rect2:
	var reg := piece_region(piece)
	var s := k / PX_PER_WORLD
	return Rect2(at - piece_feet(piece) * s, reg.size * s)


static func piece_glow(piece: String) -> Vector2:
	var e: Dictionary = pieces()[piece]
	if not e.has("glow"):
		return Vector2.INF
	var g: Array = e["glow"]
	return (Vector2(float(g[0]), float(g[1])) - piece_feet(piece)) / PX_PER_WORLD


static func get_texture(k: StringName) -> Texture2D:
	if _tex_cache.has(k):
		return _tex_cache[k]
	var tex: AtlasTexture = null
	var piece := "prop_" + String(k)
	if has_piece(piece) and atlas() != null:
		tex = AtlasTexture.new()
		tex.atlas = atlas()
		tex.region = piece_region(piece)
	_tex_cache[k] = tex
	return tex


static func def_of(k: StringName) -> Dictionary:
	return DEFS.get(k, {"block": Vector2(24, 12)})


func _setup(shared: StaticBody2D = null) -> void:
	var def := def_of(kind)
	var flat: bool = bool(def.get("flat", false))
	z_index = 1 if flat else 10
	var tex := get_texture(kind)
	if tex != null:
		_tex = tex
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var block: Vector2 = def.get("block", Vector2.ZERO)
	if block != Vector2.ZERO and shared != null:
		body = shared
		var oid := shared.create_shape_owner(self)
		var r0 := RectangleShape2D.new()
		r0.size = block
		shared.shape_owner_add_shape(oid, r0)
		var ctr := Vector2.ZERO if CENTERED.has(kind) else Vector2(0.0, -block.y * 0.5)
		shared.shape_owner_set_transform(oid, Transform2D(0.0, position + ctr - shared.position))
	elif block != Vector2.ZERO:
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


func get_glow_offset() -> Vector2:
	var piece := "prop_" + String(kind)
	return piece_glow(piece) if has_piece(piece) else Vector2(0.0, -20.0)


func _draw() -> void:
	if _tex == null:
		# Repli sans atlas : silhouette simple (bloc de grès) lisible.
		var def := def_of(kind)
		var b: Vector2 = def.get("block", Vector2(24, 12))
		if b == Vector2.ZERO:
			b = Vector2(20, 10)
		draw_rect(Rect2(-b.x * 0.5, -b.y - 14.0, b.x, b.y + 14.0), Color(0.7, 0.54, 0.34))
		draw_rect(Rect2(-b.x * 0.5, -b.y - 14.0, b.x, b.y + 14.0), Color(0.2, 0.1, 0.06), false, 1.5)
		return
	if flipped:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
	var piece := "prop_" + String(kind)
	draw_texture_rect_region(atlas(), piece_dest(piece, Vector2.ZERO), piece_region(piece))
