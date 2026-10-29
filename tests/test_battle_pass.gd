extends GutTest
## Pass de combat (BattlePassSystem, data/battle_pass/season_01.tres) : XP de raid → paliers,
## premium payé en gemmes, récompenses récupérées une seule fois, skins du pass absents de la
## boutique, skin d'arme par arme prioritaire sur la catégorie. Sauvegarde isolée.

var _saved_data: Dictionary = {}
var _saved_profile: Dictionary = {}
var _saved_pass: Dictionary = {}
var bp: BattlePassSystem = null


func before_each() -> void:
	_saved_data = SaveManager.data.duplicate(true)
	_saved_profile = Profile.to_dict()
	bp = BattlePassSystem.get_instance()
	_saved_pass = bp.to_dict()
	Profile.from_dict({"gems": 0})
	bp.reset()


func after_each() -> void:
	bp.from_dict(_saved_pass)
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_data
	SaveManager.save()


func test_season_data() -> void:
	var s := bp.get_season()
	assert_eq(s.display_name, "Saison 1 — Dust Creek")
	assert_eq(s.tiers, 30)
	assert_eq(s.free_rewards.size(), 30)
	assert_eq(s.premium_rewards.size(), 30)
	for t: int in range(2, 31):
		assert_gt(s.xp_for_tier(t), s.xp_for_tier(t - 1), "XP par palier croissante")
	# Toutes les récompenses sont valides
	for track: StringName in [BattlePassSystem.FREE, BattlePassSystem.PREMIUM]:
		for t: int in range(1, 31):
			var r := s.reward(t, track)
			if r.is_empty():
				continue
			match str(r["type"]):
				"skin":
					assert_not_null(SkinData.get_skin(StringName(str(r["id"]))), "Skin %s" % r)
				"item":
					assert_true(ResourceLoader.exists("res://data/items/%s.tres" % r["id"]), "Objet %s" % r)
				"gems", "gold":
					assert_gt(int(r["amount"]), 0)
				_:
					fail_test("Type inconnu %s" % r)
	# 4 skins de personnage déplacés de la boutique + des skins d'armes exclusifs
	var chars := 0
	var weapons := 0
	for id: StringName in s.skin_ids():
		var sk := SkinData.get_skin(id)
		assert_true(sk.is_pass(), "Skin du pass marqué source=pass : %s" % id)
		if sk.kind == SkinData.KIND_CHARACTER:
			chars += 1
		else:
			weapons += 1
	assert_eq(chars, 4)
	assert_gte(weapons, 5)


func test_xp_to_tiers() -> void:
	var s := bp.get_season()
	assert_eq(bp.tier(), 0)
	bp.add_xp(s.xp_for_tier(1) - 1)
	assert_eq(bp.tier(), 0, "Pas encore le palier 1")
	var g := bp.add_xp(1)
	assert_eq(bp.tier(), 1)
	assert_eq(int(g["tier_before"]), 0)
	assert_eq(int(g["tier_after"]), 1)
	bp.add_xp(s.xp_for_tier(2) + s.xp_for_tier(3) + 10)
	assert_eq(bp.tier(), 3)
	assert_eq(bp.tier_progress(), Vector2i(10, s.xp_for_tier(4)))
	bp.add_xp(10_000_000)
	assert_eq(bp.tier(), 30, "Plafond : pass terminé")
	assert_eq(bp.xp, s.xp_total_for(30))


