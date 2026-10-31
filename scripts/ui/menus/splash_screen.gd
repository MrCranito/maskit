class_name SplashScreen
extends Control
## Écran de démarrage animé (scène principale), direction « D ».
## Première image = image de démarrage du moteur (assets/ui/splash/boot.png, rendue depuis CETTE
## scène par tools/splash_boot/render_boot.gd) : écran encre, logotype RAIDERSGO centré.
## Puis (≈ 2,8 s, passable au toucher) : le voile encre se replie en plaque biseautée derrière le
## logo qui glisse à droite et découvre le camp au coucher du soleil (LobbyScene, le même fond
## vivant que le menu principal, héros compris) ; le grand bandeau violet translucide et un liseré
## glissent depuis la droite ; reflet sur le logo ; braises ;
## légère respiration ; barre de chargement discrète (le menu principal est chargé en tâche de
## fond) ; fondu vers le menu principal.
## Cadrage de la première image : boot.png (1920 x 1080) est affiché par le moteur en « keep »
## (application/boot_splash/stretch_mode = 1) sur fond encre : le logo y mesure
## min(l / 1920, h / 1080) fois sa taille de référence, comme ici (frame_scale).
## Réglages : balance.cfg [menu] splash_*.

## Taille de référence de boot.png.
const REF := Vector2(1920, 1080)
const GLOW: Texture2D = preload("res://assets/ui/menu/glow.png")

## Scène suivante (modifiable pour les tests).
var next_scene: String = MenuKit.MAIN_MENU_SCENE
## Désactive l'enchaînement automatique (tests / captures).
var auto_advance: bool = true
## Fige la première image (rendu de boot.png).
var frozen: bool = false

var lobby: LobbyScene = null
var shade: TextureRect = null
var slab: Slab = null
var stripe: Slab = null
var curtain: Curtain = null
var logo: Control = null
var wordmark: Wordmark = null
var shine: ColorRect = null
var loader: Loader = null
var embers: CPUParticles2D = null
var hint: Label = null
var tap: Control = null
## Échelle du logo par rapport à boot.png (même calcul que le moteur en « keep »).
var frame_scale: float = 1.0
## Taille de police du logotype (px de l'écran).
var title_size: int = 100

## 0 = première image (voile plein écran, logo centré) ; 1 = composition finale.
var reveal: float = 0.0:
	set(v):
		reveal = v
		_layout()
## Entrée du bandeau violet (0 = hors écran à droite) et du liseré.
var slab_in: float = 0.0:
	set(v):
		slab_in = v
		_layout()
var stripe_in: float = 0.0:
	set(v):
		stripe_in = v
		_layout()

var _timeline: Tween = null
var _loops: Array[Tween] = []
var _done: bool = false
var _elapsed: float = 0.0
var _loading: bool = false
var _built_size: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuKit.apply_saved_settings()
	_build()
	resized.connect(_layout)
	_layout()
	if frozen:
		set_process(false)
		return
	if auto_advance and ResourceLoader.load_threaded_request(next_scene) == OK:
		_loading = true
	_play()


