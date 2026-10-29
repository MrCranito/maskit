class_name ExtractionZone
extends Node2D
## Zone d'extraction (un groupe de cases d'extraction contiguës) : marqueur au sol propre,
## lisible sur la carte pré-rendue réaliste.
##   - plaque circulaire sombre, anneau lumineux vert/cyan, anneau en tirets qui tourne
##     lentement, 4 chevrons tournés vers le centre, pictogramme de sortie au centre ;
##   - balise radio au bord avec un feu vert qui pulse et un fumigène vert qui monte ;
##   - icône flottante au-dessus de la zone (au-dessus du brouillard : repérable de loin) ;
##   - pendant la canalisation : anneau de progression centré sur la zone et pastille
##     « Extraction… 3 s ».
## Performance : chaque morceau est dessiné UNE fois ; l'animation passe par des Tween sur
## rotation / position / échelle / opacité de nœuds (aucun redessin par frame). Seul l'anneau
## de progression est redessiné pendant la canalisation, quand la valeur affichée change.

const COL := Color(0.3, 1.0, 0.62)          ## vert extraction
const COL_CYAN := Color(0.45, 0.95, 1.0)
const COL_DARK := Color(0.02, 0.07, 0.07)
const TS := float(FloorLayout.TILE_SIZE)

## Cases de la zone.
var cells: Array[Vector2i] = []
## Centre (monde) et rayon (px) de la zone.
var center: Vector2 = Vector2.ZERO
var radius: float = 96.0

var _ground: ZoneGround = null
var _spinner: ZoneSpinner = null
var _beacon_light: Node2D = null
var _icon: Node2D = null
var _progress: ZoneProgress = null
var _tweens: Array[Tween] = []


## Regroupe les cases d'extraction en zones contiguës (4-voisinage), triées (déterministe).
static func group_cells(all_cells: Array[Vector2i]) -> Array[Array]:
	var cell_set := {}
	for c: Vector2i in all_cells:
		cell_set[c] = true
	var sorted: Array[Vector2i] = all_cells.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	var seen := {}
	var out: Array[Array] = []
	for c: Vector2i in sorted:
		if seen.has(c):
			continue
		var group: Array[Vector2i] = []
		var stack: Array[Vector2i] = [c]
		seen[c] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			group.append(cur)
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var nb := cur + d
				if cell_set.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		out.append(group)
	return out


## Une zone par groupe de cases contiguës.
static func create_all(all_cells: Array[Vector2i]) -> Array[ExtractionZone]:
	var out: Array[ExtractionZone] = []
	for g: Array in group_cells(all_cells):
		var z := ExtractionZone.new()
		z.cells.assign(g)
		z._compute_geometry()
		out.append(z)
	return out


func _compute_geometry() -> void:
	var sum := Vector2.ZERO
	for c: Vector2i in cells:
		sum += FloorLayout.cell_to_world(c)
	center = sum / maxf(cells.size(), 1.0)
	var far := 0.0
	for c: Vector2i in cells:
		far = maxf(far, FloorLayout.cell_to_world(c).distance_to(center))
	radius = clampf(far + TS * 0.45, Balance.get_float("extraction", "zone_min_radius", 78.0),
		Balance.get_float("extraction", "zone_max_radius", 170.0))
	position = center


func has_cell(c: Vector2i) -> bool:
	return cells.has(c)


func _ready() -> void:
	name = "ExtractionZone"
	z_index = 1
	_ground = ZoneGround.new()
	_ground.radius = radius
	add_child(_ground)
	_spinner = ZoneSpinner.new()
	_spinner.radius = radius
	add_child(_spinner)
	_build_beacon()
	_build_icon()
	_progress = ZoneProgress.new()
	_progress.radius = radius
	_progress.visible = false
	add_child(_progress)
	_start_animations()


func _exit_tree() -> void:
	for t: Tween in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()


