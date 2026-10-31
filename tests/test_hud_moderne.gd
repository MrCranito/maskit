extends GutTest
## HUD compact (WeaponHud), bouton Recharger, emplacements rapides, inventaire de raid refait,
## tenue de l'arme en déplacement.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
## Viewports réels (hauteur 720, stretch « expand ») : 1280×720, téléphone 2000×923 et 2400×1080.
const VIEWPORTS: Array[Vector2] = [Vector2(1280, 720), Vector2(1560, 720), Vector2(1600, 720)]
## Marges : PC, téléphone à encoche (gauche/droite) avec barre d'accueil.
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


## Faux joueur : armes, munitions, rechargement, soin (contrat Exfil Rush).
class FakeGunPlayer extends Node2D:
	signal weapons_changed
	signal ammo_changed(ammo: int, magazine: int)
	var weapons: Array[WeaponData] = []
	var current_slot: int = 0
	var ammo: int = 2
	var reloading: bool = false
	var reload_calls: int = 0
	var hp: float = 50.0
	var max_hp: float = 100.0
	var switched_to: int = -1
	func get_weapons() -> Array[WeaponData]:
		return weapons
	func get_ammo() -> int:
		return ammo
	func is_reloading() -> bool:
		return reloading
	func get_reload_progress() -> float:
		return 0.5
	func reload() -> void:
		reload_calls += 1
		reloading = true
	func heal(a: float) -> void:
		hp = minf(hp + a, max_hp)
	func switch_to(i: int) -> void:
		switched_to = i
		current_slot = i
		weapons_changed.emit()


func _hud_with(fp: FakeGunPlayer) -> WeaponHud:
	var hud := WeaponHud.new()
	add_child_autofree(hud)
	hud.bind_player(fp)
	return hud


func test_bouton_recharger_lance_le_rechargement() -> void:
	var fp := FakeGunPlayer.new()
	fp.weapons = [WeaponCatalog.get_weapon(&"smg_mp5")]
	fp.ammo = 3
	add_child_autofree(fp)
	var hud := _hud_with(fp)
	await wait_frames(1)
	assert_true(hud.reload_button.alert, "chargeur bas : bouton Recharger allumé")
	hud.reload_button.press()
	assert_eq(fp.reload_calls, 1, "Recharger appelle player.reload()")
	assert_gte(hud.pill.reload, 0.0, "la pastille affiche le rechargement")
	hud.reload_button.press()
	assert_eq(fp.reload_calls, 1, "pas de second rechargement pendant le premier")


func test_recharger_inutile_chargeur_plein() -> void:
	var fp := FakeGunPlayer.new()
	var w := WeaponCatalog.get_weapon(&"smg_mp5")
	fp.weapons = [w]
	fp.ammo = w.magazine_size
	add_child_autofree(fp)
	var hud := _hud_with(fp)
	hud.reload_button.press()
	assert_eq(fp.reload_calls, 0)
	assert_false(hud.reload_button.enabled)


func test_rechargement_auto_quand_le_chargeur_est_vide() -> void:
	var p := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(p)
	await wait_physics_frames(1)
	var w := WeaponCatalog.get_weapon(&"smg_mp5")
	var list: Array[WeaponData] = [w]
	p.set_weapons(list)
	for i in w.magazine_size:
		p.loadout.cooldown = 0.0
		p.fire(Vector2.RIGHT)
	assert_true(p.is_reloading(), "chargeur vide : rechargement automatique")


func test_touche_recharger_dans_l_inputmap() -> void:
	for a: String in ["reload", "weapon_next", "weapon_1", "gadget", "quick_1", "quick_2", "inventory"]:
		assert_true(InputMap.has_action(a), "action %s" % a)
		assert_gt(InputMap.action_get_events(a).size(), 0, "événement pour %s" % a)


