extends GutTest
## Économie (refonte n°3) : vente au marchand, armurerie (shop / kill / drop), déblocage par
## victimes, artisanat (recettes, groupes d'ingrédients), consommables emportés, leurre
## (NoiseSources) et écrans Marchand / Atelier / Armurerie / fin de raid.
## Le profil, SaveManager.data et user://save.json sont mis de côté puis restaurés à l'identique.

var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""
var _saved_bag: Inventory = null
var _saved_player: Node2D = null


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""
	_saved_bag = GameState.raid_inventory
	_saved_player = GameState.player if is_instance_valid(GameState.player) else null
	Profile.from_dict({})
	NoiseSources.clear()


func after_each() -> void:
	NoiseSources.clear()
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	GameState.raid_inventory = _saved_bag
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))
	get_tree().paused = false


func _it(id: StringName) -> ItemData:
	return LootDB.get_item(id)


# --- Vente ---------------------------------------------------------------------------------

func test_prix_de_vente_selon_balance() -> void:
	var ratio := Balance.get_float("economy", "sell_ratio", 0.5)
	var nug := _it(&"gold_nugget")
	assert_eq(Economy.item_sell_price(nug), maxi(int(round(nug.value * ratio)), 1))
	assert_gte(Economy.item_sell_price(_it(&"revolver_ammo")), 1, "jamais 0 or")
	var arr: Array = Balance.get_value("economy", "weapon_sell_by_rarity", [])
	assert_eq(arr.size(), 5)
	assert_eq(Economy.weapon_sell_price(WeaponCatalog.get_weapon(&"smg_p90")), int(arr[3]))
	# Un objet arme se vend au prix de la rareté de l'arme.
	assert_eq(Economy.item_sell_price(_it(&"wpn_smg_p90")), int(arr[3]))
	assert_true(Economy.needs_confirmation(2), "Rare : confirmation")
	assert_false(Economy.needs_confirmation(0), "Commun : vente directe")


func test_vente_d_objets_en_quantite() -> void:
	Profile.items = {"gold_nugget": 3, "mat_cloth": 5}
	var unit := Economy.item_sell_price(_it(&"gold_nugget"))
	var got := Profile.sell_item(&"gold_nugget", 2)
	assert_eq(got, unit * 2)
	assert_eq(Profile.gold, unit * 2)
	assert_eq(Profile.item_count(&"gold_nugget"), 1)
	# Demander plus que le stock : vend ce qu'il y a.
	assert_eq(Profile.sell_item(&"gold_nugget", 10), unit)
	assert_false(Profile.items.has("gold_nugget"), "pile épuisée retirée")
	assert_eq(Profile.sell_item(&"gold_nugget", 1), 0, "plus rien à vendre")
	assert_eq(Profile.sell_item(&"objet_inconnu", 1), 0)


func test_armes_vendables_seulement_en_double() -> void:
	var a := Profile.add_weapon(&"rifle_ak47")
	assert_false(Profile.can_sell_weapon(a), "dernier exemplaire : invendable")
	assert_eq(Profile.sell_weapon(a), 0)
	var b := Profile.add_weapon(&"rifle_ak47")
	assert_eq(Profile.spare_weapon_uid(&"rifle_ak47") in [a, b], true)
	var g := Profile.sell_weapon(b)
	assert_eq(g, Economy.weapon_sell_price(WeaponCatalog.get_weapon(&"rifle_ak47")))
	assert_eq(Profile.weapon_count(&"rifle_ak47"), 1)


func test_dollars_devient_l_or() -> void:
	Profile.from_dict({"dollars": 777})
	assert_eq(Profile.gold, 777, "ancienne sauvegarde : dollars → or")
	Profile.dollars = 12
	assert_eq(Profile.gold, 12, "alias dollars")
	var d := Profile.to_dict()
	assert_eq(int(d["gold"]), 12)


