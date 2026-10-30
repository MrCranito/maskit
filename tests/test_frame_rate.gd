extends GutTest
## Images par seconde (FrameRate) : 120 i/s si l'écran le permet, 60, ou éco ; reprise de
## l'ancien réglage « Économie d'énergie » ; bouton des Options.

var _saved_fps: int = 0
var _saved_settings: Variant = null


func before_each() -> void:
	_saved_fps = Engine.max_fps
	var data: Dictionary = SaveManager.get("data")
	_saved_settings = (data.get("settings", {}) as Dictionary).duplicate() if data.get("settings") is Dictionary else {}


func after_each() -> void:
	Engine.max_fps = _saved_fps
	var data: Dictionary = SaveManager.get("data")
	data["settings"] = _saved_settings


func test_targets_follow_screen_refresh() -> void:
	assert_eq(FrameRate.target_for(FrameRate.MODE_MAX, 120.0), 120, "écran 120 Hz → 120 i/s")
	assert_eq(FrameRate.target_for(FrameRate.MODE_MAX, 119.88), 120, "119,88 Hz arrondi")
	assert_eq(FrameRate.target_for(FrameRate.MODE_MAX, 90.0), 90, "écran 90 Hz → 90 i/s")
	assert_eq(FrameRate.target_for(FrameRate.MODE_MAX, 60.0), 60, "écran 60 Hz → 60 i/s")
	assert_eq(FrameRate.target_for(FrameRate.MODE_MAX, 144.0), FrameRate.cap(), "plafonné à 120")
	assert_eq(FrameRate.target_for(FrameRate.MODE_MAX, 30.0), 60, "jamais moins de 60 en mode max")
	assert_eq(FrameRate.target_for(FrameRate.MODE_60, 120.0), 60)
	assert_eq(FrameRate.target_for(FrameRate.MODE_ECO, 120.0), FrameRate.eco_fps())


func test_apply_sets_engine_max_fps_and_persists() -> void:
	var fps := FrameRate.apply(FrameRate.MODE_60, true)
	assert_eq(fps, 60)
	assert_eq(Engine.max_fps, 60)
	assert_eq(FrameRate.saved_mode(), FrameRate.MODE_60)
	FrameRate.apply(FrameRate.MODE_ECO, true)
	assert_eq(Engine.max_fps, FrameRate.eco_fps())
	assert_true(bool(MenuKit.get_setting(&"power_saving", false)), "effets allégés en éco (CombatFx)")
	FrameRate.apply(FrameRate.MODE_MAX, true)
	assert_eq(Engine.max_fps, FrameRate.target_for(FrameRate.MODE_MAX))
	assert_false(bool(MenuKit.get_setting(&"power_saving", true)))


func test_old_power_saving_setting_maps_to_eco() -> void:
	var data: Dictionary = SaveManager.get("data")
	data["settings"] = {"power_saving": true}
	assert_eq(FrameRate.saved_mode(), FrameRate.MODE_ECO)
	data["settings"] = {}
	assert_eq(FrameRate.saved_mode(), String(Balance.get_value("display", "default_frame_rate", "max")))


func test_cycle_and_labels() -> void:
	assert_eq(FrameRate.next_mode(FrameRate.MODE_MAX), FrameRate.MODE_60)
	assert_eq(FrameRate.next_mode(FrameRate.MODE_60), FrameRate.MODE_ECO)
	assert_eq(FrameRate.next_mode(FrameRate.MODE_ECO), FrameRate.MODE_MAX)
	assert_string_contains(FrameRate.label_for(FrameRate.MODE_MAX), "i/s")
	assert_string_contains(FrameRate.label_for(FrameRate.MODE_ECO), "éco")


func test_options_button_cycles_modes() -> void:
	FrameRate.apply(FrameRate.MODE_MAX, true)
	var panel := OptionsPanel.new()
	add_child_autofree(panel)
	await wait_process_frames(2)
	assert_not_null(panel.fps_button)
	panel.fps_button.pressed.emit()
	assert_eq(FrameRate.saved_mode(), FrameRate.MODE_60)
	assert_eq(Engine.max_fps, 60)
	assert_eq(panel.fps_button.text, "60 i/s")


func test_project_allows_120_and_interpolates() -> void:
	assert_true(int(ProjectSettings.get_setting("application/run/max_fps", 60)) >= 120 or
		int(ProjectSettings.get_setting("application/run/max_fps", 60)) == 0, "pas de plafond à 60 dans project.godot")
	assert_true(bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)),
		"interpolation physique : fluide à 120 i/s avec une logique à 60 pas/s")
