extends GutTest
## Vérifie que les assets tiers (audio, polices, icônes) sont présents et se chargent.

const AudioManagerScript := preload("res://scripts/core/audio_manager.gd")

const FONTS: Array[String] = [
	"res://assets/fonts/rye/Rye-Regular.ttf",
	"res://assets/fonts/nunito/Nunito-Variable.ttf",
]

const ICONS_DIR := "res://assets/third_party/icons/"


func test_tous_les_sons_se_chargent() -> void:
	var paths: PackedStringArray = AudioManagerScript.all_paths()
	assert_gt(paths.size(), 50, "la table audio doit contenir des sons")
	for path: String in paths:
		assert_true(ResourceLoader.exists(path), "fichier audio manquant : %s" % path)
		var stream := load(path) as AudioStream
		assert_not_null(stream, "impossible de charger : %s" % path)
		if stream != null:
			assert_gt(stream.get_length(), 0.0, "son vide : %s" % path)


func test_musiques_en_boucle() -> void:
	for key: StringName in AudioManagerScript.MUSIC:
		var stream := load(AudioManagerScript.MUSIC[key]) as AudioStreamOggVorbis
		assert_not_null(stream, "musique non chargée : %s" % key)
		if stream != null:
			assert_true(stream.loop, "la musique doit boucler : %s" % key)


func test_sons_ne_bouclent_pas() -> void:
	for key: StringName in AudioManagerScript.SFX:
		if key == &"desert_wind" or key == &"steps_loop":
			continue
		for path: String in AudioManagerScript.SFX[key]:
			var stream := load(path) as AudioStreamOggVorbis
			if stream != null:
				assert_false(stream.loop, "un effet ne doit pas boucler : %s" % path)


func test_polices_se_chargent() -> void:
	for path: String in FONTS:
		var font := load(path) as FontFile
		assert_not_null(font, "police non chargée : %s" % path)


func test_icones_se_chargent() -> void:
	var files := DirAccess.get_files_at(ICONS_DIR)
	var count := 0
	for f: String in files:
		if f.ends_with(".svg"):
			count += 1
			var tex := load(ICONS_DIR + f) as Texture2D
			assert_not_null(tex, "icône non chargée : %s" % f)
	assert_gt(count, 40, "au moins 40 icônes attendues")


func test_audio_manager_api() -> void:
	var am: Node = AudioManagerScript.new()
	add_child_autofree(am)
	assert_true(am.has_sfx(&"revolver_shot"))
	assert_false(am.has_sfx(&"inexistant"))
	assert_true(am.play_sfx(&"click"))
	assert_true(am.play_sfx(&"golem_stomp", Vector2(10, 10)))
	assert_true(am.play_music(&"western_explore", false))
	am.stop_music(false)