func test_extraction_ne_donne_plus_d_or() -> void:
	var a := Profile.add_weapon(&"smg_mp5")
	Profile.set_loadout([a] as Array[int])
	GameState.raid_inventory = Inventory.new(6, 4, 999.0)
	Profile.start_raid()
	var bag := Inventory.new(6, 4, 999.0)
	bag.add_item(_it(&"gold_nugget"), 4)
	var res := Profile.finish_extraction([&"smg_mp5"] as Array[StringName], bag)
	assert_eq(Profile.gold, 0, "pas d'or automatique")
	assert_eq(int(res["value"]), Economy.item_sell_price(_it(&"gold_nugget")) * 4, "valeur = or estimé")
	assert_eq(int(res["loot_value"]), _it(&"gold_nugget").value * 4)
	assert_eq(int(res["gems"]), Profile.extraction_gems(_it(&"gold_nugget").value * 4), "gemmes inchangées")


# --- Armurerie -----------------------------------------------------------------------------

func test_regles_d_armurerie_du_catalogue() -> void:
	var kills := 0
	for w: WeaponData in WeaponCatalog.all():
		if w.rarity >= 4:
			assert_eq(w.unlock_mode, WeaponData.UNLOCK_DROP, "%s : Légendaire = butin uniquement" % w.id)
			assert_eq(w.price_gold, 0, "%s : pas de prix" % w.id)
			continue
		if w.id == &"gadget_c4":
			# C4 : Épique, uniquement fabricable à l'atelier ou trouvé en butin (pas en vente).
			assert_eq(w.unlock_mode, WeaponData.UNLOCK_DROP)
			continue
		if w.id == &"gadget_hatch_key":
			# Clef de trappe : trouvée sur les ennemis et dans les coffres seulement (pas en vente).
			assert_eq(w.unlock_mode, WeaponData.UNLOCK_DROP)
			assert_eq(w.price_gold, 0)
			continue
		assert_true(w.unlock_mode in [WeaponData.UNLOCK_SHOP, WeaponData.UNLOCK_KILL], "%s : achetable" % w.id)
		assert_gt(w.price_gold, 0, "%s : prix en or" % w.id)
		if w.rarity == 0:
			assert_eq(w.unlock_mode, WeaponData.UNLOCK_SHOP, "%s : Commune en vente" % w.id)
		if w.unlock_mode == WeaponData.UNLOCK_KILL:
			kills += 1
			assert_true(ResourceLoader.exists("res://data/enemies/%s.tres" % w.unlock_enemy_kind), "%s : ennemi %s" % [w.id, w.unlock_enemy_kind])
			assert_gte(w.unlock_kills, 1)
	assert_gte(kills, 3, "quelques armes à débloquer par kill")
	var m82 := WeaponCatalog.get_weapon(&"sniper_m82")
	assert_eq(m82.unlock_mode, WeaponData.UNLOCK_KILL)
	assert_eq(m82.unlock_enemy_kind, &"fw_sharpshooter")
	assert_eq(m82.unlock_kills, 1)
	var rpg := WeaponCatalog.get_weapon(&"rocket_rpg7")
	assert_eq([rpg.unlock_enemy_kind, rpg.unlock_kills], [&"fw_raider", 3])
	assert_eq(WeaponCatalog.get_weapon(&"rocket_m202").unlock_enemy_kind, &"fw_deserter")
	# Prix cohérents : une Commune ≈ une partie, la rareté coûte plus cher.
	assert_lt(WeaponCatalog.get_weapon(&"smg_mp5").price_gold, WeaponCatalog.get_weapon(&"smg_vector").price_gold)
	assert_lt(WeaponCatalog.get_weapon(&"smg_vector").price_gold, WeaponCatalog.get_weapon(&"smg_p90").price_gold)


