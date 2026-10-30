extends GutTest
## Menus de RaidersGo : les scènes s'instancient, menu principal (boutons, options), plus de
## masques, arsenal de départ (vide = bouton désactivé, validation → Profile + raid), arsenal
## en consultation (skins), boutique (achat avec/sans gemmes, équiper, pack simulé), skins
## d'armes (shader), pause (abandon avec confirmation). La sauvegarde est isolée.

const SCENES := [
	"res://scenes/ui/menus/splash.tscn",
	"res://scenes/ui/menus/main_menu.tscn",
	"res://scenes/ui/menus/pause_menu.tscn",
	"res://scenes/ui/menus/map_select.tscn",
	"res://scenes/ui/menus/loadout.tscn",
	"res://scenes/ui/menus/arsenal.tscn",
	"res://scenes/ui/menus/shop.tscn",
	"res://scenes/ui/menus/battle_pass.tscn",
]

var _saved_data: Dictionary = {}
var _saved_profile: Dictionary = {}
var _saved_diff: int = 1
var _saved_map: Resource = null
var _saved_world: String = ""
var _saved_weapons: Array[WeaponData] = []
var _saved_pass: Dictionary = {}


func before_each() -> void:
	_saved_data = SaveManager.data.duplicate(true)
	_saved_profile = Profile.to_dict()
	_saved_diff = GameState.difficulty
	_saved_map = GameState.current_map
	_saved_world = GameState.world_path
	_saved_weapons = GameState.raid_weapons.duplicate()
	_saved_pass = BattlePassSystem.get_instance().to_dict()


func after_each() -> void:
	get_tree().paused = false
	Profile.from_dict(_saved_profile)
	GameState.difficulty = _saved_diff
	GameState.current_map = _saved_map
	GameState.world_path = _saved_world
	GameState.raid_weapons = _saved_weapons
	BattlePassSystem.get_instance().from_dict(_saved_pass)
	SaveManager.data = _saved_data
	SaveManager.save()
	ShopScreen.last_tab = &"character"
	ShopScreen.focus_skin_id = &""
	BattlePassScreen.focus_skin_id = &""
	WeaponSkin.enabled_override = -1


## Profil de test : quelques armes (dont un doublon) et un équipement, gemmes données.
func _test_profile(gems: int = 0) -> void:
	Profile.from_dict({"gems": gems})
	for id: StringName in [&"pistol_p9", &"pistol_p9", &"smg_mp5", &"rifle_ak47", &"sniper_m24", &"gadget_frag", &"gadget_smoke"]:
		if WeaponCatalog.has_weapon(id):
			Profile.add_weapon(id)
	Profile.loadout.clear()


func _cheapest_skin(kind: StringName) -> SkinData:
	var list := SkinData.shop_skins(kind)
	for s: SkinData in list:
		if s.price_gems > 0:
			return s
	return null


func _first_weapon_tile(a: ArsenalScreen, gadget: bool) -> WeaponTile:
	for t: WeaponTile in a.tiles:
		if not t.locked and t.weapon.is_gadget() == gadget:
			return t
	return null


func test_main_scene_is_splash() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/ui/menus/splash.tscn")
	assert_eq(ProjectSettings.get_setting("application/boot_splash/image"), "res://assets/ui/splash/boot.png")
	assert_true(ResourceLoader.exists("res://assets/ui/splash/boot.png"))


func test_masks_are_gone_from_menus() -> void:
	assert_false(ResourceLoader.exists("res://scenes/ui/menus/mask_select.tscn"))
	assert_false(FileAccess.file_exists("res://scripts/ui/menus/mask_select.gd"))
	assert_false(FileAccess.file_exists("res://scripts/ui/menus/mask_card.gd"))
	assert_false(DirAccess.dir_exists_absolute("res://assets/ui/masks"))
	for f: String in DirAccess.get_files_at("res://scripts/ui/menus/"):
		if f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string("res://scripts/ui/menus/" + f)
			assert_false(src.contains("MaskData"), "Plus de MaskData : " + f)
			assert_false(src.contains("selected_mask"), "Plus de masque choisi : " + f)


func test_scenes_instantiate() -> void:
	_test_profile(100)
	for path: String in SCENES:
		assert_true(ResourceLoader.exists(path), path)
		var inst: Node = (load(path) as PackedScene).instantiate()
		assert_not_null(inst, path)
		if inst is SplashScreen:
			(inst as SplashScreen).auto_advance = false
		add_child_autofree(inst)
		await wait_frames(2)
	assert_true(true)


func test_splash_continues_boot_image() -> void:
	# Le boot splash natif (boot.png, rendu depuis la première image du splash) affiché en « keep »
	# sur fond encre : même couleur de fond, logo centré à la même échelle.
	assert_eq(int(ProjectSettings.get_setting("application/boot_splash/stretch_mode")), 1, "boot splash en « keep »")
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	assert_true(bg.is_equal_approx(MenuKit.NIGHT), "fond du boot splash = encre")
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/ui/splash/boot.png"))
	assert_eq(img.get_size(), Vector2i(1920, 1080), "boot.png en 1920 x 1080")
	var px: Color = img.get_pixel(4, 4)
	assert_lt(absf(px.r - MenuKit.NIGHT.r) + absf(px.g - MenuKit.NIGHT.g) + absf(px.b - MenuKit.NIGHT.b), 0.02, "coin de boot.png = encre")
	var s := (load(SCENES[0]) as PackedScene).instantiate() as SplashScreen
	s.auto_advance = false
	add_child_autofree(s)
	await wait_frames(2)
	assert_eq(s.next_scene, "res://scenes/ui/menus/main_menu.tscn")
	# première image : voile plein écran opaque, logotype centré, slogan masqué
	assert_eq(s.reveal, 0.0)
	assert_almost_eq(s.frame_scale, minf(s.size.x / 1920.0, s.size.y / 1080.0), 0.001)
	var c: Vector2 = s.logo.position + s.wordmark.size * 0.5
	assert_almost_eq(c.x, s.size.x * 0.5, 1.0, "logo centré (x)")
	assert_almost_eq(c.y, s.size.y * 0.5, 1.0, "logo centré (y)")
	assert_eq(s.curtain.color.a, 1.0, "voile opaque à la première image")
	assert_eq(s.slogan.size.x, 0.0, "slogan pas encore révélé")
	assert_not_null(s.lobby, "fond vivant du menu")


