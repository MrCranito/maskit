class_name LobbyHero
extends Node2D
## Héros posé dans le camp du menu principal : une pose fixe haute résolution par skin
## (art/blender/build_menu_hero.py → assets/ui/menu/hero/<skin>.png, ~815 px de héros : net sur
## Retina) animée en code par une idle procédurale continue (respiration + léger balancement) : fluide à toutes les fréquences d'image, une seule
## texture par skin. Ombre au sol, réaction au changement de skin (écrasement, éclair, poussière).
## Origine du nœud = pieds. `height_px` = hauteur visible voulue (px de l'espace parent).
## Coût : une mise à jour de transformée par image (aucun redessin, aucune allocation).

const DIR := "res://assets/ui/menu/hero/"
const META_PATH := DIR + "hero_menu.json"
const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")
const SMOKE_PATH := "res://assets/ui/menu/lobby/smoke.png"
## Période (s) d'un cycle complet de l'idle : deux respirations, un balancement.
const CYCLE := 6.4

## Corps animé (porte le sprite), pivot aux pieds.
var body: Node2D = null
var sprite: Sprite2D = null
var shadow: Sprite2D = null
## Skin affiché (null = apparence par défaut).
var skin: SkinData = null
## Id de la texture utilisée (« default », « gign »…).
var sheet_id: String = ""
var height_px: float = 400.0:
	set(v):
		height_px = v
		_apply_scale()
## Phase de l'idle (0..1, boucle parfaite).
var phase: float = 0.0
## Amplitude de l'idle (0 = immobile, tests/captures).
var idle_amount: float = 1.0

var _meta: Dictionary = {}
var _base_scale: Vector2 = Vector2.ONE
var _react_tween: Tween = null
var _follow_profile: bool = true
var _pop: Vector2 = Vector2.ONE
static var _tex_cache: Dictionary = {}


func _init(follow_profile: bool = true) -> void:
	_follow_profile = follow_profile


func _ready() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH)) if FileAccess.file_exists(META_PATH) else null
	_meta = d if d is Dictionary else {}
	shadow = Sprite2D.new()
	shadow.texture = GLOW
	shadow.modulate = Color(0.03, 0.02, 0.08, 0.55)
	add_child(shadow)
	body = Node2D.new()
	add_child(body)
	sprite = Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	body.add_child(sprite)
	if _follow_profile:
		Profile.changed.connect(_on_profile_changed)
		set_skin(HeroSkin.current(), false)
	else:
		set_skin(skin, false)
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	set_process(true)


## Affiche ce skin ; `animate` : petite réaction (écrasement, éclair, bouffée de poussière).
func set_skin(s: SkinData, animate: bool = true) -> void:
	skin = s
	if sprite == null:
		return
	sheet_id = sheet_for(s)
	sprite.texture = _texture(sheet_id)
	sprite.material = HeroSkin.material_for(s) if not has_sheet(s) else null
	sprite.position = -_feet()
	_apply_scale()
	if animate and is_inside_tree():
		_react()


## Id de texture pour ce skin : « char_gign » → « gign » ; repli « default ».
static func sheet_for(s: SkinData) -> String:
	if s == null:
		return "default"
	var id := String(s.id).trim_prefix("char_")
	return id if ResourceLoader.exists(DIR + id + ".png") else "default"


static func has_sheet(s: SkinData) -> bool:
	return s == null or ResourceLoader.exists(DIR + String(s.id).trim_prefix("char_") + ".png")


## Compatibilité (tests, captures) : l'idle est toujours jouée.
func get_current_animation() -> StringName:
	return &"idle" if sprite != null and sprite.texture != null else &""


func _process(delta: float) -> void:
	phase = fmod(phase + delta / CYCLE, 1.0)
	_apply_idle()


## Idle procédurale : respiration (2 par cycle) qui gonfle le buste depuis les pieds, léger
## balancement latéral (1 par cycle) en rotation + cisaillement, ombre qui suit.
func _apply_idle() -> void:
	if body == null:
		return
	var t: float = phase * TAU
	var a: float = idle_amount
	var breath: float = sin(t * 2.0) * a
	var sway: float = sin(t + 0.6) * a
	body.scale = _pop * Vector2(1.0 - 0.006 * breath, 1.0 + 0.014 * breath)
	body.rotation = 0.010 * sway
	body.skew = -0.012 * sway
	shadow.scale = _shadow_scale() * Vector2(1.0 + 0.02 * breath, 1.0)


func _on_profile_changed() -> void:
	var cur := HeroSkin.current()
	var cur_id: StringName = cur.id if cur != null else &""
	var old_id: StringName = skin.id if skin != null else &""
	if cur_id != old_id:
		set_skin(cur, true)


func _feet() -> Vector2:
	var f: Variant = _meta.get("feet", [360, 840])
	return Vector2(float(f[0]), float(f[1]))


func _hero_px() -> float:
	return float(_meta.get("hero_px", 815))


func _shadow_scale() -> Vector2:
	var hp: float = _hero_px()
	return Vector2(hp * 0.62 / 256.0, hp * 0.12 / 256.0)


func _apply_scale() -> void:
	if sprite == null:
		return
	var k: float = height_px / maxf(_hero_px(), 1.0)
	_base_scale = Vector2(k, k)
	scale = _base_scale
	shadow.scale = _shadow_scale()


func _texture(id: String) -> Texture2D:
	if _tex_cache.has(id):
		return _tex_cache[id] as Texture2D
	var tex := load(DIR + id + ".png") as Texture2D
	if tex != null:
		_tex_cache[id] = tex
	return tex


func _set_pop(v: Vector2) -> void:
	_pop = v
	_apply_idle()


func _react() -> void:
	if _react_tween != null and _react_tween.is_valid():
		_react_tween.kill()
	var tw := create_tween()
	_react_tween = tw
	tw.tween_method(_set_pop, Vector2.ONE, Vector2(1.08, 0.9), 0.07)
	tw.tween_method(_set_pop, Vector2(1.08, 0.9), Vector2(0.96, 1.07), 0.1)
	tw.tween_method(_set_pop, Vector2(0.96, 1.07), Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sprite.modulate = Color(2.2, 2.0, 1.8)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.35)
	# bouffée de poussière au sol
	if ResourceLoader.exists(SMOKE_PATH):
		var w: float = _hero_px() * 0.5
		for k: int in 5:
			var puff := Sprite2D.new()
			puff.texture = load(SMOKE_PATH) as Texture2D
			puff.modulate = Color(0.95, 0.78, 0.6, 0.55)
			var dir := Vector2.from_angle(PI + PI * k / 4.0)
			puff.position = Vector2(dir.x * w * 0.25, -6)
			puff.scale = Vector2(0.9, 0.6)
			add_child(puff)
			var t2 := puff.create_tween().set_parallel()
			t2.tween_property(puff, "position", puff.position + Vector2(dir.x * w * 0.7, -40 - 24 * absf(dir.y)), 0.6) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t2.tween_property(puff, "scale", Vector2(2.4, 1.6), 0.6)
			t2.tween_property(puff, "modulate:a", 0.0, 0.6)
			t2.chain().tween_callback(puff.queue_free)
	MenuKit.sfx(&"item_equip", -4.0)
