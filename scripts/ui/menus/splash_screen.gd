class_name SplashScreen
extends Control
## Écran de démarrage animé (scène principale) : prend le relais du boot splash natif,
## puis : emblème viseur qui apparaît (lueur rouge), la flèche de sortie jaillit (son),
## le titre « Exfil Rush » glisse en place avec le slogan, puis fondu vers le menu principal.
## Tap / clic / touche = passer. Durée : balance.cfg [menu] splash_duration (≈ 2,5 s).

const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")

## Scène suivante (modifiable pour les tests).
var next_scene: String = MenuKit.MAIN_MENU_SCENE
## Désactive l'enchaînement automatique (tests / captures).
var auto_advance: bool = true

var title_label: Label = null
var subtitle: Label = null
var logo: ExfilLogo = null
var emblem: ExfilEmblem = null
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
	logo = ExfilLogo.new(int(Balance.get_value("menu", "splash_logo_size", 110)))
	center.add_child(logo)
	emblem = logo.emblem
	title_label = logo.title_label
	subtitle = logo.slogan_label
	glow_rect = TextureRect.new()
	glow_rect.texture = GLOW
	glow_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow_rect.modulate = Color(0.95, 0.15, 0.12, 0.0)
	glow_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_rect.show_behind_parent = true
	emblem.add_child(glow_rect)
	emblem.resized.connect(func() -> void:
		var g: float = emblem.size.x * 2.6
		glow_rect.size = Vector2(g, g)
		glow_rect.position = emblem.size * 0.5 - glow_rect.size * 0.5
		glow_rect.pivot_offset = glow_rect.size * 0.5)

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
	logo.slogan_band.modulate.a = 0.0
	emblem.modulate.a = 0.0
	emblem.scale = Vector2(0.5, 0.5)
	emblem.arrow_progress = 0.0
	MenuKit.fade_in(self, 0.35)

	_timeline = create_tween()
	# 0,0 → 0,5 s : le viseur apparaît
	_timeline.tween_property(emblem, "modulate:a", 1.0, 0.25).set_delay(0.1)
	_timeline.parallel().tween_property(emblem, "scale", Vector2.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 0,5 → 0,9 s : la flèche de sortie jaillit + lueur rouge + son
	_timeline.tween_callback(func() -> void: MenuKit.sfx(&"mask_power", -6.0))
	_timeline.tween_property(emblem, "arrow_progress", 1.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_property(glow_rect, "modulate:a", 0.9, 0.2)
	_timeline.parallel().tween_property(glow_rect, "scale", Vector2(1.15, 1.15), 0.25).from(Vector2(0.4, 0.4))
	# 0,9 → 1,4 s : titre et slogan
	_timeline.tween_property(title_label, "modulate:a", 1.0, 0.3)
	_timeline.parallel().tween_property(glow_rect, "modulate:a", 0.5, 0.4)
	_timeline.parallel().tween_property(glow_rect, "scale", Vector2.ONE, 0.4)
	_timeline.tween_property(logo.slogan_band, "modulate:a", 1.0, 0.2)
	# Pause sur le logo jusqu'à la durée totale
	_timeline.tween_interval(maxf(total - 1.5, 0.2))
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
