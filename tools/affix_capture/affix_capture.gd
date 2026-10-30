extends SceneTree
## Captures des affixes d'armes (PR « affixes tirés au drop », phase 8) : arsenal de départ,
## arsenal (collection), sac de raid, statuts en jeu, écran de fin d'extraction.
##   godot --path . --resolution 1280x720 -s res://tools/affix_capture/affix_capture.gd -- --out=C:/dossier
## ÉCRIT DANS LE PROFIL : isoler la sauvegarde avec un override.cfg (non commité) :
##   [application] config/use_custom_user_dir=true / config/custom_user_dir_name="RaidersGo_affixcap"


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/affix_capture/affix_capture_driver.gd") as Script).new()
	driver.name = "AffixCaptureDriver"
	root.add_child(driver)
