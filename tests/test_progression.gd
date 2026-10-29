extends GutTest
## Niveau de raider (RaiderProgress, Profile.raider_xp) : courbe d'XP, déblocages, emplacements
## d'armes, sac, cartes verrouillées, sauvegarde, écran Progression.

var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	Profile.from_dict({"raider_xp": 0})


func after_each() -> void:
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	SaveManager.save()


func test_courbe_xp() -> void:
	assert_eq(RaiderProgress.level_for_xp(0), 1)
	var to2 := RaiderProgress.xp_to_next(1)
	assert_gt(to2, 0)
	assert_eq(RaiderProgress.level_for_xp(to2 - 1), 1)
	assert_eq(RaiderProgress.level_for_xp(to2), 2)
	assert_gt(RaiderProgress.xp_to_next(5), RaiderProgress.xp_to_next(4), "Chaque niveau coûte plus cher")
	assert_eq(RaiderProgress.xp_total_for(3), RaiderProgress.xp_to_next(1) + RaiderProgress.xp_to_next(2))
	assert_eq(RaiderProgress.level_for_xp(10_000_000), RaiderProgress.max_level(), "Plafond")
	assert_eq(RaiderProgress.level_progress(10_000_000), Vector2i.ZERO)
	assert_eq(RaiderProgress.level_progress(to2 + 10), Vector2i(10, RaiderProgress.xp_to_next(2)))


func test_deblocages_tries_et_lisibles() -> void:
	var list := RaiderProgress.unlocks()
	assert_gt(list.size(), 3)
	for i in range(1, list.size()):
		assert_true(int(list[i - 1]["level"]) <= int(list[i]["level"]), "Triés par niveau")
	for d: Dictionary in list:
		assert_false(RaiderProgress.label_of(d).is_empty(), "Libellé pour %s" % d)
		if d["kind"] == RaiderProgress.KIND_MAP:
			assert_not_null(MapCard.find(StringName(str(d["value"]))), "Carte connue : %s" % d["value"])


func test_emplacements_suivent_le_niveau() -> void:
	var start := int(Balance.get_value("raider", "start_loadout_slots", 2))
	var max_slots := int(Balance.get_value("arsenal", "loadout_slots", 3))
	assert_eq(RaiderProgress.loadout_slots_at(1), mini(start, max_slots))
	assert_eq(Profile.loadout_slots(), RaiderProgress.loadout_slots_at(1), "Niveau 1")
	assert_eq(RaiderProgress.loadout_slots_at(RaiderProgress.max_level()), max_slots, "Plafond [arsenal]")
	Profile.add_raider_xp(RaiderProgress.xp_total_for(RaiderProgress.max_level()))
	assert_eq(Profile.loadout_slots(), max_slots, "Tous les emplacements au niveau max")


func test_gain_de_niveau_donne_les_recompenses() -> void:
	var gems_before := Profile.gems
	var gold_before := Profile.gold
	var levels: Array = []
	Profile.raider_level_up.connect(func(lv: int, _u: Array) -> void: levels.append(lv))
	var target := RaiderProgress.max_level()
	var r := Profile.add_raider_xp(RaiderProgress.xp_total_for(target))
	assert_eq(int(r["level_before"]), 1)
	assert_eq(int(r["level_after"]), target)
	assert_eq(levels.size(), target - 1, "Un signal par niveau franchi")
	var gems := 0
	var gold := 0
	for d: Dictionary in RaiderProgress.unlocks():
		if d["kind"] == RaiderProgress.KIND_GEMS:
			gems += int(d["value"])
		elif d["kind"] == RaiderProgress.KIND_GOLD:
			gold += int(d["value"])
	assert_eq(Profile.gems - gems_before, gems, "Gemmes des paliers données une fois")
	assert_eq(Profile.gold - gold_before, gold, "Or des paliers donné une fois")
	assert_eq((r["unlocks"] as Array).size(), RaiderProgress.unlocks().filter(
		func(d: Dictionary) -> bool: return int(d["level"]) > 1).size())
	# Pas de double don en rajoutant de l'XP au plafond
	Profile.add_raider_xp(1000)
	assert_eq(Profile.gems - gems_before, gems)