func test_achat_en_vente() -> void:
	var w := WeaponCatalog.get_weapon(&"smg_mp5")
	assert_false(Profile.buy_weapon(&"smg_mp5"), "pas assez d'or")
	Profile.gold = w.price_gold + 5
	assert_true(Profile.buy_weapon(&"smg_mp5"))
	assert_eq(Profile.gold, 5)
	assert_eq(Profile.weapon_count(&"smg_mp5"), 1, "l'arme rejoint la réserve")
	assert_false(Profile.buy_weapon(&"arme_inconnue"))


func test_legendaire_jamais_achetable() -> void:
	Profile.gold = 1_000_000
	for id: StringName in [&"pistol_p320", &"smg_uzi", &"rifle_aug", &"rocket_javelin", &"gadget_drone"]:
		var st := Profile.weapon_shop_status(id)
		assert_eq(st["state"], Economy.STATE_DROP_ONLY, "%s : butin uniquement" % id)
		assert_string_contains(str(st["text"]), "uniquement en butin")
		assert_false(Profile.buy_weapon(id), "%s : refusé même avec de l'or" % id)
	assert_eq(Profile.gold, 1_000_000)


func test_deblocage_par_kill() -> void:
	Profile.gold = 100_000
	var st := Profile.weapon_shop_status(&"sniper_m82")
	assert_eq(st["state"], Economy.STATE_LOCKED)
	assert_eq(str(st["text"]), "Tue 1 Tireur d'élite pour débloquer (0/1)")
	assert_false(Profile.buy_weapon(&"sniper_m82"), "pas encore débloquée")
	watch_signals(Profile)
	var newly := Profile.record_kill(&"fw_sharpshooter")
	assert_eq(newly, [&"sniper_m82"] as Array[StringName])
	assert_signal_emitted_with_parameters(Profile, "weapon_unlocked", [&"sniper_m82"])
	assert_true(Profile.is_weapon_buyable(&"sniper_m82"))
	assert_true(Profile.buy_weapon(&"sniper_m82"))
	# Deuxième kill : pas de nouveau message.
	assert_eq(Profile.record_kill(&"fw_sharpshooter").size(), 0)
	# RPG-7 : 3 pillards.
	Profile.record_kill(&"fw_raider")
	Profile.record_kill(&"fw_raider")
	var rs := Profile.weapon_shop_status(&"rocket_rpg7")
	assert_eq(rs["state"], Economy.STATE_LOCKED)
	assert_eq(str(rs["text"]), "Tue 3 Pillards pour débloquer (2/3)")
	Profile.record_kill(&"fw_raider")
	assert_true(Profile.is_weapon_buyable(&"rocket_rpg7"))
	assert_true(Profile.to_dict()["kills_by_kind"].has("fw_raider"), "kills sauvegardés")


func test_kill_ecoute_l_event_bus_et_compte_a_la_mort() -> void:
	var a := Profile.add_weapon(&"rifle_ak47")
	Profile.set_loadout([a] as Array[int])
	GameState.raid_inventory = Inventory.new(6, 4, 999.0)
	Profile.start_raid()
	var e := FakeEnemy.new()
	e.add_to_group(&"enemy_units")
	var d := EnemyData.new()
	d.kind = &"fw_deserter"
	e.data = d
	add_child_autofree(e)
	EventBus.enemy_died.emit(e, Vector2.ZERO)
	assert_eq(int(Profile.kills_by_kind.get("fw_deserter", 0)), 1, "kill compté via EventBus.enemy_died")
	var res := Profile.finish_death()
	var rep: Array = res["unlock_kills"]
	assert_eq(rep.size(), 1, "encart de fin : le Déserteur compte pour la M202")
	assert_eq(rep[0]["kind"], &"fw_deserter")
	assert_true(bool((rep[0]["weapons"] as Array)[0]["done"]), "M202 débloquée même en mourant")
	assert_true(Profile.is_weapon_buyable(&"rocket_m202"))


class FakeEnemy extends Node2D:
	var data: EnemyData = null


func test_ennemi_sans_interet_ignore_dans_l_encart() -> void:
	Profile.record_kill(&"fw_guard_dog")
	assert_true(Economy.kill_report(Profile.raid_kills, Profile.kills_by_kind).is_empty(), "aucun déblocage lié")


