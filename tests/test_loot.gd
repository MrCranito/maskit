extends GutTest
## Tests du butin : données (objets, icônes, tables), tirages pondérés déterministes,
## influence de la salle super_loot / difficulté, conteneurs, clefs et portes.

const CONTAINER_KINDS := [&"crate", &"barrel", &"chest", &"cupboard", &"wardrobe", &"wagon", &"stagecoach", &"corpse", &"safe"]
const KEY_IDS := [&"key_bank_vault", &"key_sheriff_armory", &"key_saloon_suite", &"key_hotel_suite", &"key_mine_vault"]


func _roll(kind: StringName, seed_value: int, ctx: LootRoller.Context) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return LootRoller.roll(LootDB.get_table(kind), rng, ctx)


func _sig(entries: Array[Dictionary]) -> String:
	var parts := PackedStringArray()
	for e: Dictionary in entries:
		parts.append("%s:%d" % [(e["item"] as ItemData).id, int(e["count"])])
	return ",".join(parts)


# --- Données ---------------------------------------------------------------------

func test_au_moins_25_objets_et_icones() -> void:
	var items := LootDB.all_items()
	assert_gte(items.size(), 25, "au moins 25 objets Far West")
	for it: ItemData in items:
		assert_ne(it.id, &"", "id renseigné")
		assert_false(it.display_name.is_empty(), "%s : nom" % it.id)
		assert_false(it.description.is_empty(), "%s : description" % it.id)
		if it.is_weapon():
			# Objet arme : icône vide, l'UI passe par WeaponCatalog.icon_for (ou un pictogramme).
			assert_true(WeaponCatalog.has_weapon(it.weapon_id), "%s : arme %s connue" % [it.id, it.weapon_id])
		else:
			assert_not_null(it.icon, "%s : icône chargée" % it.id)
		assert_between(it.rarity, 0, 4, "%s : rareté 0..4" % it.id)
		assert_true(ItemData.TYPES.has(it.type), "%s : type connu (%s)" % [it.id, it.type])
		assert_gte(it.stack_max, 1)
		assert_gt(it.value, 0)
		assert_lte(it.drop_min, it.drop_max)


func test_toutes_les_raretes_et_types_representes() -> void:
	var rar := {}
	var types := {}
	for it: ItemData in LootDB.all_items():
		rar[it.rarity] = true
		types[it.type] = true
	assert_eq(rar.size(), 5, "les 5 raretés existent")
	for t: StringName in ItemData.TYPES:
		assert_true(types.has(t), "type %s présent" % t)


func test_clefs_speciales_existent() -> void:
	for k: StringName in KEY_IDS:
		var it := LootDB.get_item(k)
		assert_not_null(it, "clef %s" % k)
		if it != null:
			assert_true(it.is_key())


func test_une_table_par_conteneur_et_ids_valides() -> void:
	for k: StringName in CONTAINER_KINDS:
		var t := LootDB.get_table(k)
		assert_not_null(t, "table %s" % k)
		if t == null:
			continue
		assert_false(t.entries.is_empty(), "table %s non vide" % k)
		for id: Variant in t.entries:
			assert_true(LootDB.has_item(StringName(id)), "%s : objet %s existe" % [k, id])
	# Chaque type de conteneur du monde 1 a sa table.
	var world := load("res://data/worlds/world_01_far_west.tres") as WorldData
	for k2: StringName in world.container_kinds:
		assert_not_null(LootDB.get_table(k2), "table pour %s (WorldData)" % k2)


func test_sprites_des_conteneurs_et_cachettes() -> void:
	for k: StringName in LootContainer.DEFS:
		if k == &"drop":
			continue
		assert_not_null(LootContainer.get_texture(k, false), "sprite %s" % k)
		assert_not_null(LootContainer.get_texture(k, true), "sprite %s ouvert" % k)
	for h: StringName in HidingSpot.KINDS:
		assert_not_null(HidingSpot.get_texture(h), "sprite cachette %s" % h)


func test_section_loot_balance() -> void:
	assert_gt(LootDB.getf("search_time", -1.0), 0.0)
	assert_eq(LootDB.get_arr("super_loot_rarity_mult", []).size(), 5)
	var kc := LootDB.get_arr("key_drop_chance", [])
	assert_eq(kc.size(), 5)
	for v: Variant in kc:
		assert_between(float(v), 0.005, 0.02, "clef : 0,5 % à 2 %")


# --- Tirages -----------------------------------------------------------------------

