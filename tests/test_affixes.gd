extends GutTest
## Affixes d'armes tirés au drop (phase 8) : catalogue, tirage (nombre par rareté, sans doublon,
## reproductible), effet de chaque affixe, exemplaires (sac, réserve, sauvegarde), extraction et mort.
## Les tests de profil mettent de côté Profile, SaveManager.data et le fichier de sauvegarde.

const PROJECTILE_SCENE := "res://scenes/combat/projectile.tscn"

var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


## Cible minimale du groupe damageable (comme un ennemi : affix_slow_mult).
class Dummy extends Node2D:
	var hp: float = 1000.0
	var taken: float = 0.0
	var affix_slow_mult: float = 1.0

	func take_damage(amount: float, _source: Node) -> void:
		hp -= amount
		taken += amount

	func is_alive() -> bool:
		return hp > 0.0


class FakePlayer extends Node2D:
	var healed: float = 0.0

	func heal(amount: float) -> void:
		healed += amount


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


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _dummy(pos: Vector2 = Vector2.ZERO, in_tree: bool = false) -> Dummy:
	var d := Dummy.new()
	d.position = pos
	d.add_to_group(&"damageable")
	d.add_to_group(&"enemies")
	if in_tree:
		add_child_autofree(d)
	else:
		autofree(d)
	return d


## Projectile portant un seul affixe (hors arbre sauf `in_tree`).
func _projectile(affix_id: StringName, in_tree: bool = false) -> Projectile:
	var p: Projectile
	if in_tree:
		p = (load(PROJECTILE_SCENE) as PackedScene).instantiate() as Projectile
		add_child_autofree(p)
	else:
		p = Projectile.new()
		autofree(p)
	var w := Affixes.make_weapon(WeaponCatalog.get_weapon(&"pistol_glock18"), [affix_id])
	p.affixes = w.get_affix_list()
	return p


# --- Catalogue et tirage -------------------------------------------------------------------

func test_six_affixes_de_la_roadmap() -> void:
	var ids: Array = []
	for a: AffixData in Affixes.all():
		ids.append(String(a.id))
		assert_true(AffixData.KINDS.has(a.kind), "kind connu : %s" % a.id)
		assert_false(a.display_name.is_empty())
		assert_false(a.effect_text().contains("{"), "effet formaté : %s" % a.effect_text())
		assert_gt(a.weight, 0.0)
	for id: String in ["burn", "freeze", "ricochet", "multishot", "lifesteal", "shockwave"]:
		assert_true(ids.has(id), "affixe %s" % id)


func test_nombre_d_affixes_selon_la_rarete() -> void:
	assert_eq(Affixes.count_range(0), Vector2i(0, 0), "Commun : 0")
	assert_eq(Affixes.count_range(1), Vector2i(0, 0), "Peu commun : valeur présente (0)")
	assert_eq(Affixes.count_range(2), Vector2i(1, 1), "Rare : 1")
	assert_eq(Affixes.count_range(3), Vector2i(1, 2), "Épique : 1 à 2")
	assert_eq(Affixes.count_range(4), Vector2i(2, 2), "Légendaire : 2")
	var by_id := {&"rifle_ak47": [0, 0], &"rifle_m4a1": [1, 1], &"rifle_scarh": [1, 2], &"rifle_aug": [2, 2]}
	for id: StringName in by_id:
		var w := WeaponCatalog.get_weapon(id)
		var seen := {}
		for s in 200:
			var ax := Affixes.roll_for(w, _rng(s))
			seen[ax.size()] = true
			assert_between(ax.size(), int(by_id[id][0]), int(by_id[id][1]), "%s : %d affixes" % [id, ax.size()])
		if id == &"rifle_scarh":
			assert_true(seen.has(1) and seen.has(2), "Épique : 1 et 2 affixes apparaissent")


func test_pas_de_doublon_et_categories_respectees() -> void:
	var rocket := WeaponCatalog.get_weapon(&"rocket_javelin")
	var rifle := WeaponCatalog.get_weapon(&"rifle_aug")
	for s in 300:
		var ax := Affixes.roll_for(rifle, _rng(s))
		var uniq := {}
		for a: StringName in ax:
			uniq[a] = true
		assert_eq(uniq.size(), ax.size(), "aucun doublon")
		for a2: StringName in Affixes.roll_for(rocket, _rng(s)):
			assert_true(Affixes.get_affix(a2).allows(rocket), "%s autorisé sur lance-roquettes" % a2)
			assert_false([&"ricochet", &"multishot", &"shockwave"].has(a2), "pas de %s sur roquette" % a2)
	assert_true(Affixes.roll_for(WeaponCatalog.get_weapon(&"gadget_drone"), _rng(1)).is_empty(), "jamais sur un équipement")