## Balise radio plantée au bord de la zone (nord-est) : mât, feu vert, fumigène.
func _build_beacon() -> void:
	var at := Vector2.from_angle(-PI * 0.28) * radius * 0.96
	var post := BeaconPost.new()
	post.position = at
	add_child(post)
	_beacon_light = GlowDot.new()
	(_beacon_light as GlowDot).color = COL
	(_beacon_light as GlowDot).r = 11.0
	_beacon_light.position = at + Vector2(0, -30)
	add_child(_beacon_light)
	# Fumigène vert : trois volutes qui montent en boucle, décalées dans le temps.
	var smoke := Node2D.new()
	smoke.name = "Smoke"
	smoke.position = at + Vector2(0, -30)
	smoke.z_as_relative = false
	smoke.z_index = 60
	add_child(smoke)
	for i in 3:
		var puff := SmokePuff.new()
		puff.modulate.a = 0.0
		smoke.add_child(puff)
		var tw := create_tween().set_loops()
		tw.tween_interval(0.85 * i)
		tw.tween_callback(func() -> void:
			puff.position = Vector2.ZERO
			puff.scale = Vector2(0.45, 0.45)
			puff.modulate.a = 0.0)
		tw.tween_property(puff, "modulate:a", 0.55, 0.35)
		tw.parallel().tween_property(puff, "position", Vector2(10.0 + 4.0 * i, -78.0), 2.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(puff, "scale", Vector2(1.5, 1.5), 2.55)
		tw.tween_property(puff, "modulate:a", 0.0, 0.0)
		tw.tween_interval(maxf(0.0, 0.85 * (2 - i)))
		_tweens.append(tw)


## Icône de sortie flottante au-dessus de la zone, dessinée au-dessus du brouillard.
func _build_icon() -> void:
	var holder := Node2D.new()
	holder.name = "Icon"
	holder.z_as_relative = false
	holder.z_index = 85
	holder.position = Vector2(0, -radius - 34.0)
	add_child(holder)
	_icon = ExitBadge.new()
	holder.add_child(_icon)


func _start_animations() -> void:
	var spin := create_tween().set_loops()
	spin.tween_property(_spinner, "rotation", TAU, Balance.get_float("extraction", "spin_period", 14.0)).from(0.0)
	_tweens.append(spin)
	var pulse := create_tween().set_loops()
	pulse.tween_property(_ground, "modulate:a", 0.72, 1.3).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_ground, "modulate:a", 1.0, 1.3).set_trans(Tween.TRANS_SINE)
	_tweens.append(pulse)
	var blink := create_tween().set_loops()
	blink.tween_property(_beacon_light, "modulate:a", 0.25, 0.55)
	blink.tween_property(_beacon_light, "modulate:a", 1.0, 0.55)
	_tweens.append(blink)
	var bob := create_tween().set_loops()
	bob.tween_property(_icon, "position:y", -6.0, 1.1).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_icon, "position:y", 0.0, 1.1).set_trans(Tween.TRANS_SINE)
	_tweens.append(bob)


# --- Canalisation ----------------------------------------------------------------------

func show_progress(on: bool) -> void:
	if _progress == null:
		return
	_progress.visible = on
	if _icon != null:
		_icon.get_parent().visible = not on
	if on:
		_progress.set_state(0.0, Raid.extraction_channel_time())


## p = 0..1, remaining = secondes restantes.
func set_progress(p: float, remaining: float) -> void:
	if _progress != null:
		_progress.set_state(p, remaining)


func is_progress_visible() -> bool:
	return _progress != null and _progress.visible


func get_progress_text() -> String:
	return _progress.text if _progress != null else ""


# =====================================================================================
# Morceaux dessinés une fois.

## Plaque au sol : disque sombre translucide, double anneau lumineux, chevrons, pictogramme.
class ZoneGround extends Node2D:
	var radius: float = 96.0

	func _draw() -> void:
		var r := radius
		draw_circle(Vector2.ZERO, r + 6.0, Color(COL_DARK, 0.28))
		draw_circle(Vector2.ZERO, r, Color(COL, 0.10))
		draw_circle(Vector2.ZERO, r * 0.7, Color(COL, 0.07))
		# Halo + anneau principal.
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(COL, 0.25), 12.0, true)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(COL.lightened(0.2), 0.95), 3.5, true)
		draw_arc(Vector2.ZERO, r - 12.0, 0.0, TAU, 96, Color(COL_CYAN, 0.35), 1.5, true)
		# Chevrons tournés vers le centre (« entre ici »).
		for k in 4:
			var a := PI * 0.25 + PI * 0.5 * k
			var dir := Vector2.from_angle(a)
			var side := dir.orthogonal()
			var tip := dir * (r * 0.56)
			var w := clampf(r * 0.13, 9.0, 16.0)
			var pts := PackedVector2Array([tip + dir * w + side * w, tip, tip + dir * w - side * w])
			draw_polyline(pts, Color(COL_DARK, 0.6), 8.0, true)
			draw_polyline(pts, Color(COL, 0.9), 4.5, true)
		# Plaque centrale (type hélipad) + pictogramme de sortie.
		var pr := clampf(r * 0.34, 26.0, 42.0)
		draw_circle(Vector2.ZERO, pr + 3.0, Color(COL, 0.55))
		draw_circle(Vector2.ZERO, pr, Color(COL_DARK, 0.82))
		ExtractionZone.draw_exit_glyph(self, Vector2.ZERO, pr * 0.62, Color(COL.lightened(0.25), 1.0))