# --- Artisanat -----------------------------------------------------------------------------

func test_recettes_valides() -> void:
	RecipeBook.reload()
	var all := RecipeBook.all()
	assert_gte(all.size(), 7)
	var wanted := {&"craft_bandage": &"bandage", &"craft_medkit": &"medkit", &"craft_frag": &"gadget_frag",
		&"craft_smoke": &"gadget_smoke", &"craft_decoy": &"gadget_decoy", &"craft_mine": &"gadget_mine", &"craft_c4": &"gadget_c4"}
	for id: StringName in wanted:
		var r := RecipeBook.get_recipe(id)
		assert_not_null(r, "recette %s" % id)
		if r == null:
			continue
		assert_eq(r.result_weapon_id if r.is_weapon_result() else r.result_item_id, wanted[id])
	for r: RecipeData in all:
		assert_not_null(r.get_result_item(), "%s : résultat connu" % r.id)
		assert_false(r.ingredients.is_empty(), "%s : ingrédients" % r.id)
		for k: Variant in r.ingredients:
			assert_false(RecipeBook.options_for(str(k)).is_empty(), "%s : ingrédient %s existe" % [r.id, k])
			assert_gt(int(r.ingredients[k]), 0)
	assert_gt(RecipeBook.get_recipe(&"craft_c4").gold_cost, RecipeBook.get_recipe(&"craft_mine").gold_cost, "C4 plus cher")
	assert_gt(RecipeBook.get_recipe(&"craft_mine").gold_cost, RecipeBook.get_recipe(&"craft_frag").gold_cost)


func test_materiaux_dans_les_tables_de_chaque_biome() -> void:
	var worlds := ["res://data/worlds/world_01_far_west.tres", "res://data/worlds/world_02_space_station.tres",
		"res://data/worlds/world_03_mall.tres"]
	for wp: String in worlds:
		var world := load(wp) as Resource
		var found := {}
		for k: Variant in world.get("container_kinds"):
			var t := LootDB.get_table(StringName(k))
			if t != null:
				for id: Variant in t.entries:
					found[String(id)] = true
		for need: String in ["mat_cloth", "mat_scrap", "mat_chemicals", "black_powder"]:
			assert_true(found.has(need), "%s : %s trouvable" % [wp.get_file(), need])
		var mech := false
		for id: StringName in RecipeBook.options_for("@mechanism"):
			mech = mech or found.has(String(id))
		assert_true(mech, "%s : un mécanisme trouvable" % wp.get_file())


func test_fabrication_bandage_et_medkit() -> void:
	assert_false(Profile.craft(&"craft_bandage"), "rien en réserve")
	Profile.items = {"mat_cloth": 4, "mat_chemicals": 1}
	assert_false(Profile.can_craft(&"craft_bandage"), "fabriquer coûte de l'or")
	Profile.gold = RecipeBook.get_recipe(&"craft_bandage").gold_cost
	assert_true(Profile.craft(&"craft_bandage"))
	assert_eq(Profile.gold, 0, "or dépensé")
	assert_eq(Profile.item_count(&"bandage"), 2)
	assert_eq(Profile.item_count(&"mat_cloth"), 1)
	Profile.gold = RecipeBook.get_recipe(&"craft_medkit").gold_cost
	assert_true(Profile.craft(&"craft_medkit"), "2 bandages + chimie + tissu + or")
	assert_eq(Profile.item_count(&"medkit"), 1)
	assert_eq(Profile.item_count(&"bandage"), 0)
	assert_eq(Profile.gold, 0)
	assert_true(_it(&"medkit").is_usable(), "la trousse soigne en raid")


