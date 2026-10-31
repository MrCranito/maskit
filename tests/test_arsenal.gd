extends GutTest
## Arsenal (refonte Exfil Rush) : catalogue d'armes, objets armes, tables de butin,
## cycle du profil (départ, mort, extraction) et fin de raid. Économie : tests/test_economy.gd.
## Les tests de profil utilisent l'autoload Profile après avoir mis de côté son contenu,
## SaveManager.data et le fichier de sauvegarde, restaurés à l'identique après chaque test.

## Catalogue exact de la planche docs/reference/arsenal.jpg : id → [nom, catégorie, rareté].
const PLANCHE := {
	&"pistol_p9": ["P9", &"pistol", 0], &"pistol_glock18": ["Glock 18", &"pistol", 2],
	&"pistol_deagle": ["Desert Eagle", &"pistol", 3], &"pistol_p320": ["P320", &"pistol", 4],
	&"smg_mp5": ["MP5", &"smg", 0], &"smg_vector": ["Vector", &"smg", 2],
	&"smg_p90": ["P90", &"smg", 3], &"smg_uzi": ["Uzi", &"smg", 4],
	&"rifle_ak47": ["AK-47", &"rifle", 0], &"rifle_m4a1": ["M4A1", &"rifle", 2],
	&"rifle_scarh": ["SCAR-H", &"rifle", 3], &"rifle_aug": ["AUG", &"rifle", 4],
	&"sniper_m24": ["M24", &"sniper", 0], &"sniper_ax50": ["AX-50", &"sniper", 2],
	&"sniper_m82": ["Barrett M82", &"sniper", 3],
	&"rocket_rpg7": ["RPG-7", &"rocket_launcher", 2], &"rocket_m202": ["M202", &"rocket_launcher", 3],
	&"rocket_javelin": ["Javelin", &"rocket_launcher", 4],
	&"gadget_frag": ["Grenade frag", &"gadget", 0], &"gadget_smoke": ["Grenade fumigène", &"gadget", 2],
	&"gadget_mine": ["Mine", &"gadget", 3], &"gadget_c4": ["C4", &"gadget", 3], &"gadget_drone": ["Drone", &"gadget", 4],
	# Hors planche : leurre de l'atelier (refonte n°3, économie).
	&"gadget_decoy": ["Leurre", &"gadget", 0],
}
const BIOME_TABLES := {
	"far_west": "res://data/worlds/world_01_far_west.tres",
	"space_station": "res://data/worlds/world_02_space_station.tres",
	"mall": "res://data/worlds/world_03_mall.tres",
}


var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""


func after_each() -> void:
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


## Profil vide (autoload Profile, restauré dans after_each).
func _new_profile() -> Node:
	Profile.from_dict({})
	return Profile


# --- Catalogue ---------------------------------------------------------------------------

func _catalog() -> Array[WeaponData]:
	return WeaponCatalog.all()


func test_catalogue_exact_de_la_planche() -> void:
	WeaponCatalog.reload()
	var all := _catalog()
	assert_eq(all.size(), 37, "18 armes de la planche + 12 de la phase 8 + 5 équipements + le leurre + la clef de trappe")
	for id: StringName in PLANCHE:
		var w := WeaponCatalog.get_weapon(id)
		assert_not_null(w, "arme %s" % id)
		if w == null:
			continue
		var row: Array = PLANCHE[id]
		assert_eq(w.display_name, String(row[0]), "%s : nom" % id)
		assert_eq(w.category, row[1], "%s : catégorie" % id)
		assert_eq(w.rarity, int(row[2]), "%s : rareté" % id)
		assert_eq(w.sprite_id, id, "%s : sprite_id = id" % id)
	var cats := {}
	for w: WeaponData in all:
		cats[w.category] = true
	assert_eq(cats.size(), 10, "10 catégories (6 de la planche + 4 de la phase 8)")
	for c: StringName in WeaponData.CATEGORIES:
		assert_true(cats.has(c), "catégorie %s" % c)
	assert_eq(WeaponCatalog.STARTER_ID, &"pistol_p9")
	assert_not_null(WeaponCatalog.get_starter())


