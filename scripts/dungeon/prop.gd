class_name WorldProp
extends Node2D
## Décor du monde (cactus, chariot, bar du saloon…). Sprite SVG
## `res://assets/sprites/far_west/props/<kind>.svg`, ombre bleu nuit portée
## vers le bas-droite, petite collision couche world pour les décors qui bloquent.
## Origine du nœud = point d'appui au sol (tri en Y). kind inconnu : petit
## placeholder (caisse) + push_warning, jamais d'erreur.

const PROPS_DIR := "res://assets/sprites/far_west/props/"
const LAYER_WORLD := 1
## 2 unités SVG = 1 px monde (SVG importés à svg/scale 1 → texture 2x, nette au zoom 1.3).
const SVG_TO_WORLD := 0.5
const SHADOW_COLOR := Color(0.07, 0.1, 0.25, 0.4)
const OUTLINE := Color(0.12, 0.07, 0.09)

## kind → définition :
##  block : taille (px monde) de la collision au sol (Vector2.ZERO = traversable)
##  flat  : posé à plat au sol (z 1, non trié en Y, pas d'ombre)
##  foot  : marge (px SVG) entre le bas de l'image et le point d'appui
##  shadow: demi-largeur de l'ombre (px monde)
##  glow  : lueur chaude (lanterne)
const DEFS := {
	&"cactus": {"block": Vector2(22, 12), "foot": 4.0, "shadow": 20.0},
	&"hitching_post": {"block": Vector2.ZERO, "foot": 4.0, "shadow": 34.0},
	&"water_trough": {"block": Vector2(56, 14), "foot": 2.0, "shadow": 30.0},
	&"wagon": {"block": Vector2(110, 26), "foot": 4.0, "shadow": 64.0},
	&"wagon_wheel": {"block": Vector2.ZERO, "foot": 4.0, "shadow": 18.0},
	&"barrel": {"block": Vector2(24, 12), "foot": 2.0, "shadow": 15.0},
	&"saloon_bar": {"block": Vector2(144, 22), "foot": 6.0, "shadow": 72.0},
	&"piano": {"block": Vector2(64, 16), "foot": 4.0, "shadow": 34.0},
	&"poker_table": {"block": Vector2(48, 18), "foot": 6.0, "shadow": 26.0},
	&"bed": {"block": Vector2(46, 40), "foot": 2.0, "shadow": 26.0},
	&"desk": {"block": Vector2(60, 18), "foot": 4.0, "shadow": 32.0},
	&"jail_bars": {"block": Vector2(64, 10), "foot": 2.0, "shadow": 32.0},
	&"rail_track": {"block": Vector2.ZERO, "flat": true},
	&"mine_cart": {"block": Vector2(44, 16), "foot": 2.0, "shadow": 24.0},
	&"lantern": {"block": Vector2.ZERO, "foot": 4.0, "shadow": 8.0, "glow": true},
	&"wanted_poster": {"block": Vector2(36, 8), "foot": 2.0, "shadow": 18.0},
	&"bench": {"block": Vector2(52, 12), "foot": 2.0, "shadow": 28.0},
	&"hay_bale": {"block": Vector2(40, 18), "foot": 4.0, "shadow": 22.0},
	&"safe": {"block": Vector2(36, 18), "foot": 2.0, "shadow": 20.0},
	&"shelf": {"block": Vector2(56, 14), "foot": 4.0, "shadow": 30.0},
	&"counter": {"block": Vector2(114, 20), "foot": 4.0, "shadow": 60.0},
	&"tumbleweed": {"block": Vector2.ZERO, "foot": 2.0, "shadow": 12.0},
	&"pew": {"block": Vector2(94, 14), "foot": 2.0, "shadow": 50.0},
	&"ore_pile": {"block": Vector2(30, 12), "foot": 4.0, "shadow": 18.0},
	&"support_beam": {"block": Vector2(14, 10), "foot": 2.0, "shadow": 12.0},
	&"altar": {"block": Vector2(64, 18), "foot": 4.0, "shadow": 34.0},
	&"water_tower": {"block": Vector2(76, 30), "foot": 4.0, "shadow": 46.0},
}

static var _tex_cache: Dictionary = {}

var kind: StringName = &""
var is_placeholder: bool = false
var body: StaticBody2D = null
var _def: Dictionary = {}
var _sprite: Sprite2D = null
var _glow_time: float = 0.0


## Crée un décor posé au sol à `pos` (monde). Le décor bloque si sa définition le prévoit.
static func create(p_kind: StringName, pos: Vector2) -> WorldProp:
	var p := WorldProp.new()
	p.name = "Prop_%s" % String(p_kind)
	p.kind = p_kind
	p.position = pos
	p._setup()
	return p


static func is_known_kind(k: StringName) -> bool:
	return DEFS.has(k)


static func get_texture(k: StringName) -> Texture2D:
	if _tex_cache.has(k):
		return _tex_cache[k]
	var path := PROPS_DIR + String(k) + ".svg"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_tex_cache[k] = tex
	return tex


func is_blocking() -> bool:
	return body != null


func _setup() -> void:
	var tex: Texture2D = get_texture(kind) if DEFS.has(kind) else null
	if not DEFS.has(kind) or tex == null:
		is_placeholder = true
		push_warning("WorldProp: décor inconnu « %s », placeholder." % String(kind))
		_def = {"block": Vector2.ZERO, "shadow": 14.0}
		z_index = 10
		return
	_def = DEFS[kind]
	var flat: bool = bool(_def.get("flat", false))
	z_index = 1 if flat else 10
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = tex
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sprite.scale = Vector2.ONE * SVG_TO_WORLD
	_sprite.centered = true
	if not flat:
		# Pied (bas-centre de l'image, moins la marge) à l'origine.
		var foot: float = float(_def.get("foot", 0.0))
		_sprite.offset = Vector2(0.0, -tex.get_height() * 0.5 + foot)
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
	if bool(_def.get("glow", false)):
		set_process(true)
	else:
		set_process(false)


func _process(delta: float) -> void:
	_glow_time += delta
	queue_redraw()


func _draw() -> void:
	if bool(_def.get("flat", false)):
		return
	var r: float = float(_def.get("shadow", 16.0))
	# Ombre portée bleu nuit vers le bas-droite (soleil couchant à l'ouest).
	draw_set_transform(Vector2(r * 0.35, 3.0), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, r, SHADOW_COLOR)
	draw_circle(Vector2.ZERO, r * 0.7, Color(SHADOW_COLOR, SHADOW_COLOR.a * 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if bool(_def.get("glow", false)):
		var f := 0.85 + 0.15 * sin(_glow_time * 7.0) * sin(_glow_time * 3.1)
		var c := Vector2(0.0, -18.0)
		draw_circle(c, 46.0 * f, Color(1.0, 0.62, 0.25, 0.08))
		draw_circle(c, 30.0 * f, Color(1.0, 0.7, 0.3, 0.12))
		draw_circle(c, 16.0 * f, Color(1.0, 0.85, 0.5, 0.18))
	if is_placeholder:
		var box := Rect2(-14.0, -26.0, 28.0, 26.0)
		draw_rect(box, Color(0.62, 0.42, 0.26))
		draw_rect(Rect2(box.position, Vector2(28.0, 8.0)), Color(0.8, 0.6, 0.38))
		draw_line(box.position + Vector2(0, 8), box.end, OUTLINE, 1.5)
		draw_rect(box, OUTLINE, false, 2.0)
