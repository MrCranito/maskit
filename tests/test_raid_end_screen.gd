extends GutTest
## Écran de fin de raid : bilan (tué par, survie, éliminations, étage), cartes de progression
## animées (pass de combat, niveau de raider) et détail de l'XP.


func after_each() -> void:
	get_tree().paused = false


func _sample(ok: bool) -> Dictionary:
	var d := {
		"unlock_kills": [],
		"pass_xp": {"xp": 340, "tier_before": 4, "tier_after": 5, "total_before": 1450, "total_after": 1790,
			"breakdown": BattlePassSystem.raid_xp_breakdown({"success": ok, "value": 640, "kills": 7, "time": 412.0})},
		"raider": {"xp": 220, "level_before": 6, "level_after": 7, "unlocks": [],
			"total_before": RaiderProgress.xp_total_for(7) - 120, "total_after": RaiderProgress.xp_total_for(7) + 100},
		"stats": {"kills": 7, "time": 412.0, "floor": -1, "killer": "" if ok else "Le Shérif Sable-Fou"},
	}
	if ok:
		d.merge({"weapons": [&"rifle_m4a1", &"smg_mp5"], "items": {&"gold_nugget": 3}, "value": 640, "gems": 3})
	else:
		d.merge({"lost_weapons": [&"rifle_m4a1", &"smg_mp5"], "lost_items": 6, "lost_value": 420, "lost_estimate": 380})
	return d


func test_detail_de_l_xp_egal_au_total() -> void:
	for ok: bool in [true, false]:
		for s: Dictionary in [{"value": 640, "kills": 7, "time": 412.0}, {"value": 0, "kills": 0, "time": 5.0},
				{"value": 10_000_000, "kills": 999, "time": 99999.0}]:
			var sm := s.merged({"success": ok})
			var sum := 0
			for line: Dictionary in BattlePassSystem.raid_xp_breakdown(sm):
				sum += int(line["xp"])
			assert_eq(sum, BattlePassSystem.raid_xp(sm), "somme du détail = XP du raid (%s)" % str(sm))


func test_add_raid_xp_renvoie_le_bilan() -> void:
	var bp := BattlePassSystem.get_instance()
	var xp0 := bp.xp
	EventBus.raid_started.emit(1)
	for i: int in 2:
		EventBus.enemy_died.emit(null, Vector2.ZERO)
	var r := bp.add_raid_xp({"success": false})
	assert_eq(int(r["kills"]), 2)
	assert_true(r.has("time") and r.has("breakdown"))
	assert_eq(int(r["total_before"]), xp0)
	assert_eq(int(r["total_after"]), bp.xp)
	assert_eq(bp.last_gain, r)


func test_raider_totaux_avant_apres() -> void:
	var before := Profile.raider_xp
	var r := Profile.add_raider_xp(50)
	assert_eq(int(r["total_before"]), before)
	assert_eq(int(r["total_after"]), before + 50)
	Profile.raider_xp = before


func test_nom_de_l_auteur_du_coup() -> void:
	var d := (load("res://data/enemies/fw_bandit.tres") as EnemyData)
	var e := Enemy.spawn(d)
	add_child_autofree(e)
	assert_eq(Player.damage_source_name(e), d.display_name, "ennemi lui-même")
	var shot := Node2D.new()
	e.add_child(shot)
	assert_eq(Player.damage_source_name(shot), d.display_name, "projectile enfant de l'ennemi")
	assert_eq(Player.damage_source_name(null), "")


func test_bilan_et_cartes_de_progression() -> void:
	for ok: bool in [false, true]:
		var sc := RaidEndScreen.create(ok, _sample(ok))
		add_child_autofree(sc)
		await wait_process_frames(3)
		assert_not_null(sc.find_child("RaidStats", true, false), "bilan du raid")
		assert_eq(sc.find_child("KillerChip", true, false) != null, not ok, "« Tué par » seulement à la mort")
		assert_not_null(sc.find_child("XpBreakdown", true, false), "détail de l'XP")
		var raider := sc.find_child("RaiderXp", true, false) as RaidEndScreen.XpCard
		var pass_card := sc.find_child("PassXp", true, false) as RaidEndScreen.XpCard
		assert_not_null(raider)
		assert_not_null(pass_card)
		raider.finish_animation()
		pass_card.finish_animation()
		assert_eq(raider.get_level_shown(), 7, "niveau atteint après l'animation")
		assert_eq(pass_card.get_level_shown(), 5, "palier atteint après l'animation")
		assert_true(sc.fits_on_screen(), "tout tient à l'écran (%s)" % sc.get_title_text())
		var slab := sc.find_child("SlabContent", true, false) as Control
		var vp := sc.get_viewport().get_visible_rect()
		assert_lte(slab.get_global_rect().end.x, vp.end.x + 0.5, "le bandeau ne déborde pas à droite")
		sc.queue_free()
		await wait_process_frames(1)


func test_libelle_d_etage() -> void:
	assert_eq(RaidEndScreen.floor_label(0), "RDC")
	assert_eq(RaidEndScreen.floor_label(1), "Étage 1")
	assert_eq(RaidEndScreen.floor_label(-2), "Sous-sol 2")
