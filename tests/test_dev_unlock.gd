extends GutTest
## Mode dev « Tout débloquer » (DevMode.set_all_unlocked) : profil de développement virtuel, la
## vraie sauvegarde n'est jamais touchée (ni envoyée au cloud), et on retrouve exactement son profil
## à la désactivation. Profil, pass, SaveManager.data et user://save.json restaurés après chaque test.

var _saved_profile: Dictionary = {}
var _saved_pass: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	DevMode.reset()
	_saved_profile = Profile.to_dict()
	_saved_pass = BattlePassSystem.get_instance().to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""
	# Profil réel connu, sauvegardé (c'est lui qui doit revenir à l'identique).
	Profile.reset_new()
	Profile.gems = 7
	Profile.gold = 42
	Profile.items = {"bandage": 2}
	Profile.save()
	BattlePassSystem.get_instance().from_dict({"xp": 10})
	BattlePassSystem.get_instance().save()


func after_each() -> void:
	DevMode.reset()
	Profile.from_dict(_saved_profile)
	BattlePassSystem.get_instance().from_dict(_saved_pass)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


func _owned_ids() -> Dictionary:
	var out := {}
	for e: Dictionary in Profile.get_stash_weapons():
		out[e["id"]] = true
	return out


func test_desactive_par_defaut() -> void:
	assert_false(DevMode.is_all_unlocked())
	assert_false(Profile.is_dev_profile())


func test_tout_est_debloque() -> void:
	assert_true(DevMode.set_all_unlocked(true))
	assert_true(Profile.is_dev_profile())
	var owned := _owned_ids()
	for w: WeaponData in WeaponCatalog.all():
		assert_true(owned.has(w.id), "Arme du catalogue dans la réserve : %s" % w.id)
	var rarities := {}
	var with_affixes := 0
	for e: Dictionary in Profile.get_stash_weapons():
		rarities[(e["data"] as WeaponData).rarity] = true
		if not (e["affixes"] as Array).is_empty():
			with_affixes += 1
	var cat_rarities := {}
	for w: WeaponData in WeaponCatalog.all():
		cat_rarities[w.rarity] = true
	assert_eq(rarities.size(), cat_rarities.size(), "Toutes les raretés du catalogue sont représentées")
	assert_true(rarities.has(4), "Légendaires comprises")
	if Affixes.enabled():
		assert_gt(with_affixes, 0, "Des exemplaires portent des affixes")
	for it: ItemData in LootDB.all_items():
		if not it.is_weapon():
			assert_gt(Profile.item_count(it.id), 0, "Objet en quantité : %s" % it.id)
	assert_gt(LootDB.all_keys().size(), 0)
	for k: StringName in [SkinData.KIND_CHARACTER, SkinData.KIND_WEAPON]:
		for s: SkinData in SkinData.all_of_kind(k):
			assert_true(Profile.owns_skin(s.id), "Skin possédé : %s" % s.id)
	var bp := BattlePassSystem.get_instance()
	assert_eq(bp.tier(), bp.max_tier(), "Tous les paliers du pass")
	assert_true(bp.premium, "Premium compris")
	assert_gt(bp.claimable_count(), 0, "Récompenses récupérables pour les tester")
	assert_eq(RaiderProgress.current_level(), RaiderProgress.max_level(), "Niveau de raider maximal")
	assert_eq(Profile.loadout_slots(), int(Balance.get_value("arsenal", "loadout_slots", 3)),
		"Arsenal de départ : tous les emplacements")
	assert_eq(Profile.get_loadout_weapons().size(), Profile.loadout_slots(), "Arsenal de départ rempli")


