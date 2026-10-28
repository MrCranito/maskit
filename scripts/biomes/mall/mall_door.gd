extends DoorNode
## Porte du centre commercial (même comportement que DoorNode, autre dessin) :
##   shutter : rideau métallique de boutique qui s'enroule vers le haut (lames + graffiti) ;
##   glass   : portes vitrées coulissantes (bureaux, hall) ;
##   steel   : porte de service en tôle peinte ;
##   vault   : porte blindée à lecteur de carte magnétique (bijouterie, salle des coffres).
## Verrouillée : lecteur de badge à LED rouge clignotante (au lieu du cadenas).

const KIND_SHUTTER := &"shutter"
const KIND_GLASS := &"glass"
const KIND_STEEL := &"steel"
const KIND_VAULT_STEEL := &"vault_steel"

const C_OUT := Color(0.08, 0.06, 0.1)
const C_FRAME := Color(0.3, 0.3, 0.38)
const C_FRAME_LIGHT := Color(0.72, 0.72, 0.82)
const C_SLAT := Color(0.62, 0.63, 0.7)
const C_SLAT_DARK := Color(0.4, 0.4, 0.48)
const C_GLASS := Color(0.36, 0.5, 0.66, 0.75)
const C_STEEL := Color(0.36, 0.46, 0.5)
const C_VAULT := Color(0.32, 0.33, 0.4)
const C_GOLD := Color(1.0, 0.78, 0.3)
const C_NEON := Color(1.0, 0.32, 0.75)

## Couleur d'accent (graffiti, liseré) choisie par le constructeur.
var accent: Color = C_NEON


func _draw() -> void:
	var t := 1.0 - pow(1.0 - _open_t, 3.0)
	if vertical:
		_mall_vertical(t)
	else:
		_mall_horizontal(t)


func _mall_horizontal(t: float) -> void:
	var h := wall_height
	var half := TS * 0.5
	var cap := Rect2(-half, -TS, TS, TS - h)
	draw_rect(cap, Color(0.24, 0.22, 0.3))
	draw_line(cap.position + Vector2(0, 1), Vector2(cap.end.x, cap.position.y + 1), C_FRAME_LIGHT.darkened(0.3), 2.0)
	draw_rect(cap, C_OUT, false, 1.5)
	var op := Rect2(-half + 5.0, -h + 6.0, TS - 10.0, h - 6.0)
	# Ouverture : intérieur sombre (visible quand la porte est ouverte).
	draw_rect(op, Color(0.06, 0.05, 0.1, 0.85 * (1.0 - t * 0.6)))
	match kind:
		KIND_SHUTTER:
			_shutter(op, t)
		KIND_GLASS:
			_glass(op, t)
		KIND_STEEL:
			_steel(op, t)
		_:
			_vault(op, t)
	# Encadrement métallique.
	draw_rect(Rect2(-half, -h, 5.0, h), C_FRAME)
	draw_rect(Rect2(half - 5.0, -h, 5.0, h), C_FRAME)
	draw_rect(Rect2(-half, -h, TS, 6.0), C_FRAME)
	draw_line(Vector2(-half + 1.0, -h), Vector2(-half + 1.0, 0.0), C_FRAME_LIGHT, 2.0)
	draw_rect(Rect2(-half, -h, TS, h), C_OUT, false, 2.0)
	if is_locked():
		_card_reader(Vector2(half - 12.0, -h * 0.5))


func _shutter(op: Rect2, t: float) -> void:
	# Lames qui s'enroulent vers le haut ; il reste le caisson en haut.
	var vis := 1.0 - t
	var y1 := op.position.y + op.size.y * vis
	var y := op.position.y
	var i := 0
	while y < y1 - 0.5:
		var hh := minf(5.0, y1 - y)
		draw_rect(Rect2(op.position.x, y, op.size.x, hh), C_SLAT if i % 2 == 0 else C_SLAT.darkened(0.08))
		draw_line(Vector2(op.position.x, y + hh), Vector2(op.end.x, y + hh), C_SLAT_DARK, 1.0)
		y += 5.0
		i += 1
	if vis > 0.2:
		# Graffiti (tag néon) et poignée.
		var gy := op.position.y + op.size.y * 0.45 * vis
		draw_polyline(PackedVector2Array([Vector2(-18, gy), Vector2(-8, gy - 7), Vector2(0, gy + 3), Vector2(10, gy - 6), Vector2(18, gy + 2)]),
			Color(accent, 0.85 * vis), 3.0)
		draw_rect(Rect2(-7.0, y1 - 6.0, 14.0, 4.0), C_FRAME)
		draw_rect(Rect2(-7.0, y1 - 6.0, 14.0, 4.0), C_OUT, false, 1.0)
	draw_line(Vector2(op.position.x, y1), Vector2(op.end.x, y1), C_OUT, 2.0)
	draw_rect(Rect2(op.position.x - 2.0, op.position.y - 4.0, op.size.x + 4.0, 8.0), C_SLAT_DARK)
	draw_rect(Rect2(op.position.x - 2.0, op.position.y - 4.0, op.size.x + 4.0, 8.0), C_OUT, false, 1.2)


