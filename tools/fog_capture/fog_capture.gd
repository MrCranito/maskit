extends SceneTree
## Captures du brouillard (PR « brouillard moderne ») : lance un vrai raid Dust Creek à seed
## fixe, sans toucher au profil (pas de Profile.start_raid), et enregistre le viewport.
##   godot --path . --resolution 1280x720 -s res://tools/fog_capture/fog_capture.gd -- \
##       --out=C:/dossier/captures [--style=darkened|mist] [--prefix=a]
## Isoler la sauvegarde : override.cfg (non commité) avec
##   [application] config/use_custom_user_dir=true / config/custom_user_dir_name="RaidersGo_fogcap"
## Le scénario est dans fog_capture_driver.gd (chargé après les autoloads).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/fog_capture/fog_capture_driver.gd") as Script).new()
	driver.name = "FogCaptureDriver"
	root.add_child(driver)