func test_toutes_les_cartes_et_difficultes() -> void:
	DevMode.set_all_unlocked(true)
	var offered := MapRotation.offered_cards(MapRotation.now())
	assert_eq(offered.size(), MapCard.load_all().size(), "Toute la rotation est ouverte")
	var diffs := {}
	for e: Dictionary in offered:
		var c: MapCard = e["card"]
		diffs[c.difficulty] = true
		assert_true(MapRotation.is_active(e, MapRotation.now()), "Ouverte sans limite : %s" % c.id)
		assert_true(RaiderProgress.current_level() >= RaiderProgress.required_level(c.id), "Niveau suffisant : %s" % c.id)
	assert_gt(diffs.size(), 1, "Plusieurs difficultés proposées")
	DevMode.set_all_unlocked(false)
	assert_lt(MapRotation.offered_cards(MapRotation.now()).size(), MapCard.load_all().size(), "Rotation normale rétablie")


func test_arsenal_de_depart_accepte_n_importe_quelle_arme() -> void:
	DevMode.set_all_unlocked(true)
	var best: Dictionary = {}
	for e: Dictionary in Profile.get_stash_weapons():
		if (e["data"] as WeaponData).rarity == 4 and not (e["data"] as WeaponData).is_gadget():
			best = e
			break
	assert_false(best.is_empty(), "Une Légendaire dans la réserve")
	var uids: Array[int] = [int(best["uid"])]
	Profile.set_loadout(uids)
	assert_eq(Profile.loadout, uids, "Légendaire acceptée dans l'arsenal de départ")


func test_vraie_sauvegarde_jamais_touchee() -> void:
	var real_before: Dictionary = (SaveManager.data["profile"] as Dictionary).duplicate(true)
	var pass_before: Dictionary = (SaveManager.data["battle_pass"] as Dictionary).duplicate(true)
	var file_before := FileAccess.get_file_as_string(SaveManager.SAVE_PATH)
	DevMode.set_all_unlocked(true)
	# On joue avec le profil de test : achats, artisanat, pass, réglages…
	Profile.add_gems(500)
	Profile.add_item(&"bandage", 3)
	BattlePassSystem.get_instance().claim_all()
	MenuKit.set_setting(&"vibration", true)   # une autre sauvegarde a lieu pendant le mode dev
	assert_eq(SaveManager.data["profile"], real_before, "SaveManager garde le profil réel")
	assert_eq(SaveManager.data["battle_pass"], pass_before, "SaveManager garde le vrai pass")
	var on_disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
	assert_eq(JSON.stringify((on_disk as Dictionary)["profile"]), JSON.stringify(JSON.parse_string(file_before)["profile"]),
		"Le fichier de sauvegarde garde le profil réel")
	# Ce que CloudSync enverrait : jamais le profil de développement.
	var payload := CloudSync.payload_of(SaveManager.data)
	assert_eq(int((payload["profile"] as Dictionary)["gems"]), 7, "Cloud : gemmes réelles")
	assert_eq(((payload["profile"] as Dictionary)["weapons"] as Array).size(), (real_before["weapons"] as Array).size(),
		"Cloud : réserve réelle")


func test_desactiver_rend_exactement_le_profil() -> void:
	var before := Profile.to_dict()
	var pass_before := BattlePassSystem.get_instance().to_dict()
	DevMode.set_all_unlocked(true)
	Profile.add_gems(1000)
	Profile.set_loadout([] as Array[int])
	DevMode.set_all_unlocked(false)
	assert_false(Profile.is_dev_profile())
	assert_eq(JSON.stringify(Profile.to_dict()), JSON.stringify(before), "Profil d'avant, à l'identique")
	assert_eq(JSON.stringify(BattlePassSystem.get_instance().to_dict()), JSON.stringify(pass_before), "Pass d'avant")
	assert_eq(Profile.gems, 7)
	# Et la sauvegarde reprend normalement.
	Profile.add_gems(1)
	assert_eq(int((SaveManager.data["profile"] as Dictionary)["gems"]), 8)


func test_refuse_pendant_un_raid() -> void:
	Profile.raid_in_progress = true
	assert_false(DevMode.set_all_unlocked(true), "Pas de changement de profil en plein raid")
	assert_false(Profile.is_dev_profile())
	Profile.raid_in_progress = false


