extends GutTest
## Bot de playtest (tools/playtest/playtest_bot.gd) : joue un raid court réel (Dust Creek,
## Normal) en mode intégré et produit un journal complet ; la sonde PlaytestProbe est coupée
## à la fin. Garde l'outil de la campagne de playtest en état de marche.

const BOT := "res://tools/playtest/playtest_bot.gd"

var _saved_profile: Dictionary = {}
var _saved_sm_data: Dictionary = {}
var _save_existed: bool = false
var _save_text: String = ""
var _saved_diff: int = 1
var _saved_map: Resource = null
var _saved_world: String = ""
var _saved_seed: int = 0


func before_each() -> void:
	_saved_profile = Profile.to_dict()
	_saved_sm_data = (SaveManager.data as Dictionary).duplicate(true)
	_save_existed = FileAccess.file_exists(SaveManager.SAVE_PATH)
	_save_text = FileAccess.get_file_as_string(SaveManager.SAVE_PATH) if _save_existed else ""
	_saved_diff = GameState.difficulty
	_saved_map = GameState.current_map
	_saved_world = GameState.world_path
	_saved_seed = GameState.run_seed


func after_each() -> void:
	PlaytestProbe.enabled = false
	PlaytestProbe.sink = null
	get_tree().paused = false
	Profile.from_dict(_saved_profile)
	SaveManager.data = _saved_sm_data
	GameState.difficulty = _saved_diff
	GameState.current_map = _saved_map
	GameState.world_path = _saved_world
	GameState.run_seed = _saved_seed
	GameState.raid_weapons.clear()
	if _save_existed:
		var f := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	elif FileAccess.file_exists(SaveManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.SAVE_PATH))


func test_le_bot_joue_un_raid_court() -> void:
	assert_false(PlaytestProbe.enabled, "Instrumentation coupée par défaut")
	var holder := Node.new()
	add_child_autofree(holder)
	var bot: Node = (load(BOT) as Script).new()
	bot.call(&"configure", {"mode": "raid", "map": "perm_dust_creek", "difficulty": 1, "profile": "agressif",
		"seed": 4242, "max_time": 12.0}, holder)
	add_child_autofree(bot)
	var got: Array = []
	bot.connect(&"finished", func(r: Dictionary) -> void: got.append(r))
	var frames := 0
	while got.is_empty() and frames < 60 * 40:
		await wait_physics_frames(1)
		frames += 1
	assert_eq(got.size(), 1, "Partie terminée (temps, mort ou extraction)")
	if got.is_empty():
		return
	var r: Dictionary = got[0]
	assert_true(["temps", "mort", "extraction"].has(String(r["outcome"])), "Issue valide : %s" % r["outcome"])
	assert_gt(float(r["duration"]), 0.5, "Le raid a tourné")
	for key: String in ["seed", "map", "difficulty", "profile", "arsenal", "damage_taken", "damage_dealt", "kills",
			"ttk", "items", "shots", "errors", "worst_frame_ms", "unreachable_containers"]:
		assert_true(r.has(key), "Journal : %s" % key)
	assert_eq(int(r["seed"]), 4242)
	assert_eq(r["arsenal"], ["pistol_p9", "smg_mp5"], "Arsenal débutant en Normal")
	assert_false(PlaytestProbe.enabled, "Sonde coupée en fin de partie")
