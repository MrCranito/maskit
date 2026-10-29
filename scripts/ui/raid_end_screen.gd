class_name RaidEndScreen
extends CanvasLayer
## Écran de fin de raid (construit en code), direction « D » : maquettes Death / Extract
## (https://claude.ai/artifact/FTXHPHfN5wZRxSQDW8oaDq), plein écran sur le raid en pause :
##   - gauche : petit libellé (« RAID ÉCHOUÉ » rose / carte en violet), verdict géant en Anton
##     (« ÉLIMINÉ » / « EXTRAIT ») ;
##   - extraction : pastilles de bilan (valeur estimée en or au marchand, gemmes, armes, objets),
##     « AJOUTÉ À TA RÉSERVE » : cartes d'armes D (rareté décroissante), puis les objets ;
##   - mort : « PERDU » : cartes barrées et grisées, butin perdu, « GARDÉ » (XP), cadeau du
##     pistolet si la réserve est vide ;
##   - encart « Armurerie » : victimes qui comptent pour un déblocage (summary.unlock_kills) ;
##   - droite : bandeau violet translucide dépoli : XP du pass et niveau de raider, bouton encre
##     secondaire (« VOIR L'INVENTAIRE » / « REFAIRE MON ARSENAL »), puis « CONTINUER » / « AU CAMP ».
## Le jeu est en pause derrière (PROCESS_MODE_ALWAYS). Tout tient à l'écran sans défilement
## vertical (1280×720 et téléphones larges) ; les armes défilent horizontalement.

signal menu_requested

const MAIN_MENU_SCENE := "res://scenes/ui/menus/main_menu.tscn"
const NIGHT := Color(0.024, 0.027, 0.05, 0.94)
const SUCCESS := Color(0.718, 0.608, 1.0)
const DEATH := Color(1.0, 0.24, 0.43)
const CARD_H := 112.0

## true = extraction, false = mort.
var success: bool = false
## Résumé de Profile.finish_extraction / finish_death, complété par Raid :
##   extraction : {weapons: Array[StringName], items: Dictionary(id → n), value: int (or estimé), gems: int, unlock_kills: Array}
##   mort : {lost_weapons: Array[StringName], starter_given: bool, lost_items: int, lost_value: int,
##           lost_estimate: int (or estimé), unlock_kills: Array}
var summary: Dictionary = {}