func test_splash_final_layout_fits() -> void:
	var s := (load(SCENES[0]) as PackedScene).instantiate() as SplashScreen
	s.auto_advance = false
	s.frozen = true
	add_child_autofree(s)
	await wait_frames(2)
	for vp: Vector2 in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1600, 720)]:
		s.size = vp
		s.reveal = 1.0
		s.slab_in = 1.0
		s.slogan.reveal = 1.0
		var r := Rect2(s.logo.position, s.logo.size)
		assert_true(Rect2(Vector2.ZERO, vp).encloses(r), "logo visible en entier : %s" % vp)
		assert_gt(r.position.x, vp.x * 0.5, "logo à droite du héros : %s" % vp)
		for p: Vector2 in s.curtain.points:
			assert_true(p.x >= 0.0 and p.x <= vp.x and p.y >= 0.0 and p.y <= vp.y, "plaque dans l'écran : %s" % vp)
		assert_lt(s.curtain.color.a, 1.0)


func test_game_name_is_raidersgo() -> void:
	for f: String in ["res://scripts/ui/menus/splash_screen.gd", "res://scripts/ui/menus/main_menu.gd",
			"res://scripts/ui/menus/raiders_logo.gd", "res://scripts/ui/menus/credits_panel.gd",
			"res://art/blender/build_menu_2d.py"]:
		var src := FileAccess.get_file_as_string(f).to_lower()
		assert_false(src.contains("royaume"), "Plus de « Royaumes des Masques » : " + f)
		assert_false(src.contains("exfil"), "Plus d'« Exfil Rush » : " + f)
	assert_eq(RaidersLogo.GAME_NAME, "RaidersGo")
	assert_string_contains(CreditsPanel.build_text(), "RaidersGo")


func _menu() -> MainMenu:
	var m := (load(SCENES[1]) as PackedScene).instantiate() as MainMenu
	add_child_autofree(m)
	return m


func test_main_menu_buttons() -> void:
	_test_profile(42)
	var m := _menu()
	await wait_frames(3)
	var labels: Array[String] = []
	for b: Button in m.buttons:
		labels.append(MainMenu.button_label(b))
		# pastilles Solo / Coop de la maquette : 52 px (au-dessus du minimum tactile de 48)
		assert_gte(b.custom_minimum_size.y, 48.0 if b == m.coop_button else 64.0, "Bouton tactile assez grand")
		assert_eq(b.focus_mode, Control.FOCUS_ALL, "Navigation manette/clavier")
		assert_gt(b.pressed.get_connections().size(), 0, "Bouton relié : " + MainMenu.button_label(b))
	assert_eq(labels, ["DÉPLOYER", "Coop", "Pass", "Progression", "Arsenal", "Atelier", "Inventaire", "Boutique"] as Array[String])
	assert_not_null(m.gem_counter, "Compteur de gemmes")
	assert_eq(m.gem_counter.value_label.text, "42")
	assert_gt(m.gem_plus.pressed.get_connections().size(), 0, "Bouton + des gemmes")
	assert_gt(m.gear_button.pressed.get_connections().size(), 0, "Bouton réglages")
	assert_not_null(m.hero, "Héros dans le décor")
	assert_not_null(m.lobby, "Fond vivant")
	assert_eq(m.logo.title_label.text, "RAIDERS")
	assert_eq(m.logo.go_label.text, "GO")
	var src := FileAccess.get_file_as_string("res://scripts/ui/menus/main_menu.gd")
	assert_string_contains(src, "MenuKit.go_to(self, MenuKit.MAP_SELECT_SCENE)", "« Jouer » → choix de la carte")
	assert_string_contains(src, "MenuKit.go_to(self, MenuKit.ARSENAL_SCENE)", "Arsenal → écran d'arsenal")
	var opts := m.open_options() as OptionsPanel
	await wait_frames(2)
	opts.music_slider.value = 0.35
	assert_almost_eq(float(AudioManager.music_volume), 0.35, 0.001)
	opts.vibration_toggle.button_pressed = false
	assert_false(bool(MenuKit.get_setting(&"vibration", true)))
	opts.close()


func test_main_menu_buttons_navigate() -> void:
	_test_profile(0)
	var m := _menu()
	await wait_frames(3)
	# Bloque le vrai changement de scène (MenuKit.go_to ne part qu'une fois) : on vérifie les effets.
	m.set_meta(&"_leaving", true)
	m.gem_plus.pressed.emit()
	assert_eq(ShopScreen.last_tab, &"gems", "+ → onglet Gemmes")
	m.lobby.hero_pressed.emit()
	assert_eq(ShopScreen.last_tab, &"character", "Tap sur le héros → Personnages")
	m.credits_button.pressed.emit()
	await wait_frames(2)
	assert_true(m.get_children().any(func(c: Node) -> bool: return c is CreditsPanel), "Crédits ouverts")
	m.options_button.pressed.emit()
	await wait_frames(2)
	assert_true(m.get_children().any(func(c: Node) -> bool: return c is OptionsPanel), "Options ouvertes")


func test_main_menu_stats_and_currencies() -> void:
	_test_profile(5)
	Profile.dollars = 12345   # = Profile.gold (or) une fois l'économie livrée
	Profile.stats = {"raids": 8, "extractions": 6, "deaths": 2}
	var m := _menu()
	await wait_frames(2)
	assert_eq((m.stat_values[&"raids"] as Label).text, "8")
	assert_eq((m.stat_values[&"extractions"] as Label).text, "6")
	assert_eq((m.stat_values[&"rate"] as Label).text, "75 %")
	assert_eq(m.gold_label.text, MainMenu.format_thousands(12345), "Or affiché en haut")
	assert_eq(MainMenu.gold_amount(), 12345)
	assert_eq(MainMenu.format_thousands(1234567), "1\u202f234\u202f567")


