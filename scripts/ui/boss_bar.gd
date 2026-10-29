class_name BossBar
extends Control
## Barre de vie du boss (haut centre, sous le bandeau monde/salle), charte UI : panneau bleu
## nuit, bordure fine claire, nom en blanc gras, titre gris clair, barre rouge sombre avec
## crans de phase. Apparaît quand le boss engage le combat (EventBus.boss_engaged), affiche un
## bandeau à chaque phase (boss_phase_changed) et disparaît à sa mort (boss_defeated).
## Réglages : balance.cfg [boss] bar_width, phase_banner_time.

const NIGHT_BLUE := Color(0.071, 0.102, 0.18, 0.94)
const BORDER_LIGHT := Color(0.85, 0.88, 0.95, 0.85)
const TEXT_SECONDARY := Color(0.78, 0.8, 0.86)
const FILL := Color(0.78, 0.1, 0.12)
const FILL_LOW := Color(1.0, 0.35, 0.15)
const LAG_FILL := Color(1.0, 0.85, 0.6, 0.75)
const BACK := Color(0.03, 0.04, 0.08, 0.9)
const NOTCH := Color(1.0, 1.0, 1.0, 0.75)
const TOP_OFFSET := 64.0

var boss: Enemy = null
var _panel: PanelContainer
var _name: Label
var _title: Label
var _phase: Label
var _gauge: Control
var _banner: Label
var _shown_ratio: float = 1.0
var _lag_ratio: float = 1.0
var _banner_left: float = 0.0


func _ready() -> void:
	name = "BossBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	visible = false
	set_process(false)
	EventBus.boss_engaged.connect(show_boss)
	EventBus.boss_phase_changed.connect(_on_phase)
	EventBus.boss_defeated.connect(_on_defeated)
	get_viewport().size_changed.connect(_place)


func _build() -> void:
	var w := Balance.get_float("boss", "bar_width", 560.0)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = NIGHT_BLUE
	st.border_color = BORDER_LIGHT
	st.set_border_width_all(1)
	st.set_corner_radius_all(14)
	st.set_content_margin_all(8)
	st.content_margin_left = 14
	st.content_margin_right = 14
	_panel.add_theme_stylebox_override("panel", st)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 3)
	_panel.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_name = _label(20, Color.WHITE, true)
	row.add_child(_name)
	_title = _label(13, TEXT_SECONDARY, false)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)
	_phase = _label(13, Color(1.0, 0.78, 0.4), true)
	row.add_child(_phase)
	_gauge = Control.new()
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.custom_minimum_size = Vector2(w, 16)
	_gauge.draw.connect(_draw_gauge)
	col.add_child(_gauge)
	_banner = _label(30, Color(1.0, 0.9, 0.7), true)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08))
	_banner.visible = false
	add_child(_banner)


func _label(size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_constant_override("outline_size", 2)
		l.add_theme_color_override("font_outline_color", color)
	return l


func _place() -> void:
	if not is_inside_tree():
		return
	var r := HudSafeArea.safe_rect(self)
	_panel.reset_size()
	_panel.position = Vector2(r.position.x + (r.size.x - _panel.size.x) * 0.5, r.position.y + TOP_OFFSET)
	_banner.reset_size()
	_banner.size.x = r.size.x
	_banner.position = Vector2(r.position.x, r.position.y + r.size.y * 0.32)


## Affiche la barre pour ce boss (aussi appelable directement : tests, debug).
func show_boss(b: Node2D) -> void:
	var e := b as Enemy
	if e == null or not is_instance_valid(e) or e.data == null:
		return
	boss = e
	_name.text = e.data.display_name.to_upper()
	_title.text = e.data.boss_title
	_shown_ratio = ratio()
	_lag_ratio = _shown_ratio
	_refresh_phase()
	visible = true
	set_process(true)
	_place.call_deferred()


## Fraction de PV du boss suivi (0..1).
func ratio() -> float:
	if boss == null or not is_instance_valid(boss):
		return 0.0
	return clampf(boss.hp / maxf(boss.max_hp, 0.001), 0.0, 1.0)


func _refresh_phase() -> void:
	if boss == null or not is_instance_valid(boss) or boss.data.phases.is_empty():
		_phase.text = ""
		return
	_phase.text = "PHASE %d/%d" % [maxi(boss.boss_phase, 0) + 1, boss.data.phases.size()]


func _on_phase(b: Node2D, _index: int, phase_name: String) -> void:
	if b != boss:
		show_boss(b)
	_refresh_phase()
	_banner.text = phase_name.to_upper()
	_banner.visible = true
	_banner_left = Balance.get_float("boss", "phase_banner_time", 2.2)
	_place()


func _on_defeated(b: Node2D) -> void:
	if b != boss:
		return
	_banner.text = "%s VAINCU" % _name.text
	_banner.visible = true
	_banner_left = Balance.get_float("boss", "phase_banner_time", 2.2)
	_shown_ratio = 0.0
	boss = null


func _process(delta: float) -> void:
	if boss != null and not is_instance_valid(boss):
		boss = null
	var target := ratio()
	_shown_ratio = target
	_lag_ratio = maxf(target, move_toward(_lag_ratio, target, delta * 0.35))
	_gauge.queue_redraw()
	if _banner_left > 0.0:
		_banner_left -= delta
		_banner.modulate.a = clampf(_banner_left / 0.4, 0.0, 1.0)
		if _banner_left <= 0.0:
			_banner.visible = false
	if boss == null and _banner_left <= 0.0:
		visible = false
		set_process(false)


func _draw_gauge() -> void:
	var s := _gauge.size
	_gauge.draw_rect(Rect2(Vector2.ZERO, s), BACK)
	_gauge.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * _lag_ratio, s.y)), LAG_FILL)
	_gauge.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * _shown_ratio, s.y)), FILL_LOW if _shown_ratio <= 0.3 else FILL)
	if boss != null and is_instance_valid(boss):
		for i in range(1, boss.data.phases.size()):
			var x := s.x * boss.boss_phase_from(i)
			_gauge.draw_line(Vector2(x, -2), Vector2(x, s.y + 2), NOTCH, 2.0)
	_gauge.draw_rect(Rect2(Vector2.ZERO, s), BORDER_LIGHT, false, 1.0)