func test_tirage_deterministe_avec_seed() -> void:
	var ctx := LootRoller.Context.make(1, 0, &"loot")
	for k: StringName in CONTAINER_KINDS:
		for s in [1, 42, 999]:
			assert_eq(_sig(_roll(k, s, ctx)), _sig(_roll(k, s, ctx)), "%s seed %d" % [k, s])
	# Des seeds différentes ne donnent pas toujours le même contenu.
	var seen := {}
	for s2 in 30:
		seen[_sig(_roll(&"chest", s2, ctx))] = true
	assert_gt(seen.size(), 10, "variété des tirages")


func test_tirage_respecte_les_bornes() -> void:
	var ctx := LootRoller.Context.make(1, 0, &"combat")
	for s in 200:
		var e := _roll(&"crate", s, ctx)
		var t := LootDB.get_table(&"crate")
		assert_lte(e.size(), t.rolls_max)
		var ids := {}
		for x: Dictionary in e:
			ids[(x["item"] as ItemData).id] = true
			assert_gte(int(x["count"]), 1)
		assert_eq(ids.size(), e.size(), "pas de doublon")


func test_super_loot_plus_riche() -> void:
	var normal := LootRoller.Context.make(1, 0, &"combat")
	var sup := LootRoller.Context.make(1, 0, &"super_loot")
	var n_epic := 0
	var s_epic := 0
	var n_val := 0
	var s_val := 0
	for s in 400:
		var a := _roll(&"chest", s, normal)
		var b := _roll(&"chest", s, sup)
		n_val += LootRoller.total_value(a)
		s_val += LootRoller.total_value(b)
		for e: Dictionary in a:
			if (e["item"] as ItemData).rarity >= 3:
				n_epic += 1
		for e2: Dictionary in b:
			if (e2["item"] as ItemData).rarity >= 3:
				s_epic += 1
	assert_gt(s_epic, n_epic * 2, "super_loot : Épique/Légendaire très augmentés (%d vs %d)" % [s_epic, n_epic])
	assert_gt(s_val, n_val, "super_loot : valeur totale supérieure")


func test_difficulte_et_etage_augmentent_les_raretes() -> void:
	var it_leg: ItemData = null
	for it: ItemData in LootDB.all_items():
		if it.rarity == 4:
			it_leg = it
			break
	var easy := LootRoller.rarity_multiplier(4, LootRoller.Context.make(0, 0, &"combat"))
	var hard := LootRoller.rarity_multiplier(4, LootRoller.Context.make(4, 0, &"combat"))
	var deep := LootRoller.rarity_multiplier(4, LootRoller.Context.make(0, -1, &"combat"))
	assert_gt(hard, easy, "difficulté → Légendaire plus probable")
	assert_gt(deep, easy, "étage → Légendaire plus probable")
	assert_almost_eq(LootRoller.rarity_multiplier(0, LootRoller.Context.make(4, 0, &"combat")), 1.0, 0.001, "Commun inchangé")
	assert_not_null(it_leg)


func test_pick_weighted_suit_les_poids() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var w := {&"a": 9.0, &"b": 1.0}
	var a := 0
	for i in 2000:
		if LootRoller.pick_weighted(w, rng) == &"a":
			a += 1
	assert_between(a, 1700, 1900, "~90 %")


func test_drop_ennemi_clef_rare() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var keys: Array[StringName] = [&"key_bank_vault"]
	var n_keys := 0
	var n := 20000
	for i in n:
		for e: Dictionary in LootManager.roll_enemy_drop(rng, 4, 0, keys):
			if (e["item"] as ItemData).is_key():
				n_keys += 1
	var rate := float(n_keys) / n
	assert_between(rate, 0.012, 0.028, "≈ 2 %% en Cauchemar (%.4f)" % rate)


# --- Conteneur ------------------------------------------------------------------------

func _make_container(kind: StringName, room_type: StringName = &"loot") -> LootContainer:
	var c := LootContainer.create(kind, Vector2(100, 100))
	c.room_type = room_type
	c.loot_seed = 1234
	add_child_autofree(c)
	return c


func test_conteneur_groupes_et_libelles() -> void:
	var c := _make_container(&"chest")
	assert_true(c.is_in_group(&"containers"))
	assert_true(c.is_in_group(&"fog_hideable"))
	assert_eq(c.get_interact_label(), "Fouiller")
	assert_false(c.is_processing(), "pas de _process au repos")