func test_lobby_hero_reflects_skin() -> void:
	_test_profile(0)
	Profile.skin_character = &""
	var m := _menu()
	await wait_frames(2)
	assert_eq(m.hero.sheet_id, "default", "Skin par défaut")
	assert_eq(m.hero.get_current_animation(), &"idle", "Idle, plus de rotation")
	assert_not_null(m.hero.sprite.texture, "Pose haute résolution du skin")
	var other: SkinData = null
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_CHARACTER):
		if s.id != HeroSkin.DEFAULT_SKIN_ID and LobbyHero.has_sheet(s):
			other = s
			break
	assert_not_null(other, "Un autre skin de personnage avec sa planche de menu")
	if other == null:
		return
	Profile.skins_owned.append(other.id)
	assert_true(Profile.equip_character_skin(other.id))
	await wait_frames(1)
	assert_eq(m.hero.sheet_id, String(other.id).trim_prefix("char_"), "Le héros du menu suit le skin porté")
	assert_eq(m.hero.skin, other)


func test_lobby_layout_nav_and_loadout() -> void:
	# Direction D (maquette Lobby) : menu texte à gauche sous la barre du haut, carte du pass en
	# bas à gauche, bandeau violet à droite : carte en cours en haut, DÉPLOYER puis Solo / Coop.
	_test_profile(0)
	for vp: Vector2 in [Vector2(1280, 720), Vector2(1560, 720)]:   # 16:9 et téléphone large (19,5:9)
		await _check_lobby_layout(vp)


func _check_lobby_layout(vp: Vector2) -> void:
	var m := _menu()
	await wait_frames(2)
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.size = vp
	await wait_seconds(1.1)   # fin des animations d'entrée
	assert_null(m.loadout_summary, "L'arsenal se choisit à l'étape 2, plus au lobby")
	var top: Rect2 = (m.get("_top") as Control).get_global_rect()
	var nav: Rect2 = (m.get("_nav") as Control).get_global_rect()
	assert_lt(nav.position.x, vp.x * 0.1, "Menu texte à gauche")
	assert_gte(nav.position.y, top.end.y - 1.0, "Menu sous la barre du haut")
	var hero_rect: Rect2 = m.lobby.hero_hit.get_global_rect()
	var hero_core := hero_rect.grow(-hero_rect.size.x * 0.15)
	assert_false(nav.intersects(hero_core), "Menu pas sur le héros")
	var pc: Rect2 = m.pass_card.get_global_rect()
	assert_lt(pc.position.x, vp.x * 0.1, "Pass en bas à gauche")
	assert_gt(pc.end.y, vp.y - 60.0)
	assert_false(pc.intersects(nav), "Pass sous le menu")
	assert_false(pc.intersects(hero_core), "Pass pas sur le héros")
	var slab: Rect2 = (m.get("slab") as Control).get_global_rect()
	assert_almost_eq(slab.end.x, vp.x, 1.0, "Bandeau collé au bord droit")
	assert_false(top.intersects(slab), "La barre du haut s'arrête avant le bandeau")
	var coop: Rect2 = m.coop_button.get_global_rect()
	var play: Rect2 = m.play_button.get_global_rect()
	assert_gte(coop.position.y, play.end.y - 1.0, "Coop sous DÉPLOYER (maquette : Solo / Coop)")
	assert_almost_eq(coop.end.x, play.end.x, 24.0, "Coop aligné à droite avec DÉPLOYER")
	var ml: Rect2 = m.map_link.get_global_rect()
	assert_lt(ml.end.y, play.position.y, "Carte en cours en haut du bandeau")
	assert_true(slab.encloses(ml.grow(-1.0)), "Carte en cours dans le bandeau")
	assert_false(m.info_banner.visible, "Bandeau d'info masqué hors message")
	assert_true(slab.encloses(play.grow(-1.0)), "DÉPLOYER dans le bandeau")
	assert_true(slab.encloses(coop.grow(-1.0)), "Coop dans le bandeau")
	assert_eq(m.merchant_button.caption.text, "Inventaire", "Marchand renommé Inventaire")
	assert_eq(m.merchant_button.soon, not ResourceLoader.exists(MenuKit.MERCHANT_SCENE), "Inventaire : « Bientôt » si absent")
	assert_eq(m.crafting_button.soon, not ResourceLoader.exists(MenuKit.CRAFTING_SCENE))
	assert_eq(bool(m.coop_button.get_meta(&"soon")), not ResourceLoader.exists(MenuKit.COOP_SCENE))
	# Un écran absent ne plante pas : aucun départ
	m.call("_go_optional", m.merchant_button, "res://scenes/ui/menus/__absent__.tscn")
	assert_false(bool(m.get_meta(&"_leaving", false)), "« Bientôt » : on reste au lobby")

func test_loadout_summary_shows_loadout() -> void:
	_test_profile(0)
	# 3e emplacement d'arme : débloqué par le niveau de raider (RaiderProgress)
	Profile.raider_xp = RaiderProgress.xp_total_for(RaiderProgress.max_level())
	var uids: Array[int] = []
	for e: Dictionary in Profile.get_stash_weapons():
		if String(e["id"]) in ["rifle_ak47", "smg_mp5", "gadget_frag"]:
			uids.append(int(e["uid"]))
	Profile.set_loadout(uids)
	var ls := LoadoutSummary.new()
	add_child_autofree(ls)
	await wait_frames(1)
	assert_eq(ls.slots.size(), Profile.loadout_slots() + Profile.gadget_slots())
	var names: Array[String] = []
	for s: Dictionary in ls.slots:
		if s["weapon"] != null:
			names.append((s["weapon"] as WeaponData).display_name)
	assert_eq(names.size(), 3, "2 armes + 1 équipement affichés")
	assert_true(ls.slots[Profile.loadout_slots()]["weapon"] != null and (ls.slots[Profile.loadout_slots()]["weapon"] as WeaponData).is_gadget(),
		"Dernier emplacement = équipement")
	assert_string_contains((ls.slots[2]["name"] as Label).text, "libre", "3e emplacement vide")
	Profile.set_loadout([] as Array[int])
	await wait_frames(1)
	assert_null(ls.slots[0]["weapon"], "Mise à jour sur Profile.changed")


