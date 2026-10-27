class_name DoorNode
extends StaticBody2D
## Porte du monde (module « Portes », cf. docs/CONVENTIONS.md, phase 3).
## Fermée : collision sur la couche world (bloque déplacement ET lignes de vue,
## les raycasts utilisant la couche world). Ouverte : plus aucune collision.
## S'ouvre automatiquement au contact du joueur ou d'un ennemi en poursuite
## (zone Area2D un peu plus grande que la case). Verrouillée : cadenas visible,
## message « Clef requise » au contact, ouverture par try_unlock(key_id).
## Reste ouverte une fois ouverte (pas de refermeture automatique).
##
## Origine du nœud : milieu du BORD BAS de la case (tri en Y cohérent avec les
## murs vus en 3/4). Visuels dessinés en code : porte en bois, portes battantes
## de saloon, grille de coffre-fort.

signal state_changed(door: DoorNode)
## Le joueur a touché la porte verrouillée sans la bonne clef.
signal locked_bumped(door: DoorNode)

const LAYER_WORLD := 1
const MASK_PLAYER := 2
const MASK_ENEMIES := 4
const TS := float(FloorLayout.TILE_SIZE)

const KIND_WOOD := &"wood"
const KIND_SALOON := &"saloon"
const KIND_VAULT := &"vault"

const COL_OUTLINE := Color(0.09, 0.05, 0.07)
const COL_FRAME := Color(0.42, 0.27, 0.17)
const COL_FRAME_LIGHT := Color(0.78, 0.56, 0.34)
const COL_CAP := Color(0.27, 0.17, 0.13)
const COL_WOOD := Color(0.62, 0.4, 0.24)
const COL_WOOD_DARK := Color(0.36, 0.21, 0.13)
const COL_SALOON := Color(0.55, 0.16, 0.12)
const COL_SALOON_TRIM := Color(0.98, 0.86, 0.6)
const COL_IRON := Color(0.36, 0.38, 0.47)
const COL_IRON_LIGHT := Color(0.75, 0.78, 0.86)
const COL_BRASS := Color(1.0, 0.78, 0.3)
const COL_DARK := Color(0.08, 0.07, 0.12, 0.85)

## Case de la porte (contrat CONVENTIONS).
@export var cell: Vector2i = Vector2i.ZERO
## true : porte dans un mur vertical (on la traverse horizontalement).
@export var vertical: bool = false
## wood, saloon, vault.
@export var kind: StringName = KIND_WOOD
## Clef requise quand la porte est verrouillée.
@export var key_id: StringName = &""
## Hauteur de la face avant du mur (unités monde), fixée par le WorldBuilder.
## Le mur occupe sa case : dessus sur [-TS, -wall_height], face sur [-wall_height, 0].
var wall_height: float = 52.0
## Donnée de carte associée (mise à jour quand l'état change), peut être null.
var data: FloorLayout.Door = null

var _state: int = FloorLayout.DoorState.CLOSED
var _open_t: float = 0.0
var _anim_time: float = 0.0
var _redraw_left: float = 0.0
var _poll_left: float = 0.0
var _bodies_inside: int = 0
var _built: bool = false
var _shape: CollisionShape2D = null
var _trigger: Area2D = null
var _label: Label = null
var _label_tween: Tween = null

# Équilibrage (balance.cfg, section [door])
var trigger_margin: float = 14.0
var open_duration: float = 0.22
var enemy_check_interval: float = 0.2
var locked_message_duration: float = 1.4


func _init() -> void:
	add_to_group(&"doors")


func _ready() -> void:
	_ensure_built()
	_apply_collision()


