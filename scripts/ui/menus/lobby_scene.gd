class_name LobbyScene
extends Control
## Fond vivant du menu principal : le camp de base à la lisière de Dust Creek au coucher du
## soleil, pré-rendu dans Blender (art/blender/build_menu.py → assets/ui/menu/lobby/) en
## couches (lointain, camp, premier plan) + le héros (LobbyHero) posé à sa place.
## Animé en code, sans shader ni _process : drapeau (6 images), flammes (6 images, additif),
## lueur du feu et de la lanterne qui vacillent (Tween), fumée et poussière (CPUParticles2D,
## peu de particules), léger parallaxe en balancement lent (Tween), zoom d'entrée.
## La scène (2048 x 1024 px) est mise à l'échelle « cover » : toutes les positions du JSON sont
## en pixels de l'image.

signal hero_pressed

const DIR := "res://assets/ui/menu/lobby/"
const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")
const VIGNETTE: Texture2D = preload("res://assets/ui/menu/vignette.png")
## Amplitude du parallaxe (px de l'image) par couche : lointain, camp, héros, premier plan.
const PARALLAX := [5.0, 11.0, 17.0, 26.0]

var meta: Dictionary = {}
var image_size: Vector2 = Vector2(2048, 1024)
## Racine mise à l'échelle (coordonnées = pixels de l'image).
var stage: Control = null
var back_layer: Control = null
var camp_layer: Control = null
var hero_layer: Control = null
var front_layer: Control = null
var hero: LobbyHero = null
var flag: AnimatedSprite2D = null
var flames: AnimatedSprite2D = null
var fire_glow: Sprite2D = null
var smoke: CPUParticles2D = null
var dust: CPUParticles2D = null
var hero_hit: Control = null
## Balancement du parallaxe (-1..1), animé en boucle.
var sway: float = 0.0:
	set(v):
		sway = v
		_apply_parallax()
## Zoom d'entrée (1 = cadrage final).
var zoom: float = 1.0:
	set(v):
		zoom = v
		_layout()

var _layers: Array[Control] = []
var _base_scale: float = 1.0
var _tweens: Array[Tween] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_process(false)
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "lobby.json")) if FileAccess.file_exists(DIR + "lobby.json") else null
	meta = d if d is Dictionary else {}
	var sz: Variant = meta.get("size", [2048, 1024])
	image_size = Vector2(float(sz[0]), float(sz[1]))
	var bg := ColorRect.new()
	bg.color = MenuKit.NIGHT_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size = image_size
	add_child(stage)
	back_layer = _layer("Back")
	camp_layer = _layer("Camp")
	hero_layer = _layer("Hero")
	front_layer = _layer("Front")
	_build_back()
	_build_camp()
	_build_hero()
	_build_front()
	_build_overlay()
	resized.connect(_layout)
	_layout()
	_start_loops()


func _layer(n: String) -> Control:
	var c := Control.new()
	c.name = n
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = image_size
	stage.add_child(c)
	_layers.append(c)
	return c


func _tex(name: String) -> Texture2D:
	var p := DIR + name
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


func _sprite_rect(tex: Texture2D, rect: Variant, parent: Control) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	if rect is Array and (rect as Array).size() >= 4:
		t.position = Vector2(float(rect[0]), float(rect[1]))
		t.size = Vector2(float(rect[2]), float(rect[3]))
	else:
		t.size = image_size
	parent.add_child(t)
	return t


func _v(key: String, sub: String = "") -> Vector2:
	var v: Variant = meta.get(key)
	if v is Dictionary and not sub.is_empty():
		v = (v as Dictionary).get(sub)
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return image_size * 0.5


# --- Couches -----------------------------------------------------------------------

func _build_back() -> void:
	var tex := _tex("back.jpg")
	if tex == null:
		# Repli : ancien fond peint (projet sans les rendus du lobby)
		var mb := MenuBackground.new()
		mb.size = image_size
		back_layer.add_child(mb)
		return
	_sprite_rect(tex, null, back_layer)
	# lueur du feu au sol (additive, vacille)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fire_glow = Sprite2D.new()
	fire_glow.texture = GLOW
	fire_glow.material = add
	fire_glow.modulate = Color(1.0, 0.45, 0.15, 0.5)
	var fu: float = float((meta.get("fire", {}) as Dictionary).get("unit_px", 120.0))
	fire_glow.position = _v("fire", "pos") + Vector2(0, -fu * 0.1)
	fire_glow.scale = Vector2(fu * 3.2 / 256.0, fu * 1.4 / 256.0)
	back_layer.add_child(fire_glow)