## Colonne de gauche (verdict + bilan) ; `_slab` = bandeau de droite.
var _panel: Control = null
var _slab: Control = null
var _menu_btn: Button = null
var _second_btn: Button = null
var _paused_by_me: bool = false
var _left_w: float = 800.0


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
	var accent := SUCCESS if success else DEATH
	var vp: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720)
	var m: Vector4 = HudSafeArea.margins(get_viewport()) if is_inside_tree() else Vector4(16, 16, 16, 16)
	m.x = maxf(m.x, Balance.get_float("menu", "lobby_margin_left", 80.0))
	m.w = maxf(m.w, Balance.get_float("menu", "lobby_margin_bottom", 36.0))
	m.y = maxf(m.y, 24.0)
	var slab_w: float = clampf(vp.x * Balance.get_float("menu", "lobby_slab_ratio", 0.3),
		Balance.get_float("menu", "lobby_slab_min", 370.0), Balance.get_float("menu", "lobby_slab_max", 440.0))
	_left_w = vp.x - m.x - slab_w - 30.0

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	# Voile : encre à gauche (lisibilité), le raid reste visible à droite ; teinte rouge à la mort
	var g := Gradient.new()
	g.set_color(0, Color(MenuKit.NIGHT_DEEP, 0.95))
	g.add_point(0.58, Color(0.16, 0.02, 0.08, 0.7) if not success else Color(MenuKit.NIGHT_DEEP, 0.7))
	g.set_color(g.get_point_count() - 1, Color(MenuKit.NIGHT_DEEP, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 4
	var veil := TextureRect.new()
	veil.texture = gt
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(veil)
	var deco := MainMenu.LobbyDeco.new()
	deco.accent = DEATH if not success else MenuKit.VIOLET
	deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(deco)

	# Bandeau violet de droite
	var sl := MainMenu.LobbySlab.new()
	sl.name = "Slab"
	sl.cut = Balance.get_float("menu", "lobby_slab_cut", 94.0)
	sl.color = Color(MenuKit.VIOLET, Balance.get_float("menu", "lobby_slab_alpha", 0.66) - 0.04)
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.anchor_left = 1.0
	sl.anchor_right = 1.0
	sl.anchor_bottom = 1.0
	sl.offset_left = -slab_w
	root.add_child(sl)
	MenuKit.frosted(sl)
	_slab = sl
	_build_slab(sl, m)

	# Colonne de gauche
	var col := VBoxContainer.new()
	col.name = "Left"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 12)
	col.position = Vector2(m.x, m.y + 6.0)
	col.custom_minimum_size = Vector2(_left_w, 0)
	root.add_child(col)
	_panel = col
	var kick := MenuKit.label(_kicker_text(), 18, accent if not success else MenuKit.GOLD, MenuKit.nunito(600), 0)
	kick.uppercase = true
	col.add_child(kick)
	var verdict := MenuKit.label("EXTRAIT" if success else "ÉLIMINÉ", int(Balance.get_value("menu", "raid_end_title_size", 132)),
		MenuKit.TEXT, MenuKit.display(), 0)
	verdict.name = "Verdict"
	verdict.custom_minimum_size.y = 0
	col.add_child(verdict)
	var sub := MenuKit.label("Ton butin rejoint ta réserve." if success else "Ton arsenal et ton butin sont perdus.",
		18, Color(1, 1, 1, 0.75), MenuKit.nunito(600), 0)
	sub.uppercase = true
	col.add_child(sub)
	if success:
		_build_success(col)
	else:
		_build_death(col)
	_add_kills(col)

	# Entrée : la colonne glisse depuis la gauche, le bandeau apparaît en fondu
	col.modulate.a = 0.0
	sl.modulate.a = 0.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(col, "modulate:a", 1.0, 0.3)
	tw.tween_property(col, "position:x", col.position.x, 0.4).from(col.position.x - 60.0)
	tw.tween_property(sl, "modulate:a", 1.0, 0.35).set_delay(0.08)   # fondu seul : le bouton reste à l'écran


func _kicker_text() -> String:
	if not success:
		return "Raid échoué"
	var card: Variant = GameState.get("current_map") if GameState != null else null
	return (card as MapCard).display_name if card is MapCard else "Raid terminé"


## Bandeau : XP du pass + niveau de raider en haut, bouton secondaire et bouton principal en bas.
func _build_slab(sl: Control, m: Vector4) -> void:
	var col := VBoxContainer.new()
	col.name = "SlabContent"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 16.0
	col.offset_top = maxf(m.y, 36.0)
	col.offset_right = -maxf(m.z, 44.0)
	col.offset_bottom = -maxf(m.w, 40.0)
	col.add_theme_constant_override("separation", 8)
	sl.add_child(col)
	_add_pass_xp(col)
	_add_raider_xp(col)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	_second_btn = _ink_button("Voir l'inventaire" if success else "Refaire mon arsenal")
	_second_btn.name = "SecondButton"
	_second_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_second_btn.pressed.connect(func() -> void:
		go_to_menu(MenuKit.MERCHANT_SCENE if success else MenuKit.MAP_SELECT_SCENE))
	col.add_child(_second_btn)
	_menu_btn = Button.new()
	_menu_btn.name = "MenuButton"
	_menu_btn.text = "CONTINUER" if success else "AU CAMP"
	_menu_btn.focus_mode = Control.FOCUS_ALL
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_menu_btn.add_theme_font_override("font", MenuKit.display())
	_menu_btn.add_theme_font_size_override("font_size", int(Balance.get_value("menu", "deploy_font_size", 84)))
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_menu_btn.add_theme_color_override(k, MenuKit.TEXT)
	var hov := CutBox.make(Color(1, 1, 1, 0.1), 14.0, Color(0, 0, 0, 0), 0.0, 6.0, 0.0)
	for k: String in ["normal", "pressed", "focus"]:
		_menu_btn.add_theme_stylebox_override(k, CutBox.make(Color(0, 0, 0, 0), 14.0, Color(0, 0, 0, 0), 0.0, 6.0, 0.0))
	_menu_btn.add_theme_stylebox_override("hover", hov)
	_menu_btn.add_theme_stylebox_override("hover_pressed", hov)
	_menu_btn.pressed.connect(go_to_menu)
	col.add_child(_menu_btn)


## Bouton encre à coin haut gauche coupé, libellé Anton (bouton secondaire du bandeau).
func _ink_button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt.to_upper()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(Balance.get_float("menu", "loadout_detail_width", 300.0), 66)
	b.add_theme_font_override("font", MenuKit.display())
	b.add_theme_font_size_override("font_size", 25)
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, MenuKit.TEXT)
	var mk := func(bg: Color) -> CutBox:
		var c := CutBox.make(bg, 16.0, Color(0, 0, 0, 0), 0.0, 16.0, 0.0)
		c.corners = CutBox.CUT_TOP_LEFT
		return c
	b.add_theme_stylebox_override("normal", mk.call(MenuKit.NIGHT_DEEP))
	b.add_theme_stylebox_override("hover", mk.call(MenuKit.NIGHT_PANEL))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0, 0, 0, 1)))
	b.add_theme_stylebox_override("hover_pressed", mk.call(Color(0, 0, 0, 1)))
	var f := CutBox.new()
	f.draw_center = false
	f.border_color = MenuKit.TEXT
	f.border_width = 2.0
	f.cut = 18.0
	f.corners = CutBox.CUT_TOP_LEFT
	f.grow = 3.0
	b.add_theme_stylebox_override("focus", f)
	return b


