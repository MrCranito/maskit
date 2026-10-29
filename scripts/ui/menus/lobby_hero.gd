class_name LobbyHero
extends Node2D
## Héros posé dans le camp du menu principal : idle « lobby » (pose 3/4, fusil en main) rendue
## pour chaque skin par art/blender/build_menu_hero.py (assets/ui/menu/hero/<skin>.png, planche
## 4 x 2), ombre au sol, réaction au changement de skin (écrasement + éclair + poussière).
## Origine du nœud = pieds. `height_px` = hauteur visible voulue (px de l'espace parent).
## Aucun _process : AnimatedSprite2D + Tween.

const DIR := "res://assets/ui/menu/hero/"
const META_PATH := DIR + "hero_menu.json"
const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")
const SMOKE_PATH := "res://assets/ui/menu/lobby/smoke.png"

var sprite: AnimatedSprite2D = null
var shadow: Sprite2D = null
## Skin affiché (null = apparence par défaut).
var skin: SkinData = null
## Id de la planche utilisée (« default », « gign »…).
var sheet_id: String = ""
var height_px: float = 400.0:
	set(v):
		height_px = v
		_apply_scale()

var _meta: Dictionary = {}
var _base_scale: Vector2 = Vector2.ONE
var _react_tween: Tween = null
var _follow_profile: bool = true
static var _frames_cache: Dictionary = {}


func _init(follow_profile: bool = true) -> void:
	_follow_profile = follow_profile


func _ready() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH)) if FileAccess.file_exists(META_PATH) else null
	_meta = d if d is Dictionary else {}
	shadow = Sprite2D.new()
	shadow.texture = GLOW
	shadow.modulate = Color(0.03, 0.02, 0.08, 0.55)
	add_child(shadow)
	sprite = AnimatedSprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(sprite)
	if _follow_profile:
		Profile.changed.connect(_on_profile_changed)
		set_skin(HeroSkin.current(), false)
	elif sprite.sprite_frames == null:
		set_skin(skin, false)


## Affiche ce skin ; `animate` : petite réaction (écrasement, éclair, bouffée de poussière).
func set_skin(s: SkinData, animate: bool = true) -> void:
	skin = s
	if sprite == null:
		return
	var id := sheet_for(s)
	sheet_id = id
	var frames := _frames(id)
	sprite.sprite_frames = frames
	sprite.material = HeroSkin.material_for(s) if not has_sheet(s) else null
	if frames != null:
		sprite.play(&"idle")
	sprite.position = -_feet()
	sprite.offset = Vector2.ZERO
	shadow.position = Vector2(0, -2)
	_apply_scale()
	if animate and is_inside_tree():
		_react()


## Id de planche pour ce skin : « char_gign » → « gign » ; repli « default ».
static func sheet_for(s: SkinData) -> String:
	if s == null:
		return "default"
	var id := String(s.id).trim_prefix("char_")
	return id if ResourceLoader.exists(DIR + id + ".png") else "default"


static func has_sheet(s: SkinData) -> bool:
	return s == null or ResourceLoader.exists(DIR + String(s.id).trim_prefix("char_") + ".png")


func get_current_animation() -> StringName:
	return sprite.animation if sprite != null else &""


func _on_profile_changed() -> void:
	var cur := HeroSkin.current()
	var cur_id: StringName = cur.id if cur != null else &""
	var old_id: StringName = skin.id if skin != null else &""
	if cur_id != old_id:
		set_skin(cur, true)


func _frame_size() -> Vector2:
	var fs: Variant = _meta.get("frame_size", [320, 400])
	return Vector2(float(fs[0]), float(fs[1]))


func _feet() -> Vector2:
	var f: Variant = _meta.get("feet", [160, 372])
	return Vector2(float(f[0]), float(f[1]))


func _apply_scale() -> void:
	if sprite == null:
		return
	var hp: float = float(_meta.get("hero_px", 363))
	var k: float = height_px / maxf(hp, 1.0)
	_base_scale = Vector2(k, k)
	if _react_tween == null or not _react_tween.is_valid():
		scale = _base_scale
	shadow.scale = Vector2(hp * 0.62 / 256.0, hp * 0.12 / 256.0)


func _frames(id: String) -> SpriteFrames:
	if _frames_cache.has(id):
		return _frames_cache[id] as SpriteFrames
	var tex := load(DIR + id + ".png") as Texture2D
	if tex == null:
		return null
	var fs := _frame_size()
	var cols: int = int(_meta.get("cols", 4))
	var n: int = int(_meta.get("frames", 8))
	var sf := SpriteFrames.new()
	sf.remove_animation(&"default")
	sf.add_animation(&"idle")
	sf.set_animation_loop(&"idle", true)
	sf.set_animation_speed(&"idle", float(_meta.get("fps", 7)))
	for i: int in n:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(Vector2((i % cols) * fs.x, (i / cols) * fs.y), fs)
		sf.add_frame(&"idle", at)
	_frames_cache[id] = sf
	return sf


func _react() -> void:
	var base := _base_scale
	if _react_tween != null and _react_tween.is_valid():
		_react_tween.kill()
	var tw := create_tween()
	_react_tween = tw
	tw.tween_property(self, "scale", Vector2(base.x * 1.08, base.y * 0.9), 0.07)
	tw.tween_property(self, "scale", Vector2(base.x * 0.96, base.y * 1.07), 0.1)
	tw.tween_property(self, "scale", base, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sprite.modulate = Color(2.2, 2.0, 1.8)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.35)
	# bouffée de poussière au sol
	if ResourceLoader.exists(SMOKE_PATH):
		var fs := _frame_size()
		for k: int in 5:
			var puff := Sprite2D.new()
			puff.texture = load(SMOKE_PATH) as Texture2D
			puff.modulate = Color(0.95, 0.78, 0.6, 0.55)
			var dir := Vector2.from_angle(PI + PI * k / 4.0)
			puff.position = Vector2(dir.x * fs.x * 0.12, -6)
			puff.scale = Vector2(0.5, 0.35)
			add_child(puff)
			var t2 := puff.create_tween().set_parallel()
			t2.tween_property(puff, "position", puff.position + Vector2(dir.x * fs.x * 0.35, -20 - 12 * absf(dir.y)), 0.6) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t2.tween_property(puff, "scale", Vector2(1.3, 0.9), 0.6)
			t2.tween_property(puff, "modulate:a", 0.0, 0.6)
			t2.chain().tween_callback(puff.queue_free)
	MenuKit.sfx(&"item_equip", -4.0)