func _build_camp() -> void:
	var tex := _tex("camp.png")
	if tex != null:
		_sprite_rect(tex, meta.get("camp"), camp_layer)
	# drapeau (planche 3 x 2)
	var ftex := _tex("flag.png")
	var fm: Dictionary = meta.get("flag", {})
	if ftex != null and fm.has("rect"):
		var r: Array = fm["rect"]
		var sf := SpriteFrames.new()
		sf.remove_animation(&"default")
		sf.add_animation(&"wave")
		sf.set_animation_speed(&"wave", float(fm.get("fps", 8)))
		var cols: int = int(fm.get("cols", 3))
		for i: int in int(fm.get("frames", 6)):
			var at := AtlasTexture.new()
			at.atlas = ftex
			at.region = Rect2((i % cols) * float(r[2]), (i / cols) * float(r[3]), float(r[2]), float(r[3]))
			sf.add_frame(&"wave", at)
		flag = AnimatedSprite2D.new()
		flag.sprite_frames = sf
		flag.centered = false
		flag.position = Vector2(float(r[0]), float(r[1]))
		camp_layer.add_child(flag)
		flag.play(&"wave")
	# flammes (6 images, additif) + fumée
	var fl := _tex("flame.png")
	var fire: Dictionary = meta.get("fire", {})
	if fl != null and not fire.is_empty():
		var fu: float = float(fire.get("unit_px", 120.0))
		var sf2 := SpriteFrames.new()
		sf2.remove_animation(&"default")
		sf2.add_animation(&"burn")
		sf2.set_animation_speed(&"burn", 12.0)
		var fw: float = fl.get_width() / 6.0
		for i: int in 6:
			var at2 := AtlasTexture.new()
			at2.atlas = fl
			at2.region = Rect2(i * fw, 0, fw, fl.get_height())
			sf2.add_frame(&"burn", at2)
		flames = AnimatedSprite2D.new()
		flames.sprite_frames = sf2
		flames.centered = false
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		flames.material = add
		var k: float = fu * 0.62 / fl.get_height()
		flames.scale = Vector2(k * 1.15, k)
		flames.offset = Vector2(-fw * 0.5, -fl.get_height() * 0.94)
		flames.position = _v("fire", "pos") + Vector2(0, -fu * 0.04)
		camp_layer.add_child(flames)
		flames.play(&"burn")
		var core := Sprite2D.new()
		core.texture = GLOW
		core.material = add
		core.modulate = Color(1.0, 0.6, 0.25, 0.75)
		core.position = flames.position + Vector2(0, -fu * 0.2)
		core.scale = Vector2(fu * 1.2 / 256.0, fu * 0.9 / 256.0)
		camp_layer.add_child(core)
		_flicker(core, 0.75, 0.2)
		smoke = _make_smoke(flames.position + Vector2(0, -fu * 0.55), fu)
		camp_layer.add_child(smoke)
	# lanterne de la table d'armes
	if meta.has("lantern"):
		var add3 := CanvasItemMaterial.new()
		add3.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		var lg := Sprite2D.new()
		lg.texture = GLOW
		lg.material = add3
		lg.modulate = Color(1.0, 0.7, 0.35, 0.55)
		lg.position = _v("lantern")
		lg.scale = Vector2(0.42, 0.42)
		camp_layer.add_child(lg)
		_flicker(lg, 0.55, 0.12)


func _build_hero() -> void:
	hero = LobbyHero.new()
	var h: Dictionary = meta.get("hero", {})
	hero.position = _v("hero", "feet")
	hero_layer.add_child(hero)
	hero.height_px = float(h.get("unit_px", 560.0))
	# zone de tap sur le héros (ouvre les personnages)
	hero_hit = Control.new()
	hero_hit.name = "HeroHit"
	hero_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	hero_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var hh: float = hero.height_px
	hero_hit.size = Vector2(hh * 0.6, hh)
	hero_hit.position = hero.position - Vector2(hh * 0.3, hh)
	hero_hit.gui_input.connect(_on_hero_input)
	hero_layer.add_child(hero_hit)


func _build_front() -> void:
	var tex := _tex("front.png")
	if tex != null:
		_sprite_rect(tex, meta.get("front"), front_layer)


func _build_overlay() -> void:
	# poussière en suspension, éclairée par le soleil rasant
	dust = CPUParticles2D.new()
	dust.amount = int(Balance.get_value("menu", "dust_amount", 18))
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.texture = GLOW
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = image_size * Vector2(0.5, 0.32)
	dust.position = image_size * Vector2(0.45, 0.62)
	dust.direction = Vector2(1, -0.15)
	dust.spread = 25.0
	dust.gravity = Vector2.ZERO
	dust.initial_velocity_min = 14.0
	dust.initial_velocity_max = 34.0
	dust.scale_amount_min = 0.012
	dust.scale_amount_max = 0.035
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.6, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.85, 0.6, 0.55))
	ramp.add_point(0.7, Color(1.0, 0.8, 0.55, 0.4))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.8, 0.5, 0.0))
	dust.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	dust.material = add
	dust.visible = bool(Balance.get_value("menu", "dust_enabled", true))
	stage.add_child(dust)
	# voiles haut / bas (lisibilité de l'interface) + vignettage
	add_child(_scrim(true))
	add_child(_scrim(false))
	var vig := TextureRect.new()
	vig.texture = VIGNETTE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate.a = 0.7
	add_child(vig)


