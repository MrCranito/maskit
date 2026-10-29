class_name ProgressionScreen
extends Control
## Écran « Progression » (direction « D ») : niveau de raider permanent (RaiderProgress).
##  - gauche : gros niveau en Anton, barre à 10 crans, XP du niveau, barème « Gagner de l'XP »
##    (lu dans balance.cfg [battle_pass] × [raider] xp_ratio : mêmes valeurs qu'en jeu) ;
##  - centre : piste des déblocages (obtenus atténués, prochain en violet, à venir en encre) ;
##  - droite : bandeau violet translucide avec le prochain déblocage et « EN RAID » (choix des cartes).
## Se met à jour sur Profile.changed. Aucun _process.

const CELLS := 10

var back_button: Button = null
var level_label: Label = null
var xp_label: Label = null
var next_title: Label = null
var next_level_label: Label = null
var next_kind_label: Label = null
var raid_button: Button = null
## Une entrée par déblocage : {data: Dictionary, row: Control, state: Label}.
var rows: Array[Dictionary] = []

var _cells: Array[ColorRect] = []
var _scroll: ScrollContainer = null
var _list: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	MenuKit.apply_saved_settings()
	MenuKit.music(&"western_hub")
	var bg := ColorRect.new()
	bg.color = MenuKit.NIGHT_DEEP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var art_path := "res://assets/ui/menu/lobby/back.jpg"
	if ResourceLoader.exists(art_path):
		var art := TextureRect.new()
		art.texture = load(art_path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.modulate = Color(0.28, 0.27, 0.34)
		add_child(art)
	_build()
	Profile.changed.connect(refresh)
	refresh()
	MenuKit.fade_in(self)
	raid_button.grab_focus.call_deferred()


func _build() -> void:
	var m: Vector4 = MenuKit.safe_margins(self)
	var vp: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var slab_w: float = clampf(vp.x * Balance.get_float("menu", "lobby_slab_ratio", 0.3),
		Balance.get_float("menu", "lobby_slab_min", 370.0), Balance.get_float("menu", "lobby_slab_max", 440.0))

	# En-tête
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 16)
	head.position = Vector2(m.x, m.y)
	add_child(head)
	back_button = MenuKit.back_button("Menu")
	back_button.pressed.connect(go_back)
	head.add_child(back_button)
	var title := MenuKit.title("Progression", 40)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_FILL
	head.add_child(title)

	var top: float = m.y + 64.0 + 24.0
	var col_w: float = (vp.x - m.x - slab_w - 40.0) * 0.5 - 12.0

	# Gauche : niveau, barre, barème d'XP
	var left := VBoxContainer.new()
	left.name = "Level"
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", 8)
	left.position = Vector2(m.x, top)
	left.custom_minimum_size.x = col_w
	add_child(left)
	var lv_row := HBoxContainer.new()
	lv_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv_row.add_theme_constant_override("separation", 14)
	left.add_child(lv_row)
	level_label = MenuKit.label("1", 110, MenuKit.TEXT, MenuKit.display())
	lv_row.add_child(level_label)
	var cap := VBoxContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.alignment = BoxContainer.ALIGNMENT_CENTER
	cap.add_theme_constant_override("separation", 0)
	lv_row.add_child(cap)
	cap.add_child(MenuKit.label("Niveau de raider", 20, MenuKit.TEXT, MenuKit.nunito(700)))
	cap.add_child(MenuKit.label("Permanent, ne se remet pas à zéro", 15, MenuKit.TEXT_DIM, MenuKit.nunito(500)))
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 4)
	left.add_child(bar)
	for i in CELLS:
		var c := ColorRect.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.custom_minimum_size = Vector2(0, 10)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(c)
		_cells.append(c)
	xp_label = MenuKit.label("", 15, Color(MenuKit.TEXT, 0.8), MenuKit.nunito(600))
	left.add_child(xp_label)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(gap)
	left.add_child(MenuKit.label("GAGNER DE L'XP", 14, MenuKit.TEXT_DIM, MenuKit.nunito(700)))
	for g: Array in xp_gains():
		left.add_child(_gain_row(String(g[0]), String(g[1])))

	# Centre : piste des déblocages (défilement tactile)
	var mid := VBoxContainer.new()
	mid.name = "Unlocks"
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_theme_constant_override("separation", 8)
	mid.position = Vector2(m.x + col_w + 24.0, top)
	mid.size = Vector2(col_w, vp.y - top - m.w)
	add_child(mid)
	mid.add_child(MenuKit.label("DÉBLOCAGES", 14, MenuKit.TEXT_DIM, MenuKit.nunito(700)))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(col_w, vp.y - top - m.w - 30.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	MenuKit.make_touch_scroll(_scroll)
	mid.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	for d: Dictionary in RaiderProgress.unlocks():
		rows.append(_unlock_row(d))

	# Droite : bandeau violet (prochain déblocage + EN RAID)
	var sl := MainMenu.LobbySlab.new()
	sl.name = "Slab"
	sl.cut = Balance.get_float("menu", "lobby_slab_cut", 64.0)
	sl.color = Color(MenuKit.VIOLET, Balance.get_float("menu", "lobby_slab_alpha", 0.62))
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.anchor_left = 1.0
	sl.anchor_right = 1.0
	sl.anchor_bottom = 1.0
	sl.offset_left = -slab_w
	add_child(sl)
	MenuKit.frosted(sl)
	var inner := VBoxContainer.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = sl.cut
	inner.offset_top = m.y + 8.0
	inner.offset_right = -m.z
	inner.offset_bottom = -m.w
	inner.add_theme_constant_override("separation", 6)
	sl.add_child(inner)
	var cap2 := MenuKit.label("PROCHAIN DÉBLOCAGE", 15, MenuKit.TEXT, MenuKit.nunito(700))
	cap2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(cap2)
	next_level_label = MenuKit.label("", 30, MenuKit.TEXT, MenuKit.display())
	next_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(next_level_label)
	next_title = MenuKit.label("", 40, MenuKit.TEXT, MenuKit.display())
	next_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_title.uppercase = true
	inner.add_child(next_title)
	next_kind_label = MenuKit.label("", 15, MenuKit.TEXT, MenuKit.nunito(500))
	next_kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	inner.add_child(next_kind_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(spacer)
	raid_button = Button.new()
	raid_button.name = "RaidButton"
	raid_button.text = "En raid ›"
	raid_button.focus_mode = Control.FOCUS_ALL
	raid_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	raid_button.custom_minimum_size = Vector2(0, 76)
	raid_button.add_theme_font_override("font", MenuKit.display())
	raid_button.add_theme_font_size_override("font_size", 52)
	for st: String in ["normal", "pressed", "hover_pressed", "disabled"]:
		raid_button.add_theme_stylebox_override(st, CutBox.make(Color(0, 0, 0, 0), 12.0, Color(0, 0, 0, 0), 0.0, 8.0, 0.0))
	raid_button.add_theme_stylebox_override("hover", CutBox.make(Color(1, 1, 1, 0.1), 12.0, Color(0, 0, 0, 0), 0.0, 8.0, 0.0))
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = Color(MenuKit.TEXT, 0.45)
	f.border_width = 1.5
	f.cut = 12.0
	raid_button.add_theme_stylebox_override("focus", f)
	for c: String in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		raid_button.add_theme_color_override(c, MenuKit.TEXT)
	raid_button.pressed.connect(func() -> void:
		MenuKit.sfx(&"confirm")
		MenuKit.go_to(self, MenuKit.MAP_SELECT_SCENE))
	MenuKit.add_feedback(raid_button, 1.03)
	inner.add_child(raid_button)


## Barème affiché : [libellé, « +N XP »], lu dans [battle_pass] × [raider] xp_ratio.
static func xp_gains() -> Array:
	var r := float(Balance.get_value("raider", "xp_ratio", 1.0))
	var f := func(key: String, dflt: float) -> String:
		return "+%d XP" % roundi(float(Balance.get_value("battle_pass", key, dflt)) * r)
	return [
		["Extraction réussie", f.call("xp_extraction", 250.0)],
		["Ennemi éliminé", f.call("xp_per_kill", 12.0)],
		["Minute survécue", f.call("xp_per_minute", 15.0)],
		["Mort en raid", f.call("xp_death", 60.0)],
	]


func _gain_row(label_text: String, value_text: String) -> Control:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.75), 0.0, Color(0, 0, 0, 0), 0.0, 14.0, 7.0)
	st.accent_width = 3.0
	st.accent_color = MenuKit.VIOLET
	p.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var l := MenuKit.label(label_text, 16, MenuKit.TEXT, MenuKit.nunito(600))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(MenuKit.label(value_text, 18, MenuKit.GOLD, MenuKit.display()))
	return p


