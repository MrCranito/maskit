class_name MenuKit
extends RefCounted
## Boîte à outils des menus de RaidersGo (direction « D ») :
## titres en Anton (capitales condensées), texte en Space Grotesk, fond encre, accent violet,
## panneaux à angles vifs, boutons à coins coupés (CutBox), gros boutons tactiles
## (retour de pression, survol PC, focus manette/clavier), transitions en fondu,
## marges de sécurité (encoche), réglages joueur (volumes, vibrations).
## Aucun _process : toutes les animations passent par des Tween.

const RYE: FontFile = preload("res://assets/fonts/rye/Rye-Regular.ttf")
const NUNITO: FontFile = preload("res://assets/fonts/nunito/Nunito-Variable.ttf")
const ANTON: FontFile = preload("res://assets/fonts/anton/Anton-Regular.ttf")
const SPACE: FontFile = preload("res://assets/fonts/space_grotesk/SpaceGrotesk-Variable.ttf")

const NIGHT := Color(0.035, 0.035, 0.07)           # encre (direction D)
const NIGHT_PANEL := Color(0.024, 0.027, 0.05, 0.85)
const NIGHT_DEEP := Color(0.02, 0.02, 0.04)
const BORDER := Color(1.0, 1.0, 1.0, 0.16)
const TEXT := Color(1.0, 1.0, 1.0)
const TEXT_DIM := Color(1.0, 1.0, 1.0, 0.62)
## Accent clair (historiquement « or ») : sélection, focus, liens.
const GOLD := Color(0.718, 0.608, 1.0)              # #B79BFF
const VIOLET := Color(0.486, 0.302, 1.0)            # #7C4DFF : action principale, bandeaux
const VIOLET_LIGHT := Color(0.616, 0.482, 1.0)      # #9D7BFF
## Couleur de la pièce d'or (monnaie), distincte de l'accent.
const COIN := Color(0.949, 0.757, 0.306)            # #F2C14E
const RED := Color(0.78, 0.13, 0.17)
const RED_DARK := Color(0.42, 0.05, 0.09)

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const MAP_SELECT_SCENE := "res://scenes/ui/menus/map_select.tscn"
const LOADOUT_SCENE := "res://scenes/ui/menus/loadout.tscn"
const ARSENAL_SCENE := "res://scenes/ui/menus/arsenal.tscn"
const SHOP_SCENE := "res://scenes/ui/menus/shop.tscn"
const RAID_SCENE := "res://scenes/dungeon/raid.tscn"
const BATTLE_PASS_SCENE := "res://scenes/ui/menus/battle_pass.tscn"
const PROGRESSION_SCENE := "res://scenes/ui/menus/progression.tscn"
## Écrans des autres modules (créés en parallèle : bouton « Bientôt » tant qu'ils manquent).
const MERCHANT_SCENE := "res://scenes/ui/menus/merchant.tscn"
const CRAFTING_SCENE := "res://scenes/ui/menus/crafting.tscn"
const COOP_SCENE := "res://scenes/ui/menus/coop_lobby.tscn"

enum Style { PRIMARY, SECONDARY, GHOST }

static var _font_cache: Dictionary = {}


# --- Polices ----------------------------------------------------------------------

## Police de texte (Space Grotesk) à la graisse donnée, ramenée dans 300..700 ; mise en cache.
## (Nom historique : l'interface utilisait Nunito.)
static func nunito(weight: int = 700) -> Font:
	weight = clampi(weight, 300, 700)
	var key: String = "n%d" % weight
	if _font_cache.has(key):
		return _font_cache[key]
	var fv := FontVariation.new()
	fv.base_font = SPACE
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	fv.variation_opentype = {tag: weight}
	_font_cache[key] = fv
	return fv


## Police d'affichage (Anton) : titres, boutons, gros chiffres.
static func display() -> Font:
	return ANTON


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


## Titre : Anton en capitales, légère ombre portée.
static func title(text: String, size: int, color: Color = TEXT) -> Label:
	var l := label(text, size, color, ANTON)
	l.uppercase = true
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.03, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(1, size / 20))
	return l


# --- Styles -----------------------------------------------------------------------

const FROSTED_SHADER: Shader = preload("res://assets/shaders/frosted_panel.gdshader")
static var _frosted_mat: ShaderMaterial = null


## Verre dépoli : le fond derrière `ci` est flouté puis teinté de sa couleur (alpha = force de la
## teinte). Menus seulement ([menu] blur_enabled, blur_radius, blur_lod) ; rien si désactivé.
static func frosted(ci: CanvasItem) -> void:
	if ci == null or not bool(Balance.get_value("menu", "blur_enabled", true)):
		return
	if _frosted_mat == null:
		_frosted_mat = ShaderMaterial.new()
		_frosted_mat.shader = FROSTED_SHADER
		_frosted_mat.set_shader_parameter("radius", Balance.get_float("menu", "blur_radius", 10.0))
		_frosted_mat.set_shader_parameter("lod", Balance.get_float("menu", "blur_lod", 2.5))
	ci.material = _frosted_mat