func test_autres_armes_en_ronds_toucher_pour_changer() -> void:
	var fp := FakeGunPlayer.new()
	fp.weapons = [WeaponCatalog.get_weapon(&"smg_mp5"), WeaponCatalog.get_weapon(&"rifle_ak47"), null]
	add_child_autofree(fp)
	var hud := _hud_with(fp)
	assert_eq(hud.pill.weapon.id, &"smg_mp5", "arme tenue dans la pastille")
	assert_eq(hud.other_rounds[0].weapon.id, &"rifle_ak47")
	assert_null(hud.other_rounds[1].weapon, "3e emplacement vide")
	hud.other_rounds[0].press()
	assert_eq(fp.switched_to, 1)
	assert_eq(hud.pill.weapon.id, &"rifle_ak47", "la pastille suit l'arme en main")
	assert_eq(hud.other_rounds[0].weapon.id, &"smg_mp5")


# --- Emplacements rapides -------------------------------------------------------------

func test_soin_ramasse_va_dans_un_emplacement_rapide() -> void:
	var inv := Inventory.new()
	inv.add_item(_it(&"bandage"), 2)
	assert_eq(inv.quick_item(0).id, &"bandage", "affectation automatique")
	inv.add_item(_it(&"gold_nugget"), 1)
	assert_eq(inv.quick[1], "", "un objet de valeur n'y va pas")
	assert_false(inv.assign_quick(1, _it(&"gold_nugget")))
	assert_true(inv.assign_quick(1, _it(&"bandage")), "réaffectation")
	assert_eq(inv.quick[0], "", "un objet n'occupe qu'un emplacement")


func test_emplacement_rapide_utilise_un_soin() -> void:
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.add_item(_it(&"bandage"), 2)
	var fp := FakeGunPlayer.new()
	fp.weapons = [WeaponCatalog.get_weapon(&"smg_mp5")]
	add_child_autofree(fp)
	var hud := _hud_with(fp)
	await wait_frames(1)
	assert_eq(hud.quick_rounds[0].count, 2)
	hud.quick_rounds[0].press()
	assert_almost_eq(fp.hp, 50.0 + _it(&"bandage").heal_amount, 0.01, "soin appliqué")
	assert_eq(GameState.raid_inventory.count_of(&"bandage"), 1, "une unité consommée")
	assert_eq(hud.quick_rounds[0].count, 1, "compteur du HUD à jour")
	fp.hp = fp.max_hp
	hud.quick_rounds[0].press()
	assert_eq(GameState.raid_inventory.count_of(&"bandage"), 1, "PV au max : rien consommé")
	assert_string_contains(hud.get_hint_text(), "PV")


func test_emplacement_rapide_avec_le_vrai_joueur() -> void:
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.add_item(_it(&"bandage"), 1)
	var p := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(p)
	await wait_physics_frames(1)
	p.hp = 40.0
	assert_eq(p.use_quick(0), "")
	assert_gt(p.hp, 40.0)
	assert_false(GameState.raid_inventory.has_item(&"bandage"))
	assert_ne(p.use_quick(0), "", "épuisé : refus expliqué")


func test_equipement_en_emplacement_rapide_s_equipe() -> void:
	GameState.raid_inventory = Inventory.new()
	var c4 := _it(&"wpn_gadget_c4")
	GameState.raid_inventory.add_item(c4, 1)
	assert_true(GameState.raid_inventory.assign_quick(0, c4))
	var fp := FakeGadget.new()
	add_child_autofree(fp)
	assert_eq(ItemUse.use_quick(GameState.raid_inventory, 0, fp), "")
	assert_eq(fp.gadget.id, &"gadget_c4")


class FakeGadget extends Node2D:
	var weapon: WeaponData = null
	var gadget: WeaponData = null
	func get_gadget() -> WeaponData:
		return gadget
	func equip_gadget(w: WeaponData) -> WeaponData:
		var old := gadget
		gadget = w
		return old


