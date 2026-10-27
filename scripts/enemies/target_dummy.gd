class_name TargetDummy
extends CharacterBody2D
## Cible d'entraînement immobile. Encaisse des dégâts, affiche une barre de vie
## et des chiffres flottants, meurt puis réapparaît après `respawn_delay`.
## Respecte l'interface de dégâts du contrat (take_damage / is_alive).

## Émis à chaque coup reçu (utile pour les tests et le debug).
signal damaged(amount: float, current_hp: float)

enum Look { MANNEQUIN, GOLEM }

const LAYER_ENEMIES := 4
const GROUP_ENEMIES := &"enemies"
const GROUP_DAMAGEABLE := &"damageable"

## Durée du flash blanc au coup (purement visuel).
const FLASH_DURATION := 0.12
## Durée de vie d'un chiffre de dégâts flottant (purement visuel).
const DAMAGE_NUMBER_DURATION := 0.75
const DAMAGE_NUMBER_RISE := 56.0
const HP_BAR_SIZE := Vector2(64.0, 9.0)
const HP_BAR_OFFSET_Y := -62.0

## Apparence du placeholder : mannequin de pierre ou golem de pierre (tous deux massifs).
@export var variant: Look = Look.MANNEQUIN

var max_hp: float = 60.0
var hp: float = 60.0
var respawn_delay: float = 2.0

var _alive: bool = true
var _respawn_left: float = 0.0
var _flash_left: float = 0.0
var _wobble: float = 0.0


func _ready() -> void:
	add_to_group(&"enemy_units")
	max_hp = Balance.get_float("target_dummy", "max_hp", 60.0)
	respawn_delay = Balance.get_float("target_dummy", "respawn_delay", 2.0)
	collision_layer = LAYER_ENEMIES
	collision_mask = 0
	_spawn()


func _process(delta: float) -> void:
	var needs_redraw := false
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		needs_redraw = true
	if _wobble > 0.0:
		_wobble = maxf(_wobble - delta * 4.0, 0.0)
		needs_redraw = true
	if not _alive:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_spawn()
		needs_redraw = true
	if needs_redraw:
		queue_redraw()


# --- Interface de dégâts -----------------------------------------------------

func take_damage(amount: float, source: Node) -> void:
	if not _alive or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_flash_left = FLASH_DURATION
	_wobble = 1.0
	_spawn_damage_number(amount)
	damaged.emit(amount, hp)
	queue_redraw()
	if hp <= 0.0:
		_die(source)


func is_alive() -> bool:
	return _alive


## Temps restant avant réapparition (0 si vivant).
func get_respawn_time_left() -> float:
	return 0.0 if _alive else maxf(_respawn_left, 0.0)


# --- Cycle de vie ------------------------------------------------------------

func _spawn() -> void:
	_alive = true
	hp = max_hp
	_respawn_left = 0.0
	add_to_group(GROUP_ENEMIES)
	add_to_group(GROUP_DAMAGEABLE)
	_set_collision_enabled(true)
	queue_redraw()
	EventBus.enemy_spawned.emit(self)


func _die(_source: Node) -> void:
	_alive = false
	_respawn_left = respawn_delay
	remove_from_group(GROUP_ENEMIES)
	remove_from_group(GROUP_DAMAGEABLE)
	_set_collision_enabled(false)
	queue_redraw()
	EventBus.enemy_died.emit(self, global_position)


func _set_collision_enabled(enabled: bool) -> void:
	# Différé : take_damage est souvent appelé pendant un callback physique.
	set_deferred("collision_layer", LAYER_ENEMIES if enabled else 0)
	for child: Node in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not enabled)


# --- Effets visuels ----------------------------------------------------------