static func panel_style(bg: Color = NIGHT_PANEL, border: Color = BORDER, radius: int = 18,
		border_w: int = 1, margin: int = 18) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(mini(radius, 2))   # direction D : angles vifs
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0.0, 0.0, 0.03, 0.3)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	return s


static func panel(bg: Color = NIGHT_PANEL, radius: int = 18, margin: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, BORDER, radius, 1, margin))
	return p


static func _button_box(bg: Color, border: Color, bottom: int, _radius: int) -> CutBox:
	var s := CutBox.make(bg, 12.0, border, 1.5 if border.a > 0.0 else 0.0, 24.0, 8.0)
	s.content_margin_bottom = 8.0 + float(bottom - 2)
	return s


## Gros bouton tactile : coins coupés, libellé en Anton. Retours : survol (éclairci +
## léger agrandissement), pression (écrasement), focus (contour violet), son + vibration au clic.
static func button(text: String, style: Style = Style.SECONDARY, font_size: int = 28,
		min_size: Vector2 = Vector2(300, 74)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", ANTON)
	b.add_theme_font_size_override("font_size", font_size)
	var base: Color
	var edge: Color
	match style:
		Style.PRIMARY:
			base = VIOLET
			edge = Color(0, 0, 0, 0)
		Style.GHOST:
			base = Color(NIGHT_DEEP, 0.55)
			edge = Color(1, 1, 1, 0.35)
		_:
			base = Color(NIGHT_DEEP, 0.85)
			edge = Color(1, 1, 1, 0.28)
	var normal := _button_box(base, edge, 2, 0)
	var hover := _button_box(base.lightened(0.12), edge.lightened(0.3), 2, 0)
	var pressed := _button_box(base.darkened(0.2), edge, 2, 0)
	pressed.content_margin_top += 2.0
	var focus := CutBox.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.border_width = 2.5
	focus.cut = 14.0
	focus.grow = 4.0
	var disabled := _button_box(Color(base, 0.4), Color(edge, 0.3 * edge.a), 2, 0)
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
	if not c.is_inside_tree() or c.is_queued_for_deletion():
		return
	var old: Variant = c.get_meta(&"_scale_tween") if c.has_meta(&"_scale_tween") else null
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	if c.scale.is_equal_approx(Vector2(s, s)):
		c.remove_meta(&"_scale_tween")
		return
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


# --- Éléments partagés (arsenal, boutique, cartes) --------------------------------

const GEM := Color(0.36, 0.9, 1.0)
const GOOD := Color(0.45, 0.9, 0.5)
const BAD := Color(1.0, 0.45, 0.4)


## Raretés affichées (planches de référence) : Commun gris, Rare bleu, Épique violet,
## Légendaire or. « Peu commun » (index 1) n'est plus affiché : il apparaît comme Rare.
const RARITY_UI_COLORS: Array[Color] = [
	Color(0.56, 0.59, 0.64),  # Commun
	Color(0.2, 0.5, 0.96),    # (Peu commun → Rare)
	Color(0.2, 0.5, 0.96),    # Rare
	Color(0.6, 0.27, 0.96),   # Épique
	Color(0.96, 0.72, 0.18),  # Légendaire (or)
]
const RARITY_UI_NAMES: Array[String] = ["Commun", "Rare", "Rare", "Épique", "Légendaire"]


static func rarity_color(r: int) -> Color:
	return RARITY_UI_COLORS[clampi(r, 0, RARITY_UI_COLORS.size() - 1)]


static func rarity_name(r: int) -> String:
	return RARITY_UI_NAMES[clampi(r, 0, RARITY_UI_NAMES.size() - 1)]


## Cadre de rareté : fond bleu nuit teinté, bordure à la couleur de rareté,
## lueur pour Épique et Légendaire.
static func rarity_style(r: int, selected: bool = false, radius: int = 14) -> StyleBoxFlat:
	var c: Color = rarity_color(r)
	var s := panel_style(Color(0.1, 0.13, 0.23, 0.96).lerp(c.darkened(0.5), 0.16), Color(c, 0.95 if selected else 0.7),
		radius, 3 if selected else 2, 8)
	s.shadow_offset = Vector2.ZERO
	if r >= 3 or selected:
		s.shadow_color = Color(c, 0.5 if selected else 0.3)
		s.shadow_size = 12 if selected else 6
	else:
		s.shadow_color = Color(0, 0, 0.05, 0.3)
		s.shadow_size = 4
	return s


## Bouton « retour » (≥ 64 px de haut).
static func back_button(text: String = "Retour") -> Button:
	return button("‹  " + text, Style.GHOST, 22, Vector2(150, 64))


## Puce de filtre (bouton bascule) ; `accent` = couleur une fois activée.
static func chip(text: String, accent: Color = VIOLET, group: ButtonGroup = null) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_override("font", nunito(700))
	b.add_theme_font_size_override("font_size", 17)
	var off := CutBox.make(Color(NIGHT_DEEP, 0.75), 8.0, Color(1, 1, 1, 0.18), 1.0, 18.0, 4.0)
	var hov := CutBox.make(Color(1, 1, 1, 0.08), 8.0, Color(1, 1, 1, 0.3), 1.0, 18.0, 4.0)
	var on := CutBox.make(accent.darkened(0.25), 8.0, accent.lightened(0.35), 1.5, 18.0, 4.0)
	var focus := CutBox.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.border_width = 2.0
	focus.cut = 10.0
	focus.grow = 3.0
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", TEXT_DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	for c: String in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, TEXT)
	add_feedback(b, 1.03)
	return b


## Pastille arrondie avec texte (badge).
static func pill(txt: String, bg: Color, font_size: int = 14, fg: Color = TEXT, border: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(2)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 2
	s.content_margin_bottom = 3
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	s.anti_aliasing = true
	p.add_theme_stylebox_override("panel", s)
	var l := label(txt, font_size, fg, nunito(900))
	l.name = "Text"
	p.add_child(l)
	return p


## Défilement au doigt partout dans la liste (TouchScroller : glisser sur un bouton = défiler sans
## cliquer, inertie ; tap = clic) + barres de défilement fines et discrètes. Idempotent.
static func make_touch_scroll(scroll: ScrollContainer) -> TouchScroller:
	if scroll == null:
		return null
	var existing := scroll.get_node_or_null(^"TouchScroller") as TouchScroller
	if existing != null:
		return existing
	var ts := TouchScroller.new()
	ts.name = "TouchScroller"
	scroll.add_child(ts, false, Node.INTERNAL_MODE_BACK)
	scroll.scroll_deadzone = 0   # le seuil est géré par TouchScroller
	for bar: ScrollBar in [scroll.get_v_scroll_bar(), scroll.get_h_scroll_bar()]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(1, 1, 1, 0.05)
		track.set_corner_radius_all(3)
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(1, 1, 1, 0.28)
		grab.set_corner_radius_all(3)
		var grab_h := grab.duplicate() as StyleBoxFlat
		grab_h.bg_color = Color(MenuKit.GOLD, 0.6)
		if bar is VScrollBar:
			track.content_margin_left = 3
			track.content_margin_right = 3
		else:
			track.content_margin_top = 3
			track.content_margin_bottom = 3
		bar.add_theme_stylebox_override("scroll", track)
		bar.add_theme_stylebox_override("scroll_focus", track)
		bar.add_theme_stylebox_override("grabber", grab)
		bar.add_theme_stylebox_override("grabber_highlight", grab_h)
		bar.add_theme_stylebox_override("grabber_pressed", grab_h)
	return ts


## Restyle d'un bouton existant (marges horizontales réduites : petits boutons).
static func tighten(b: Button, h_margin: int = 14) -> void:
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := b.get_theme_stylebox(st)
		if sb != null and not (sb is StyleBoxEmpty):
			var d := sb.duplicate() as StyleBox
			d.content_margin_left = h_margin
			d.content_margin_right = h_margin
			b.add_theme_stylebox_override(st, d)


## Bandeau de rareté (bas des cartes d'arme et de skin) : fond à la couleur de rareté,
## nom centré. `round_bottom` : arrondi bas (bandeau collé au bas d'une carte arrondie).
static func rarity_band(r: int, font_size: int = 15, height: float = 28.0, round_bottom: int = 0) -> PanelContainer:
	var c: Color = rarity_color(r)
	var p := PanelContainer.new()
	p.name = "RarityBand"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(0, height)
	var s := StyleBoxFlat.new()
	s.bg_color = c.darkened(0.12) if r < 4 else c.darkened(0.05)
	s.corner_radius_bottom_left = mini(round_bottom, 0)
	s.corner_radius_bottom_right = mini(round_bottom, 0)
	s.border_color = c.lightened(0.3)
	s.border_width_top = 1
	s.anti_aliasing = true
	p.add_theme_stylebox_override("panel", s)
	var l := label(rarity_name(r), font_size, TEXT if r != 4 else Color(0.16, 0.1, 0.02), nunito(900))
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


## Fond de carte façon planche : bleu nuit avec un halo radial à la couleur de rareté
## (plus fort pour Épique et Légendaire).
static func rarity_backdrop(r: int) -> TextureRect:
	var c: Color = rarity_color(r)
	var strength: float = [0.28, 0.42, 0.42, 0.55, 0.6][clampi(r, 0, 4)]
	var g := Gradient.new()
	g.set_color(0, Color(c, strength))
	g.add_point(0.55, Color(c.darkened(0.5), strength * 0.45))
	g.set_color(g.get_point_count() - 1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42)
	gt.fill_to = Vector2(1.15, 1.1)
	gt.width = 64
	gt.height = 64
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
