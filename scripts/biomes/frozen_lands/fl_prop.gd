extends Node2D
## Décor des Terres gelées (caisses militaires, cuves cryo, hélicoptère, cristaux…) : en jeu la
## carte est pré-rendue dans Blender (tools/prerender/fl_scene.py), le décor n'a donc qu'une
## COLLISION au sol (couche world) et un dessin 2D de secours (silhouette simple dans la palette
## du biome) utilisé seulement sans fond pré-calculé. Origine = point d'appui au sol (tri en Y).
## Aucun traitement par image.

const LAYER_WORLD := 1
const TS := 64.0

## kind → block : taille (unités monde) de la collision au sol (ZERO = traversable) ; fp :
## empreinte en cases (grands décors) ; col : couleur de secours ; h : hauteur dessinée (px).
const DEFS := {
	&"fl_lab_bench": {"block": Vector2(82, 22), "col": Color(0.8, 0.84, 0.9), "h": 30.0},
	&"fl_cryo_tank": {"block": Vector2(40, 20), "col": Color(0.45, 0.85, 1.0), "h": 60.0},
	&"fl_console": {"block": Vector2(76, 22), "col": Color(0.3, 0.34, 0.4), "h": 34.0},
	&"fl_bunk": {"block": Vector2(62, 40), "col": Color(0.3, 0.4, 0.3), "h": 24.0},
	&"fl_stove": {"block": Vector2(30, 24), "col": Color(0.2, 0.2, 0.22), "h": 40.0},
	&"fl_table": {"block": Vector2(84, 40), "col": Color(0.5, 0.42, 0.3), "h": 26.0},
	&"fl_med_bed": {"block": Vector2(46, 44), "col": Color(0.85, 0.88, 0.92), "h": 24.0},
	&"fl_map_table": {"block": Vector2(70, 40), "col": Color(0.35, 0.4, 0.5), "h": 28.0},
	&"fl_radio_rack": {"block": Vector2(44, 18), "col": Color(0.25, 0.28, 0.32), "h": 64.0},
	&"fl_crate_stack": {"block": Vector2(58, 22), "col": Color(0.4, 0.45, 0.32), "h": 44.0},
	&"fl_barrels": {"block": Vector2(50, 22), "col": Color(0.75, 0.18, 0.15), "h": 40.0},
	&"fl_sandbags": {"block": Vector2(60, 20), "col": Color(0.55, 0.5, 0.38), "h": 22.0},
	&"fl_weapon_rack": {"block": Vector2(70, 14), "col": Color(0.25, 0.27, 0.3), "h": 64.0},
	&"fl_generator": {"block": Vector2(60, 30), "col": Color(0.6, 0.55, 0.2), "h": 46.0},
	&"fl_pipes": {"block": Vector2(60, 16), "col": Color(0.45, 0.48, 0.52), "h": 70.0},
	&"fl_workbench": {"block": Vector2(80, 22), "col": Color(0.4, 0.36, 0.3), "h": 32.0},
	&"fl_tool_cart": {"block": Vector2(40, 24), "col": Color(0.7, 0.25, 0.15), "h": 36.0},
	&"fl_telescope": {"block": Vector2(36, 36), "col": Color(0.85, 0.88, 0.92), "h": 70.0},
	&"fl_antenna": {"block": Vector2(24, 24), "col": Color(0.5, 0.55, 0.6), "h": 120.0},
	&"fl_helicopter": {"block": Vector2(260, 120), "fp": Vector2i(5, 3), "col": Color(0.3, 0.36, 0.3), "h": 90.0},
	&"fl_snowcat": {"block": Vector2(150, 80), "fp": Vector2i(3, 2), "col": Color(0.85, 0.3, 0.15), "h": 70.0},
	&"fl_crystal_core": {"block": Vector2(130, 130), "fp": Vector2i(3, 3), "col": Color(0.45, 0.85, 1.0), "h": 150.0, "glow": Color(0.4, 0.85, 1.0)},
}

var kind: StringName = &""
var is_placeholder: bool = false
var body: StaticBody2D = null
var flipped: bool = false
var _size: Vector2i = Vector2i.ONE


