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

## Durée de vie d'un chiffre de dégâts flottant (purement visuel).
const DAMAGE_NUMBER_DURATION := 0.75
const DAMAGE_NUMBER_RISE := 56.0
const HP_BAR_SIZE := Vector2(64.0, 9.0)
## Marge entre le haut de la tête (EnemyVisual.get_head_offset) et la barre de vie.
const HP_BAR_GAP := 6.0
## Kind d'EnemyVisual utilisé par chaque apparence.
const LOOK_KINDS: Dictionary = {Look.MANNEQUIN: &"masked_grunt", Look.GOLEM: &"golem"}

## Apparence : soldat masqué (MANNEQUIN) ou golem de pierre (GOLEM).
@export var variant: Look = Look.MANNEQUIN:
	set(value):
		variant = value
		if _visual != null:
			_visual.setup(LOOK_KINDS.get(variant, &"masked_grunt"))
			_overlay.queue_redraw()

var max_hp: float = 60.0
var hp: float = 60.0
var respawn_delay: float = 2.0

var _alive: bool = true
var _respawn_left: float = 0.0
var _visual: EnemyVisual = null
var _overlay: Node2D = null
var _respawn_was_dead: bool = false


func _ready() -> void:
	add_to_group(&"enemy_units")
	max_hp = Balance.get_float("target_dummy", "max_hp", 60.0)
	respawn_delay = Balance.get_float("target_dummy", "respawn_delay", 2.0)
	collision_layer = LAYER_ENEMIES
	collision_mask = 0
	_visual = EnemyVisual.new()
	_visual.name = "Visual"
	add_child(_visual)
	_visual.setup(LOOK_KINDS.get(variant, &"masked_grunt"))
	# Barre de vie et jauge de réapparition, au-dessus du sprite.
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.z_index = 20
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_spawn()


func _process(delta: float) -> void:
	if not _alive:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_spawn()
		_overlay.queue_redraw()


# --- Interface de dégâts -----------------------------------------------------

func take_damage(amount: float, source: Node) -> void:
	if not _alive or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	_visual.flash_hit()
	_spawn_damage_number(amount)
	damaged.emit(amount, hp)
	_overlay.queue_redraw()
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
	if _respawn_was_dead:
		_visual.setup(LOOK_KINDS.get(variant, &"masked_grunt"))
	_respawn_was_dead = false
	_overlay.queue_redraw()
	EventBus.enemy_spawned.emit(self)


func _die(_source: Node) -> void:
	_alive = false
	_respawn_left = respawn_delay
	remove_from_group(GROUP_ENEMIES)
	remove_from_group(GROUP_DAMAGEABLE)
	_set_collision_enabled(false)
	_respawn_was_dead = true
	_visual.play_death()
	_overlay.queue_redraw()
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
	var head := _visual.get_head_offset()
	label.position = Vector2(-40.0 + randf_range(-14.0, 14.0), head.y - HP_BAR_GAP - HP_BAR_SIZE.y - 40.0)
	add_child(label)
	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - DAMAGE_NUMBER_RISE, DAMAGE_NUMBER_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, DAMAGE_NUMBER_DURATION).set_delay(DAMAGE_NUMBER_DURATION * 0.35)
	tween.chain().tween_callback(label.queue_free)


func _draw_overlay() -> void:
	var head := _visual.get_head_offset()
	if not _alive:
		# Jauge circulaire de réapparition, à mi-hauteur du corps.
		var ratio := 1.0 - clampf(_respawn_left / maxf(respawn_delay, 0.01), 0.0, 1.0)
		var c := Vector2(0.0, head.y * 0.45)
		_overlay.draw_arc(c, 16.0, 0.0, TAU, 32, Color(0.07, 0.10, 0.18, 0.6), 6.0, true)
		_overlay.draw_arc(c, 16.0, -PI / 2.0, -PI / 2.0 + TAU * ratio, 32, Color(1, 0.85, 0.5, 0.9), 4.0, true)
		return
	var ratio_hp := clampf(hp / maxf(max_hp, 0.01), 0.0, 1.0)
	var bar := Rect2(Vector2(-HP_BAR_SIZE.x / 2.0, head.y - HP_BAR_GAP - HP_BAR_SIZE.y), HP_BAR_SIZE)
	_overlay.draw_rect(bar.grow(2.0), Color(0.07, 0.10, 0.18))
	_overlay.draw_rect(bar, Color(0.18, 0.06, 0.08))
	var fill := Rect2(bar.position, Vector2(bar.size.x * ratio_hp, bar.size.y))
	_overlay.draw_rect(fill, Color(0.9, 0.2, 0.15).lerp(Color(0.35, 0.85, 0.3), ratio_hp))
	_overlay.draw_rect(bar.grow(2.0), Color(0.85, 0.88, 0.95, 0.7), false, 1.0)
