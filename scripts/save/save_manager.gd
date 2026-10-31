extends Node
## Sauvegarde locale en JSON (profil, pass, réglages…), un seul fichier user://save.json.
## Chaque module y range sa clef (Profile → "profile", BattlePass → "battle_pass",
## MenuKit → "settings"). La clef "_cloud" est réservée à CloudSync (version, à pousser).
## `saved` est émis après chaque écriture : CloudSync s'en sert pour pousser au cloud.
## Écriture atomique : le JSON est écrit dans save.json.tmp, l'ancien fichier devient
## save.json.bak, puis le .tmp prend sa place. Un arrêt brutal pendant l'écriture (appli tuée,
## batterie) laisse donc toujours un fichier lisible ; au chargement, si save.json est illisible,
## la copie de secours est relue au lieu de repartir d'un profil vide.

signal saved

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BACKUP_PATH := "user://save.json.bak"

var data: Dictionary = {}


func save() -> void:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager : écriture impossible (%s)" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data, "	"))
	f.close()
	var main := ProjectSettings.globalize_path(SAVE_PATH)
	var backup := ProjectSettings.globalize_path(BACKUP_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.remove_absolute(backup)
		DirAccess.rename_absolute(main, backup)
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(TMP_PATH), main)
	if err != OK:
		push_error("SaveManager : remplacement de la sauvegarde impossible (%s)" % error_string(err))
	saved.emit()


func load_save() -> void:
	var parsed: Variant = _read(SAVE_PATH)
	if parsed == null:
		parsed = _read(BACKUP_PATH)
		if parsed != null:
			push_warning("SaveManager : save.json illisible, copie de secours relue")
	data = parsed if parsed is Dictionary else {}


## Contenu JSON d'un fichier de sauvegarde, ou null s'il est absent ou illisible.
static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()   # parse() ne journalise pas d'erreur moteur, contrairement à parse_string()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("SaveManager : %s illisible (%s, ligne %d)" % [path, json.get_error_message(), json.get_error_line()])
		return null
	return json.data if json.data is Dictionary else null


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
