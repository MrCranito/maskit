class_name WeaponTile
extends Button
## Carte d'arme façon planche docs/reference/arsenal.jpg : carte horizontale, fond bleu nuit
## teinté d'un halo à la couleur de rareté (lueur pour Épique/Légendaire), grande icône, nom en
## bas à gauche, bandeau de rareté coloré tout en bas.
## Une carte = un modèle d'arme (`weapon`) ; `uids` = exemplaires possédés (quantité affichée
## « ×N » si > 1). `locked` : modèle non possédé (consultation du catalogue) → grisé + cadenas.
## `slot_index` ≥ 0 : placé dans l'arsenal de départ (pastille numérotée ; « É » = équipement).
## Armurerie (`set_shop_status`, Economy.weapon_status) : pastille en haut à gauche : prix en or (achetable),
## cadenas + progression « 0/1 » (à débloquer en tuant un ennemi), « BUTIN » (Légendaire :
## jamais en vente) ; la quantité possédée reste affichée en haut à droite.

## Disposition « D » (arsenal de départ, maquette Loadout) : carte encre à coin haut droit coupé,
## halo de rareté, icône centrée, nom en Anton, barre de rareté en bas, repère « [1] » violet
## quand l'arme est placée, contour blanc quand elle est affichée. À régler avant _ready.
var style_d: bool = false
var weapon: WeaponData = null
var uids: Array[int] = []
var locked: bool = false
var slot_index: int = -1
var focused_detail: bool = false
## Compatibilité : premier exemplaire (ou -1).
var uid: int = -1
var icon_view: WeaponIcon = null
var name_label: Label = null
var _frame: Panel = null
var _frame_style: StyleBoxFlat = null
var _count: PanelContainer = null
var _slot_badge: PanelContainer = null
var _lock: Control = null
var _content: Control = null
## État d'armurerie (vide = hors armurerie).
var shop_status: Dictionary = {}
var _shop_pill: PanelContainer = null


func _init(w: WeaponData = null, p_uids: Array[int] = [], p_locked: bool = false) -> void:
	weapon = w
	uids = p_uids
	locked = p_locked
	uid = p_uids[0] if not p_uids.is_empty() else -1


func owned_count() -> int:
	return uids.size()


func _ready() -> void:
	text = ""
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(Balance.get_float("menu", "weapon_card_width", 196.0),
		Balance.get_float("menu", "weapon_card_height", 124.0))
	clip_contents = false
	var empty := StyleBoxEmpty.new()
	for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		add_theme_stylebox_override(st, empty)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = MenuKit.TEXT
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(10)
	focus.set_expand_margin_all(4)
	add_theme_stylebox_override("focus", focus)
	var r: int = weapon.rarity if weapon != null else 0
	var rc: Color = MenuKit.rarity_color(r)
	if style_d:
		_build_d(r, rc)
		resized.connect(func() -> void: pivot_offset = size * 0.5)
		MenuKit.add_feedback(self, 1.04)
		_refresh()
		return

	# Cadre + fond teinté (découpé aux coins arrondis)
	_frame = Panel.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_style = StyleBoxFlat.new()
	_frame_style.bg_color = Color(0.07, 0.09, 0.15, 0.97)
	_frame_style.set_corner_radius_all(8)
	_frame_style.anti_aliasing = true
	_frame.add_theme_stylebox_override("panel", _frame_style)
	_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(_frame)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_content)
	_content.add_child(MenuKit.rarity_backdrop(r))
	var band_h: float = Balance.get_float("menu", "weapon_card_band", 24.0)
	icon_view = WeaponIcon.new(weapon)
	icon_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_view.offset_left = 12
	icon_view.offset_right = -12
	icon_view.offset_top = 8
	icon_view.offset_bottom = -(band_h + 22)
	_content.add_child(icon_view)
	name_label = MenuKit.label(weapon.display_name if weapon != null else "-", 15, MenuKit.TEXT, MenuKit.nunito(800), 3)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_left = 9
	name_label.offset_right = -8
	name_label.offset_top = -(band_h + 22)
	name_label.offset_bottom = -band_h - 2
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content.add_child(name_label)
	var band := MenuKit.rarity_band(r, 13, band_h)
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -band_h
	_content.add_child(band)

	# Bordure à la couleur de rareté (au-dessus du contenu)
	var ring := Panel.new()
	ring.name = "Ring"
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := StyleBoxFlat.new()
	rs.draw_center = false
	rs.set_corner_radius_all(8)
	rs.anti_aliasing = true
	ring.add_theme_stylebox_override("panel", rs)
	add_child(ring)

	# Quantité possédée, cadenas, pastille d'emplacement
	_count = MenuKit.pill("", Color(0.02, 0.03, 0.08, 0.82), 14, MenuKit.TEXT, Color(1, 1, 1, 0.25))
	_count.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.offset_right = -6
	_count.offset_top = 6
	add_child(_count)
	_lock = LockIcon.new()
	_lock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_lock.offset_left = -34
	_lock.offset_right = -8
	_lock.offset_top = 7
	_lock.offset_bottom = 37
	add_child(_lock)
	_shop_pill = MenuKit.pill("", Color(0.02, 0.03, 0.08, 0.88), 14, MenuKit.TEXT, Color(1, 1, 1, 0.3))
	_shop_pill.name = "ShopPill"
	_shop_pill.position = Vector2(6, 6)
	add_child(_shop_pill)
	_slot_badge = MenuKit.pill("", MenuKit.RED, 15, MenuKit.TEXT, Color(1, 0.7, 0.6, 0.9))
	_slot_badge.position = Vector2(-6, -8)
	add_child(_slot_badge)
	# Exemplaire à affixes : pastilles en haut à gauche.
	if weapon != null and weapon.has_rolled_affixes():
		var ax := AffixBadges.strip(weapon.rolled_affixes, 11)
		ax.position = Vector2(8, 8)
		add_child(ax)
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	MenuKit.add_feedback(self, 1.04)
	_refresh()