## Configure la porte depuis la donnée de carte. `p_kind` vide : déduit
## (verrouillée → grille de coffre, sinon bois). Place le nœud sur la case.
func setup(d: FloorLayout.Door, p_kind: StringName = &"", p_wall_height: float = -1.0) -> void:
	data = d
	cell = d.cell
	vertical = d.vertical
	key_id = d.key_id
	if p_kind != &"":
		kind = p_kind
	elif d.state == FloorLayout.DoorState.LOCKED:
		kind = KIND_VAULT
	if p_wall_height > 0.0:
		wall_height = p_wall_height
	position = Vector2((cell.x + 0.5) * TS, (cell.y + 1.0) * TS)
	_state = d.state
	_open_t = 1.0 if _state == FloorLayout.DoorState.OPEN else 0.0
	_ensure_built()
	_apply_collision()
	queue_redraw()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	trigger_margin = Balance.get_float("door", "trigger_margin", 14.0)
	open_duration = Balance.get_float("door", "open_duration", 0.22)
	enemy_check_interval = Balance.get_float("door", "enemy_check_interval", 0.2)
	locked_message_duration = Balance.get_float("door", "locked_message_duration", 1.4)
	collision_mask = 0
	_shape = CollisionShape2D.new()
	_shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(TS, TS)
	_shape.shape = rect
	_shape.position = Vector2(0.0, -TS * 0.5)
	add_child(_shape)
	_trigger = Area2D.new()
	_trigger.name = "Trigger"
	_trigger.collision_layer = 0
	_trigger.collision_mask = MASK_PLAYER | MASK_ENEMIES
	_trigger.monitorable = false
	var ts := CollisionShape2D.new()
	var tr := RectangleShape2D.new()
	tr.size = Vector2(TS, TS) + Vector2.ONE * trigger_margin * 2.0
	ts.shape = tr
	ts.position = Vector2(0.0, -TS * 0.5)
	_trigger.add_child(ts)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)
	_trigger.body_exited.connect(_on_body_exited)


# --- API -------------------------------------------------------------------

func is_open() -> bool:
	return _state == FloorLayout.DoorState.OPEN


func is_locked() -> bool:
	return _state == FloorLayout.DoorState.LOCKED


func get_state() -> int:
	return _state


## Ouvre la porte si elle n'est pas verrouillée (sinon : rien, utiliser try_unlock).
func open() -> void:
	if is_open() or is_locked():
		return
	_set_state(FloorLayout.DoorState.OPEN)


## Referme la porte (non verrouillée).
func close() -> void:
	if not is_open():
		return
	_set_state(FloorLayout.DoorState.CLOSED)


## Déverrouille et ouvre si `p_key_id` correspond. Porte non verrouillée : l'ouvre
## et renvoie true. Mauvaise clef : false, la porte reste verrouillée.
func try_unlock(p_key_id: StringName) -> bool:
	if is_locked():
		if p_key_id == &"" or p_key_id != key_id:
			return false
		_state = FloorLayout.DoorState.CLOSED
		_set_state(FloorLayout.DoorState.OPEN)
		return true
	open()
	return true


func _set_state(s: int) -> void:
	_state = s
	if data != null:
		data.state = s
	_apply_collision()
	set_process(true)
	queue_redraw()
	state_changed.emit(self)


func _apply_collision() -> void:
	if _shape == null:
		return
	var closed := not is_open()
	var layer := LAYER_WORLD if closed else 0
	# La couche suffit à (dé)bloquer immédiatement ; la forme est désactivée en
	# différé si on est dans un rappel physique (body_entered).
	collision_layer = layer
	if Engine.is_in_physics_frame():
		_shape.set_deferred(&"disabled", not closed)
	else:
		_shape.disabled = not closed


# --- Contact -----------------------------------------------------------------

func _on_body_entered(body: Node2D) -> void:
	_bodies_inside += 1
	_handle_body(body, true)


func _on_body_exited(_body: Node2D) -> void:
	_bodies_inside = maxi(_bodies_inside - 1, 0)


func _handle_body(body: Node2D, entering: bool) -> void:
	if is_open() or body == null:
		return
	if body.is_in_group(&"player"):
		if is_locked():
			if entering:
				_bump()
		else:
			open()
	elif _is_pursuing_enemy(body) and not is_locked():
		open()


