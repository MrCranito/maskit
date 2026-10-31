extends GutTest
## Emplacements rapides refaits (WeaponHud.QuickSlot) : taille tactile, non-chevauchement aux trois
## résolutions avec et sans encoche, badge contenu dans la case, état utilisable / grisé, retour
## visuel à l'utilisation, case vide qui ouvre le sac, aucun traitement par image.

## Viewports réels (hauteur 720, stretch « expand ») et taille d'écran correspondante :
## PC 1280×720, Galaxy S24+ 2000×923, téléphone 2400×1080.
const VIEWPORTS: Array[Vector2] = [Vector2(1280, 720), Vector2(1560, 720), Vector2(1600, 720)]
const SCREEN_H: Array[float] = [720.0, 923.0, 1080.0]
## Marges : sans encoche, puis encoche (gauche/droite) avec barre d'accueil.
const SAFES: Array[Vector4] = [Vector4(16, 16, 16, 16), Vector4(64, 16, 64, 28)]

var _saved_inv: Inventory
var _saved_player = null


func before_each() -> void:
	_saved_inv = GameState.raid_inventory
	_saved_player = GameState.player if is_instance_valid(GameState.player) else null


func after_each() -> void:
	GameState.raid_inventory = _saved_inv
	GameState.player = _saved_player if is_instance_valid(_saved_player) else null


func _it(id: StringName) -> ItemData:
	return LootDB.get_item(id)


class FakeHealer extends Node2D:
	signal quick_used(index: int, message: String)
	var hp: float = 50.0
	var max_hp: float = 100.0
	var cooldown_s: float = 0.0
	func heal(a: float) -> void:
		hp = minf(hp + a, max_hp)
	func use_quick(i: int) -> String:
		var msg := ItemUse.use_quick(GameState.raid_inventory, i, self)
		quick_used.emit(i, msg)
		return msg
	func get_quick_cooldown(_i: int) -> float:
		return cooldown_s


class FakeBag extends Node:
	var opened: int = 0
	func toggle_inventory() -> void:
		opened += 1


func _hud_with(p: Node2D) -> WeaponHud:
	add_child_autofree(p)
	var hud := WeaponHud.new()
	add_child_autofree(hud)
	hud.bind_player(p)
	return hud