func test_pass_card_on_lobby() -> void:
	_test_profile(0)
	var bp := BattlePassSystem.get_instance()
	var saved := bp.to_dict()
	bp.from_dict({"xp": bp.get_season().xp_total_for(4) + 10})
	var c := PassCard.new()
	add_child_autofree(c)
	await wait_frames(1)
	assert_eq(c.tier_label.text, "PALIER 4", "Palier actuel")
	assert_true(c.claim_pill.visible)
	assert_string_contains((c.claim_pill.get_node("Text") as Label).text, "%d à récupérer" % bp.claimable_count())
	assert_eq(c.next_label.text, "Palier 5")
	assert_false(c.next_value.text.is_empty(), "Récompense du prochain palier")
	assert_false(c.premium_pill.visible)
	bp.premium = true
	bp.claim_all()
	await wait_frames(1)
	assert_false(c.claim_pill.visible, "Rien à récupérer")
	assert_true(c.premium_pill.visible, "Accent premium")
	bp.from_dict(saved)


func test_touch_scroll_drag_vs_tap() -> void:
	# Glisser en commençant sur un bouton fait défiler sans le cliquer ; un tap = clic.
	var root := Control.new()
	root.size = Vector2(400, 300)
	add_child_autofree(root)
	var sc := ScrollContainer.new()
	sc.size = Vector2(400, 300)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	MenuKit.make_touch_scroll(sc)
	var col := VBoxContainer.new()
	sc.add_child(col)
	var clicks := [0]
	for i: int in 12:
		var b := Button.new()
		b.text = "Bouton %d" % i
		b.custom_minimum_size = Vector2(380, 80)
		b.pressed.connect(func() -> void: clicks[0] += 1)
		col.add_child(b)
	await wait_frames(2)
	var p0 := sc.get_global_rect().position + Vector2(100, 120)
	_touch(p0, true)
	for k: int in 6:
		_drag(p0 + Vector2(0, -20 * (k + 1)))
	_touch(p0 + Vector2(0, -120), false)
	await wait_frames(2)
	assert_gt(sc.scroll_vertical, 80, "Le glisser fait défiler")
	assert_eq(clicks[0], 0, "Pas de clic en faisant défiler")
	var before := sc.scroll_vertical
	_touch(p0, true)
	_touch(p0, false)
	await wait_frames(2)
	assert_eq(clicks[0], 1, "Un tap reste un clic")
	assert_almost_eq(float(sc.scroll_vertical), float(before), 2.0)
	assert_not_null(sc.get_node_or_null(^"TouchScroller"))


## Doigt simulé comme sur téléphone : événement tactile + souris émulée (emulate_mouse_from_touch).
func _touch(vp_pos: Vector2, pressed: bool) -> void:
	var p: Vector2 = get_viewport().get_final_transform() * vp_pos   # push_input attend des coordonnées fenêtre
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = p
	e.pressed = pressed
	get_viewport().push_input(e)
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = p
	m.global_position = p
	m.pressed = pressed
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(m)


func _drag(vp_pos: Vector2) -> void:
	var p: Vector2 = get_viewport().get_final_transform() * vp_pos
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = p
	get_viewport().push_input(e)
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m)


func test_menus_use_touch_scroll() -> void:
	for f: String in ["arsenal_screen", "battle_pass_screen", "crafting_screen", "credits_panel", "map_select",
			"merchant_screen", "shop_screen"]:
		var src := FileAccess.get_file_as_string("res://scripts/ui/menus/%s.gd" % f)
		assert_string_contains(src, "MenuKit.make_touch_scroll(", "Défilement tactile : " + f)


func test_play_card_shows_map() -> void:
	var card := MapCard.find(&"perm_dust_creek")
	GameState.current_map = card
	var p := PlayCard.new()
	add_child_autofree(p)
	await wait_frames(1)
	assert_eq(p.title_label.text, "DÉPLOYER")
	assert_eq(p.map_label.text, "%s · %s" % [card.display_name, card.difficulty_name()], "Ligne discrète : carte · difficulté")
	assert_eq(p.find_children("*", "TextureRect", true, false).size(), 0, "Pas de vignette de carte")
	assert_true(p.get_theme_stylebox("normal") is CutBox, "Coins coupés (direction D)")
	assert_eq((p.get_theme_stylebox("normal") as CutBox).bg_color.a, 0.0, "Sans fond : posé sur le bandeau violet")
	GameState.current_map = null
	assert_not_null(PlayCard.displayed_card(), "Sans carte choisie : première carte de la rotation")


func test_info_banner_messages() -> void:
	var ib := InfoBanner.new()
	add_child_autofree(ib)
	await wait_frames(1)
	assert_gt(ib.messages.size(), 1)
	assert_false(ib.text_label.text.is_empty())
	var first := ib.index
	ib.next()
	await wait_seconds(0.7)
	assert_ne(ib.index, first, "Les messages défilent")


func test_gem_counter_follows_profile() -> void:
	_test_profile(10)
	var g := GemCounter.new()
	add_child_autofree(g)
	await wait_frames(1)
	assert_eq(g.value_label.text, "10")
	Profile.add_gems(5)
	assert_eq(g.value_label.text, "15")


func test_credits_show_cc_by_attribution() -> void:
	var text := CreditsPanel.build_text()
	assert_string_contains(text, "game-icons.net")
	assert_string_contains(text, "CC BY 3.0")
	var credits_md := FileAccess.get_file_as_string("res://CREDITS.md")
	assert_string_contains(credits_md, CreditsPanel.ICONS_ATTRIBUTION)


func test_hero_preview_uses_lobby_hero() -> void:
	# Même rendu que le lobby : pose haute résolution + idle procédurale, plus de rotation.
	var hp := HeroPreview.new()
	hp.size = Vector2(300, 460)
	add_child_autofree(hp)
	await wait_frames(1)
	assert_true(hp.hero is LobbyHero, "Composant du lobby réutilisé")
	assert_not_null(hp.hero.sprite.texture, "Pose haute résolution")
	assert_eq(hp.get_current_animation(), &"idle")
	var sk := SkinData.get_skin(&"char_spetsnaz")
	hp.set_skin(sk)
	assert_eq(hp.get_sheet_id(), "spetsnaz", "Pose du skin sélectionné")
	assert_almost_eq(hp.hero.position.y, 460.0 * hp.feet_ratio, 0.5, "Pieds en bas de la boîte")
	hp.set_skin(null)
	assert_eq(hp.get_sheet_id(), "default")