func _build_d(r: int, rc: Color) -> void:
	custom_minimum_size = Vector2(0, Balance.get_float("menu", "loadout_card_height", 200.0))
	(get_theme_stylebox("focus") as StyleBoxFlat).set_corner_radius_all(0)
	_frame = Panel.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.96), 20.0, Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
	box.corners = CutBox.CUT_TOP_RIGHT
	_frame.add_theme_stylebox_override("panel", box)
	_frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	add_child(_frame)
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_content)
	_content.add_child(MenuKit.rarity_backdrop(r))
	icon_view = WeaponIcon.new(weapon)
	icon_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_view.anchor_left = 0.12
	icon_view.anchor_right = 0.88
	icon_view.anchor_top = 0.16
	icon_view.anchor_bottom = 0.58
	_content.add_child(icon_view)
	name_label = MenuKit.label(weapon.display_name if weapon != null else "-", 27, MenuKit.TEXT, MenuKit.display(), 0)
	name_label.uppercase = true
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_left = 8
	name_label.offset_right = -8
	name_label.offset_top = -64
	name_label.offset_bottom = -18
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content.add_child(name_label)
	var bar := ColorRect.new()
	bar.name = "RarityBar"
	bar.color = rc
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -5
	_content.add_child(bar)
	# Contour blanc (arme affichée), au-dessus du contenu
	var ring := Panel.new()
	ring.name = "Ring"
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rs := CutBox.new()
	rs.draw_center = false
	rs.border_color = MenuKit.TEXT
	rs.border_width = 3.0
	rs.cut = 20.0
	rs.corners = CutBox.CUT_TOP_RIGHT
	ring.add_theme_stylebox_override("panel", rs)
	add_child(ring)
	_count = MenuKit.pill("", Color(MenuKit.NIGHT_DEEP, 0.82), 14, MenuKit.TEXT)
	_count.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.offset_right = -24
	_count.offset_top = 8
	add_child(_count)
	_lock = LockIcon.new()
	_lock.visible = false
	add_child(_lock)
	_shop_pill = MenuKit.pill("", Color(0, 0, 0, 0), 14, MenuKit.TEXT)
	_shop_pill.visible = false
	add_child(_shop_pill)
	# Repère d'emplacement « [1] » / « [É] » (violet clair, haut gauche)
	_slot_badge = PanelContainer.new()
	_slot_badge.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_slot_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_badge.position = Vector2(12, 8)
	var t := MenuKit.label("", 17, MenuKit.GOLD, MenuKit.nunito(600), 0)
	t.name = "Text"
	_slot_badge.add_child(t)
	add_child(_slot_badge)
	# Exemplaire à affixes : pastilles centrées au-dessus du nom.
	if weapon != null and weapon.has_rolled_affixes():
		var ax := AffixBadges.strip(weapon.rolled_affixes, 12, true)
		ax.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		ax.offset_left = 6
		ax.offset_right = -6
		ax.offset_top = -86
		ax.offset_bottom = -64
		_content.add_child(ax)


## Exemplaires possédés (consultation : mise à jour sans reconstruire).
func set_uids(p_uids: Array[int]) -> void:
	uids = p_uids
	uid = p_uids[0] if not p_uids.is_empty() else -1
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


