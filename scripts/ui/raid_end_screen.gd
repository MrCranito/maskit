class_name RaidEndScreen
extends CanvasLayer
## Écran de fin de raid (construit en code, charte bleu nuit) affiché par Raid :
##   - « Extraction réussie » : armes récupérées (rareté), objets, valeur estimée en or au marchand
##     (l'extraction ne donne plus d'or : on vend au marchand), gemmes gagnées ;
##   - encart « Armurerie » : victimes du raid qui comptent pour un déblocage d'arme (summary.unlock_kills) ;
##   - « Tu es mort » : armes perdues, butin perdu, « Un petit pistolet t'attend au camp »
##     si un pistolet de départ a été offert.
## Le jeu est en pause derrière (ce nœud tourne en PROCESS_MODE_ALWAYS).
## Mise en page : tout tient à l'écran SANS défilement vertical (1280×720 et téléphones larges) ;
## armes et équipements = une rangée horizontale défilable, triée par rareté décroissante
## (Légendaire d'abord, puis catégorie, puis nom) ; « Retour au menu » toujours visible.
## Bouton « Retour au menu » → menu principal.

signal menu_requested

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const NIGHT := Color(0.024, 0.027, 0.05, 0.94)
const SUCCESS := Color(0.718, 0.608, 1.0)
const DEATH := Color(1.0, 0.3, 0.43)
const CARD_H := 104.0

## true = extraction, false = mort.
var success: bool = false
## Résumé de Profile.finish_extraction / finish_death, complété par Raid :
##   extraction : {weapons: Array[StringName], items: Dictionary(id → n), value: int (or estimé), gems: int, unlock_kills: Array}
##   mort : {lost_weapons: Array[StringName], starter_given: bool, lost_items: int, lost_value: int,
##           lost_estimate: int (or estimé), unlock_kills: Array}
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

	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(safe)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(center)
	_apply_safe_margins(safe)

	var accent := SUCCESS if success else DEATH
	_panel = PanelContainer.new()
	var st := InventoryStyle.panel(24, 26, NIGHT)
	st.border_color = Color(accent, 0.85)
	st.set_border_width_all(2)
	st.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", st)
	_panel.custom_minimum_size = Vector2(panel_width(), 0)
	center.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	_panel.add_child(root)

	var title := InventoryStyle.title(get_title_text(), 40, accent.lightened(0.15))
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

	_add_pass_xp(root)
	_add_raider_xp(root)

	_menu_btn = InventoryStyle.button("Retour au menu", InventoryStyle.VIOLET, 24, Vector2(300, 62))
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu_btn.pressed.connect(go_to_menu)
	root.add_child(_menu_btn)

	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	_panel.resized.connect(func() -> void: _panel.pivot_offset = _panel.size * 0.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Largeur du panneau : 900 px max, dans la zone sûre.
func panel_width() -> float:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var m := HudSafeArea.margins(get_viewport()) if is_inside_tree() else Vector4(16, 16, 16, 16)
	return minf(900.0, vp.x - m.x - m.z - 24.0)


func _apply_safe_margins(mc: MarginContainer) -> void:
	var m := HudSafeArea.margins(get_viewport()) if is_inside_tree() else Vector4(16, 16, 16, 16)
	mc.add_theme_constant_override("margin_left", int(m.x))
	mc.add_theme_constant_override("margin_top", int(m.y))
	mc.add_theme_constant_override("margin_right", int(m.z))
	mc.add_theme_constant_override("margin_bottom", int(m.w))


## Ids triés : rareté décroissante, puis ordre des catégories (équipements en dernier), puis nom.
static func sort_by_rarity(ids: Array) -> Array:
	var out: Array = []
	for id: Variant in ids:
		if WeaponCatalog.get_weapon(StringName(str(id))) != null:
			out.append(id)
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var wa := WeaponCatalog.get_weapon(StringName(str(a)))
		var wb := WeaponCatalog.get_weapon(StringName(str(b)))
		if wa.rarity != wb.rarity:
			return wa.rarity > wb.rarity
		var ca := WeaponData.CATEGORIES.find(wa.category)
		var cb := WeaponData.CATEGORIES.find(wb.category)
		if ca != cb:
			return ca < cb
		return wa.display_name < wb.display_name)
	return out


func _build_success(root: VBoxContainer) -> void:
	var split := split_gadgets(summary.get("weapons", []))
	var all_ids: Array = sort_by_rarity(summary.get("weapons", []))
	var title := "Armes récupérées (%d)" % (split[0] as Array).size()
	if not (split[1] as Array).is_empty():
		title += " · équipement (%d)" % (split[1] as Array).size()
	root.add_child(_section(title))
	root.add_child(_weapon_row(all_ids, false))

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
	var vchip := _stat_chip("Valeur estimée (or au marchand)", "≈ %d" % int(summary.get("value", 0)), InventoryStyle.GOLD)
	vchip.name = "ValueChip"
	stats.add_child(vchip)
	stats.add_child(_stat_chip("Gemmes", "+%d" % int(summary.get("gems", 0)), Color(0.55, 0.85, 1.0)))
	_add_kills(root)


