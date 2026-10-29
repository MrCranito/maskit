class_name BuildingRoof
extends Node2D
## Toit d'un bâtiment (z_index 50) : masque l'intérieur vu de la rue et porte la
## fausse façade (« false front ») avec l'enseigne peinte (police Rye). S'efface en
## fondu (tween, seulement au changement) quand le joueur (groupe `player`) entre dans
## l'emprise du bâtiment, revient à sa sortie. Test de présence espacé (10 Hz).
## Dessiné UNE fois en coordonnées monde (position du nœud = 0) : matières peintes
## tuilables (assets/textures/roofs : bardeaux, tôle, terrasse d'adobe) teintées par
## archétype, éléments 3D du kit Blender (cheminée, clocher, citerne), ombre bleu nuit.

const OUTLINE := Color(0.09, 0.05, 0.08)
const NIGHT := Color(0.1, 0.12, 0.3)
const FONT: Font = preload("res://assets/fonts/rye/Rye-Regular.ttf")
const TEX_SHINGLE: Texture2D = preload("res://assets/textures/roofs/shingle.png")
const TEX_TIN: Texture2D = preload("res://assets/textures/roofs/tin.png")
const TEX_FLAT: Texture2D = preload("res://assets/textures/roofs/flat.png")
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
	&"saloon": [Color(0.86, 0.42, 0.28), Color(0.5, 0.26, 0.32)],
	&"hotel": [Color(0.7, 0.48, 0.56), Color(0.34, 0.24, 0.38)],
	&"store": [Color(0.5, 0.64, 0.54), Color(0.22, 0.32, 0.38)],
	&"church": [Color(0.9, 0.76, 0.6), Color(0.46, 0.38, 0.48)],
	&"sheriff": [Color(0.8, 0.8, 0.86), Color(0.36, 0.38, 0.52)],
	&"stable": [Color(0.86, 0.56, 0.4), Color(0.4, 0.26, 0.3)],
	&"mine": [Color(0.72, 0.62, 0.54), Color(0.32, 0.28, 0.38)],
	&"bank": [Color(0.96, 0.74, 0.54), Color(0.62, 0.44, 0.42)],
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
var _check_left: float = 0.0
var _tween: Tween = null


func _ready() -> void:
	z_index = 50
	z_as_relative = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	hidden_alpha = Balance.get_float("world_builder", "roof_hidden_alpha", 0.1)
	fade_duration = Balance.get_float("world_builder", "roof_fade_duration", 0.25)


func is_player_inside() -> bool:
	return _player_inside


## Vrai si `pos` (monde) est dans l'emprise du bâtiment.
func contains_world(pos: Vector2) -> bool:
	return footprint.has_point(pos)


func _process(delta: float) -> void:
	# Test espacé (0,1 s) ; le fondu est un tween lancé seulement au changement d'état.
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.1
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	var inside := _player != null and contains_world(_player.global_position)
	# (Toits) Joueur perché sur un toit : il est AU-DESSUS, aucun toit ne s'efface.
	if inside and _player.has_method("is_on_roof") and bool(_player.call("is_on_roof")):
		inside = false
	if inside == _player_inside:
		return
	_player_inside = inside
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", hidden_alpha if inside else 1.0, fade_duration)


# --- Dessin --------------------------------------------------------------------

func _draw() -> void:
	var r := roof_rect
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	var cols: Array = COLORS.get(archetype, COLORS[&"saloon"])
	var lit: Color = cols[0]
	var dark: Color = cols[1]
	var style: StringName = STYLE.get(archetype, &"shingle")
	# Ombre portée bleu nuit (vers le bas-droite), en deux couches pour un bord doux.
	draw_rect(Rect2(r.position + Vector2(10, 10), r.size + Vector2(8, 4)), Color(NIGHT, 0.22))
	draw_rect(Rect2(r.position + Vector2(6, 6), r.size), Color(NIGHT, 0.3))
	if style == &"flat":
		_draw_flat(r, lit, dark)
	else:
		_draw_gable(r, lit, dark, style)
	_draw_extras(r, lit, dark)
	_draw_false_front(r)
	draw_rect(r, OUTLINE, false, 3.0)


## Matière tuilable (unités monde : 1 répétition = 176 u) dans `dst`, teintée.
func _tiled(tex: Texture2D, dst: Rect2, tint: Color, offset: Vector2 = Vector2.ZERO) -> void:
	var k := float(tex.get_width()) / 176.0
	draw_texture_rect_region(tex, dst, Rect2((dst.position + offset) * k, dst.size * k), tint)


