class_name ArenaDummy
extends TargetDummy
## Mannequin d'entraînement de l'arène de test : TargetDummy avec beaucoup de PV
## ([test_arena] dummy_hp), un compteur (DamageMeter : dernier coup, DPS sur 5 s, total) affiché
## dans un cartouche encre sous les pieds, et un aller-retour optionnel (`moving`) sur
## [test_arena] dummy_move_range px à dummy_move_speed px/s.

var meter: DamageMeter = null
var moving: bool = false
var move_axis: Vector2 = Vector2.RIGHT
var _origin: Vector2 = Vector2.ZERO
var _phase: float = 0.0
var _label: Label = null
var _clock: float = 0.0


func _init() -> void:
	# Même collision que scenes/enemies/target_dummy.tscn (créé en code, sans scène).
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var cs := CollisionShape2D.new()
	cs.name = "CollisionShape2D"
	var shape := CircleShape2D.new()
	shape.radius = Balance.get_float("test_arena", "dummy_radius", 26.0)
	cs.shape = shape
	cs.position = Vector2(0, -12)
	add_child(cs)


func _ready() -> void:
	super._ready()
	max_hp = Balance.get_float("test_arena", "dummy_hp", 100000.0)
	hp = max_hp
	respawn_delay = Balance.get_float("test_arena", "dummy_respawn_delay", 1.0)
	meter = DamageMeter.new(Balance.get_float("test_arena", "dps_window", 5.0))
	_origin = position
	_label = Label.new()
	_label.name = "MeterLabel"
	_label.add_theme_font_override("font", MenuKit.nunito(700))
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", MenuKit.TEXT)
	_label.add_theme_stylebox_override("normal", CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.82), 6.0,
		Color(MenuKit.VIOLET, 0.9), 1.0, 8.0, 3.0))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.z_index = 30
	add_child(_label)
	_refresh_label()


func _process(delta: float) -> void:
	super._process(delta)
	_clock += delta
	_refresh_label()


func _physics_process(delta: float) -> void:
	if not moving:
		return
	var speed := Balance.get_float("test_arena", "dummy_move_speed", 120.0)
	var span := maxf(Balance.get_float("test_arena", "dummy_move_range", 220.0), 1.0)
	_phase += delta * speed / span
	position = _origin + move_axis * sin(_phase) * span * 0.5


func take_damage(amount: float, source: Node) -> void:
	if not is_alive() or amount <= 0.0:
		return
	if meter != null:
		meter.add(amount, _clock)
	super.take_damage(amount, source)
	_refresh_label()


## Remise à zéro : compteur vidé, PV pleins, retour au point de départ.
func reset_meter() -> void:
	if meter != null:
		meter.reset()
	hp = max_hp
	_phase = 0.0
	position = _origin
	_refresh_label()


## Horloge interne (s) utilisée par le compteur.
func clock() -> float:
	return _clock


func _refresh_label() -> void:
	if _label == null or meter == null:
		return
	_label.text = meter.text(_clock)
	_label.size = _label.get_minimum_size()
	_label.position = Vector2(-_label.size.x * 0.5, 16.0)
