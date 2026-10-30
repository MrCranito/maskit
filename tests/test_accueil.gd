extends GutTest
## Accueil (menu principal), retours de Victor : carte du pass (hiérarchie, XP x / y, icône de la
## prochaine récompense, pastille qui pulse), compteurs or / gemmes + « + » + réglages (alignés,
## même hauteur, « ∞ » lisible), infobulles coupées sur écran tactile, bandeau réservé à DÉPLOYER,
## interrupteur En ligne / Hors ligne, « + Coéquipier » réduit. Mises en page vérifiées en
## 1280 × 720, 2000 × 923 (viewport 1560 × 720) et 2400 × 1080 (1600 × 720), avec et sans encoche.

const VIEWPORTS: Array[Vector2] = [Vector2(1280, 720), Vector2(1560, 720), Vector2(1600, 720)]
## Encoche simulée (px du viewport en headless) : gauche, haut, droite, bas.
const NOTCH := Vector4(70, 0, 70, 30)

var _saved_data: Dictionary = {}
var _saved_profile: Dictionary = {}
var _saved_pass: Dictionary = {}
var _saved_insets: Vector4
var _saved_dev: bool = false


func before_each() -> void:
	_saved_data = SaveManager.data.duplicate(true)
	_saved_profile = Profile.to_dict()
	_saved_pass = BattlePassSystem.get_instance().to_dict()
	_saved_insets = HudSafeArea.debug_insets
	_saved_dev = DevMode.is_unlimited()
	var old := NetSession.current()
	if old != null:
		old.free()


func after_each() -> void:
	HudSafeArea.debug_insets = _saved_insets
	MenuKit.touch_ui_override = -1
	var tree := get_tree()
	if tree.node_added.is_connected(MenuKit._strip_tooltip):
		tree.node_added.disconnect(MenuKit._strip_tooltip)
	DevMode.set_unlimited(_saved_dev)
	Profile.from_dict(_saved_profile)
	BattlePassSystem.get_instance().from_dict(_saved_pass)
	SaveManager.data = _saved_data
	SaveManager.save()
	var s := NetSession.current()
	if s != null:
		s.status = NetSession.Status.OFFLINE
		s.free()


func _menu(vp: Vector2 = Vector2(1280, 720)) -> MainMenu:
	var m := (load(MenuKit.MAIN_MENU_SCENE) as PackedScene).instantiate() as MainMenu
	add_child_autofree(m)
	await wait_process_frames(2)
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.size = vp
	await wait_seconds(1.1)   # fin des animations d'entrée
	return m


## Le texte tient-il dans le label (pas de débordement ni de troncature) ?
func _fits(l: Label) -> bool:
	if not l.is_visible_in_tree() or l.text.is_empty():
		return true
	var f := l.get_theme_font("font")
	var fs := l.get_theme_font_size("font_size")
	var txt := l.text.to_upper() if l.uppercase else l.text
	return f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= l.size.x + 1.0


func _rect(c: Control) -> Rect2:
	return c.get_global_rect()


# --- Carte du pass ----------------------------------------------------------------------

func _pass_card(tier: int) -> PassCard:
	var bp := BattlePassSystem.get_instance()
	var s := bp.get_season()
	bp.from_dict({"xp": s.xp_total_for(tier) + s.xp_for_tier(tier + 1) / 2})
	var c := PassCard.new()
	add_child_autofree(c)
	c.position = Vector2(40, 40)
	await wait_process_frames(3)
	return c


func test_pass_card_hierarchy_and_xp() -> void:
	var c := await _pass_card(6)
	var bp := BattlePassSystem.get_instance()
	var prog := bp.tier_progress()
	assert_eq(c.tier_label.text, "PALIER 6")
	assert_eq(c.tier_max_label.text, "/ %d" % bp.max_tier())
	assert_eq(c.xp_label.text, PassCard.xp_text(prog), "Légende de la barre : XP x / y")
	assert_string_ends_with(c.xp_label.text, " XP")
	assert_almost_eq(c.xp_bar.value / c.xp_bar.max_value, float(prog.x) / float(prog.y), 0.001)
	# Prochaine récompense : vignette (RewardIcon) + palier + valeur
	assert_true(c.next_icon.visible, "Icône de la récompense suivante")
	assert_false(c.next_icon.reward.is_empty())
	assert_eq(c.next_label.text, "Palier 7")
	assert_eq(c.next_value.text, BattlePassSystem.reward_label(c.next_icon.reward))
	# Hiérarchie : en-tête au-dessus du palier, barre sous le palier, légende sous la barre
	assert_lt(_rect(c.title_label).end.y, _rect(c.tier_label).position.y + 2.0)
	assert_lt(_rect(c.tier_label).end.y, _rect(c.xp_bar).position.y + 2.0)
	assert_lte(_rect(c.xp_bar).end.y, _rect(c.xp_label).position.y + 1.0)
	# La récompense est à droite de la progression, sans chevauchement
	assert_gte(_rect(c.next_tile).position.x, _rect(c.xp_bar).end.x)
	assert_false(_rect(c.next_tile).intersects(_rect(c.tier_label)))
	assert_false(_rect(c.claim_pill).intersects(_rect(c.title_label)), "Pastille à côté du titre")