func _draw_gable(r: Rect2, lit: Color, dark: Color, style: StringName) -> void:
	# Faîtage nord-sud : versant ouest éclairé par le couchant, versant est dans l'ombre bleue.
	var tex: Texture2D = TEX_SHINGLE if style == &"shingle" else TEX_TIN
	var mid := r.position.x + r.size.x * 0.5
	var left := Rect2(r.position, Vector2(r.size.x * 0.5, r.size.y))
	var right := Rect2(Vector2(mid, r.position.y), Vector2(r.size.x * 0.5, r.size.y))
	var off := Vector2(float(seed_value % 97), float(seed_value % 61))
	_tiled(tex, left, lit, off)
	_tiled(tex, right, dark, off)
	# Dégradé : plus clair près du faîtage côté ouest, ombre dans le creux côté est.
	_grad_rect(Rect2(mid - 26.0, r.position.y, 26.0, r.size.y), Color(1, 0.9, 0.7, 0.0), Color(1, 0.9, 0.7, 0.22), true)
	_grad_rect(Rect2(mid, r.position.y, 34.0, r.size.y), Color(NIGHT, 0.35), Color(NIGHT, 0.0), true)
	# Égout (avant-toit) : chant sombre + liseré éclairé.
	var fascia := Rect2(r.position.x, r.end.y - 9.0, r.size.x, 9.0)
	draw_rect(fascia, dark.darkened(0.45))
	draw_line(fascia.position, Vector2(fascia.end.x, fascia.position.y), lit.lightened(0.35), 2.0)
	# Faîtage.
	draw_rect(Rect2(mid - 5.0, r.position.y, 10.0, r.size.y), OUTLINE)
	draw_rect(Rect2(mid - 4.0, r.position.y, 4.0, r.size.y), lit.lightened(0.3))
	draw_rect(Rect2(mid, r.position.y, 4.0, r.size.y), dark.darkened(0.2))
	# Rives : lumière rasante à l'ouest, ombre à l'est.
	draw_rect(Rect2(r.position.x, r.position.y, 4.0, r.size.y), lit.lightened(0.45))
	draw_rect(Rect2(r.end.x - 5.0, r.position.y, 5.0, r.size.y), dark.darkened(0.35))


func _draw_flat(r: Rect2, lit: Color, dark: Color) -> void:
	var p := 12.0
	var inner := r.grow(-p)
	_tiled(TEX_FLAT, inner, lit.lerp(Color.WHITE, 0.15), Vector2(float(seed_value % 53), 0))
	# Acrotère (parapet) d'adobe : éclairé à l'ouest/nord, à l'ombre à l'est/sud.
	_tiled(TEX_FLAT, Rect2(r.position, Vector2(r.size.x, p)), lit.lightened(0.15))
	_tiled(TEX_FLAT, Rect2(r.position, Vector2(p, r.size.y)), lit.lightened(0.22))
	_tiled(TEX_FLAT, Rect2(Vector2(r.end.x - p, r.position.y), Vector2(p, r.size.y)), dark)
	_tiled(TEX_FLAT, Rect2(Vector2(r.position.x, r.end.y - p), Vector2(r.size.x, p)), lit.lerp(dark, 0.5))
	draw_rect(inner, OUTLINE, false, 1.5)
	# Ombre portée du parapet sur la terrasse (bas-droite).
	_grad_rect(Rect2(inner.position, Vector2(inner.size.x, 14.0)), Color(NIGHT, 0.4), Color(NIGHT, 0.0), false)
	_grad_rect(Rect2(inner.position, Vector2(14.0, inner.size.y)), Color(NIGHT, 0.4), Color(NIGHT, 0.0), true)
	# Vigas (poutres) qui dépassent de l'acrotère.
	var x := r.position.x + 28.0
	while x < r.end.x - 20.0:
		draw_rect(Rect2(x, r.end.y - p - 2.0, 9.0, 8.0), Color(0.36, 0.22, 0.14))
		draw_rect(Rect2(x, r.end.y - p - 2.0, 9.0, 8.0), OUTLINE, false, 1.2)
		x += 44.0


## Pièce du kit 3D (atlas des décors) posée par son point d'appui.
func _kit(piece: String, at: Vector2, k: float = 1.0) -> void:
	if WorldProp.has_piece(piece):
		draw_texture_rect_region(WorldProp.ATLAS, WorldProp.piece_dest(piece, at, k), WorldProp.piece_region(piece))


func _draw_extras(r: Rect2, _lit: Color, _dark: Color) -> void:
	match archetype:
		&"saloon", &"hotel", &"store":
			_kit("kit_chimney", Vector2(r.position.x + r.size.x * 0.72, r.position.y + r.size.y * 0.42))
		&"church":
			_kit("kit_belltower", Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.62))
		&"bank":
			_kit("kit_tank", Vector2(r.position.x + r.size.x * 0.76, r.position.y + r.size.y * 0.52))
		&"stable":
			# Lucarne de fenil (foin doré).
			var h := Rect2(r.position.x + r.size.x * 0.5 - 22.0, r.position.y + r.size.y * 0.3, 44.0, 34.0)
			draw_rect(Rect2(h.position + Vector2(6, 6), h.size), Color(NIGHT, 0.4))
			draw_rect(h, Color(0.3, 0.16, 0.12))
			draw_rect(h.grow(-5.0), Color(0.95, 0.78, 0.38))
			draw_line(h.position, h.end, Color(0.46, 0.24, 0.16), 3.0)
			draw_rect(h, OUTLINE, false, 2.0)
		&"mine":
			_kit("kit_chimney", Vector2(r.position.x + r.size.x * 0.3, r.position.y + r.size.y * 0.45), 0.8)
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
		var font: Font = FONT
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

