class_name ExtractionZone
extends Node2D
## Zone d'extraction (un groupe de cases d'extraction contiguës) : marqueur au sol propre,
## lisible sur la carte pré-rendue réaliste.
##   - plaque circulaire sombre, anneau lumineux vert/cyan, anneau en tirets qui tourne
##     lentement, 4 chevrons tournés vers le centre, pictogramme de sortie au centre ;
##   - balise radio au bord avec un feu vert qui pulse et un fumigène vert qui monte ;
##   - icône flottante au-dessus de la zone (au-dessus du brouillard : repérable de loin) ;
##   - pendant la canalisation : anneau de progression centré sur la zone et pastille
##     « Extraction… 3 s », colonne de lumière qui s'intensifie, anneau en tirets qui accélère ;
##   - réussite (play_success) : colonne éblouissante et gerbe d'éclats qui montent.
##   - durée de vie (ExtractionPlan) : minuteur au-dessus de la zone, qui clignote en orange
##     avant la fermeture ; zone fermée grisée et barrée (plus de colonne ni de fumigène) ;
##   - extraction permanente (ExtractionPlan, option A) : jamais fermée, minuteur « ∞ » absent ;
##   - trappe d'urgence (kind hatch) : rendu Blender de trappe à chevrons verts
##     (assets/sprites/extraction/hatch*.png), fermée à clef (`locked`) ; ni plaque, ni balise,
##     ni icône au-dessus du brouillard (cachée hors du champ de vision, jamais sur la carte).
## Performance : chaque morceau est dessiné UNE fois ; l'animation passe par des Tween sur
## rotation / position / échelle / opacité de nœuds (aucun redessin par frame). Seul l'anneau
## de progression est redessiné pendant la canalisation, quand la valeur affichée change.

const COL := Color(0.3, 1.0, 0.62)          ## vert extraction
const COL_CYAN := Color(0.45, 0.95, 1.0)
const COL_DARK := Color(0.02, 0.07, 0.07)
const TS := float(FloorLayout.TILE_SIZE)
const COL_WARN := Color(1.0, 0.62, 0.22)
const COL_CLOSED := Color(0.62, 0.64, 0.7)

enum State { OPEN, CLOSING, CLOSED, DORMANT }

## Cases de la zone.
var cells: Array[Vector2i] = []
## Centre (monde) et rayon (px) de la zone.
var center: Vector2 = Vector2.ZERO
var radius: float = 96.0
## Durée de vie (horloge du raid, s) : ouverte de opens_at à closes_at (INF = jamais fermée).
var zone_name: String = ""
var opens_at: float = 0.0
var closes_at: float = INF
## ExtractionPlan.KIND_* (permanente, temporaire, trappe).
var kind: StringName = ExtractionPlan.KIND_TEMPORARY
## Option de placement (ExtractionPlan.Spec.option) : debug.
var option: String = ""
## Trappe : fermée tant qu'aucune clef n'a été utilisée.
var locked: bool = false
var rank: int = 0
var state: int = State.OPEN

var _ground: ZoneGround = null
var _spinner: ZoneSpinner = null
var _beacon_light: Node2D = null
var _icon: Node2D = null
var _progress: ZoneProgress = null
var _beam: ZoneBeam = null
var _spin_tween: Tween = null
var _tweens: Array[Tween] = []
var _smoke: Node2D = null
var _timer: ZoneTimer = null
var _closed_mark: Node2D = null
var _pending_clock: float = -1.0
var _hatch: HatchSprite = null


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


## Une zone par ExtractionPlan.Spec (durées de vie, noms, zone d'urgence).
static func create_from_specs(specs: Array) -> Array[ExtractionZone]:
	var out: Array[ExtractionZone] = []
	for sp: Variant in specs:
		var z := ExtractionZone.new()
		z.cells.assign(sp.cells)
		z.zone_name = sp.name
		z.opens_at = sp.opens_at
		z.closes_at = sp.closes_at
		z.kind = sp.kind
		z.option = sp.option
		z.locked = sp.kind == ExtractionPlan.KIND_HATCH
		z.rank = sp.rank
		z._compute_geometry()
		out.append(z)
	return out


## État à l'instant `t` (s, horloge du raid).
func state_at(t: float) -> int:
	if t < opens_at:
		return State.DORMANT
	if t >= closes_at:
		return State.CLOSED
	if closes_at - t <= Balance.get_float("extraction", "close_warning", 30.0):
		return State.CLOSING
	return State.OPEN


