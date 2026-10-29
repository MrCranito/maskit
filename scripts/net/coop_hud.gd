class_name CoopHud
extends CanvasLayer
## Interface du raid coop (au-dessus du HUD du raid) :
##  - carte du coéquipier (haut gauche, sous la barre de vie) : pseudo, statut, PV, ping ;
##  - bandeau central : attente du coéquipier, compte à rebours d'étage, reconnexion ;
##  - « À TERRE » (voile rouge + temps restant + progression de la réanimation) ;
##  - barre spectateur (bas) avec « Quitter » ; panneau « hôte déconnecté ».
## Textes mis à jour seulement quand ils changent (aucun redessin par image), debug F3 à 2 Hz.

const RED := Color(0.9, 0.22, 0.2)

var coop: CoopRaid = null

var _card: PanelContainer = null
var _card_name: Label = null
var _card_status: Label = null
var _card_bar: ProgressBar = null
var _card_fill: StyleBoxFlat = null
var _center: PanelContainer = null
var _center_label: Label = null
var _downed: Control = null
var _downed_label: Label = null
var _downed_sub: Label = null
var _downed_bar: ProgressBar = null
var _spectator: PanelContainer = null
var _spectator_label: Label = null
var _debug: Label = null
var _wait_text: String = ""
var _countdown_text: String = ""
var _conn_text: String = ""
var _debug_left: float = 0.0
var _last_downed_s: int = -1


func setup(c: CoopRaid) -> void:
	coop = c


func _ready() -> void:
	layer = 12
	name = "CoopHud"
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_card(root)
	_build_center(root)
	_build_downed(root)
	_build_spectator(root)
	_debug = MenuKit.label("", 13, MenuKit.TEXT_DIM)
	_debug.position = Vector2(16, 690)
	_debug.visible = false
	root.add_child(_debug)
	refresh_partner()


func _style(bg: Color = MenuKit.NIGHT_PANEL, radius: int = 14, margin: int = 10) -> StyleBoxFlat:
	return MenuKit.panel_style(bg, MenuKit.BORDER, radius, 1, margin)


func _build_card(root: Control) -> void:
	_card = PanelContainer.new()
	_card.name = "PartnerCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", _style(Color(0.071, 0.102, 0.18, 0.88), 12, 8))
	var m := maxf(Balance.get_float("hud", "margin", 16.0), HudSafeArea.margins(self).x)
	_card.position = Vector2(m, Balance.get_float("net", "hud_card_top", 74.0))
	root.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	_card_name = MenuKit.label("", 16, CoopAvatar.NAME_COLOR, MenuKit.nunito(900))
	row.add_child(_card_name)
	_card_status = MenuKit.label("", 14, MenuKit.TEXT_DIM)
	row.add_child(_card_status)
	_card_bar = ProgressBar.new()
	_card_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_bar.custom_minimum_size = Vector2(200, 10)
	_card_bar.show_percentage = false
	_card_bar.max_value = 1.0
	_card_bar.value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.05, 0.07, 0.9)
	bg.set_corner_radius_all(4)
	_card_fill = StyleBoxFlat.new()
	_card_fill.bg_color = Color(0.35, 0.85, 0.5)
	_card_fill.set_corner_radius_all(4)
	_card_bar.add_theme_stylebox_override("background", bg)
	_card_bar.add_theme_stylebox_override("fill", _card_fill)
	v.add_child(_card_bar)


func _build_center(root: Control) -> void:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.anchor_left = 0.0
	cc.anchor_right = 1.0
	cc.anchor_top = 0.2
	cc.anchor_bottom = 0.2
	cc.offset_bottom = 60
	root.add_child(cc)
	_center = PanelContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.add_theme_stylebox_override("panel", _style(MenuKit.NIGHT_PANEL, 14, 12))
	_center.visible = false
	cc.add_child(_center)
	_center_label = MenuKit.label("", 24, MenuKit.TEXT, MenuKit.nunito(900), 4)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.add_child(_center_label)


func _build_downed(root: Control) -> void:
	_downed = Control.new()
	_downed.name = "Downed"
	_downed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_downed.visible = false
	root.add_child(_downed)
	var veil := ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.color = Color(0.45, 0.02, 0.04, 0.28)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_downed.add_child(veil)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_downed.add_child(cc)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", MenuKit.panel_style(MenuKit.NIGHT_PANEL, Color(RED, 0.8), 18, 2, 18))
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	_downed_label = MenuKit.title("À TERRE", 44, Color(1.0, 0.42, 0.38))
	_downed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_downed_label)
	_downed_sub = MenuKit.label("", 20, MenuKit.TEXT)
	_downed_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_downed_sub)
	_downed_bar = ProgressBar.new()
	_downed_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_bar.custom_minimum_size = Vector2(320, 14)
	_downed_bar.show_percentage = false
	_downed_bar.max_value = 1.0
	_downed_bar.visible = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.45, 1.0, 0.55)
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.08, 0.14, 0.9)
	bg.set_corner_radius_all(6)
	_downed_bar.add_theme_stylebox_override("fill", fill)
	_downed_bar.add_theme_stylebox_override("background", bg)
	v.add_child(_downed_bar)