## Phase 8 : revolver, fusil à pompe, mitrailleuse, lance-grenades (tools/gen_weapons.py).
const PHASE8 := {
	&"revolver_peacemaker": [&"revolver", 0], &"revolver_model29": [&"revolver", 2],
	&"revolver_python": [&"revolver", 3], &"shotgun_870": [&"shotgun", 0],
	&"shotgun_benelli": [&"shotgun", 2], &"shotgun_aa12": [&"shotgun", 4],
	&"lmg_m249": [&"lmg", 0], &"lmg_pkm": [&"lmg", 2], &"lmg_m60": [&"lmg", 3],
	&"gl_m79": [&"grenade_launcher", 0], &"gl_china_lake": [&"grenade_launcher", 2],
	&"gl_m32": [&"grenade_launcher", 3],
}


func test_armes_de_la_phase_8() -> void:
	var firearms := 0
	for w: WeaponData in _catalog():
		if not w.is_gadget():
			firearms += 1
	assert_gte(firearms, 30, "au moins 30 armes à feu (CLAUDE.md « Armes »)")
	for id: StringName in PHASE8:
		var w := WeaponCatalog.get_weapon(id)
		assert_not_null(w, "arme %s" % id)
		if w == null:
			continue
		assert_eq(w.category, PHASE8[id][0], "%s : catégorie" % id)
		assert_eq(w.rarity, int(PHASE8[id][1]), "%s : rareté" % id)
		assert_false(w.is_gadget(), "%s : emplacement d'arme" % id)
		assert_ne(w.rarity, 1, "%s : pas de Peu commun (non affiché, voir MenuKit)" % id)
		assert_not_null(LootDB.get_item(StringName("wpn_" + String(id))), "%s : objet de butin" % id)
		assert_gt(w.get_dps(), 0.0, "%s : DPS" % id)
		match w.category:
			WeaponData.CAT_SHOTGUN:
				assert_gt(w.projectile_count, 1, "%s : plusieurs plombs" % id)
				assert_gt(w.spread_degrees, 0.0, "%s : gerbe" % id)
			WeaponData.CAT_GRENADE:
				assert_eq(w.projectile_style, &"grenade", "%s : grenade en cloche" % id)
				assert_true(w.is_explosive(), "%s : explose" % id)
			WeaponData.CAT_LMG:
				assert_gte(w.magazine_size, 100, "%s : bande de 100" % id)
				assert_lt(w.move_speed_mult, 1.0, "%s : ralentit" % id)
			WeaponData.CAT_REVOLVER:
				assert_eq(w.magazine_size, 6, "%s : six coups" % id)


## Une table gérée garde, par rareté, le poids total des armes à feu de la planche : ajouter des
## modèles rend le butin plus varié, pas plus riche (tools/add_weapons.py).
func test_armes_de_la_phase_8_dans_le_butin() -> void:
	var chest := LootDB.get_table(&"chest")
	assert_not_null(chest)
	for id: StringName in PHASE8:
		assert_true(chest.entries.has(StringName("wpn_" + String(id))), "coffre : %s" % id)
	var commons := 0.0
	for k: Variant in chest.entries:
		var it := LootDB.get_item(StringName(str(k)))
		var w := WeaponCatalog.get_weapon(it.weapon_id) if it != null and it.is_weapon() else null
		if w != null and not w.is_gadget() and w.rarity == 0:
			commons += float(chest.entries[k])
	assert_almost_eq(commons, 3.0, 0.01, "coffre : poids total des armes Communes inchangé")


func test_equipements_dans_l_emplacement_gadget() -> void:
	var kinds := {&"gadget_frag": [&"frag", 3], &"gadget_smoke": [&"smoke", 2], &"gadget_mine": [&"mine", 2],
		&"gadget_c4": [&"c4", 1], &"gadget_drone": [&"drone", 1], &"gadget_decoy": [&"decoy", 2],
		&"gadget_hatch_key": [&"hatch_key", 1]}
	for w: WeaponData in _catalog():
		assert_eq(w.is_gadget(), w.category == WeaponData.CAT_GADGET, "%s : slot cohérent" % w.id)
		if not w.is_gadget():
			continue
		assert_eq(w.slot, WeaponData.SLOT_GADGET)
		assert_eq(w.gadget_kind, kinds[w.id][0], "%s : gadget_kind" % w.id)
		assert_eq(w.charges, int(kinds[w.id][1]), "%s : charges" % w.id)
		match w.gadget_kind:
			WeaponData.GADGET_FRAG, WeaponData.GADGET_C4, WeaponData.GADGET_MINE:
				assert_true(w.is_explosive(), "%s : explose" % w.id)
			WeaponData.GADGET_SMOKE, WeaponData.GADGET_DRONE, WeaponData.GADGET_DECOY:
				assert_gt(w.effect_duration, 0.0, "%s : durée" % w.id)
				assert_gt(w.effect_radius, 0.0, "%s : rayon" % w.id)