## Largeur de la colonne de gauche (compatibilité).
func panel_width() -> float:
	return _left_w


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
	var items: Dictionary = summary.get("items", {})
	var n_items := 0
	for k: Variant in items:
		n_items += int(items[k])
	var weapons: Array = sort_by_rarity(summary.get("weapons", []))
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	root.add_child(chips)
	var vchip := _stat_chip("Valeur estimée (or au marchand)", "≈ %d" % int(summary.get("value", 0)), MenuKit.COIN)
	vchip.name = "ValueChip"
	chips.add_child(vchip)
	chips.add_child(_stat_chip("Gemmes", "+%d" % int(summary.get("gems", 0)), MenuKit.GEM))
	chips.add_child(_stat_chip("Armes", str(weapons.size()), MenuKit.GOLD))
	chips.add_child(_stat_chip("Objets", str(n_items), Color(1, 1, 1, 0.4)))
	root.add_child(_section("Ajouté à ta réserve", "%d arme%s · %d objet%s · par rareté" % [
		weapons.size(), "s" if weapons.size() > 1 else "", n_items, "s" if n_items > 1 else ""], MenuKit.GOLD))
	root.add_child(_weapon_row(weapons, false))
	if not items.is_empty():
		root.add_child(_item_row(items))


func _build_death(root: VBoxContainer) -> void:
	var lost: Array = sort_by_rarity(summary.get("lost_weapons", []))
	var n := int(summary.get("lost_items", 0))
	# Or estimé au marchand (Profile.finish_death : lost_estimate), sinon la valeur brute convertie.
	var v := int(summary.get("lost_estimate", round(float(summary.get("lost_value", 0)) * Economy.cfg_f("sell_ratio", 0.5))))
	var right := ("Butin : %d objet%s · ≈ %d or" % [n, "s" if n > 1 else "", v]) if n > 0 else "Aucun butin perdu"
	root.add_child(_section("Perdu", right, Color(1.0, 0.44, 0.57)))
	root.add_child(_weapon_row(lost, true))
	if bool(summary.get("starter_given", false)):
		var gift := PanelContainer.new()
		gift.name = "StarterGift"
		var gs := StyleBoxFlat.new()
		gs.bg_color = Color(MenuKit.VIOLET, 0.35)
		gs.content_margin_left = 14
		gs.content_margin_right = 14
		gs.content_margin_top = 8
		gs.content_margin_bottom = 8
		gift.add_theme_stylebox_override("panel", gs)
		gift.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var gl := MenuKit.label("Un petit pistolet t'attend au camp.", 17, MenuKit.TEXT, MenuKit.nunito(600), 0)
		gl.uppercase = true
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
	st.bg_color = Color(MenuKit.NIGHT_DEEP, 0.8)
	st.border_color = MenuKit.GOLD if unlocked else Color(1, 1, 1, 0.3)
	st.border_width_left = 4
	st.content_margin_left = 14
	st.content_margin_right = 14
	st.content_margin_top = 5
	st.content_margin_bottom = 6
	box.add_theme_stylebox_override("panel", st)
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var l := MenuKit.label("Armurerie · " + "  ·  ".join(parts), 16, MenuKit.GOLD if unlocked else MenuKit.TEXT, MenuKit.nunito(600), 0)
	l.name = "KillsText"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.custom_minimum_size = Vector2(minf(_left_w - 30.0, 760.0), 0)
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