func _unlock_row(d: Dictionary) -> Dictionary:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size.y = 58
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var lv := MenuKit.label(str(int(d["level"])), 26, MenuKit.TEXT, MenuKit.display())
	lv.custom_minimum_size.x = 40
	lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(lv)
	var txt := VBoxContainer.new()
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.alignment = BoxContainer.ALIGNMENT_CENTER
	txt.add_theme_constant_override("separation", -2)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(txt)
	txt.add_child(MenuKit.label(RaiderProgress.label_of(d), 17, MenuKit.TEXT, MenuKit.nunito(700)))
	txt.add_child(MenuKit.label(RaiderProgress.kind_name(d), 13, MenuKit.TEXT_DIM, MenuKit.nunito(500)))
	var state := MenuKit.label("", 13, MenuKit.TEXT, MenuKit.nunito(700))
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(state)
	_list.add_child(p)
	return {"data": d, "row": p, "state": state, "level": lv}


func refresh() -> void:
	var xp: int = int(Profile.raider_xp)
	var level := RaiderProgress.level_for_xp(xp)
	level_label.text = str(level)
	var prog := RaiderProgress.level_progress(xp)
	var filled: int = CELLS if prog.y <= 0 else int(floor(float(prog.x) / float(prog.y) * CELLS))
	for i in CELLS:
		_cells[i].color = MenuKit.TEXT if i < filled else Color(1, 1, 1, 0.15)
	if prog.y > 0:
		xp_label.text = "%s / %s XP  ·  niveau %d dans %s XP" % [MainMenu.format_thousands(prog.x),
			MainMenu.format_thousands(prog.y), level + 1, MainMenu.format_thousands(prog.y - prog.x)]
	else:
		xp_label.text = "Niveau maximal atteint"
	var nxt := RaiderProgress.next_unlock(level)
	var next_row: Control = null
	for r: Dictionary in rows:
		var lvl := int((r["data"] as Dictionary)["level"])
		var row := r["row"] as PanelContainer
		var st := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.78), 10.0, Color(0, 0, 0, 0), 0.0, 12.0, 6.0)
		st.corners = CutBox.CUT_TOP_RIGHT
		var state := r["state"] as Label
		if lvl <= level:
			st.bg_color = Color(MenuKit.NIGHT_DEEP, 0.5)
			row.modulate = Color(1, 1, 1, 0.6)
			state.text = "OBTENU"
			state.add_theme_color_override("font_color", MenuKit.TEXT_DIM)
		elif not nxt.is_empty() and lvl == int(nxt["level"]):
			st.bg_color = Color(MenuKit.VIOLET, 0.38)
			row.modulate = Color.WHITE
			state.text = "PROCHAIN"
			state.add_theme_color_override("font_color", MenuKit.GOLD)
			if next_row == null:
				next_row = row
		else:
			row.modulate = Color.WHITE
			state.text = ""
		row.add_theme_stylebox_override("panel", st)
	if nxt.is_empty():
		next_level_label.text = "NIVEAU %d" % level
		next_title.text = "Tout est débloqué"
		next_kind_label.text = ""
	else:
		next_level_label.text = "NIVEAU %d" % int(nxt["level"])
		next_title.text = RaiderProgress.label_of(nxt)
		next_kind_label.text = RaiderProgress.kind_name(nxt)
	if next_row != null and is_inside_tree():
		_scroll.ensure_control_visible.call_deferred(next_row)


func go_back() -> void:
	MenuKit.sfx(&"back")
	MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()
