extends GutTest
## Arsenal (refonte Exfil Rush) : catalogue d'armes, objets armes, tables de butin,
## cycle du profil (départ, mort, extraction) et fin de raid.
## Les tests de profil utilisent l'autoload Profile après avoir mis de côté son contenu,
## SaveManager.data et le fichier de sauvegarde, restaurés à l'identique après chaque test.

## Armes historiques encore lues par le joueur (repli), hors catalogue Exfil Rush.
const LEGACY_IDS: Array[StringName] = [&"starter_revolver", &"starter_bow"]
const SPRITE_IDS: Array[String] = ["starter_pistol", "pistol", "pistol_heavy", "revolver", "revolver_gold",
	"smg", "smg_compact", "shotgun", "shotgun_double", "rifle", "rifle_tactical", "sniper", "sniper_heavy",
	"lmg", "rocket_launcher", "grenade_launcher"]
const BIOME_TABLES := {
	"far_west": "res://data/worlds/world_01_far_west.tres",
	"space_station": "res://data/worlds/world_02_space_station.tres",
	"mall": "res://data/worlds/world_03_mall.tres",
	"underwater": "res://data/worlds/world_04_underwater.tres",
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


func _catalog() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for w: WeaponData in WeaponCatalog.all():
		if not LEGACY_IDS.has(w.id):
			out.append(w)
	return out


# --- Catalogue -------------------------------------------------------------------------

func test_catalogue_au_moins_32_armes_et_9_categories() -> void:
	WeaponCatalog.reload()
	var all := _catalog()
	assert_gte(all.size(), 32, "au moins 32 armes")
	var cats := {}
	var rar_by_cat := {}
	for w: WeaponData in all:
		cats[w.category] = true
		if not rar_by_cat.has(w.category):
			rar_by_cat[w.category] = {}
		rar_by_cat[w.category][w.rarity] = true
	for c: StringName in WeaponData.CATEGORIES:
		assert_true(cats.has(c), "catégorie %s présente" % c)
		assert_gte((rar_by_cat.get(c, {}) as Dictionary).size(), 3, "%s : plusieurs raretés" % c)
	assert_not_null(WeaponCatalog.get_starter(), "pistolet de départ présent")


func test_chaque_arme_est_coherente() -> void:
	for w: WeaponData in _catalog():
		assert_false(w.display_name.is_empty(), "%s : nom" % w.id)
		assert_true(SPRITE_IDS.has(String(w.sprite_id)), "%s : sprite_id %s dans la liste figée" % [w.id, w.sprite_id])
		assert_true(WeaponData.CATEGORIES.has(w.category), "%s : catégorie connue" % w.id)
		assert_between(w.rarity, 0, 4)
		assert_gt(w.damage, 0.0)
		assert_gt(w.fire_rate, 0.0)
		assert_gte(w.magazine_size, 1, "%s : chargeur" % w.id)
		assert_gt(w.value, 0)
		match w.category:
			WeaponData.CAT_SNIPER:
				assert_eq(w.projectile_style, &"tracer")
				assert_gte(w.pierce, 1, "%s : sniper perforant" % w.id)
				assert_lte(w.fire_rate, 1.5)
			WeaponData.CAT_SHOTGUN:
				assert_gt(w.projectile_count, 1, "%s : plombs" % w.id)
				assert_gt(w.spread_degrees, 0.0)
			WeaponData.CAT_SMG:
				assert_true(w.automatic, "%s : automatique" % w.id)
			WeaponData.CAT_LMG:
				assert_gte(w.magazine_size, 100)
				assert_almost_eq(w.move_speed_mult, 0.85, 0.001)
			WeaponData.CAT_ROCKET:
				assert_eq(w.projectile_style, &"rocket")
				assert_true(w.is_explosive())
				assert_lte(w.magazine_size, 2)
				assert_false(w.eject_shells)
			WeaponData.CAT_GRENADE:
				assert_eq(w.projectile_style, &"grenade")
				assert_true(w.is_explosive())


func test_rarete_plus_haute_plus_forte() -> void:
	# Dans chaque catégorie, le DPS du meilleur modèle dépasse celui du moins rare.
	var by_cat := {}
	for w: WeaponData in _catalog():
		if w.id == WeaponCatalog.STARTER_ID:
			continue
		if not by_cat.has(w.category):
			by_cat[w.category] = []
		(by_cat[w.category] as Array).append(w)
	for c: Variant in by_cat:
		var list: Array = by_cat[c]
		list.sort_custom(func(a: WeaponData, b: WeaponData) -> bool: return a.rarity < b.rarity)
		var lo: WeaponData = list[0]
		var hi: WeaponData = list[list.size() - 1]
		if hi.rarity > lo.rarity:
			assert_gt(hi.get_dps(), lo.get_dps(), "%s : %s > %s" % [c, hi.id, lo.id])
			assert_lt(hi.get_dps(), lo.get_dps() * 4.0, "%s : gain pas absurde" % c)


func test_chaque_arme_a_son_objet() -> void:
	for w: WeaponData in _catalog():
		if w.id == WeaponCatalog.STARTER_ID:
			continue
		var it := LootDB.get_item(StringName("wpn_" + String(w.id)))
		assert_not_null(it, "objet wpn_%s" % w.id)
		if it == null:
			continue
		assert_true(it.is_weapon(), "%s : type weapon + weapon_id" % it.id)
		assert_eq(it.weapon_id, w.id)
		assert_eq(it.rarity, w.rarity, "%s : rareté de l'arme" % it.id)
		assert_eq(it.stack_max, 1)
		assert_null(it.icon, "%s : icône vide (UI → WeaponCatalog.icon_for)" % it.id)
		assert_gt(it.weight, 0.0)


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
	assert_gt(float(chest.entries.get(&"wpn_pistol_9mm", 0.0)), float(enemy.entries.get(&"wpn_pistol_9mm", 0.0)))
	# Les hautes raretés pèsent moins que les communes.
	assert_lt(float(chest.entries[&"wpn_rifle_steel_storm"]), float(chest.entries[&"wpn_pistol_9mm"]))


# --- Profil ----------------------------------------------------------------------------

func test_start_raid_retire_l_arsenal_de_la_reserve() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"pistol_9mm")
	var b: int = p.call("add_weapon", &"shotgun_pump")
	var c: int = p.call("add_weapon", &"sniper_hunter")
	var lo: Array[int] = [a, b]
	p.call("set_loadout", lo)
	var taken: Array[WeaponData] = p.call("start_raid")
	assert_eq(taken.size(), 2)
	assert_eq(taken[0].id, &"pistol_9mm")
	assert_eq((p.get("weapons") as Array).size(), 1, "seul le sniper reste en réserve")
	assert_eq(p.call("weapon_id_of", c), &"sniper_hunter")
	assert_true(bool(p.get("raid_in_progress")))