# --- Construction -------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = MenuKit.NIGHT   # = application/boot_splash/bg_color
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Fond vivant : le camp du menu principal (héros, feu, drapeau, poussière)
	lobby = LobbyScene.new()
	add_child(lobby)
	if lobby.hero_hit != null:
		lobby.hero_hit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Assombrissement à droite et en bas (lisibilité du logo et de l'invite)
	shade = TextureRect.new()
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color(MenuKit.NIGHT, 0.0))
	g.set_color(1, Color(MenuKit.NIGHT, Balance.get_float("menu", "splash_shade", 0.55)))
	g.add_point(0.45, Color(MenuKit.NIGHT, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0.15, 0.2)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 64
	gt.height = 64
	shade.texture = gt
	add_child(shade)
	# Bandeau violet translucide (verre dépoli) + liseré violet vif, comme le menu
	slab = Slab.new()
	slab.color = Color(MenuKit.VIOLET, Balance.get_float("menu", "splash_slab_alpha", 0.6))
	MenuKit.frosted(slab)
	add_child(slab)
	stripe = Slab.new()
	stripe.color = Color(MenuKit.VIOLET_LIGHT, 0.95)
	add_child(stripe)
	embers = CPUParticles2D.new()
	embers.amount = 28
	embers.lifetime = 3.2
	embers.preprocess = 2.0
	embers.texture = GLOW
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.direction = Vector2(0.2, -1)
	embers.spread = 18.0
	embers.gravity = Vector2(14, -10)
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 95.0
	embers.scale_amount_min = 0.02
	embers.scale_amount_max = 0.05
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.6, 0.2, 0.0))
	ramp.add_point(0.2, Color(1.0, 0.66, 0.3, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.75, 0.45, 1.0, 0.0))
	embers.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.material = add
	embers.emitting = false
	add_child(embers)
	# Voile encre : plein écran à la première image, puis plaque biseautée derrière le logo
	curtain = Curtain.new()
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuKit.frosted(curtain)
	add_child(curtain)
	logo = Control.new()
	logo.name = "Logo"
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(logo)
	wordmark = Wordmark.new()
	wordmark.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	logo.add_child(wordmark)
	# reflet : bande claire inclinée, visible seulement sur le logotype (clip_children)
	shine = ColorRect.new()
	shine.color = Color(1, 1, 1, 0.5)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.rotation = 0.38
	shine.visible = false
	wordmark.add_child(shine)
	loader = Loader.new()
	loader.modulate.a = 0.0
	logo.add_child(loader)
	hint = MenuKit.label("Touchez pour continuer", 17, Color(1, 1, 1, 0.62), MenuKit.nunito(500))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.0
	add_child(hint)
	# capte le toucher / clic partout (au-dessus du fond vivant, qui a ses zones cliquables)
	tap = Control.new()
	tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap.mouse_filter = Control.MOUSE_FILTER_STOP
	tap.gui_input.connect(_on_tap)
	add_child(tap)


## (Re)construit le logo à la taille voulue (au redimensionnement seulement).
func _build_logo(fs: int) -> void:
	if fs == _built_size:
		return
	_built_size = fs
	title_size = fs
	wordmark.setup(fs)
	shine.size = Vector2(fs * 0.32, wordmark.size.y * 2.2)
	loader.position = Vector2(wordmark.text_x, wordmark.size.y + fs * 0.3)
	loader.size = Vector2(wordmark.size.x - wordmark.text_x, maxf(3.0, fs * 0.035))
	logo.size = Vector2(wordmark.size.x, loader.position.y + loader.size.y)
	logo.pivot_offset = wordmark.size * 0.5


# --- Mise en page -------------------------------------------------------------------