func test_pass_card_texts_fit_and_stay_inside() -> void:
	for tier: int in [0, 6, 29]:
		var c := await _pass_card(tier)
		var card := _rect(c)
		for l: Label in [c.title_label, c.tier_label, c.tier_max_label, c.xp_label, c.next_label, c.next_value,
				c.claim_pill.get_node("Text") as Label]:
			if not l.is_visible_in_tree():
				continue
			assert_true(_fits(l), "Texte entier (palier %d) : « %s »" % [tier, l.text])
			assert_true(card.encloses(_rect(l)), "Dans la carte (palier %d) : « %s »" % [tier, l.text])
		assert_true(card.encloses(_rect(c.next_tile)), "Vignette dans la carte")
		assert_true(card.encloses(_rect(c.claim_pill)) or not c.claim_pill.visible, "Pastille dans la carte")
		c.queue_free()
		await wait_process_frames(1)


func test_pass_card_finished_pass() -> void:
	var bp := BattlePassSystem.get_instance()
	bp.from_dict({"xp": bp.get_season().xp_total_for(bp.max_tier())})
	var c := PassCard.new()
	add_child_autofree(c)
	await wait_process_frames(2)
	assert_eq(c.next_label.text, "Pass terminé")
	assert_eq(c.xp_label.text, "Pass terminé")
	assert_false(c.next_icon.visible)


func test_claim_pill_pulses_in_violet() -> void:
	var c := await _pass_card(6)
	assert_true(c.claim_pill.visible, "Des récompenses à récupérer")
	var box := c.claim_pill.get_theme_stylebox("panel") as CutBox
	assert_not_null(box)
	assert_eq(box.bg_color, MenuKit.VIOLET, "Violet de l'action principale, plus de rouge criard")
	var halo := c.claim_pill.get_node("Halo") as Control
	var a0 := halo.modulate.a
	await wait_seconds(0.4)
	assert_ne(halo.modulate.a, a0, "Le halo pulse")
	BattlePassSystem.get_instance().claim_all()
	await wait_process_frames(2)
	assert_false(c.claim_pill.visible)
	assert_eq(halo.modulate.a, 0.0, "Pulsation arrêtée sans récompense")


# --- Monnaies -------------------------------------------------------------------------------

func test_wallet_aligned_same_height_no_overlap() -> void:
	Profile.from_dict({"gems": 1250, "gold": 98765})
	DevMode.set_unlimited(false)
	var m := await _menu()
	var w := m.wallet
	assert_not_null(w)
	var blocks: Array[Control] = [w.gold_counter, w.gem_counter, w.gem_plus, w.gear_button]
	var h := _rect(w.gold_counter).size.y
	for b: Control in blocks:
		assert_almost_eq(_rect(b).size.y, h, 0.5, "Même hauteur : " + String(b.name))
		assert_almost_eq(_rect(b).position.y, _rect(w.gold_counter).position.y, 0.5, "Alignés en haut : " + String(b.name))
	for i: int in blocks.size() - 1:
		assert_lte(_rect(blocks[i]).end.x, _rect(blocks[i + 1]).position.x + 0.5, "Pas de chevauchement")
	assert_almost_eq(_rect(w.gem_plus).position.x, _rect(w.gem_counter).end.x, 0.5, "« + » collé aux gemmes")
	var gap_pills := _rect(w.gem_counter).position.x - _rect(w.gold_counter).end.x
	var gap_gear := _rect(w.gear_button).position.x - _rect(w.gem_plus).end.x
	assert_gt(gap_gear, gap_pills, "Réglages détachés des monnaies")
	assert_eq(m.gold_label.text, Economy.fmt(98765))
	assert_eq(m.gem_counter.value_label.text, Economy.fmt(1250))
	assert_true(_fits(m.gold_label), "Or lisible en entier")
	assert_true(_fits(m.gem_counter.value_label), "Gemmes lisibles en entier")
	assert_gte(w.gem_plus.size.x, 48.0, "« + » : cible tactile")
	assert_gte(w.gear_button.size.x, 48.0, "Réglages : cible tactile")


