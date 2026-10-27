class_name BuildingRoof
extends Node2D
## Toit d'un bâtiment (z_index 50) : masque l'intérieur vu de la rue et porte la
## fausse façade (« false front ») avec l'enseigne. S'efface en fondu quand le
## joueur (groupe `player`) est dans l'emprise du bâtiment, revient à sa sortie.
## Dessiné en code, en coordonnées monde (position du nœud = 0).

const OUTLINE := Color(0.09, 0.05, 0.08)
const SIGN_TEXT := {
	&"saloon": "SALOON", &"bank": "BANK", &"sheriff": "SHERIFF", &"store": "GENERAL STORE",
	&"hotel": "HOTEL", &"stable": "STABLE", &"church": "", &"mine": "MINE",
}
## Style par archétype : shingle (bardeaux), tin (tôle), flat (toit plat d'adobe).
const STYLE := {
	&"saloon": &"shingle", &"hotel": &"shingle", &"store": &"shingle", &"church": &"shingle",
	&"sheriff": &"tin", &"stable": &"tin", &"mine": &"tin", &"bank": &"flat",
}
## Couleurs [versant éclairé (ouest), versant à l'ombre (est)].
const COLORS := {
	&"saloon": [Color(0.78, 0.36, 0.22), Color(0.46, 0.22, 0.26)],
	&"hotel": [Color(0.62, 0.42, 0.5), Color(0.28, 0.18, 0.3)],
	&"store": [Color(0.42, 0.56, 0.48), Color(0.18, 0.26, 0.3)],
	&"church": [Color(0.86, 0.72, 0.56), Color(0.42, 0.34, 0.42)],
	&"sheriff": [Color(0.66, 0.66, 0.72), Color(0.28, 0.3, 0.42)],
	&"stable": [Color(0.72, 0.42, 0.3), Color(0.32, 0.2, 0.24)],
	&"mine": [Color(0.6, 0.5, 0.42), Color(0.26, 0.22, 0.3)],
	&"bank": [Color(0.9, 0.66, 0.46), Color(0.56, 0.38, 0.36)],
}

var archetype: StringName = &"saloon"
var building_name: String = ""
## Emprise du bâtiment (monde, murs compris) : sert au test « joueur dedans ».
var footprint: Rect2 = Rect2()
## Surface dessinée du toit (monde).
var roof_rect: Rect2 = Rect2()
## Côté de la façade sur rue : true = bas (sud), false = haut (nord).
var facade_bottom: bool = true
## X (monde) du centre de la porte de façade (enseigne centrée dessus), NAN = centre.
var facade_x: float = NAN
var hidden_alpha: float = 0.1
var fade_duration: float = 0.25
var seed_value: int = 0

var _player: Node2D = null
var _player_inside: bool = false


func _ready() -> void:
	z_index = 50
	z_as_relative = false
	hidden_alpha = Balance.get_float("world_builder", "roof_hidden_alpha", 0.1)
	fade_duration = Balance.get_float("world_builder", "roof_fade_duration", 0.25)


func is_player_inside() -> bool:
	return _player_inside


## Vrai si `pos` (monde) est dans l'emprise du bâtiment.
func contains_world(pos: Vector2) -> bool:
	return footprint.has_point(pos)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	_player_inside = _player != null and contains_world(_player.global_position)
	var target := hidden_alpha if _player_inside else 1.0
	var step := delta / maxf(fade_duration, 0.01)
	modulate.a = move_toward(modulate.a, target, step)


# --- Dessin --------------------------------------------------------------------

func _draw() -> void:
	var r := roof_rect
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var cols: Array = COLORS.get(archetype, COLORS[&"saloon"])
	var lit: Color = cols[0]
	var dark: Color = cols[1]
	var style: StringName = STYLE.get(archetype, &"shingle")
	# Épaisseur de l'avant-toit (bordure sombre sous le bord sud, ombre portée).
	draw_rect(Rect2(r.position + Vector2(12, 12), r.size), Color(0.08, 0.1, 0.28, 0.35))
	if style == &"flat":
		_draw_flat(r, lit, dark)
	else:
		_draw_gable(r, lit, dark, style)
		var fascia := Rect2(r.position.x, r.end.y - 8.0, r.size.x, 8.0)
		draw_rect(fascia, dark.darkened(0.35))
		draw_line(fascia.position, Vector2(fascia.end.x, fascia.position.y), lit.lightened(0.3), 1.5)
	_draw_extras(r, lit, dark)
	_draw_false_front(r)
	draw_rect(r, OUTLINE, false, 3.0)


