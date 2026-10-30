extends GutTest
## Séquence de mort (DeathOverlay, [death]) et jauge de vie continue du HUD (HealthGauge).
## L'écran de fin met l'arbre en pause (les attentes GUT se figent) : la séquence est observée
## avant la fin, l'écran de fin est vérifié avec [death] outro_time = 0.

const RAID_SCENE := "res://scenes/dungeon/raid.tscn"

var _raid: Raid = null
var _saved: Dictionary = {}
var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""


func before_each() -> void:
	_saved = {}
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""


func after_each() -> void:
	for k: String in _saved:
		Balance._config.set_value("death", k, _saved[k])
	Engine.time_scale = 1.0
	get_tree().paused = false
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


func _set_death(key: String, v: Variant) -> void:
	if not _saved.has(key):
		_saved[key] = Balance.get_value("death", key, null)
	Balance._config.set_value("death", key, v)


func _start_raid() -> void:
	_raid = (load(RAID_SCENE) as PackedScene).instantiate() as Raid
	add_child_autofree(_raid)
	await wait_physics_frames(3)


func _kill(by: String) -> Player:
	var p := _raid.player as Player
	p.hp = 0.0
	p.last_hit_by = by
	p._die()
	return p


# --- Séquence de mort ------------------------------------------------------------------------

func test_balance_death_section() -> void:
	assert_gt(DeathOverlay.outro_time(), 0.0, "séquence de mort réglée ([death] outro_time)")
	assert_lt(Balance.get_float("death", "slowmo_scale", 0.3), 1.0, "ralenti à l'impact")


func test_sequence_titre_tueur_chute_et_monde_assombri() -> void:
	_set_death("outro_time", 60.0)  # minuteur de fin hors du test (pause)
	_set_death("slowmo_scale", 1.0)  # pas de ralenti : attentes GUT en temps normal
	await _start_raid()
	var p := _kill("Pistolero")
	var o := _raid.get_node_or_null(^"DeathOverlay") as DeathOverlay
	assert_not_null(o, "calque de mort créé")
	assert_eq(o.get_title_text(), "ÉLIMINÉ")
	assert_eq(o.get_killer_text(), "par PISTOLERO", "« par <tueur> »")
	assert_false(_raid.is_raid_over(), "pas d'écran de fin pendant la séquence")
	assert_null(_raid.end_screen)
	await wait_seconds(0.9)
	assert_gt(o.get_amount(), 0.0, "le monde se désature / s'assombrit (rampe sur outro_time × 0,45)")
	assert_gt(absf(p.visual.rotation), deg_to_rad(60.0), "le héros s'est effondré")
	assert_not_null(p.get_node_or_null(^"DeathPool"), "flaque sous le cadavre")
	assert_false(_raid.is_raid_over())
	# Fin de séquence (directe, l'écran de fin figerait l'attente).
	_raid._finish_death()
	assert_true(_raid.is_raid_over())
	assert_not_null(_raid.end_screen, "écran de fin après la séquence")


func test_sans_tueur_connu() -> void:
	_set_death("outro_time", 60.0)  # minuteur de fin hors du test (pause)
	_set_death("slowmo_scale", 1.0)
	await _start_raid()
	_kill("")
	var o := _raid.get_node_or_null(^"DeathOverlay") as DeathOverlay
	assert_eq(o.get_killer_text(), "Le raid est perdu")


func test_ralenti_puis_retour_a_la_normale() -> void:
	_set_death("outro_time", 60.0)  # minuteur de fin hors du test (pause)
	_set_death("slowmo_scale", 0.4)
	_set_death("slowmo_time", 0.4)
	await _start_raid()
	_kill("Brute")
	assert_almost_eq(Engine.time_scale, 0.4, 0.01, "ralenti à l'impact")
	# Le ralenti se mesure en temps réel (tweens insensibles à l'échelle de temps).
	var until := Time.get_ticks_msec() + 1500
	while Engine.time_scale < 1.0 and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	assert_eq(Engine.time_scale, 1.0, "vitesse normale rendue")


