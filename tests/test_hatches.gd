extends GutTest
## Trappes d'urgence et clef de trappe (scripts/loot/hatch_keys.gd, ExtractionZone kind hatch) :
## verrou, clef consommée (sac puis gadget), gadget jamais lancé, drops, retour en réserve
## comme gadget, trappes absentes de la mini-carte, extractions des autres étages en
## transparence.


class GadgetStub extends Node:
	var charges: int = 0

	func has_hatch_key_gadget() -> bool:
		return charges > 0

	func consume_hatch_key_gadget() -> bool:
		if charges <= 0:
			return false
		charges -= 1
		return true


func _hatch_spec() -> ExtractionPlan.Spec:
	var s := ExtractionPlan.Spec.new()
	s.cells.assign([Vector2i(4, 4), Vector2i(5, 4), Vector2i(4, 5), Vector2i(5, 5)])
	s.kind = ExtractionPlan.KIND_HATCH
	s.name = "Trappe Nord"
	return s


func test_ressources_de_la_clef() -> void:
	var it := LootDB.get_item(HatchKeys.ITEM_ID)
	assert_not_null(it, "objet hatch_key")
	assert_eq(it.type, ItemData.TYPE_KEY)
	assert_eq(it.reserve_weapon_id(), HatchKeys.GADGET_ID, "devient le gadget en réserve")
	var g := WeaponCatalog.get_weapon(HatchKeys.GADGET_ID)
	assert_not_null(g, "gadget gadget_hatch_key")
	assert_true(g.is_gadget())
	assert_eq(g.gadget_kind, WeaponData.GADGET_HATCH_KEY)
	assert_eq(g.charges, 1)
	assert_not_null(it.icon, "icône rendue sous Blender")


func test_trappe_verrouillee_puis_ouverte() -> void:
	var zones := ExtractionZone.create_from_specs([_hatch_spec()])
	var z: ExtractionZone = zones[0]
	add_child_autofree(z)
	z.update_clock(0.0)
	assert_true(z.is_hatch())
	assert_true(z.locked)
	assert_false(z.is_open(), "verrouillée : pas de canalisation")
	assert_false(z.is_hatch_open_visual())
	assert_true(z.is_in_group(&"fog_hideable"), "cachée hors du champ de vision")
	assert_true(z.unlock())
	assert_true(z.is_open())
	assert_true(z.is_hatch_open_visual(), "rendu ouvert")
	assert_false(z.unlock(), "déjà ouverte")


func test_clef_du_sac_puis_gadget() -> void:
	var inv := Inventory.new()
	var stub := GadgetStub.new()
	add_child_autofree(stub)
	stub.charges = 1
	inv.add_item(LootDB.get_item(HatchKeys.ITEM_ID), 1)
	assert_eq(HatchKeys.count(inv, stub), 2)
	assert_eq(HatchKeys.consume(inv, stub), "bag", "le sac d'abord")
	assert_eq(inv.count_of(HatchKeys.ITEM_ID), 0)
	assert_eq(HatchKeys.consume(inv, stub), "gadget")
	assert_eq(stub.charges, 0)
	assert_eq(HatchKeys.consume(inv, stub), "", "plus de clef")


func test_tirages_de_drop() -> void:
	assert_true(HatchKeys.roll(12, 0.0).is_empty())
	var e := HatchKeys.roll(12, 1.0)
	assert_eq((e["item"] as ItemData).id, HatchKeys.ITEM_ID)
	assert_eq(HatchKeys.roll(99, 0.5), HatchKeys.roll(99, 0.5), "déterministe (coop)")
	assert_gt(HatchKeys.enemy_chance(0, false), 0.0)
	assert_almost_eq(HatchKeys.enemy_chance(2, true),
		HatchKeys.enemy_chance(2, false) * Balance.get_float("extraction", "hatch_key_elite_mult", 4.0), 0.0001)
	assert_gt(HatchKeys.container_chance(&"chest"), 0.0, "coffres")
	assert_eq(HatchKeys.container_chance(&"barrel"), 0.0, "pas dans les tonneaux")
	# Fréquence réelle sur les ennemis (graines successives).
	var n := 0
	for i in 4000:
		if not HatchKeys.roll(i, HatchKeys.enemy_chance(1, false)).is_empty():
			n += 1
	var want := 4000.0 * HatchKeys.enemy_chance(1, false)
	assert_between(float(n), want * 0.5, want * 1.6, "taux de drop ≈ réglage (%d / 4000)" % n)