func _draw_gable(r: Rect2, lit: Color, dark: Color, style: StringName) -> void:
	# Faîtage nord-sud : versant ouest éclairé par le couchant, versant est dans l'ombre bleue.
	var mid := r.position.x + r.size.x * 0.5
	var left := Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y))
	var right := Rect2(Vector2(mid, r.position.y), Vector2(r.size.x * 0.5, r.size.y))
	_grad_rect(left, lit.lightened(0.12), lit.darkened(0.08), true)
	_grad_rect(right, dark.lightened(0.08), dark.darkened(0.12), true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if style == &"shingle":
		# Rangées de bardeaux : bord inférieur sombre, haut éclairé, joints décalés.
		var row := 16.0
		var y := r.position.y + 4.0
		var odd := false
		while y < r.end.y - 4.0:
			var y2 := minf(y + row, r.end.y)
			for half_i: int in 2:
				var base: Color = lit if half_i == 0 else dark
				var hx0 := r.position.x if half_i == 0 else mid
				var hx1 := mid if half_i == 0 else r.end.x
				draw_line(Vector2(hx0, y2 - 1.5), Vector2(hx1, y2 - 1.5), base.darkened(0.4), 3.0)
				draw_line(Vector2(hx0, y + 1.0), Vector2(hx1, y + 1.0), base.lightened(0.14), 1.4)
				var x := hx0 + (11.0 if odd else 0.0)
				while x < hx1:
					draw_line(Vector2(x, y + 2.0), Vector2(x, y2 - 3.0), base.darkened(0.28), 1.4)
					if rng.randf() < 0.07:
						draw_rect(Rect2(x + 1.0, y + 2.0, minf(20.0, hx1 - x - 1.0), row - 5.0), base.darkened(0.12))
					x += 22.0
			odd = not odd
			y += row
	else:
		# Tôle ondulée : nervures parallèles au faîtage + quelques plaques rouillées.
		var x2 := r.position.x + 6.0
		while x2 < r.end.x - 2.0:
			var c2 := lit.lightened(0.2) if x2 < mid else dark.lightened(0.12)
			draw_line(Vector2(x2, r.position.y + 2.0), Vector2(x2, r.end.y - 2.0), c2, 1.4)
			draw_line(Vector2(x2 + 3.0, r.position.y + 2.0), Vector2(x2 + 3.0, r.end.y - 2.0), (lit if x2 < mid else dark).darkened(0.3), 1.4)
			x2 += 10.0
		var seams := int(r.size.y / 96.0)
		for i: int in range(1, seams + 1):
			var sy := r.position.y + r.size.y * float(i) / float(seams + 1)
			draw_line(Vector2(r.position.x, sy), Vector2(r.end.x, sy), OUTLINE.lerp(dark, 0.5), 2.0)
		for _i: int in 3:
			var px := rng.randf_range(r.position.x, r.end.x - 50.0)
			var py := rng.randf_range(r.position.y, r.end.y - 40.0)
			draw_rect(Rect2(px, py, 40.0, 30.0), Color(0.66, 0.32, 0.16, 0.35))
	# Faîtage.
	draw_line(Vector2(mid, r.position.y), Vector2(mid, r.end.y), OUTLINE, 6.0)
	draw_line(Vector2(mid - 1.5, r.position.y), Vector2(mid - 1.5, r.end.y), lit.lightened(0.35), 2.0)
	# Rive ouest : lumière rasante.
	draw_line(r.position + Vector2(2.5, 0), Vector2(r.position.x + 2.5, r.end.y), lit.lightened(0.45), 3.0)


func _draw_flat(r: Rect2, lit: Color, dark: Color) -> void:
	_grad_rect(r, lit, dark, false)
	# Acrotère (parapet) d'adobe.
	var p := 12.0
	var inner := r.grow(-p)
	draw_rect(Rect2(r.position, Vector2(r.size.x, p)), lit.lightened(0.15))
	draw_rect(Rect2(r.position, Vector2(p, r.size.y)), lit.lightened(0.2))
	draw_rect(Rect2(Vector2(r.end.x - p, r.position.y), Vector2(p, r.size.y)), dark)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - p), Vector2(r.size.x, p)), lit.lerp(dark, 0.5))
	draw_rect(inner, Color(dark, 0.35))
	draw_rect(inner, OUTLINE, false, 1.5)
	# Ombre portée du parapet sur la terrasse (bas-droite).
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, 8.0)), Color(0.12, 0.15, 0.32, 0.35))
	draw_rect(Rect2(inner.position, Vector2(8.0, inner.size.y)), Color(0.12, 0.15, 0.32, 0.35))
	# Terrasse : lanterneau, réservoir d'eau, rustines de goudron.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _i: int in 4:
		var pp := Vector2(rng.randf_range(inner.position.x + 10.0, inner.end.x - 50.0), rng.randf_range(inner.position.y + 10.0, inner.end.y - 40.0))
		draw_rect(Rect2(pp, Vector2(rng.randf_range(24, 48), rng.randf_range(14, 26))), Color(dark.darkened(0.2), 0.35))
	var sky := Rect2(inner.position.x + inner.size.x * 0.18, inner.position.y + inner.size.y * 0.3, 70.0, 44.0)
	draw_rect(Rect2(sky.position + Vector2(8, 8), sky.size), Color(0.1, 0.12, 0.3, 0.4))
	draw_rect(sky, Color(0.5, 0.36, 0.28))
	draw_polygon(PackedVector2Array([sky.position + Vector2(5, 5), Vector2(sky.end.x - 5, sky.position.y + 5), sky.end - Vector2(5, 5), Vector2(sky.position.x + 5, sky.end.y - 5)]),
		PackedColorArray([Color(1.0, 0.7, 0.42), Color(0.9, 0.48, 0.5), Color(0.3, 0.22, 0.4), Color(0.5, 0.3, 0.42)]))
	draw_line(Vector2(sky.get_center().x, sky.position.y), Vector2(sky.get_center().x, sky.end.y), Color(0.36, 0.22, 0.14), 3.0)
	draw_rect(sky, OUTLINE, false, 2.0)
	var tank := Vector2(inner.end.x - inner.size.x * 0.22, inner.position.y + inner.size.y * 0.42)
	draw_circle(tank + Vector2(10, 10), 30.0, Color(0.1, 0.12, 0.3, 0.4))
	draw_circle(tank, 30.0, OUTLINE)
	draw_circle(tank, 28.0, Color(0.56, 0.38, 0.26))
	draw_circle(tank, 21.0, Color(0.68, 0.48, 0.32))
	draw_arc(tank, 25.0, PI * 0.9, PI * 1.6, 12, Color(0.92, 0.7, 0.46), 3.0)
	draw_arc(tank, 28.0, 0.0, TAU, 32, Color(0.25, 0.25, 0.32), 3.0)
	# Vigas (poutres) qui dépassent.
	var x := r.position.x + 28.0
	while x < r.end.x - 20.0:
		draw_rect(Rect2(x, r.end.y - p - 2.0, 9.0, 8.0), Color(0.36, 0.22, 0.14))
		draw_rect(Rect2(x, r.end.y - p - 2.0, 9.0, 8.0), OUTLINE, false, 1.2)
		x += 44.0