## Un ennemi n'ouvre que s'il poursuit (états d'alerte/poursuite/attaque).
static func _is_pursuing_enemy(body: Node) -> bool:
	if not (body.is_in_group(&"enemies") or body.is_in_group(&"enemy_units")):
		return false
	if body.has_method("is_in_combat"):
		return bool(body.call("is_in_combat"))
	return false


func _physics_process(delta: float) -> void:
	# Un ennemi déjà dans la zone peut passer en poursuite plus tard : on revérifie.
	if is_open() or _bodies_inside <= 0 or _trigger == null:
		return
	_poll_left -= delta
	if _poll_left > 0.0:
		return
	_poll_left = enemy_check_interval
	for b: Node2D in _trigger.get_overlapping_bodies():
		if not b.is_in_group(&"player"):
			_handle_body(b, false)


func _bump() -> void:
	locked_bumped.emit(self)
	_show_locked_message()


func _show_locked_message() -> void:
	if _label == null:
		_label = Label.new()
		_label.name = "LockedLabel"
		_label.text = "Clef requise"
		var ls := LabelSettings.new()
		ls.font_size = 18
		ls.font_color = Color(1.0, 0.93, 0.78)
		ls.outline_size = 6
		ls.outline_color = Color(0.07, 0.1, 0.18)
		_label.label_settings = ls
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.size = Vector2(140.0, 26.0)
		_label.z_as_relative = false
		_label.z_index = 60
		add_child(_label)
	var base := Vector2(-70.0, -TS - 34.0)
	_label.position = base
	_label.modulate.a = 1.0
	_label.visible = true
	if _label_tween != null and _label_tween.is_valid():
		_label_tween.kill()
	if not is_inside_tree():
		return
	_label_tween = create_tween()
	_label_tween.set_parallel(true)
	_label_tween.tween_property(_label, "position", base + Vector2(0.0, -16.0), locked_message_duration)
	_label_tween.tween_property(_label, "modulate:a", 0.0, locked_message_duration * 0.4).set_delay(locked_message_duration * 0.6)


## Message de verrou affiché (tests).
func is_locked_message_visible() -> bool:
	return _label != null and _label.visible and _label.modulate.a > 0.01


# --- Animation & dessin ------------------------------------------------------

func _process(delta: float) -> void:
	var target := 1.0 if is_open() else 0.0
	if not is_equal_approx(_open_t, target):
		_open_t = move_toward(_open_t, target, delta / maxf(open_duration, 0.01))
		queue_redraw()
	elif is_locked():
		# Lueur du sceau : redessin à ~15 i/s.
		_anim_time += delta
		_redraw_left -= delta
		if _redraw_left <= 0.0:
			_redraw_left = 1.0 / 15.0
			queue_redraw()
	else:
		set_process(false)


## Progression de l'animation d'ouverture (0 fermé → 1 ouvert).
func get_open_progress() -> float:
	return _open_t


func _draw() -> void:
	# Ease-out : la porte s'ouvre vite puis ralentit.
	var t := 1.0 - pow(1.0 - _open_t, 3.0)
	if vertical:
		_draw_vertical(t)
	else:
		_draw_horizontal(t)