func test_jamais_en_version_publiee() -> void:
	DevMode.build_check = func() -> bool: return false
	assert_false(DevMode.set_all_unlocked(true))
	assert_false(DevMode.is_all_unlocked())
	assert_false(Profile.is_dev_profile())


func test_donner_arme_et_objet_hors_raid() -> void:
	DevMode.set_all_unlocked(true)
	var n := Profile.weapon_count(&"smg_mp5")
	assert_ne(DevTools.give_weapon(&"smg_mp5"), "")
	assert_eq(Profile.weapon_count(&"smg_mp5"), n + 1, "Arme ajoutée à la réserve")
	var k := Profile.item_count(&"bandage")
	assert_ne(DevTools.give_item(&"bandage", 4), "")
	assert_eq(Profile.item_count(&"bandage"), k + 4)
	assert_eq(DevTools.give_weapon(&"arme_inconnue"), "", "Id inconnu refusé")


func test_donner_en_raid_arme_en_main_objet_dans_le_sac() -> void:
	var old_player: Variant = GameState.player
	var old_inv: Variant = GameState.raid_inventory
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child_autofree(player)
	await wait_process_frames(2)
	GameState.player = player
	GameState.raid_inventory = Inventory.from_balance()
	var held_before: WeaponData = player.call("get_weapons")[0]
	# weapon_item() met en cache un objet créé à la volée (pistolet de départ) : retiré en fin de test.
	var cached_id := StringName("wpn_" + String(held_before.id)) if held_before != null else &""
	var was_cached := cached_id != &"" and LootDB.has_item(cached_id)
	assert_string_contains(DevTools.give_weapon(&"smg_mp5"), "en main")
	var held: Array = player.call("get_weapons")
	assert_true(held.any(func(w: Variant) -> bool: return w is WeaponData and (w as WeaponData).id == &"smg_mp5"),
		"Arme donnée en main")
	if held_before != null:
		assert_gt(GameState.raid_inventory.count_of(LootDB.weapon_item(held_before).id), 0, "Ancienne arme dans le sac")
	assert_string_contains(DevTools.give_item(&"bandage", 2), "sac")
	assert_eq(GameState.raid_inventory.count_of(&"bandage"), 2)
	GameState.player = old_player
	GameState.raid_inventory = old_inv
	if cached_id != &"" and not was_cached:
		LootDB._items.erase(cached_id)


func test_interrupteur_dans_les_options() -> void:
	var p := OptionsPanel.new()
	add_child_autofree(p)
	await wait_process_frames(2)
	assert_not_null(p.unlock_toggle, "Interrupteur « Tout débloquer » dans la section développeur")
	assert_false(p.unlock_toggle.button_pressed)
	p.unlock_toggle.button_pressed = true
	assert_true(DevMode.is_all_unlocked())
	assert_eq(p.unlock_toggle.text, "Activé")
	p.unlock_toggle.button_pressed = false
	assert_false(DevMode.is_all_unlocked())


func test_options_sans_interrupteur_en_version_publiee() -> void:
	DevMode.build_check = func() -> bool: return false
	var p := OptionsPanel.new()
	add_child_autofree(p)
	await wait_process_frames(2)
	assert_null(p.unlock_toggle)


func test_panneau_dev_donner() -> void:
	var dp := DevPanel.new()
	add_child_autofree(dp)
	await wait_process_frames(1)
	assert_not_null(dp.give_picker)
	assert_eq(dp.give_picker.item_count, DevTools.catalog().size(), "Toutes les armes et tous les objets")
	assert_true(dp.select_entry(&"bandage"))
	dp.give_count.value = 3
	var k := Profile.item_count(&"bandage")
	assert_ne(dp.give_selected(), "")
	assert_eq(Profile.item_count(&"bandage"), k + 3)
	dp.unlock_toggle.button_pressed = true
	assert_true(DevMode.is_all_unlocked(), "Bascule depuis le panneau F3")
	assert_true(dp.badge.visible, "Badge DEV visible")