func test_chaque_arme_est_coherente() -> void:
	for w: WeaponData in _catalog():
		if w.is_gadget():
			continue
		assert_gt(w.damage, 0.0)
		assert_gt(w.fire_rate, 0.0)
		assert_gte(w.magazine_size, 1, "%s : chargeur" % w.id)
		assert_gt(w.value, 0)
		match w.category:
			WeaponData.CAT_SNIPER:
				assert_eq(w.projectile_style, &"tracer")
				assert_gte(w.pierce, 1, "%s : sniper perforant" % w.id)
			WeaponData.CAT_SMG:
				assert_true(w.automatic, "%s : automatique" % w.id)
			WeaponData.CAT_ROCKET:
				assert_eq(w.projectile_style, &"rocket")
				assert_true(w.is_explosive())
				assert_false(w.eject_shells)
	assert_eq(WeaponCatalog.get_weapon(&"rocket_rpg7").magazine_size, 1, "RPG-7 : 1 roquette")
	assert_eq(WeaponCatalog.get_weapon(&"rocket_m202").magazine_size, 4, "M202 : 4 roquettes")
	assert_true(WeaponCatalog.get_weapon(&"rocket_javelin").affixes.has(&"homing"), "Javelin guidé")
	assert_true(WeaponCatalog.get_weapon(&"pistol_glock18").automatic, "Glock 18 automatique")
	assert_gt(WeaponCatalog.get_weapon(&"smg_vector").fire_rate, WeaponCatalog.get_weapon(&"smg_mp5").fire_rate * 1.5)
	assert_gt(WeaponCatalog.get_weapon(&"smg_p90").magazine_size, WeaponCatalog.get_weapon(&"smg_mp5").magazine_size)


func test_rarete_plus_haute_plus_forte() -> void:
	# Dans chaque catégorie d'armes, le DPS croît avec la rareté (gain net, pas absurde).
	var by_cat := {}
	for w: WeaponData in _catalog():
		if w.is_gadget():
			continue
		if not by_cat.has(w.category):
			by_cat[w.category] = []
		(by_cat[w.category] as Array).append(w)
	for c: Variant in by_cat:
		var list: Array = by_cat[c]
		list.sort_custom(func(a: WeaponData, b: WeaponData) -> bool: return a.rarity < b.rarity)
		var lo: WeaponData = list[0]
		var hi: WeaponData = list[list.size() - 1]
		assert_gt(hi.get_dps(), lo.get_dps(), "%s : %s > %s" % [c, hi.id, lo.id])
		assert_lt(hi.get_dps(), lo.get_dps() * 4.0, "%s : gain pas absurde" % c)


func test_chaque_arme_a_son_objet() -> void:
	for w: WeaponData in _catalog():
		var it := LootDB.get_item(StringName("wpn_" + String(w.id)))
		if w.id == WeaponCatalog.STARTER_ID:
			assert_null(it, "pas d'objet pour le pistolet de départ")
			continue
		assert_not_null(it, "objet wpn_%s" % w.id)
		if it == null:
			continue
		assert_true(it.is_weapon(), "%s : type weapon + weapon_id" % it.id)
		assert_eq(it.weapon_id, w.id)
		assert_eq(it.rarity, w.rarity, "%s : rareté de l'arme" % it.id)
		assert_eq(it.stack_max, 1)
		assert_null(it.icon, "%s : icône vide (UI → WeaponCatalog.icon_for)" % it.id)
	# Aucun objet wpn_ orphelin (ancien catalogue).
	for it2: ItemData in LootDB.all_items():
		if String(it2.id).begins_with("wpn_"):
			assert_true(WeaponCatalog.has_weapon(it2.weapon_id), "%s : arme du catalogue" % it2.id)