func _draw_horizontal(t: float) -> void:
	var h := wall_height
	var half := TS * 0.5
	# Linteau (dessus du mur au-dessus de la porte).
	var cap := Rect2(-half, -TS, TS, TS - h)
	draw_rect(cap, COL_CAP)
	draw_line(cap.position + Vector2(0, 1), Vector2(cap.end.x, cap.position.y + 1), COL_FRAME_LIGHT.darkened(0.3), 2.0)
	draw_rect(cap, COL_OUTLINE, false, 1.5)
	# Ouverture sombre (visible pendant l'ouverture).
	var opening := Rect2(-half + 6.0, -h + 6.0, TS - 12.0, h - 6.0)
	if t < 0.999:
		draw_rect(opening, Color(COL_DARK, COL_DARK.a * (1.0 - t)))
	# Battants.
	match kind:
		KIND_SALOON:
			var lift := 12.0
			var hh := h * 0.56
			var ang := t * deg_to_rad(80.0)
			_draw_leaf(Vector2(-half + 6.0, -lift), Vector2(cos(ang), -sin(ang)) * (half - 6.0), hh, COL_SALOON, true)
			_draw_leaf(Vector2(half - 6.0, -lift), Vector2(-cos(ang), -sin(ang)) * (half - 6.0), hh, COL_SALOON, true)
		KIND_VAULT:
			_draw_grille_front(opening, t)
		_:
			var ang2 := t * deg_to_rad(95.0)
			_draw_leaf(Vector2(-half + 6.0, -3.0), Vector2(cos(ang2), -sin(ang2)) * (TS - 12.0), h - 9.0, COL_WOOD, false)
	# Chambranle.
	draw_rect(Rect2(-half, -h, 6.0, h), COL_FRAME)
	draw_rect(Rect2(half - 6.0, -h, 6.0, h), COL_FRAME)
	draw_rect(Rect2(-half, -h, TS, 6.0), COL_FRAME)
	draw_line(Vector2(-half + 1.0, -h), Vector2(-half + 1.0, 0.0), COL_FRAME_LIGHT, 2.0)
	draw_rect(Rect2(-half, -h, TS, h), COL_OUTLINE, false, 2.0)
	draw_rect(Rect2(-half + 6.0, -h + 6.0, TS - 12.0, h - 6.0), COL_OUTLINE, false, 1.5)
	if is_locked():
		_draw_padlock(Vector2(0.0, -h * 0.45))


func _draw_vertical(t: float) -> void:
	# Porte dans un mur vertical : vue « de dessus » (le mur vertical n'a pas de
	# face visible). Battant = planche épaisse qui pivote autour de sa charnière.
	var top := -TS + 4.0
	var length := TS - 8.0
	draw_rect(Rect2(-9.0, -TS, 18.0, TS), Color(COL_FRAME.darkened(0.2), 0.7))
	match kind:
		KIND_SALOON:
			var ang := t * deg_to_rad(80.0)
			var hl := length * 0.5
			_draw_slab(Vector2(0.0, top), Vector2(sin(ang), cos(ang)) * hl, COL_SALOON, 9.0)
			_draw_slab(Vector2(0.0, -4.0), Vector2(sin(ang), -cos(ang)) * hl, COL_SALOON, 9.0)
		KIND_VAULT:
			var vis := 1.0 - t
			if vis > 0.02:
				for k: int in 7:
					var p := Vector2(0.0, top + 4.0 + float(k) * (length - 8.0) / 6.0)
					draw_circle(p, 5.5 * vis, COL_OUTLINE)
					draw_circle(p, 3.8 * vis, COL_IRON)
					draw_circle(p + Vector2(-1, -1), 1.6 * vis, COL_IRON_LIGHT)
				draw_line(Vector2(0.0, top), Vector2(0.0, top + length * vis), COL_OUTLINE, 3.0)
		_:
			var ang2 := t * deg_to_rad(95.0)
			_draw_slab(Vector2(0.0, top), Vector2(sin(ang2), cos(ang2)) * length, COL_WOOD, 12.0)
	# Montants aux extrémités (bouts de mur).
	for y: float in [-TS + 2.0, -2.0]:
		draw_rect(Rect2(-11.0, y - 5.0, 22.0, 10.0), COL_FRAME)
		draw_rect(Rect2(-11.0, y - 5.0, 22.0, 10.0), COL_OUTLINE, false, 1.5)
	if is_locked():
		_draw_padlock(Vector2(0.0, -TS * 0.5))


## Battant vu de dessus : planche épaisse de `a` à `a + dir_len` (+ chant avant).
func _draw_slab(a: Vector2, dir_len: Vector2, col: Color, w: float) -> void:
	var b := a + dir_len
	draw_line(a + Vector2(0, 4), b + Vector2(0, 4), col.darkened(0.45), w + 3.0)
	draw_line(a, b, COL_OUTLINE, w + 3.0)
	draw_line(a, b, col, w)
	draw_line(a + Vector2(-w * 0.25, 0), b + Vector2(-w * 0.25, 0), col.lightened(0.3), 2.0)
	draw_circle(b, w * 0.5 + 1.5, COL_OUTLINE)


