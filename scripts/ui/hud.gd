class_name Hud
extends Control
## HUD paysage (1280x720) : barre de vie compacte en haut à gauche (panneau bleu nuit,
## liseré or), lisible sur mobile. Mise à jour par signaux uniquement
## (EventBus.player_spawned / player_damaged / player_died) : aucun traitement par frame.
## Zones laissées libres pour les autres modules : haut centre = bandeau monde/salle
## (Raid), haut droite = bouton sac (inventaire), bas droite au-dessus du stick de visée
## = bouton « action ». Armes tenues (bas centre) + bouton de changement d'arme :
## WeaponHud (scripts/ui/weapon_hud.gd), enfant de ce HUD.

const NIGHT_BLUE := Color(0.071, 0.102, 0.18, 0.92)  # ~#121a2e
const BORDER_LIGHT := Color(0.85, 0.88, 0.95, 0.85)
const GOLD := Color(0.91, 0.72, 0.36)
const HP_FILL := Color(0.82, 0.13, 0.14)
const HP_LOW := Color(1.0, 0.35, 0.2)

var _bar: ProgressBar
var _hp_label: Label
var _fill_style: StyleBoxFlat
var _panel: PanelContainer
var _hp: float = -1.0
var _max_hp: float = -1.0
var weapon_hud: WeaponHud = null


func _ready() -> void:
	name = "Hud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	set_physics_process(false)
	_build_ui()
	weapon_hud = WeaponHud.new()
	add_child(weapon_hud)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.player_damaged.connect(_on_player_damaged)
	EventBus.player_died.connect(_on_player_died)
	# Le joueur a pu apparaître avant le HUD.
	var fallback_max := Balance.get_float("player", "max_hp", 100.0)
	set_health(fallback_max, fallback_max)
	if is_instance_valid(GameState.player):
		_on_player_spawned(GameState.player)


func _build_ui() -> void:
	var m: int = int(Balance.get_value("hud", "margin", 16))
	var w: float = Balance.get_float("hud", "hp_bar_width", 300.0)

	# Charte UI : panneau bleu nuit, coins arrondis, bordure fine claire.
	_panel = PanelContainer.new()
	_panel.name = "HealthPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(m, m)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = NIGHT_BLUE
	panel_style.border_color = BORDER_LIGHT
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(14)
	panel_style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_panel.add_child(row)

	# Petit cœur dessiné (une fois).
	var heart := Control.new()
	heart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heart.custom_minimum_size = Vector2(30, 34)
	heart.draw.connect(_draw_heart.bind(heart))
	row.add_child(heart)

	_bar = ProgressBar.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.custom_minimum_size = Vector2(w, 34)
	_bar.show_percentage = false
	_bar.min_value = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.11)
	bg.border_color = Color(GOLD, 0.55)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(9)
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = HP_FILL
	_fill_style.set_corner_radius_all(9)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", _fill_style)
	row.add_child(_bar)

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
	settings.font_size = 22
	settings.font_color = Color.WHITE
	settings.outline_size = 5
	settings.outline_color = NIGHT_BLUE
	_hp_label.label_settings = settings
	_bar.add_child(_hp_label)


func _draw_heart(c: Control) -> void:
	var s: Vector2 = c.size
	var cx: float = s.x * 0.5
	var cy: float = s.y * 0.5
	var r: float = minf(s.x, s.y) * 0.24
	c.draw_circle(Vector2(cx - r * 0.95, cy - r * 0.4), r, HP_FILL, true, -1.0, true)
	c.draw_circle(Vector2(cx + r * 0.95, cy - r * 0.4), r, HP_FILL, true, -1.0, true)
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - r * 1.9, cy - r * 0.15), Vector2(cx + r * 1.9, cy - r * 0.15), Vector2(cx, cy + r * 2.1)]), HP_FILL)
	c.draw_circle(Vector2(cx - r * 1.1, cy - r * 0.7), r * 0.32, Color(1, 1, 1, 0.55), true, -1.0, true)


## Met à jour l'affichage (public pour les tests et d'autres systèmes).
## Ne touche aux nœuds que si une valeur change.
func set_health(current: float, maximum: float) -> void:
	var new_max: float = maxf(maximum, 1.0)
	var new_hp: float = clampf(current, 0.0, new_max)
	if is_equal_approx(new_max, _max_hp) and is_equal_approx(new_hp, _hp):
		return
	_max_hp = new_max
	_hp = new_hp
	_bar.max_value = _max_hp
	_bar.value = _hp
	_hp_label.text = "%d / %d" % [ceili(_hp), ceili(_max_hp)]
	_fill_style.bg_color = HP_LOW if _hp / _max_hp <= 0.3 else HP_FILL


func get_health() -> float:
	return _hp


## Rectangle écran occupé par la barre de vie (pour placer d'autres éléments à côté).
func get_health_panel_rect() -> Rect2:
	return _panel.get_global_rect() if _panel != null else Rect2()


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