# --- Arsenal de départ ----------------------------------------------------------------

func _loadout() -> ArsenalScreen:
	var a := (load("res://scenes/ui/menus/loadout.tscn") as PackedScene).instantiate() as ArsenalScreen
	a.raid_scene = ""
	add_child_autofree(a)
	return a


func test_loadout_empty_disables_validate() -> void:
	_test_profile()
	var a := _loadout()
	await wait_frames(2)
	assert_true(a.loadout_mode)
	assert_eq(a.slot_buttons.size(), Profile.loadout_slots(), "3 emplacements")
	assert_eq(a.tiles.size(), a.owned.size(), "Une carte par modèle possédé")
	assert_not_null(a.gadget_slot_button, "Emplacement d'équipement")
	assert_true(a.selected_uids.is_empty())
	assert_true(a.validate_button.disabled, "Aucune arme : « Valider et partir » désactivé")
	assert_false(a.validate_and_go())
	assert_false(Profile.raid_in_progress)
	var warn_found := false
	for l: Node in a.find_children("*", "Label", true, false):
		if (l as Label).text.contains("perdues si tu meurs"):
			warn_found = true
	assert_true(warn_found, "Rappel : armes perdues à la mort")


func test_loadout_toggle_and_validate() -> void:
	_test_profile()
	var a := _loadout()
	await wait_frames(2)
	assert_eq(a.gadget_slot_button != null, true, "Emplacement d'équipement")
	var weapons: Array[WeaponTile] = []
	for t: WeaponTile in a.tiles:
		assert_false(t.locked, "Arsenal de départ : seulement les armes possédées")
		if not t.weapon.is_gadget():
			weapons.append(t)
	assert_gte(weapons.size(), 4)
	assert_true(a.toggle_model(weapons[0].weapon))
	assert_false(a.validate_button.disabled, "Une arme : bouton actif")
	assert_eq(weapons[0].slot_index, 0)
	assert_true(a.toggle_model(weapons[0].weapon), "Retirer")
	assert_true(a.validate_button.disabled)
	for i: int in Profile.loadout_slots():
		assert_true(a.toggle_model(weapons[i].weapon))
	assert_false(a.toggle_model(weapons[Profile.loadout_slots()].weapon), "Emplacements d'armes pleins")
	# Équipement : un seul, remplacé par le suivant
	var gadgets: Array[WeaponTile] = []
	for t: WeaponTile in a.tiles:
		if t.weapon.is_gadget():
			gadgets.append(t)
	assert_eq(gadgets.size(), 2)
	assert_true(a.toggle_model(gadgets[0].weapon), "Gadget en plus des 3 armes")
	assert_true(a.toggle_model(gadgets[1].weapon), "Le gadget suivant remplace le premier")
	assert_eq(a.selected_weapon_count(), Profile.loadout_slots())
	assert_eq(a.selected_uids.size(), Profile.loadout_slots() + 1)
	# Validation : arsenal enregistré, raid lancé côté profil
	var n_before: int = Profile.weapons.size()
	assert_true(a.validate_and_go())
	assert_true(Profile.raid_in_progress, "GameState.begin_raid() appelé")
	assert_eq(GameState.raid_weapons.size(), Profile.loadout_slots(), "Armes emportées")
	assert_eq(GameState.raid_gadget, gadgets[1].weapon, "Équipement emporté")
	assert_eq(Profile.weapons.size(), n_before - Profile.loadout_slots() - 1, "Les armes quittent la réserve")


func test_loadout_duplicate_takes_one_copy() -> void:
	_test_profile()
	var a := _loadout()
	await wait_frames(2)
	var p9: WeaponTile = null
	for t: WeaponTile in a.tiles:
		if t.weapon.id == &"pistol_p9":
			p9 = t
	assert_not_null(p9)
	assert_eq(p9.owned_count(), 2, "Une carte par modèle, quantité ×2")
	assert_true(a.toggle_model(p9.weapon))
	assert_eq(a.selected_uids.size(), 1, "Un seul exemplaire emporté")


func test_loadout_keys_toggle() -> void:
	_test_profile()
	var a := _loadout()
	await wait_frames(2)
	assert_false(a.keys_label.visible, "Sans clef en réserve : pas de ligne « Clefs »")
	a.queue_free()
	Profile.items["key_bank_vault"] = 1
	Profile.pack_keys = false
	var b := _loadout()
	await wait_frames(2)
	assert_true(b.keys_label.visible, "Clef en réserve : ligne visible")
	assert_eq(b.keys_toggle.text, "Clefs : non")
	b.toggle_keys()
	assert_true(Profile.pack_keys, "Choix enregistré")
	assert_eq(b.keys_toggle.text, "Clefs : oui")
	Profile.pack_keys = false


func test_loadout_restores_previous_choice() -> void:
	_test_profile()
	var first: int = -1
	for e: Dictionary in Profile.get_stash_weapons():
		if not (e["data"] as WeaponData).is_gadget():
			first = int(e["uid"])
			break
	Profile.set_loadout([first] as Array[int])
	var a := _loadout()
	await wait_frames(2)
	assert_eq(a.selected_uids, [first] as Array[int], "Arsenal précédent pré-rempli")
	assert_false(a.validate_button.disabled)