## Armurerie : état {state, price, kills, needed…} (Economy.weapon_status) ; {} = retire.
func set_shop_status(st: Dictionary) -> void:
	shop_status = st
	_refresh()


func get_shop_text() -> String:
	return (_shop_pill.get_node(^"Text") as Label).text if _shop_pill != null and _shop_pill.visible else ""


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
	var rc: Color = MenuKit.rarity_color(r)
	if style_d:
		(get_node(^"Ring") as Panel).visible = focused_detail
		_count.visible = owned_count() > 1
		(_count.get_node(^"Text") as Label).text = "×%d" % owned_count()
		_slot_badge.visible = slot_index >= 0
		var g: bool = weapon != null and weapon.is_gadget()
		(_slot_badge.get_node(^"Text") as Label).text = "[%s]" % ("É" if g else str(slot_index + 1))
		return
	var rs := (get_node(^"Ring") as Panel).get_theme_stylebox("panel") as StyleBoxFlat
	var sel: bool = slot_index >= 0
	rs.border_color = MenuKit.TEXT if sel else (rc.lightened(0.25) if focused_detail else Color(rc, 0.85))
	rs.set_border_width_all(3 if sel or focused_detail else 2)
	rs.shadow_color = Color(rc, 0.55 if (sel or focused_detail) else (0.35 if r >= 3 else 0.0))
	rs.shadow_size = 14 if (sel or focused_detail) else (8 if r >= 3 else 0)
	rs.shadow_offset = Vector2.ZERO
	(get_node(^"Ring") as Panel).queue_redraw()
	_content.modulate = Color(0.42, 0.44, 0.5, 0.9) if locked else Color.WHITE
	_lock.visible = locked
	_count.visible = not locked and owned_count() > 1
	(_count.get_node(^"Text") as Label).text = "×%d" % owned_count()
	_refresh_shop()
	_slot_badge.visible = slot_index >= 0
	var gadget: bool = weapon != null and weapon.is_gadget()
	(_slot_badge.get_node(^"Text") as Label).text = "É" if gadget else str(slot_index + 1)


func _refresh_shop() -> void:
	if _shop_pill == null:
		return
	_shop_pill.visible = not shop_status.is_empty()
	if shop_status.is_empty():
		return
	var state: StringName = shop_status.get("state", &"")
	var txt := ""
	var bg := Color(0.02, 0.03, 0.08, 0.88)
	var fg := MenuKit.TEXT
	var border := Color(1, 1, 1, 0.3)
	match state:
		Economy.STATE_BUYABLE:
			txt = "%s or" % Economy.fmt(int(shop_status.get("price", 0)))
			fg = Color(1.0, 0.82, 0.32)
			border = Color(1.0, 0.78, 0.25, 0.7)
			_content.modulate = Color.WHITE
		Economy.STATE_LOCKED:
			txt = "%d/%d" % [int(shop_status.get("kills", 0)), int(shop_status.get("needed", 1))]
			bg = Color(0.25, 0.05, 0.07, 0.9)
			border = Color(1.0, 0.45, 0.4, 0.6)
			_content.modulate = Color(0.62, 0.64, 0.7, 0.95)
		_:
			txt = "BUTIN"
			bg = Color(0.38, 0.22, 0.02, 0.92)
			fg = Color(1.0, 0.86, 0.5)
			border = Color(1.0, 0.72, 0.2, 0.7)
			_content.modulate = Color(0.78, 0.78, 0.84, 0.95)
	_lock.visible = state == Economy.STATE_LOCKED and not _count.visible
	(_shop_pill.get_node(^"Text") as Label).text = txt
	(_shop_pill.get_node(^"Text") as Label).add_theme_color_override("font_color", fg)
	var ps := _shop_pill.get_theme_stylebox("panel") as StyleBoxFlat
	ps.bg_color = bg
	ps.border_color = border
	ps.set_border_width_all(1)


## Petit cadenas dessiné (modèle non possédé).
class LockIcon extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		var body := Rect2(o + Vector2(s * 0.15, s * 0.45), Vector2(s * 0.7, s * 0.5))
		draw_circle(o + Vector2(s * 0.5, s * 0.6), s * 0.55, Color(0.02, 0.03, 0.08, 0.7))
		draw_arc(o + Vector2(s * 0.5, s * 0.45), s * 0.22, PI, TAU, 16, MenuKit.TEXT_DIM, maxf(2.0, s * 0.1), true)
		draw_rect(body, MenuKit.TEXT_DIM)
		draw_circle(body.get_center(), s * 0.07, Color(0.05, 0.06, 0.1))
