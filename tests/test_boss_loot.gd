extends GutTest
## Butin des boss et de la hyène (rapport de playtest du 30/10, volet 3) : une table propre par
## boss, boss exemptés du plafond de drop ([loot] drop_cap_exempt_bosses), valeur d'un cadavre de
## boss proche de celle du Shérif, cadavres de Maraudeur (hyène) rarement vides.

const N_BOSS := 3000
const N_HYENA := 6000


## Cadavres tirés comme en jeu (contexte combat, Normal, rez-de-chaussée) :
## {empty, value, epic} moyens par fouille.
func _corpse_stats(kind: StringName, n: int, seed_value: int) -> Dictionary:
	var data := load("res://data/enemies/%s.tres" % kind) as EnemyData
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var keys: Array[StringName] = []
	var empty := 0
	var value := 0.0
	var epic := 0
	for i in n:
		var corpse: Array = LootManager.roll_enemy_loot(data, rng, 1, 0, keys)["corpse"]
		if corpse.is_empty():
			empty += 1
		value += LootRoller.total_value(corpse)
		for e: Dictionary in corpse:
			if (e["item"] as ItemData).rarity >= 3:
				epic += 1
	return {"empty": float(empty) / n, "value": value / n, "epic": float(epic) / n}


func test_chaque_boss_a_sa_table() -> void:
	var bosses := DropCaps.boss_datas()
	assert_gte(bosses.size(), 3, "Shérif, Architecte, Omnistore")
	var kinds: Array[StringName] = []
	for d: EnemyData in bosses:
		kinds.append(d.kind)
		var own := DropCaps.own_table_kind(d)
		assert_eq(own, StringName("enemy_" + String(d.kind)), "%s : table propre" % d.kind)
		var t := LootManager.corpse_table_for(d, &"enemy_mall")
		assert_eq(t.kind, own, "%s : le cadavre utilise sa table, pas celle du biome" % d.kind)
		assert_eq(t.empty_chance, 0.0, "%s : jamais vide" % d.kind)
		assert_gte(t.rolls_min, 4, "%s : au moins 4 objets" % d.kind)
		var rar := {}
		for id: Variant in t.entries:
			var it := LootDB.get_item(StringName(id))
			assert_not_null(it, "%s : objet %s existe" % [t.kind, id])
			if it != null:
				rar[it.rarity] = true
		assert_true(rar.has(3) and rar.has(4), "%s : Épiques et Légendaires possibles" % t.kind)
	for k: StringName in [&"fw_sheriff", &"ss_architect", &"mall_omnistore"]:
		assert_true(kinds.has(k), "%s est un boss" % k)


func test_boss_exemptes_du_plafond() -> void:
	var cfg := LootDB.cfg()
	var saved: Variant = cfg.get_value(LootDB.SECTION, "drop_cap_exempt_bosses", true)
	assert_true(bool(saved), "réglage par défaut : boss exemptés")
	var boss_tables := DropCaps.boss_table_kinds()
	for k: StringName in [&"enemy_fw_sheriff", &"enemy_ss_architect", &"enemy_mall_omnistore"]:
		assert_true(boss_tables.has(k), "%s : table de boss" % k)
		assert_true(DropCaps.is_exempt(k), "%s exemptée" % k)
		assert_eq(DropCaps.cap_for(k, 4), -1.0, "%s : pas de plafond Légendaire" % k)
		assert_eq(DropCaps.cap_for(k, 3), -1.0, "%s : pas de plafond Épique" % k)
	# Les autres sources restent plafonnées (tables de biome partagées comprises).
	for k2: StringName in [&"enemy_fw_bandit", &"enemy_fw_marauder", &"enemy_fw_buffalo", &"enemy_mall",
			&"enemy_space_station", &"chest", &"enemy_drop"]:
		assert_false(DropCaps.is_exempt(k2), "%s plafonnée" % k2)
		assert_almost_eq(DropCaps.cap_for(k2, 4), LootDB.getf("drop_cap_legendary", -1.0), 1e-6)
		assert_almost_eq(DropCaps.cap_for(k2, 3), LootDB.getf("drop_cap_epic", -1.0), 1e-6)
	assert_eq(DropCaps.cap_for(&"chest", 2), -1.0, "Rare et en dessous : pas de plafond")
	# Réglable : sans l'exemption, les boss reviennent sous le plafond.
	cfg.set_value(LootDB.SECTION, "drop_cap_exempt_bosses", false)
	assert_false(DropCaps.is_exempt(&"enemy_fw_sheriff"), "exemption coupée")
	assert_gt(DropCaps.cap_for(&"enemy_ss_architect", 4), 0.0)
	cfg.set_value(LootDB.SECTION, "drop_cap_exempt_bosses", saved)


func test_valeur_des_boss_proche_du_sherif() -> void:
	var sheriff := _corpse_stats(&"fw_sheriff", N_BOSS, 11)
	assert_gt(float(sheriff["value"]), 400.0, "le Shérif paie (%.0f)" % sheriff["value"])
	for k: StringName in [&"ss_architect", &"mall_omnistore"]:
		var s := _corpse_stats(k, N_BOSS, 11)
		var ratio := float(s["value"]) / float(sheriff["value"])
		assert_between(ratio, 0.85, 1.15, "%s : valeur %.0f contre %.0f pour le Shérif" % [k, s["value"], sheriff["value"]])
		assert_eq(float(s["empty"]), 0.0, "%s : cadavre jamais vide" % k)
		var er := float(s["epic"]) / maxf(float(sheriff["epic"]), 0.001)
		assert_between(er, 0.75, 1.25, "%s : Épiques+ %.2f contre %.2f" % [k, s["epic"], sheriff["epic"]])


func test_hyene_cadavres_rarement_vides() -> void:
	var t := LootManager.corpse_table_for(load("res://data/enemies/fw_marauder.tres") as EnemyData)
	assert_eq(t.kind, &"enemy_fw_marauder")
	assert_lte(t.empty_chance, 0.15, "chance de vide de la table")
	var hyena := _corpse_stats(&"fw_marauder", N_HYENA, 7)
	var bandit := _corpse_stats(&"fw_bandit", N_HYENA, 7)
	assert_lt(float(hyena["empty"]), 0.18, "cadavres vides : %.1f %% (45 %% avant)" % (100.0 * hyena["empty"]))
	assert_gte(float(hyena["value"]), 0.8 * float(bandit["value"]),
		"valeur %.0f, au moins comparable au Bandit (%.0f)" % [hyena["value"], bandit["value"]])