func test_tout_tient_a_l_ecran_aux_trois_resolutions() -> void:
	var stick_r := Balance.get_float("joystick", "radius", 90.0)
	for vp: Vector2 in VIEWPORTS:
		for safe: Vector4 in SAFES:
			var lay := WeaponHud.compute_layout(vp, safe, 2)
			var area := Rect2(Vector2(safe.x, safe.y), vp - Vector2(safe.x + safe.z, safe.y + safe.w))
			var keys: Array = lay.keys()
			for k: String in keys:
				var r: Rect2 = lay[k]
				assert_true(area.encloses(r), "%s dans la zone sûre (%s, %s)" % [k, vp, safe])
				assert_gte(r.size.y, 54.0, "%s : cible tactile confortable" % k)
			for i in keys.size():
				for j in range(i + 1, keys.size()):
					assert_false((lay[keys[i]] as Rect2).intersects(lay[keys[j]]),
						"%s / %s ne se chevauchent pas (%s)" % [keys[i], keys[j], vp])
			# Rien sur la base des sticks au repos ni sur le bouton action au-dessus du stick droit.
			var rc := Vector2(vp.x * Balance.get_float("joystick", "right_rest_x", 0.87), vp.y * Balance.get_float("joystick", "rest_y", 0.77))
			var lc := Vector2(vp.x * Balance.get_float("joystick", "left_rest_x", 0.13), rc.y)
			var action_c := rc - Vector2(0, stick_r + 58.0 + 26.0 + Balance.get_float("hud", "action_button_lift", 40.0))
			for k: String in keys:
				var r2: Rect2 = lay[k]
				for c: Vector2 in [rc, lc]:
					assert_gt(_dist_rect(r2, c), stick_r - 4.0, "%s hors de la base du stick (%s)" % [k, vp])
				assert_gt(_dist_rect(r2, action_c), 58.0, "%s hors du bouton action (%s)" % [k, vp])


static func _dist_rect(r: Rect2, p: Vector2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return q.distance_to(p)


# --- Tenue de l'arme --------------------------------------------------------------------

func test_arme_tourne_en_douceur_sans_saut() -> void:
	var a := 0.0
	var steps := 0
	while absf(angle_difference(a, PI * 0.9)) > 0.05 and steps < 200:
		var prev := a
		a = PlayerVisual.smooth_angle(a, PI * 0.9, 12.0, 1.0 / 60.0)
		assert_lt(absf(angle_difference(prev, a)), 0.6, "pas de saut d'une image à l'autre")
		assert_lt(absf(angle_difference(prev, a)), absf(angle_difference(prev, PI * 0.9)) * 0.5 + 0.001, "approche progressive")
		steps += 1
	assert_lt(steps, 60, "rejoint la direction en moins d'une seconde")
	# Chemin le plus court à travers ±PI.
	var b := PlayerVisual.smooth_angle(PI - 0.1, -PI + 0.1, 30.0, 1.0 / 60.0)
	assert_true(absf(b) > PI - 0.2, "passe par le côté court")


func test_retournement_avec_hysteresis() -> void:
	assert_eq(PlayerVisual.flip_sign(0.0, -0.01, 0.18), -1.0)
	assert_eq(PlayerVisual.flip_sign(1.0, -0.1, 0.18), 1.0, "marche verticale : pas de bascule")
	assert_eq(PlayerVisual.flip_sign(1.0, -0.3, 0.18), -1.0)
	assert_eq(PlayerVisual.flip_sign(-1.0, 0.1, 0.18), -1.0)
	assert_eq(PlayerVisual.flip_sign(-1.0, 0.25, 0.18), 1.0)


func test_arme_suit_la_marche_sans_viser() -> void:
	var p := PLAYER_SCENE.instantiate() as Player
	add_child_autofree(p)
	await wait_physics_frames(1)
	# Marche vers la gauche sans viser : l'arme finit orientée à gauche, retournée.
	p.velocity = Vector2(-240, 0)
	p.aim_direction = Vector2.LEFT
	p.set("_is_moving", true)
	for i in 40:
		p.visual.update_facing(false, 1.0 / 60.0)
	assert_almost_eq(absf(p.visual.get_weapon_angle()), PI, 0.08, "arme dans le sens de la marche")
	assert_eq(p.visual.get_weapon_flip(), -1.0, "arme retournée à gauche")
	# Marche vers le bas : légère dérive x, pas de retournement intempestif.
	p.velocity = Vector2(10, 240)
	for i in 60:
		p.visual.update_facing(false, 1.0 / 60.0)
	assert_eq(p.visual.get_weapon_flip(), -1.0, "vers le bas : garde son côté (hystérésis)")
