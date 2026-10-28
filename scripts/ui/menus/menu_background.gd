class_name MenuBackground
extends Control
## Fond animé léger des menus : ciel de coucher de soleil (texture), deux bandes de
## silhouettes de ville Far West qui défilent lentement (parallaxe par Tween en boucle),
## poussière (CPUParticles2D, peu de particules) et vignettage.
## Aucun shader, aucun _process : uniquement des Tween et des textures pré-calculées
## (assets/ui/menu/build_menu_art.py).

const SKY: Texture2D = preload("res://assets/ui/menu/sky.png")
const TOWN_FAR: Texture2D = preload("res://assets/ui/menu/town_far.png")
const TOWN_NEAR: Texture2D = preload("res://assets/ui/menu/town_near.png")
const VIGNETTE: Texture2D = preload("res://assets/ui/menu/vignette.png")
const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")

## Assombrit l'image (0 = aucun) pour les écrans chargés (sélection du masque).
@export_range(0.0, 1.0) var dim: float = 0.0
## Teinte du halo derrière le soleil (modifiable : aura du masque).
var sun_glow: TextureRect = null

var _strips: Array[Control] = []
var _dust: CPUParticles2D = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	clip_contents = true
	var sky := TextureRect.new()
	sky.texture = SKY
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sky)

	sun_glow = TextureRect.new()
	sun_glow.texture = GLOW
	sun_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sun_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sun_glow.modulate = Color(1.0, 0.75, 0.5, 0.0)
	add_child(sun_glow)

	var far_speed: float = Balance.get_float("menu", "bg_far_scroll_time", 160.0)
	var near_speed: float = Balance.get_float("menu", "bg_near_scroll_time", 70.0)
	_strips.append(_make_strip(TOWN_FAR, 0.42, 0.0, far_speed))
	_strips.append(_make_strip(TOWN_NEAR, 0.47, 0.0, near_speed))

	if bool(Balance.get_value("menu", "dust_enabled", true)):
		_build_dust()

	var vig := TextureRect.new()
	vig.texture = VIGNETTE
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)
	if dim > 0.0:
		var shade := ColorRect.new()
		shade.color = Color(MenuKit.NIGHT_DEEP, dim)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
	resized.connect(_layout)
	_layout()
	_animate_sun()


## Bande de silhouettes : deux copies côte à côte qui glissent d'une largeur, en boucle.
func _make_strip(tex: Texture2D, height_ratio: float, _y: float, loop_time: float) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	for i: int in 2:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(t)
	holder.set_meta(&"height_ratio", height_ratio)
	holder.set_meta(&"loop_time", loop_time)
	return holder


func _layout() -> void:
	var s: Vector2 = size
	if s.x <= 0.0:
		return
	for holder: Control in _strips:
		var h: float = s.y * float(holder.get_meta(&"height_ratio"))
		var tex: Texture2D = (holder.get_child(0) as TextureRect).texture
		var w: float = h * float(tex.get_width()) / float(tex.get_height())
		w = maxf(w, s.x)
		holder.size = Vector2(w * 2.0, h)
		holder.position = Vector2(0.0, s.y - h)
		for i: int in 2:
			var t := holder.get_child(i) as TextureRect
			t.position = Vector2(w * i, 0.0)
			t.size = Vector2(w + 1.0, h)
		_start_scroll(holder, w)
	var g: float = s.y * 1.1
	sun_glow.size = Vector2(g, g)
	sun_glow.position = Vector2(s.x * 0.5 - g * 0.5, s.y * 0.74 - g * 0.5)
	sun_glow.pivot_offset = sun_glow.size * 0.5
	if _dust != null:
		_dust.position = Vector2(s.x * 0.5, s.y * 0.75)
		_dust.emission_rect_extents = Vector2(s.x * 0.55, s.y * 0.25)


func _start_scroll(holder: Control, w: float) -> void:
	var old: Variant = holder.get_meta(&"tween") if holder.has_meta(&"tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var t: float = float(holder.get_meta(&"loop_time"))
	if t <= 0.0:
		return
	holder.position.x = 0.0
	var tw := create_tween().set_loops()
	tw.tween_property(holder, "position:x", -w, t).from(0.0)
	holder.set_meta(&"tween", tw)


func _animate_sun() -> void:
	var tw := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	tw.tween_property(sun_glow, "modulate:a", 0.45, 3.0).from(0.25)
	tw.tween_property(sun_glow, "modulate:a", 0.25, 3.0)


func _build_dust() -> void:
	_dust = CPUParticles2D.new()
	_dust.amount = int(Balance.get_value("menu", "dust_amount", 28))
	_dust.lifetime = 9.0
	_dust.preprocess = 9.0
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.direction = Vector2(-1.0, -0.15)
	_dust.spread = 18.0
	_dust.gravity = Vector2.ZERO
	_dust.initial_velocity_min = 14.0
	_dust.initial_velocity_max = 38.0
	_dust.scale_amount_min = 1.5
	_dust.scale_amount_max = 3.5
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.65, 0.0))
	grad.add_point(0.2, Color(1.0, 0.85, 0.65, 0.55))
	grad.add_point(0.8, Color(1.0, 0.85, 0.65, 0.4))
	grad.set_color(grad.get_point_count() - 1, Color(1.0, 0.85, 0.65, 0.0))
	_dust.color_ramp = grad
	add_child(_dust)


## Teinte le halo du soleil (couleur d'aura du masque sélectionné).
func set_glow_color(c: Color) -> void:
	var tw := create_tween()
	tw.tween_property(sun_glow, "self_modulate", Color(c.lightened(0.2), 1.0), 0.4)
