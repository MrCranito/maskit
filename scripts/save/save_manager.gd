extends Node
## Sauvegarde locale en JSON (profil, pass, réglages…), un seul fichier user://save.json.
## Chaque module y range sa clef (Profile → "profile", BattlePass → "battle_pass",
## MenuKit → "settings"). La clef "_cloud" est réservée à CloudSync (version, à pousser).
## `saved` est émis après chaque écriture : CloudSync s'en sert pour pousser au cloud.

signal saved

const SAVE_PATH := "user://save.json"

var data: Dictionary = {}


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
	saved.emit()


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		data = {}
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	data = parsed if parsed is Dictionary else {}


## Remplace toute la sauvegarde (restauration depuis le cloud) et l'écrit sur le disque,
## puis recharge les modules qui en dépendent (Profile, BattlePass, réglages).
func replace_data(new_data: Dictionary) -> void:
	data = new_data.duplicate(true)
	save()
	var profile: Node = get_node_or_null(^"/root/Profile")
	if profile != null and profile.has_method("_load"):
		profile.call("_load")
	var pass_node: Node = get_node_or_null(^"/root/BattlePass")
	if pass_node != null and pass_node.has_method("_load"):
		pass_node.call("_load")
	MenuKit.apply_saved_settings()
