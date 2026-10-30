extends GutTest
## Écran d'inventaire de raid refait : glisser-déposer, emplacements rapides, actions, mise en page.

const VIEWPORTS: Array[Vector2] = [Vector2(1280, 720), Vector2(1560, 720), Vector2(1600, 720)]
const SAFES: Array[Vector4] = [Vector4(16, 16, 16, 16), Vector4(64, 16, 64, 28)]

var _saved_inv: Inventory


func before_each() -> void:
	_saved_inv = GameState.raid_inventory


func after_each() -> void:
	GameState.raid_inventory = _saved_inv
	get_tree().paused = false


func _it(id: StringName) -> ItemData:
	return LootDB.get_item(id)


func test_inventaire_glisser_vers_emplacement_rapide_et_sac() -> void:
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.quick_auto_assign = false
	GameState.raid_inventory.add_item(_it(&"bandage"), 3)
	GameState.raid_inventory.add_item(_it(&"gold_nugget"), 1)
	var screen := InventoryScreen.new()
	add_child_autofree(screen)
	await wait_frames(1)
	screen.open()
	var data := {"from": "bag", "index": 0}
	assert_true(screen._accepts_quick(data), "soin accepté")
	assert_false(screen._accepts_quick({"from": "bag", "index": 1}), "objet de valeur refusé")
	screen._on_drop_quick(1, data)
	assert_eq(GameState.raid_inventory.quick_item(1).id, &"bandage")
	# Glisser l'emplacement rapide vers le sac : il se libère.
	screen._on_drop_bag(5, {"from": "quick", "index": 1})
	assert_eq(GameState.raid_inventory.quick[1], "")
	# Déplacer une case du sac.
	screen._on_drop_bag(7, {"from": "bag", "index": 1})
	assert_eq((GameState.raid_inventory.get_slot(7)["item"] as ItemData).id, &"gold_nugget")
	screen.close()


func test_inventaire_bouton_rapide_et_affixes() -> void:
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.quick_auto_assign = false
	GameState.raid_inventory.add_item(_it(&"bandage"), 1)
	var screen := InventoryScreen.new()
	add_child_autofree(screen)
	await wait_frames(1)
	screen.open()
	assert_true(screen._quick_btn.visible, "bouton Rapide pour un soin")
	screen._on_quick_pressed()
	assert_eq(GameState.raid_inventory.quick_item(0).id, &"bandage")
	screen._select(InventoryScreen.SEL_QUICK, 0)
	assert_true(screen._use_btn.visible, "Utiliser depuis l'emplacement rapide")
	screen.close()


func test_inventaire_tient_a_l_ecran() -> void:
	# Inventaire : le panneau et son contenu tiennent dans la zone sûre.
	GameState.raid_inventory = Inventory.from_balance()
	GameState.raid_inventory.add_item(_it(&"wpn_rifle_m4a1"), 1)
	var screen := InventoryScreen.new()
	add_child_autofree(screen)
	await wait_frames(1)
	for vp2: Vector2 in VIEWPORTS:
		for safe2: Vector4 in SAFES:
			screen.apply_layout(vp2, safe2)
			var need := screen._panel.get_combined_minimum_size()
			assert_lte(need.x, screen._panel.size.x + 0.5, "inventaire en largeur (%s, %s)" % [vp2, safe2])
			assert_lte(need.y, screen._panel.size.y + 0.5, "inventaire en hauteur (%s, %s)" % [vp2, safe2])
			assert_gte(screen.slot_size, 62.0, "cases du sac assez grandes au doigt")
