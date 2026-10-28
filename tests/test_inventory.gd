extends GutTest
## Tests de l'inventaire de raid : empilement, capacité (cases + poids), retrait, tri,
## sérialisation, signaux ; écran d'inventaire (pause, rafraîchissement).


func _it(id: StringName) -> ItemData:
	return LootDB.get_item(id)


func test_dimensions_depuis_balance() -> void:
	var inv := Inventory.from_balance()
	assert_eq(inv.columns, LootDB.geti("inventory_columns", 6))
	assert_eq(inv.capacity(), inv.columns * inv.rows)
	assert_true(inv.is_empty())
	assert_not_null(GameState.raid_inventory, "GameState.raid_inventory existe")


func test_empilement() -> void:
	var inv := Inventory.new(4, 2, 999.0)
	var ammo := _it(&"revolver_ammo")
	assert_eq(inv.add_item(ammo, 10), 10)
	assert_eq(inv.add_item(ammo, 15), 15)
	assert_eq(inv.used_slots(), 1, "même pile")
	assert_eq(inv.count_of(&"revolver_ammo"), 25)
	# Dépassement de stack_max → nouvelle pile.
	assert_eq(inv.add_item(ammo, ammo.stack_max), ammo.stack_max)
	assert_eq(inv.used_slots(), 2)
	assert_eq(inv.count_of(&"revolver_ammo"), 25 + ammo.stack_max)


func test_non_empilable_une_case_chacun() -> void:
	var inv := Inventory.new(4, 2, 999.0)
	var gun := _it(&"wpn_smg_mp5")
	assert_eq(gun.stack_max, 1)
	assert_eq(inv.add_item(gun, 3), 3)
	assert_eq(inv.used_slots(), 3)


func test_capacite_en_cases() -> void:
	var inv := Inventory.new(2, 1, 999.0)
	assert_eq(inv.add_item(_it(&"wpn_smg_mp5"), 1), 1)
	assert_eq(inv.add_item(_it(&"wpn_smg_vector"), 1), 1)
	assert_false(inv.can_add(_it(&"gold_bar")))
	assert_eq(inv.add_item(_it(&"gold_bar"), 1), 0, "plein")
	assert_eq(inv.used_slots(), 2)


func test_capacite_en_poids() -> void:
	var bar := _it(&"gold_bar")
	var inv := Inventory.new(10, 10, bar.weight * 2.5)
	assert_eq(inv.add_item(bar, 3), 2, "seuls 2 lingots rentrent")
	assert_lte(inv.total_weight(), inv.max_weight)
	assert_eq(inv.space_for(bar), 0)


func test_retrait() -> void:
	var inv := Inventory.new(4, 2, 999.0)
	inv.add_item(_it(&"bandage"), 4)
	inv.add_item(_it(&"whisky"), 1)
	assert_eq(inv.remove_item(&"bandage", 3), 3)
	assert_eq(inv.count_of(&"bandage"), 1)
	assert_eq(inv.remove_item(&"bandage", 5), 1, "on ne retire que ce qu'on a")
	assert_false(inv.has_item(&"bandage"))
	assert_eq(inv.remove_item(&"inconnu", 1), 0)
	assert_true(inv.remove_at(inv.capacity() - 1).is_empty(), "case vide → rien")
	var idx := -1
	for i in inv.capacity():
		if not inv.get_slot(i).is_empty():
			idx = i
	var got := inv.remove_at(idx)
	assert_eq((got["item"] as ItemData).id, &"whisky")
	assert_true(inv.is_empty())


func test_signaux_changed() -> void:
	var inv := Inventory.new()
	watch_signals(inv)
	inv.add_item(_it(&"gold_nugget"), 2)
	assert_signal_emitted(inv, "changed")
	assert_signal_emitted_with_parameters(inv, "item_added", [_it(&"gold_nugget"), 2])
	inv.remove_item(&"gold_nugget", 1)
	assert_signal_emit_count(inv, "changed", 2)
	inv.add_item(_it(&"gold_nugget"), 0)
	assert_signal_emit_count(inv, "changed", 2, "rien ajouté → pas de signal")


func test_tri_regroupe_et_ordonne() -> void:
	var inv := Inventory.new(6, 2, 999.0)
	inv.add_item(_it(&"silver_dollars"), 5)
	inv.add_item(_it(&"wpn_rifle_aug"), 1)
	inv.add_item(_it(&"pocket_watch"), 1)
	inv.slots[8] = {"item": _it(&"silver_dollars"), "count": 7}
	inv.sort()
	assert_eq((inv.get_slot(0)["item"] as ItemData).id, &"wpn_rifle_aug", "Légendaire en premier")
	assert_eq(inv.count_of(&"silver_dollars"), 12)
	assert_eq(inv.used_slots(), 3, "piles regroupées")


func test_valeur_totale_et_serialisation() -> void:
	var inv := Inventory.new()
	inv.add_item(_it(&"gold_nugget"), 2)
	inv.add_item(_it(&"pocket_watch"), 1)
	assert_eq(inv.total_value(), _it(&"gold_nugget").value * 2 + _it(&"pocket_watch").value)
	var data := inv.to_array()
	var inv2 := Inventory.new()
	inv2.from_array(data)
	assert_eq(inv2.count_of(&"gold_nugget"), 2)
	assert_eq(inv2.total_value(), inv.total_value())