func is_open() -> bool:
	return (state == State.OPEN or state == State.CLOSING) and not locked


func is_hatch() -> bool:
	return kind == ExtractionPlan.KIND_HATCH


func is_permanent() -> bool:
	return kind == ExtractionPlan.KIND_PERMANENT


## Trappe : ouverture (clef utilisée ici ou chez le coéquipier). Renvoie false si déjà ouverte.
func unlock() -> bool:
	if not locked:
		return false
	locked = false
	if _hatch != null:
		_hatch.set_open(true)
	return true


## Secondes avant fermeture (INF si la zone ne ferme pas).
func remaining_at(t: float) -> float:
	return closes_at - t if closes_at != INF else INF


## Libellé de minuteur (« 3:05 », « URGENCE », « FERMÉE »).
static func format_time(sec: float) -> String:
	var s := maxi(ceili(sec), 0)
	return "%d:%02d" % [s / 60, s % 60]


## Avance l'horloge : met à jour l'état (visuels) et le minuteur. Renvoie l'état.
func update_clock(t: float) -> int:
	var st := state_at(t)
	if not is_node_ready():
		state = st
		_pending_clock = t
		return st
	if st != state:
		state = st
		_apply_state()
	_update_timer(t)
	return st


func _apply_state() -> void:
	visible = state != State.DORMANT
	var closed := state == State.CLOSED
	if _closed_mark != null:
		_closed_mark.visible = closed
	for n: Node2D in [_spinner, _beam, _smoke, _beacon_light, _icon.get_parent() if _icon != null else null]:
		if n != null:
			n.visible = not closed
	if _progress != null and closed:
		_progress.visible = false
	if _ground != null:
		_ground.self_modulate = Color(COL_CLOSED, 0.55) if closed else Color.WHITE
	if closed:
		for tw: Tween in _tweens:
			if tw != null and tw.is_valid():
				tw.kill()
		_tweens.clear()


func _update_timer(t: float) -> void:
	if _timer == null:
		return
	var txt := ""
	var col := COL
	var blink := false
	match state:
		State.CLOSED:
			txt = "FERMÉE"
			col = COL_CLOSED
		State.CLOSING:
			txt = format_time(closes_at - t)
			col = COL_WARN
			blink = fmod(t, 1.0) > 0.5
		_:
			txt = format_time(closes_at - t) if closes_at != INF else ""
	_timer.set_state(txt, col, blink)


func get_timer_text() -> String:
	return _timer.text if _timer != null else ""


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
	if is_hatch():
		_build_hatch()
		return
	_ground = ZoneGround.new()
	_ground.radius = radius
	add_child(_ground)
	_spinner = ZoneSpinner.new()
	_spinner.radius = radius
	add_child(_spinner)
	_build_beacon()
	_build_icon()
	_beam = ZoneBeam.new()
	_beam.radius = radius
	_beam.modulate.a = 0.0
	add_child(_beam)
	_progress = ZoneProgress.new()
	_progress.radius = radius
	_progress.visible = false
	add_child(_progress)
	_closed_mark = ClosedMark.new()
	_closed_mark.radius = radius
	_closed_mark.visible = false
	add_child(_closed_mark)
	var th := Node2D.new()
	th.name = "Timer"
	th.z_as_relative = false
	th.z_index = 85
	th.position = Vector2(0, -radius - 82.0)
	add_child(th)
	_timer = ZoneTimer.new()
	th.add_child(_timer)
	_start_animations()
	if _pending_clock >= 0.0:
		_apply_state()
		_update_timer(_pending_clock)


## Trappe d'urgence : rendu de trappe (fermée / ouverte), colonne et anneau de progression
## (canalisation), cachée hors du champ de vision comme les conteneurs.
func _build_hatch() -> void:
	name = "HatchZone"
	add_to_group(&"fog_hideable")
	_hatch = HatchSprite.new()
	_hatch.set_open(not locked)
	add_child(_hatch)
	_beam = ZoneBeam.new()
	_beam.radius = radius
	_beam.modulate.a = 0.0
	add_child(_beam)
	_progress = ZoneProgress.new()
	_progress.radius = radius
	_progress.visible = false
	add_child(_progress)


