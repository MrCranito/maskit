extends GutTest
## Boutique (scripts/cosmetics/store.gd) : premier achat doublé une seule fois, packs à contenu
## (skins de boutique uniquement, doublons remboursés, pack « once »), coffres de skins GRATUITS
## (gagnés toutes les N extractions, taux affichés respectés, garantie, doublons remboursés).
## La sauvegarde est isolée.

var _saved_profile: Dictionary = {}
var _saved_data: Dictionary = {}


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_data = SaveManager.data.duplicate(true)
	Profile.from_dict({"gems": 0})


func after_each() -> void:
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_data
	SaveManager.save()
	WeaponSkin.enabled_override = -1


func _rng(seed_v: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	return r


# --- Gemmes ---------------------------------------------------------------------------

func test_premier_achat_double_une_seule_fois() -> void:
	assert_true(Store.first_bonus_available())
	var g0 := int(Store.packs()[0]["gems"])
	assert_eq(Store.pack_gems_now(0), g0 * 2, "Premier pack : gemmes doublées")
	assert_true(Store.purchase_pack(0))
	assert_eq(Profile.gems, g0 * 2)
	assert_false(Store.first_bonus_available())
	assert_eq(Store.pack_gems_now(0), g0)
	assert_true(Store.purchase_pack(0))
	assert_eq(Profile.gems, g0 * 3, "Deuxième achat sans bonus")


func test_premier_pack_achete_un_skin() -> void:
	var cheapest := 1 << 30
	for k: StringName in [SkinData.KIND_CHARACTER, SkinData.KIND_WEAPON]:
		for s: SkinData in SkinData.shop_skins(k):
			if s.price_gems > 0:
				cheapest = mini(cheapest, s.price_gems)
	assert_gte(Store.pack_gems_now(0), cheapest, "Le plus petit pack, doublé au premier achat, paie le skin le moins cher")


func test_bonus_premier_achat_sauvegarde() -> void:
	Store.purchase_pack(0)
	var d := Profile.to_dict()
	Profile.from_dict({})
	assert_true(Store.first_bonus_available())
	Profile.from_dict(d)
	assert_false(Store.first_bonus_available(), "Bonus consommé relu depuis la sauvegarde")


func test_packs_de_gemmes_rapport_croissant() -> void:
	var packs := Store.packs()
	for i in range(1, packs.size()):
		var a := float(packs[i - 1]["gems"]) / float(String(packs[i - 1]["price"]).replace(",", ".").to_float())
		var b := float(packs[i]["gems"]) / float(String(packs[i]["price"]).replace(",", ".").to_float())
		assert_gt(b, a, "Les gros packs donnent plus de gemmes par euro")


# --- Packs à contenu ------------------------------------------------------------------

func test_packs_a_contenu_sans_skin_du_pass() -> void:
	var list := Store.bundles()
	assert_gte(list.size(), 3)
	for b: Dictionary in list:
		assert_false((b["skins"] as Array).is_empty(), "%s contient au moins un skin" % b["name"])
		for id: StringName in b["skins"]:
			var s := SkinData.get_skin(id)
			assert_false(s.is_pass(), "%s : %s ne vient pas du pass de combat" % [b["name"], id])
		assert_gt(Store.bundle_value(b), int(b["ref_gems"]), "%s vaut plus que les gemmes au même prix" % b["name"])


func test_pack_recrue_une_seule_fois() -> void:
	var b := Store.bundle(&"recrue")
	assert_false(b.is_empty())
	assert_true(bool(b["once"]))
	var r := Store.purchase_bundle(&"recrue")
	assert_eq((r["skins"] as Array).size(), (b["skins"] as Array).size())
	for id: StringName in b["skins"]:
		assert_true(Profile.owns_skin(id))
	assert_eq(Profile.gems, int(b["gems"]))
	assert_false(Store.bundle_available(&"recrue"))
	assert_true(Store.purchase_bundle(&"recrue").is_empty(), "Pas de deuxième achat")


func test_pack_doublon_rembourse() -> void:
	var b := Store.bundle(&"commando")
	var owned: StringName = (b["skins"] as Array)[0]
	Profile.grant_skin(owned)
	var r := Store.purchase_bundle(&"commando")
	assert_eq(int(r["refunded"]), SkinData.get_skin(owned).price_gems, "Skin déjà possédé remboursé à son prix")
	assert_eq(Profile.gems, int(b["gems"]) + int(r["refunded"]))
	assert_false((r["skins"] as Array).has(owned))


# --- Coffres --------------------------------------------------------------------------

func test_coffre_gagne_toutes_les_n_extractions() -> void:
	var n := Store.chest_every()
	for i in n - 1:
		assert_false(Profile.add_chest_progress())
	assert_eq(Profile.free_chests, 0)
	assert_true(Profile.add_chest_progress())
	assert_eq(Profile.free_chests, 1)
	assert_eq(Profile.chest_progress, 0)


func test_extraction_compte_pour_le_coffre() -> void:
	Profile.chest_progress = Store.chest_every() - 1
	var res := Profile.finish_extraction([], null)
	assert_true(bool(res["chest"]))
	assert_eq(Profile.free_chests, 1)


func test_pas_de_coffre_sans_stock() -> void:
	assert_true(Store.open_chest(_rng(1)).is_empty(), "Les coffres ne s'achètent pas : sans stock, rien")
	assert_eq(Profile.gems, 0)


func test_coffre_donne_un_skin_de_boutique() -> void:
	Profile.free_chests = 1
	var r := Store.open_chest(_rng(3))
	assert_false(r.is_empty())
	var s: SkinData = r["skin"]
	assert_false(s.is_pass())
	assert_true(Profile.owns_skin(s.id))
	assert_eq(Profile.free_chests, 0)


func test_taux_des_coffres() -> void:
	var rng := _rng(42)
	var counts := {}
	var n := 20000
	for i in n:
		Profile.chest_pity_count = 0
		var r := Store.roll_chest_rarity(rng)
		counts[r] = int(counts.get(r, 0)) + 1
	for e: Array in Store.chest_odds():
		var got := float(counts.get(int(e[0]), 0)) / n
		assert_almost_eq(got, float(e[1]), maxf(float(e[1]) * 0.15, 0.01), "Taux affiché de la rareté %d" % e[0])


func test_garantie_epique() -> void:
	var rng := _rng(7)
	Profile.chest_pity_count = Store.chest_pity() - 1
	for i in 200:
		Profile.chest_pity_count = Store.chest_pity() - 1
		assert_gte(Store.roll_chest_rarity(rng), int(Balance.get_value("chests", "pity_min_rarity", 3)))


func test_garantie_remise_a_zero() -> void:
	Profile.free_chests = 50
	var rng := _rng(11)
	var since := 0
	for i in 50:
		var r := Store.open_chest(rng)
		if int(r["rarity"]) >= 3:
			since = 0
		else:
			since += 1
		assert_lt(since, Store.chest_pity(), "Jamais %d coffres d'affilée sans Épique" % Store.chest_pity())
		assert_eq(Profile.chest_pity_count, since)


func test_coffre_doublon_rembourse() -> void:
	for r in [2, 3, 4]:
		for s: SkinData in Store.chest_pool(r):
			Profile.grant_skin(s.id)
	Profile.free_chests = 1
	var res := Store.open_chest(_rng(5))
	assert_true(bool(res["duplicate"]))
	var s: SkinData = res["skin"]
	assert_eq(int(res["refunded"]), int(round(s.price_gems * float(Balance.get_value("chests", "duplicate_refund", 0.5)))))
	assert_eq(Profile.gems, int(res["refunded"]))


func test_coffres_sauvegardes() -> void:
	Profile.free_chests = 2
	Profile.chest_progress = 3
	Profile.chest_pity_count = 4
	var d := Profile.to_dict()
	Profile.from_dict({})
	Profile.from_dict(d)
	assert_eq(Profile.free_chests, 2)
	assert_eq(Profile.chest_progress, 3)
	assert_eq(Profile.chest_pity_count, 4)