func _scrim(top: bool) -> TextureRect:
	var g := Gradient.new()
	var c := MenuKit.NIGHT_DEEP
	g.set_color(0, Color(c, 0.72 if top else 0.0))
	g.set_color(1, Color(c, 0.0 if top else 0.78))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if top:
		t.anchor_right = 1.0
		t.anchor_bottom = 0.24
	else:
		t.anchor_top = 0.66
		t.anchor_right = 1.0
		t.anchor_bottom = 1.0
	return t


func _make_smoke(pos: Vector2, unit: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _tex("smoke.png")
	p.amount = 9
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.position = pos
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = unit * 0.06
	p.direction = Vector2(0.25, -1)
	p.spread = 12.0
	p.gravity = Vector2(unit * 0.05, 0)
	p.initial_velocity_min = unit * 0.16
	p.initial_velocity_max = unit * 0.24
	p.scale_amount_min = unit * 0.25 / 128.0
	p.scale_amount_max = unit * 0.4 / 128.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.45, 0.45, 0.0))
	ramp.add_point(0.15, Color(0.5, 0.42, 0.45, 0.32))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.62, 0.5, 0.6, 0.0))
	p.color_ramp = ramp
	return p


# --- Mise en page, animations -------------------------------------------------------

func _layout() -> void:
	if stage == null:
		return
	var vp: Vector2 = size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var overscan: float = 1.0 + PARALLAX[3] * 2.2 / image_size.x
	_base_scale = maxf(vp.x / image_size.x, vp.y / image_size.y) * overscan
	var s: float = _base_scale * zoom
	stage.scale = Vector2(s, s)
	# cadrage : centre horizontal, verticalement un peu au-dessus du centre (le sol est vide en bas)
	var focus := Vector2(0.5, 0.56)
	stage.position = vp * focus - image_size * focus * s
	stage.position.x = clampf(stage.position.x, vp.x - image_size.x * s, 0.0)
	stage.position.y = clampf(stage.position.y, vp.y - image_size.y * s, 0.0)


func _apply_parallax() -> void:
	for i: int in _layers.size():
		var a: float = PARALLAX[mini(i, PARALLAX.size() - 1)]
		_layers[i].position = Vector2(sway * a, -absf(sway) * a * 0.12)
	if dust != null:
		dust.position.x = image_size.x * 0.45 + sway * PARALLAX[2]


func _flicker(node: CanvasItem, base_a: float, amp: float) -> void:
	# séquence pseudo-aléatoire figée (déterministe), jouée en boucle
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node.get_instance_id()) & 0xffff
	var tw := node.create_tween().set_loops()
	var sc: Vector2 = (node as Node2D).scale if node is Node2D else Vector2.ONE
	for i: int in 7:
		var k: float = rng.randf_range(-1.0, 1.0)
		var dur: float = rng.randf_range(0.08, 0.22)
		tw.tween_property(node, "modulate:a", clampf(base_a + amp * k, 0.05, 1.0), dur)
		if node is Node2D:
			tw.parallel().tween_property(node, "scale", sc * (1.0 + 0.06 * k), dur)
	_tweens.append(tw)


func _start_loops() -> void:
	if fire_glow != null:
		_flicker(fire_glow, 0.5, 0.18)
	var period: float = Balance.get_float("menu", "lobby_sway_time", 14.0)
	var tw := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "sway", 1.0, period * 0.5).from(-1.0)
	tw.tween_property(self, "sway", -1.0, period * 0.5)
	_tweens.append(tw)


## Zoom d'entrée (léger travelling arrière) ; renvoie le Tween.
func play_intro(duration: float = 1.4) -> Tween:
	zoom = 1.07
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "zoom", 1.0, duration)
	return tw


## Arrête les animations en boucle (écran quitté, tests).
func stop_loops() -> void:
	for t: Tween in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()


## Position (px de l'écran, repère de ce nœud) des pieds du héros.
func hero_screen_position() -> Vector2:
	return stage.position + (hero_layer.position + hero.position) * stage.scale.x


func _on_hero_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		hero_hit.accept_event()
		hero_pressed.emit()