func test_tirage_reproductible_et_traits_fixes_intacts() -> void:
	var w := WeaponCatalog.get_weapon(&"rocket_m202")
	assert_eq(Affixes.roll_for(w, _rng(42)), Affixes.roll_for(w, _rng(42)), "même RNG → mêmes affixes")
	var it := LootDB.get_item(&"wpn_rocket_m202")
	var a := Affixes.roll_item(it, _rng(7))
	var b := Affixes.roll_item(it, _rng(7))
	assert_eq(a.weapon_affixes, b.weapon_affixes)
	assert_true(a.weapon_affixes.size() >= 1, "Épique : au moins un affixe")
	assert_true(it.weapon_affixes.is_empty(), "objet partagé du catalogue intact")
	assert_true(w.rolled_affixes.is_empty(), "arme du catalogue intacte")
	assert_true(Player.is_salvo_weapon(a.get_weapon()), "M202 : salve conservée")
	# Trait fixe du Javelin (homing) conservé sur un exemplaire à affixes.
	var jav := Affixes.roll_item(LootDB.get_item(&"wpn_rocket_javelin"), _rng(11)).get_weapon()
	assert_eq(jav.rolled_affixes.size(), 2, "Légendaire : 2 affixes")
	assert_true(jav.affixes.has(&"homing"), "trait fixe homing conservé")
	assert_gt(Player.weapon_homing(jav), 0.0)
	# roll_item ne fait pas avancer le RNG du conteneur.
	var r1 := _rng(99)
	var r2 := _rng(99)
	Affixes.roll_item(it, r1)
	assert_eq(r1.randi(), r2.randi(), "RNG du conteneur non décalé")
	# Commun : jamais d'affixe, objet partagé rendu tel quel.
	var common := LootDB.get_item(&"wpn_rifle_ak47")
	assert_same(Affixes.roll_item(common, _rng(3)), common)


func test_les_conteneurs_donnent_des_armes_a_affixes() -> void:
	var t := LootTable.new()
	t.entries = {&"wpn_rifle_aug": 1.0}
	t.rolls_min = 1
	t.rolls_max = 1
	t.empty_chance = 0.0
	var ctx := LootRoller.Context.make(1, 0, &"combat")
	var e1 := LootRoller.roll(t, _rng(5), ctx)
	var e2 := LootRoller.roll(t, _rng(5), ctx)
	assert_eq(e1.size(), 1)
	var it: ItemData = e1[0]["item"]
	assert_eq(it.weapon_affixes.size(), 2, "Légendaire tombée : 2 affixes")
	assert_eq(it.weapon_affixes, (e2[0]["item"] as ItemData).weapon_affixes, "même conteneur, mêmes affixes")


# --- Effets en jeu (un test par affixe) --------------------------------------------------------

func test_brulure_inflige_des_degats_dans_la_duree() -> void:
	var d := _dummy()
	var p := _projectile(&"burn")
	var a := Affixes.get_affix(&"burn")
	p.apply_hit_affixes(d, 100.0)
	var st := AffixStatus.of(d, false)
	assert_not_null(st, "statut créé")
	assert_true(st.is_burning())
	st.advance(a.duration + 0.5)
	assert_almost_eq(d.taken, 100.0 * a.ratio, 0.5, "dégâts de brûlure = ratio × coup")
	assert_false(st.is_burning(), "brûlure terminée")


func test_gel_ralentit_puis_se_dissipe() -> void:
	var d := _dummy()
	var p := _projectile(&"freeze")
	var a := Affixes.get_affix(&"freeze")
	p.apply_hit_affixes(d, 10.0)
	assert_almost_eq(d.affix_slow_mult, 1.0 - a.slow, 0.001, "vitesse réduite")
	AffixStatus.of(d, false).advance(a.duration + 0.1)
	assert_almost_eq(d.affix_slow_mult, 1.0, 0.001, "vitesse rendue")
	var e := Enemy.new()
	assert_true(&"affix_slow_mult" in e, "Enemy applique le ralentissement")
	e.free()


