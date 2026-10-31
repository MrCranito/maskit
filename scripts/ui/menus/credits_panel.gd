class_name CreditsPanel
extends ModalPanel
## Crédits : reprend CREDITS.md. L'attribution game-icons.net (CC BY 3.0) est
## OBLIGATOIRE et affichée en premier.

## Attribution obligatoire (texte exact de CREDITS.md, section « Attribution à afficher »).
const ICONS_ATTRIBUTION := "Icons made by Lorc, Delapouite, Skoll, Sbed, Carl Olsen, John Colburn, Guard13007 and Willdabeast, from game-icons.net — licensed under CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/). Icons modified (background removed)."
const FONTS_ATTRIBUTION := "« Rye » © 2011 Sorkin Type Co ; « Nunito » © 2014 The Nunito Project Authors — SIL Open Font License 1.1."
const AUDIO_ATTRIBUTION := "Pixel-boy / Sparklin Labs (Superpowers Asset Packs, CC0) ; Kenney (www.kenney.nl, CC0)."

var text_label: RichTextLabel = null


func _init() -> void:
	super._init("Crédits", Vector2(820, 600))


func _build_body() -> void:
	var scroll := ScrollContainer.new()
	MenuKit.make_touch_scroll(scroll)   # glisser au doigt partout (même sur les boutons)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	body.add_child(scroll)
	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = true
	text_label.fit_content = true
	text_label.scroll_active = false
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_override("normal_font", MenuKit.nunito(600))
	text_label.add_theme_font_override("bold_font", MenuKit.nunito(900))
	text_label.add_theme_font_size_override("normal_font_size", 20)
	text_label.add_theme_font_size_override("bold_font_size", 22)
	text_label.add_theme_color_override("default_color", MenuKit.TEXT_DIM)
	text_label.text = build_text()
	text_label.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	scroll.add_child(text_label)


static func build_text() -> String:
	var gold: String = MenuKit.GOLD.to_html(false)
	var t := ""
	t += "[center][b][color=#%s]RaidersGo[/color][/b][/center]\n\n" % gold
	t += "[b][color=#ffffff]Icônes[/color][/b]\n" + ICONS_ATTRIBUTION.replace(
		"https://creativecommons.org/licenses/by/3.0/",
		"[url=https://creativecommons.org/licenses/by/3.0/]https://creativecommons.org/licenses/by/3.0/[/url]") + "\n\n"
	t += "[b][color=#ffffff]Polices[/color][/b]\n" + FONTS_ATTRIBUTION + "\n\n"
	t += "[b][color=#ffffff]Sons et musiques[/color][/b]\n" + AUDIO_ATTRIBUTION + "\n"
	t += "Musiques western : Superpowers « western-fps-2d » (Pixel-boy). Effets d'interface : Kenney Interface Sounds / UI Audio. Sons additionnels : Kenney Starter Kits (FPS, 3D Platformer, Racing, Match-3).\n\n"
	t += "[b][color=#ffffff]Moteur[/color][/b]\nGodot Engine (licence MIT) — godotengine.org/license\n\n"
	t += "[color=#8a90a0]Détail complet des sources et licences : fichier CREDITS.md.[/color]"
	return t