func _build_death(root: VBoxContainer) -> void:
	var split := split_gadgets(summary.get("lost_weapons", []))
	var title := "Armes perdues (%d)" % (split[0] as Array).size()
	if not (split[1] as Array).is_empty():
		title += " · équipement perdu (%d)" % (split[1] as Array).size()
	root.add_child(_section(title))
	root.add_child(_weapon_row(sort_by_rarity(summary.get("lost_weapons", [])), true))
	var n := int(summary.get("lost_items", 0))
	# Or estimé au marchand (Profile.finish_death : lost_estimate), sinon la valeur brute convertie.
	var v := int(summary.get("lost_estimate", round(float(summary.get("lost_value", 0)) * Economy.cfg_f("sell_ratio", 0.5))))
	var loot := InventoryStyle.label(
		("Butin perdu : %d objet%s (≈ %d or au marchand)" % [n, "s" if n > 1 else "", v]) if n > 0 else "Aucun butin à perdre.",
		18, InventoryStyle.TEXT, 700)
	loot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(loot)
	_add_kills(root)
	if bool(summary.get("starter_given", false)):
		var gift := PanelContainer.new()
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(InventoryStyle.GOLD, 0.14)
		gs.border_color = Color(InventoryStyle.GOLD, 0.7)
		gs.set_border_width_all(1)
		gs.set_corner_radius_all(2)
		gs.set_content_margin_all(10)
		gift.add_theme_stylebox_override("panel", gs)
		var gl := InventoryStyle.label("Un petit pistolet t'attend au camp.", 19, InventoryStyle.GOLD, 800)
		gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gift.add_child(gl)
		root.add_child(gift)


## Encart « Déblocages » : victimes du raid qui comptent pour l'armurerie (summary["unlock_kills"],
## Economy.kill_report). Une ligne compacte (tient à l'écran) ; rien si aucune.
func _add_kills(root: VBoxContainer) -> void:
	var rep: Variant = summary.get("unlock_kills", [])
	if not (rep is Array) or (rep as Array).is_empty():
		return
	var parts: PackedStringArray = []
	var unlocked := false
	for e: Variant in rep:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		var txt := "%s ×%d" % [str(d.get("name", "")), int(d.get("count", 0))]
		var ws: PackedStringArray = []
		for w: Variant in d.get("weapons", []):
			var wd: Dictionary = w
			if bool(wd.get("done", false)):
				ws.append("%s débloquée" % str(wd.get("name", "")))
				unlocked = true
			else:
				ws.append("%s %d/%d" % [str(wd.get("name", "")), mini(int(d.get("total", 0)), int(wd.get("needed", 1))), int(wd.get("needed", 1))])
		if not ws.is_empty():
			txt += " → " + ", ".join(ws)
		parts.append(txt)
	if parts.is_empty():
		return
	var box := PanelContainer.new()
	box.name = "KillsBox"
	var st := StyleBoxFlat.new()
	st.bg_color = Color(InventoryStyle.GOLD, 0.12 if unlocked else 0.06)
	st.border_color = Color(InventoryStyle.GOLD, 0.75 if unlocked else 0.35)
	st.set_border_width_all(1)
	st.set_corner_radius_all(2)
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 5
	st.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", st)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var l := InventoryStyle.label("Armurerie · " + "  ·  ".join(parts), 15, InventoryStyle.GOLD if unlocked else InventoryStyle.TEXT, 800)
	l.name = "KillsText"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(minf(panel_width() - 80.0, 760.0), 0)
	box.add_child(l)
	root.add_child(box)


## Texte de l'encart des déblocages ("" si absent ; tests).
func get_kills_text() -> String:
	var l := find_child("KillsText", true, false) as Label
	return l.text if l != null else ""


## Sépare une liste d'ids en [armes, équipements].
static func split_gadgets(ids: Array) -> Array:
	var weapons: Array = []
	var gadgets: Array = []
	for id: Variant in ids:
		var w := WeaponCatalog.get_weapon(StringName(str(id)))
		if w != null and w.is_gadget():
			gadgets.append(id)
		else:
			weapons.append(id)
	return [weapons, gadgets]


func _section(text: String) -> Label:
	var l := InventoryStyle.label(text.to_upper(), 15, InventoryStyle.TEXT_SECONDARY, 800)
	return l