func test_wallet_unlimited_symbol_is_readable() -> void:
	DevMode.set_unlimited(true)
	if not DevMode.is_unlimited():
		pass_test("Mode développeur indisponible dans ce build")
		return
	var m := await _menu()
	for l: Label in [m.gold_label, m.gem_counter.value_label]:
		assert_eq(l.text, DevMode.SYMBOL)
		assert_gt(l.get_theme_font_size("font_size"), int(l.get_meta(&"base_size")), "« ∞ » plus grand que le chiffre")
		assert_eq(l.get_theme_color("font_color"), MenuKit.GOLD, "« ∞ » en violet clair")
		assert_true(_fits(l))
	DevMode.set_unlimited(false)
	await wait_process_frames(1)
	for l: Label in [m.gold_label, m.gem_counter.value_label]:
		assert_ne(l.text, DevMode.SYMBOL, "Vrai solde à la sortie du mode")
		assert_eq(l.get_theme_font_size("font_size"), int(l.get_meta(&"base_size")))
		assert_eq(l.get_theme_color("font_color"), MenuKit.TEXT)


func test_shared_counters_use_same_unlimited_style() -> void:
	# Cohérence avec la boutique, le pass et l'arsenal : mêmes composants, même rendu du « ∞ ».
	DevMode.set_unlimited(true)
	if not DevMode.is_unlimited():
		pass_test("Mode développeur indisponible dans ce build")
		return
	var g := GoldCounter.new()
	var gm := GemCounter.new()
	add_child_autofree(g)
	add_child_autofree(gm)
	await wait_process_frames(1)
	for l: Label in [g.value_label, gm.value_label]:
		assert_eq(l.text, DevMode.SYMBOL)
		assert_eq(l.get_theme_color("font_color"), MenuKit.GOLD)


# --- Infobulle « Réglages » -----------------------------------------------------------------

func test_no_tooltips_on_touch_screens() -> void:
	MenuKit.touch_ui_override = 1
	MenuKit.install_touch_tooltip_guard()
	var m := await _menu()
	assert_eq(m.gear_button.tooltip_text, "", "Pas d'infobulle « Réglages » sur téléphone")
	var tips := m.find_children("*", "Control", true, false).filter(
		func(c: Node) -> bool: return not (c as Control).tooltip_text.is_empty())
	assert_eq(tips.size(), 0, "Aucune infobulle sur l'accueil tactile")
	var b := Button.new()
	b.tooltip_text = "Test"
	add_child_autofree(b)
	assert_eq(b.tooltip_text, "", "Contrôles créés ensuite : infobulle retirée à l'entrée dans l'arbre")


func test_tooltips_kept_with_mouse() -> void:
	MenuKit.touch_ui_override = 0
	MenuKit.install_touch_tooltip_guard()
	var m := await _menu()
	assert_eq(m.gear_button.tooltip_text, "Réglages", "PC : infobulle conservée")


# --- Mises en page (3 résolutions, avec et sans encoche) ------------------------------------

func test_home_layout_all_viewports() -> void:
	for notch: bool in [false, true]:
		HudSafeArea.debug_insets = NOTCH if notch else Vector4(-1, -1, -1, -1)
		for vp: Vector2 in VIEWPORTS:
			var m := await _menu(vp)
			var tag := "%dx%d%s" % [vp.x, vp.y, " encoche" if notch else ""]
			var screen := Rect2(Vector2.ZERO, vp)
			var safe: Vector4 = MenuKit.safe_margins(m)
			var pc := _rect(m.pass_card)
			var nav := _rect(m.get("_nav") as Control)
			var slab := _rect(m.get("slab") as Control)
			var wallet := _rect(m.wallet)
			var logo := _rect(m.logo)
			var play := _rect(m.play_button)
			var sw := _rect(m.online_switch)
			assert_true(screen.encloses(pc), "Pass dans l'écran " + tag)
			assert_gte(pc.position.x, safe.x - 0.5, "Pass hors de l'encoche " + tag)
			assert_lte(pc.end.y, vp.y - safe.w + 0.5, "Pass au-dessus de la barre d'accueil " + tag)
			assert_false(pc.intersects(nav), "Pass sous le menu " + tag)
			assert_false(pc.intersects(slab), "Pass pas sous le bandeau " + tag)
			assert_true(screen.encloses(wallet), "Monnaies dans l'écran " + tag)
			assert_false(wallet.intersects(slab), "Monnaies avant le bandeau " + tag)
			assert_false(wallet.intersects(logo), "Monnaies pas sur le logo " + tag)
			assert_true(slab.encloses(play), "DÉPLOYER dans le bandeau " + tag)
			assert_true(slab.encloses(sw), "Interrupteur dans le bandeau " + tag)
			assert_lte(sw.end.x, vp.x - safe.z + 0.5, "Interrupteur hors de l'encoche " + tag)
			assert_lte(sw.end.y, vp.y - safe.w + 0.5, "Interrupteur au-dessus de la barre d'accueil " + tag)
			assert_false(sw.intersects(play), "Interrupteur sous DÉPLOYER " + tag)
			assert_gte(sw.position.y - play.end.y, Balance.get_float("menu", "lobby_deploy_switch_gap", 9.0),
				"Espace net entre DÉPLOYER et l'interrupteur " + tag)
			assert_gte(play.position.y, _rect(m.wallet).end.y, "DÉPLOYER reste sous la barre du haut " + tag)
			for l: Label in [m.pass_card.tier_label, m.pass_card.xp_label, m.pass_card.next_value, m.gold_label]:
				assert_true(_fits(l), "Texte entier %s : « %s »" % [tag, l.text])
			for b: Button in [m.online_switch.online_button, m.online_switch.offline_button]:
				assert_gte(b.size.y, 36.0, "Segment tactile " + tag)
			m.queue_free()
			await wait_process_frames(1)


