extends GutTest
## Sauvegarde atomique (SaveManager) : jamais de fichier à moitié écrit, copie de secours relue
## quand save.json est illisible (au lieu de repartir d'un profil vide).

var _backup: Dictionary = {}


func before_each() -> void:
	_backup = {}
	for p: String in [SaveManager.SAVE_PATH, SaveManager.BACKUP_PATH, SaveManager.TMP_PATH]:
		if FileAccess.file_exists(p):
			_backup[p] = FileAccess.get_file_as_string(p)
	_backup["_data"] = SaveManager.data.duplicate(true)


func after_each() -> void:
	for p: String in [SaveManager.SAVE_PATH, SaveManager.BACKUP_PATH, SaveManager.TMP_PATH]:
		if _backup.has(p):
			_write(p, _backup[p])
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	SaveManager.data = _backup["_data"]


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_save_writes_readable_file_and_backup_without_tmp() -> void:
	SaveManager.data = {"profile": {"gems": 1}}
	SaveManager.save()
	SaveManager.data = {"profile": {"gems": 2}}
	SaveManager.save()
	assert_false(FileAccess.file_exists(SaveManager.TMP_PATH), "pas de .tmp qui traîne")
	var main: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
	var bak: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.BACKUP_PATH))
	assert_eq(int(main["profile"]["gems"]), 2, "save.json = dernière écriture")
	assert_eq(int(bak["profile"]["gems"]), 1, "save.json.bak = écriture précédente")


func test_corrupted_save_falls_back_to_backup() -> void:
	# Cas vu en test : JSON valide suivi d'un reste d'ancien contenu (« Expected 'EOF' »).
	_write(SaveManager.SAVE_PATH, "{\"profile\": {\"gems\": 5}}\n\t}\n}")
	_write(SaveManager.BACKUP_PATH, "{\"profile\": {\"gems\": 4}}")
	SaveManager.load_save()
	assert_eq(int(SaveManager.data["profile"]["gems"]), 4, "copie de secours relue")


func test_both_unreadable_gives_empty_data() -> void:
	_write(SaveManager.SAVE_PATH, "{tronqué")
	if FileAccess.file_exists(SaveManager.BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.BACKUP_PATH))
	SaveManager.load_save()
	assert_eq(SaveManager.data, {}, "rien de lisible : profil vide comme avant")