func _spawn_damage_number(amount: float) -> void:
	var label := Label.new()
	label.text = str(roundi(amount)) if is_equal_approx(amount, roundf(amount)) else "%.1f" % amount
	var settings := LabelSettings.new()
	settings.font_size = 28
	settings.font_color = Color(1.0, 0.97, 0.9)
	settings.outline_size = 6
	settings.outline_color = Color(0.07, 0.10, 0.18)
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80.0, 34.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 50
	label.position = Vector2(-40.0 + randf_range(-14.0, 14.0), HP_BAR_OFFSET_Y - 70.0)
	add_child(label)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - DAMAGE_NUMBER_RISE, DAMAGE_NUMBER_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, DAMAGE_NUMBER_DURATION).set_delay(DAMAGE_NUMBER_DURATION * 0.35)
	tween.chain().tween_callback(label.queue_free)


func _draw() -> void:
	# Ombre portée bleu nuit (lumière de coucher de soleil rasante).
	draw_set_transform(Vector2(10, 22), 0.0, Vector2(1.25, 0.42))
	draw_circle(Vector2.ZERO, 32.0, SHADOW)
	draw_set_transform(Vector2.ZERO)

	if not _alive:
		_draw_broken()
		return

	var tilt := sin(_wobble * 18.0) * 0.12 * _wobble
	draw_set_transform(Vector2(0, 20), tilt, Vector2.ONE)
	if variant == Look.GOLEM:
		_draw_golem()
	else:
		_draw_mannequin()
	draw_set_transform(Vector2.ZERO)

	if _flash_left > 0.0:
		var a := _flash_left / FLASH_DURATION
		draw_circle(Vector2(0, -24), 34.0, Color(1, 1, 1, 0.5 * a))

	_draw_hp_bar()


# Palette pierre ocre, ombres bleu nuit, accent rouge à emblème blanc.
const OUTLINE := Color(0.11, 0.09, 0.14)
const SHADOW := Color(0.07, 0.10, 0.22, 0.45)
const OCHRE_LIGHT := Color(0.93, 0.74, 0.47)
const OCHRE := Color(0.78, 0.58, 0.36)
const OCHRE_SHADE := Color(0.47, 0.36, 0.38)
const BANNER_RED := Color(0.78, 0.11, 0.12)


func _stone(c: Color) -> Color:
	return c.lerp(Color.WHITE, _flash_tint())


## Polygone rempli + contour net.
func _poly(points: PackedVector2Array, fill: Color, width: float = 2.5) -> void:
	draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, OUTLINE, width, true)


## Mannequin d'entraînement en blocs de pierre ocre, cible rouge peinte (coordonnées au pied).
func _draw_mannequin() -> void:
	# Socle.
	_poly(PackedVector2Array([Vector2(-28, 4), Vector2(28, 4), Vector2(24, -10), Vector2(-24, -10)]), _stone(OCHRE_SHADE))
	# Torse massif (face éclairée à gauche, ombre bleutée à droite).
	_poly(PackedVector2Array([Vector2(-24, -10), Vector2(24, -10), Vector2(30, -50), Vector2(20, -64), Vector2(-20, -64), Vector2(-30, -50)]), _stone(OCHRE))
	draw_colored_polygon(PackedVector2Array([Vector2(6, -10), Vector2(24, -10), Vector2(30, -50), Vector2(20, -64), Vector2(8, -64)]), Color(SHADOW, 0.35))
	draw_line(Vector2(-22, -14), Vector2(-26, -50), _stone(OCHRE_LIGHT), 3.0)
	# Épaulières.
	for side: float in [-1.0, 1.0]:
		_poly(PackedVector2Array([Vector2(28 * side, -48), Vector2(40 * side, -54), Vector2(38 * side, -66), Vector2(22 * side, -66)]), _stone(OCHRE_SHADE if side > 0.0 else OCHRE_LIGHT))
	# Tête cubique.
	_poly(PackedVector2Array([Vector2(-13, -64), Vector2(13, -64), Vector2(13, -86), Vector2(-13, -86)]), _stone(OCHRE_LIGHT))
	draw_line(Vector2(-8, -76), Vector2(8, -76), OUTLINE, 3.0)
	# Cible rouge peinte, emblème blanc.
	draw_circle(Vector2(0, -38), 12.0, BANNER_RED)
	draw_arc(Vector2(0, -38), 12.0, 0, TAU, 24, OUTLINE, 2.0, true)
	draw_circle(Vector2(0, -38), 6.5, Color(0.98, 0.96, 0.92))
	draw_circle(Vector2(0, -38), 3.0, BANNER_RED)


