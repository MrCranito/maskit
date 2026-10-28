class_name HeroPreview
extends Control
## Aperçu du héros (planche du skin porté : HeroSkin.frames_for / meta_for / material_for) :
## animation idle qui tourne lentement dans les 8 directions (Timer, pas de _process),
## halo au sol. Fonctionne avec l'ancienne et la nouvelle planche (animations idle_<dir>,
## repli sur la première animation disponible).

const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")
## Ordre de rotation (sens horaire vu de dessus, en partant de face).
const TURN_ORDER: Array[String] = ["s", "sw", "w", "nw", "n", "ne", "e", "se"]

var sprite: AnimatedSprite2D = null
var glow: TextureRect = null
var dir_index: int = 0
## Tourne sur lui-même (sinon reste de face).
var turning: bool = true
var skin: SkinData = null
## Hauteur de la planche rapportée à la boîte (< 0 : balance.cfg [menu] preview_height_ratio).
var height_ratio: float = -1.0
var _use_current: bool = true
var _timer: Timer = null
var _feet: Vector2 = Vector2(80, 131)
var _frame_size: Vector2 = Vector2(160, 160)


func _init(p_turning: bool = true) -> void:
	turning = p_turning


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	clip_contents = false
	glow = TextureRect.new()
	glow.texture = GLOW
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.self_modulate = Color(1.0, 0.72, 0.5)
	add_child(glow)
	sprite = AnimatedSprite2D.new()
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(sprite)
	_apply_skin()
	if turning:
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


## Affiche ce skin (null = apparence par défaut). Sans appel : skin porté (HeroSkin.current()).
func set_skin(s: SkinData) -> void:
	skin = s
	_use_current = false
	if sprite != null:
		_apply_skin()
		_layout()


func _apply_skin() -> void:
	var s: SkinData = HeroSkin.current() if _use_current else skin
	var frames: SpriteFrames = HeroSkin.frames_for(s)
	sprite.sprite_frames = frames
	sprite.visible = frames != null
	sprite.material = HeroSkin.material_for(s)
	var meta: Dictionary = HeroSkin.meta_for(s)
	var fs: Variant = meta.get("frame_size")
	var ft: Variant = meta.get("feet_offset")
	if fs is Array and (fs as Array).size() >= 2:
		_frame_size = Vector2(float(fs[0]), float(fs[1]))
	if ft is Array and (ft as Array).size() >= 2:
		_feet = Vector2(float(ft[0]), float(ft[1]))
	sprite.offset = -(_feet - _frame_size * 0.5)
	_play_dir()


func _layout() -> void:
	var feet_pos := Vector2(size.x * 0.5, size.y * 0.88)
	if sprite != null:
		var hr: float = height_ratio if height_ratio > 0.0 else Balance.get_float("menu", "preview_height_ratio", 0.95)
		var sc: float = size.y * hr / _frame_size.y
		sprite.scale = Vector2(sc, sc)
		sprite.position = feet_pos
	var gw: float = minf(size.x * 0.95, size.y * 1.1)
	glow.size = Vector2(gw, gw * 0.34)
	glow.position = feet_pos - glow.size * 0.5


func _turn() -> void:
	dir_index = (dir_index + 1) % TURN_ORDER.size()
	_play_dir()


func _play_dir() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var anim := StringName("idle_" + TURN_ORDER[dir_index])
	if not sprite.sprite_frames.has_animation(anim):
		var names := sprite.sprite_frames.get_animation_names()
		if names.is_empty():
			return
		anim = StringName(names[0])
	var f: int = sprite.frame
	sprite.play(anim)
	sprite.frame = f % maxi(sprite.sprite_frames.get_frame_count(anim), 1)


func get_current_animation() -> StringName:
	return sprite.animation if sprite != null else &""