func test_ralenti_annule_si_le_calque_disparait() -> void:
	_set_death("outro_time", 60.0)  # minuteur de fin hors du test (pause)
	_set_death("slowmo_scale", 0.4)
	_set_death("slowmo_time", 2.0)
	await _start_raid()
	_kill("Brute")
	var o := _raid.get_node_or_null(^"DeathOverlay") as DeathOverlay
	o.free()
	assert_eq(Engine.time_scale, 1.0, "jamais de ralenti coincé")


func test_outro_zero_ecran_de_fin_immediat() -> void:
	_set_death("outro_time", 0.0)
	await _start_raid()
	_kill("Pistolero")
	assert_null(_raid.get_node_or_null(^"DeathOverlay"), "aucune séquence")
	await get_tree().process_frame
	assert_true(_raid.is_raid_over())
	assert_not_null(_raid.end_screen)
	assert_eq(str((_raid.end_screen.summary.get("stats", {}) as Dictionary).get("killer", "")), "Pistolero")


# --- Jauge de vie ----------------------------------------------------------------------------

func _hud() -> Hud:
	var h := Hud.new()
	add_child_autofree(h)
	h.set_health(100.0, 100.0)
	return h


func _gauge(h: Hud) -> HealthGauge:
	return h.find_child("Gauge", true, false) as HealthGauge


func test_jauge_continue_et_chiffres() -> void:
	var h := _hud()
	var g := _gauge(h)
	assert_not_null(g, "jauge continue")
	h.set_health(72.0, 100.0)
	assert_eq((h.find_child("HpValue", true, false) as Label).text, "72")
	assert_eq((h.find_child("HpMax", true, false) as Label).text, "/100")
	assert_almost_eq(g.ratio(), 0.72, 0.001)


func test_traine_de_degats() -> void:
	var h := _hud()
	var g := _gauge(h)
	h.set_health(60.0, 100.0)
	assert_almost_eq(g.shown, 60.0, 0.01, "le remplissage tombe tout de suite")
	assert_almost_eq(g.trail, 100.0, 0.01, "la partie perdue reste visible")
	await wait_seconds(Balance.get_float("hud", "hp_trail_hold", 0.4) * 0.5)
	assert_almost_eq(g.trail, 100.0, 0.01, "maintenue un instant")
	await wait_seconds(Balance.get_float("hud", "hp_trail_hold", 0.4) + Balance.get_float("hud", "hp_trail_time", 0.5) + 0.2)
	assert_almost_eq(g.trail, 60.0, 0.01, "puis descend")
	assert_false(g.is_processing(), "plus d'animation : plus de traitement par frame")


func test_couleurs_et_clignotement_bas() -> void:
	var h := _hud()
	var g := _gauge(h)
	assert_eq(g.fill_color_for(1.0), HealthGauge.GREEN, "plein : vert")
	assert_eq(g.fill_color_for(0.2), HealthGauge.RED, "bas : rouge")
	var mid := g.fill_color_for(0.45)
	assert_true(mid.g < HealthGauge.GREEN.g + 0.01 and mid.r > HealthGauge.GREEN.r, "entre deux : vers l'ambre / le rouge")
	h.set_health(50.0, 100.0)
	assert_false(g.is_low())
	h.set_health(20.0, 100.0)
	assert_true(g.is_low(), "sous 25 % : alerte")
	assert_true(g.is_processing(), "clignotement actif")
	assert_eq((h.find_child("HpValue", true, false) as Label).label_settings.font_color, HealthGauge.RED)
	h.set_health(0.0, 100.0)
	assert_false(g.is_low(), "mort : plus de clignotement")


func test_soin_segment_vert_et_plus_n() -> void:
	var h := _hud()
	var g := _gauge(h)
	h.set_health(40.0, 100.0)
	await wait_seconds(1.2)
	h.set_health(65.0, 100.0)
	assert_almost_eq(g.value, 65.0, 0.01)
	assert_lt(g.shown, 65.0, "le remplissage monte vers la nouvelle valeur")
	var pop := h.find_child("HealPop", true, false) as Label
	assert_not_null(pop, "indication de soin")
	assert_eq(pop.text, "+25")
	await wait_seconds(Balance.get_float("hud", "hp_heal_time", 0.35) + 0.2)
	assert_almost_eq(g.shown, 65.0, 0.01)
