class_name AffixBadges
extends RefCounted
## Affichage des affixes tirés d'un exemplaire d'arme (direction D, MenuKit) :
##  - `strip` : rangée de pastilles « BRÛLURE  GEL » (cartes d'arme, compact) ;
##  - `details` : une ligne par affixe, nom à la couleur de l'affixe + effet court (fiches).
## Rien n'est créé pour une arme sans affixe (strip/details renvoient un conteneur vide).


## Pastilles compactes (nom en capitales, liseré et texte à la couleur de l'affixe).
static func strip(ids: Array, font_size: int = 12, centered: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "AffixStrip"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	if centered:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	for a: AffixData in Affixes.resolve(ids):
		var p := MenuKit.pill(a.display_name.to_upper(), Color(MenuKit.NIGHT_DEEP, 0.88), font_size,
			a.color, Color(a.color, 0.7))
		var st := p.get_theme_stylebox("panel") as StyleBoxFlat
		st.content_margin_left = 6
		st.content_margin_right = 6
		st.content_margin_top = 1
		st.content_margin_bottom = 1
		p.set_meta(&"affix_id", a.id)
		row.add_child(p)
	return row


## Version compacte (bandeau de l'arsenal de départ, peu de hauteur) : un texte par affixe,
## « BRÛLURE  effet » sur la même ligne (retour à la ligne si besoin), nom à la couleur de l'affixe.
static func compact(ids: Array, font_size: int = 14) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "AffixDetails"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	for a: AffixData in Affixes.resolve(ids):
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.scroll_active = false
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_theme_font_override("normal_font", MenuKit.nunito(600))
		r.add_theme_font_override("bold_font", MenuKit.nunito(800))
		r.add_theme_font_size_override("normal_font_size", font_size)
		r.add_theme_font_size_override("bold_font_size", font_size)
		r.add_theme_color_override("default_color", MenuKit.TEXT_DIM)
		r.text = "[b][color=#%s]%s[/color][/b]  %s" % [a.color.to_html(false), a.display_name.to_upper(), a.effect_text()]
		r.set_meta(&"affix_id", a.id)
		col.add_child(r)
	return col


## Lignes détaillées : « Brûlure » (couleur de l'affixe) puis l'effet (texte secondaire).
static func details(ids: Array, font_size: int = 15) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "AffixDetails"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	for a: AffixData in Affixes.resolve(ids):
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var mark := ColorRect.new()
		mark.color = a.color
		mark.custom_minimum_size = Vector2(4, 0)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)
		var txt := VBoxContainer.new()
		txt.add_theme_constant_override("separation", -2)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(txt)
		var nm := MenuKit.label(a.display_name.to_upper(), font_size, a.color, MenuKit.nunito(800))
		txt.add_child(nm)
		var ef := MenuKit.label(a.effect_text(), font_size - 1, MenuKit.TEXT_DIM, MenuKit.nunito(600))
		ef.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.add_child(ef)
		row.set_meta(&"affix_id", a.id)
		col.add_child(row)
	return col