func _layout() -> void:
	var vp: Vector2 = size
	if vp.x <= 0.0 or vp.y <= 0.0 or logo == null:
		return
	frame_scale = minf(vp.x / REF.x, vp.y / REF.y)
	_build_logo(maxi(24, roundi(Balance.get_float("menu", "splash_logo_size", 150.0) * frame_scale)))
	var fs: float = float(title_size)
	var wm: Vector2 = wordmark.size
	# Logotype : centré à la première image, à droite du héros à la fin
	var start := (vp - wm) * 0.5
	var m: Vector4 = MenuKit.safe_margins(self)
	var pad := Vector2(fs * 0.42, fs * 0.3)
	var skew: float = fs * 0.22
	var plate_size := Vector2(logo.size.x + pad.x * 2.0 + skew, logo.size.y + pad.y * 2.0)
	var cx: float = vp.x * Balance.get_float("menu", "splash_logo_x", 0.71)
	cx = minf(cx, vp.x - maxf(m.z, vp.x * 0.03) - plate_size.x * 0.5)
	var plate_pos := Vector2(cx - plate_size.x * 0.5, vp.y * Balance.get_float("menu", "splash_logo_y", 0.44) - plate_size.y * 0.5)
	var final := plate_pos + pad + Vector2(skew * 0.5, 0.0)
	var e: float = _ease(reveal)
	logo.position = start.lerp(final, e)
	# Voile : rectangle plein écran → parallélogramme (plaque) autour du logo
	var full := PackedVector2Array([Vector2(-2, -2), Vector2(vp.x + 2, -2), vp + Vector2(2, 2), Vector2(-2, vp.y + 2)])
	var pr := Rect2(plate_pos, plate_size)
	var plate := PackedVector2Array([pr.position + Vector2(skew, 0), Vector2(pr.end.x, pr.position.y),
		pr.end - Vector2(skew, 0), Vector2(pr.position.x, pr.end.y)])
	# coins décalés : le bord gauche part en premier (haut avant bas) → balayage en biais
	var lead := [1.5, 1.0, 1.0, 1.25]
	var pts := PackedVector2Array()
	for i: int in 4:
		pts.append(full[i].lerp(plate[i], _ease(clampf(reveal * lead[i], 0.0, 1.0))))
	curtain.points = pts
	curtain.shadow = Vector2(fs * 0.08, fs * 0.12) * e
	curtain.color = Color(MenuKit.NIGHT, lerpf(1.0, Balance.get_float("menu", "splash_plate_alpha", 0.82), e))
	curtain.edge = clampf(e * 1.4 - 0.4, 0.0, 1.0)
	curtain.edge_width = maxf(4.0, fs * 0.06)
	curtain.queue_redraw()
	# Bandeau violet pleine hauteur à droite (bord gauche en biais), glisse depuis la droite
	var slab_w: float = vp.x * Balance.get_float("menu", "splash_slab_ratio", 0.38)
	var cut: float = Balance.get_float("menu", "lobby_slab_cut", 64.0) * vp.y / 720.0 * 1.6
	slab.cut = cut
	slab.size = Vector2(slab_w + cut, vp.y)
	slab.position = Vector2(vp.x - slab_w + (1.0 - slab_in) * (slab_w + cut * 1.2), 0)
	slab.visible = slab_in > 0.0
	var sw: float = maxf(6.0, fs * 0.09)
	stripe.cut = cut
	stripe.band = sw
	stripe.size = Vector2(sw + cut, vp.y)
	stripe.position = Vector2(vp.x - slab_w - sw - fs * 0.22 + (1.0 - stripe_in) * (slab_w + cut * 2.0), 0)
	stripe.visible = stripe_in > 0.0
	embers.position = Vector2(vp.x * 0.62, vp.y + 6.0)
	embers.emission_rect_extents = Vector2(vp.x * 0.4, 8)
	hint.size = Vector2(slab_w - cut * 0.5, 24)
	hint.position = Vector2(vp.x - hint.size.x, vp.y - maxf(m.w, 16.0) - 30.0)


## Courbe du repli du voile et du glissement du logo.
static func _ease(t: float) -> float:
	return ease(clampf(t, 0.0, 1.0), -3.2)


# --- Animation ----------------------------------------------------------------------

