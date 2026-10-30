extends GutTest
## Armes visibles partout : l'arme réellement équipée (image Blender + skin d'arme) est tenue par le
## héros des menus (lobby, aperçus, cartes de boutique), par le coéquipier au menu, au salon et en
## raid (ses armes et SES skins, jamais ceux du profil local), changement d'arme répercuté.

var _saved_profile: Dictionary = {}
var _saved_data: Dictionary = {}


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_data = SaveManager.data.duplicate(true)
	WeaponSkin.enabled_override = 1


func after_each() -> void:
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_data
	SaveManager.save()
	WeaponSkin.enabled_override = -1


## Profil de test : AK-47 (skin Tigre équipé) puis MP5 dans l'arsenal de départ.
func _profile_with_ak_tiger() -> void:
	Profile.from_dict({})
	var ak := Profile.add_weapon(&"rifle_ak47")
	var mp5 := Profile.add_weapon(&"smg_mp5")
	Profile.set_loadout([ak, mp5] as Array[int])
	Profile.skins_owned.append(&"wsk_ak47_tiger")
	assert_true(WeaponSkin.equip(&"wsk_ak47_tiger"))


# --- Logique pure ------------------------------------------------------------------------

func test_forced_skin_for_matches_weapon_only() -> void:
	var ak := WeaponCatalog.get_weapon(&"rifle_ak47")
	var aug := WeaponCatalog.get_weapon(&"rifle_aug")
	assert_eq(WeaponView.forced_skin_for(ak, {"rifle_ak47": "wsk_ak47_tiger"}).id, &"wsk_ak47_tiger")
	assert_null(WeaponView.forced_skin_for(aug, {"rifle_aug": "wsk_ak47_tiger"}), "Skin d'une autre arme refusé")
	assert_null(WeaponView.forced_skin_for(ak, {"rifle_ak47": "char_gign"}), "Skin de personnage refusé")
	assert_null(WeaponView.forced_skin_for(ak, {}), "Aucun skin")
	assert_null(WeaponView.forced_skin_for(null, {"rifle_ak47": "wsk_ak47_tiger"}))


func test_skin_map_and_ids_for() -> void:
	var m := WeaponSkin.skin_map(["rifle_ak47", "smg_mp5", ""], ["wsk_ak47_tiger", "", "wsk_mp5_desert"])
	assert_eq(m, {"rifle_ak47": "wsk_ak47_tiger"}, "Paires vides ignorées")
	_profile_with_ak_tiger()
	var ids := WeaponSkin.skin_ids_for(Profile.get_loadout_weapons())
	assert_eq(ids, ["wsk_ak47_tiger", ""] as Array[String], "Même ordre que les armes")
	WeaponSkin.enabled_override = 0
	assert_eq(WeaponSkin.skin_ids_for(Profile.get_loadout_weapons()), ["", ""] as Array[String], "Skins désactivés")


func test_main_weapon_loadout_then_best_then_starter() -> void:
	Profile.from_dict({})
	var main := Profile.get_main_weapon()
	assert_not_null(main, "Réserve vide : pistolet de départ")
	assert_eq(main.id, WeaponCatalog.STARTER_ID)
	Profile.add_weapon(&"pistol_p9")
	var m82 := Profile.add_weapon(&"sniper_m82")
	assert_eq(Profile.get_main_weapon().id, &"sniper_m82", "Sans arsenal : meilleure arme de la réserve")
	var p9 := Profile.weapons[0]["uid"] as int
	Profile.set_loadout([p9, m82] as Array[int])
	assert_eq(Profile.get_main_weapon().id, &"pistol_p9", "Première arme de l'arsenal de départ")