## Rangée HORIZONTALE défilable de cartes d'armes (icône + nom couleur de rareté), déjà
## triée. Barrées si perdues. Défilement au doigt (glisser) ou à la molette.
func _weapon_row(ids: Array, lost: bool) -> Control:
	if ids.is_empty():
		var none := InventoryStyle.label("Aucune.", 16, InventoryStyle.TEXT_SECONDARY, 600)
		return none
	var scroll := ScrollContainer.new()
	scroll.name = "WeaponRow"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, CARD_H + 14.0)
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.name = "Cards"
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(row)
	for id: Variant in ids:
		var w := WeaponCatalog.get_weapon(StringName(str(id)))
		if w != null:
			row.add_child(_weapon_card(w, lost))
	return scroll


## Ids des cartes affichées, dans l'ordre (tests).
func get_card_ids() -> Array:
	var out: Array = []
	var row := find_child("Cards", true, false)
	if row == null:
		return out
	for c: Node in row.get_children():
		out.append(c.get_meta(&"weapon_id", &""))
	return out


## Le panneau tient-il à l'écran sans défilement vertical ?
func fits_on_screen() -> bool:
	if _panel == null or not is_inside_tree():
		return false
	var vp := get_viewport().get_visible_rect()
	return vp.encloses(_panel.get_global_rect().grow(-1.0)) and _menu_btn != null \
		and vp.encloses(_menu_btn.get_global_rect())


func _weapon_card(w: WeaponData, lost: bool) -> Control:
	var rc := w.get_rarity_color()
	var card := PanelContainer.new()
	card.set_meta(&"weapon_id", w.id)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var st := StyleBoxFlat.new()
	st.bg_color = InventoryStyle.NIGHT_BLUE_DEEP.lerp(rc, 0.12)
	st.border_color = Color(rc, 0.4 if lost else 0.9)
	st.set_border_width_all(2)
	st.set_corner_radius_all(2)
	st.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", st)
	card.custom_minimum_size = Vector2(176, CARD_H)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(160, 48)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.draw.connect(func() -> void:
		LootVisuals.draw_weapon(pic, Rect2(Vector2(10, 2), pic.size - Vector2(20, 4)), w, Color(1, 1, 1, 0.45) if lost else Color.WHITE)
		if lost:
			pic.draw_line(Vector2(14, pic.size.y - 6), Vector2(pic.size.x - 14, 6), Color(DEATH, 0.85), 4.0, true))
	v.add_child(pic)
	WeaponSkin.apply_equipped(pic, w)   # skin d'arme équipé (recoloration)
	var nm := InventoryStyle.label(w.display_name, 15, rc.lightened(0.25) if not lost else Color(rc, 0.7), 800)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(160, 0)
	v.add_child(nm)
	var cat := ("Équipement ×%d" % w.charges) if w.is_gadget() else w.get_category_name()
	v.add_child(InventoryStyle.label("%s · %s" % [cat, w.get_rarity_name()], 12, InventoryStyle.TEXT_SECONDARY, 700))
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


## XP et niveau de raider (summary["raider"] = {xp, level_before, level_after, unlocks}, ajouté par Raid) :
## une pastille « Niveau de raider N », puis une ligne par déblocage obtenu.
func _add_raider_xp(root: VBoxContainer) -> void:
	var rx: Variant = summary.get("raider")
	if not (rx is Dictionary) or (rx as Dictionary).is_empty():
		return
	var d: Dictionary = rx
	var after := int(d.get("level_after", 1))
	var up := after > int(d.get("level_before", 1))
	var txt := ("Niveau de raider %d atteint !" % after) if up else ("Niveau de raider %d" % after)
	var chip := _stat_chip(txt, "+%d XP" % int(d.get("xp", 0)), InventoryStyle.GOLD)
	chip.name = "RaiderXp"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(chip)
	var names: PackedStringArray = []
	for u: Variant in d.get("unlocks", []):
		if u is Dictionary:
			names.append(RaiderProgress.label_of(u))
	if not names.is_empty():
		var l := InventoryStyle.label("Débloqué : " + "  ·  ".join(names), 16, InventoryStyle.GOLD, 700)
		l.name = "RaiderUnlocks"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(l)


## XP du pass de combat gagnée (summary["pass_xp"] = {xp, tier_before, tier_after}, ajouté par Raid).
func _add_pass_xp(root: VBoxContainer) -> void:
	var px: Variant = summary.get("pass_xp")
	if not (px is Dictionary) or (px as Dictionary).is_empty():
		return
	var d: Dictionary = px
	var txt := "Pass de combat : palier %d" % int(d.get("tier_after", 0))
	if int(d.get("tier_after", 0)) > int(d.get("tier_before", 0)):
		txt = "Pass de combat : palier %d atteint !" % int(d.get("tier_after", 0))
	var chip := _stat_chip(txt, "+%d XP" % int(d.get("xp", 0)), InventoryStyle.GOLD)
	chip.name = "PassXp"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(chip)


func _stat_chip(label_text: String, value_text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = InventoryStyle.NIGHT_BLUE_LIGHT
	st.set_corner_radius_all(2)
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