func test_aucun_objet_arme_sans_weapon_id_ni_masque() -> void:
	for it: ItemData in LootDB.all_items():
		if it.type == ItemData.TYPE_WEAPON:
			assert_true(it.is_weapon(), "%s : objet arme sans weapon_id" % it.id)
			assert_true(WeaponCatalog.has_weapon(it.weapon_id), "%s : arme %s connue" % [it.id, it.weapon_id])
		var low := (String(it.id) + " " + it.display_name).to_lower()
		assert_false(low.contains("mask") or low.contains("masque"), "objet lié aux masques : %s" % it.id)


func test_weapon_item_repli_pour_le_pistolet_de_depart() -> void:
	var it := LootDB.weapon_item(WeaponCatalog.get_starter())
	assert_not_null(it)
	assert_true(it.is_weapon())
	assert_eq(it.weapon_id, WeaponCatalog.STARTER_ID)


# --- Tables ----------------------------------------------------------------------------

func test_tables_sans_masques_et_ids_valides() -> void:
	for k: String in LootDB.table_kinds():
		var t := LootDB.get_table(StringName(k))
		assert_not_null(t, k)
		for id: Variant in t.entries:
			assert_false(String(id).contains("mask"), "%s : objet masque %s" % [k, id])
			assert_true(LootDB.has_item(StringName(id)), "%s : objet %s existe" % [k, id])


func test_chaque_biome_peut_donner_des_armes() -> void:
	for biome: String in BIOME_TABLES:
		var world := load(String(BIOME_TABLES[biome])) as Resource
		assert_not_null(world, biome)
		if world == null:
			continue
		var kinds: Array = world.get("container_kinds")
		var weapons := 0
		for k: Variant in kinds:
			var t := LootDB.get_table(StringName(k))
			if t == null:
				continue
			for id: Variant in t.entries:
				var it := LootDB.get_item(StringName(id))
				if it != null and it.is_weapon():
					weapons += 1
		assert_gt(weapons, 0, "%s : des armes dans les conteneurs" % biome)


func test_coffre_plus_genereux_que_ennemi() -> void:
	var chest := LootDB.get_table(&"chest")
	var enemy := LootDB.get_table(&"enemy")
	assert_gt(float(chest.entries.get(&"wpn_smg_mp5", 0.0)), float(enemy.entries.get(&"wpn_smg_mp5", 0.0)))
	# Les hautes raretés pèsent moins que les communes.
	assert_lt(float(chest.entries[&"wpn_rifle_aug"]), float(chest.entries[&"wpn_rifle_ak47"]))
	# Équipement : plus présent dans les caisses militaires que chez les ennemis.
	assert_gt(float(LootDB.get_table(&"crate").entries.get(&"wpn_gadget_frag", 0.0)), float(enemy.entries.get(&"wpn_gadget_frag", 0.0)))


# --- Profil ----------------------------------------------------------------------------

func test_start_raid_retire_l_arsenal_de_la_reserve() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"smg_mp5")
	var b: int = p.call("add_weapon", &"rifle_m4a1")
	var c: int = p.call("add_weapon", &"sniper_m24")
	var lo: Array[int] = [a, b]
	p.call("set_loadout", lo)
	var taken: Array[WeaponData] = p.call("start_raid")
	assert_eq(taken.size(), 2)
	assert_eq(taken[0].id, &"smg_mp5")
	assert_null(p.get("raid_gadget"), "aucun équipement emporté")
	assert_eq((p.get("weapons") as Array).size(), 1, "seul le sniper reste en réserve")
	assert_eq(p.call("weapon_id_of", c), &"sniper_m24")
	assert_true(bool(p.get("raid_in_progress")))


func test_mort_ne_rend_rien_et_redonne_le_pistolet() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"rifle_ak47")
	var lo: Array[int] = [a]
	p.call("set_loadout", lo)
	p.call("start_raid")
	assert_true((p.get("weapons") as Array).is_empty())
	var res: Dictionary = p.call("finish_death")
	assert_true(bool(res["starter_given"]), "pistolet offert")
	assert_eq((res["lost_weapons"] as Array).size(), 1)
	var ws: Array = p.get("weapons")
	assert_eq(ws.size(), 1)
	assert_eq(str(ws[0]["id"]), String(WeaponCatalog.STARTER_ID))
	assert_false(bool(p.get("raid_in_progress")))


func test_mort_sans_pistolet_si_reserve_non_vide() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"rifle_ak47")
	p.call("add_weapon", &"smg_vector")
	var lo: Array[int] = [a]
	p.call("set_loadout", lo)
	p.call("start_raid")
	var res: Dictionary = p.call("finish_death")
	assert_false(bool(res["starter_given"]))
	assert_eq((p.get("weapons") as Array).size(), 1)


