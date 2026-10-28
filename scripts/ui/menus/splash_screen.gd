class_name SplashScreen
extends Control
## Écran de démarrage animé (scène principale) : prend le relais du boot splash natif
## (même image de fond pour une transition invisible), puis :
## titre en fondu, masque kitsune qui apparaît avec une lueur rouge pulsée, petit son,
## puis fondu vers le menu principal. Tap / clic / touche = passer.
## Durée totale : balance.cfg [menu] splash_duration (≈ 2,5 s). Animations par Tween.

const MASK: Texture2D = preload("res://assets/ui/masks/kitsune.png")
const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")

## Scène suivante (modifiable pour les tests).
var next_scene: String = MenuKit.MAIN_MENU_SCENE
## Désactive l'enchaînement automatique (tests / captures).
var auto_advance: bool = true

var title_label: Label = null
var subtitle: Label = null
var mask_rect: TextureRect = null
var glow_rect: TextureRect = null
var _timeline: Tween = null
var _done: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)
	MenuKit.apply_saved_settings()
	_build()
	_play()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = MenuKit.NIGHT_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Fond : la ville au coucher du soleil (le boot natif reste dessous pendant le chargement)
	var back := MenuBackground.new()
	add_child(back)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	title_label = MenuKit.title("Les Royaumes des Masques", 76)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title_label)
	subtitle = MenuKit.label("E X T R A C T I O N", 26, MenuKit.GOLD, MenuKit.nunito(900), 4)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(subtitle)

	var mask_holder := Control.new()
	mask_holder.custom_minimum_size = Vector2(320, 320)
	mask_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mask_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mask_holder)
	glow_rect = TextureRect.new()
	glow_rect.texture = GLOW
	glow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow_rect.modulate = Color(0.95, 0.12, 0.12, 0.0)
	glow_rect.size = Vector2(520, 520)
	glow_rect.position = Vector2(160 - 260, 160 - 260)
	glow_rect.pivot_offset = Vector2(260, 260)
	glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask_holder.add_child(glow_rect)
	mask_rect = TextureRect.new()
	mask_rect.texture = MASK
	mask_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mask_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mask_rect.size = Vector2(300, 300)
	mask_rect.position = Vector2(10, 10)
	mask_rect.pivot_offset = Vector2(150, 150)
	mask_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask_holder.add_child(mask_rect)

	var hint := MenuKit.label("Touchez pour continuer", 18, Color(MenuKit.TEXT_DIM, 0.7), MenuKit.nunito(700), 3)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.position.y -= 40
	add_child(hint)
	hint.modulate.a = 0.0
	create_tween().tween_property(hint, "modulate:a", 1.0, 0.6).set_delay(0.8)


func _play() -> void:
	var total: float = Balance.get_float("menu", "splash_duration", 2.5)
	title_label.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	mask_rect.modulate.a = 0.0
	mask_rect.scale = Vector2(0.6, 0.6)
	MenuKit.fade_in(self, 0.35)

	_timeline = create_tween()
	# 0,0 → 0,6 s : titre
	_timeline.tween_property(title_label, "modulate:a", 1.0, 0.55).set_delay(0.1)
	_timeline.parallel().tween_property(subtitle, "modulate:a", 1.0, 0.5).set_delay(0.35)
	# 0,6 → 1,3 s : masque + lueur rouge + son
	_timeline.tween_callback(func() -> void: MenuKit.sfx(&"mask_power", -6.0))
	_timeline.tween_property(mask_rect, "modulate:a", 1.0, 0.35)
	_timeline.parallel().tween_property(mask_rect, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_property(glow_rect, "modulate:a", 0.95, 0.3)
	_timeline.parallel().tween_property(glow_rect, "scale", Vector2(1.15, 1.15), 0.3).from(Vector2(0.5, 0.5))
	_timeline.tween_property(glow_rect, "modulate:a", 0.6, 0.45)
	_timeline.parallel().tween_property(glow_rect, "scale", Vector2.ONE, 0.45)
	# Pause sur le logo jusqu'à la durée totale
	_timeline.tween_interval(maxf(total - 1.75, 0.2))
	_timeline.tween_callback(func() -> void:
		if auto_advance:
			finish())


## Passe au menu principal (tap, touche, ou fin de l'animation).
func finish() -> void:
	if _done:
		return
	_done = true
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	MenuKit.go_to(self, next_scene, Balance.get_float("menu", "fade_time", 0.3))


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
