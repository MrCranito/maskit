extends GutTest
## Menus : les scènes s'instancient, le choix du masque / de la difficulté met à jour
## GameState, la pause met l'arbre en pause, les crédits contiennent l'attribution CC BY.

const SCENES := [
	"res://scenes/ui/menus/splash.tscn",
	"res://scenes/ui/menus/main_menu.tscn",
	"res://scenes/ui/menus/mask_select.tscn",
	"res://scenes/ui/menus/pause_menu.tscn",
]

var _saved_mask: StringName = &"kitsune"
var _saved_diff: int = 1
var _saved_data: Dictionary = {}


func before_each() -> void:
	_saved_mask = GameState.selected_mask_id
	_saved_diff = GameState.difficulty
	_saved_data = SaveManager.data.duplicate(true)


func after_each() -> void:
	get_tree().paused = false
	GameState.selected_mask_id = _saved_mask
	GameState.difficulty = _saved_diff
	SaveManager.data = _saved_data
	SaveManager.save()


func test_main_scene_is_splash() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/ui/menus/splash.tscn")
	assert_eq(ProjectSettings.get_setting("application/boot_splash/image"), "res://assets/ui/splash/boot.png")
	assert_true(ResourceLoader.exists("res://assets/ui/splash/boot.png"))


func test_scenes_instantiate() -> void:
	for path: String in SCENES:
		assert_true(ResourceLoader.exists(path), path)
		var inst: Node = (load(path) as PackedScene).instantiate()
		assert_not_null(inst, path)
		if inst is SplashScreen:
			(inst as SplashScreen).auto_advance = false
		add_child_autofree(inst)
	await wait_frames(3)
	assert_true(true)


func test_splash_has_title_and_mask() -> void:
	var s := (load(SCENES[0]) as PackedScene).instantiate() as SplashScreen
	s.auto_advance = false
	add_child_autofree(s)
	await wait_frames(2)
	assert_eq(s.title_label.text, "Les Royaumes des Masques")
	assert_not_null(s.mask_rect.texture)
	assert_eq(s.next_scene, "res://scenes/ui/menus/main_menu.tscn")


func test_main_menu_buttons() -> void:
	var m := (load(SCENES[1]) as PackedScene).instantiate() as MainMenu
	add_child_autofree(m)
	await wait_frames(2)
	var labels: Array[String] = []
	for b: Button in m.buttons:
		labels.append(b.text)
		assert_gte(b.custom_minimum_size.y, 60.0, "Bouton tactile assez grand")
		assert_eq(b.focus_mode, Control.FOCUS_ALL, "Navigation manette/clavier")
	assert_eq(labels, ["Jouer", "Masques", "Options", "Crédits"] as Array[String])
	var opts := m.open_options() as OptionsPanel
	await wait_frames(2)
	assert_not_null(opts.music_slider)
	assert_not_null(opts.sfx_slider)
	assert_not_null(opts.vibration_toggle)
	opts.music_slider.value = 0.35
	assert_almost_eq(float(AudioManager.music_volume), 0.35, 0.001)
	assert_almost_eq(float(MenuKit.get_setting(&"music_volume", 0.0)), 0.35, 0.001)
	opts.vibration_toggle.button_pressed = false
	assert_false(bool(MenuKit.get_setting(&"vibration", true)))
	opts.close()


func test_credits_show_cc_by_attribution() -> void:
	var text := CreditsPanel.build_text()
	assert_string_contains(text, "game-icons.net")
	assert_string_contains(text, "CC BY 3.0")
	assert_string_contains(text, "Lorc")
	assert_string_contains(text, "Delapouite")
	assert_string_contains(text, "creativecommons.org/licenses/by/3.0")
	# Le texte doit être celui de CREDITS.md
	var credits_md := FileAccess.get_file_as_string("res://CREDITS.md")
	assert_string_contains(credits_md, CreditsPanel.ICONS_ATTRIBUTION)


func test_mask_select_updates_game_state() -> void:
	GameState.selected_mask_id = &"kitsune"
	var ms := (load(SCENES[2]) as PackedScene).instantiate() as MaskSelect
	ms.raid_scene = ""  # pas de changement de scène pendant le test
	add_child_autofree(ms)
	await wait_frames(3)
	assert_eq(ms.cards.size(), 5, "Une carte par masque")
	assert_eq(ms.current.id, &"kitsune", "Le masque porté est affiché au départ")
	assert_not_null(ms.preview.sprite, "Aperçu du héros 3D")
	assert_true(String(ms.preview.get_current_animation()).begins_with("idle_"))

	var spectre: MaskData = null
	for m: MaskData in ms.masks:
		if m.id == &"spectre":
			spectre = m
	ms.show_mask(spectre)
	assert_eq(ms.current, spectre)
	assert_eq(GameState.selected_mask_id, &"kitsune", "Afficher ne choisit pas")
	var panel := ms.choose_current()
	assert_eq(GameState.selected_mask_id, &"spectre", "« Choisir » met à jour GameState")
	assert_eq(String(SaveManager.data.get("selected_mask_id", "")), "spectre", "Choix sauvegardé")
	assert_not_null(panel, "Le choix de la difficulté s'ouvre")
	await wait_frames(2)
	assert_eq(panel.difficulty_buttons.size(), 5, "Facile → Cauchemar")
	panel.difficulty_buttons[4].button_pressed = true
	assert_eq(GameState.difficulty, 4)
	assert_eq(GameState.difficulty_name(GameState.difficulty), "Cauchemar")
	assert_eq(int(SaveManager.data.get("difficulty", -1)), 4)
	panel.set_difficulty(0)
	assert_eq(GameState.difficulty, 0)


func test_hero_preview_turns() -> void:
	var hp := HeroPreview.new()
	hp.size = Vector2(300, 260)
	add_child_autofree(hp)
	await wait_frames(1)
	var first := hp.get_current_animation()
	hp.call("_turn")
	assert_ne(hp.get_current_animation(), first, "L'aperçu change de direction")
	hp.set_mask(MaskData.load_mask(&"alchimiste"))
	assert_true(true)


func test_game_state_rejects_unknown_mask() -> void:
	GameState.selected_mask_id = &"kitsune"
	assert_false(GameState.set_selected_mask(&"nope", false))
	assert_eq(GameState.selected_mask_id, &"kitsune")
	GameState.set_difficulty(99, false)
	assert_eq(GameState.difficulty, 4, "Difficulté bornée")


func test_pause_menu_pauses_tree() -> void:
	var layer := CanvasLayer.new()
	add_child_autofree(layer)
	var pm := PauseMenu.attach(layer)
	await wait_frames(1)
	assert_eq(PauseMenu.attach(layer), pm, "Pas de doublon")
	assert_not_null(pm.pause_button)
	assert_false(pm.overlay.visible)
	pm.open()
	assert_true(get_tree().paused, "L'arbre est en pause")
	assert_true(pm.overlay.visible)
	assert_eq(pm.process_mode, Node.PROCESS_MODE_ALWAYS)
	pm.close()
	assert_false(get_tree().paused, "Reprendre relance le jeu")
	assert_false(pm.overlay.visible)
