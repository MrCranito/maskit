class_name DebugOverlay
extends Control
## Overlay texte de debug (F3). Caché par défaut, basculé par EventBus.debug_toggled.
## Affiche FPS, seed, position du joueur, get_debug_info() du joueur,
## ennemis vivants et projectiles actifs.

var _panel: PanelContainer
var _label: Label
var _refresh_interval: float = 0.2
var _refresh_left: float = 0.0
## Projectiles connus (via EventBus.projectile_fired), indexés par instance id.
var _projectiles: Dictionary = {}


func _ready() -> void:
	name = "DebugOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_refresh_interval = Balance.get_float("debug", "overlay_refresh_interval", 0.2)
	_build_ui()
	EventBus.debug_toggled.connect(_on_debug_toggled)
	EventBus.projectile_fired.connect(_on_projectile_fired)
	_on_debug_toggled(GameState.debug_enabled)


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.position = Vector2(12, 110)
	var style := StyleBoxFlat.new()
	# Charte UI : panneau bleu nuit, coins arrondis, bordure fine claire.
	style.bg_color = Color(0.071, 0.102, 0.18, 0.88)  # ~#121a2e
	style.border_color = Color(0.85, 0.88, 0.95, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settings := LabelSettings.new()
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.7
	settings.font = bold
	settings.font_size = 20
	settings.font_color = Color.WHITE
	_label.label_settings = settings
	_panel.add_child(_label)


func _on_debug_toggled(enabled: bool) -> void:
	visible = enabled
	set_process(enabled)
	if enabled:
		_refresh_left = 0.0
		_refresh()


func _on_projectile_fired(projectile: Node2D) -> void:
	if is_instance_valid(projectile):
		_projectiles[projectile.get_instance_id()] = projectile


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = _refresh_interval
		_refresh()


func _refresh() -> void:
	if _label == null:
		return
	_label.text = build_text()


## Construit le texte de l'overlay (public pour les tests).
func build_text() -> String:
	var lines: PackedStringArray = []
	lines.append("DEBUG (F3)")
	lines.append("FPS : %d" % Engine.get_frames_per_second())
	lines.append("Seed : %d" % GameState.run_seed)

	var player: Node2D = GameState.player
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node2D
	if is_instance_valid(player):
		lines.append("Joueur : (%.0f, %.0f)" % [player.global_position.x, player.global_position.y])
		if player.has_method("get_debug_info"):
			var info: Variant = player.call("get_debug_info")
			if info is Dictionary:
				for key: Variant in (info as Dictionary):
					lines.append("  %s : %s" % [str(key), _fmt((info as Dictionary)[key])])
	else:
		lines.append("Joueur : absent")

	var alive := 0
	var total := 0
	for e: Node in get_tree().get_nodes_in_group(&"enemy_units"):
		total += 1
		if not e.has_method("is_alive") or e.call("is_alive"):
			alive += 1
	lines.append("Ennemis vivants : %d / %d" % [alive, total])
	lines.append("Projectiles actifs : %d" % count_active_projectiles())

	var dbg := DebugWorldDraw.find(get_tree())
	if dbg != null:
		lines.append("Dessins monde : %d" % dbg.get_drawer_count())
	return "\n".join(lines)


func count_active_projectiles() -> int:
	var count := 0
	for id: int in _projectiles.keys():
		var p: Object = instance_from_id(id)
		if p == null or not is_instance_valid(p):
			_projectiles.erase(id)
			continue
		var active: Variant = p.get("active")
		if active == null:
			if (p as CanvasItem).visible:
				count += 1
		elif active:
			count += 1
	return count


func _fmt(value: Variant) -> String:
	if value is float:
		return "%.2f" % value
	if value is Vector2:
		return "(%.0f, %.0f)" % [value.x, value.y]
	if value is Node:
		return (value as Node).name if is_instance_valid(value) else "<libéré>"
	if value == null:
		return "-"
	return str(value)
