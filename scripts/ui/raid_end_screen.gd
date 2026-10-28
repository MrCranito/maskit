class_name RaidEndScreen
extends CanvasLayer
## Écran de fin de raid (construit en code, charte bleu nuit) affiché par Raid :
##   - « Extraction réussie » : armes récupérées (rareté), objets, valeur, gemmes gagnées ;
##   - « Tu es mort » : armes perdues, butin perdu, « Un petit pistolet t'attend au camp »
##     si un pistolet de départ a été offert.
## Le jeu est en pause derrière (ce nœud tourne en PROCESS_MODE_ALWAYS).
## Bouton « Retour au menu » → menu principal.

signal menu_requested

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const NIGHT := Color(0.071, 0.102, 0.18, 0.97)
const SUCCESS := Color(0.36, 0.86, 0.5)
const DEATH := Color(0.9, 0.26, 0.24)

## true = extraction, false = mort.
var success: bool = false
## Résumé de Profile.finish_extraction / finish_death, complété par Raid :
##   extraction : {weapons: Array[StringName], items: Dictionary(id → n), value: int, gems: int}
##   mort : {lost_weapons: Array[StringName], starter_given: bool, lost_items: int, lost_value: int}
var summary: Dictionary = {}

var _panel: PanelContainer = null
var _menu_btn: Button = null
var _paused_by_me: bool = false


static func create(p_success: bool, p_summary: Dictionary) -> RaidEndScreen:
	var s := RaidEndScreen.new()
	s.success = p_success
	s.summary = p_summary
	return s


func _ready() -> void:
	name = "RaidEndScreen"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	if not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true


func _exit_tree() -> void:
	if _paused_by_me and is_inside_tree():
		get_tree().paused = false


func get_title_text() -> String:
	return "Extraction réussie" if success else "Tu es mort"


# --- Construction --------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.72) if success else Color(0.12, 0.01, 0.03, 0.74)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var accent := SUCCESS if success else DEATH
	_panel = PanelContainer.new()
	var st := InventoryStyle.panel(24, 26, NIGHT)
	st.border_color = Color(accent, 0.85)
	st.set_border_width_all(2)
	st.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", st)
	_panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_panel.add_child(root)

	var title := InventoryStyle.title(get_title_text(), 44, accent.lightened(0.15))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	var sub := InventoryStyle.label(
		"Ton butin rejoint ta réserve." if success else "Ton arsenal et ton butin sont perdus.",
		18, InventoryStyle.TEXT_SECONDARY, 700)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	if success:
		_build_success(root)
	else:
		_build_death(root)

	_menu_btn = InventoryStyle.button("Retour au menu", InventoryStyle.GOLD, 22, Vector2(300, 62))
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_btn.pressed.connect(go_to_menu)
	root.add_child(_menu_btn)

	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_success(root: VBoxContainer) -> void:
	var weapons: Array = summary.get("weapons", [])
	root.add_child(_section("Armes récupérées (%d)" % weapons.size()))
	root.add_child(_weapon_grid(weapons, false))

	var items: Dictionary = summary.get("items", {})
	var n_items := 0
	for k: Variant in items:
		n_items += int(items[k])
	root.add_child(_section("Objets (%d)" % n_items))
	root.add_child(_item_row(items))

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 18)
	root.add_child(stats)
	stats.add_child(_stat_chip("Valeur", "%d $" % int(summary.get("value", 0)), InventoryStyle.GOLD))
	stats.add_child(_stat_chip("Gemmes", "+%d" % int(summary.get("gems", 0)), Color(0.55, 0.85, 1.0)))


func _build_death(root: VBoxContainer) -> void:
	var lost: Array = summary.get("lost_weapons", [])
	root.add_child(_section("Armes perdues (%d)" % lost.size()))
	root.add_child(_weapon_grid(lost, true))
	var n := int(summary.get("lost_items", 0))
	var v := int(summary.get("lost_value", 0))
	var loot := InventoryStyle.label(
		("Butin perdu : %d objet%s (%d $)" % [n, "s" if n > 1 else "", v]) if n > 0 else "Aucun butin à perdre.",
		18, InventoryStyle.TEXT, 700)
	loot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(loot)
	if bool(summary.get("starter_given", false)):
		var gift := PanelContainer.new()
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(InventoryStyle.GOLD, 0.14)
		gs.border_color = Color(InventoryStyle.GOLD, 0.7)
		gs.set_border_width_all(1)
		gs.set_corner_radius_all(12)
		gs.set_content_margin_all(10)
		gift.add_theme_stylebox_override("panel", gs)
		var gl := InventoryStyle.label("Un petit pistolet t'attend au camp.", 19, InventoryStyle.GOLD, 800)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gift.add_child(gl)
		root.add_child(gift)