func test_groupe_consomme_le_moins_cher_d_abord() -> void:
	Profile.items = {"mat_gears": 1, "space_circuit": 3, "mat_scrap": 2, "mat_cloth": 1}
	Profile.gold = 100
	var r := RecipeBook.get_recipe(&"craft_decoy")
	var plan := RecipeBook.plan(r, Profile.items)
	assert_eq(int(plan.get("mat_gears", 0)), 1, "rouages (moins chers) d'abord")
	assert_eq(int(plan.get("space_circuit", 0)), 1, "puis un circuit")
	assert_true(Profile.craft(&"craft_decoy"))
	assert_eq(Profile.weapon_count(&"gadget_decoy"), 1, "équipement fabriqué = réserve d'armes")
	assert_true(WeaponCatalog.get_weapon(&"gadget_decoy").is_gadget())
	assert_eq(Profile.item_count(&"space_circuit"), 2)
	assert_eq(RecipeBook.usage_text(&"mat_gears").contains("Leurre"), true, "le matériau dit à quoi il sert")


func test_consommables_emportes_au_lancement() -> void:
	Profile.items = {"bandage": 3, "medkit": 2, "gold_nugget": 1}
	var mx := Profile.raid_consumables_max()
	var prev := Profile.consumables_preview()
	assert_eq((prev[0]["item"] as ItemData).id, &"medkit", "meilleur soin d'abord")
	var total := 0
	for e: Dictionary in prev:
		total += int(e["count"])
	assert_eq(total, mini(5, mx), "au plus raid_consumables_max")
	var a := Profile.add_weapon(&"smg_mp5")
	Profile.set_loadout([a] as Array[int])
	GameState.raid_inventory = Inventory.new(6, 4, 999.0)
	Profile.start_raid()
	var bag := GameState.raid_inventory
	assert_eq(bag.count_of(&"medkit") + bag.count_of(&"bandage"), mini(5, mx), "soins dans le sac")
	assert_eq(Profile.item_count(&"medkit") + Profile.item_count(&"bandage"), 5 - mini(5, mx), "retirés de la réserve")
	assert_eq(Profile.item_count(&"gold_nugget"), 1, "les valeurs restent")
	Profile.finish_death()
	# Désactivé : rien n'est emporté.
	Profile.set_pack_consumables(false)
	assert_true(Profile.consumables_preview().is_empty())


# --- Leurre --------------------------------------------------------------------------------

class LurePlayer extends CharacterBody2D:
	func _ready() -> void:
		add_to_group(&"player")
	func is_alive() -> bool:
		return true
	func get_noise_level() -> float:
		return 0.0
	func is_hidden() -> bool:
		return false


func _lure_world() -> Node2D:
	var w := Node2D.new()
	add_child_autofree(w)
	var p := LurePlayer.new()
	p.position = Vector2(4000, 4000)
	w.add_child(p)
	GameState.player = p
	return w


func _lure_enemy(world: Node2D, pos: Vector2) -> Enemy:
	var d := EnemyData.new()
	d.kind = &"fw_raider"
	d.detection_radius = 200.0
	d.detection_angle_deg = 90.0
	d.patrol_radius = 0.0
	d.hearing_radius = 400.0
	d.awareness_alert_threshold = 1.0
	d.alert_neighbors_radius = 0.0
	var e := Enemy.spawn(d)
	e.position = pos
	world.add_child(e)
	e.set_physics_process(false)
	return e