func _play() -> void:
	var total: float = Balance.get_float("menu", "splash_duration", 2.8)
	var hold: float = Balance.get_float("menu", "splash_hold", 0.18)
	var open_t: float = Balance.get_float("menu", "splash_reveal_time", 0.75)
	# Pas de fondu d'entrée : la première image est identique au boot splash natif.
	_timeline = create_tween()
	_timeline.tween_interval(hold)
	_timeline.tween_callback(func() -> void:
		MenuKit.sfx(&"mask_power", -6.0)
		lobby.play_intro(1.6))
	_timeline.tween_property(self, "reveal", 1.0, open_t)
	_timeline.parallel().tween_property(self, "slab_in", 1.0, 0.6).set_delay(open_t * 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_property(self, "stripe_in", 1.0, 0.55).set_delay(open_t * 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_timeline.parallel().tween_callback(func() -> void: embers.emitting = true).set_delay(open_t * 0.5)
	# barre de chargement, puis reflet sur le logotype
	_timeline.tween_property(loader, "modulate:a", 1.0, 0.3)
	_timeline.tween_callback(func() -> void:
		shine.visible = true
		shine.position = Vector2(-shine.size.x * 2.0, -wordmark.size.y * 0.6))
	_timeline.tween_property(shine, "position:x", wordmark.size.x + shine.size.x, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_timeline.parallel().tween_property(hint, "modulate:a", 1.0, 0.45)
	_timeline.tween_callback(func() -> void: shine.visible = false)
	# légère respiration du logo et du bandeau
	var b := create_tween().set_loops()
	b.tween_property(logo, "scale", Vector2.ONE * 1.012, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	b.tween_property(logo, "scale", Vector2.ONE, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_loops.append(b)
	var h := create_tween().set_loops()
	h.tween_property(hint, "self_modulate:a", 0.45, 0.9).set_delay(1.6)
	h.tween_property(hint, "self_modulate:a", 1.0, 0.9)
	_loops.append(h)
	set_process(true)


## Progression affichée par la barre : le plus lent du temps écoulé et du chargement du menu.
func load_progress() -> float:
	var total: float = Balance.get_float("menu", "splash_duration", 2.8)
	var p: float = clampf(_elapsed / maxf(total, 0.1), 0.0, 1.0)
	if _loading:
		var arr: Array = []
		var st := ResourceLoader.load_threaded_get_status(next_scene, arr)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			p = minf(p, float(arr[0]) if not arr.is_empty() else 0.0)
	return p


func _process(delta: float) -> void:
	_elapsed += delta
	var p := load_progress()
	loader.progress = maxf(loader.progress, p)
	if auto_advance and p >= 1.0 and loader.modulate.a >= 1.0:
		finish()


## Passe au menu principal (tap, touche, ou fin de l'animation).
func finish() -> void:
	if _done:
		return
	_done = true
	set_process(false)
	if _timeline != null and _timeline.is_valid():
		_timeline.kill()
	for t: Tween in _loops:
		if t != null and t.is_valid():
			t.kill()
	# menu déjà chargé en tâche de fond : on le récupère (sinon change_scene attend la fin du chargement)
	if _loading and ResourceLoader.load_threaded_get_status(next_scene) == ResourceLoader.THREAD_LOAD_LOADED:
		set_meta(&"_next", ResourceLoader.load_threaded_get(next_scene))
	var d: float = Balance.get_float("menu", "fade_time", 0.3) + 0.1
	var tw := create_tween().set_parallel()
	tw.tween_property(logo, "modulate:a", 0.0, d * 0.8)
	tw.tween_property(hint, "modulate:a", 0.0, d * 0.5)
	MenuKit.go_to(self, next_scene, d)


func _on_tap(event: InputEvent) -> void:
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		tap.accept_event()
		if not frozen:
			finish()


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) \
			or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed):
		get_viewport().set_input_as_handled()
		finish()


# --- Éléments dessinés ----------------------------------------------------------------

## Parallélogramme plein, bord gauche en biais (bandeau du menu) ; `band` > 0 : bande de cette
## largeur aux deux bords parallèles (liseré).
class Slab extends Control:
	var cut: float = 64.0
	var band: float = 0.0
	var color: Color = Color(MenuKit.VIOLET, 0.6)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if band > 0.0:
			draw_colored_polygon(PackedVector2Array([Vector2(cut, 0), Vector2(cut + band, 0),
				Vector2(band, size.y), Vector2(0, size.y)]), color)
			return
		draw_colored_polygon(PackedVector2Array([Vector2(cut, 0), Vector2(size.x, 0), size, Vector2(0, size.y)]), color)


## Voile encre (4 sommets) + liseré violet sur son bord gauche une fois replié en plaque.
class Curtain extends Control:
	var points: PackedVector2Array = PackedVector2Array()
	var color: Color = MenuKit.NIGHT
	var edge: float = 0.0
	var edge_width: float = 6.0
	var shadow: Vector2 = Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if points.size() < 4:
			return
		if shadow != Vector2.ZERO:
			var sh := PackedVector2Array()
			for p: Vector2 in points:
				sh.append(p + shadow)
			draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
		draw_colored_polygon(points, color)
		if edge > 0.0:
			# liseré : bande violette collée au bord gauche (en biais) de la plaque
			var a: Vector2 = points[0]
			var b: Vector2 = points[3]
			var w := Vector2(edge_width, 0)
			var top: Vector2 = b.lerp(a, edge)
			draw_colored_polygon(PackedVector2Array([b, top, top + w, b + w]), MenuKit.VIOLET)


## Logotype « RAIDERSGO » direction D : insigne (carré violet biseauté, viseur blanc dont une flèche
## de sortie s'échappe), « RAIDERS » en
## Anton blanc, « GO » en violet clair. Hauteur = hauteur des capitales.
class Wordmark extends Control:
	## Hauteur des capitales d'Anton (fraction de la taille de police).
	const CAP := 0.865
	var fs: int = 100
	var emblem_rect: Rect2 = Rect2()
	var text_x: float = 0.0
	var _w_raiders: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(font_size: int) -> void:
		fs = font_size
		var font: Font = MenuKit.display()
		var cap: float = roundf(fs * CAP)
		emblem_rect = Rect2(Vector2.ZERO, Vector2(cap, cap))
		text_x = cap + roundf(fs * 0.16)
		_w_raiders = font.get_string_size(RaidersLogo.TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var w_go: float = font.get_string_size(RaidersLogo.GO, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		size = Vector2(text_x + _w_raiders + w_go, cap)
		queue_redraw()

	func _draw() -> void:
		var font: Font = MenuKit.display()
		var c: float = emblem_rect.size.x * 0.24
		var r := emblem_rect
		draw_colored_polygon(PackedVector2Array([r.position + Vector2(0, c), r.position + Vector2(c, 0),
			Vector2(r.end.x, r.position.y), r.end - Vector2(0, c), r.end - Vector2(c, 0),
			Vector2(r.position.x, r.end.y)]), MenuKit.VIOLET)
		_draw_reticle(r)
		var base: float = size.y
		draw_string(font, Vector2(text_x, base), RaidersLogo.TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MenuKit.TEXT)
		draw_string(font, Vector2(text_x + _w_raiders, base), RaidersLogo.GO, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MenuKit.VIOLET_LIGHT)


	## Viseur ouvert en haut à droite, flèche de sortie qui s'en échappe (aplat blanc).
	func _draw_reticle(r: Rect2) -> void:
		var s: float = r.size.x
		var c: Vector2 = r.get_center()
		var rad: float = s * 0.27
		var w: float = maxf(2.0, s * 0.075)
		var col: Color = MenuKit.TEXT
		draw_arc(c, rad, -PI * 0.08, PI * 1.58, 40, col, w, true)
		for ang: float in [PI, PI * 0.5, -PI * 0.5]:
			var d := Vector2.from_angle(ang)
			draw_line(c + d * (rad - s * 0.1), c + d * (rad + s * 0.1), col, w * 0.8, true)
		draw_circle(c, s * 0.04, col)
		var dir := Vector2.from_angle(-PI * 0.25)
		var n := Vector2(-dir.y, dir.x)
		var tip: Vector2 = c + dir * s * 0.4
		var head: float = s * 0.16
		var base: Vector2 = tip - dir * head
		draw_line(c + dir * s * 0.08, base, col, w, true)
		draw_colored_polygon(PackedVector2Array([tip, base + n * head * 0.62, base - n * head * 0.62]), col)


class Loader extends Control:
	var progress: float = 0.0:
		set(v):
			progress = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * progress, size.y)), MenuKit.VIOLET_LIGHT)
