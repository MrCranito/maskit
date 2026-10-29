class_name Hud
extends Control
## HUD paysage (1280x720) : barre de vie compacte en haut à gauche (panneau bleu nuit,
## liseré or), lisible sur mobile. Mise à jour par signaux uniquement
## (EventBus.player_spawned / player_damaged / player_died) : aucun traitement par frame.
## Zones laissées libres pour les autres modules : haut centre = bandeau monde/salle
## (Raid), haut droite = bouton sac (inventaire), bas droite au-dessus du stick de visée
## = bouton « action ». Armes tenues (bas centre) + bouton de changement d'arme :
## WeaponHud (scripts/ui/weapon_hud.gd), enfant de ce HUD.

const NIGHT_BLUE := Color(0.024, 0.027, 0.05, 0.72)  # encre translucide (direction D)
const BORDER_LIGHT := Color(1.0, 1.0, 1.0, 0.45)
const GOLD := Color(0.718, 0.608, 1.0)
const HP_FILL := Color(1.0, 1.0, 1.0)
const HP_LOW := Color(1.0, 0.3, 0.43)
## Nombre de crans de la barre de vie (10 PV par cran pour 100 PV).
const HP_CELLS := 10

var _bar: ProgressBar
var _hp_label: Label
var _fill_style: StyleBoxFlat
var _panel: PanelContainer
var _hp: float = -1.0
var _max_hp: float = -1.0
var weapon_hud: WeaponHud = null
## Barre de vie du boss (haut centre), visible pendant le combat contre le boss.
var boss_bar: BossBar = null


func _ready() -> void:
	name = "Hud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	set_physics_process(false)
	_build_ui()
	get_viewport().size_changed.connect(_place_safe)
	_place_safe.call_deferred()
	weapon_hud = WeaponHud.new()
	add_child(weapon_hud)
	boss_bar = BossBar.new()
	add_child(boss_bar)
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

	# Direction D : boîte encre translucide, coin haut droit coupé, barre à crans.
	_panel = PanelContainer.new()
	_panel.name = "HealthPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(m, m)
	var panel_style := CutBox.make(NIGHT_BLUE, 12.0, Color(0, 0, 0, 0), 0.0, 12.0, 8.0)
	panel_style.corners = CutBox.CUT_TOP_RIGHT
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
	_bar.custom_minimum_size = Vector2(w, 20)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	_bar.min_value = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.14)
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = HP_FILL
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", _fill_style)
	row.add_child(_bar)
	# crans : fines séparations encre par-dessus la barre
	var cells := Control.new()
	cells.name = "Cells"
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cells.draw.connect(func() -> void:
		for i in range(1, HP_CELLS):
			var x: float = cells.size.x * float(i) / float(HP_CELLS)
			cells.draw_line(Vector2(x, 0), Vector2(x, cells.size.y), Color(0.02, 0.02, 0.04, 0.85), 3.0))
	_bar.add_child(cells)

	# PV en gros chiffres (Anton) à droite de la barre
	_hp_label = Label.new()
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.custom_minimum_size = Vector2(92, 0)
	var settings := LabelSettings.new()
	settings.font = LootVisuals.title_font()
	settings.font_size = 26
	settings.font_color = Color.WHITE
	_hp_label.label_settings = settings
	row.add_child(_hp_label)


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


## Barre de vie dans la zone sûre (encoche / coins arrondis), recalée au redimensionnement.
func _place_safe() -> void:
	if not is_inside_tree() or _panel == null:
		return
	var m := HudSafeArea.margins(self)
	_panel.position = Vector2(m.x, m.y)


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
	var low: bool = _hp / _max_hp <= 0.3
	_fill_style.bg_color = HP_LOW if low else HP_FILL
	_hp_label.label_settings.font_color = HP_LOW if low else Color.WHITE


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