func test_leurre_attire_un_ennemi() -> void:
	var world := _lure_world()
	var e := _lure_enemy(world, Vector2.ZERO)
	var far := _lure_enemy(world, Vector2(3000, 0))
	await wait_physics_frames(2)
	assert_eq(e.current_state_name(), Enemy.STATE_PATROL)
	var decoy_pos := Vector2(260, 40)
	# Durée en temps réel (Time.get_ticks_msec) alors que le test avance de 200 images physiques :
	# 30 s de marge pour qu'une machine chargée n'efface pas le leurre avant la fin du test.
	NoiseSources.emit(decoy_pos, 1.0, 30.0, 500.0)
	assert_eq(NoiseSources.count(), 1)
	var n := NoiseSources.pulse(get_tree())
	assert_eq(n, 1, "seul l'ennemi dans le rayon est attiré")
	assert_eq(e.current_state_name(), Enemy.STATE_INVESTIGATE, "le leurre le fait enquêter")
	assert_eq(e.stimulus_position, decoy_pos, "il va vers le leurre")
	assert_lt(e.awareness, 1.0, "jamais d'alerte à cause du leurre")
	assert_eq(far.current_state_name(), Enemy.STATE_PATROL, "hors de portée : rien")
	# Passages suivants : pas de nouveau stimulus (la pause de suspicion n'est pas relancée).
	var serial := e.stimulus_serial
	NoiseSources.pulse(get_tree())
	assert_eq(e.stimulus_serial, serial)
	# Il marche vers le leurre.
	e.set_physics_process(true)
	var d0 := e.global_position.distance_to(decoy_pos)
	await wait_physics_frames(200)
	gut.p("leurre : %s → %.0f px (état %s)" % [d0, e.global_position.distance_to(decoy_pos), e.current_state_name()])
	assert_lt(e.global_position.distance_to(decoy_pos), d0 - 20.0, "l'ennemi s'approche du leurre")
	var best := NoiseSources.loudest_at(Vector2(100, 0))
	assert_eq(best.get("pos"), decoy_pos, "API tirée pour l'IA")


func test_leurre_ignore_par_un_ennemi_en_combat() -> void:
	var world := _lure_world()
	var e := _lure_enemy(world, Vector2.ZERO)
	await wait_physics_frames(1)
	e.become_aware(Vector2(-100, 0))
	assert_true(e.is_in_combat())
	assert_false(NoiseSources.lure(e, Vector2(100, 0), 1.0, 500.0))


func test_gadget_leurre_pose_une_source_de_bruit() -> void:
	var world := _lure_world()
	var w := WeaponCatalog.get_weapon(&"gadget_decoy")
	assert_not_null(w)
	assert_eq(w.gadget_kind, WeaponData.GADGET_DECOY)
	assert_gt(w.effect_duration, 0.0)
	assert_gt(w.effect_radius, 0.0)
	var dev := GadgetDevice.throw_device(world, w, Vector2.ZERO, 20.0, Vector2(200, 0), null)
	assert_not_null(dev)
	await wait_physics_frames(120)
	var decoys := get_tree().get_nodes_in_group(&"decoys")
	assert_eq(decoys.size(), 1, "le leurre se pose")
	assert_eq(NoiseSources.count(), 1, "et crie")
	(decoys[0] as DecoyDevice).queue_free()
	await wait_physics_frames(1)
	assert_eq(NoiseSources.count(), 0, "détruit : silence")


# --- Écrans --------------------------------------------------------------------------------

func test_marchand_vente_et_confirmation() -> void:
	Profile.items = {"mat_cloth": 6, "gold_bar": 1}
	var m := MerchantScreen.new()
	m.back_scene = ""
	add_child_autofree(m)
	await wait_frames(2)
	assert_eq(m.entries().size(), 2)
	m.select(&"mat_cloth")
	assert_true(m.request_sell(1), "Commun : vente directe")
	assert_eq(Profile.item_count(&"mat_cloth"), 5)
	assert_true(m.request_sell(-1), "tout vendre")
	assert_eq(Profile.item_count(&"mat_cloth"), 0)
	m.select(&"gold_bar")
	assert_false(m.request_sell(1), "Épique : confirmation demandée")
	assert_not_null(m.last_confirm)
	assert_eq(Profile.item_count(&"gold_bar"), 1, "rien vendu avant confirmation")
	m.last_confirm.confirmed.emit()
	assert_eq(Profile.item_count(&"gold_bar"), 0)
	assert_eq(Profile.gold, Economy.item_sell_price(_it(&"mat_cloth")) * 6 + Economy.item_sell_price(_it(&"gold_bar")))
	# Armes en double.
	Profile.add_weapon(&"smg_mp5")
	Profile.add_weapon(&"smg_mp5")
	m.set_filter(&"weapons")
	assert_eq(m.entries().size(), 1)
	m.select(&"smg_mp5")
	assert_true(m.request_sell(1))
	assert_eq(Profile.weapon_count(&"smg_mp5"), 1)