func test_loadout_layout_d() -> void:
	# Maquette Loadout : bandeau violet à droite (fiche + Équiper + DÉPLOYER) ; 1er tap = fiche,
	# 2e tap ou bouton du bandeau = équiper / retirer.
	_test_profile()
	var a := _loadout()
	await wait_frames(3)
	assert_true(a.slab.is_ancestor_of(a.validate_button), "DÉPLOYER dans le bandeau")
	assert_true(a.slab.is_ancestor_of(a.equip_button), "Équiper dans le bandeau")
	assert_eq(a.validate_button.text, "DÉPLOYER")
	var t: WeaponTile = null
	for x: WeaponTile in a.tiles:
		if not x.weapon.is_gadget() and x.weapon != a.detail_weapon:
			t = x
			break
	assert_true(t.style_d, "Cartes d'armes au format D")
	a.call("_on_tile_pressed", t)
	assert_eq(a.detail_weapon, t.weapon, "1er tap : fiche")
	assert_eq(a.selected_weapon_count(), 0, "1er tap : rien d'équipé")
	assert_eq(a.equip_button.text, "ÉQUIPER EN 01")
	a.call("_on_tile_pressed", t)
	assert_eq(a.selected_weapon_count(), 1, "2e tap : équipée")
	assert_eq(a.equip_button.text, "RETIRER")
	a.equip_button.pressed.emit()
	assert_eq(a.selected_weapon_count(), 0, "Bouton du bandeau : retirée")


func test_arsenal_catalog_sections() -> void:
	_test_profile()
	var a := (load("res://scenes/ui/menus/arsenal.tscn") as PackedScene).instantiate() as ArsenalScreen
	add_child_autofree(a)
	await wait_frames(2)
	assert_false(a.loadout_mode)
	assert_null(a.validate_button, "Consultation : pas de lancement de raid")
	assert_eq(a.tiles.size(), WeaponCatalog.all().size(), "Catalogue complet : une carte par modèle")
	for cat: StringName in WeaponData.CATEGORIES:
		var has_model := WeaponCatalog.all().any(func(w: WeaponData) -> bool: return w.category == cat)
		assert_eq(a.sections.has(cat), has_model, "Section %s" % cat)
	var titles: Array[String] = []
	for l: Node in a.find_children("*", "Label", true, false):
		titles.append((l as Label).text)
	assert_has(titles, "PISTOLETS")
	assert_has(titles, "AUTRES")
	var locked := 0
	for t: WeaponTile in a.tiles:
		assert_eq(t.locked, a.owned_count(t.weapon.id) == 0)
		if t.locked:
			locked += 1
		assert_eq(t.owned_count(), a.owned_count(t.weapon.id))
		assert_not_null(t.find_child("RarityBand", true, false), "Bandeau de rareté")
	assert_gt(locked, 0, "Modèles non possédés grisés")
	var p9: WeaponTile = null
	for t: WeaponTile in a.tiles:
		if t.weapon.id == &"pistol_p9":
			p9 = t
	assert_eq(p9.owned_count(), 2)
	assert_true(p9._count.visible, "Quantité ×2 affichée")
	a.show_weapon_detail(p9.weapon, false)
	assert_eq(a.detail_weapon, p9.weapon)
	assert_not_null(a.skin_button, "Skins d'armes activés : bouton de skin dans l'arsenal")


func test_rarity_names_on_ui() -> void:
	assert_eq(MenuKit.rarity_name(0), "Commun")
	assert_eq(MenuKit.rarity_name(1), "Rare", "Plus de « Peu commun » affiché")
	assert_eq(MenuKit.rarity_name(2), "Rare")
	assert_eq(MenuKit.rarity_name(3), "Épique")
	assert_eq(MenuKit.rarity_name(4), "Légendaire")


# --- Skins d'armes --------------------------------------------------------------------

func test_weapon_skins_data() -> void:
	var list := SkinData.all_of_kind(SkinData.KIND_WEAPON)
	assert_gte(list.size(), 16, "Au moins 16 skins d'armes")
	var n_shop := 0
	var n_pass := 0
	for s: SkinData in list:
		assert_true(String(s.id).begins_with("wsk_"), String(s.id))
		assert_true(WeaponCatalog.has_weapon(s.weapon_id), "Arme existante : %s" % s.id)
		assert_eq(s.weapon_category, WeaponCatalog.get_weapon(s.weapon_id).category, "Catégorie cohérente : %s" % s.id)
		assert_between(s.rarity, 2, 4, "Rare à Légendaire : %s" % s.id)
		assert_between(s.price_gems, 100, 1200, "Prix cohérent : %s" % s.id)
		assert_true(WeaponSkin.PATTERNS.has(s.pattern), "Motif connu : %s" % s.id)
		assert_false(s.display_name.is_empty())
		assert_true(s.source in [SkinData.SOURCE_SHOP, SkinData.SOURCE_PASS], "Provenance : %s" % s.id)
		if s.is_pass():
			n_pass += 1
		else:
			n_shop += 1
		assert_true(s.applies_to(s.weapon_category, s.weapon_id))
		assert_false(s.applies_to(s.weapon_category, &"pistol_p9") and s.weapon_id != &"pistol_p9", "Une seule arme : %s" % s.id)
	assert_gte(n_shop, 6, "Skins d'armes en boutique")
	assert_gte(n_pass, 5, "Skins d'armes exclusifs au pass")


func test_weapon_skins_enabled_and_dedicated_textures() -> void:
	assert_true(bool(Balance.get_value("shop", "weapon_skins_enabled", false)), "Skins d'armes activés")
	assert_true(WeaponSkin.is_enabled())
	# Textures Blender dédiées : mêmes dimensions que l'arme d'origine (grip/muzzle valables).
	var n := 0
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_WEAPON):
		var held := s.held_texture()
		if held == null:
			continue
		n += 1
		var base := load("res://assets/sprites/weapons/%s.png" % s.weapon_id) as Texture2D
		assert_eq(held.get_size(), base.get_size(), "Taille du sprite dédié : %s" % s.id)
		assert_not_null(s.icon_texture(), "Icône dédiée : %s" % s.id)
	assert_gte(n, 4, "Au moins 4 skins rendus sous Blender")


func test_weapon_skin_apply() -> void:
	WeaponSkin.enabled_override = 1
	var spr := Sprite2D.new()
	add_child_autofree(spr)
	var s := SkinData.get_skin(&"wsk_p90_digital")   # recoloration par shader (pas de texture dédiée)
	assert_null(s.held_texture())
	WeaponSkin.apply(spr, s)
	assert_true(spr.material is ShaderMaterial)
	var m := spr.material as ShaderMaterial
	assert_eq(m.shader, WeaponSkin.SHADER)
	assert_eq(int(m.get_shader_parameter(&"pattern")), WeaponSkin.pattern_index(s.pattern))
	WeaponSkin.apply(spr, null)
	assert_null(spr.material, "null = apparence d'origine")
	WeaponSkin.enabled_override = -1


