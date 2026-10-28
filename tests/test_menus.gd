extends GutTest
## Menus d'Exfil Rush : les scènes s'instancient, menu principal (boutons, options), plus de
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
]

var _saved_data: Dictionary = {}
var _saved_profile: Dictionary = {}
var _saved_diff: int = 1
var _saved_map: Resource = null
var _saved_world: String = ""
var _saved_weapons: Array[WeaponData] = []


func before_each() -> void:
	_saved_data = SaveManager.data.duplicate(true)
	_saved_profile = Profile.to_dict()
	_saved_diff = GameState.difficulty
	_saved_map = GameState.current_map
	_saved_world = GameState.world_path
	_saved_weapons = GameState.raid_weapons.duplicate()


func after_each() -> void:
	get_tree().paused = false
	Profile.from_dict(_saved_profile)
	GameState.difficulty = _saved_diff
	GameState.current_map = _saved_map
	GameState.world_path = _saved_world
	GameState.raid_weapons = _saved_weapons
	SaveManager.data = _saved_data
	SaveManager.save()
	ShopScreen.last_tab = &"character"
	WeaponSkin.enabled_override = -1


## Profil de test : quelques armes (dont un doublon) et un équipement, gemmes données.
func _test_profile(gems: int = 0) -> void:
	Profile.from_dict({"gems": gems})
	for id: StringName in [&"pistol_p9", &"pistol_p9", &"smg_mp5", &"rifle_ak47", &"sniper_m24", &"gadget_frag", &"gadget_smoke"]:
		if WeaponCatalog.has_weapon(id):
			Profile.add_weapon(id)
	Profile.loadout.clear()


func _cheapest_skin(kind: StringName) -> SkinData:
	var list := SkinData.all_of_kind(kind)
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


func test_splash_has_exfil_logo() -> void:
	var s := (load(SCENES[0]) as PackedScene).instantiate() as SplashScreen
	s.auto_advance = false
	add_child_autofree(s)
	await wait_frames(2)
	assert_eq(s.title_label.text, "EXFIL RUSH")
	assert_eq(s.subtitle.text, "Tire. Pille. Tire-toi.")
	assert_not_null(s.emblem)
	assert_eq(s.next_scene, "res://scenes/ui/menus/main_menu.tscn")


func test_main_menu_buttons() -> void:
	var m := (load(SCENES[1]) as PackedScene).instantiate() as MainMenu
	add_child_autofree(m)
	await wait_frames(2)
	var labels: Array[String] = []
	for b: Button in m.buttons:
		labels.append(b.text)
		assert_gte(b.custom_minimum_size.y, 64.0, "Bouton tactile assez grand")
		assert_eq(b.focus_mode, Control.FOCUS_ALL, "Navigation manette/clavier")
	assert_eq(labels, ["Jouer", "Arsenal", "Boutique", "Options", "Crédits"] as Array[String])
	assert_not_null(m.gem_counter, "Compteur de gemmes")
	assert_eq(m.gem_counter.value_label.text, str(Profile.gems))
	assert_not_null(m.hero, "Aperçu du héros")
	assert_eq(m.logo.title_label.text, "EXFIL RUSH")
	var src := FileAccess.get_file_as_string("res://scripts/ui/menus/main_menu.gd")
	assert_string_contains(src, "MenuKit.go_to(self, MenuKit.MAP_SELECT_SCENE)", "« Jouer » → choix de la carte")
	var opts := m.open_options() as OptionsPanel
	await wait_frames(2)
	opts.music_slider.value = 0.35
	assert_almost_eq(float(AudioManager.music_volume), 0.35, 0.001)
	opts.vibration_toggle.button_pressed = false
	assert_false(bool(MenuKit.get_setting(&"vibration", true)))
	opts.close()


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


func test_hero_preview_turns_and_takes_skin() -> void:
	var hp := HeroPreview.new()
	hp.size = Vector2(300, 260)
	add_child_autofree(hp)
	await wait_frames(1)
	assert_not_null(hp.sprite.sprite_frames, "Planche du héros (HeroSkin)")
	var first := hp.get_current_animation()
	hp.call("_turn")
	assert_ne(hp.get_current_animation(), first, "L'aperçu change de direction")
	hp.set_skin(null)
	assert_not_null(hp.sprite.sprite_frames)


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
	assert_null(a.skin_button, "Skins d'armes désactivés : pas de bouton de skin")


