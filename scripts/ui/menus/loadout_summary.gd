class_name LoadoutSummary
extends Button
## Panneau « Arsenal de départ » du lobby : les armes (Profile.loadout_slots(), 3 par défaut)
## et l'équipement actuellement choisis, en petites cartes à la couleur de rareté, + nombre
## d'armes en réserve (version compacte : le pass de combat tient dessous). Un tap ouvre l'arsenal. Se met à jour sur Profile.changed.

var title_label: Label = null
var stash_label: Label = null
## Une entrée par emplacement : {panel, icon: WeaponIcon, name: Label, sub: Label, weapon}.
var slots: Array[Dictionary] = []
var _rows: VBoxContainer = null


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	text = ""
	custom_minimum_size = Vector2(Balance.get_float("menu", "loadout_panel_width", 290.0), 0)
	var n := MenuKit.panel_style(Color(MenuKit.NIGHT, 0.84), MenuKit.BORDER, 18, 1, 12)
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.1, 0.14, 0.25, 0.9)
	h.border_color = Color(1, 1, 1, 0.5)
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = Color(0.05, 0.07, 0.13, 0.92)
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = MenuKit.GOLD
	f.set_border_width_all(3)
	f.set_corner_radius_all(21)
	f.set_expand_margin_all(4)
	add_theme_stylebox_override("normal", n)
	add_theme_stylebox_override("hover", h)
	add_theme_stylebox_override("pressed", p)
	add_theme_stylebox_override("hover_pressed", p)
	add_theme_stylebox_override("focus", f)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_top = 8
	col.offset_right = -12
	col.offset_bottom = -10
	add_child(col)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var g := MenuGlyph.new(&"rifle", MenuKit.GOLD, 26)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(g)
	title_label = MenuKit.label("Arsenal de départ", 18, MenuKit.TEXT, MenuKit.nunito(900), 3)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var chev := MenuGlyph.new(&"chevron", MenuKit.TEXT_DIM, 18)
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chev)
	_rows = VBoxContainer.new()
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows.add_theme_constant_override("separation", 5)
	col.add_child(_rows)
	for i: int in Profile.loadout_slots() + Profile.gadget_slots():
		_rows.add_child(_make_slot(i >= Profile.loadout_slots()))
	stash_label = MenuKit.label("", 13, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	col.add_child(stash_label)


func _ready() -> void:
	MenuKit.add_feedback(self, 1.02)
	Profile.changed.connect(refresh)
	refresh()
	# hauteur = contenu (le Button ne se dimensionne pas sur ses enfants libres)
	var c := get_child(0) as Control
	custom_minimum_size.y = c.get_combined_minimum_size().y + 18


func _make_slot(gadget: bool) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(0, 36 if gadget else 46)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	var icon := WeaponIcon.new()
	icon.custom_minimum_size = Vector2(66 if not gadget else 46, 0)
	row.add_child(icon)
	var txt := VBoxContainer.new()
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.alignment = BoxContainer.ALIGNMENT_CENTER
	txt.add_theme_constant_override("separation", -3)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	var name_l := MenuKit.label("", 15 if not gadget else 14, MenuKit.TEXT, MenuKit.nunito(900))
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.add_child(name_l)
	var sub := MenuKit.label("", 12, MenuKit.TEXT_DIM, MenuKit.nunito(800))
	txt.add_child(sub)
	slots.append({"panel": p, "icon": icon, "name": name_l, "sub": sub, "gadget": gadget, "weapon": null})
	return p


func refresh() -> void:
	var weapons: Array[WeaponData] = Profile.get_loadout_weapons()
	var gadget: WeaponData = Profile.get_loadout_gadget()
	var wi: int = 0
	for s: Dictionary in slots:
		var w: WeaponData = null
		if bool(s["gadget"]):
			w = gadget
		else:
			w = weapons[wi] if wi < weapons.size() else null
			wi += 1
		s["weapon"] = w
		var p: PanelContainer = s["panel"]
		var icon: WeaponIcon = s["icon"]
		var name_l: Label = s["name"]
		var sub: Label = s["sub"]
		if w != null:
			var st := MenuKit.rarity_style(w.rarity, false, 12)
			st.set_content_margin_all(5)
			st.content_margin_right = 10
			p.add_theme_stylebox_override("panel", st)
			icon.visible = true
			icon.set_weapon(w)
			name_l.text = w.display_name
			name_l.add_theme_color_override("font_color", MenuKit.TEXT)
			sub.text = "%s · %s" % [w.get_category_name(), MenuKit.rarity_name(w.rarity)]
			sub.add_theme_color_override("font_color", MenuKit.rarity_color(w.rarity).lightened(0.35))
		else:
			var st2 := MenuKit.panel_style(Color(0, 0, 0, 0.18), Color(1, 1, 1, 0.16), 12, 1, 5)
			st2.shadow_size = 0
			p.add_theme_stylebox_override("panel", st2)
			icon.visible = false
			name_l.text = "Équipement libre" if bool(s["gadget"]) else "Emplacement libre"
			name_l.add_theme_color_override("font_color", Color(MenuKit.TEXT_DIM, 0.8))
			sub.text = "Choisi avant chaque raid"
			sub.add_theme_color_override("font_color", Color(MenuKit.TEXT_DIM, 0.6))
	var n: int = Profile.weapons.size()
	stash_label.text = "%d arme%s en réserve" % [n, "s" if n > 1 else ""]