func test_raid_xp() -> void:
	var ext := BattlePassSystem.raid_xp({"success": true, "value": 1000, "kills": 5, "time": 300.0})
	var death := BattlePassSystem.raid_xp({"success": false, "value": 1000, "kills": 5, "time": 300.0})
	assert_gt(death, 0, "Mort : un peu d'XP")
	assert_gt(ext, death * 2, "Extraction bien plus rentable")
	assert_gt(BattlePassSystem.raid_xp({"success": true, "kills": 10}), BattlePassSystem.raid_xp({"success": true, "kills": 0}), "Kills")
	assert_gt(BattlePassSystem.raid_xp({"success": true, "value": 5000}), BattlePassSystem.raid_xp({"success": true, "value": 0}), "Valeur extraite")
	assert_gt(BattlePassSystem.raid_xp({"success": true, "time": 600.0}), BattlePassSystem.raid_xp({"success": true, "time": 0.0}), "Temps survécu")
	assert_lte(BattlePassSystem.raid_xp({"success": true, "value": 10_000_000, "kills": 999, "time": 99999.0}),
		int(Balance.get_value("battle_pass", "xp_raid_max", 1500)), "Plafond par raid")
	# add_raid_xp compte les kills du raid (EventBus) quand le résumé ne les donne pas
	EventBus.raid_started.emit(1)
	for i: int in 3:
		EventBus.enemy_died.emit(null, Vector2.ZERO)
	var r := bp.add_raid_xp({"success": true, "value": 0})
	assert_eq(int(r["xp"]), BattlePassSystem.raid_xp({"success": true, "value": 0, "kills": 3, "time": 0.0}))
	assert_eq(bp.xp, int(r["xp"]))
	assert_eq(bp.last_gain, r)


func test_premium_paid_with_gems() -> void:
	var price := BattlePassSystem.premium_price()
	assert_gt(price, 0)
	Profile.gems = price - 1
	assert_false(bp.buy_premium(), "Pas assez de gemmes")
	assert_false(bp.premium)
	Profile.gems = price + 7
	assert_true(bp.buy_premium())
	assert_true(bp.premium)
	assert_eq(Profile.gems, 7, "Gemmes débitées")
	assert_false(bp.buy_premium(), "Une seule fois")
	assert_eq(Profile.gems, 7)


func test_claim_once() -> void:
	var s := bp.get_season()
	assert_false(bp.can_claim(1, BattlePassSystem.FREE), "Palier non atteint")
	bp.add_xp(s.xp_total_for(5))
	var r1 := s.reward(3, BattlePassSystem.FREE)
	assert_eq(str(r1["type"]), "gems")
	var gems_before := Profile.gems
	assert_true(bp.claim(3, BattlePassSystem.FREE))
	assert_eq(Profile.gems, gems_before + int(r1["amount"]))
	assert_false(bp.claim(3, BattlePassSystem.FREE), "Une seule fois")
	assert_eq(Profile.gems, gems_before + int(r1["amount"]))
	# Or et objets
	var gold_before := MainMenu.gold_amount()
	assert_true(bp.claim(1, BattlePassSystem.FREE))
	assert_eq(MainMenu.gold_amount(), gold_before + int(s.reward(1, BattlePassSystem.FREE)["amount"]), "Or crédité")
	var r2 := s.reward(2, BattlePassSystem.FREE)
	var n_before := int(Profile.items.get(str(r2["id"]), 0))
	assert_true(bp.claim(2, BattlePassSystem.FREE))
	assert_eq(int(Profile.items.get(str(r2["id"]), 0)), n_before + int(r2["amount"]), "Objet ajouté à la réserve")
	# Premium : verrouillé tant qu'il n'est pas acheté
	assert_false(bp.can_claim(5, BattlePassSystem.PREMIUM))
	Profile.gems = BattlePassSystem.premium_price()
	assert_true(bp.buy_premium())
	var skin_id := StringName(str(s.reward(5, BattlePassSystem.PREMIUM)["id"]))
	assert_false(Profile.owns_skin(skin_id))
	assert_true(bp.claim(5, BattlePassSystem.PREMIUM))
	assert_true(Profile.owns_skin(skin_id), "Skin du pass obtenu")
	assert_true(Profile.equip_character_skin(skin_id))
	# Tout récupérer : le reste des paliers 1..5, une seule fois
	var n := bp.claimable_count()
	assert_gt(n, 0)
	assert_eq(bp.claim_all(), n)
	assert_eq(bp.claimable_count(), 0)
	assert_eq(bp.claim_all(), 0)


