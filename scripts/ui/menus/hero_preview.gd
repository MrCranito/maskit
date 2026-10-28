class_name HeroPreview
extends Control
## Aperçu du héros 3D (hero_frames.tres) : animation idle qui tourne lentement dans les
## 8 directions (Timer, pas de _process), lueur d'aura au sol, teinte d'aura du masque.

const HERO_FRAMES_PATH := "res://assets/sprites/hero3d/hero_frames.tres"
const HERO_META_PATH := "res://assets/sprites/hero3d/hero_meta.json"
const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")
## Ordre de rotation (sens horaire vu de dessus, en partant de face).
const TURN_ORDER: Array[String] = ["s", "sw", "w", "nw", "n", "ne", "e", "se"]

var sprite: AnimatedSprite2D = null
var glow: TextureRect = null
var dir_index: int = 0
var _timer: Timer = null
var _feet: Vector2 = Vector2(80, 131)
var _frame_size: Vector2 = Vector2(160, 160)
var _aura: Color = Color.WHITE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	clip_contents = false
	glow = TextureRect.new()
	glow.texture = GLOW
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	if ResourceLoader.exists(HERO_FRAMES_PATH):
		sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = load(HERO_FRAMES_PATH) as SpriteFrames
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(HERO_META_PATH)) \
			if FileAccess.file_exists(HERO_META_PATH) else null
		if meta is Dictionary:
			var fs: Variant = (meta as Dictionary).get("frame_size")
			var ft: Variant = (meta as Dictionary).get("feet_offset")
			if fs is Array and (fs as Array).size() >= 2:
				_frame_size = Vector2(float(fs[0]), float(fs[1]))
			if ft is Array and (ft as Array).size() >= 2:
				_feet = Vector2(float(ft[0]), float(ft[1]))
		sprite.offset = -(_feet - _frame_size * 0.5)
		add_child(sprite)
		_play_dir()
	_timer = Timer.new()
	_timer.wait_time = Balance.get_float("menu", "preview_turn_interval", 1.1)
	_timer.timeout.connect(_turn)
	add_child(_timer)
	_timer.start()
	resized.connect(_layout)
	_layout()
	var tw := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tw.tween_property(glow, "modulate:a", 0.95, 1.4).from(0.6)
	tw.tween_property(glow, "modulate:a", 0.6, 1.4)


func _layout() -> void:
	# Pieds à 82 % de la hauteur ; hauteur du héros ≈ 78 % de la boîte.
	var feet_pos := Vector2(size.x * 0.5, size.y * 0.84)
	if sprite != null:
		var sc: float = size.y * Balance.get_float("menu", "preview_height_ratio", 1.05) / _frame_size.y
		sprite.scale = Vector2(sc, sc)
		sprite.position = feet_pos
	var gw: float = size.x * 0.95
	glow.size = Vector2(gw, gw * 0.36)
	glow.position = feet_pos - glow.size * 0.5


func _turn() -> void:
	dir_index = (dir_index + 1) % TURN_ORDER.size()
	_play_dir()


func _play_dir() -> void:
	if sprite == null:
		return
	var anim := StringName("idle_" + TURN_ORDER[dir_index])
	if sprite.sprite_frames.has_animation(anim):
		var f: int = sprite.frame
		sprite.play(anim)
		sprite.frame = f % maxi(sprite.sprite_frames.get_frame_count(anim), 1)


func get_current_animation() -> StringName:
	return sprite.animation if sprite != null else &""


## Applique la teinte d'aura du masque (plus marquée qu'en jeu pour la lisibilité du menu).
func set_mask(mask: MaskData) -> void:
	if mask == null:
		return
	_aura = mask.aura_color
	var tint: Color = Color.WHITE.lerp(_aura, clampf(mask.aura_tint_strength * 1.3, 0.0, 0.6))
	var tw := create_tween().set_parallel()
	if sprite != null:
		tw.tween_property(sprite, "self_modulate", tint, 0.3)
	tw.tween_property(glow, "self_modulate", Color(_aura.lightened(0.1), 1.0), 0.3)
	if sprite != null:
		sprite.scale *= 0.92
		var sc: float = size.y * Balance.get_float("menu", "preview_height_ratio", 1.05) / _frame_size.y
		tw.tween_property(sprite, "scale", Vector2(sc, sc), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