func test_held_span_and_weapon_scale_keep_game_proportions() -> void:
	var ak := WeaponCatalog.get_weapon(&"rifle_ak47")
	var glock := WeaponCatalog.get_weapon(&"pistol_glock18")
	var span_ak := WeaponView.held_span(ak)
	var span_glock := WeaponView.held_span(glock)
	assert_gt(span_ak, span_glock * 1.5, "Un fusil est bien plus long qu'un pistolet")
	var ppu := Balance.get_float("menu", "lobby_weapon_px_per_unit", 8.0)
	assert_almost_eq(LobbyHero.weapon_scale(ak, 100.0) * 100.0, span_ak * ppu, 0.01)
	# Arme sans sprite ni repli de catégorie (silhouette dessinée) : longueur de la silhouette.
	var w := WeaponData.new()
	w.category = &"test_cat_xyz"
	w.id = &"test_no_sprite_xyz"
	assert_almost_eq(WeaponView.held_span(w), WeaponView.shape_muzzle(&"test_cat_xyz").length(), 0.01)


func test_held_from_info() -> void:
	var h := LobbyHero.held_from_info({"loadout": ["sniper_m82", "rocket_rpg7"], "wskins": ["wsk_m82_night", ""]})
	assert_eq((h["weapon"] as WeaponData).id, &"sniper_m82", "Première arme de l'arsenal")
	assert_eq(h["skins"], {"sniper_m82": "wsk_m82_night"})
	h = LobbyHero.held_from_info({"loadout": ["sniper_m82"], "main": "rifle_ak47", "main_skin": "wsk_ak47_tiger"})
	assert_eq((h["weapon"] as WeaponData).id, &"rifle_ak47", "« main » prioritaire")
	assert_eq(str((h["skins"] as Dictionary).get("rifle_ak47", "")), "wsk_ak47_tiger")
	h = LobbyHero.held_from_info({"name": "Ancienne version"})
	assert_not_null(h["weapon"], "Infos sans arsenal : arme par défaut")


func test_local_info_sends_weapon_skins() -> void:
	_profile_with_ak_tiger()
	var info := CoopLobby.local_info_dict("Moi", false)
	assert_eq(info["loadout"], ["rifle_ak47", "smg_mp5"])
	assert_eq(info["wskins"], ["wsk_ak47_tiger", ""] as Array[String])
	assert_eq(info["main"], "rifle_ak47")
	assert_eq(info["main_skin"], "wsk_ak47_tiger")


# --- WeaponView ---------------------------------------------------------------------------

func test_weapon_view_forced_skins_never_leak_local_skin() -> void:
	_profile_with_ak_tiger()
	var ak := WeaponCatalog.get_weapon(&"rifle_ak47")
	var local := WeaponView.new()
	add_child_autofree(local)
	local.set_weapon(ak, false)
	assert_eq(local.get_skin_id(), "wsk_ak47_tiger", "Joueur local : son skin")
	var mate := WeaponView.new()
	add_child_autofree(mate)
	mate.set_skin_ids({})
	mate.set_weapon(ak, false)
	assert_eq(mate.get_skin_id(), "", "Coéquipier sans skin : pas le skin du profil local")
	mate.set_skin_ids({"rifle_ak47": "wsk_ak47_tiger"})
	assert_eq(mate.get_skin_id(), "wsk_ak47_tiger", "Skin du coéquipier appliqué tout de suite")
	assert_true(mate.get_texture().resource_path.contains("/skins/"), "Texture dédiée du skin")


func test_weapon_view_icon_mode_uses_blender_icon_and_grip() -> void:
	Profile.from_dict({})  # aucun skin équipé
	var wv := WeaponView.new()
	wv.icon_mode = true
	add_child_autofree(wv)
	wv.set_weapon(WeaponCatalog.get_weapon(&"rifle_ak47"), false)
	assert_eq(wv.get_texture().resource_path, "res://assets/ui/weapons/rifle_ak47.png")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/weapons/rifle_ak47.json"))
	var expected := Vector2(meta["muzzle"][0], meta["muzzle"][1]) - Vector2(meta["grip"][0], meta["grip"][1])
	assert_almost_eq(wv.muzzle_local.x, expected.x, 0.01, "Bout du canon depuis la poignée (px d'icône)")
	assert_almost_eq(wv.muzzle_local.y, expected.y, 0.01)