func test_extraction_rend_armes_tenues_sac_et_objets() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"smg_mp5")
	var lo: Array[int] = [a]
	p.call("set_loadout", lo)
	p.call("start_raid")
	var bag := Inventory.new(6, 4, 999.0)
	bag.add_item(LootDB.get_item(&"wpn_rifle_m4a1"), 1)
	bag.add_item(LootDB.get_item(&"gold_nugget"), 3)
	var carried: Array[StringName] = [&"smg_mp5", &"rifle_ak47"]
	var res: Dictionary = p.call("finish_extraction", carried, bag)
	var ids: Array = []
	for e: Dictionary in p.get("weapons"):
		ids.append(str(e["id"]))
	ids.sort()
	ids.sort()
	assert_eq(ids, ["rifle_ak47", "rifle_m4a1", "smg_mp5"], "armes tenues + arme du sac")
	assert_eq(int((p.get("items") as Dictionary).get("gold_nugget", 0)), 3, "objets en réserve")
	assert_eq((res["weapons"] as Array).size(), 3)
	var expected_value := LootDB.get_item(&"wpn_rifle_m4a1").value + LootDB.get_item(&"gold_nugget").value * 3
	assert_eq(int(res["loot_value"]), expected_value, "valeur brute du butin")
	# Valeur affichée = or estimé au marchand ; l'extraction ne donne pas d'or (vente manuelle).
	assert_eq(int(res["value"]), Economy.item_sell_price(LootDB.get_item(&"wpn_rifle_m4a1"))
		+ Economy.item_sell_price(LootDB.get_item(&"gold_nugget")) * 3)
	assert_eq(int(p.get("gold")), 0, "pas d'or automatique")
	assert_eq(int(res["gems"]), Profile.extraction_gems(expected_value))
	assert_false(bool(p.get("raid_in_progress")))


func test_gemmes_plafonnees() -> void:
	var cap := int(Balance.get_value("shop", "gems_per_extraction_max", 15))
	assert_eq(Profile.extraction_gems(10_000_000), cap)
	assert_gte(Profile.extraction_gems(0), 0)


func test_pas_de_duplication_si_raid_en_cours_au_chargement() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"sniper_m82")
	p.call("add_weapon", &"smg_vector")
	var lo: Array[int] = [a]
	p.call("set_loadout", lo)
	p.call("start_raid")
	var saved: Dictionary = p.call("to_dict")
	# Jeu quitté en plein raid : rechargement du profil → compte comme une mort.
	var p2 := _new_profile()
	p2.call("from_dict", saved)
	assert_true(bool(p2.get("raid_in_progress")))
	if bool(p2.get("raid_in_progress")):
		p2.call("finish_death")
	var ids: Array = []
	for e: Dictionary in p2.get("weapons"):
		ids.append(str(e["id"]))
	assert_eq(ids, ["smg_vector"], "l'arme emportée n'est pas revenue")
	assert_false(bool(p2.get("raid_in_progress")))


# --- Fin de raid -------------------------------------------------------------------------

func test_ecran_de_fin_extraction_et_mort() -> void:
	var ok := RaidEndScreen.create(true, {"weapons": [&"rifle_ak47"], "items": {&"gold_nugget": 2}, "value": 40, "gems": 3})
	add_child_autofree(ok)
	await wait_frames(1)
	assert_eq(ok.get_title_text(), "Extraction réussie")
	assert_eq((ok.find_child("Verdict", true, false) as Label).text, "EXTRAIT", "Verdict de la maquette")
	assert_eq((ok.find_child("MenuButton", true, false) as Button).text, "CONTINUER")
	assert_eq((ok.find_child("SecondButton", true, false) as Button).text, "VOIR L'INVENTAIRE")
	assert_not_null(ok.find_child("Slab", true, false), "Bandeau violet")
	assert_true(get_tree().paused, "jeu en pause derrière")
	ok.queue_free()
	await wait_frames(1)
	assert_false(get_tree().paused, "pause levée à la fermeture")
	var dead := RaidEndScreen.create(false, {"lost_weapons": [&"smg_mp5", &"gadget_c4"], "starter_given": true})
	add_child_autofree(dead)
	await wait_frames(1)
	assert_eq(dead.get_title_text(), "Tu es mort")
	assert_eq((dead.find_child("Verdict", true, false) as Label).text, "ÉLIMINÉ")
	assert_eq((dead.find_child("MenuButton", true, false) as Button).text, "AU CAMP")
	assert_not_null(dead.find_child("StarterGift", true, false), "Pistolet offert affiché")
	dead.queue_free()
	await wait_frames(1)
	get_tree().paused = false