func _build_spectator(root: Control) -> void:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.anchor_left = 0.0
	cc.anchor_right = 1.0
	cc.anchor_top = 1.0
	cc.anchor_bottom = 1.0
	cc.offset_top = -120
	cc.offset_bottom = -20
	root.add_child(cc)
	_spectator = PanelContainer.new()
	_spectator.add_theme_stylebox_override("panel", _style(MenuKit.NIGHT_PANEL, 16, 12))
	_spectator.visible = false
	cc.add_child(_spectator)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_spectator.add_child(row)
	_spectator_label = MenuKit.label("", 20, MenuKit.TEXT, MenuKit.nunito(800))
	_spectator_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_spectator_label)
	var quit := MenuKit.button("Quitter", MenuKit.Style.PRIMARY, 22, Vector2(180, 60))
	quit.name = "QuitSpectator"
	quit.pressed.connect(func() -> void:
		MenuKit.sfx(&"confirm")
		if coop != null:
			coop.quit_spectating())
	row.add_child(quit)


# --- API ------------------------------------------------------------------------------

func show_wait(on: bool) -> void:
	_wait_text = ("En attente de %s…" % coop.partner_name) if on and coop != null else ""
	_refresh_center()


func set_countdown(text: String) -> void:
	if text == _countdown_text:
		return
	_countdown_text = text
	_refresh_center()


func set_connection_text(text: String) -> void:
	_conn_text = text
	_refresh_center()


func _refresh_center() -> void:
	var t := _conn_text if _conn_text != "" else (_countdown_text if _countdown_text != "" else _wait_text)
	_center.visible = t != ""
	if _center_label.text != t:
		_center_label.text = t


func show_downed(on: bool) -> void:
	_downed.visible = on
	_last_downed_s = -1
	if on:
		_downed_bar.visible = false
		_downed_sub.text = "%s peut te relever" % coop.partner_name if coop != null else ""


func set_downed_time(left: float) -> void:
	var s := ceili(left)
	if s == _last_downed_s:
		return
	_last_downed_s = s
	_downed_label.text = "À TERRE — %d s" % s


func set_revive_progress(v: float) -> void:
	_downed_bar.visible = v >= 0.0 and _downed.visible
	if v >= 0.0:
		_downed_bar.value = v
		_downed_sub.text = "%s te relève…" % coop.partner_name
	elif _downed.visible:
		_downed_sub.text = "%s peut te relever" % coop.partner_name


func set_partner_hp(ratio: float) -> void:
	if absf(_card_bar.value - ratio) > 0.004:
		_card_bar.value = ratio
		_card_fill.bg_color = Color(0.35, 0.85, 0.5) if ratio > 0.35 else RED


func refresh_partner() -> void:
	if coop == null or _card_name == null:
		return
	_card_name.text = coop.partner_name
	var st := CoopRules.status_text(coop.partner_status)
	if not coop.partner_connected and CoopRules.in_raid(coop.partner_status):
		st = CoopRules.status_text(CoopRules.Status.DISCONNECTED)
	_card_status.text = st
	_card_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45) if coop.partner_status == CoopRules.Status.DOWNED else MenuKit.TEXT_DIM)


func show_spectator(on: bool) -> void:
	_spectator.visible = on
	if on and coop != null:
		_spectator_label.text = "Spectateur — tu regardes %s" % coop.partner_name
		var quit := _spectator.find_child("QuitSpectator", true, false) as Button
		if quit != null:
			quit.text = "Quitter" if not coop.is_host else "Quitter (fin du raid de %s)" % coop.partner_name
			quit.custom_minimum_size.x = 180 if not coop.is_host else 420


## Invité : l'hôte a disparu → fin du raid, arsenal conservé, butin perdu.
func show_host_lost(summary: Dictionary) -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color(MenuKit.NIGHT_DEEP, 0.75)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_node("Root").add_child(veil)
	get_node("Root").add_child(cc)
	var p := MenuKit.panel(MenuKit.NIGHT_PANEL, 20, 28)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var t := MenuKit.title("Hôte déconnecté", 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var kept: Array = summary.get("kept_weapons", [])
	var lines := "Le raid est terminé : %s a quitté la partie.\nTon arsenal emporté est conservé (%d arme%s)." % [
		coop.partner_name if coop != null else "l'hôte", kept.size(), "s" if kept.size() > 1 else ""]
	if int(summary.get("lost_items", 0)) > 0:
		lines += "\nLe butin du raid est perdu (%d objet%s)." % [int(summary["lost_items"]), "s" if int(summary["lost_items"]) > 1 else ""]
	var l := MenuKit.label(lines, 20, MenuKit.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var b := MenuKit.button("Menu principal", MenuKit.Style.PRIMARY, 26, Vector2(320, 72))
	b.name = "HostLostMenu"
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		get_tree().paused = false
		MenuKit.go_to(self, MenuKit.MAIN_MENU_SCENE))
	v.add_child(b)
	b.grab_focus.call_deferred()


func tick(delta: float) -> void:
	_debug_left -= delta
	if _debug_left > 0.0:
		return
	_debug_left = 0.5
	var on := GameState.debug_enabled
	_debug.visible = on
	if on and coop != null:
		_debug.text = coop.get_debug_text()
	refresh_partner()
