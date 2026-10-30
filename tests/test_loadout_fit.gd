extends GutTest
## Arsenal de départ : le libellé du bouton principal tient dans le bandeau (retour de Victor :
## en coop, « Valider mon arsenal » sortait de l'écran et poussait la fiche de l'arme dehors).


func test_bouton_valider_tient_dans_le_bandeau() -> void:
	for coop: bool in [false, true]:
		var s: ArsenalScreen = CoopLoadout.new() if coop else ArsenalScreen.new()
		if not coop:
			s.loadout_mode = true
			s.raid_scene = ""
		add_child_autofree(s)
		await wait_process_frames(3)
		var vp := s.get_viewport_rect()
		var col := s.find_child("SlabContent", true, false) as Control
		assert_not_null(col)
		assert_lte(col.get_global_rect().end.x, vp.end.x + 0.5, "colonne du bandeau dans l'écran (coop=%s)" % coop)
		assert_lte(s.validate_button.get_global_rect().end.x, vp.end.x + 0.5, "bouton dans l'écran (coop=%s)" % coop)
		s.queue_free()
		await wait_process_frames(1)