func test_rarity_names_on_ui() -> void:
	assert_eq(MenuKit.rarity_name(0), "Commun")
	assert_eq(MenuKit.rarity_name(1), "Rare", "Plus de « Peu commun » affiché")
	assert_eq(MenuKit.rarity_name(2), "Rare")
	assert_eq(MenuKit.rarity_name(3), "Épique")
	assert_eq(MenuKit.rarity_name(4), "Légendaire")


# --- Skins d'armes --------------------------------------------------------------------

func test_weapon_skins_data() -> void:
	var list := SkinData.all_of_kind(SkinData.KIND_WEAPON)
	assert_gte(list.size(), 8, "Au moins 8 skins d'armes")
	var has_any := false
	var has_cat := false
	for s: SkinData in list:
		assert_true(String(s.id).begins_with("wsk_"), String(s.id))
		assert_between(s.price_gems, 80, 600, "Prix cohérent : %s" % s.id)
		assert_true(WeaponSkin.PATTERNS.has(s.pattern), "Motif connu : %s" % s.id)
		assert_false(s.display_name.is_empty())
		if s.weapon_category == SkinData.ANY_CATEGORY:
			has_any = true
		else:
			has_cat = true
			assert_true(WeaponData.CATEGORIES.has(s.weapon_category), "Catégorie valide : %s" % s.id)
	assert_true(has_any and has_cat, "Skins universels et par catégorie")


func test_weapon_skin_disabled_by_default() -> void:
	assert_false(bool(Balance.get_value("shop", "weapon_skins_enabled", true)), "Skins d'armes plus tard")
	assert_false(WeaponSkin.is_enabled())
	var spr := Sprite2D.new()
	add_child_autofree(spr)
	WeaponSkin.apply(spr, SkinData.all_of_kind(SkinData.KIND_WEAPON)[0])
	assert_null(spr.material, "Désactivé : aucun effet")


func test_weapon_skin_apply() -> void:
	WeaponSkin.enabled_override = 1
	var spr := Sprite2D.new()
	add_child_autofree(spr)
	var s := SkinData.all_of_kind(SkinData.KIND_WEAPON)[0]
	WeaponSkin.apply(spr, s)
	assert_true(spr.material is ShaderMaterial)
	var m := spr.material as ShaderMaterial
	assert_eq(m.shader, WeaponSkin.SHADER)
	assert_eq(int(m.get_shader_parameter(&"pattern")), WeaponSkin.pattern_index(s.pattern))
	WeaponSkin.apply(spr, null)
	assert_null(spr.material, "null = apparence d'origine")
	WeaponSkin.enabled_override = -1


# --- Boutique -------------------------------------------------------------------------

func _shop() -> ShopScreen:
	var s := (load("res://scenes/ui/menus/shop.tscn") as PackedScene).instantiate() as ShopScreen
	add_child_autofree(s)
	return s


func test_shop_tabs_and_cosmetic_notice() -> void:
	_test_profile(0)
	var s := _shop()
	await wait_frames(2)
	assert_eq(s.tabs, [&"character", &"gems"] as Array[StringName], "Onglet Armes masqué")
	assert_false(s.tab_chips.has(&"weapon"))
	assert_eq(s.current_tab, &"character")
	assert_eq(s.cards.size(), s.character_skins().size(), "Une carte par skin (hors base)")
	assert_true(s.action_buttons.has(s.base_skin.id if s.base_skin != null else &""), "Panneau du personnage de base")
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


func test_shop_weapon_tab_when_enabled() -> void:
	WeaponSkin.enabled_override = 1
	var s := _shop()
	await wait_frames(2)
	assert_true(s.tab_chips.has(&"weapon"))
	s.show_tab(&"weapon")
	assert_eq(s.cards.size(), SkinData.all_of_kind(SkinData.KIND_WEAPON).size())
	WeaponSkin.enabled_override = -1


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
	assert_true(Store.purchase_pack(0))
	assert_eq(Profile.gems, int(packs[0]["gems"]), "Gemmes créditées (paiement simulé)")
	assert_false(Store.purchase_pack(-1))
	assert_false(Store.purchase_pack(packs.size()))
	assert_eq(Profile.gems, int(packs[0]["gems"]))
	var s := _shop()
	await wait_frames(2)
	s.show_tab(&"gems")
	assert_true(s.buy_pack(packs.size() - 1))
	assert_eq(Profile.gems, int(packs[0]["gems"]) + int(packs[packs.size() - 1]["gems"]))


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