func test_arsenal_3_armes_plus_1_equipement() -> void:
	var p := _new_profile()
	# 3e emplacement d'arme : débloqué par le niveau de raider (RaiderProgress)
	Profile.raider_xp = RaiderProgress.xp_total_for(RaiderProgress.max_level())
	var uids: Array[int] = []
	for id: StringName in [&"smg_mp5", &"gadget_frag", &"rifle_ak47", &"sniper_m24", &"pistol_deagle", &"gadget_c4"]:
		uids.append(int(p.call("add_weapon", id)))
	p.call("set_loadout", uids)
	var lw: Array[WeaponData] = p.call("get_loadout_weapons")
	assert_eq(lw.size(), 3, "3 armes max")
	var g: WeaponData = p.call("get_loadout_gadget")
	assert_not_null(g)
	assert_eq(g.id, &"gadget_frag", "1 équipement (le premier)")
	var taken: Array[WeaponData] = p.call("start_raid")
	assert_eq(taken.size(), 3)
	for w: WeaponData in taken:
		assert_false(w.is_gadget(), "les armes de raid ne contiennent pas l'équipement")
	assert_eq((p.get("raid_gadget") as WeaponData).id, &"gadget_frag", "raid_gadget fixé")
	# Mort : équipement perdu aussi ; il reste pistol_deagle + gadget_c4 en réserve.
	var res: Dictionary = p.call("finish_death")
	assert_true((res["lost_weapons"] as Array).has(&"gadget_frag"), "équipement perdu")
	assert_false(bool(res["starter_given"]), "il reste une arme en réserve")


func test_pistolet_redonne_si_seulement_des_equipements() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"rifle_ak47")
	p.call("add_weapon", &"gadget_smoke")
	var lo: Array[int] = [a]
	p.call("set_loadout", lo)
	p.call("start_raid")
	var res: Dictionary = p.call("finish_death")
	assert_true(bool(res["starter_given"]), "plus aucune ARME → P9 offert")
	var ids: Array = []
	for e: Dictionary in p.get("weapons"):
		ids.append(str(e["id"]))
	assert_true(ids.has("pistol_p9"))
	assert_true(ids.has("gadget_smoke"))


func test_ecran_de_fin_separe_les_equipements() -> void:
	var split := RaidEndScreen.split_gadgets([&"smg_mp5", &"gadget_drone"])
	assert_eq(split[0], [&"smg_mp5"])
	assert_eq(split[1], [&"gadget_drone"])


func test_ecran_de_fin_trie_par_rarete_et_tient_a_l_ecran() -> void:
	var ids: Array = [&"smg_mp5", &"gadget_frag", &"rifle_aug", &"sniper_m24", &"pistol_deagle", &"rocket_javelin",
		&"gadget_c4", &"rifle_m4a1", &"smg_p90"]
	var sorted := RaidEndScreen.sort_by_rarity(ids)
	var prev := 99
	for id: Variant in sorted:
		var r := WeaponCatalog.get_weapon(StringName(str(id))).rarity
		assert_lte(r, prev, "rareté décroissante")
		prev = r
	assert_eq(sorted[0], &"rifle_aug", "Légendaire d'abord, puis ordre des catégories")
	for ok: bool in [true, false]:
		var key := "weapons" if ok else "lost_weapons"
		var sc := RaidEndScreen.create(ok, {key: ids, "items": {&"gold_nugget": 2, &"bandage": 1}, "value": 99, "gems": 3,
			"starter_given": true, "lost_items": 4, "lost_value": 80})
		add_child_autofree(sc)
		await wait_process_frames(3)
		assert_eq(sc.get_card_ids(), sorted, "cartes dans l'ordre trié")
		assert_true(sc.fits_on_screen(), "tout tient sans défilement vertical (%s)" % sc.get_title_text())
		sc.queue_free()
		await wait_process_frames(1)
	get_tree().paused = false


