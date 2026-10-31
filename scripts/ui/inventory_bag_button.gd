class_name InventoryBagButton
extends Control
## Bouton « sac » (haut droite, à droite de la pause, au-dessus de la mini-carte) : ouvre l'écran
## d'inventaire. Direction D : encre translucide, coin haut gauche coupé (comme la pause),
## pictogramme de sac à dos vectoriel net, cases occupées « 17/24 » en Anton et jauge de
## remplissage dessous : claire, puis orange ([hud] bag_warn_ratio), rouge ([hud] bag_danger_ratio) ;
## sac plein : « PLEIN », contour et jauge rouges. Objet ajouté : rebond + « +N » qui monte et
## s'efface ([hud] bag_bump_scale, bag_plus_time).
## Redessiné uniquement sur Inventory.changed et pendant la courte animation d'ajout.

signal pressed

const SIZE := Vector2(68, 68)
const WARN := Color(1.0, 0.62, 0.2)
const DANGER := Color(1.0, 0.36, 0.32)
const ICON := Color(1.0, 1.0, 1.0, 0.95)

var inventory: Inventory = null
var _down: bool = false
var _pulse: Tween = null
var _plus: Tween = null
## Animation « +N » : 0 = départ, 1 = terminée.
var _plus_t: float = 1.0
var _plus_n: int = 0


func _ready() -> void:
	name = "BagButton"
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	bind(GameState.raid_inventory)


func bind(inv: Inventory) -> void:
	if inventory != null and inventory.changed.is_connected(queue_redraw):
		inventory.changed.disconnect(queue_redraw)
		inventory.item_added.disconnect(_on_added)
	inventory = inv
	if inventory != null:
		inventory.changed.connect(queue_redraw)
		inventory.item_added.connect(_on_added)
	queue_redraw()


## Remplissage 0..1 (cases occupées / capacité).
func fill_ratio() -> float:
	if inventory == null or inventory.capacity() <= 0:
		return 0.0
	return clampf(float(inventory.used_slots()) / float(inventory.capacity()), 0.0, 1.0)


func is_full() -> bool:
	return inventory != null and inventory.capacity() > 0 and inventory.used_slots() >= inventory.capacity()


## Couleur de la jauge et du compteur selon le remplissage.
func gauge_color() -> Color:
	var r := fill_ratio()
	if is_full() or r >= Balance.get_float("hud", "bag_danger_ratio", 0.9):
		return DANGER
	if r >= Balance.get_float("hud", "bag_warn_ratio", 0.75):
		return WARN
	return MenuKit.GOLD


## Texte affiché sous le sac (« 17/24 » ou « PLEIN »).
func count_text() -> String:
	if inventory == null:
		return ""
	return "PLEIN" if is_full() else "%d/%d" % [inventory.used_slots(), inventory.capacity()]


func is_plus_visible() -> bool:
	return _plus_t < 1.0


func _on_added(_it: ItemData, n: int) -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	scale = Vector2.ONE
	var s := Balance.get_float("hud", "bag_bump_scale", 1.14)
	_pulse = create_tween()
	_pulse.tween_property(self, "scale", Vector2(s, s), 0.08)
	_pulse.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_plus_n = (_plus_n + n) if is_plus_visible() else n
	if _plus != null and _plus.is_valid():
		_plus.kill()
	_set_plus(0.0)
	_plus = create_tween()
	_plus.tween_method(_set_plus, 0.0, 1.0, Balance.get_float("hud", "bag_plus_time", 0.7))


func _set_plus(t: float) -> void:
	_plus_t = t
	queue_redraw()


## Touches lues dans _input (avant les joysticks) ; souris réelle via _gui_input.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		var local := get_global_transform_with_canvas().affine_inverse() * (event as InputEventScreenTouch).position
		if Rect2(Vector2.ZERO, size).grow(8.0).has_point(local):
			get_viewport().set_input_as_handled()
			_fire()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			accept_event()
			_fire()


