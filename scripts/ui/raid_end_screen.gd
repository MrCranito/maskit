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
##   - bilan du raid sous le verdict (summary["stats"]) : tué par, survie, éliminations, étage ;
##   - droite : bandeau violet translucide dépoli : cartes de progression animées (pass de combat,
##     niveau de raider : badge, barre qui se remplit, passage de palier/niveau, prochaine
##     récompense), détail de l'XP, bouton encre secondaire (« VOIR L'INVENTAIRE » /
##     « REFAIRE MON ARSENAL »), puis « CONTINUER » / « AU CAMP ».
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
## Coop : ligne d'information au-dessus des boutons (coéquipier encore en raid…), masquée si vide.
var _note_label: Label = null
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
	_add_stats(col)
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
	verdict.pivot_offset = Vector2(0, verdict.get_combined_minimum_size().y * 0.6)
	verdict.scale = Vector2(1.35, 1.35)
	tw.tween_property(verdict, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var cards := col.find_child("Cards", true, false)
	if cards != null:
		var i := 0
		for c: Node in cards.get_children():
			var ci := c as CanvasItem
			ci.modulate.a = 0.0
			tw.tween_property(ci, "modulate:a", 1.0, 0.25).set_delay(0.25 + 0.08 * i)
			i += 1


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
	# Le bord gauche du bandeau est en biais (LobbySlab.cut) : la colonne en suit le milieu.
	col.offset_left = maxf(16.0, (sl as MainMenu.LobbySlab).cut * 0.5) if sl is MainMenu.LobbySlab else 16.0
	col.offset_top = maxf(m.y, 36.0)
	col.offset_right = -maxf(m.z, 44.0)
	var avail := -sl.offset_left - col.offset_left + col.offset_right
	col.offset_bottom = -maxf(m.w, 40.0)
	col.add_theme_constant_override("separation", 10)
	sl.add_child(col)
	_add_pass_xp(col)
	_add_raider_xp(col)
	_add_xp_breakdown(col)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	_note_label = MenuKit.label("", 16, Color(1, 1, 1, 0.85), MenuKit.nunito(600), 0)
	_note_label.name = "CoopNote"
	_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_note_label.custom_minimum_size.x = avail
	_note_label.visible = false
	col.add_child(_note_label)
	_second_btn = _ink_button("Voir l'inventaire" if success else "Refaire mon arsenal")
	_second_btn.name = "SecondButton"
	_second_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_second_btn.custom_minimum_size.x = minf(_second_btn.custom_minimum_size.x, avail)
	_second_btn.pressed.connect(func() -> void:
		go_to_menu(MenuKit.MERCHANT_SCENE if success else MenuKit.MAP_SELECT_SCENE))
	col.add_child(_second_btn)
	_menu_btn = Button.new()
	_menu_btn.name = "MenuButton"
	_menu_btn.text = "CONTINUER" if success else "AU CAMP"
	_menu_btn.focus_mode = Control.FOCUS_ALL
	_menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_menu_btn.add_theme_font_override("font", MenuKit.display())
	# Taille du libellé réduite s'il ne tient pas dans la colonne (« CONTINUER » est long).
	var fs := int(Balance.get_value("menu", "deploy_font_size", 84))
	var tw := MenuKit.display().get_string_size(_menu_btn.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0
	if tw > avail:
		fs = int(floor(float(fs) * avail / tw))
	_menu_btn.add_theme_font_size_override("font_size", fs)
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


## Coop : texte d'information au-dessus des boutons du bandeau ("" = masqué).
func set_note(text: String) -> void:
	if _note_label == null:
		return
	_note_label.text = text
	_note_label.visible = not text.is_empty()


func get_note() -> String:
	return _note_label.text if _note_label != null and _note_label.visible else ""


## Largeur de la colonne de gauche (compatibilité).
func panel_width() -> float:
	return _left_w


## Ids triés : rareté décroissante, puis ordre des catégories (équipements en dernier), puis nom.
## Les éléments peuvent être des ids ou des entrées {id, affixes} (weapon_entries / lost_entries).
static func sort_by_rarity(ids: Array) -> Array:
	var out: Array = []
	for id: Variant in ids:
		if WeaponCatalog.get_weapon(entry_id(id)) != null:
			out.append(id)
	out.sort_custom(func(a: Variant, b: Variant) -> bool:
		var wa := WeaponCatalog.get_weapon(entry_id(a))
		var wb := WeaponCatalog.get_weapon(entry_id(b))
		if wa.rarity != wb.rarity:
			return wa.rarity > wb.rarity
		var ca := WeaponData.CATEGORIES.find(wa.category)
		var cb := WeaponData.CATEGORIES.find(wb.category)
		if ca != cb:
			return ca < cb
		if wa.display_name != wb.display_name:
			return wa.display_name < wb.display_name
		return entry_affixes(a).size() > entry_affixes(b).size())
	return out


## Id d'arme d'un élément de liste (id, ou entrée {id, affixes}).
static func entry_id(v: Variant) -> StringName:
	return StringName(str((v as Dictionary).get("id", ""))) if v is Dictionary else StringName(str(v))


static func entry_affixes(v: Variant) -> Array:
	var ax: Variant = (v as Dictionary).get("affixes", []) if v is Dictionary else []
	return ax if ax is Array else []


func _build_success(root: VBoxContainer) -> void:
	var items: Dictionary = summary.get("items", {})
	var n_items := 0
	for k: Variant in items:
		n_items += int(items[k])
	var weapons: Array = sort_by_rarity(summary.get("weapon_entries", summary.get("weapons", [])))
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
	var lost: Array = sort_by_rarity(summary.get("lost_entries", summary.get("lost_weapons", [])))
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
		# Exemplaire avec ses affixes (entrée {id, affixes}) ou modèle seul (id).
		var w := Affixes.make_weapon(WeaponCatalog.get_weapon(entry_id(id)), entry_affixes(id))
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
	var backdrop := MenuKit.rarity_backdrop(w.rarity)
	if lost:
		backdrop.modulate = Color(1, 1, 1, 0.35)
	card.add_child(backdrop)
	var pic := Control.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.offset_top = 10
	pic.offset_bottom = -44
	pic.draw.connect(func() -> void:
		LootVisuals.draw_weapon(pic, Rect2(Vector2(18, 2), pic.size - Vector2(36, 4)), w, Color(0.6, 0.6, 0.66, 0.6) if lost else Color.WHITE))
	card.add_child(pic)
	WeaponSkin.apply_equipped(pic, w)   # skin d'arme équipé (recoloration)
	if w.has_rolled_affixes():
		# Affixes tirés : pastilles en haut, au-dessus de l'icône.
		var ax := AffixBadges.strip(w.rolled_affixes, 11, true)
		ax.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		ax.offset_left = 6
		ax.offset_right = -22
		ax.offset_top = 6
		ax.offset_bottom = 24
		if lost:
			ax.modulate = Color(1, 1, 1, 0.55)
		card.add_child(ax)
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
	var bar := ColorRect.new()
	bar.color = Color(rc, 0.45) if lost else rc
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


## Niveau de raider (summary["raider"] = {xp, level_before, level_after, unlocks, total_before,
## total_after}, ajouté par Raid) : carte de progression animée, déblocages obtenus.
func _add_raider_xp(root: VBoxContainer) -> void:
	var rx: Variant = summary.get("raider")
	if not (rx is Dictionary) or (rx as Dictionary).is_empty():
		return
	var d: Dictionary = rx
	var after := int(d.get("level_after", 1))
	var gain := int(d.get("xp", 0))
	var t1 := int(d.get("total_after", RaiderProgress.xp_total_for(after)))
	var card := XpCard.new()
	card.name = "RaiderXp"
	card.kicker = "Niveau de raider"
	card.up_text = "Niveau supérieur"
	card.gain = gain
	card.total_before = int(d.get("total_before", maxi(t1 - gain, 0)))
	card.total_after = t1
	card.level_of = RaiderProgress.level_for_xp
	card.progress_of = RaiderProgress.level_progress
	var names: PackedStringArray = []
	for u: Variant in d.get("unlocks", []):
		if u is Dictionary:
			names.append(RaiderProgress.label_of(u))
	var next := RaiderProgress.next_unlock(after)
	if not names.is_empty():
		card.footer = "Débloqué : " + " · ".join(names)
		card.footer_hot = true
	elif not next.is_empty():
		card.footer = "Niveau %d : %s" % [int(next["level"]), RaiderProgress.label_of(next)]
	root.add_child(card)
	if not names.is_empty():
		card.set_meta(&"unlocks", names)


## Pass de combat (summary["pass_xp"] = {xp, tier_before, tier_after, total_before, total_after},
## ajouté par Raid) : carte de progression animée, récompense du palier atteint ou suivant.
func _add_pass_xp(root: VBoxContainer) -> void:
	var px: Variant = summary.get("pass_xp")
	if not (px is Dictionary) or (px as Dictionary).is_empty():
		return
	var d: Dictionary = px
	var bp := BattlePassSystem.get_instance()
	var season: BattlePassSeason = bp.get_season() if bp != null else null
	var after := int(d.get("tier_after", 0))
	var gain := int(d.get("xp", 0))
	var card := XpCard.new()
	card.name = "PassXp"
	card.kicker = "Pass de combat"
	card.unit = "Palier"
	card.up_text = "Palier franchi"
	card.gain = gain
	if season != null:
		var t1 := int(d.get("total_after", season.xp_total_for(after)))
		card.total_before = int(d.get("total_before", maxi(t1 - gain, 0)))
		card.total_after = t1
		card.level_of = func(total: int) -> int: return pass_tier_for(season, total)
		card.progress_of = func(total: int) -> Vector2i:
			var t := pass_tier_for(season, total)
			return Vector2i.ZERO if t >= season.tiers else Vector2i(total - season.xp_total_for(t), season.xp_for_tier(t + 1))
		var shown := after if after > int(d.get("tier_before", 0)) else mini(after + 1, season.tiers)
		var r := season.reward(shown, BattlePassSystem.FREE)
		if bp.premium:
			var rp := season.reward(shown, BattlePassSystem.PREMIUM)
			if not rp.is_empty():
				r = rp
		if not r.is_empty():
			var lbl := BattlePassSystem.reward_label(r)
			if after > int(d.get("tier_before", 0)):
				card.footer = "Palier %d : %s à récupérer" % [shown, lbl]
				card.footer_hot = true
			else:
				card.footer = "Palier %d : %s" % [shown, lbl]
	else:
		card.total_before = 0
		card.total_after = gain
		card.level_of = func(_t: int) -> int: return after
		card.progress_of = func(_t: int) -> Vector2i: return Vector2i.ZERO
	root.add_child(card)


## Palier du pass atteint avec `total` XP cumulée (même calcul que BattlePassSystem.tier()).
static func pass_tier_for(season: BattlePassSeason, total: int) -> int:
	var t := 0
	while t < season.tiers and total >= season.xp_total_for(t + 1):
		t += 1
	return t


## Détail de l'XP du raid (summary["pass_xp"]["breakdown"]) : une ligne compacte sous les cartes.
func _add_xp_breakdown(root: VBoxContainer) -> void:
	var px: Variant = summary.get("pass_xp")
	var lines: Variant = (px as Dictionary).get("breakdown", []) if px is Dictionary else []
	if not (lines is Array) or (lines as Array).is_empty():
		return
	var box := PanelContainer.new()
	box.name = "XpBreakdown"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_stylebox_override("panel", CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.45), 10.0, Color(0, 0, 0, 0), 0.0, 14.0, 8.0))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(grid)
	for e: Variant in lines:
		if not (e is Dictionary):
			continue
		var v := int((e as Dictionary).get("xp", 0))
		var k := MenuKit.label(str((e as Dictionary).get("label", "")), 14, Color(1, 1, 1, 0.75), MenuKit.nunito(700), 0)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(k)
		var val := MenuKit.label("%s%d XP" % ["+" if v >= 0 else "−", absi(v)], 16, MenuKit.TEXT if v >= 0 else DEATH, MenuKit.display(), 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
	root.add_child(box)


## Bilan du raid (summary["stats"] = {kills, time, floor, killer}, ajouté par Raid) : pastilles
## sous le verdict. Mort : « Tué par » d'abord ; extraction : survie et éliminations (la valeur et
## les gemmes ont leurs propres pastilles).
func _add_stats(root: VBoxContainer) -> void:
	var st: Variant = summary.get("stats")
	if not (st is Dictionary) or (st as Dictionary).is_empty():
		return
	var d: Dictionary = st
	var row := HBoxContainer.new()
	row.name = "RaidStats"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var killer := str(d.get("killer", ""))
	if not success:
		var kc := _stat_chip("Tué par", killer if not killer.is_empty() else "Inconnu", DEATH, 24)
		kc.name = "KillerChip"
		kc.custom_minimum_size.x = Balance.get_float("menu", "raid_end_killer_width", 250.0)
		row.add_child(kc)
	var secs := int(round(float(d.get("time", 0.0))))
	row.add_child(_stat_chip("Survie", "%d:%02d" % [secs / 60, secs % 60], Color(1, 1, 1, 0.55), 24))
	row.add_child(_stat_chip("Éliminations", str(int(d.get("kills", 0))), MenuKit.GOLD, 24))
	row.add_child(_stat_chip("Étage", floor_label(int(d.get("floor", 0))), Color(1, 1, 1, 0.3), 24))
	root.add_child(row)


## Libellé court d'un étage (0 = rez-de-chaussée, > 0 étages, < 0 sous-sols).
static func floor_label(f: int) -> String:
	if f == 0:
		return "RDC"
	return ("Étage %d" % f) if f > 0 else ("Sous-sol %d" % -f)


func _right_label(txt: String, px: int, color: Color) -> Label:
	var l := MenuKit.label(txt, px, color, MenuKit.nunito(600), 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


## Pastille de bilan (maquette Extract) : encre, liseré bas coloré, gros chiffre Anton, libellé.
func _stat_chip(label_text: String, value_text: String, color: Color, value_px: int = 33) -> Control:
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
	var val := MenuKit.label(value_text, value_px, MenuKit.TEXT, MenuKit.display(), 0)
	val.clip_text = true
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(val)
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


## Carte de progression du bandeau (pass de combat, niveau de raider) : encre biseautée, badge du
## palier/niveau, « +XP » qui défile, barre qui se remplit de total_before à total_after (plusieurs
## tours si des paliers/niveaux sont franchis : le badge monte, « NIVEAU SUPÉRIEUR » apparaît),
## XP dans le palier en cours, ligne de récompense. Animation : [menu] raid_end_xp_* (balance.cfg).
class XpCard extends PanelContainer:
	var kicker: String = ""
	## Unité du badge (« Niveau », « Palier »).
	var unit: String = "Niveau"
	var up_text: String = "Niveau supérieur"
	var gain: int = 0
	var total_before: int = 0
	var total_after: int = 0
	## total → niveau/palier ; total → Vector2i(XP dans le niveau, XP du niveau) ((0, 0) = maximum).
	var level_of: Callable
	var progress_of: Callable
	var footer: String = ""
	## Ligne de récompense mise en avant (déblocage ou récompense à récupérer).
	var footer_hot: bool = false
	## XP cumulée affichée (animée).
	var shown_total: float = 0.0:
		set(v):
			shown_total = v
			_refresh()

	var _badge_num: Label = null
	var _gain_lbl: Label = null
	var _bar: Control = null
	var _count_lbl: Label = null
	var _up_lbl: Label = null
	var _badge: Control = null
	var _level_shown: int = -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := CutBox.make(Color(MenuKit.NIGHT_DEEP, 0.74), 14.0, Color(0, 0, 0, 0), 0.0, 14.0, 12.0)
		add_theme_stylebox_override("panel", box)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 12)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(top)
		_badge = PanelContainer.new()
		_badge.custom_minimum_size = Vector2(58, 58)
		_badge.pivot_offset = Vector2(29, 29)
		_badge.add_theme_stylebox_override("panel", CutBox.make(MenuKit.VIOLET, 10.0, Color(0, 0, 0, 0), 0.0, 2.0, 2.0))
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(_badge)
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", -6)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.add_child(bv)
		var bu := MenuKit.label(unit.to_upper(), 10, Color(1, 1, 1, 0.8), MenuKit.nunito(800), 0)
		bu.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(bu)
		_badge_num = MenuKit.label("0", 30, MenuKit.TEXT, MenuKit.display(), 0)
		_badge_num.name = "LevelNumber"
		_badge_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bv.add_child(_badge_num)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -4)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(tv)
		var k := MenuKit.label(kicker.to_upper(), 14, Color(1, 1, 1, 0.7), MenuKit.nunito(700), 0)
		tv.add_child(k)
		_gain_lbl = MenuKit.label("+0 XP", 34, MenuKit.TEXT, MenuKit.display(), 0)
		_gain_lbl.name = "Gain"
		tv.add_child(_gain_lbl)
		_bar = Control.new()
		_bar.name = "Bar"
		_bar.custom_minimum_size = Vector2(0, 10)
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.draw.connect(_draw_bar)
		v.add_child(_bar)
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 8)
		crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(crow)
		_count_lbl = MenuKit.label("", 13, Color(1, 1, 1, 0.65), MenuKit.nunito(700), 0)
		_count_lbl.name = "Count"
		_count_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crow.add_child(_count_lbl)
		_up_lbl = MenuKit.label(up_text.to_upper(), 13, MenuKit.NIGHT_DEEP, MenuKit.nunito(800), 0)
		_up_lbl.name = "LevelUp"
		var up_box := PanelContainer.new()
		up_box.add_theme_stylebox_override("panel", CutBox.make(MenuKit.GOLD, 6.0, Color(0, 0, 0, 0), 0.0, 8.0, 2.0))
		up_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		up_box.add_child(_up_lbl)
		up_box.modulate.a = 0.0
		up_box.name = "LevelUpBox"
		crow.add_child(up_box)
		if not footer.is_empty():
			var f := MenuKit.label(footer, 14, MenuKit.GOLD if footer_hot else Color(1, 1, 1, 0.8), MenuKit.nunito(700), 0)
			f.name = "Footer"
			f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			f.max_lines_visible = 2
			v.add_child(f)
		shown_total = float(total_before)
		_animate()

	## Lance le remplissage après l'entrée de l'écran ; le gain défile en même temps.
	func _animate() -> void:
		var delay := Balance.get_float("menu", "raid_end_xp_delay", 0.45)
		var dur := Balance.get_float("menu", "raid_end_xp_duration", 1.3)
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "shown_total", float(total_after), dur).set_delay(delay)

	func _refresh() -> void:
		if _bar == null or not level_of.is_valid():
			return
		var t := roundi(shown_total)
		var lv: int = level_of.call(t)
		if _level_shown >= 0 and lv > _level_shown:
			_level_up()
		_level_shown = lv
		_badge_num.text = str(lv)
		var span := maxi(total_after - total_before, 1)
		_gain_lbl.text = "+%d XP" % roundi(float(gain) * clampf(float(t - total_before) / float(span), 0.0, 1.0))
		var pr: Vector2i = progress_of.call(t)
		_count_lbl.text = ("%d / %d XP" % [pr.x, pr.y]) if pr.y > 0 else "Maximum atteint"
		_bar.queue_redraw()

	func _level_up() -> void:
		var up := find_child("LevelUpBox", true, false) as Control
		var tw := create_tween().set_parallel(true)
		if up != null:
			up.pivot_offset = up.size * 0.5
			up.scale = Vector2(1.6, 1.6)
			tw.tween_property(up, "modulate:a", 1.0, 0.15)
			tw.tween_property(up, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_badge.scale = Vector2(1.35, 1.35)
		tw.tween_property(_badge, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# Lueur de la carte, puis retour au calme.
		var box := get_theme_stylebox("panel") as CutBox
		if box != null:
			box.border_color = MenuKit.GOLD
			box.border_width = 2.0
		modulate = Color(1.35, 1.25, 1.6)
		tw.tween_property(self, "modulate", Color.WHITE, 0.6)
		_burst()

	## Éclats dorés autour du badge (passage de palier / niveau).
	func _burst() -> void:
		var p := CPUParticles2D.new()
		p.position = _badge.position + _badge.size * 0.5 + Vector2(get_theme_stylebox("panel").content_margin_left,
			get_theme_stylebox("panel").content_margin_top)
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = int(Balance.get_value("menu", "raid_end_burst_amount", 26))
		p.lifetime = 0.7
		p.spread = 180.0
		p.initial_velocity_min = 160.0
		p.initial_velocity_max = 320.0
		p.gravity = Vector2(0, 380)
		p.scale_amount_min = 3.0
		p.scale_amount_max = 6.0
		p.color = MenuKit.GOLD
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1, 1, 1, 1))
		ramp.set_color(1, Color(1, 1, 1, 0))
		p.color_ramp = ramp
		p.emitting = true
		add_child(p)
		get_tree().create_timer(1.2, true).timeout.connect(p.queue_free)

	## Barre : fond, part déjà acquise avant le raid (dans le niveau affiché), part gagnée (vive).
	func _draw_bar() -> void:
		var r := Rect2(Vector2.ZERO, _bar.size)
		_bar.draw_rect(r, Color(1, 1, 1, 0.12))
		if not progress_of.is_valid():
			return
		var t := roundi(shown_total)
		var pr: Vector2i = progress_of.call(t)
		if pr.y <= 0:
			_bar.draw_rect(r, MenuKit.GOLD)
			return
		var ratio := clampf(float(pr.x) / float(pr.y), 0.0, 1.0)
		var base_ratio := 0.0
		if level_of.call(total_before) == level_of.call(t):
			var pb: Vector2i = progress_of.call(total_before)
			base_ratio = clampf(float(pb.x) / float(maxi(pb.y, 1)), 0.0, ratio)
		_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * ratio, r.size.y)), MenuKit.GOLD)
		if base_ratio > 0.0:
			_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * base_ratio, r.size.y)), Color(MenuKit.VIOLET, 0.9))
		_bar.draw_rect(Rect2(Vector2(r.size.x * ratio - 2.0, -2.0), Vector2(2.0, r.size.y + 4.0)), MenuKit.TEXT)
		# Lueur de pointe : halo derrière le curseur.
		_bar.draw_rect(Rect2(Vector2(r.size.x * ratio - 14.0, 0.0), Vector2(12.0, r.size.y)), Color(1, 1, 1, 0.35))

	## Niveau affiché (tests).
	func get_level_shown() -> int:
		return _level_shown

	func finish_animation() -> void:
		shown_total = float(total_after)
