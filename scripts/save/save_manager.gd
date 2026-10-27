extends Node
## Sauvegarde locale en JSON (réserve, masques, progression). Rempli en phase 6.

const SAVE_PATH := "user://save.json"

var data: Dictionary = {}


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		data = {}
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	data = parsed if parsed is Dictionary else {}