## `shared` : corps statique commun de l'étage (forme ajoutée par shape owner).
static func create(p_kind: StringName, pos: Vector2, shared: StaticBody2D = null, p_flip: bool = false, p_size: Vector2i = Vector2i.ONE) -> Node2D:
	var p: Node2D = (load("res://scripts/biomes/frozen_lands/fl_prop.gd") as GDScript).new()
	p.name = "Prop_%s" % String(p_kind)
	p.set("kind", p_kind)
	p.set("flipped", p_flip)
	p.set("_size", p_size)
	p.position = pos
	p.call("_setup", shared)
	return p


static func make_shared_body() -> StaticBody2D:
	var b := StaticBody2D.new()
	b.name = "PropBodies"
	b.collision_layer = LAYER_WORLD
	b.collision_mask = 0
	return b


static func is_known_kind(k: StringName) -> bool:
	return DEFS.has(k)


func is_blocking() -> bool:
	return body != null


## Lueur : [décalage monde, couleur, alarme ?] ou [].
func get_glow() -> Array:
	if not DEFS.has(kind) or not (DEFS[kind] as Dictionary).has("glow"):
		return []
	var d: Dictionary = DEFS[kind]
	return [Vector2(0.0, -float(d.get("h", 30.0)) * 0.4), d["glow"], false]


func _setup(shared: StaticBody2D = null) -> void:
	set_process(false)
	set_physics_process(false)
	if not DEFS.has(kind):
		is_placeholder = true
		push_warning("FrozenProp: décor inconnu « %s »." % String(kind))
		z_index = 10
		return
	var def: Dictionary = DEFS[kind]
	z_index = 10
	var block: Vector2 = def.get("block", Vector2.ZERO)
	if block == Vector2.ZERO:
		return
	# Grands décors : l'empreinte (cases) centrée sur la case d'appui (rangée du bas).
	var center := Vector2(0.0, -block.y * 0.5)
	if _size != Vector2i.ONE:
		center = Vector2(0.0, -float(_size.y) * TS * 0.5 + TS * 0.25)
	if shared != null:
		body = shared
		var oid := shared.create_shape_owner(self)
		var r0 := RectangleShape2D.new()
		r0.size = block
		shared.shape_owner_add_shape(oid, r0)
		shared.shape_owner_set_transform(oid, Transform2D(0.0, position + center - shared.position))
	else:
		body = StaticBody2D.new()
		body.name = "Body"
		body.collision_layer = LAYER_WORLD
		body.collision_mask = 0
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = block
		cs.shape = rect
		cs.position = center
		body.add_child(cs)
		add_child(body)


## Dessin de secours (sans fond pré-rendu) : boîte dans la palette, ombre bleu nuit.
func _draw() -> void:
	if is_placeholder:
		draw_rect(Rect2(-14, -26, 28, 26), Color(0.4, 0.45, 0.55))
		draw_rect(Rect2(-14, -26, 28, 26), Color(0.05, 0.05, 0.1), false, 2.0)
		return
	var def: Dictionary = DEFS[kind]
	var block: Vector2 = def.get("block", Vector2(32, 16))
	var h: float = float(def.get("h", 30.0))
	var col: Color = def.get("col", Color(0.5, 0.5, 0.5))
	var w := maxf(block.x, 20.0)
	var dpt := maxf(block.y, 12.0)
	draw_rect(Rect2(-w * 0.5 + 6.0, -dpt * 0.5 + 4.0, w, dpt), Color(0.06, 0.1, 0.22, 0.45))
	draw_rect(Rect2(-w * 0.5, -dpt * 0.5, w, dpt), col.darkened(0.35))
	draw_rect(Rect2(-w * 0.5, -dpt * 0.5 - h, w, h), col)
	draw_rect(Rect2(-w * 0.5, -dpt * 0.5 - h, w, 4.0), col.lightened(0.3))
	draw_rect(Rect2(-w * 0.5, -dpt * 0.5 - h, w, h + dpt), Color(0.04, 0.05, 0.09), false, 1.5)