func test_save_roundtrip() -> void:
	bp.add_xp(1234)
	Profile.gems = BattlePassSystem.premium_price()
	bp.buy_premium()
	bp.claim(1, BattlePassSystem.FREE)
	var d: Dictionary = SaveManager.data.get(BattlePassSystem.SAVE_KEY, {})
	assert_eq(int(d.get("xp", 0)), 1234, "Sauvegardé dans SaveManager.data[battle_pass]")
	var other := BattlePassSystem.new()
	other.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(other.xp, 1234)
	assert_true(other.premium)
	assert_true(other.is_claimed(1, BattlePassSystem.FREE))
	other.free()
	# Autre saison : remise à zéro
	var o2 := BattlePassSystem.new()
	o2.from_dict({"season": "season_99", "xp": 999, "premium": true})
	assert_eq(o2.xp, 0)
	assert_false(o2.premium)
	o2.free()


func test_pass_skins_absent_from_shop() -> void:
	for id: StringName in [&"char_fantome", &"char_forest", &"char_cyber", &"char_scorpion"]:
		var s := SkinData.get_skin(id)
		assert_true(s.is_pass(), "%s est dans le pass" % id)
		assert_false(s.is_in_shop())
		assert_false(SkinData.shop_skins(SkinData.KIND_CHARACTER).has(s), "%s retiré de la boutique" % id)
		assert_true(bp.is_pass_skin(id))
		assert_false(bp.find_skin(id).is_empty(), "%s se trouve dans la saison" % id)
	assert_eq(SkinData.shop_skins(SkinData.KIND_CHARACTER).size(), 4, "4 skins de personnage restent en boutique")
	var shop := (load("res://scenes/ui/menus/shop.tscn") as PackedScene).instantiate() as ShopScreen
	add_child_autofree(shop)
	await wait_frames(2)
	for c: SkinData in shop.character_skins():
		assert_false(c.is_pass(), "Absent de la boutique tant qu'il n'est pas obtenu : %s" % c.id)
	assert_eq(shop.skin_state(SkinData.get_skin(&"char_cyber")), "pass", "Badge « Dans le pass »")
	assert_false(shop.buy(SkinData.get_skin(&"char_cyber")))


func test_weapon_skin_per_weapon_priority() -> void:
	var ak := WeaponCatalog.get_weapon(&"rifle_ak47")
	var m4 := WeaponCatalog.get_weapon(&"rifle_m4a1")
	# Skin de catégorie (ancien système) simulé + skin propre à l'AK
	var cat_skin := SkinData.new()
	cat_skin.id = &"wsk_test_cat"
	cat_skin.kind = SkinData.KIND_WEAPON
	cat_skin.weapon_category = &"rifle"
	assert_true(cat_skin.applies_to(&"rifle", &"rifle_m4a1"))
	var tiger := SkinData.get_skin(&"wsk_ak47_tiger")
	assert_true(tiger.applies_to(&"rifle", &"rifle_ak47"))
	assert_false(tiger.applies_to(&"rifle", &"rifle_m4a1"), "Skin d'arme : une seule arme")
	assert_false(WeaponSkin.equip(tiger.id), "Non possédé")
	Profile.skins_owned.append(tiger.id)
	assert_true(WeaponSkin.equip(tiger.id))
	assert_eq(str(Profile.skin_weapons.get("rifle_ak47", "")), String(tiger.id), "Rangé sous l'id de l'arme")
	assert_eq(WeaponSkin.equipped_for(ak), tiger)
	assert_null(WeaponSkin.equipped_for(m4))
	# Un skin de catégorie équipé : la clé de l'arme reste prioritaire
	var arctic := SkinData.get_skin(&"wsk_m4a1_arctic")
	Profile.skins_owned.append(arctic.id)
	assert_true(WeaponSkin.equip(arctic.id))
	assert_eq(WeaponSkin.equipped_for(m4), arctic)
	assert_eq(WeaponSkin.equipped_for(ak), tiger, "Chaque arme garde son skin")
	WeaponSkin.unequip(&"rifle_ak47")
	assert_null(WeaponSkin.equipped_for(ak))
	assert_true(WeaponSkin.is_equipped(arctic))