# --- Dispersion (retour Victor : « pas foufou ») : premier tir net, rafale lisible ----------

func test_dispersion_par_categorie() -> void:
	for id: StringName in [&"rifle_ak47", &"rifle_m4a1", &"rifle_scarh", &"rifle_aug", &"smg_mp5", &"smg_vector", &"smg_p90", &"smg_uzi"]:
		var w := WeaponCatalog.get_weapon(id)
		assert_lte(w.inaccuracy_deg, 2.5, "%s : le premier tir part là où on vise" % id)
		assert_gt(w.spread_bloom_per_shot, 0.0, "%s : la dispersion grandit en rafale" % id)
		assert_gte(w.spread_bloom_max, 4.0, "%s : plafond de rafale lisible" % id)
		assert_lte(w.inaccuracy_deg + w.spread_bloom_max, 9.0, "%s : la rafale reste jouable" % id)
		assert_gte(w.spread_bloom_recovery, 25.0, "%s : se resserre vite" % id)
		assert_gt(w.spread_move_deg, 0.0)
	for l: StringName in [&"lmg_m249", &"lmg_pkm", &"lmg_m60"]:
		var wl := WeaponCatalog.get_weapon(l)
		assert_lte(wl.inaccuracy_deg, 3.0, "%s : premier tir net" % l)
		assert_gt(wl.effective_inaccuracy(0.0, 1.0), wl.inaccuracy_deg + 4.0, "%s : imprécise en courant" % l)
	for g: StringName in [&"shotgun_870", &"shotgun_benelli", &"shotgun_aa12"]:
		assert_lte(WeaponCatalog.get_weapon(g).inaccuracy_deg, 1.5, "%s : gerbe centrée sur la visée" % g)
	for p: StringName in [&"pistol_p9", &"pistol_deagle", &"pistol_p320"]:
		var wp := WeaponCatalog.get_weapon(p)
		assert_lte(wp.inaccuracy_deg + wp.spread_bloom_max, 5.0, "%s : reste précis" % p)
	for s: StringName in [&"sniper_m24", &"sniper_ax50", &"sniper_m82"]:
		var ws := WeaponCatalog.get_weapon(s)
		assert_eq(ws.inaccuracy_deg, 0.0, "%s : très précis à l'arrêt" % s)
		assert_gt(ws.effective_inaccuracy(0.0, 1.0), 5.0, "%s : imprécis en courant" % s)


func test_bloom_monte_en_rafale_et_redescend() -> void:
	var lo := WeaponLoadout.new(3)
	var ak := WeaponCatalog.get_weapon(&"rifle_ak47")
	var list: Array = [ak, WeaponCatalog.get_weapon(&"pistol_p9")]
	lo.set_weapons(list)
	var base := lo.current_inaccuracy(0.0)
	assert_almost_eq(base, ak.inaccuracy_deg, 0.001, "premier tir : imprécision de base")
	for i in 30:
		lo.consume_shot()
		lo.tick(ak.get_fire_interval())
	var full := lo.current_inaccuracy(0.0)
	assert_gt(full, base + 5.0, "la dispersion grandit en tir continu")
	assert_almost_eq(full - base, ak.spread_bloom_max * WeaponLoadout.bloom_mult(), 0.01, "plafonnée")
	assert_gt(lo.current_inaccuracy(1.0), full, "plus imprécis en se déplaçant")
	for i in 60:
		lo.tick(0.1)
	assert_almost_eq(lo.current_inaccuracy(0.0), base, 0.001, "retombe quand on arrête de tirer")
	for i in 10:
		lo.consume_shot()
	assert_true(lo.switch_to(1))
	assert_eq(lo.bloom, 0.0, "changement d'arme : dispersion remise à zéro")


func test_tir_du_joueur_utilise_la_dispersion() -> void:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(p)
	await wait_physics_frames(2)
	var vec := WeaponCatalog.get_weapon(&"smg_vector")
	var list: Array[WeaponData] = [vec]
	p.set_weapons(list)
	await wait_physics_frames(1)
	var s0 := p.get_current_spread()
	assert_almost_eq(s0, vec.inaccuracy_deg, 0.01)
	for i in 12:
		p.loadout.cooldown = 0.0
		p.fire(Vector2.RIGHT)
	assert_gt(p.get_current_spread(), s0 + 5.0, "le cône s'élargit après une rafale")