func _draw_extras(r: Rect2, lit: Color, dark: Color) -> void:
	match archetype:
		&"saloon", &"hotel", &"store":
			# Cheminée de briques.
			var c := Rect2(r.position.x + r.size.x * 0.68, r.position.y + r.size.y * 0.22, 26.0, 26.0)
			draw_rect(Rect2(c.position + Vector2(8, 8), c.size), Color(0.1, 0.12, 0.3, 0.4))
			draw_rect(c, Color(0.62, 0.3, 0.22))
			draw_rect(Rect2(c.position, Vector2(c.size.x * 0.45, c.size.y)), Color(0.8, 0.44, 0.3))
			draw_rect(c.grow(-6.0), Color(0.12, 0.08, 0.1))
			draw_rect(c, OUTLINE, false, 2.0)
		&"church":
			# Clocher : petite tour carrée et croix.
			var cx := r.position.x + r.size.x * 0.5
			var cy := r.position.y + r.size.y * 0.36
			var t := Rect2(cx - 30.0, cy - 30.0, 60.0, 60.0)
			draw_rect(Rect2(t.position + Vector2(12, 12), t.size), Color(0.1, 0.12, 0.3, 0.4))
			draw_rect(t, Color(0.94, 0.86, 0.74))
			draw_colored_polygon(PackedVector2Array([t.position, Vector2(cx, cy), Vector2(t.position.x, t.end.y)]), Color(1.0, 0.92, 0.8))
			draw_colored_polygon(PackedVector2Array([Vector2(t.end.x, t.position.y), Vector2(cx, cy), t.end]), Color(0.52, 0.46, 0.56))
			draw_rect(t, OUTLINE, false, 2.5)
			draw_line(Vector2(cx, cy - 22.0), Vector2(cx, cy + 22.0), OUTLINE, 9.0)
			draw_line(Vector2(cx - 14.0, cy - 8.0), Vector2(cx + 14.0, cy - 8.0), OUTLINE, 9.0)
			draw_line(Vector2(cx, cy - 22.0), Vector2(cx, cy + 22.0), Color(1.0, 0.86, 0.45), 5.0)
			draw_line(Vector2(cx - 14.0, cy - 8.0), Vector2(cx + 14.0, cy - 8.0), Color(1.0, 0.86, 0.45), 5.0)
		&"stable":
			# Lucarne de fenil.
			var h := Rect2(r.position.x + r.size.x * 0.5 - 22.0, r.position.y + r.size.y * 0.3, 44.0, 34.0)
			draw_rect(h, Color(0.3, 0.16, 0.12))
			draw_rect(h.grow(-5.0), Color(0.95, 0.78, 0.38))
			draw_line(h.position, h.end, Color(0.46, 0.24, 0.16), 3.0)
			draw_rect(h, OUTLINE, false, 2.0)
		_:
			pass