func test_vol_de_vie_soigne_le_joueur() -> void:
	var d := _dummy()
	var p := _projectile(&"lifesteal")
	var pl := FakePlayer.new()
	pl.add_to_group(&"player")
	autofree(pl)
	p.source = pl
	p.apply_hit_affixes(d, 50.0)
	assert_almost_eq(pl.healed, 50.0 * Affixes.get_affix(&"lifesteal").ratio, 0.001)


func test_onde_de_choc_touche_les_voisins() -> void:
	var a := Affixes.get_affix(&"shockwave")
	var p := _projectile(&"shockwave", true)
	var hit := _dummy(Vector2(500, 500), true)
	var near := _dummy(Vector2(500 + a.radius * 0.5, 500), true)
	var far := _dummy(Vector2(500 + a.radius * 3.0, 500), true)
	p.global_position = hit.global_position
	p.apply_hit_affixes(hit, 100.0)
	assert_gt(near.taken, 0.0, "voisin dans le rayon touché")
	assert_eq(far.taken, 0.0, "hors rayon : rien")


func test_ricochet_repart_vers_un_ennemi_proche() -> void:
	var a := Affixes.get_affix(&"ricochet")
	var p := _projectile(&"ricochet", true)
	var w := Affixes.make_weapon(WeaponCatalog.get_weapon(&"pistol_glock18"), [&"ricochet"])
	p.launch(Vector2(1000, 1000), Vector2.RIGHT, w, null)
	var first := _dummy(Vector2(1000, 1000), true)
	var other := _dummy(Vector2(1000, 1000 + a.radius * 0.5), true)
	p._hit_ids[first.get_instance_id()] = true
	var dmg := p.damage
	assert_true(p._try_ricochet_enemy(), "rebond trouvé")
	assert_eq(p.ricochets, 1)
	assert_almost_eq(p.direction.angle_to(other.global_position - p.global_position), 0.0, 0.01, "vers l'autre ennemi")
	assert_almost_eq(p.damage, dmg * a.damage_mult, 0.01, "dégâts réduits au rebond")
	assert_false(p._try_ricochet_enemy(), "plus de rebond disponible")
	p.deactivate()


func test_multi_tir_ajoute_un_projectile_sans_toucher_au_catalogue() -> void:
	var base := WeaponCatalog.get_weapon(&"pistol_glock18")
	var n0 := maxi(base.projectile_count, 1)
	var w := Affixes.make_weapon(base, [&"multishot"])
	assert_eq(w.projectile_count, n0 + Affixes.get_affix(&"multishot").count)
	assert_gt(w.spread_degrees, base.spread_degrees)
	# Projectile en plus à `ratio` des dégâts : un tir vaut (n0 + count·ratio) projectiles de base.
	var a := Affixes.get_affix(&"multishot")
	assert_almost_eq(w.damage * w.projectile_count, base.damage * (n0 + a.count * a.ratio), 0.01,
		"dégâts totaux d'un tir")
	assert_almost_eq(a.ratio, 0.5, 0.0001, "projectile en plus à 50 %")
	assert_eq(base.projectile_count, n0, "catalogue intact")
	assert_same(Affixes.make_weapon(base, [&"multishot"]), w, "exemplaire partagé (cache)")
	assert_same(Affixes.make_weapon(base, []), base, "sans affixe : la ressource du catalogue")


# --- Exemplaires : sac, valeur, réserve, sauvegarde ---------------------------------------------

func test_valeur_marchande_augmentee() -> void:
	var base := WeaponCatalog.get_weapon(&"rifle_m4a1")
	var w := Affixes.make_weapon(base, [&"burn"])
	assert_gt(Economy.weapon_sell_price(w), Economy.weapon_sell_price(base))
	var it := LootDB.weapon_item(w)
	assert_eq(it.weapon_affixes, [&"burn"] as Array[StringName], "objet de sac garde les affixes")
	assert_gt(it.value, LootDB.get_item(&"wpn_rifle_m4a1").value)
	assert_gt(Economy.item_sell_price(it), Economy.item_sell_price(LootDB.get_item(&"wpn_rifle_m4a1")))
	assert_same(it.get_weapon(), w, "sac → main : même exemplaire")


