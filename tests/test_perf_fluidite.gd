extends GutTest
## perf/fluidite : préchauffe du raid (RaidWarmup), overlay de mesure (PerfOverlay), banc rejouable.


func test_warmup_fills_loot_db_and_audio_cache() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var w := RaidWarmup.start(host)
	assert_not_null(w, "préchauffe active ([warmup] enabled)")
	# Sous --headless : objets chargés tout de suite (chargement en fil non sûr pour les textures).
	assert_true(LootDB._items_loaded, "LootDB rempli avant le premier butin")
	assert_gt(LootDB.all_items().size(), 10)
	var done := false
	for i: int in 600:
		await wait_process_frames(1)
		if w.is_done():
			done = true
			break
	assert_true(done, "préchauffe terminée")
	var cache: Dictionary = AudioManager.get("_cache")
	var paths: PackedStringArray = AudioManager.all_sfx_paths()
	assert_gt(paths.size(), 10)
	var cached := 0
	for p: String in paths:
		if cache.has(p):
			cached += 1
	assert_eq(cached, paths.size(), "tous les sons en cache : plus de load() au premier tir")


func test_warmup_balance_settings() -> void:
	assert_true(bool(Balance.get_value("warmup", "enabled", false)))
	assert_gt(int(Balance.get_value("warmup", "icons_per_frame", 0)), 0)


func test_perf_overlay_text() -> void:
	var o := PerfOverlay.new()
	add_child_autofree(o)
	o.set_shown(true)
	await wait_process_frames(5)
	var txt := o.build_text()
	assert_string_contains(txt, "i/s")
	assert_string_contains(txt, "Saccades")
	assert_string_contains(txt, "max_fps")
	o.toggle()
	assert_false(o.visible)


func test_perf_bench_scripts_exist() -> void:
	assert_true(ResourceLoader.exists("res://tools/perf_bench/perf_bench_main.gd"))
	assert_true(ResourceLoader.exists("res://tools/perf_bench/perf_recorder.gd"))