func test_weapon_skin_in_raid_by_weapon_texture() -> void:
	# Le joueur appelle apply(sprite, skin de catégorie) : le skin propre à l'arme équipée l'emporte,
	# reconnu par la texture (…/weapons/<id>.png) ; texture dédiée échangée puis restaurée.
	_test_profile(0)
	Profile.skins_owned.append(&"wsk_ak47_tiger")
	assert_true(WeaponSkin.equip(&"wsk_ak47_tiger"))
	var spr := Sprite2D.new()
	add_child_autofree(spr)
	var base := load("res://assets/sprites/weapons/rifle_ak47.png") as Texture2D
	spr.texture = base
	WeaponSkin.apply(spr, Profile.get_weapon_skin(&"rifle"))
	var tiger := SkinData.get_skin(&"wsk_ak47_tiger")
	if tiger.held_texture() != null:
		assert_eq(spr.texture, tiger.held_texture(), "Sprite dédié du skin")
	else:
		assert_true(spr.material is ShaderMaterial)
	# Autre fusil : le skin de l'AK ne s'applique pas
	var m4 := Sprite2D.new()
	add_child_autofree(m4)
	m4.texture = load("res://assets/sprites/weapons/rifle_m4a1.png") as Texture2D
	WeaponSkin.apply(m4, tiger)
	assert_null(m4.material, "Skin d'une autre arme ignoré")
	assert_eq(m4.texture.resource_path, "res://assets/sprites/weapons/rifle_m4a1.png")
	WeaponSkin.unequip(&"rifle_ak47")
	WeaponSkin.apply(spr, null)
	assert_eq(spr.texture, base, "Texture d'origine restaurée")
	assert_null(spr.material)


# --- Boutique -------------------------------------------------------------------------

func _shop() -> ShopScreen:
	var s := (load("res://scenes/ui/menus/shop.tscn") as PackedScene).instantiate() as ShopScreen
	add_child_autofree(s)
	return s


func test_shop_tabs_and_cosmetic_notice() -> void:
	_test_profile(0)
	var s := _shop()
	await wait_frames(2)
	assert_eq(s.tabs, [&"character", &"weapon", &"packs", &"chests", &"gold", &"gems"] as Array[StringName], "Onglets Personnages, Armes, Packs, Coffres, Or, Gemmes")
	assert_eq(s.current_tab, &"character")
	assert_eq(s.cards.size(), s.character_skins().size() + 1, "Une carte par skin + le personnage de base")
	assert_true(s.action_buttons.has(s.base_skin.id), "Carte du personnage de base")
	for sk: SkinData in s.character_skins():
		assert_false(sk.is_pass(), "Skins du pass absents de la boutique (non obtenus) : %s" % sk.id)
	assert_true(s.detail_preview.hero is LobbyHero, "Aperçu = rendu du lobby")
	for c: Control in s.cards:
		assert_not_null(c.find_child("RarityBand", true, false), "Bandeau de rareté")
		assert_not_null(c.find_child("Preview", true, false), "Personnage en pied")
	s.show_tab(&"gems")
	assert_eq(s.pack_buttons.size(), Store.packs().size())
	assert_true(s.simulated_badge.visible, "Badge « Paiement simulé »")
	var notice := false
	for l: Node in s.find_children("*", "Label", true, false):
		if (l as Label).text.contains("aucun avantage en jeu"):
			notice = true
	assert_true(notice, "Message « Purement cosmétique »")


func test_shop_weapon_tab() -> void:
	_test_profile(1000)
	var s := _shop()
	await wait_frames(2)
	s.show_tab(&"weapon")
	assert_eq(s.cards.size(), SkinData.shop_skins(SkinData.KIND_WEAPON).size(), "Skins d'armes vendus (pass exclus)")
	var gold := SkinData.get_skin(&"wsk_deagle_gold")
	s.select_skin(gold)
	assert_true(s.detail_icon.visible, "Aperçu sur l'arme")
	assert_eq(s.detail_icon.weapon.id, &"pistol_deagle")
	assert_eq(s.skin_state(gold), "buy")
	assert_true(s.buy(gold))
	assert_eq(s.skin_state(gold), "equipped")
	assert_eq(WeaponSkin.equipped_for(WeaponCatalog.get_weapon(&"pistol_deagle")), gold, "Équipé sur le Desert Eagle")
	assert_null(WeaponSkin.equipped_for(WeaponCatalog.get_weapon(&"pistol_p9")), "Pas sur les autres pistolets")
	assert_eq((s.action_buttons[gold.id] as Button).text, "Retirer")
	s.unequip_weapon(gold)
	assert_eq(s.skin_state(gold), "equip")
	# Skin du pass pas encore obtenu : « Dans le pass », pas d'achat possible
	var neon := SkinData.get_skin(&"wsk_vector_neon")
	assert_eq(s.skin_state(neon), "pass")
	assert_false(s.buy(neon), "Un skin du pass ne s'achète pas")
	var m := s.ask_buy(neon) as ConfirmPanel
	await wait_frames(1)
	assert_string_contains(m.message, "pass de combat")
	m.close()
	# Une fois obtenu, il apparaît (badge « Pass ») et s'équipe
	Profile.skins_owned.append(neon.id)
	s.show_tab(&"weapon")
	assert_eq(s.cards.size(), SkinData.shop_skins(SkinData.KIND_WEAPON).size() + 1)
	assert_eq(s.skin_state(neon), "equip")


func test_shop_buy_without_gems() -> void:
	_test_profile(0)
	var s := _shop()
	await wait_frames(2)
	var skin := _cheapest_skin(SkinData.KIND_CHARACTER)
	assert_not_null(skin)
	assert_eq(s.skin_state(skin), "buy")
	var m := s.ask_buy(skin) as ConfirmPanel
	await wait_frames(1)
	assert_string_contains(m.message, "Il te manque")
	assert_false(s.buy(skin), "Pas assez de gemmes")
	assert_false(Profile.owns_skin(skin.id))
	assert_eq(Profile.gems, 0)
	m.close()


