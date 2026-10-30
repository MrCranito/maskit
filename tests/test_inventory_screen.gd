extends GutTest
## Écran d'inventaire de raid refait : glisser-déposer, emplacements rapides, actions, mise en page.

const VIEWPORTS: Array[Vector2] = [Vector2(1280, 720), Vector2(1560, 720), Vector2(1600, 720)]
const SAFES: Array[Vector4] = [Vector4(16, 16, 16, 16), Vector4(64, 16, 64, 28)]

var _saved_inv: Inventory
var _saved_player = null


func before_each() -> void:
	_saved_inv = GameState.raid_inventory
	_saved_player = GameState.player if is_instance_valid(GameState.player) else null


func after_each() -> void:
	GameState.raid_inventory = _saved_inv
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null
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


# --- Fenêtre de butin : fermeture automatique en s'éloignant ------------------------------

func test_fenetre_de_butin_hysteresis() -> void:
	assert_false(InventoryLootWindow.out_of_range(80.0, 78.0, 0.0, 24.0), "juste après la portée : reste ouverte")
	assert_false(InventoryLootWindow.out_of_range(101.0, 78.0, 0.0, 24.0), "dans la marge")
	assert_true(InventoryLootWindow.out_of_range(103.0, 78.0, 0.0, 24.0), "au-delà de la marge : se ferme")
	assert_false(InventoryLootWindow.out_of_range(120.0, 78.0, 26.0, 24.0), "la portée propre du conteneur compte")


func test_fenetre_de_butin_se_ferme_quand_on_s_eloigne() -> void:
	var p := Node2D.new()
	add_child_autofree(p)
	GameState.player = p
	var c := LootContainer.create(&"crate", Vector2(40, 0))
	c.has_preset = true
	c.preset_entries = [{"item": _it(&"bandage"), "count": 1}, {"item": _it(&"gold_nugget"), "count": 1}]
	add_child_autofree(c)
	var win := InventoryLootWindow.new()
	add_child_autofree(win)
	await wait_frames(1)
	win.open_for(c, Inventory.new())
	assert_true(win.is_open())
	var limit := LootDB.getf("interact_range", 78.0) + c.get_interact_reach()
	var margin := LootDB.getf("loot_window_close_margin", 24.0)
	# Juste hors de portée, dans la marge, cible perdue : la fenêtre reste (pas de clignotement).
	p.global_position = c.global_position + Vector2(limit + margin * 0.5, 0)
	win._on_target_changed(null)
	win.check_distance()
	assert_true(win.is_open(), "dans la marge d'hystérésis : reste ouverte")
	# Au-delà de la marge : fermeture animée, puis masquée.
	p.global_position = c.global_position + Vector2(limit + margin + 20.0, 0)
	await wait_seconds(LootDB.getf("loot_window_check_interval", 0.1) * 3.0)
	assert_false(win.is_open(), "fermée toute seule par le minuteur")
	await wait_seconds(0.35)
	assert_false(win.visible, "fondu terminé")
	# La croix reste disponible : réouverture puis fermeture immédiate.
	p.global_position = c.global_position
	win.open_for(c, Inventory.new())
	assert_true(win.visible and win.is_open(), "réouverture")
	win.close()
	assert_false(win.visible, "✕ : fermeture immédiate")
