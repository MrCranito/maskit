extends GutTest
## Masques : les 5 ressources chargent, multiplicateurs > 0, cohérence avec CLAUDE.md,
## et Player.apply_mask() modifie les stats sans cumul ni modification de l'arme partagée.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var _saved_mask: StringName = &"kitsune"


func before_each() -> void:
	_saved_mask = GameState.selected_mask_id


func after_each() -> void:
	GameState.selected_mask_id = _saved_mask


func test_all_five_masks_load() -> void:
	assert_eq(MaskData.IDS.size(), 5)
	for id: StringName in MaskData.IDS:
		assert_true(ResourceLoader.exists(MaskData.path_for(id)), "Fichier %s" % id)
		var m := load(MaskData.path_for(id)) as MaskData
		assert_not_null(m, "MaskData %s" % id)
		assert_eq(m.id, id)
		assert_false(m.display_name.is_empty(), "Nom affiché %s" % id)
		assert_false(m.description.is_empty(), "Description %s" % id)
		assert_false(m.tagline.is_empty(), "Description courte %s" % id)
		assert_not_null(m.portrait, "Portrait %s" % id)
		assert_false(String(m.power_id).is_empty(), "power_id %s" % id)
	assert_eq(MaskData.load_all().size(), 5)


func test_multipliers_positive() -> void:
	for m: MaskData in MaskData.load_all():
		for v: float in [m.max_hp_mult, m.speed_mult, m.damage_mult, m.fire_rate_mult]:
			assert_gt(v, 0.0, "Multiplicateur > 0 (%s)" % m.id)
		assert_eq(m.get_stat_entries().size(), 4)


func test_mask_identities_match_design() -> void:
	var k := MaskData.load_mask(&"kitsune")
	var c := MaskData.load_mask(&"colosse")
	var s := MaskData.load_mask(&"spectre")
	# Kitsune : équilibré
	for v: float in [k.max_hp_mult, k.speed_mult, k.damage_mult, k.fire_rate_mult]:
		assert_almost_eq(v, 1.0, 0.001)
	# Colosse : PV ++, vitesse --, dégâts ++, cadence -
	assert_gt(c.max_hp_mult, 1.3)
	assert_lt(c.speed_mult, 1.0)
	assert_gt(c.damage_mult, 1.2)
	assert_lt(c.fire_rate_mult, 1.0)
	# Spectre : vitesse ++, PV -
	assert_gt(s.speed_mult, 1.2)
	assert_lt(s.max_hp_mult, 1.0)


func test_unknown_mask_falls_back_to_default() -> void:
	var m := MaskData.load_mask(&"inexistant")
	assert_not_null(m)
	assert_eq(m.id, MaskData.DEFAULT_ID)
	assert_false(MaskData.exists(&"inexistant"))


func test_apply_mask_changes_player_stats() -> void:
	GameState.selected_mask_id = &"kitsune"
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(p)
	await wait_physics_frames(1)
	var base_hp: float = p.max_hp
	var base_speed: float = p.move_speed
	var shared_weapon: WeaponData = Player.load_default_weapon()
	var base_damage: float = p.weapon.damage
	var base_rate: float = p.weapon.fire_rate

	var colosse := MaskData.load_mask(&"colosse")
	p.apply_mask(colosse)
	assert_eq(p.mask, colosse)
	assert_almost_eq(p.max_hp, base_hp * colosse.max_hp_mult, 0.01)
	assert_almost_eq(p.hp, p.max_hp, 0.01, "PV pleins conservés en proportion")
	assert_almost_eq(p.move_speed, base_speed * colosse.speed_mult, 0.01)
	assert_almost_eq(p.weapon.damage, base_damage * colosse.damage_mult, 0.01)
	assert_almost_eq(p.weapon.fire_rate, base_rate * colosse.fire_rate_mult, 0.01)
	assert_almost_eq(shared_weapon.damage, base_damage, 0.01, "La ressource d'arme partagée n'est pas modifiée")

	# Pas de cumul : réappliquer un autre masque repart des valeurs de base.
	var spectre := MaskData.load_mask(&"spectre")
	p.apply_mask(spectre)
	assert_almost_eq(p.max_hp, base_hp * spectre.max_hp_mult, 0.01)
	assert_almost_eq(p.move_speed, base_speed * spectre.speed_mult, 0.01)
	assert_almost_eq(p.weapon.damage, base_damage * spectre.damage_mult, 0.01)

	# Teinte d'aura + lueur au sol
	var glow := p.get_node_or_null(^"AuraGlow") as Node2D
	assert_not_null(glow, "Lueur d'aura au sol")
	assert_true(glow.visible)

	# Retirer le masque : retour aux valeurs de base
	p.apply_mask(null)
	assert_almost_eq(p.max_hp, base_hp, 0.01)
	assert_almost_eq(p.move_speed, base_speed, 0.01)
	assert_almost_eq(p.weapon.damage, base_damage, 0.01)


func test_player_applies_selected_mask_on_ready() -> void:
	GameState.selected_mask_id = &"colosse"
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(p)
	await wait_physics_frames(1)
	assert_not_null(p.mask)
	assert_eq(p.mask.id, &"colosse")
	var base_hp: float = Balance.get_float("player", "max_hp", 100.0)
	assert_almost_eq(p.max_hp, base_hp * p.mask.max_hp_mult, 0.01)
	assert_almost_eq(p.hp, p.max_hp, 0.01)