func test_sac_distingue_et_serialise_les_affixes() -> void:
	var bag := Inventory.new(6, 4, 999.0)
	var base := LootDB.get_item(&"wpn_rifle_m4a1")
	bag.add_item(Affixes.make_item(base, [&"burn"]), 1)
	bag.add_item(Affixes.make_item(base, [&"freeze"]), 1)
	bag.add_item(base, 1)
	bag.sort()
	assert_eq(bag.used_slots(), 3, "trois exemplaires distincts après tri")
	var copy := Inventory.new(6, 4, 999.0)
	copy.from_array(JSON.parse_string(JSON.stringify(bag.to_array())))
	var found: Array = []
	for i in copy.capacity():
		var s := copy.get_slot(i)
		if not s.is_empty():
			found.append(Affixes.key_for(&"x", (s["item"] as ItemData).weapon_affixes))
	found.sort()
	assert_eq(found, ["x", "x+burn", "x+freeze"])


func test_sauvegarde_et_ancienne_sauvegarde() -> void:
	Profile.from_dict({})
	var u := Profile.add_weapon(&"rifle_aug", [&"shockwave", &"burn"])
	var u2 := Profile.add_weapon(&"smg_mp5")
	var d: Dictionary = JSON.parse_string(JSON.stringify(Profile.to_dict()))
	Profile.from_dict({})
	Profile.from_dict(d)
	assert_eq(Profile.weapon_affixes_of(u), [&"burn", &"shockwave"] as Array[StringName], "affixes rechargés (triés)")
	assert_true(Profile.weapon_affixes_of(u2).is_empty())
	assert_eq(Profile.get_weapon_data(u).rolled_affixes.size(), 2)
	# Ancienne sauvegarde : pas de clé « affixes » ; affixe inconnu ignoré.
	Profile.from_dict({"weapons": [{"uid": 3, "id": "rifle_ak47"}, {"uid": 4, "id": "rifle_m4a1", "affixes": ["n_existe_pas", "gel_x", "freeze"]}], "next_uid": 5})
	assert_eq(Profile.weapons.size(), 2)
	assert_true(Profile.weapon_affixes_of(3).is_empty(), "ancienne arme : aucun affixe")
	assert_same(Profile.get_weapon_data(3), WeaponCatalog.get_weapon(&"rifle_ak47"))
	assert_eq(Profile.weapon_affixes_of(4), [&"freeze"] as Array[StringName])


func test_extraction_garde_les_affixes_du_sac_et_des_mains() -> void:
	Profile.from_dict({})
	var u := Profile.add_weapon(&"rifle_m4a1", [&"lifesteal"])
	Profile.set_loadout([u] as Array[int])
	var taken: Array[WeaponData] = Profile.start_raid()
	assert_eq(taken[0].rolled_affixes, [&"lifesteal"] as Array[StringName], "l'arsenal de départ garde ses affixes")
	var bag := Inventory.new(6, 4, 999.0)
	bag.add_item(Affixes.make_item(LootDB.get_item(&"wpn_smg_vector"), [&"ricochet"]), 1)
	var carried: Array = [taken[0]]
	var res := Profile.finish_extraction(carried, bag)
	var got := {}
	for e: Dictionary in Profile.weapons:
		got[str(e["id"])] = e.get("affixes", [])
	assert_eq(got.get("rifle_m4a1"), ["lifesteal"], "arme tenue : affixes conservés")
	assert_eq(got.get("smg_vector"), ["ricochet"], "arme du sac : affixes conservés")
	assert_eq((res["weapon_entries"] as Array).size(), 2)
	# Ancienne API (ids) : toujours acceptée, sans affixe.
	Profile.start_raid()
	Profile.finish_extraction([&"sniper_m24"] as Array[StringName], null)
	assert_eq(Profile.weapon_count(&"sniper_m24"), 1)


func test_mort_perd_les_armes_a_affixes() -> void:
	Profile.from_dict({})
	var u := Profile.add_weapon(&"rifle_aug", [&"burn", &"freeze"])
	Profile.add_weapon(&"smg_mp5")
	Profile.set_loadout([u] as Array[int])
	Profile.start_raid()
	var res := Profile.finish_death()
	assert_eq(Profile.weapon_count(&"rifle_aug"), 0, "arme emportée perdue")
	var lost: Array = res["lost_entries"]
	assert_eq(lost.size(), 1)
	assert_eq((lost[0] as Dictionary)["affixes"], [&"burn", &"freeze"] as Array[StringName])


func test_vente_prefere_l_exemplaire_sans_affixe() -> void:
	Profile.from_dict({})
	var a := Profile.add_weapon(&"rifle_m4a1", [&"burn"])
	var b := Profile.add_weapon(&"rifle_m4a1")
	assert_eq(Profile.spare_weapon_uid(&"rifle_m4a1"), b)
	assert_ne(a, b)