## Titre de rubrique : libellé à gauche (couleur d'accent), précision à droite (blanc atténué).
func _section(text: String, right: String = "", color: Color = Color(1, 1, 1, 0.65)) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.x = _left_w
	var l := MenuKit.label(text, 17, color, MenuKit.nunito(600), 0)
	l.uppercase = true
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if not right.is_empty():
		var r := MenuKit.label(right, 17, Color(1, 1, 1, 0.6), MenuKit.nunito(600), 0)
		r.uppercase = true
		row.add_child(r)
	return row


## Rangée HORIZONTALE défilable de cartes d'armes (icône + nom couleur de rareté), déjà
## triée. Barrées si perdues. Défilement au doigt (glisser) ou à la molette.
func _weapon_row(ids: Array, lost: bool) -> Control:
	if ids.is_empty():
		var none := MenuKit.label("Aucune arme.", 17, Color(1, 1, 1, 0.55), MenuKit.nunito(600), 0)
		return none
	var scroll := ScrollContainer.new()
	scroll.name = "WeaponRow"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(_left_w, CARD_H + 10.0)
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.name = "Cards"
	row.add_theme_constant_override("separation", 8)
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
	return vp.encloses(_panel.get_global_rect()) and _menu_btn != null \
		and vp.encloses(_menu_btn.get_global_rect())


## Carte d'arme D : encre à coin haut droit coupé, halo de rareté, icône, nom en Anton, barre de
## rareté en bas ; perdue = grisée, barrée en rose, liseré gauche rose.
func _weapon_card(w: WeaponData, lost: bool) -> Control:
	var rc := w.get_rarity_color()
	var card := Panel.new()
	card.set_meta(&"weapon_id", w.id)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.92), 18.0, Color(0, 0, 0, 0), 0.0, 0.0, 0.0)
	box.corners = CutBox.CUT_TOP_RIGHT
	if lost:
		box.accent_width = 4.0
		box.accent_color = DEATH
	card.add_theme_stylebox_override("panel", box)
	card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	card.custom_minimum_size = Vector2(Balance.get_float("menu", "raid_end_card_width", 200.0), CARD_H)
	if not lost:
		card.add_child(MenuKit.rarity_backdrop(w.rarity))
	var pic := Control.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.offset_top = 10
	pic.offset_bottom = -44
	pic.draw.connect(func() -> void:
		LootVisuals.draw_weapon(pic, Rect2(Vector2(18, 2), pic.size - Vector2(36, 4)), w, Color(0.6, 0.6, 0.66, 0.6) if lost else Color.WHITE))
	card.add_child(pic)
	WeaponSkin.apply_equipped(pic, w)   # skin d'arme équipé (recoloration)
	var nm := MenuKit.label(w.display_name, 19, Color(1, 1, 1, 0.55) if lost else MenuKit.TEXT, MenuKit.display(), 0)
	nm.uppercase = true
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nm.offset_top = -42
	nm.offset_bottom = -10
	nm.offset_left = 8
	nm.offset_right = -8
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(nm)
	if lost:
		var strike := ColorRect.new()
		strike.color = Color(DEATH, 0.85)
		strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strike.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		strike.offset_top = -27
		strike.offset_bottom = -25
		strike.offset_left = 30
		strike.offset_right = -30
		card.add_child(strike)
	else:
		var bar := ColorRect.new()
		bar.color = rc
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = -4
		card.add_child(bar)
	return card