func test_every_held_sprite_has_icon_meta() -> void:
	for f: String in DirAccess.get_files_at(WeaponView.WEAPON_ICON_DIR):
		if not f.ends_with(".png") or f.begins_with("gadget"):
			continue
		var j := WeaponView.WEAPON_ICON_DIR + f.get_basename() + ".json"
		assert_true(FileAccess.file_exists(j), "Métadonnées d'icône : %s" % j)
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(j)) if FileAccess.file_exists(j) else null
		assert_true(d is Dictionary and (d as Dictionary).has("grip") and (d as Dictionary).has("muzzle"),
			"grip et muzzle lisibles : %s" % j)


# --- Héros des menus ------------------------------------------------------------------------

func test_menu_poses_are_weapon_free_with_hands_layer() -> void:
	assert_true(LobbyHero.poses_have_grip(), "hero_menu.json : main et angle de l'arme")
	for s: SkinData in SkinData.all_of_kind(SkinData.KIND_CHARACTER):
		var id := LobbyHero.sheet_for(s)
		assert_not_null(LobbyHero.hands_texture(id), "Calque des mains : %s" % id)


func test_lobby_hero_holds_profile_main_weapon_with_skin() -> void:
	_profile_with_ak_tiger()
	var h := LobbyHero.new()
	add_child_autofree(h)
	await wait_frames(1)
	assert_true(h.weapon_pivot.visible, "Arme tenue")
	assert_eq(h.weapon.id, &"rifle_ak47", "Arme principale du profil")
	assert_eq(h.weapon_view.get_skin_id(), "wsk_ak47_tiger", "Avec son skin")
	assert_true(h.hands.visible, "Mains devant l'arme")
	assert_gt(h.hands.get_index(), h.weapon_pivot.get_index(), "Mains dessinées après l'arme")
	# Changement d'arsenal : l'arme suit.
	var m82 := Profile.add_weapon(&"sniper_m82")
	Profile.set_loadout([m82] as Array[int])
	Profile.changed.emit()
	assert_eq(h.weapon.id, &"sniper_m82", "Arme principale mise à jour")
	assert_eq(h.weapon_view.get_skin_id(), "", "Pas de skin sur le M82")


func test_lobby_hero_mate_uses_partner_weapon_and_skins() -> void:
	_profile_with_ak_tiger()
	var mate := LobbyHero.new(false)
	mate.set_weapon(WeaponCatalog.get_weapon(&"rifle_ak47"), {})
	add_child_autofree(mate)
	await wait_frames(1)
	assert_eq(mate.weapon.id, &"rifle_ak47")
	assert_eq(mate.weapon_view.get_skin_id(), "", "Le skin local ne passe pas au coéquipier")
	mate.set_weapon(WeaponCatalog.get_weapon(&"sniper_m82"), {"sniper_m82": "wsk_m82_night"})
	assert_eq(mate.weapon.id, &"sniper_m82")
	assert_eq(mate.weapon_view.get_skin_id(), "wsk_m82_night")
	Profile.changed.emit()
	assert_eq(mate.weapon.id, &"sniper_m82", "Le profil local ne remplace pas l'arme du coéquipier")