## Battant posé au sol de `a` à `a + dir_len`, de hauteur `h` (levé de `lift`).
## Panneau vertical vu en 3/4 + chant supérieur épais (lisible même vu de profil).
func _draw_leaf(a: Vector2, dir_len: Vector2, h: float, col: Color, batwing: bool, lift: float = 0.0) -> void:
	a -= Vector2(0.0, lift)
	var b := a + dir_len
	var up := Vector2(0.0, h)
	var b_top := b - up * (0.78 if batwing else 1.0)
	var poly := PackedVector2Array([a, b, b_top, a - up])
	# Teinte : battant de face = éclairé ; de profil = plus sombre.
	var facing := absf(dir_len.normalized().x)
	var c := col.lerp(col.darkened(0.35), 1.0 - facing)
	if facing > 0.05:
		draw_colored_polygon(poly, c)
		# Lattes / planches.
		for i: int in range(1, 4):
			var f := float(i) / 4.0
			var p := a.lerp(b, f)
			var q := (a - up).lerp(b_top, f)
			if batwing:
				var pa := a.lerp(a - up, f)
				var pb := b.lerp(b_top, f)
				draw_line(pa, pb, c.darkened(0.3), 1.5)
			else:
				draw_line(p, q, c.darkened(0.3), 1.5)
		if not batwing:
			draw_line(a - up * 0.2, b - up * 0.75, COL_WOOD_DARK, 3.0)
			draw_circle(b.lerp(a, 0.12) - up * 0.45, 2.5, COL_BRASS)
		else:
			draw_line(a - up, b_top, COL_SALOON_TRIM, 2.0)
		poly.append(a)
		draw_polyline(poly, COL_OUTLINE, 1.6)
	# Chant supérieur et chant libre.
	draw_line(a - up, b_top, COL_OUTLINE, 6.0)
	draw_line(a - up, b_top, c.lightened(0.25), 3.0)
	draw_line(b, b_top, COL_OUTLINE, 5.0)
	draw_line(b, b_top, c.darkened(0.1), 2.5)


func _draw_grille_front(opening: Rect2, t: float) -> void:
	var vis := 1.0 - t
	if vis <= 0.01:
		return
	var y0 := opening.position.y
	var y1 := y0 + opening.size.y * vis
	var x := opening.position.x + 3.0
	while x < opening.end.x - 1.0:
		draw_line(Vector2(x, y0), Vector2(x, y1), COL_OUTLINE, 5.0)
		draw_line(Vector2(x, y0), Vector2(x, y1), COL_IRON, 3.0)
		draw_line(Vector2(x - 0.8, y0), Vector2(x - 0.8, y1), COL_IRON_LIGHT, 1.0)
		x += 8.0
	for f: float in [0.12, 0.55, 0.95]:
		var yy := y0 + (y1 - y0) * f
		draw_rect(Rect2(opening.position.x, yy - 2.5, opening.size.x, 5.0), COL_IRON)
		draw_rect(Rect2(opening.position.x, yy - 2.5, opening.size.x, 5.0), COL_OUTLINE, false, 1.2)


func _draw_padlock(p: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_time * 3.0)
	draw_circle(p, 16.0 + pulse * 3.0, Color(1.0, 0.72, 0.2, 0.18 + 0.12 * pulse))
	draw_arc(p + Vector2(0.0, -6.0), 6.0, PI, TAU, 10, COL_OUTLINE, 5.0)
	draw_arc(p + Vector2(0.0, -6.0), 6.0, PI, TAU, 10, COL_IRON_LIGHT, 2.5)
	var body := Rect2(p + Vector2(-8.0, -6.0), Vector2(16.0, 13.0))
	draw_rect(body, COL_BRASS)
	draw_rect(Rect2(body.position, Vector2(16.0, 4.0)), COL_BRASS.lightened(0.4))
	draw_rect(body, COL_OUTLINE, false, 2.0)
	draw_circle(p + Vector2(0.0, 1.0), 2.0, COL_OUTLINE)