func test_pass_screen() -> void:
	Profile.gems = 5000
	bp.add_xp(bp.get_season().xp_total_for(6) + 40)
	var scr := (load("res://scenes/ui/menus/battle_pass.tscn") as PackedScene).instantiate() as BattlePassScreen
	add_child_autofree(scr)
	await wait_frames(3)
	assert_eq(scr.cells.size(), 60, "30 paliers × 2 pistes")
	assert_not_null(scr.track_scroll)
	assert_eq(scr.tier_label.text, "Palier 6")
	# Vitrine par défaut : prochain grand skin premium non obtenu (personnage en pied)
	var feat := scr.featured_reward()
	assert_eq(StringName(feat["track"]), BattlePassSystem.PREMIUM)
	assert_gt(int(feat["tier"]), 6)
	assert_true(scr.detail_preview.visible, "Personnage en pied dans la vitrine")
	assert_true(scr.premium_button.visible)
	assert_false(scr.premium_badge.visible)
	# États des cases : disponible / verrouillé / premium verrouillé, un seul bouton global
	var c1 := scr.cells["free:1"] as BattlePassScreen.PassCell
	assert_eq(c1.state, BattlePassScreen.PassCell.AVAILABLE)
	assert_true(c1.glow.visible, "Barre violette en haut de la case (maquette)")
	assert_false(c1.dot.visible, "Plus de pastille sur les cases (maquette)")
	assert_eq((scr.cells["free:7"] as BattlePassScreen.PassCell).state, BattlePassScreen.PassCell.LOCKED)
	assert_eq((scr.cells["premium:1"] as BattlePassScreen.PassCell).state, BattlePassScreen.PassCell.PREMIUM_LOCKED)
	assert_eq(scr.find_children("*", "Button", true, false).filter(func(b: Node) -> bool:
		return (b as Button).text.begins_with("Récupérer")).size(), 0, "Pas de bouton « Récupérer » par case")
	assert_true(scr.claim_all_button.visible)
	assert_eq(scr.claim_all_button.text, "Tout récupérer (%d)" % bp.claimable_count())
	# Toucher une case disponible la récupère (une seule fois) et l'affiche en vitrine
	c1.pressed.emit()
	assert_true(bp.is_claimed(1, BattlePassSystem.FREE))
	assert_eq(c1.state, BattlePassScreen.PassCell.CLAIMED)
	assert_true(c1.check.visible)
	assert_eq(int(scr.selected["tier"]), 1)
	assert_false(scr.claim_reward(1, BattlePassSystem.FREE), "Une seule fois")
	# Toucher une case verrouillée : seulement la vitrine
	var c9 := scr.cells["free:9"] as BattlePassScreen.PassCell
	c9.pressed.emit()
	assert_eq(int(scr.selected["tier"]), 9)
	assert_false(bp.is_claimed(9, BattlePassSystem.FREE))
	# Premium puis tout récupérer : le bouton global disparaît
	assert_true(scr.buy_premium())
	assert_false(scr.premium_button.visible)
	assert_true(scr.premium_badge.visible)
	var n := bp.claimable_count()
	assert_eq(scr.claim_all(), n)
	assert_false(scr.claim_all_button.visible, "Rien à récupérer : bouton masqué")
	# Vitrine : skin d'arme sur l'arme
	var w := bp.find_skin(&"wsk_vector_neon")
	scr.select(int(w["tier"]), StringName(w["track"]))
	assert_true(scr.detail_icon.visible)
	assert_false(scr.detail_preview.visible)
	assert_eq(scr.detail_icon.weapon.id, &"smg_vector")
	var f := bp.find_skin(&"char_fantome")
	scr.select(int(f["tier"]), StringName(f["track"]))
	assert_eq(scr.detail_preview.get_sheet_id(), "fantome")
	assert_true(scr.equip_button.visible, "Skin obtenu : Équiper")