func _section(text: String) -> Label:
	var l := InventoryStyle.label(text.to_upper(), 15, InventoryStyle.TEXT_SECONDARY, 800)
	return l


## Grille de cartes d'armes (icône + nom couleur de rareté). Barrées si perdues.
func _weapon_grid(ids: Array, lost: bool) -> Control:
	if ids.is_empty():
		var none := InventoryStyle.label("Aucune.", 16, InventoryStyle.TEXT_SECONDARY, 600)
		return none
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for id: Variant in ids:
		var w := WeaponCatalog.get_weapon(StringName(str(id)))
		if w != null:
			grid.add_child(_weapon_card(w, lost))
	return grid


func _weapon_card(w: WeaponData, lost: bool) -> Control:
	var rc := w.get_rarity_color()
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = InventoryStyle.NIGHT_BLUE_DEEP.lerp(rc, 0.12)
	st.border_color = Color(rc, 0.4 if lost else 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", st)
	card.custom_minimum_size = Vector2(190, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(170, 52)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func() -> void:
		LootVisuals.draw_weapon(pic, Rect2(Vector2(10, 2), pic.size - Vector2(20, 4)), w, Color(1, 1, 1, 0.45) if lost else Color.WHITE)
		if lost:
			pic.draw_line(Vector2(14, pic.size.y - 6), Vector2(pic.size.x - 14, 6), Color(DEATH, 0.85), 4.0, true))
	v.add_child(pic)
	var nm := InventoryStyle.label(w.display_name, 15, rc.lightened(0.25) if not lost else Color(rc, 0.7), 800)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(170, 0)
	v.add_child(nm)
	v.add_child(InventoryStyle.label("%s · %s" % [w.get_category_name(), w.get_rarity_name()], 12, InventoryStyle.TEXT_SECONDARY, 700))
	return card


## Ligne de tuiles d'objets (au plus 8, puis « +N »).
func _item_row(items: Dictionary) -> Control:
	if items.is_empty():
		return InventoryStyle.label("Aucun.", 16, InventoryStyle.TEXT_SECONDARY, 600)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var keys: Array = items.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ia := LootDB.get_item(StringName(str(a)))
		var ib := LootDB.get_item(StringName(str(b)))
		var ra := ia.rarity if ia != null else 0
		var rb := ib.rarity if ib != null else 0
		return ra > rb if ra != rb else str(a) < str(b))
	var shown := 0
	for k: Variant in keys:
		var it := LootDB.get_item(StringName(str(k)))
		if it == null:
			continue
		if shown >= 8:
			row.add_child(InventoryStyle.label("+%d" % (keys.size() - shown), 18, InventoryStyle.TEXT_SECONDARY, 800))
			break
		var n := int(items[k])
		var tile := Control.new()
		tile.custom_minimum_size = Vector2(60, 60)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.draw.connect(func() -> void:
			InventoryStyle.draw_item_tile(tile, Rect2(Vector2.ZERO, tile.size), it, n, false, LootVisuals.text_font(800)))
		row.add_child(tile)
		shown += 1
	return row


func _stat_chip(label_text: String, value_text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = InventoryStyle.NIGHT_BLUE_LIGHT
	st.set_corner_radius_all(12)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var l := InventoryStyle.label(label_text, 16, InventoryStyle.TEXT_SECONDARY, 700)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	h.add_child(InventoryStyle.label(value_text, 26, color, 900))
	return p


# --- Sortie ----------------------------------------------------------------------------

func go_to_menu() -> void:
	if _menu_btn != null:
		_menu_btn.disabled = true
	menu_requested.emit()
	var tree := get_tree()
	tree.paused = false
	_paused_by_me = false
	if ResourceLoader.exists(MAIN_MENU_SCENE):
		tree.change_scene_to_file(MAIN_MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			get_viewport().set_input_as_handled()
			go_to_menu()