func test_atelier_fabrique() -> void:
	Profile.items = {"mat_cloth": 3}
	Profile.gold = RecipeBook.get_recipe(&"craft_bandage").gold_cost
	var c := CraftingScreen.new()
	c.back_scene = ""
	add_child_autofree(c)
	await wait_frames(2)
	assert_eq(c.rows.size(), RecipeBook.all().size())
	assert_eq(c.selected.id, &"craft_bandage", "la recette faisable est présélectionnée")
	assert_false(c.craft_button.disabled)
	assert_true(c.craft_selected())
	assert_eq(Profile.item_count(&"bandage"), 2)
	assert_true(c.craft_button.disabled, "plus de tissu")
	c.select(RecipeBook.get_recipe(&"craft_c4"))
	assert_true(c.craft_button.disabled)


func test_armurerie_dans_l_arsenal() -> void:
	Profile.gold = 300
	Profile.add_weapon(&"pistol_p9")
	var a := (load("res://scenes/ui/menus/arsenal.tscn") as PackedScene).instantiate() as ArsenalScreen
	add_child_autofree(a)
	await wait_frames(2)
	a.set_shop_mode(true)
	await wait_frames(1)
	var by := {}
	for t: WeaponTile in a.tiles:
		by[t.weapon.id] = t
	assert_eq((by[&"smg_mp5"] as WeaponTile).get_shop_text(), "220 or")
	assert_eq((by[&"sniper_m82"] as WeaponTile).get_shop_text(), "0/1")
	assert_eq((by[&"rifle_aug"] as WeaponTile).get_shop_text(), "BUTIN")
	a.show_weapon_detail(WeaponCatalog.get_weapon(&"rifle_aug"), false)
	assert_false(a.buy_button.visible, "Légendaire : pas de bouton d'achat")
	a.show_weapon_detail(WeaponCatalog.get_weapon(&"sniper_m82"), false)
	assert_true(a.buy_button.disabled, "M82 verrouillée")
	a.show_weapon_detail(WeaponCatalog.get_weapon(&"smg_mp5"), false)
	assert_false(a.buy_button.disabled)
	assert_true(a.buy_selected())
	assert_eq(Profile.gold, 80)
	assert_eq(Profile.weapon_count(&"smg_mp5"), 1)
	assert_true(a.buy_button.disabled, "plus assez d'or")


func test_arsenal_de_depart_montre_les_consommables() -> void:
	Profile.items = {"bandage": 2}
	Profile.add_weapon(&"pistol_p9")
	var a := (load("res://scenes/ui/menus/loadout.tscn") as PackedScene).instantiate() as ArsenalScreen
	a.raid_scene = ""
	add_child_autofree(a)
	await wait_frames(2)
	assert_string_contains(a.consumables_label.text, "Bandages ×2")
	a.toggle_consumables()
	assert_false(Profile.pack_consumables)
	assert_string_contains(a.consumables_label.text, "aucun")


func test_fin_de_raid_encart_des_kills_et_valeur_estimee() -> void:
	Profile.record_kill(&"fw_sharpshooter")
	var rep := Economy.kill_report(Profile.raid_kills, Profile.kills_by_kind)
	var sc := RaidEndScreen.create(true, {"weapons": [&"rifle_ak47"], "items": {&"gold_nugget": 2}, "value": 25,
		"gems": 3, "unlock_kills": rep})
	add_child_autofree(sc)
	await wait_process_frames(3)
	assert_string_contains(sc.get_kills_text(), "Tireur d'élite ×1")
	assert_string_contains(sc.get_kills_text(), "Barrett M82 débloquée")
	var chip := sc.find_child("ValueChip", true, false)
	assert_not_null(chip, "valeur estimée affichée")
	var txt := ""
	for l: Node in chip.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	assert_string_contains(txt, "or au marchand")
	assert_false(txt.contains("$"))
	assert_true(sc.fits_on_screen(), "tient à l'écran avec l'encart")
	sc.queue_free()
	await wait_process_frames(1)