func test_ecran_inventaire_pause_et_affichage() -> void:
	var saved := GameState.raid_inventory
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.add_item(_it(&"whisky"), 1)
	var screen := InventoryScreen.new()
	add_child_autofree(screen)
	await wait_frames(1)
	assert_false(screen.is_open())
	screen.open()
	assert_true(screen.is_open())
	assert_eq(get_tree().paused, LootDB.getf("inventory_time_scale", 0.0) <= 0.0, "jeu en pause")
	assert_eq(screen.get_selected_item().id, &"whisky")
	screen._drop_selected()
	assert_true(GameState.raid_inventory.is_empty(), "Jeter retire l'objet")
	screen.close()
	assert_false(get_tree().paused, "pause levée")
	GameState.raid_inventory = saved


func test_fiche_arme_dans_le_detail() -> void:
	var saved := GameState.raid_inventory
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.add_item(_it(&"wpn_rifle_m4a1"), 1)
	var screen := InventoryScreen.new()
	add_child_autofree(screen)
	await wait_frames(1)
	screen.open()
	assert_true(screen.get_selected_item().is_weapon())
	assert_true(screen._equip_btn.visible, "bouton Équiper visible pour une arme")
	var labels := PackedStringArray()
	for c: Node in screen._facts_grid.get_children():
		labels.append((c as Label).text)
	for k: String in ["Dégâts", "Cadence", "Chargeur", "DPS"]:
		assert_true(labels.has(k), "fiche : %s" % k)
	screen.close()
	GameState.raid_inventory = saved


## Faux joueur : API equip_into_current_slot du contrat.
class FakePlayer extends Node2D:
	var weapon: WeaponData = null
	var current_slot: int = 0
	func get_weapons() -> Array[WeaponData]:
		var a: Array[WeaponData] = [weapon]
		return a
	func equip_into_current_slot(w: WeaponData) -> WeaponData:
		var old := weapon
		weapon = w
		return old


func test_equiper_echange_avec_l_arme_courante() -> void:
	var saved_inv := GameState.raid_inventory
	var saved_player := GameState.player
	var fp := FakePlayer.new()
	fp.weapon = WeaponCatalog.get_weapon(&"smg_mp5")
	add_child_autofree(fp)
	GameState.player = fp
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.add_item(_it(&"wpn_rifle_ak47"), 1)
	var screen := InventoryScreen.new()
	add_child_autofree(screen)
	await wait_frames(1)
	screen.open()
	assert_true(screen._equip_selected(), "échange effectué")
	assert_eq(fp.weapon.id, &"rifle_ak47", "arme équipée")
	assert_eq(GameState.raid_inventory.count_of(&"wpn_rifle_ak47"), 0, "l'objet quitte le sac")
	assert_eq(GameState.raid_inventory.count_of(&"wpn_smg_mp5"), 1, "l'arme remplacée revient dans le sac")
	# Sac plein : l'arme remplacée ne rentre pas → rien ne se passe.
	GameState.raid_inventory = Inventory.new(1, 1, 0.5)
	GameState.raid_inventory.slots[0] = {"item": _it(&"wpn_sniper_m82"), "count": 1}
	screen.bind(GameState.raid_inventory)
	screen.selected = 0
	assert_false(screen._equip_selected(), "sac plein : refus")
	assert_eq(fp.weapon.id, &"rifle_ak47", "arme inchangée")
	assert_eq(GameState.raid_inventory.count_of(&"wpn_sniper_m82"), 1, "objet resté dans le sac")
	screen.close()
	GameState.raid_inventory = saved_inv
	GameState.player = saved_player


class FakeGadgetPlayer extends Node2D:
	var weapon: WeaponData = null
	var gadget: WeaponData = null
	func get_gadget() -> WeaponData:
		return gadget
	func get_gadget_charges() -> int:
		return gadget.charges if gadget != null else 0
	func equip_gadget(w: WeaponData) -> WeaponData:
		var old := gadget
		gadget = w
		return old


func test_equiper_un_equipement_va_dans_l_emplacement_gadget() -> void:
	var saved_inv := GameState.raid_inventory
	var saved_player := GameState.player
	var fp := FakeGadgetPlayer.new()
	fp.weapon = WeaponCatalog.get_weapon(&"smg_mp5")
	fp.gadget = WeaponCatalog.get_weapon(&"gadget_frag")
	add_child_autofree(fp)
	GameState.player = fp
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.add_item(_it(&"wpn_gadget_c4"), 1)
	var screen := InventoryScreen.new()
	add_child_autofree(screen)
	await wait_frames(1)
	screen.open()
	assert_true(screen._equip_btn.visible)
	assert_true(screen._equip_selected())
	assert_eq(fp.gadget.id, &"gadget_c4", "équipement remplacé")
	assert_eq(fp.weapon.id, &"smg_mp5", "arme intacte")
	assert_eq(GameState.raid_inventory.count_of(&"wpn_gadget_frag"), 1, "ancien équipement dans le sac")
	screen.close()
	GameState.raid_inventory = saved_inv
	GameState.player = saved_player