func test_fouille_complete_puis_vidage() -> void:
	var c := _make_container(&"chest")
	var p := Node2D.new()
	add_child_autofree(p)
	p.global_position = c.global_position
	watch_signals(c)
	c.search_time = 0.2
	c.interact(p)
	assert_true(c.is_searching())
	assert_true(c.is_processing(), "_process actif pendant la fouille")
	await wait_seconds(0.35)
	assert_signal_emitted(c, "opened")
	assert_eq(c.state, LootContainer.State.OPENED)
	assert_false(c.is_processing())
	assert_eq(c.get_interact_label(), "Ouvrir")
	var inv := Inventory.new(6, 4, 999.0)
	var expected := 0
	for e: Dictionary in c.entries:
		expected += int(e["count"])
	assert_gt(expected, 0, "un coffre de salle de fouille n'est jamais vide")
	assert_eq(c.take_all(inv), expected)
	assert_true(c.is_emptied(), "conteneur vidé")
	assert_false(c.can_interact())


func test_fouille_interrompue_si_on_bouge_ou_touche() -> void:
	var c := _make_container(&"crate")
	var p := Node2D.new()
	add_child_autofree(p)
	c.search_time = 1.0
	c.start_search(p)
	await wait_physics_frames(2)
	p.global_position += Vector2(40, 0)
	await wait_physics_frames(2)
	assert_eq(c.state, LootContainer.State.CLOSED, "déplacement → fouille annulée")
	p.global_position -= Vector2(40, 0)
	c.start_search(p)
	EventBus.player_damaged.emit(5.0, 95.0, 100.0)
	assert_eq(c.state, LootContainer.State.CLOSED, "dégâts → fouille annulée")
	c.start_search(p)
	c.release_interact(p)
	assert_eq(c.state, LootContainer.State.CLOSED, "relâcher → fouille annulée")


func test_meme_seed_meme_contenu() -> void:
	var a := _make_container(&"stagecoach")
	var b := _make_container(&"stagecoach")
	a.force_open()
	b.force_open()
	assert_eq(_sig(a.entries), _sig(b.entries))


func test_inventaire_plein_ne_vide_pas() -> void:
	var c := _make_container(&"chest")
	c.force_open()
	var inv := Inventory.new(1, 1, 0.001)
	assert_eq(c.take_all(inv), 0)
	assert_eq(c.state, LootContainer.State.OPENED, "reste ouvert avec son contenu")


# --- Clefs et portes -----------------------------------------------------------------

func test_clef_ouvre_porte_verrouillee_et_est_consommee() -> void:
	var d := FloorLayout.Door.new()
	d.cell = Vector2i(5, 5)
	d.state = FloorLayout.DoorState.LOCKED
	d.key_id = &"key_bank_vault"
	var door := (load("res://scenes/dungeon/door.tscn") as PackedScene).instantiate() as DoorNode
	door.setup(d)
	add_child_autofree(door)
	var inv := Inventory.new()
	assert_false(LootManager.try_unlock_with_inventory(door, inv), "sans clef : reste fermée")
	assert_true(door.is_locked())
	inv.add_item(LootDB.get_item(&"key_sheriff_armory"))
	assert_false(LootManager.try_unlock_with_inventory(door, inv), "mauvaise clef")
	inv.add_item(LootDB.get_item(&"key_bank_vault"))
	assert_true(LootManager.try_unlock_with_inventory(door, inv), "bonne clef")
	assert_false(door.is_locked())
	assert_true(door.is_open())
	assert_false(inv.has_item(&"key_bank_vault"), "clef consommée")
	assert_true(inv.has_item(&"key_sheriff_armory"), "l'autre clef reste")


func test_spawner_place_conteneurs_et_cachettes() -> void:
	var L := FloorLayout.make_sample()
	L.add_spawn(L.hiding_spot_spawns, Vector2i(20, 14), &"barrel", 0)
	var root := Node2D.new()
	add_child_autofree(root)
	var loot := LootSpawner.spawn_for_floor(L, root, 99, 1)
	var n_c := 0
	var n_h := 0
	for ch: Node in loot.get_children():
		if ch is LootContainer:
			n_c += 1
		elif ch is HidingSpot:
			n_h += 1
	assert_eq(n_c, L.container_spawns.size())
	assert_eq(n_h, 1)


# --- Taux de drop des clefs par difficulté (phase 5) ---------------------------------------