func test_hero_preview_and_pose_rect_hold_weapon() -> void:
	_profile_with_ak_tiger()
	var hp := HeroPreview.new()
	hp.size = Vector2(300, 460)
	add_child_autofree(hp)
	await wait_frames(1)
	assert_eq(hp.get_weapon().id, &"rifle_ak47", "Aperçu : arme principale")
	hp.set_weapon(WeaponCatalog.get_weapon(&"rocket_rpg7"), {"rocket_rpg7": "wsk_rpg7_rust"})
	assert_eq(hp.get_weapon().id, &"rocket_rpg7", "Aperçu imposé (salon coop)")
	assert_eq(hp.hero.weapon_view.get_skin_id(), "wsk_rpg7_rust")
	var card := HeroPoseRect.make(SkinData.get_skin(&"char_gign"))
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.size = Vector2(160, 240)
	add_child_autofree(card)
	await wait_frames(1)
	assert_true(card.is_lobby_pose())
	assert_true(card.held.visible, "Carte : arme tenue")
	assert_eq(card.get_weapon().id, &"rifle_ak47")
	assert_eq(card.weapon_view.get_skin_id(), "wsk_ak47_tiger")
	var region := (card.texture as AtlasTexture).region
	var wr := card.weapon_view.get_item_rect()
	var muzzle := card.pivot.transform * Vector2(wr.end.x, wr.position.y + wr.size.y * 0.5)
	assert_true(region.grow(1.0).has_point(muzzle), "Recadrage élargi : l'arme tient dans la carte")


# --- Coop ---------------------------------------------------------------------------------

func test_coop_avatar_weapon_skins_and_switch() -> void:
	_profile_with_ak_tiger()
	var a := CoopAvatar.create("Moreau", &"char_gign")
	add_child_autofree(a)
	await wait_frames(1)
	var ids: Array[String] = ["rifle_ak47", "rocket_rpg7"]
	a.apply_loadout(ids, 0, "", 0, -1.0, ["", "wsk_rpg7_rust"] as Array[String])
	var wv := a.visual.weapon_view
	assert_eq(wv.weapon.id, &"rifle_ak47", "Arme tenue du coéquipier")
	assert_eq(wv.get_skin_id(), "", "Son AK n'a pas de skin : pas le Tigre du profil local")
	# Changement d'arme (état réseau) : répercuté, avec son skin.
	var st := NetProtocol.PlayerState.new()
	st.time_ms = NetProtocol.now_ms()
	st.position = Vector2(10, 10)
	st.aim = Vector2.LEFT
	st.slot = 1
	st.hp_ratio = 1.0
	a.apply_state(st)
	assert_eq(a.weapon.id, &"rocket_rpg7")
	a.visual.weapon_view.set_weapon(a.weapon, false)  # fin d'animation de changement
	assert_eq(wv.get_skin_id(), "wsk_rpg7_rust")
	# Ancienne version (aucun skin envoyé) : aucun skin, jamais ceux du profil local.
	a.apply_loadout(["rifle_ak47"] as Array[String], 0, "", 0, -1.0)
	assert_eq(wv.weapon.id, &"rifle_ak47")
	assert_eq(wv.get_skin_id(), "")


func test_coop_loadout_message_carries_skins_backward_compatible() -> void:
	# Message LOADOUT tel qu'envoyé par CoopRaid._send_loadout (skins en fin de message).
	var w := NetProtocol.Writer.new()
	w.begin(NetProtocol.Msg.LOADOUT)
	w.text("Moreau")
	w.text("char_gign")
	w.u8(2)
	w.text("sniper_m82")
	w.text("rocket_rpg7")
	w.u8(0)
	w.text("")
	w.u8(0)
	w.f32(100.0)
	w.text("wsk_m82_night")
	w.text("")
	w.end()
	var r := NetProtocol.Reader.new()
	r.reset(w.bytes())
	assert_eq(r.next_msg(), NetProtocol.Msg.LOADOUT)
	r.text()
	r.text()
	var n := r.u8()
	for i: int in n:
		r.text()
	r.u8()
	r.text()
	r.u8()
	r.f32()
	assert_gt(r.remaining(), 0, "Skins présents en fin de message")
	assert_eq(r.text(), "wsk_m82_night")
	# Un lecteur ancien qui s'arrête avant les skins passe proprement au message suivant.
	assert_eq(r.next_msg(), 0)
