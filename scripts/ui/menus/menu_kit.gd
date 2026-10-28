class_name MenuKit
extends RefCounted
## Boîte à outils des menus (charte de la planche de référence) :
## polices Rye / Nunito, panneaux bleu nuit aux coins arrondis, gros boutons tactiles
## (retour de pression, survol PC, focus manette/clavier), transitions en fondu,
## marges de sécurité (encoche), réglages joueur (volumes, vibrations).
## Aucun _process : toutes les animations passent par des Tween.

const RYE: FontFile = preload("res://assets/fonts/rye/Rye-Regular.ttf")
const NUNITO: FontFile = preload("res://assets/fonts/nunito/Nunito-Variable.ttf")

const NIGHT := Color(0.071, 0.102, 0.18)            # #121a2e
const NIGHT_PANEL := Color(0.071, 0.102, 0.18, 0.9)
const NIGHT_DEEP := Color(0.035, 0.05, 0.1)
const BORDER := Color(0.85, 0.88, 0.95, 0.35)
const TEXT := Color(1.0, 0.98, 0.95)
const TEXT_DIM := Color(0.78, 0.8, 0.86)
const GOLD := Color(0.98, 0.78, 0.45)
const RED := Color(0.78, 0.13, 0.17)
const RED_DARK := Color(0.42, 0.05, 0.09)

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const MASK_SELECT_SCENE := "res://scenes/ui/menus/mask_select.tscn"
const MAP_SELECT_SCENE := "res://scenes/ui/menus/map_select.tscn"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"

enum Style { PRIMARY, SECONDARY, GHOST }

static var _font_cache: Dictionary = {}


# --- Polices ----------------------------------------------------------------------

## Nunito à la graisse donnée (200..1000), mise en cache.
static func nunito(weight: int = 700) -> Font:
	var key: String = "n%d" % weight
	if _font_cache.has(key):
		return _font_cache[key]
	var fv := FontVariation.new()
	fv.base_font = NUNITO
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	fv.variation_opentype = {tag: weight}
	_font_cache[key] = fv
	return fv


static func label(text: String, size: int, color: Color = TEXT, font: Font = null, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font != null else nunito(700))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08, 0.9))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Titre western (Rye) avec ombre portée.
static func title(text: String, size: int, color: Color = TEXT) -> Label:
	var l := label(text, size, color, RYE, maxi(4, size / 10))
	l.add_theme_color_override("font_shadow_color", Color(0.05, 0.02, 0.08, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 16))
	return l


# --- Styles -----------------------------------------------------------------------

static func panel_style(bg: Color = NIGHT_PANEL, border: Color = BORDER, radius: int = 18,
		border_w: int = 1, margin: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0.0, 0.0, 0.05, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


static func panel(bg: Color = NIGHT_PANEL, radius: int = 18, margin: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, BORDER, radius, 1, margin))
	return p


static func _button_box(bg: Color, border: Color, bottom: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.border_width_bottom = bottom
	s.set_corner_radius_all(radius)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 10
	s.content_margin_bottom = 10 + bottom - 2
	s.anti_aliasing = true
	return s


## Gros bouton tactile stylé. Retours : survol (éclairci + léger agrandissement),
## pression (écrasement), focus (liseré or), son + vibration au clic.
static func button(text: String, style: Style = Style.SECONDARY, font_size: int = 28,
		min_size: Vector2 = Vector2(300, 74)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", nunito(900))
	b.add_theme_font_size_override("font_size", font_size)
	var base: Color
	var edge: Color
	match style:
		Style.PRIMARY:
			base = RED
			edge = Color(1.0, 0.62, 0.5, 0.9)
		Style.GHOST:
			base = Color(NIGHT, 0.55)
			edge = Color(1, 1, 1, 0.22)
		_:
			base = Color(0.11, 0.15, 0.27, 0.94)
			edge = Color(0.85, 0.88, 0.95, 0.45)
	var radius: int = 16
	var normal := _button_box(base, edge, 5, radius)
	normal.border_color = edge
	var hover := _button_box(base.lightened(0.14), edge.lightened(0.3), 5, radius)
	var pressed := _button_box(base.darkened(0.2), edge, 2, radius)
	pressed.content_margin_top = 13
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(radius + 3)
	focus.set_expand_margin_all(4)
	focus.anti_aliasing = true
	var disabled := _button_box(Color(base, 0.4), Color(edge, 0.3), 5, radius)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)
	for c: String in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, TEXT)
	b.add_theme_color_override("font_pressed_color", Color(TEXT, 0.85))
	b.add_theme_color_override("font_disabled_color", Color(TEXT, 0.4))
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08, 0.55))
	add_feedback(b)
	return b


## Retours tactiles/visuels communs à tout bouton (cartes comprises).
static func add_feedback(b: BaseButton, hover_scale: float = 1.04) -> void:
	var press_scale: float = Balance.get_float("menu", "button_press_scale", 0.94)
	b.resized.connect(func() -> void: b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			_scale_to(b, hover_scale, 0.12)
			sfx(&"hover", -12.0))
	b.mouse_exited.connect(func() -> void: _scale_to(b, 1.0, 0.15))
	b.focus_entered.connect(func() -> void: _scale_to(b, hover_scale, 0.12))
	b.focus_exited.connect(func() -> void: _scale_to(b, 1.0, 0.15))
	b.button_down.connect(func() -> void:
		_scale_to(b, press_scale, 0.06)
		vibrate())
	b.button_up.connect(func() -> void:
		_scale_to(b, hover_scale if b.is_hovered() or b.has_focus() else 1.0, 0.12))