## Fausse façade de bois au bord côté rue, avec enseigne (ou emblème).
func _draw_false_front(r: Rect2) -> void:
	var h := minf(54.0, r.size.y * 0.45)
	var w := clampf(r.size.x * 0.78, 140.0, r.size.x - 8.0)
	var cx := r.position.x + r.size.x * 0.5
	if not is_nan(facade_x):
		cx = clampf(facade_x, r.position.x + w * 0.5 + 4.0, r.end.x - w * 0.5 - 4.0)
	var y0 := r.end.y - h - 4.0 if facade_bottom else r.position.y + 4.0
	var board := Rect2(cx - w * 0.5, y0, w, h)
	var wood := Color(0.74, 0.6, 0.46)
	if archetype == &"bank" or archetype == &"church":
		wood = Color(0.92, 0.78, 0.6)
	elif archetype == &"sheriff":
		wood = Color(0.62, 0.5, 0.4)
	# Ombre de la fausse façade (vers le bas-droite).
	draw_rect(Rect2(board.position + Vector2(10, 10), board.size), Color(0.1, 0.12, 0.3, 0.45))
	# Fronton à gradins.
	var step := 12.0
	var crown := PackedVector2Array([
		board.position + Vector2(0, step), board.position + Vector2(w * 0.18, step),
		board.position + Vector2(w * 0.18, 0), board.position + Vector2(w * 0.82, 0),
		board.position + Vector2(w * 0.82, step), board.position + Vector2(w, step),
		board.end, Vector2(board.position.x, board.end.y)])
	var crown_cols := PackedColorArray()
	for p: Vector2 in crown:
		crown_cols.append(wood.lightened(0.12) if p.y < board.position.y + h * 0.5 else wood.darkened(0.18))
	draw_polygon(crown, crown_cols)
	if archetype != &"bank" and archetype != &"church":
		var x := board.position.x + 14.0
		while x < board.end.x - 4.0:
			draw_line(Vector2(x, board.position.y + step + 2.0), Vector2(x, board.end.y - 2.0), wood.darkened(0.3), 1.2)
			x += 16.0
	crown.append(crown[0])
	draw_polyline(crown, OUTLINE, 2.5)
	draw_line(board.position + Vector2(2, step + 2), Vector2(board.end.x - 2, board.position.y + step + 2), wood.lightened(0.35), 2.0)
	# Panneau de l'enseigne.
	var panel := Rect2(board.position.x + w * 0.1, board.position.y + step + 6.0, w * 0.8, h - step - 12.0)
	var panel_col := Color(0.28, 0.12, 0.1)
	var text_col := Color(1.0, 0.86, 0.56)
	match archetype:
		&"bank":
			panel_col = Color(0.14, 0.24, 0.2)
		&"sheriff":
			panel_col = Color(0.14, 0.14, 0.24)
		&"church":
			panel_col = Color(0.95, 0.88, 0.76)
		&"hotel":
			panel_col = Color(0.26, 0.14, 0.26)
	draw_rect(panel, panel_col)
	draw_rect(panel, OUTLINE, false, 2.0)
	draw_rect(panel.grow(-3.0), Color(text_col, 0.5), false, 1.0)
	var text: String = SIGN_TEXT.get(archetype, building_name.to_upper())
	var icon_w := 0.0
	if archetype == &"sheriff":
		icon_w = panel.size.y * 0.9
		_draw_star(Vector2(panel.position.x + icon_w * 0.6, panel.get_center().y), panel.size.y * 0.42)
	elif archetype == &"church":
		var c := panel.get_center()
		draw_line(c + Vector2(0, -12), c + Vector2(0, 12), Color(0.3, 0.16, 0.1), 5.0)
		draw_line(c + Vector2(-8, -4), c + Vector2(8, -4), Color(0.3, 0.16, 0.1), 5.0)
	elif archetype == &"stable":
		icon_w = panel.size.y * 0.8
		var hc := Vector2(panel.position.x + icon_w * 0.6, panel.get_center().y + 2.0)
		draw_arc(hc, panel.size.y * 0.3, PI * 0.15, PI * 1.85 - PI * 0.0, 14, OUTLINE, 7.0)
		draw_arc(hc, panel.size.y * 0.3, PI * 0.15, PI * 1.85, 14, Color(0.78, 0.8, 0.88), 4.0)
	if text != "":
		var font: Font = ThemeDB.fallback_font
		var avail := panel.size.x - icon_w - 10.0
		var fs := int(clampf(panel.size.y * 0.72, 10.0, 26.0))
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		while tw > avail and fs > 9:
			fs -= 1
			tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tx := panel.position.x + icon_w + (panel.size.x - icon_w - tw) * 0.5
		var ty := panel.get_center().y + font.get_ascent(fs) * 0.5 - font.get_descent(fs) * 0.35
		draw_string_outline(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, OUTLINE)
		draw_string(font, Vector2(tx, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)


func _draw_star(c: Vector2, rad: float) -> void:
	var pts := PackedVector2Array()
	for i: int in 10:
		var a := -PI * 0.5 + float(i) * PI / 5.0
		var rr := rad if i % 2 == 0 else rad * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color(1.0, 0.8, 0.3))
	pts.append(pts[0])
	draw_polyline(pts, OUTLINE, 2.0)
	for i: int in range(0, 10, 2):
		draw_circle(pts[i], 2.5, Color(1.0, 0.9, 0.55))


## Rectangle en dégradé (horizontal : gauche→droite, sinon haut→bas).
func _grad_rect(r: Rect2, a: Color, b: Color, horizontal: bool) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray([a, b, b, a]) if horizontal else PackedColorArray([a, a, b, b])
	draw_polygon(pts, cols)