func _glass(op: Rect2, t: float) -> void:
	# Deux vantaux vitrés qui coulissent vers les côtés.
	var half_w := op.size.x * 0.5
	var slide := half_w * 0.9 * t
	for side: float in [-1.0, 1.0]:
		var x0 := op.get_center().x + (0.0 if side > 0 else -half_w) + side * slide
		var r := Rect2(x0, op.position.y, half_w, op.size.y)
		r = r.intersection(op)
		if r.size.x <= 0.5:
			continue
		draw_rect(r, C_GLASS)
		draw_line(r.position + Vector2(4, r.size.y - 6), r.position + Vector2(r.size.x * 0.7, 6), Color(1, 0.95, 0.9, 0.45), 2.0)
		draw_rect(r, C_FRAME, false, 2.0)
	draw_line(Vector2(op.position.x, op.end.y - 14.0), Vector2(op.end.x, op.end.y - 14.0), Color(accent, 0.4 * (1.0 - t)), 2.0)


func _steel(op: Rect2, t: float) -> void:
	var ang := t * deg_to_rad(95.0)
	_draw_leaf(Vector2(op.position.x, -3.0), Vector2(cos(ang), -sin(ang)) * op.size.x, op.size.y - 3.0, C_STEEL, false)


func _vault(op: Rect2, t: float) -> void:
	# Porte blindée qui coulisse vers la droite (dans le mur).
	var vis := 1.0 - t
	if vis <= 0.01:
		return
	var r := Rect2(op.position.x + op.size.x * t, op.position.y, op.size.x * vis, op.size.y)
	draw_rect(r, C_VAULT)
	for k: int in 4:
		var yy := r.position.y + 6.0 + float(k) * (r.size.y - 12.0) / 3.0
		draw_line(Vector2(r.position.x + 3.0, yy), Vector2(r.end.x - 3.0, yy), C_VAULT.lightened(0.25), 1.5)
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.45)
	if r.size.x > 20.0:
		draw_arc(c, 9.0, 0.0, TAU, 16, C_OUT, 4.0)
		draw_arc(c, 9.0, 0.0, TAU, 16, C_GOLD, 2.0)
		for k2: int in 3:
			var a := float(k2) * TAU / 3.0 + _anim_time * 0.0
			draw_line(c, c + Vector2(cos(a), sin(a)) * 9.0, C_GOLD, 2.0)
	draw_rect(r, C_OUT, false, 1.5)


func _card_reader(p: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_time * 4.0)
	var body := Rect2(p + Vector2(-6.0, -10.0), Vector2(12.0, 20.0))
	draw_rect(body, Color(0.12, 0.12, 0.18))
	draw_rect(Rect2(body.position + Vector2(2, 3), Vector2(8, 3)), Color(0.4, 0.4, 0.5))
	draw_circle(p + Vector2(0, 5), 2.6, Color(1.0, 0.2, 0.15))
	draw_circle(p + Vector2(0, 5), 7.0 + pulse * 3.0, Color(1.0, 0.2, 0.15, 0.18 + 0.12 * pulse))
	draw_rect(body, C_OUT, false, 1.5)


func _mall_vertical(t: float) -> void:
	# Porte dans un mur vertical : vue de dessus (le mur n'a pas de face visible).
	var top := -TS + 4.0
	var length := TS - 8.0
	draw_rect(Rect2(-9.0, -TS, 18.0, TS), Color(0.22, 0.2, 0.28, 0.75))
	match kind:
		KIND_SHUTTER, KIND_VAULT_STEEL:
			var vis := 1.0 - t
			if vis > 0.02:
				var col := C_SLAT if kind == KIND_SHUTTER else C_VAULT
				draw_rect(Rect2(-6.0, top, 12.0, length * vis), col)
				var y := top
				while y < top + length * vis - 1.0:
					draw_line(Vector2(-6.0, y), Vector2(6.0, y), col.darkened(0.3), 1.0)
					y += 5.0
				draw_rect(Rect2(-6.0, top, 12.0, length * vis), C_OUT, false, 1.5)
		KIND_GLASS:
			var slide := length * 0.5 * t
			draw_rect(Rect2(-3.0, top - slide, 6.0, length * 0.5), C_GLASS)
			draw_rect(Rect2(-3.0, top + length * 0.5 + slide, 6.0, length * 0.5), C_GLASS)
		_:
			var ang := t * deg_to_rad(95.0)
			_draw_slab(Vector2(0.0, top), Vector2(sin(ang), cos(ang)) * length, C_STEEL, 10.0)
	for y2: float in [-TS + 2.0, -2.0]:
		draw_rect(Rect2(-11.0, y2 - 5.0, 22.0, 10.0), C_FRAME)
		draw_rect(Rect2(-11.0, y2 - 5.0, 22.0, 10.0), C_OUT, false, 1.5)
	if is_locked():
		_card_reader(Vector2(0.0, -TS * 0.5))