## Anneau en tirets (tourne lentement par Tween sur la rotation).
class ZoneSpinner extends Node2D:
	var radius: float = 96.0

	func _draw() -> void:
		var n := 16
		var rr := radius + 11.0
		for i in n:
			var a0 := TAU * float(i) / n
			draw_arc(Vector2.ZERO, rr, a0, a0 + TAU / n * 0.5, 8, Color(COL_CYAN, 0.75), 3.0, true)


## Mât de la balise radio.
class BeaconPost extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2(3, 2), 7.0, Color(0, 0, 0, 0.35))
		draw_rect(Rect2(-6, -6, 12, 7), Color(0.16, 0.18, 0.2))
		draw_rect(Rect2(-2, -30, 4, 26), Color(0.22, 0.24, 0.27))
		draw_line(Vector2(0, -30), Vector2(7, -44), Color(0.6, 0.62, 0.66), 1.5, true)
		draw_rect(Rect2(-5, -36, 10, 8), Color(0.1, 0.12, 0.13))


## Feu lumineux (disques concentriques à alpha décroissant).
class GlowDot extends Node2D:
	var color: Color = COL
	var r: float = 10.0

	func _init() -> void:
		z_as_relative = false
		z_index = 60

	func _draw() -> void:
		for k in 4:
			draw_circle(Vector2.ZERO, r * (1.0 + 0.55 * (3 - k)), Color(color, 0.08 + 0.05 * k))
		draw_circle(Vector2.ZERO, r * 0.4, Color(1, 1, 1, 0.95))


## Volute de fumée verte.
class SmokePuff extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 14.0, Color(0.55, 1.0, 0.7, 0.22))
		draw_circle(Vector2(-4, -3), 9.0, Color(0.7, 1.0, 0.8, 0.28))
		draw_circle(Vector2(5, 2), 8.0, Color(0.45, 0.95, 0.6, 0.25))


## Badge flottant : pastille sombre, bord vert, pictogramme de sortie.
class ExitBadge extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2(0, 3), 21.0, Color(0, 0, 0, 0.35))
		draw_circle(Vector2.ZERO, 20.0, Color(0.05, 0.09, 0.12, 0.92))
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 40, COL, 3.0, true)
		ExtractionZone.draw_exit_glyph(self, Vector2.ZERO, 12.0, Color(COL.lightened(0.3), 1.0))
		draw_colored_polygon(PackedVector2Array([Vector2(-7, 19), Vector2(7, 19), Vector2(0, 28)]), COL)


## Anneau de progression + pastille « Extraction… 3 s » (redessiné quand l'affichage change).
class ZoneProgress extends Node2D:
	var radius: float = 96.0
	var progress: float = 0.0
	var text: String = ""

	func _init() -> void:
		z_as_relative = false
		z_index = 86

	func set_state(p: float, remaining: float) -> void:
		var q := snappedf(clampf(p, 0.0, 1.0), 0.004)
		var t := "Extraction… %d s" % ceili(maxf(remaining, 0.0))
		if is_equal_approx(q, progress) and t == text:
			return
		progress = q
		text = t
		queue_redraw()

	func _draw() -> void:
		var r := radius
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(COL_DARK, 0.55), 11.0, true)
		if progress > 0.0:
			draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * progress, 96, Color(COL, 0.35), 16.0, true)
			draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * progress, 96, Color(0.85, 1.0, 0.9), 6.0, true)
		# Pastille de texte au sommet de l'anneau.
		var font := LootVisuals.text_font(900)
		var fs := 18
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pill := Rect2(Vector2(-w * 0.5 - 14.0, -r - 44.0), Vector2(w + 28.0, 30.0))
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.05, 0.08, 0.12, 0.9)
		st.border_color = COL
		st.set_border_width_all(2)
		st.set_corner_radius_all(15)
		st.anti_aliasing = true
		draw_style_box(st, pill)
		draw_string(font, Vector2(-w * 0.5, pill.position.y + 21.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## Pictogramme « sortie » : flèche vers le haut sortant d'un cadre de porte.
static func draw_exit_glyph(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var lw := maxf(s * 0.16, 2.0)
	# Cadre (porte ouverte vers le haut).
	ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.78, -s * 0.15), c + Vector2(-s * 0.78, s * 0.8),
		c + Vector2(s * 0.78, s * 0.8), c + Vector2(s * 0.78, -s * 0.15)]), col, lw, true)
	# Flèche.
	ci.draw_line(c + Vector2(0, s * 0.55), c + Vector2(0, -s * 0.5), col, lw * 1.15, true)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.25), c + Vector2(0, -s * 0.95),
		c + Vector2(s * 0.5, -s * 0.25)]), col)