func test_message_en_raid_quand_une_arme_devient_achetable() -> void:
	var hud := InventoryHud.new()
	add_child_autofree(hud)
	await wait_frames(1)
	Profile.record_kill(&"fw_sharpshooter")
	assert_string_contains(hud.get_last_feed_text(), "Nouvelle arme déblocable à l'armurerie : Barrett M82")


func test_pilote_du_bruit_attire_sans_appel_manuel() -> void:
	var world := _lure_world()
	var e := _lure_enemy(world, Vector2.ZERO)
	await wait_physics_frames(2)
	NoiseSources.emit(Vector2(200, 0), 1.0, 3.0, 500.0)
	await wait_physics_frames(30)
	assert_eq(e.current_state_name(), Enemy.STATE_INVESTIGATE, "le pilote fait le travail tout seul")


func test_leurre_emet_a_sa_position() -> void:
	var world := _lure_world()
	world.position = Vector2(50, 0)
	var d := DecoyDevice.spawn(world, Vector2(300, 120), WeaponCatalog.get_weapon(&"gadget_decoy"))
	assert_eq(d.global_position, Vector2(300, 120))
	assert_eq(NoiseSources.loudest_at(Vector2(300, 130)).get("pos"), Vector2(300, 120), "source au point de pose")



func test_fabriquer_coute_de_l_or() -> void:
	RecipeBook.reload()
	var expected := {&"craft_bandage": 20, &"craft_medkit": 60, &"craft_frag": 50, &"craft_smoke": 70,
		&"craft_decoy": 60, &"craft_mine": 180, &"craft_c4": 400}
	var mult := Balance.get_float("crafting", "gold_cost_mult", 1.0)
	for id: StringName in expected:
		var r := RecipeBook.get_recipe(id)
		assert_eq(r.gold_cost, RecipeBook.cost_of(int(expected[id])), "%s : coût × multiplicateur" % id)
		assert_gt(r.gold_cost, 0, "%s : jamais gratuit" % id)
	assert_eq(RecipeBook.cost_of(100), maxi(int(round(100.0 * mult)), int(Balance.get_value("crafting", "min_gold_cost", 5))))
	# Pas de double multiplication au rechargement.
	var before := RecipeBook.get_recipe(&"craft_c4").gold_cost
	RecipeBook.reload()
	assert_eq(RecipeBook.get_recipe(&"craft_c4").gold_cost, before)
	# Refus clair quand l'or manque ; ingrédients intacts.
	var r2 := RecipeBook.get_recipe(&"craft_bandage")
	Profile.items = {"mat_cloth": 3}
	Profile.gold = r2.gold_cost - 35
	assert_eq(RecipeBook.refusal(r2, Profile.items, Profile.gold), "Il te manque 35 or")
	assert_false(Profile.craft(&"craft_bandage"))
	assert_eq(Profile.item_count(&"mat_cloth"), 3, "rien consommé")
	assert_eq(Profile.gold, r2.gold_cost - 35)
	Profile.items = {}
	assert_string_contains(RecipeBook.refusal(r2, Profile.items, 999), "Manque : 3 bandes de tissu")
	Profile.gold = 999
	Profile.items = {"mat_cloth": 3}
	assert_eq(RecipeBook.refusal(r2, Profile.items, Profile.gold), "")
	# Ordre de grandeur : un raid moyen (~250 or) paie quelques soins, pas une C4.
	assert_lt(RecipeBook.get_recipe(&"craft_bandage").gold_cost, 50)
	assert_gt(RecipeBook.get_recipe(&"craft_c4").gold_cost, 250)
