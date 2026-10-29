class_name SplashScreen
extends Control
## Écran de démarrage animé (scène principale). Il prend le relais de l'image de démarrage du
## moteur (assets/ui/splash/boot.png, mise à l'échelle « cover ») SANS saut : même fond
## (splash_bg.png = boot.png sans le logo) et même logo (splash_logo.png) aux mêmes
## coordonnées, cadrés de la même façon. Puis : le logo « frappe » (petit zoom + lueur rouge
## derrière « GO », son), un reflet balaie le titre, braises qui montent, lente poussée du fond,
## et fondu vers le menu principal. Tap / clic / touche = passer.
## Durée : balance.cfg [menu] splash_duration. Images : art/blender/build_menu_2d.py splash.

const DIR := "res://assets/ui/splash/"
const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")

## Scène suivante (modifiable pour les tests).
var next_scene: String = MenuKit.MAIN_MENU_SCENE
## Désactive l'enchaînement automatique (tests / captures).
var auto_advance: bool = true

var meta: Dictionary = {}
var image_size: Vector2 = Vector2(1920, 1080)
var background: TextureRect = null
var logo: TextureRect = null
var shine: ColorRect = null
var emblem_glow: Sprite2D = null
var embers: CPUParticles2D = null
var hint: Label = null
## Cadre « cover » de l'image (repère de cet écran) : position et échelle.
var frame_origin: Vector2 = Vector2.ZERO
var frame_scale: float = 1.0
var push: float = 1.0:
	set(v):
		push = v
		_layout()

var _timeline: Tween = null
var _done: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	MenuKit.apply_saved_settings()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "splash.json")) if FileAccess.file_exists(DIR + "splash.json") else null
	meta = d if d is Dictionary else {}
	var sz: Variant = meta.get("size", [1920, 1080])
	image_size = Vector2(float(sz[0]), float(sz[1]))
	_build()
	resized.connect(_layout)
	_layout()
	_play()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = MenuKit.NIGHT   # = application/boot_splash/bg_color
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	background = TextureRect.new()
	background.texture = _load("splash_bg.png", "boot.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	embers = CPUParticles2D.new()
	embers.amount = 26
	embers.lifetime = 3.2
	embers.preprocess = 2.0
	embers.texture = GLOW
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.direction = Vector2(0.15, -1)
	embers.spread = 18.0
	embers.gravity = Vector2(12, -10)
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 90.0
	embers.scale_amount_min = 0.02
	embers.scale_amount_max = 0.05
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.6, 0.2, 0.0))
	ramp.add_point(0.2, Color(1.0, 0.62, 0.25, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.3, 0.1, 0.0))
	embers.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = add
	embers.emitting = false
	add_child(embers)
	emblem_glow = Sprite2D.new()
	emblem_glow.texture = GLOW
	emblem_glow.material = add
	emblem_glow.modulate = Color(0.95, 0.18, 0.12, 0.0)
	add_child(emblem_glow)
	logo = TextureRect.new()
	logo.texture = _load("splash_logo.png", "")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_SCALE
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	logo.visible = logo.texture != null
	add_child(logo)
	# reflet : bande claire inclinée, visible seulement sur le logo (clip_children)
	shine = ColorRect.new()
	shine.color = Color(1, 0.95, 0.85, 0.55)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.rotation = 0.35
	shine.visible = false
	logo.add_child(shine)
	hint = MenuKit.label("Touchez pour continuer", 18, Color(MenuKit.TEXT_DIM, 0.75), MenuKit.nunito(800), 3)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -maxf(MenuKit.safe_margins(self).w, 14.0)
	hint.modulate.a = 0.0
	add_child(hint)


func _load(name: String, fallback: String) -> Texture2D:
	if ResourceLoader.exists(DIR + name):
		return load(DIR + name) as Texture2D
	if not fallback.is_empty() and ResourceLoader.exists(DIR + fallback):
		return load(DIR + fallback) as Texture2D
	return null


func _rect(key: String) -> Rect2:
	var r: Variant = meta.get(key)
	if r is Array and (r as Array).size() >= 4:
		return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	return Rect2(Vector2.ZERO, image_size)


## Même cadrage que le boot splash natif (« cover », centré). `push` agrandit le fond seul.
func _layout() -> void:
	var vp: Vector2 = size
	if vp.x <= 0.0 or vp.y <= 0.0 or background == null:
		return
	frame_scale = maxf(vp.x / image_size.x, vp.y / image_size.y)
	frame_origin = (vp - image_size * frame_scale) * 0.5
	var bs: float = frame_scale * push
	background.size = image_size * bs
	background.position = (vp - image_size * bs) * 0.5
	var lr := _rect("logo_layer")
	logo.position = frame_origin + lr.position * frame_scale
	logo.size = lr.size * frame_scale
	logo.pivot_offset = logo.size * Vector2(0.5, 0.45)
	shine.size = Vector2(logo.size.x * 0.12, logo.size.y * 1.6)
	var ec: Variant = meta.get("glow_center", [image_size.x * 0.5, image_size.y * 0.8])
	emblem_glow.position = frame_origin + Vector2(float(ec[0]), float(ec[1])) * frame_scale
	var es: float = float(meta.get("glow_size", 200)) * frame_scale
	emblem_glow.scale = Vector2(es * 3.6 / 256.0, es * 2.2 / 256.0)
	embers.position = Vector2(vp.x * 0.5, vp.y * 0.98)
	embers.emission_rect_extents = Vector2(vp.x * 0.45, 10)


func _play() -> void:
	var total: float = Balance.get_float("menu", "splash_duration", 2.6)
	# Pas de fondu d'entrée : la première image est identique au boot splash natif.
	_timeline = create_tween()
	_timeline.tween_interval(0.12)
	_timeline.tween_callback(func() -> void:
		embers.emitting = true
		MenuKit.sfx(&"mask_power", -6.0))
	# frappe du logo + lueur rouge de l'emblème
	_timeline.tween_property(logo, "scale", Vector2(1.07, 1.07), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_property(emblem_glow, "modulate:a", 1.0, 0.12)
	_timeline.tween_property(logo, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_property(emblem_glow, "modulate:a", 0.45, 0.6)
	# reflet qui balaie le titre
	_timeline.tween_callback(func() -> void:
		shine.visible = true
		shine.position = Vector2(-shine.size.x * 2.0, -logo.size.y * 0.3))
	_timeline.tween_property(shine, "position:x", logo.size.x * 1.15, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_timeline.parallel().tween_property(hint, "modulate:a", 1.0, 0.5)
	_timeline.tween_interval(maxf(total - 1.3, 0.2))
	_timeline.tween_callback(func() -> void:
		if auto_advance:
			finish())
	# lente poussée du fond (indépendante de la timeline)
	create_tween().tween_property(self, "push", 1.045, total + 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Passe au menu principal (tap, touche, ou fin de l'animation).
func finish() -> void:
	if _done:
		return
	_done = true
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	MenuKit.go_to(self, next_scene, Balance.get_float("menu", "fade_time", 0.3) + 0.1)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		accept_event()
		finish()


func _unhandled_input(event: InputEvent) -> void:
	if (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed):
		get_viewport().set_input_as_handled()
		finish()
