class_name ArenaPanel
extends Control
## Panneau de l'arène de test (direction D, MenuKit) : onglet « ARÈNE » au bord droit qui ouvre
## un panneau encre biseauté. Contenu : réglages (munitions infinies, invincibilité, brouillard),
## remise à zéro, râtelier (arme du catalogue, objet + quantité, skin de l'arme tenue), ennemis à
## la demande (un bouton par archétype), sortie libre vers le menu. Tactile et souris.

var arena: TestArena = null
var tab_button: Button = null
var box: PanelContainer = null
var ammo_toggle: Button = null
var god_toggle: Button = null
var fog_toggle: Button = null
var reset_button: Button = null
var exit_button: Button = null
var weapon_picker: OptionButton = null
var take_weapon_button: Button = null
var item_picker: OptionButton = null
var item_count: SpinBox = null
var take_item_button: Button = null
var skin_picker: OptionButton = null
var skin_button: Button = null
var enemy_buttons: Array[Button] = []
var clear_button: Button = null
var status_label: Label = null
var _weapons: Array[WeaponData] = []
var _items: Array[ItemData] = []
var _skins: Array[SkinData] = []


func _init(p_arena: TestArena = null) -> void:
	arena = p_arena
	name = "ArenaPanel"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m: Vector4 = MenuKit.safe_margins(self)
	var w: float = Balance.get_float("test_arena", "panel_width", 430.0)

	tab_button = MenuKit.button("Arène", MenuKit.Style.PRIMARY, 20, Vector2(132, 52))
	tab_button.name = "ArenaTab"
	tab_button.anchor_left = 1.0
	tab_button.anchor_right = 1.0
	tab_button.anchor_top = 0.5
	tab_button.anchor_bottom = 0.5
	tab_button.offset_right = -maxf(m.z, 12.0)
	tab_button.offset_left = tab_button.offset_right - 132.0
	tab_button.offset_top = -26.0
	tab_button.offset_bottom = 26.0
	tab_button.pressed.connect(func() -> void: set_open(not box.visible))
	add_child(tab_button)

	box = PanelContainer.new()
	box.name = "ArenaBox"
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_theme_stylebox_override("panel", CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.9), 14.0,
		Color(MenuKit.VIOLET, 0.8), 1.5, 18.0, 14.0))
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_right = -maxf(m.z, 12.0)
	box.offset_left = box.offset_right - w
	box.offset_top = maxf(m.y, 12.0)
	box.offset_bottom = -maxf(m.w, 12.0)
	box.visible = false
	add_child(box)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	sc.add_child(col)
	MenuKit.make_touch_scroll(sc)

	var head := HBoxContainer.new()
	col.add_child(head)
	var title := MenuKit.title("Arène de test", 30, MenuKit.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := MenuKit.button("Fermer", MenuKit.Style.SECONDARY, 16, Vector2(96, 40))
	close.pressed.connect(func() -> void: set_open(false))
	head.add_child(close)

	_section(col, "Réglages")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	ammo_toggle = _toggle(row, "Munitions ∞", arena.infinite_ammo if arena != null else true,
		func(on: bool) -> void: arena.set_infinite_ammo(on))
	god_toggle = _toggle(row, "Invincible", arena.god_mode if arena != null else true,
		func(on: bool) -> void: arena.set_god_mode(on))
	fog_toggle = _toggle(row, "Brouillard", arena.fog_enabled if arena != null else false,
		func(on: bool) -> void: arena.set_fog(on))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	col.add_child(row2)
	reset_button = _action(row2, "Remise à zéro", func() -> void:
		arena.reset()
		_say("Arène remise à zéro"))
	exit_button = _action(row2, "Quitter vers le menu", func() -> void: arena.exit_to_menu())

	_section(col, "Râtelier")
	weapon_picker = _picker(col, "WeaponPicker")
	for wd: WeaponData in _sorted_weapons():
		_weapons.append(wd)
		weapon_picker.add_item("%s · %s" % [wd.display_name, LootDB.rarity_name(wd.rarity)])
	take_weapon_button = _action(col, "Prendre l'arme", func() -> void:
		var i := weapon_picker.selected
		if i >= 0 and i < _weapons.size() and arena.take_weapon(_weapons[i].id):
			_say("%s en main" % _weapons[i].display_name)
			_refresh_skins())
	item_picker = _picker(col, "ItemPicker")
	for it: ItemData in LootDB.all_items():
		if not it.is_weapon():
			_items.append(it)
			item_picker.add_item("%s · %s" % [it.display_name, LootDB.type_name(it.type)])
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 6)
	col.add_child(row3)
	item_count = SpinBox.new()
	item_count.min_value = 1
	item_count.max_value = int(Balance.get_value("test_arena", "item_max_count", 20))
	item_count.value = 1
	item_count.custom_minimum_size = Vector2(110, 44)
	row3.add_child(item_count)
	take_item_button = _action(row3, "Prendre l'objet", func() -> void:
		var i := item_picker.selected
		if i >= 0 and i < _items.size():
			var got := arena.take_item(_items[i].id, int(item_count.value))
			_say(("%s ×%d dans le sac" % [_items[i].display_name, got]) if got > 0 else "Sac plein"))
	skin_picker = _picker(col, "SkinPicker")
	skin_button = _action(col, "Changer le skin de l'arme", func() -> void:
		var i := skin_picker.selected
		var sid: StringName = _skins[i - 1].id if i >= 1 and i - 1 < _skins.size() else &""
		if arena.apply_weapon_skin(sid):
			_say("Skin : %s" % (_skins[i - 1].display_name if sid != &"" else "d'origine")))

	_section(col, "Ennemis")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	for a: Dictionary in TestArena.archetypes():
		var kind: StringName = a["kind"]
		var label: String = a["name"]
		var b := _action(grid, label, func() -> void:
			var got := arena.spawn_enemy(kind, 1)
			_say("%s : %d apparu" % [label, got.size()]))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		enemy_buttons.append(b)
	clear_button = _action(col, "Retirer les ennemis", func() -> void:
		arena.clear_enemies()
		_say("Ennemis retirés"))
	status_label = MenuKit.label("", 15, MenuKit.TEXT_DIM, MenuKit.nunito(600))
	status_label.name = "Status"
	col.add_child(status_label)
	_refresh_skins()