func is_hatch_open_visual() -> bool:
	return _hatch != null and _hatch.opened


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
	_smoke = smoke
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
	_spin_tween = spin
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
	if _progress == null or (on and state == State.CLOSED):
		return
	_progress.visible = on
	if _icon != null:
		_icon.get_parent().visible = not on
	if on:
		_progress.set_state(0.0, Raid.extraction_channel_time())
	else:
		_set_intensity(0.0)


## p = 0..1, remaining = secondes restantes.
func set_progress(p: float, remaining: float) -> void:
	if _progress != null:
		_progress.set_state(p, remaining)
	_set_intensity(p)


## Colonne de lumière et vitesse de l'anneau selon la progression (0 = au repos).
func _set_intensity(p: float) -> void:
	var q := clampf(p, 0.0, 1.0)
	if _beam != null:
		_beam.modulate.a = 0.0 if q <= 0.0 else lerpf(Balance.get_float("extraction", "beam_alpha_min", 0.25),
			Balance.get_float("extraction", "beam_alpha_max", 0.8), q)
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.set_speed_scale(1.0 + Balance.get_float("extraction", "spin_boost", 9.0) * q)


## Réussite : colonne éblouissante qui s'élargit, gerbe d'éclats vers le haut.
func play_success(duration: float) -> void:
	if _progress != null:
		_progress.visible = false
	if _beam != null:
		_beam.modulate.a = 1.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(_beam, "scale", Vector2(1.6, 1.15), duration * 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(_beam, "modulate", Color(1.6, 1.6, 1.6, 1.0), duration * 0.5)
	var p := CPUParticles2D.new()
	p.z_as_relative = false
	p.z_index = 87
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = int(Balance.get_value("extraction", "success_particles", 60))
	p.lifetime = duration
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.6
	p.direction = Vector2.UP
	p.spread = 25.0
	p.initial_velocity_min = 220.0
	p.initial_velocity_max = 520.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color = COL.lightened(0.4)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.emitting = true
	add_child(p)


func is_progress_visible() -> bool:
	return _progress != null and _progress.visible


func get_progress_text() -> String:
	return _progress.text if _progress != null else ""


# =====================================================================================
# Morceaux dessinés une fois.

## Colonne de lumière de l'extraction : dégradé vertical additif, large au sol, qui s'efface
## vers le haut ; au-dessus du brouillard (visible de loin pendant la canalisation).
class ZoneBeam extends Node2D:
	var radius: float = 96.0

	func _init() -> void:
		z_as_relative = false
		z_index = 84
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func _draw() -> void:
		var h := Balance.get_float("extraction", "beam_height", 520.0)
		var w0 := radius * 0.95
		var w1 := radius * 0.55
		var steps := 12
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			# Fondu en bas (pas de bord net au sol) et vers le haut.
			var a0 := 0.55 * (1.0 - t0) * smoothstep(0.0, 0.18, t0)
			var a1 := 0.55 * (1.0 - t1) * smoothstep(0.0, 0.18, t1)
			var y0 := -h * t0
			var y1 := -h * t1
			var hw0 := lerpf(w0, w1, t0)
			var hw1 := lerpf(w0, w1, t1)
			var pts := PackedVector2Array([Vector2(-hw0, y0), Vector2(hw0, y0), Vector2(hw1, y1), Vector2(-hw1, y1)])
			var cols := PackedColorArray([Color(COL, a0), Color(COL, a0), Color(COL, a1), Color(COL, a1)])
			draw_polygon(pts, cols)
		# Cœur plus clair.
		var core := PackedVector2Array([Vector2(-w0 * 0.25, 0), Vector2(w0 * 0.25, 0), Vector2(w1 * 0.12, -h), Vector2(-w1 * 0.12, -h)])
		draw_polygon(core, PackedColorArray([Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)]))
		# Disque au sol.
		draw_circle(Vector2.ZERO, radius * 0.9, Color(COL, 0.18))


## Intensité affichée de la colonne de lumière (tests).
func get_beam_alpha() -> float:
	return _beam.modulate.a if _beam != null else 0.0

## Zone fermée : grand X barré et contour gris par-dessus la plaque.
class ClosedMark extends Node2D:
	var radius: float = 96.0

	func _init() -> void:
		z_index = 2

	func _draw() -> void:
		var r := radius * 0.62
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(COL_CLOSED, 0.8), 3.0, true)
		for k in 2:
			var a := Vector2(r, r) if k == 0 else Vector2(r, -r)
			draw_line(-a, a, Color(0.05, 0.05, 0.08, 0.7), 14.0, true)
			draw_line(-a, a, Color(0.85, 0.3, 0.28, 0.9), 7.0, true)