## Golem de pierre massif, cœur cristallin et yeux bleu clair.
func _draw_golem() -> void:
	# Bras-rochers.
	for side: float in [-1.0, 1.0]:
		_poly(PackedVector2Array([Vector2(26 * side, -60), Vector2(44 * side, -54), Vector2(46 * side, -14), Vector2(30 * side, -8), Vector2(24 * side, -30)]), _stone(OCHRE_SHADE if side > 0.0 else OCHRE))
	# Corps.
	_poly(PackedVector2Array([Vector2(-26, 0), Vector2(26, 0), Vector2(32, -46), Vector2(18, -68), Vector2(-18, -68), Vector2(-32, -46)]), _stone(OCHRE))
	draw_colored_polygon(PackedVector2Array([Vector2(8, 0), Vector2(26, 0), Vector2(32, -46), Vector2(18, -68), Vector2(10, -68)]), Color(SHADOW, 0.35))
	# Fissures.
	draw_polyline(PackedVector2Array([Vector2(-18, -56), Vector2(-11, -44), Vector2(-16, -30)]), OUTLINE, 1.5)
	draw_polyline(PackedVector2Array([Vector2(14, -20), Vector2(20, -10)]), OUTLINE, 1.5)
	# Tête enfoncée dans les épaules.
	_poly(PackedVector2Array([Vector2(-14, -66), Vector2(14, -66), Vector2(11, -88), Vector2(-11, -88)]), _stone(OCHRE_LIGHT))
	draw_rect(Rect2(-8, -80, 5, 4), Color(0.55, 0.85, 1.0))
	draw_rect(Rect2(3, -80, 5, 4), Color(0.55, 0.85, 1.0))
	# Cristal au cœur.
	_poly(PackedVector2Array([Vector2(0, -50), Vector2(8, -36), Vector2(0, -22), Vector2(-8, -36)]), Color(0.5, 0.85, 1.0), 1.5)


## Éboulis de pierre pendant l'attente de réapparition.
func _draw_broken() -> void:
	var col := Color(OCHRE, 0.85)
	for p: Vector2 in [Vector2(-18, 14), Vector2(12, 18), Vector2(0, 6), Vector2(20, 4), Vector2(-6, 20)]:
		_poly(PackedVector2Array([p + Vector2(-8, 2), p + Vector2(-3, -7), p + Vector2(7, -5), p + Vector2(8, 4), p + Vector2(0, 8)]), col, 1.5)
	# Jauge circulaire de réapparition.
	var ratio := 1.0 - clampf(_respawn_left / maxf(respawn_delay, 0.01), 0.0, 1.0)
	draw_arc(Vector2(0, -20), 16.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 32, Color(1, 0.85, 0.5, 0.9), 4.0, true)


func _draw_hp_bar() -> void:
	var ratio := clampf(hp / maxf(max_hp, 0.01), 0.0, 1.0)
	var bar := Rect2(Vector2(-HP_BAR_SIZE.x / 2.0, HP_BAR_OFFSET_Y - 36.0), HP_BAR_SIZE)
	draw_rect(bar.grow(2.0), Color(0.07, 0.10, 0.18))
	draw_rect(bar, Color(0.18, 0.06, 0.08))
	var fill := Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y))
	draw_rect(fill, Color(0.9, 0.2, 0.15).lerp(Color(0.35, 0.85, 0.3), ratio))
	draw_rect(bar.grow(2.0), Color(0.85, 0.88, 0.95, 0.7), false, 1.0)


func _flash_tint() -> float:
	return clampf(_flash_left / FLASH_DURATION, 0.0, 1.0) * 0.8
