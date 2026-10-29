class_name Hud
extends Control
## HUD paysage (1280x720) : vie compacte en haut à gauche (maquette Hud, direction D) : boîte
## encre à coin coupé, PV en Anton puis 10 crans inclinés (rose sous 30 %), lisible sur mobile. Mise à jour par signaux uniquement
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
	row.add_theme_constant_override("separation", 14)
	_panel.add_child(row)

	# PV en gros chiffre (Anton), blanc ; rose sous 30 %
	_hp_label = Label.new()
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_label.custom_minimum_size = Vector2(56, 0)
	var settings := LabelSettings.new()
	settings.font = MenuKit.display()
	settings.font_size = int(Balance.get_value("hud", "hp_font_size", 36))
	settings.font_color = Color.WHITE
	_hp_label.label_settings = settings
	row.add_child(_hp_label)

	# Crans inclinés (maquette) : un cran = 10 % des PV ; la ProgressBar porte la valeur et
	# n'est pas dessinée, les crans sont dessinés par-dessus.
	_bar = ProgressBar.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.custom_minimum_size = Vector2(w, 20)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = HP_FILL
	_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	_bar.add_theme_stylebox_override("fill", StyleBoxEmpty.new())
	row.add_child(_bar)
	var cells := Control.new()
	cells.name = "Cells"
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cells.draw.connect(func() -> void:
		var gap := 3.0
		var cw: float = (cells.size.x - gap * (HP_CELLS - 1)) / float(HP_CELLS)
		var h: float = cells.size.y
		var k: float = h * 0.32   # inclinaison (≈ -18°)
		var full: int = ceili(_bar.value / maxf(_bar.max_value, 1.0) * HP_CELLS) if _bar.value > 0.0 else 0
		for i in HP_CELLS:
			var x: float = i * (cw + gap)
			var col: Color = _fill_style.bg_color if i < full else Color(1, 1, 1, 0.15)
			cells.draw_colored_polygon(PackedVector2Array([Vector2(x + k, 0), Vector2(x + cw, 0),
				Vector2(x + cw - k, h), Vector2(x, h)]), col))
	_bar.add_child(cells)
	_bar.value_changed.connect(func(_v: float) -> void: cells.queue_redraw())


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
	_hp_label.text = str(ceili(_hp))
	var low: bool = _hp / _max_hp <= 0.3
	_fill_style.bg_color = HP_LOW if low else HP_FILL
	_hp_label.label_settings.font_color = HP_LOW if low else Color.WHITE
	(_bar.get_node(^"Cells") as Control).queue_redraw()


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
