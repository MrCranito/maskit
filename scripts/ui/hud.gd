class_name Hud
extends Control
## HUD minimal : grosse barre de vie du joueur en haut de l'écran (lisible sur mobile).
## Se met à jour via EventBus.player_spawned / player_damaged / player_died.

const NIGHT_BLUE := Color(0.071, 0.102, 0.18, 0.92)  # ~#121a2e
const BORDER_LIGHT := Color(0.85, 0.88, 0.95, 0.85)

var _bar: ProgressBar
var _hp_label: Label
var _hp: float = 0.0
var _max_hp: float = 0.0


func _ready() -> void:
	name = "Hud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	# Le joueur a pu apparaître avant le HUD.
	var fallback_max := Balance.get_float("player", "max_hp", 100.0)
	set_health(fallback_max, fallback_max)
	if is_instance_valid(GameState.player):
		_on_player_spawned(GameState.player)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	add_child(margin)

	# Charte UI : panneau bleu nuit, coins arrondis, bordure fine claire.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = NIGHT_BLUE
	panel_style.border_color = BORDER_LIGHT
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(16)
	panel_style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)
	margin.add_child(panel)

	_bar = ProgressBar.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.custom_minimum_size = Vector2(0, 48)
	_bar.show_percentage = false
	_bar.min_value = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.11)
	bg.set_corner_radius_all(10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.82, 0.13, 0.14)
	fill.set_corner_radius_all(10)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fill)
	panel.add_child(_bar)

	_hp_label = Label.new()
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var settings := LabelSettings.new()
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.9
	settings.font = bold
	settings.font_size = 30
	settings.font_color = Color.WHITE
	settings.outline_size = 6
	settings.outline_color = NIGHT_BLUE
	_hp_label.label_settings = settings
	_bar.add_child(_hp_label)


## Met à jour l'affichage (public pour les tests et d'autres systèmes).
func set_health(current: float, maximum: float) -> void:
	_max_hp = maxf(maximum, 1.0)
	_hp = clampf(current, 0.0, _max_hp)
	_bar.max_value = _max_hp
	_bar.value = _hp
	_hp_label.text = "%d / %d" % [ceili(_hp), ceili(_max_hp)]


func get_health() -> float:
	return _hp


func _on_player_spawned(player: Node2D) -> void:
	if not is_instance_valid(player):
		return
	var mh: Variant = player.get("max_hp")
	var h: Variant = player.get("hp")
	var maximum: float = float(mh) if mh != null else _max_hp
	var current: float = float(h) if h != null else maximum
	set_health(current, maximum)


func _on_player_damaged(_amount: float, current_hp: float, max_hp: float) -> void:
	set_health(current_hp, max_hp)


func _on_player_died() -> void:
	set_health(0.0, _max_hp)