static func _scale_to(c: Control, s: float, t: float) -> void:
	if not c.is_inside_tree():
		return
	var old: Variant = c.get_meta(&"_scale_tween") if c.has_meta(&"_scale_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(s, s), t)
	c.set_meta(&"_scale_tween", tw)


# --- Son, vibration, réglages -----------------------------------------------------

static func sfx(name: StringName, volume_db: float = 0.0) -> void:
	var am: Node = _autoload(&"AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.call("play_sfx", name, Vector2.INF, volume_db)


static func music(name: StringName) -> void:
	var am: Node = _autoload(&"AudioManager")
	if am != null and am.has_method("play_music"):
		am.call("play_music", name)


static func vibrate(ms: int = -1) -> void:
	if not get_setting(&"vibration", true):
		return
	if not (OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")):
		return
	Input.vibrate_handheld(ms if ms > 0 else int(Balance.get_value("menu", "vibration_ms", 18)))


## Réglages joueur, stockés dans SaveManager.data["settings"].
static func get_setting(key: StringName, default: Variant) -> Variant:
	var sm: Node = _autoload(&"SaveManager")
	if sm == null:
		return default
	var data: Dictionary = sm.get("data")
	var settings: Variant = data.get("settings", {})
	return (settings as Dictionary).get(String(key), default) if settings is Dictionary else default


static func set_setting(key: StringName, value: Variant, persist: bool = true) -> void:
	var sm: Node = _autoload(&"SaveManager")
	if sm == null:
		return
	var data: Dictionary = sm.get("data")
	if not (data.get("settings") is Dictionary):
		data["settings"] = {}
	(data["settings"] as Dictionary)[String(key)] = value
	if persist:
		sm.call("save")


## Applique les volumes sauvegardés à l'AudioManager (au lancement).
static func apply_saved_settings() -> void:
	var sm: Node = _autoload(&"SaveManager")
	if sm != null and (sm.get("data") as Dictionary).is_empty() and sm.has_method("load_save"):
		sm.call("load_save")
	var am: Node = _autoload(&"AudioManager")
	if am == null:
		return
	am.set("music_volume", float(get_setting(&"music_volume", am.get("music_volume"))))
	am.set("sfx_volume", float(get_setting(&"sfx_volume", am.get("sfx_volume"))))


static func _autoload(n: StringName) -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return null
	return loop.root.get_node_or_null(NodePath(String(n)))


# --- Mise en page -----------------------------------------------------------------

## Marges de sécurité (gauche, haut, droite, bas) en unités du viewport : zone sûre
## de l'écran (encoche, coins arrondis) + marge minimale de balance.cfg [menu].
static func safe_margins(node: Node) -> Vector4:
	var m: float = Balance.get_float("menu", "safe_margin", 32.0)
	var mv: float = Balance.get_float("menu", "safe_margin_v", 16.0)
	var out := Vector4(m, mv, m, mv)
	if node == null or not node.is_inside_tree():
		return out
	var win_size := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var screen := Vector2(DisplayServer.screen_get_size())
	if win_size.x <= 0.0 or screen.x <= 0.0 or safe.size.x <= 0 or not OS.has_feature("mobile"):
		return out
	var vp := node.get_viewport().get_visible_rect().size
	var k: Vector2 = vp / screen
	out.x = maxf(out.x, safe.position.x * k.x)
	out.y = maxf(out.y, safe.position.y * k.y)
	out.z = maxf(out.z, (screen.x - safe.end.x) * k.x)
	out.w = maxf(out.w, (screen.y - safe.end.y) * k.y)
	return out


## MarginContainer plein écran respectant la zone sûre.
static func safe_container(node: Node) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m: Vector4 = safe_margins(node)
	mc.add_theme_constant_override("margin_left", int(m.x))
	mc.add_theme_constant_override("margin_top", int(m.y))
	mc.add_theme_constant_override("margin_right", int(m.z))
	mc.add_theme_constant_override("margin_bottom", int(m.w))
	return mc


# --- Transitions ------------------------------------------------------------------

## Voile plein écran (CanvasLayer haut) ; renvoie le ColorRect.
static func make_fader(owner: Node, start_alpha: float) -> ColorRect:
	var layer := CanvasLayer.new()
	layer.name = "Fader"
	layer.layer = 100
	owner.add_child(layer)
	var r := ColorRect.new()
	r.color = Color(NIGHT_DEEP, start_alpha)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(r)
	return r


## Fondu d'entrée (depuis le bleu nuit).
static func fade_in(owner: Node, duration: float = -1.0) -> void:
	var d: float = duration if duration >= 0.0 else Balance.get_float("menu", "fade_time", 0.3)
	var r := make_fader(owner, 1.0)
	var tw := owner.create_tween()
	tw.tween_property(r, "color:a", 0.0, d)
	tw.tween_callback(r.get_parent().queue_free)


## Fondu de sortie puis changement de scène. Bloque les clics pendant le fondu.
static func go_to(owner: Node, scene_path: String, duration: float = -1.0) -> void:
	if owner.get_meta(&"_leaving", false):
		return
	owner.set_meta(&"_leaving", true)
	var d: float = duration if duration >= 0.0 else Balance.get_float("menu", "fade_time", 0.3)
	var r := make_fader(owner, 0.0)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	var tree := owner.get_tree()
	var tw := owner.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(r, "color:a", 1.0, d)
	tw.tween_callback(func() -> void:
		tree.paused = false
		tree.change_scene_to_file(scene_path))