static func _dist_rect(r: Rect2, p: Vector2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return q.distance_to(p)


func test_cases_tactiles_sans_chevauchement_aux_trois_resolutions() -> void:
	var grow := Balance.get_float("hud", "quick_hit_grow", 5.0)
	var stick_r := Balance.get_float("joystick", "radius", 90.0)
	for v in VIEWPORTS.size():
		var vp := VIEWPORTS[v]
		var scale := SCREEN_H[v] / vp.y
		for safe: Vector4 in SAFES:
			var lay := WeaponHud.compute_layout(vp, safe, 2)
			var area := Rect2(Vector2(safe.x, safe.y), vp - Vector2(safe.x + safe.z, safe.y + safe.w))
			var lc := Vector2(vp.x * Balance.get_float("joystick", "left_rest_x", 0.13), vp.y * Balance.get_float("joystick", "rest_y", 0.77))
			for qi in 2:
				var qk := "quick%d" % qi
				var q: Rect2 = lay[qk]
				assert_gte(minf(q.size.x, q.size.y) * scale, 64.0, "%s : au moins 64 px à l'écran (%s, %s)" % [qk, vp, safe])
				assert_true(area.encloses(q), "%s dans la zone sûre (%s, %s)" % [qk, vp, safe])
				assert_gt(_dist_rect(q, lc), stick_r - 4.0, "%s hors de la base du stick (%s, %s)" % [qk, vp, safe])
				# Zone tactile (case + marge) : ne déborde sur aucun autre élément du HUD.
				for k: String in lay.keys():
					if k == qk:
						continue
					var other: Rect2 = lay[k]
					var other_hit := other.grow(grow) if k.begins_with("quick") else other
					assert_false(q.grow(grow).intersects(other_hit),
						"%s / %s : zones tactiles séparées (%s, %s)" % [qk, k, vp, safe])
				# Message de refus au-dessus de la 1re case : reste à l'écran.
				if qi == 0:
					assert_gte(q.position.y - 30.0, area.position.y, "message au-dessus des cases à l'écran (%s, %s)" % [vp, safe])


func test_badge_ne_deborde_pas_de_la_case() -> void:
	var s := WeaponHud.quick_size()
	var cut := Balance.get_float("hud", "quick_cut", 12.0)
	var inner := Rect2(Vector2.ZERO, Vector2(s, s)).grow(-Balance.get_float("hud", "quick_border", 2.0) + 0.01)
	for n: int in [0, 1, 3, 9, 20, 99]:
		var b := WeaponHud.QuickSlot.badge_rect(Vector2(s, s), n)
		assert_true(inner.encloses(b), "badge ×%d dans la case" % n)
		# Coin bas-droit du badge biseauté comme la case : reste sous la diagonale du biseau.
		var corner := b.end - Vector2(minf(cut, b.size.y * 0.6), 0)
		assert_lte(corner.x + corner.y, s + s - cut + 0.5, "badge ×%d sous le biseau" % n)
		assert_gte(b.size.y, 18.0, "badge ×%d lisible" % n)


func test_soin_grise_quand_les_pv_sont_pleins() -> void:
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.add_item(_it(&"bandage"), 2)
	var p := FakeHealer.new()
	p.hp = p.max_hp
	var hud := _hud_with(p)
	await wait_frames(1)
	var slot := hud.quick_rounds[0]
	assert_eq(slot.item.id, &"bandage")
	assert_false(slot.usable, "PV pleins : soin grisé")
	p.hp = 30.0
	hud._poll()
	assert_true(slot.usable, "PV entamés : soin utilisable")
	assert_false(WeaponHud.quick_usable(_it(&"bandage"), 0, p), "plus d'exemplaire : grisé")
	assert_true(WeaponHud.quick_usable(_it(&"wpn_gadget_c4"), 1, p), "équipement : toujours utilisable")
	assert_false(hud.quick_rounds[1].usable, "case vide : rien à utiliser")


func test_utilisation_flash_rebond_et_recharge() -> void:
	GameState.raid_inventory = Inventory.new()
	GameState.raid_inventory.add_item(_it(&"bandage"), 3)
	var p := FakeHealer.new()
	p.cooldown_s = 1.0
	var hud := _hud_with(p)
	await wait_frames(1)
	var slot := hud.quick_rounds[0]
	slot.press()
	assert_eq(slot.count, 2, "le chiffre décrémente")
	assert_gt(slot._bump, 0.0, "rebond du chiffre")
	assert_gt(slot._flash, 0.0, "flash")
	assert_true(slot._flash_ok, "flash de réussite")
	assert_gt(slot.cooldown, 0.0, "temps de recharge circulaire lancé")
	await wait_seconds(Balance.get_float("hud", "quick_bump_time", 0.3) + 0.1)
	assert_eq(slot._bump, 0.0, "rebond terminé")
	assert_eq(slot._flash, 0.0, "flash terminé")
	# Refus (PV pleins) : flash rouge, rien consommé, pas de recharge.
	p.hp = p.max_hp
	p.cooldown_s = 0.0
	slot.press()
	assert_eq(slot.count, 2)
	assert_false(slot._flash_ok, "flash de refus")
	assert_false(slot.is_processing(), "aucun traitement par image")
	assert_false(hud.is_processing(), "HUD au repos : aucun traitement par image")


func test_case_vide_ouvre_le_sac() -> void:
	GameState.raid_inventory = Inventory.new()
	var bag := FakeBag.new()
	bag.add_to_group(&"inventory_hud")
	add_child_autofree(bag)
	var hud := _hud_with(FakeHealer.new())
	await wait_frames(1)
	assert_null(hud.quick_rounds[0].item)
	hud.quick_rounds[0].press()
	assert_eq(bag.opened, 1, "emplacement vide : le sac s'ouvre")


func test_icone_reduite_a_la_taille_affichee() -> void:
	var slot := WeaponHud.QuickSlot.new()
	add_child_autofree(slot)
	var it := _it(&"bandage")
	var tex := slot._icon(it, Vector2(48, 48), false)
	assert_not_null(tex)
	var sc := slot._screen_scale()
	assert_almost_eq(float(maxi(tex.get_width(), tex.get_height())), roundf(48.0 * sc), 1.0, "icône réduite une fois à sa taille écran")
	assert_same(slot._icon(it, Vector2(48, 48), false), tex, "en cache")
	assert_ne(slot._icon(it, Vector2(48, 48), true), tex, "version grisée distincte")
	# Équipement (icône d'arme 2:1) : proportions conservées.
	var gadget := slot._icon(_it(&"wpn_gadget_drone"), Vector2(48, 48), false)
	if gadget != null:
		assert_lte(gadget.get_height(), gadget.get_width() + 1, "icône d'arme non déformée")