# --- Bandeau DÉPLOYER, coéquipier ------------------------------------------------------------

func test_slab_only_deploy_and_coop_paths_kept() -> void:
	var m := await _menu()
	assert_eq(MainMenu.button_label(m.play_button), "DÉPLOYER")
	var src := FileAccess.get_file_as_string("res://scripts/ui/menus/main_menu.gd")
	assert_string_contains(src, "MenuKit.go_to(self, MenuKit.MAP_SELECT_SCENE)", "Solo : DÉPLOYER → choix de la carte")
	assert_string_contains(src, "MenuKit.go_to(self, MenuKit.COOP_SCENE)", "Salon ouvert : DÉPLOYER → salon coop")
	assert_true(m.mate_plus.visible, "La coop reste accessible par « + Coéquipier »")
	assert_gt(m.mate_plus.pressed.get_connections().size(), 0)


# --- En ligne / Hors ligne -------------------------------------------------------------------

func test_online_switch_persists_setting() -> void:
	OnlineMode.set_online(true)
	var m := await _menu()
	var sw := m.online_switch
	assert_true(sw.online_button.button_pressed, "En ligne par défaut")
	assert_false(sw.offline_button.button_pressed)
	sw.offline_button.pressed.emit()
	assert_false(OnlineMode.is_online(), "Hors ligne choisi")
	assert_false(bool((SaveManager.data["settings"] as Dictionary)[String(OnlineMode.SETTING)]), "Mémorisé dans les réglages du profil")
	assert_true(sw.offline_button.button_pressed, "Pastille violette sur Hors ligne")
	sw.online_button.pressed.emit()
	assert_true(OnlineMode.is_online())
	assert_true(sw.online_button.button_pressed)


func test_offline_greys_teammate_and_blocks_coop() -> void:
	OnlineMode.set_online(false)
	var m := await _menu()
	assert_lt(m.mate_plus.modulate.a, 0.6, "« + Coéquipier » grisé hors ligne")
	assert_eq((m.get("_mate_caption") as Label).text, "Hors ligne")
	m.set_meta(&"_leaving", false)
	m.mate_plus.pressed.emit()
	await wait_process_frames(1)
	assert_true(m.info_banner.visible, "Message affiché au tap")
	assert_eq(m.info_banner.text_label.text, MainMenu.OFFLINE_COOP_HINT)
	assert_false(bool(m.get_meta(&"_leaving", false)), "Pas de départ vers le salon coop")
	assert_null(NetSession.current(), "Aucune session réseau créée hors ligne")
	OnlineMode.set_online(true)
	await wait_process_frames(1)
	assert_eq(m.mate_plus.modulate.a, 1.0, "Retour en ligne : « + » normal")
	assert_eq((m.get("_mate_caption") as Label).text, "Coéquipier")


func test_offline_pauses_cloud_sync() -> void:
	var cs: Node = get_node_or_null(^"/root/CloudSync")
	assert_not_null(cs)
	if cs == null:
		return
	OnlineMode.set_online(false)
	assert_true(bool(cs.call("paused_by_player")), "Hors ligne : CloudSync en pause")
	assert_string_contains(str(cs.call("status_label", &"offline")), "Mode hors ligne")
	OnlineMode.set_online(true)
	assert_false(bool(cs.call("paused_by_player")))
	assert_eq(str(cs.call("status_label", &"offline")), "Hors ligne : sauvegarde locale")


func test_switch_locked_online_in_coop_room() -> void:
	OnlineMode.set_online(true)
	var s := NetSession.new()
	s.name = NetSession.NODE_NAME
	get_tree().root.add_child(s)
	s.status = NetSession.Status.IN_ROOM
	var m := await _menu()
	assert_true(m.online_switch.locked, "Salon coop ouvert : interrupteur verrouillé en ligne")
	m.online_switch.offline_button.pressed.emit()
	assert_true(OnlineMode.is_online(), "Refus de passer hors ligne dans un salon")
	assert_true(m.online_switch.online_button.button_pressed)
