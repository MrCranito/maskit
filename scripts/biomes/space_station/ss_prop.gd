extends Node2D
## Décor de la Station Orbitale (console, baie de serveurs, navette…) : sprite 3D peint pris
## dans l'atlas unique assets/sprites/space_station/atlas.png (pièce `prop_<kind>`, ombre bleu
## nuit déjà peinte), collision au sol sur la couche world pour les décors bloquants.
## Origine = point d'appui au sol (tri en Y). Aucun traitement par image.
## Régénérer l'atlas : art/blender/space_station/build_props.py.

const ATLAS: Texture2D = preload("res://assets/sprites/space_station/atlas.png")
const AtlasMeta := preload("res://assets/sprites/space_station/atlas_meta.gd")
const LAYER_WORLD := 1
const PX_PER_WORLD := 2.0

## kind → block : taille (unités monde) de la collision au sol (ZERO = traversable) ;
## flat : posé à plat (z 1) ; glow : couleur de la lueur additive (si le décor a un point chaud).
const DEFS := {
	&"console": {"block": Vector2(76, 22), "glow": Color(0.35, 0.85, 1.0)},
	&"server_rack": {"block": Vector2(44, 18), "glow": Color(0.4, 1.0, 0.6)},
	&"bunk_bed": {"block": Vector2(62, 40)},
	&"mess_table": {"block": Vector2(84, 40)},
	&"med_bed": {"block": Vector2(46, 44), "glow": Color(0.45, 1.0, 0.55)},
	&"lab_bench": {"block": Vector2(82, 22), "glow": Color(0.4, 1.0, 0.75)},
	&"specimen_tank": {"block": Vector2(40, 20), "glow": Color(0.35, 1.0, 0.7)},
	&"cargo_stack": {"block": Vector2(58, 22)},
	&"pipe_cluster": {"block": Vector2(60, 16)},
	&"reactor_core": {"block": Vector2(100, 46), "glow": Color(0.45, 0.95, 1.0)},
	&"holo_table": {"block": Vector2(46, 22), "glow": Color(0.45, 0.9, 1.0)},
	&"captain_chair": {"block": Vector2(36, 18)},
	&"weapon_rack": {"block": Vector2(70, 14), "glow": Color(1.0, 0.45, 0.2)},
	&"plant_bed": {"block": Vector2(66, 22), "glow": Color(0.8, 0.45, 1.0)},
	&"vending_machine": {"block": Vector2(48, 20), "glow": Color(0.7, 0.95, 1.0)},
	&"coolant_tank": {"block": Vector2(44, 20), "glow": Color(0.4, 0.85, 1.0)},
	&"power_node": {"block": Vector2(56, 22), "glow": Color(1.0, 0.6, 0.25)},
	&"escape_pod": {"block": Vector2(50, 22), "glow": Color(0.45, 1.0, 0.6)},
	&"floor_cables": {"block": Vector2.ZERO, "flat": true},
	&"warning_beacon": {"block": Vector2(14, 10), "glow": Color(1.0, 0.2, 0.15), "alarm": true},
	&"shuttle": {"block": Vector2(250, 96), "glow": Color(0.35, 0.65, 1.0)},
	&"workbench": {"block": Vector2(80, 22), "glow": Color(1.0, 0.72, 0.35)},
	&"fuel_drums": {"block": Vector2(50, 22)},
}

static var _tex_cache: Dictionary = {}

var kind: StringName = &""
var is_placeholder: bool = false
var body: StaticBody2D = null


static func create(p_kind: StringName, pos: Vector2) -> Node2D:
	var p: Node2D = (load("res://scripts/biomes/space_station/ss_prop.gd") as GDScript).new()
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


## Point chaud (unités monde, relatif au point d'appui) ou Vector2.INF.
static func piece_glow(piece: String) -> Vector2:
	var e: Dictionary = AtlasMeta.PIECES[piece]
	if not e.has("glow"):
		return Vector2.INF
	var g: Array = e["glow"]
	return (Vector2(float(g[0]), float(g[1])) - piece_feet(piece)) / PX_PER_WORLD


static func piece_dest(piece: String, at: Vector2, scale_k: float = 1.0) -> Rect2:
	var reg := piece_region(piece)
	var s := scale_k / PX_PER_WORLD
	return Rect2(at - piece_feet(piece) * s, reg.size * s)


static func is_known_kind(k: StringName) -> bool:
	return DEFS.has(k) and has_piece("prop_" + String(k))


static func get_texture(k: StringName) -> Texture2D:
	if _tex_cache.has(k):
		return _tex_cache[k]
	var tex: AtlasTexture = null
	if has_piece("prop_" + String(k)):
		tex = AtlasTexture.new()
		tex.atlas = ATLAS
		tex.region = piece_region("prop_" + String(k))
	_tex_cache[k] = tex
	return tex


func is_blocking() -> bool:
	return body != null


## Lueur : [décalage monde, couleur, alarme ?] ou [] si aucune.
func get_glow() -> Array:
	if is_placeholder or not DEFS.has(kind):
		return []
	var d: Dictionary = DEFS[kind]
	if not d.has("glow"):
		return []
	var off := piece_glow("prop_" + String(kind))
	if off == Vector2.INF:
		return []
	return [off, d["glow"], bool(d.get("alarm", false))]


func _setup() -> void:
	set_process(false)
	var tex: Texture2D = get_texture(kind) if DEFS.has(kind) else null
	if tex == null:
		is_placeholder = true
		push_warning("SpaceProp: décor inconnu « %s »." % String(kind))
		z_index = 10
		return
	var def: Dictionary = DEFS[kind]
	z_index = 1 if bool(def.get("flat", false)) else 10
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.scale = Vector2.ONE / PX_PER_WORLD
	spr.offset = -piece_feet("prop_" + String(kind))
	add_child(spr)
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
		cs.position = Vector2(0.0, -block.y * 0.5)
		body.add_child(cs)
		add_child(body)


func _draw() -> void:
	if is_placeholder:
		draw_rect(Rect2(-14, -26, 28, 26), Color(0.4, 0.45, 0.55))
		draw_rect(Rect2(-14, -26, 28, 26), Color(0.05, 0.05, 0.1), false, 2.0)