## Minuteur au-dessus de la zone (pastille encre, texte coloré) ; redessiné quand il change.
class ZoneTimer extends Node2D:
	var text: String = ""
	var color: Color = COL
	var dim: bool = false

	func set_state(t: String, c: Color, blink: bool) -> void:
		if t == text and c == color and blink == dim:
			return
		text = t
		color = c
		dim = blink
		queue_redraw()

	func _draw() -> void:
		if text == "":
			return
		var font := LootVisuals.text_font(900)
		var fs := 22
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pill := Rect2(Vector2(-w * 0.5 - 12.0, -16.0), Vector2(w + 24.0, 32.0))
		draw_rect(pill, Color(0.024, 0.027, 0.05, 0.85))
		draw_rect(pill, Color(color, 0.9), false, 2.0)
		var c := Color(color.lightened(0.25), 0.45 if dim else 1.0)
		draw_string(font, Vector2(-w * 0.5, 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)


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
	## Pastille « Extraction… N s » au-dessus de l'anneau (masquée : le compte à rebours plein
	## écran d'ExtractionOverlay la remplace ; [extraction] ring_label).
	var show_label: bool = Balance.get_value("extraction", "ring_label", false) == true

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
		if not show_label:
			return
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


## Trappe d'urgence : rendu Blender (art/blender/build_hatch.py) fermé / ouvert, point d'appui
## lu dans hatch.json ; repli dessiné (cadre à bandes vert et noir, battants, chevrons) si les
## images manquent.
class HatchSprite extends Node2D:
	const DIR := "res://assets/sprites/extraction/"
	## Rendus à 2 px par unité monde : affichés à l'échelle 0,5.
	const RENDER_SCALE := 0.5
	static var _meta: Dictionary = {}
	var opened: bool = false
	var _sprite: Sprite2D = null

	func set_open(o: bool) -> void:
		opened = o
		if not is_node_ready():
			return
		_refresh()

	func _ready() -> void:
		_sprite = Sprite2D.new()
		_sprite.centered = false
		_sprite.scale = Vector2(RENDER_SCALE, RENDER_SCALE)
		add_child(_sprite)
		_refresh()

	static func meta() -> Dictionary:
		if _meta.is_empty() and FileAccess.file_exists(DIR + "hatch.json"):
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "hatch.json"))
			if v is Dictionary:
				_meta = v
		return _meta

	func _refresh() -> void:
		var key := "hatch_open" if opened else "hatch"
		var path := DIR + key + ".png"
		var info: Dictionary = meta().get(key, {})
		if ResourceLoader.exists(path) and not info.is_empty():
			_sprite.texture = load(path) as Texture2D
			var feet: Array = info.get("feet", [0, 0])
			_sprite.position = -Vector2(float(feet[0]), float(feet[1])) * RENDER_SCALE
			_sprite.visible = true
		else:
			_sprite.visible = false
		queue_redraw()

	func _draw() -> void:
		if _sprite != null and _sprite.visible:
			return
		var h := TS * 0.95
		var r := Rect2(-h, -h, h * 2.0, h * 2.0)
		draw_rect(r.grow(6.0), Color(0.16, 0.17, 0.2))
		var n := 10
		for i in n:
			var c := COL if i % 2 == 0 else Color(0.05, 0.06, 0.06)
			draw_rect(Rect2(r.position.x + r.size.x * i / n, r.position.y - 6.0, r.size.x / n, 6.0), c)
			draw_rect(Rect2(r.position.x + r.size.x * i / n, r.end.y, r.size.x / n, 6.0), c)
		var inner := r.grow(-14.0)
		draw_rect(inner, Color(0.02, 0.03, 0.03) if opened else Color(0.3, 0.32, 0.36))
		if opened:
			for k in 5:
				var y := inner.position.y + 10.0 + k * inner.size.y / 5.0
				draw_line(Vector2(-18, y), Vector2(18, y), Color(0.55, 0.42, 0.3), 4.0)
		else:
			draw_line(Vector2(0, inner.position.y), Vector2(0, inner.end.y), Color(0.12, 0.13, 0.15), 3.0)
		for k in 2:
			var y0 := -h - 40.0 + k * 22.0
			draw_polyline(PackedVector2Array([Vector2(-22, y0), Vector2(0, y0 + 16), Vector2(22, y0)]), COL, 7.0, true)
