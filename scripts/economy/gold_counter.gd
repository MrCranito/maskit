class_name GoldCounter
extends PanelContainer
## Compteur de pièces d'or (pastille encre soulignée, direction D : pièce dessinée + nombre). Se met à jour sur
## Profile.gold_changed ; le total défile jusqu'à la nouvelle valeur (Tween, pas de _process).
## `pressed` : tap (ex. ouvrir le marchand).

signal pressed

const GOLD_COIN := Color(1.0, 0.78, 0.25)

var value_label: Label = null
var shown: int = -1
var _anim: float = 0.0
var _tw: Tween = null


func _init(font_size: int = 24) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", MenuKit.currency_style(MenuKit.COIN))
	custom_minimum_size = Vector2(0, 60)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var icon := CoinIcon.new()
	icon.custom_minimum_size = Vector2(font_size + 8, font_size + 8)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	value_label = MenuKit.label("0", font_size, MenuKit.TEXT, MenuKit.nunito(700), 0)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value_label)
	tooltip_text = "Pièces d'or : vends ton butin au marchand, achète des armes à l'armurerie"


func _ready() -> void:
	_anim = Balance.get_float("economy", "gold_anim_time", 0.6)
	Profile.gold_changed.connect(_on_gold)
	refresh(false)


func refresh(animate: bool = true) -> void:
	_on_gold(Profile.gold, animate)


func _on_gold(g: int, animate: bool = true) -> void:
	if value_label == null:
		return
	var old: int = shown
	if _tw != null and _tw.is_valid():
		_tw.kill()
	if not animate or old < 0 or old == g or not is_inside_tree():
		_set_shown(g)
		return
	# Défilement du total + petit rebond, vert si gain, rouge si dépense.
	value_label.add_theme_color_override("font_color", MenuKit.GOOD if g > old else MenuKit.BAD)
	pivot_offset = size * 0.5
	_tw = create_tween()
	_tw.tween_method(func(v: float) -> void: _set_shown(int(round(v))), float(old), float(g), _anim) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(self, "scale", Vector2.ONE, 0.3).from(Vector2(1.12, 1.12)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_callback(func() -> void:
		_set_shown(g)
		value_label.add_theme_color_override("font_color", MenuKit.TEXT))


func _set_shown(v: int) -> void:
	shown = v
	value_label.text = DevMode.SYMBOL if DevMode.is_unlimited() else Economy.fmt(v)


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed):
		accept_event()
		MenuKit.sfx(&"click_soft")
		pressed.emit()


## Pièce d'or dessinée (disque doré, liseré, reflet, étoile gravée). Statique.
class CoinIcon extends Control:
	var tint: Color = GOLD_COIN
	## false : toujours le dessin en code (comparaisons, tests du repli).
	var use_art: bool = true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var c := size * 0.5
		var tex := CurrencyArt.coin() if use_art else null
		if tex != null:   # image peinte (rendu Blender) ; sinon le dessin en code ci-dessous
			var k: float = s * CurrencyArt.ICON_ZOOM
			CurrencyArt.draw_fit(self, tex, Rect2(c - Vector2(k, k) * 0.5, Vector2(k, k)))
			return
		var r := s * 0.46
		draw_circle(c + Vector2(0, s * 0.04), r, tint.darkened(0.55), true, -1.0, true)
		draw_circle(c, r, tint.darkened(0.15), true, -1.0, true)
		draw_circle(c, r * 0.78, tint, true, -1.0, true)
		draw_arc(c, r * 0.78, 0.0, TAU, 28, tint.darkened(0.35), maxf(1.0, s * 0.05), true)
		var pts := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + TAU * float(i) / 10.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r * (0.44 if i % 2 == 0 else 0.2)))
		draw_colored_polygon(pts, tint.darkened(0.3))
		draw_arc(c, r, PI * 1.1, PI * 1.45, 10, Color(1, 1, 1, 0.75), maxf(1.0, s * 0.06), true)
		draw_arc(c, r, 0.0, TAU, 32, Color(0.2, 0.12, 0.02, 0.9), maxf(1.0, s * 0.05), true)
