class_name WeaponTile
extends Button
## Tuile d'arme de la réserve (grille de l'arsenal) : cadre et lueur de rareté, icône
## (skin équipé appliqué), nom, catégorie. `slot_index` ≥ 0 : arme placée dans l'arsenal de
## départ (pastille numérotée). `focused_detail` : arme affichée dans le panneau de détail.

var uid: int = -1
var weapon: WeaponData = null
var slot_index: int = -1
var focused_detail: bool = false
var icon_view: WeaponIcon = null
var _slot_badge: PanelContainer = null
var _rarity_bar: ColorRect = null


func _init(p_uid: int = -1, w: WeaponData = null) -> void:
	uid = p_uid
	weapon = w


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(Balance.get_float("menu", "weapon_tile_width", 168.0),
		Balance.get_float("menu", "weapon_tile_height", 132.0))
	clip_contents = false
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MenuKit.GOLD
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(17)
	focus.set_expand_margin_all(4)
	add_theme_stylebox_override("focus", focus)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_right = -8
	col.offset_top = 6
	col.offset_bottom = -8
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	icon_view = WeaponIcon.new(weapon)
	icon_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(icon_view)
	var n := MenuKit.label(weapon.display_name if weapon != null else "-", 16, MenuKit.TEXT, MenuKit.nunito(900), 3)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	col.add_child(n)
	var c := MenuKit.label(weapon.get_category_name() if weapon != null else "", 13,
		MenuKit.rarity_color(weapon.rarity if weapon != null else 0).lightened(0.35), MenuKit.nunito(800))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(c)
	_slot_badge = MenuKit.pill("", MenuKit.RED, 15, MenuKit.TEXT, Color(1, 0.7, 0.6, 0.9))
	_slot_badge.position = Vector2(-6, -8)
	add_child(_slot_badge)
	MenuKit.add_feedback(self, 1.04)
	_refresh()


func set_slot(i: int) -> void:
	if slot_index == i:
		return
	var was: int = slot_index
	slot_index = i
	_refresh()
	if i >= 0 and was < 0 and is_inside_tree():
		_slot_badge.pivot_offset = _slot_badge.size * 0.5
		create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
			.tween_property(_slot_badge, "scale", Vector2.ONE, 0.25).from(Vector2(0.3, 0.3))


func set_focused_detail(on: bool) -> void:
	focused_detail = on
	_refresh()


func refresh_skin() -> void:
	if icon_view != null:
		icon_view.refresh()


func _refresh() -> void:
	if _slot_badge == null:
		return
	var r: int = weapon.rarity if weapon != null else 0
	var sel: bool = slot_index >= 0 or focused_detail
	var normal := MenuKit.rarity_style(r, sel, 16)
	if slot_index >= 0:
		normal.border_color = MenuKit.TEXT
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = normal.bg_color.lightened(0.08)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", hover)
	add_theme_stylebox_override("hover_pressed", hover)
	_slot_badge.visible = slot_index >= 0
	(_slot_badge.get_node(^"Text") as Label).text = str(slot_index + 1)
