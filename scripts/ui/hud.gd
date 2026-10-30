class_name Hud
extends Control
## HUD paysage (1280x720) : vie compacte en haut à gauche (direction D) : boîte encre à coin
## coupé, croix de soin, jauge continue (HealthGauge : vert → ambre → rouge, traînée de dégâts,
## soin en vert, clignote sous [hud] hp_low_ratio) puis PV actuels / max. Mise à jour par signaux uniquement
## (EventBus.player_spawned / player_damaged / player_died) ; la jauge ne s'anime que si besoin.
## Zones laissées libres pour les autres modules : haut centre = bandeau monde/salle
## (Raid), haut droite = bouton sac (inventaire), bas droite au-dessus du stick de visée
## = bouton « action ». Arme tenue, autres armes, équipement, Recharger (autour du stick de
## visée) et emplacements rapides (au-dessus du stick de déplacement) : WeaponHud
## (scripts/ui/weapon_hud.gd), enfant de ce HUD.

const NIGHT_BLUE := Color(0.024, 0.027, 0.05, 0.72)  # encre translucide (direction D)
const BORDER_LIGHT := Color(1.0, 1.0, 1.0, 0.45)

var _gauge: HealthGauge
var _icon: Control
var _hp_label: Label
var _max_label: Label
var _panel_style: CutBox
var _panel: PanelContainer
var _heal_flash: float = 0.0
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
	var w: float = Balance.get_float("hud", "hp_bar_width", 210.0)
	var h: float = Balance.get_float("hud", "hp_bar_height", 16.0)

	# Direction D : boîte encre translucide à coin coupé : croix de soin, jauge continue, PV.
	_panel = PanelContainer.new()
	_panel.name = "HealthPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(m, m)
	_panel_style = CutBox.make(NIGHT_BLUE, 10.0, Color(0, 0, 0, 0), 1.5, 12.0, 7.0)
	_panel_style.corners = CutBox.CUT_TOP_RIGHT
	_panel.add_theme_stylebox_override("panel", _panel_style)
	add_child(_panel)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	_panel.add_child(row)

	# Croix médicale dessinée (couleur de la jauge ; verte au soin, clignote PV bas).
	_icon = Control.new()
	_icon.name = "HpIcon"
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.custom_minimum_size = Vector2(22, 22)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.draw.connect(_draw_icon)
	row.add_child(_icon)

	_gauge = HealthGauge.new()
	_gauge.name = "Gauge"
	_gauge.custom_minimum_size = Vector2(w, h)
	_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gauge.low_changed.connect(func(_low: bool) -> void: _refresh_colors())
	_gauge.draw.connect(_icon.queue_redraw)
	row.add_child(_gauge)

	# PV actuels (Anton) / max (texte secondaire).
	var nums := HBoxContainer.new()
	nums.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nums.add_theme_constant_override("separation", 2)
	nums.alignment = BoxContainer.ALIGNMENT_END
	nums.custom_minimum_size = Vector2(Balance.get_float("hud", "hp_numbers_width", 78.0), 0)
	row.add_child(nums)
	_hp_label = Label.new()
	_hp_label.name = "HpValue"
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var settings := LabelSettings.new()
	settings.font = MenuKit.display()
	settings.font_size = int(Balance.get_value("hud", "hp_font_size", 26))
	settings.font_color = Color.WHITE
	_hp_label.label_settings = settings
	nums.add_child(_hp_label)
	_max_label = MenuKit.label("/100", 15, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	_max_label.name = "HpMax"
	_max_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_max_label.size_flags_vertical = Control.SIZE_SHRINK_END
	nums.add_child(_max_label)


func _draw_icon() -> void:
	var s := _icon.size
	var c := s * 0.5
	var t: float = s.x * 0.34   # épaisseur des branches
	var col: Color = _gauge.fill_color() if _gauge != null else HealthGauge.GREEN
	if _gauge != null:
		col.a = _gauge.blink_alpha()
		if _heal_flash > 0.0:
			col = col.lerp(HealthGauge.HEAL, _heal_flash)
	_icon.draw_rect(Rect2(c.x - t * 0.5, 0, t, s.y), col)
	_icon.draw_rect(Rect2(0, c.y - t * 0.5, s.x, t), col)


## Barre de vie dans la zone sûre (encoche / coins arrondis), recalée au redimensionnement.
func _place_safe() -> void:
	if not is_inside_tree() or _panel == null:
		return
	var m := HudSafeArea.margins(self)
	_panel.position = Vector2(m.x, m.y)


## Met à jour l'affichage (public pour les tests et d'autres systèmes).
## Ne touche aux nœuds que si une valeur change. Dégâts : traînée ; soin : segment vert, « +N ».
func set_health(current: float, maximum: float) -> void:
	var new_max: float = maxf(maximum, 1.0)
	var new_hp: float = clampf(current, 0.0, new_max)
	if is_equal_approx(new_max, _max_hp) and is_equal_approx(new_hp, _hp):
		return
	var first: bool = _hp < 0.0 or not is_equal_approx(new_max, _max_hp) and _hp >= new_max
	var gained: float = new_hp - _hp if _hp >= 0.0 else 0.0
	_max_hp = new_max
	_hp = new_hp
	_gauge.set_values(_hp, _max_hp, first)
	_hp_label.text = str(ceili(_hp))
	_max_label.text = "/%d" % ceili(_max_hp)
	if not first and gained >= 1.0:
		_show_heal(gained)
	elif not first and gained < 0.0:
		_flash_damage()
	_refresh_colors()


## Couleur du chiffre et liseré du panneau selon les PV (rouge sous le seuil bas).
func _refresh_colors() -> void:
	var low: bool = _gauge.is_low()
	_hp_label.label_settings.font_color = HealthGauge.RED if low else Color.WHITE
	_panel_style.border_color = Color(HealthGauge.RED, 0.7) if low else Color(0, 0, 0, 0)
	_panel.queue_redraw()
	_icon.queue_redraw()


## Soin : croix verte un instant et « +N » qui monte au-dessus de la jauge.
func _show_heal(amount: float) -> void:
	_heal_flash = 1.0
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		_heal_flash = v
		_icon.queue_redraw(), 1.0, 0.0, 0.6)
	var lbl := MenuKit.label("+%d" % roundi(amount), 20, HealthGauge.HEAL, MenuKit.display(), 6)
	lbl.name = "HealPop"
	add_child(lbl)
	var r := _gauge.get_global_rect()
	lbl.global_position = Vector2(r.position.x + r.size.x * (_hp / _max_hp) - 12.0, r.end.y + 4.0)
	var tl := create_tween().set_parallel(true)
	tl.tween_property(lbl, "position:y", lbl.position.y + 18.0, 0.8).set_ease(Tween.EASE_OUT)
	tl.tween_property(lbl, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tl.chain().tween_callback(lbl.queue_free)


## Dégâts : le chiffre tressaute en rouge.
func _flash_damage() -> void:
	_hp_label.pivot_offset = _hp_label.size * 0.5
	_hp_label.scale = Vector2(1.25, 1.25)
	_hp_label.modulate = Color(1.0, 0.55, 0.6)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_hp_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_hp_label, "modulate", Color.WHITE, 0.3)


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