func set_open(on: bool) -> void:
	box.visible = on
	tab_button.visible = not on
	if on:
		_refresh_skins()


func _say(msg: String) -> void:
	status_label.text = msg
	MenuKit.sfx(&"click_soft")


func _sorted_weapons() -> Array[WeaponData]:
	var list := WeaponCatalog.all()
	list.sort_custom(func(a: WeaponData, b: WeaponData) -> bool:
		var ca := WeaponData.CATEGORIES.find(a.category)
		var cb := WeaponData.CATEGORIES.find(b.category)
		if ca != cb:
			return ca < cb
		return a.rarity < b.rarity if a.rarity != b.rarity else a.display_name < b.display_name)
	return list


## Skins de l'arme tenue (premier choix : « Skin d'origine »).
func _refresh_skins() -> void:
	if skin_picker == null or arena == null:
		return
	skin_picker.clear()
	_skins = arena.skins_for_held()
	skin_picker.add_item("Skin d'origine")
	for s: SkinData in _skins:
		skin_picker.add_item("%s · %s" % [s.display_name, LootDB.rarity_name(s.rarity)])
	skin_button.disabled = _skins.is_empty()


func _section(col: VBoxContainer, text: String) -> void:
	var l := MenuKit.label(text, 16, MenuKit.VIOLET_LIGHT, MenuKit.nunito(700))
	l.uppercase = true
	col.add_child(l)


func _picker(col: Control, n: String) -> OptionButton:
	var p := OptionButton.new()
	p.name = n
	p.custom_minimum_size = Vector2(0, 44)
	p.fit_to_longest_item = false
	p.add_theme_font_override("font", MenuKit.nunito(600))
	p.add_theme_font_size_override("font_size", 16)
	col.add_child(p)
	return p


func _toggle(parent: Control, text: String, on: bool, apply: Callable) -> Button:
	var b := MenuKit.chip(text, MenuKit.VIOLET)
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.button_pressed = on
	b.toggled.connect(func(v: bool) -> void:
		apply.call(v)
		MenuKit.sfx(&"toggle"))
	parent.add_child(b)
	return b


func _action(parent: Control, text: String, cb: Callable) -> Button:
	var b := MenuKit.chip(text, MenuKit.VIOLET)
	b.toggle_mode = false
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