func _fire() -> void:
	_down = true
	queue_redraw()
	pressed.emit()
	get_tree().create_timer(0.1, true, false, true).timeout.connect(func() -> void:
		_down = false
		queue_redraw())


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var full := is_full()
	var col := gauge_color()
	# Fond : encre translucide, coin haut gauche coupé (comme le bouton pause).
	var st := CutBox.make(Color(MenuKit.VIOLET, 0.8) if _down else Color(MenuKit.NIGHT_DEEP, 0.72), size.x * 0.22,
		Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
	st.corners = CutBox.CUT_TOP_LEFT
	draw_style_box(st, r)
	if full and not _down:
		var pts := st.points(r.grow(-1.0))
		pts.append(pts[0])
		draw_polyline(pts, Color(DANGER, 0.9), 2.0, true)
	draw_backpack(self, Vector2(size.x * 0.5, size.y * 0.37), size.y * 0.42, ICON, Color(MenuKit.NIGHT_DEEP, 0.95))
	if inventory == null:
		return
	# Compteur (Anton) et jauge de remplissage.
	var font := LootVisuals.title_font()
	var txt := count_text()
	var fs := 15
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var at := Vector2((size.x - w) * 0.5, size.y - 12.0)
	var tc := col if (full or fill_ratio() >= Balance.get_float("hud", "bag_warn_ratio", 0.75)) else MenuKit.TEXT
	draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(MenuKit.NIGHT_DEEP, 0.9))
	draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
	var bar := Rect2(10.0, size.y - 8.0, size.x - 20.0, 3.0)
	draw_rect(bar, Color(1, 1, 1, 0.16))
	var k := fill_ratio()
	if k > 0.0:
		draw_rect(Rect2(bar.position, Vector2(maxf(bar.size.x * k, 2.0), bar.size.y)), col)
	# « +N » : monte et s'efface (seulement pendant l'animation).
	if is_plus_visible() and _plus_n > 0:
		var pt := "+%d" % _plus_n
		var e := 1.0 - pow(1.0 - _plus_t, 2.0)
		var a := 1.0 - smoothstep(0.55, 1.0, _plus_t)
		var pfs := 17
		var pw := font.get_string_size(pt, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs).x
		var pp := Vector2(size.x - pw - 4.0, 24.0 - 9.0 * e)
		draw_string_outline(font, pp, pt, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, 5, Color(MenuKit.NIGHT_DEEP, 0.9 * a))
		draw_string(font, pp, pt, HORIZONTAL_ALIGNMENT_LEFT, -1, pfs, Color(DANGER if full else MenuKit.GOLD, a))


## Pictogramme de sac à dos (tracés vectoriels anti-crénelés) centré en `c`, hauteur `h`.
static func draw_backpack(ci: CanvasItem, c: Vector2, h: float, col: Color, ink: Color) -> void:
	var w := h * 0.78
	# Poches latérales (bretelles), de part et d'autre du corps.
	for sx: float in [-1.0, 1.0]:
		var side := _round_rect(Rect2(c.x + sx * (w * 0.5 + h * 0.06) - h * 0.07, c.y - h * 0.02, h * 0.14, h * 0.36), h * 0.05, h * 0.05)
		ci.draw_colored_polygon(side, col)
	# Poignée (anse) au-dessus.
	ci.draw_arc(c + Vector2(0, -h * 0.42), h * 0.13, PI, TAU, 16, col, maxf(h * 0.07, 1.5), true)
	# Corps : rectangle aux coins arrondis (haut plus arrondi).
	var body := _round_rect(Rect2(c.x - w * 0.5, c.y - h * 0.4, w, h * 0.9), h * 0.22, h * 0.1)
	ci.draw_colored_polygon(body, col)
	var loop := body.duplicate()
	loop.append(body[0])
	ci.draw_polyline(loop, col, 1.0, true)
	# Rabat (ligne courbe) et poche avant.
	var flap := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		flap.append(c + Vector2(lerpf(-w * 0.5, w * 0.5, t), -h * 0.06 + sin(t * PI) * h * 0.1))
	ci.draw_polyline(flap, ink, maxf(h * 0.06, 1.2), true)
	var pocket := _round_rect(Rect2(c.x - w * 0.3, c.y + h * 0.14, w * 0.6, h * 0.26), h * 0.06, h * 0.06)
	var pl := pocket.duplicate()
	pl.append(pocket[0])
	ci.draw_polyline(pl, ink, maxf(h * 0.06, 1.2), true)
	# Boucle du rabat.
	ci.draw_rect(Rect2(c + Vector2(-h * 0.05, h * 0.0), Vector2(h * 0.1, h * 0.09)), ink)


## Contour d'un rectangle à coins arrondis (rayon haut `rt`, rayon bas `rb`).
static func _round_rect(r: Rect2, rt: float, rb: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - rt, r.position.y + rt), rt, -PI * 0.5],
		[Vector2(r.end.x - rb, r.end.y - rb), rb, 0.0],
		[Vector2(r.position.x + rb, r.end.y - rb), rb, PI * 0.5],
		[Vector2(r.position.x + rt, r.position.y + rt), rt, PI],
	]
	for cn: Array in corners:
		for i in 6:
			var a: float = float(cn[2]) + PI * 0.5 * float(i) / 5.0
			pts.append((cn[0] as Vector2) + Vector2(cos(a), sin(a)) * float(cn[1]))
	return pts