func test_sac_plus_lourd_avec_le_niveau() -> void:
	var base := LootDB.getf("inventory_max_weight", 30.0)
	assert_almost_eq(Inventory.from_balance().max_weight, base, 0.01, "Niveau 1 : poids de base")
	Profile.add_raider_xp(RaiderProgress.xp_total_for(RaiderProgress.max_level()))
	assert_almost_eq(Inventory.from_balance().max_weight, base + RaiderProgress.bag_bonus_at(RaiderProgress.max_level()), 0.01)
	assert_gt(RaiderProgress.bag_bonus_at(RaiderProgress.max_level()), 0.0)


func test_carte_verrouillee_par_niveau() -> void:
	var locked: Dictionary = {}
	for d: Dictionary in RaiderProgress.unlocks():
		if d["kind"] == RaiderProgress.KIND_MAP:
			locked = d
			break
	assert_false(locked.is_empty())
	var id := StringName(str(locked["value"]))
	assert_eq(RaiderProgress.required_level(id), int(locked["level"]))
	assert_eq(RaiderProgress.required_level(&"perm_dust_creek"), 1, "Dust Creek libre")
	var tile := MapTile.new({"card": MapCard.find(id)})
	add_child_autofree(tile)
	await wait_frames(1)
	assert_true(tile.is_level_locked())
	assert_false(tile.is_playable())
	Profile.add_raider_xp(RaiderProgress.xp_total_for(int(locked["level"])))
	assert_false(tile.is_level_locked(), "Débloquée au niveau requis")


func test_sauvegarde_et_ancienne_sauvegarde() -> void:
	Profile.add_raider_xp(1234)
	var d := Profile.to_dict()
	assert_eq(int(d["raider_xp"]), 1234)
	Profile.from_dict(d)
	assert_eq(Profile.raider_xp, 1234)
	# Sauvegarde d'avant le niveau : XP estimée depuis les statistiques
	var old := d.duplicate(true)
	old.erase("raider_xp")
	old["stats"] = {"raids": 10, "extractions": 6, "deaths": 4}
	Profile.from_dict(old)
	assert_eq(Profile.raider_xp, RaiderProgress.xp_from_stats({"raids": 10, "extractions": 6}))
	assert_gt(Profile.raider_level(), 1, "Un joueur existant ne repart pas du niveau 1")


func test_xp_de_raid() -> void:
	assert_eq(RaiderProgress.raid_xp(300), roundi(300 * float(Balance.get_value("raider", "xp_ratio", 1.0))))
	assert_eq(RaiderProgress.raid_xp(-5), 0)


func test_ecran_progression() -> void:
	Profile.add_raider_xp(RaiderProgress.xp_total_for(3) + 5)
	var s := (load("res://scenes/ui/menus/progression.tscn") as PackedScene).instantiate() as ProgressionScreen
	add_child_autofree(s)
	await wait_frames(2)
	assert_eq(s.level_label.text, "3")
	assert_eq(s.rows.size(), RaiderProgress.unlocks().size(), "Une ligne par déblocage")
	var nxt := RaiderProgress.next_unlock(3)
	assert_eq(s.next_title.text, RaiderProgress.label_of(nxt))
	assert_eq(s.next_level_label.text, "NIVEAU %d" % int(nxt["level"]))
	var obtained := s.rows.filter(func(r: Dictionary) -> bool: return (r["state"] as Label).text == "OBTENU").size()
	assert_eq(obtained, RaiderProgress.unlocks().filter(func(d: Dictionary) -> bool: return int(d["level"]) <= 3).size())
	assert_eq(ProgressionScreen.xp_gains().size(), 4)
	assert_gt(s.raid_button.pressed.get_connections().size(), 0)