func test_extraction_rend_le_gadget() -> void:
	var saved_profile: Dictionary = Profile.to_dict()
	var saved_sm: Dictionary = (SaveManager.data as Dictionary).duplicate(true)
	var inv := Inventory.new()
	inv.add_item(LootDB.get_item(HatchKeys.ITEM_ID), 2)
	var before := Profile.weapons.filter(func(e: Dictionary) -> bool: return String(e["id"]) == String(HatchKeys.GADGET_ID)).size()
	var summary: Dictionary = Profile.finish_extraction([], inv)
	var after := Profile.weapons.filter(func(e: Dictionary) -> bool: return String(e["id"]) == String(HatchKeys.GADGET_ID)).size()
	assert_eq(after - before, 2, "deux clefs → deux gadgets en réserve")
	assert_true((summary["weapons"] as Array).has(HatchKeys.GADGET_ID))
	assert_false((summary["items"] as Dictionary).has(HatchKeys.ITEM_ID), "pas gardée comme objet")
	Profile.from_dict(saved_profile)
	SaveManager.data = saved_sm


func test_fantome_autre_etage() -> void:
	var s := ExtractionPlan.Spec.new()
	s.closes_at = 200.0
	var g := MiniMap.ghost_state({"spec": s, "floor": -1}, 20.0)
	assert_true(g["ghost"])
	assert_eq(g["text"], "-1 · 3:00")
	assert_eq(int(g["state"]), ExtractionZone.State.OPEN)
	s.closes_at = INF
	assert_eq(MiniMap.ghost_state({"spec": s, "floor": 1}, 20.0)["text"], "+1", "permanente : étage seul")
	s.closes_at = 10.0
	assert_eq(int(MiniMap.ghost_state({"spec": s, "floor": 1}, 20.0)["state"]), ExtractionZone.State.CLOSED)
	assert_eq(MiniMap.floor_label(0), "RDC")


# --- Raid ------------------------------------------------------------------------------

func test_raid_trappe_avec_et_sans_clef() -> void:
	var saved_profile: Dictionary = Profile.to_dict()
	var saved_sm: Dictionary = (SaveManager.data as Dictionary).duplicate(true)
	var raid := (load("res://scenes/dungeon/raid.tscn") as PackedScene).instantiate() as Raid
	add_child_autofree(raid)
	await wait_physics_frames(3)
	var hatch: ExtractionZone = null
	for z: ExtractionZone in raid.extraction_zones:
		if z.is_hatch():
			hatch = z
	# Mini-carte : jamais de trappe.
	if raid.minimap != null:
		for n: Node2D in raid.minimap._zones:
			assert_false((n as ExtractionZone).is_hatch(), "trappe absente de la mini-carte")
	if hatch == null:
		pending("pas de trappe sur cet étage")
		Profile.from_dict(saved_profile)
		SaveManager.data = saved_sm
		return
	# Gadget clef : jamais lancé.
	raid.player.call(&"set_gadget", WeaponCatalog.get_weapon(HatchKeys.GADGET_ID))
	assert_false(bool(raid.player.call(&"use_gadget")), "la clef ne se lance pas")
	assert_true(bool(raid.player.call(&"has_hatch_key_gadget")), "charge intacte")
	raid.player.call(&"set_gadget", null)
	var inv: Inventory = GameState.raid_inventory
	inv.remove_item(HatchKeys.ITEM_ID, 99)
	var cell: Vector2i = hatch.cells[0]
	raid.place_player(cell)
	raid._update_extraction(cell, 0.1)
	assert_false(raid.is_extracting(), "sans clef : pas de canalisation")
	assert_true(hatch.locked)
	assert_string_contains(raid.get_toast_text(), "clef de trappe requise")
	inv.add_item(LootDB.get_item(HatchKeys.ITEM_ID), 1)
	raid._update_extraction(cell, 0.1)
	assert_false(hatch.locked, "clef utilisée : trappe ouverte")
	assert_eq(inv.count_of(HatchKeys.ITEM_ID), 0, "clef consommée")
	assert_true(raid.is_extracting(), "canalisation sur la trappe ouverte")
	assert_almost_eq(raid.current_channel_time(), Raid.extraction_channel_time()
		* Balance.get_float("extraction", "hatch_channel_mult", 1.0), 0.001)
	raid._cancel_extraction(false)
	# Coop : l'ouverture distante d'une trappe déjà ouverte ne fait rien de plus.
	assert_true(raid.open_hatch_at(cell))
	Profile.from_dict(saved_profile)
	SaveManager.data = saved_sm