func test_mort_ne_rend_rien_et_redonne_le_pistolet() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"rifle_assault")
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
	var a: int = p.call("add_weapon", &"rifle_assault")
	p.call("add_weapon", &"smg_pocket")
	var lo: Array[int] = [a]
	p.call("set_loadout", lo)
	p.call("start_raid")
	var res: Dictionary = p.call("finish_death")
	assert_false(bool(res["starter_given"]))
	assert_eq((p.get("weapons") as Array).size(), 1)


func test_extraction_rend_armes_tenues_sac_et_objets() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"pistol_9mm")
	var lo: Array[int] = [a]
	p.call("set_loadout", lo)
	p.call("start_raid")
	var bag := Inventory.new(6, 4, 999.0)
	bag.add_item(LootDB.get_item(&"wpn_shotgun_pump"), 1)
	bag.add_item(LootDB.get_item(&"gold_nugget"), 3)
	var carried: Array[StringName] = [&"pistol_9mm", &"rifle_assault"]
	var res: Dictionary = p.call("finish_extraction", carried, bag)
	var ids: Array = []
	for e: Dictionary in p.get("weapons"):
		ids.append(str(e["id"]))
	ids.sort()
	assert_eq(ids, ["pistol_9mm", "rifle_assault", "shotgun_pump"], "armes tenues + arme du sac")
	assert_eq(int((p.get("items") as Dictionary).get("gold_nugget", 0)), 3, "objets en réserve")
	assert_eq((res["weapons"] as Array).size(), 3)
	var expected_value := LootDB.get_item(&"wpn_shotgun_pump").value + LootDB.get_item(&"gold_nugget").value * 3
	assert_eq(int(res["value"]), expected_value)
	assert_eq(int(res["gems"]), Profile.extraction_gems(expected_value))
	assert_false(bool(p.get("raid_in_progress")))


func test_gemmes_plafonnees() -> void:
	var cap := int(Balance.get_value("shop", "gems_per_extraction_max", 15))
	assert_eq(Profile.extraction_gems(10_000_000), cap)
	assert_gte(Profile.extraction_gems(0), 0)


func test_pas_de_duplication_si_raid_en_cours_au_chargement() -> void:
	var p := _new_profile()
	var a: int = p.call("add_weapon", &"lmg_saw")
	p.call("add_weapon", &"smg_pocket")
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
	assert_eq(ids, ["smg_pocket"], "l'arme emportée n'est pas revenue")
	assert_false(bool(p2.get("raid_in_progress")))


# --- Fin de raid -------------------------------------------------------------------------

func test_ecran_de_fin_extraction_et_mort() -> void:
	var ok := RaidEndScreen.create(true, {"weapons": [&"rifle_assault"], "items": {&"gold_nugget": 2}, "value": 40, "gems": 3})
	add_child_autofree(ok)
	await wait_frames(1)
	assert_eq(ok.get_title_text(), "Extraction réussie")
	assert_true(get_tree().paused, "jeu en pause derrière")
	ok.queue_free()
	await wait_frames(1)
	assert_false(get_tree().paused, "pause levée à la fermeture")
	var dead := RaidEndScreen.create(false, {"lost_weapons": [&"pistol_9mm"], "starter_given": true})
	add_child_autofree(dead)
	await wait_frames(1)
	assert_eq(dead.get_title_text(), "Tu es mort")
	dead.queue_free()
	await wait_frames(1)
	get_tree().paused = false