func test_taux_de_clef_par_difficulte() -> void:
	var chances: Array = LootDB.cfg().get_value(LootDB.SECTION, "key_drop_chance", [])
	assert_eq(chances.size(), 5, "un taux par difficulté")
	for d in chances.size():
		var p := float(chances[d])
		assert_between(p, 0.005, 0.02, "taux dans [0,5 %% ; 2 %%] (difficulté %d)" % d)
		if d > 0:
			assert_gte(p, float(chances[d - 1]), "le taux monte avec la difficulté")
		var rng := RandomNumberGenerator.new()
		rng.seed = 100 + d
		var keys: Array[StringName] = [&"key_bank_vault", &"key_saloon_suite"]
		var n := 40000
		var got := 0
		for i in n:
			for e: Dictionary in LootManager.roll_enemy_drop(rng, d, 0, keys):
				if (e["item"] as ItemData).is_key():
					got += 1
		var rate := float(got) / n
		assert_between(rate, p * 0.75, p * 1.25, "taux observé %.4f ≈ %.4f (difficulté %d)" % [rate, p, d])


# --- Clefs emportées depuis la réserve ------------------------------------------------------

func test_clefs_de_la_reserve_emportees_puis_rendues_ou_perdues() -> void:
	var saved := Profile.to_dict()
	var saved_inv: Variant = GameState.get("raid_inventory")
	Profile.from_dict({"items": {"key_bank_vault": 1, "bandage": 1}})
	Profile.add_weapon(&"pistol_p9")
	assert_false(Profile.pack_keys, "par défaut : les clefs restent en réserve")
	assert_eq(Profile.keys_in_reserve().size(), 1)
	assert_true(Profile.keys_preview().is_empty(), "rien d'emporté tant que le choix est « non »")
	Profile.set_pack_keys(true)
	var bag := Inventory.from_balance()
	GameState.set("raid_inventory", bag)
	Profile.start_raid()
	assert_true(bag.has_item(&"key_bank_vault"), "clef dans le sac de raid")
	assert_eq(Profile.item_count(&"key_bank_vault"), 0, "la clef a quitté la réserve")
	Profile.finish_extraction([] as Array[StringName], bag)
	assert_eq(Profile.item_count(&"key_bank_vault"), 1, "extraction : clef non utilisée rendue")
	# Mort : la clef emportée est perdue
	var bag2 := Inventory.from_balance()
	GameState.set("raid_inventory", bag2)
	Profile.start_raid()
	assert_true(bag2.has_item(&"key_bank_vault"))
	Profile.finish_death()
	assert_eq(Profile.item_count(&"key_bank_vault"), 0, "mort : clef perdue")
	GameState.set("raid_inventory", saved_inv)
	Profile.from_dict(saved)


# --- Ouverture (maquette « Butin révélé ») ------------------------------------------------

func _entries(ids: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: StringName in ids:
		out.append({"item": LootDB.get_item(id), "count": 1})
	return out


func test_ouverture_montre_les_plus_rares_d_abord() -> void:
	var e := _entries([&"bandage", &"pearl_necklace", &"pocket_watch", &"gold_nugget"])
	var shown := ChestReveal.pick(e, 3)
	assert_eq(shown.size(), 3, "au plus N objets montrés")
	assert_eq(shown[0].id, &"pearl_necklace", "le plus rare en premier")
	for i in range(1, shown.size()):
		assert_lte(shown[i].rarity, shown[i - 1].rarity, "rareté décroissante")
	var order := InventoryLootWindow.display_order(e)
	assert_eq((e[order[0]]["item"] as ItemData).id, &"pearl_necklace", "fenêtre de butin : le plus rare en haut")
	assert_eq((e[order[order.size() - 1]]["item"] as ItemData).id, &"bandage", "le moins rare en bas")


func test_ouverture_lance_l_effet_puis_le_libere() -> void:
	var c := LootContainer.create(&"chest", Vector2.ZERO)
	c.has_preset = true
	c.preset_entries = _entries([&"pearl_necklace", &"bandage"])
	add_child_autofree(c)
	await wait_frames(1)
	c.force_open()
	await wait_frames(1)
	var rv := c.get_node_or_null(^"ChestReveal")
	assert_not_null(rv, "effet d'ouverture ajouté")
	assert_eq(rv.get_child_count(), 3, "faisceau + 2 icônes")
	await wait_seconds(LootDB.getf("reveal_duration", 1.6) + 0.6)
	assert_null(c.get_node_or_null(^"ChestReveal"), "effet libéré à la fin")