## Ligne de tuiles d'objets (au plus 8, puis « +N »).
func _item_row(items: Dictionary) -> Control:
	if items.is_empty():
		return MenuKit.label("Aucun objet.", 17, Color(1, 1, 1, 0.55), MenuKit.nunito(600), 0)
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
			row.add_child(MenuKit.label("+%d" % (keys.size() - shown), 20, Color(1, 1, 1, 0.6), MenuKit.display(), 0))
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


## XP et niveau de raider (summary["raider"] = {xp, level_before, level_after, unlocks}, ajouté par
## Raid), dans le bandeau : « NIVEAU DE RAIDER N », « +XP » en Anton, déblocages obtenus.
func _add_raider_xp(root: VBoxContainer) -> void:
	var rx: Variant = summary.get("raider")
	if not (rx is Dictionary) or (rx as Dictionary).is_empty():
		return
	var d: Dictionary = rx
	var after := int(d.get("level_after", 1))
	var up := after > int(d.get("level_before", 1))
	var box := _slab_block("RaiderXp", ("Niveau %d atteint" % after) if up else ("Niveau de raider %d" % after),
		"+%d XP" % int(d.get("xp", 0)), 34)
	root.add_child(box)
	var names: PackedStringArray = []
	for u: Variant in d.get("unlocks", []):
		if u is Dictionary:
			names.append(RaiderProgress.label_of(u))
	if not names.is_empty():
		var l := _right_label("Débloqué : " + " · ".join(names), 16, MenuKit.TEXT)
		l.name = "RaiderUnlocks"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = Balance.get_float("menu", "loadout_detail_width", 300.0)
		l.size_flags_horizontal = Control.SIZE_SHRINK_END
		root.add_child(l)


## XP du pass de combat (summary["pass_xp"] = {xp, tier_before, tier_after}, ajouté par Raid),
## dans le bandeau : « PASS DE COMBAT · PALIER N », « +XP ».
func _add_pass_xp(root: VBoxContainer) -> void:
	var px: Variant = summary.get("pass_xp")
	if not (px is Dictionary) or (px as Dictionary).is_empty():
		return
	var d: Dictionary = px
	var before := int(d.get("tier_before", 0))
	var after := int(d.get("tier_after", 0))
	var k := ("Pass de combat · palier %d → %d" % [before, after]) if after > before else ("Pass de combat · palier %d" % after)
	root.add_child(_slab_block("PassXp", k, "+%d XP" % int(d.get("xp", 0))))


func _slab_block(node_name: String, kicker: String, value: String, value_px: int = 50) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = node_name
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	var k := _right_label(kicker, 17, MenuKit.TEXT)
	k.uppercase = true
	v.add_child(k)
	var val := MenuKit.label(value, value_px, MenuKit.TEXT, MenuKit.display(), 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(val)
	return v


func _right_label(txt: String, px: int, color: Color) -> Label:
	var l := MenuKit.label(txt, px, color, MenuKit.nunito(600), 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


## Pastille de bilan (maquette Extract) : encre, liseré bas coloré, gros chiffre Anton, libellé.
func _stat_chip(label_text: String, value_text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(MenuKit.NIGHT_DEEP, 0.8)
	st.border_color = color
	st.border_width_bottom = 4
	st.content_margin_left = 18
	st.content_margin_right = 18
	st.content_margin_top = 6
	st.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(Balance.get_float("menu", "raid_end_chip_width", 190.0), 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	p.add_child(v)
	v.add_child(MenuKit.label(value_text, 33, MenuKit.TEXT, MenuKit.display(), 0))
	var l := MenuKit.label(label_text, 14, Color(1, 1, 1, 0.65), MenuKit.nunito(600), 0)
	l.uppercase = true
	v.add_child(l)
	return p


# --- Sortie ----------------------------------------------------------------------------

## Quitte l'écran : menu principal par défaut, ou `path` (inventaire, choix des cartes) s'il existe.
func go_to_menu(path: String = MAIN_MENU_SCENE) -> void:
	for b: Button in [_menu_btn, _second_btn]:
		if b != null:
			b.disabled = true
	menu_requested.emit()
	var tree := get_tree()
	tree.paused = false
	_paused_by_me = false
	var target := path if ResourceLoader.exists(path) else MAIN_MENU_SCENE
	if ResourceLoader.exists(target):
		tree.change_scene_to_file(target)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE:
			get_viewport().set_input_as_handled()
			go_to_menu()