func test_shop_buy_with_gems_and_equip() -> void:
	var skin := _cheapest_skin(SkinData.KIND_CHARACTER)
	_test_profile(skin.price_gems + 5)
	var s := _shop()
	await wait_frames(2)
	var m := s.ask_buy(skin) as ConfirmPanel
	await wait_frames(1)
	assert_string_contains(m.message, str(skin.price_gems))
	m.confirm_button.pressed.emit()
	assert_true(Profile.owns_skin(skin.id), "Acheté après confirmation")
	assert_eq(Profile.gems, 5, "Gemmes débitées")
	assert_eq(s.skin_state(skin), "equipped", "Équipé après l'achat")
	assert_eq(Profile.skin_character, skin.id)
	assert_true((s.action_buttons[skin.id] as Button).disabled, "« Équipé »")
	assert_eq(s.skin_state(s.base_skin), "equip", "Le personnage de base n'est plus porté")
	# Revenir au personnage de base puis rééquiper
	assert_true(s.equip(s.base_skin))
	assert_eq(s.skin_state(skin), "equip")
	assert_eq((s.action_buttons[skin.id] as Button).text, "Équiper")
	assert_true(s.equip(skin))
	assert_eq(s.skin_state(skin), "equipped")


func test_shop_character_default_equipped() -> void:
	_test_profile(0)
	var s := _shop()
	await wait_frames(2)
	assert_eq(s.skin_state(s.base_skin), "equipped", "Personnage de base porté par défaut")
	assert_eq(s.skin_state(null), "equipped")


func test_store_simulated_pack() -> void:
	_test_profile(0)
	var packs := Store.packs()
	assert_gte(packs.size(), 1, "Packs dans balance.cfg")
	var first := int(packs[0]["gems"]) * Store.first_bonus_multiplier()
	assert_true(Store.purchase_pack(0))
	assert_eq(Profile.gems, first, "Gemmes créditées (paiement simulé), doublées au premier achat")
	assert_false(Store.purchase_pack(-1))
	assert_false(Store.purchase_pack(packs.size()))
	assert_eq(Profile.gems, first)
	var s := _shop()
	await wait_frames(2)
	s.show_tab(&"gems")
	assert_true(s.buy_pack(packs.size() - 1))
	assert_eq(Profile.gems, first + int(packs[packs.size() - 1]["gems"]), "Bonus de premier achat une seule fois")


func test_shop_coffres_gratuits() -> void:
	_test_profile(0)
	Profile.free_chests = 0
	var s := _shop()
	await wait_frames(2)
	s.show_tab(&"chests")
	assert_not_null(s.offers, "Onglet Coffres")
	assert_true(s.offers.action_button.disabled, "Sans coffre gagné, rien à ouvrir (jamais vendus)")
	assert_eq(s.offers.find_children("Odds*", "", true, false).size(), Store.chest_odds().size(), "Taux affichés")
	Profile.free_chests = 1
	s.show_tab(&"chests")
	assert_false(s.offers.action_button.disabled)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var r := s.offers.open_chest(rng)
	assert_false(r.is_empty())
	assert_true(Profile.owns_skin((r["skin"] as SkinData).id))
	assert_not_null(s.offers.reveal, "Révélation du skin")
	s.offers.close_reveal()
	assert_true(s.offers.action_button.disabled)


func test_shop_packs_a_contenu() -> void:
	_test_profile(0)
	var s := _shop()
	await wait_frames(2)
	s.show_tab(&"packs")
	assert_eq(s.offers.cards.size(), Store.bundles().size())
	assert_eq(s.offers.selected, 0, "Pack Recrue choisi d'office")
	assert_true(s.offers.buy_bundle(&"recrue"))
	assert_false(Store.bundle_available(&"recrue"))
	s.show_tab(&"packs")
	assert_ne(s.offers.selected, 0, "Pack Recrue déjà pris : un autre pack est choisi")


func test_shop_gemmes_premier_achat() -> void:
	_test_profile(0)
	var s := _shop()
	await wait_frames(2)
	s.show_tab(&"gems")
	assert_not_null(s.offers.find_child("WelcomeBanner", true, false), "Bandeau premier achat")
	s.offers.select(0)
	assert_true(s.buy_pack(0))
	assert_eq(Profile.gems, int(Store.packs()[0]["gems"]) * Store.first_bonus_multiplier())
	assert_null(s.offers.find_child("WelcomeBanner", true, false), "Bandeau retiré après le premier achat")


# --- Pause ----------------------------------------------------------------------------

func test_pause_menu_pauses_tree() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var pm := PauseMenu.attach(layer)
	await wait_frames(1)
	assert_eq(PauseMenu.attach(layer), pm, "Pas de doublon")
	assert_false(pm.overlay.visible)
	pm.open()
	assert_true(get_tree().paused, "L'arbre est en pause")
	assert_eq(pm.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_eq(pm.abandon_button.text, "Abandonner le raid")
	pm.close()
	assert_false(get_tree().paused, "Reprendre relance le jeu")


func test_pause_abandon_asks_confirmation_then_calls_raid() -> void:
	var fake := _FakeRaid.new()
	get_tree().root.add_child(fake)
	autofree(fake)
	var pm := PauseMenu.new()
	fake.add_child(pm)
	await wait_frames(1)
	pm.open()
	var m := pm.ask_abandon()
	await wait_frames(1)
	assert_string_contains(m.message, "Tu perdras ton arsenal et ton butin")
	assert_eq(fake.abandoned, 0, "Rien avant confirmation")
	# Le menu appelle abandon_raid() sur la scène courante : on simule avec la racine de test.
	var prev := get_tree().current_scene
	get_tree().current_scene = fake
	m.confirm_button.pressed.emit()
	get_tree().current_scene = prev
	assert_eq(fake.abandoned, 1, "abandon_raid() appelé")
	assert_false(get_tree().paused)


class _FakeRaid extends Node:
	var abandoned: int = 0

	func abandon_raid() -> void:
		abandoned += 1
