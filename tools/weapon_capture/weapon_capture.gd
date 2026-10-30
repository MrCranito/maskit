extends SceneTree
## Captures des armes (PR « catalogue de la phase 8 ») : écran d'arsenal, puis un vrai raid
## Dust Creek à seed fixe où le joueur tire avec des armes données, sans toucher au profil.
##   godot --path . --resolution 1280x720 -s res://tools/weapon_capture/weapon_capture.gd -- \
##       --out=C:/dossier/captures [--weapons=revolver_python,shotgun_870] [--dirs]
## Isoler la sauvegarde : override.cfg (non commité) avec
##   [application] config/use_custom_user_dir=true / config/custom_user_dir_name="RaidersGo_wpncap"
## Le scénario est dans weapon_capture_driver.gd (chargé après les autoloads).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/weapon_capture/weapon_capture_driver.gd") as Script).new()
	driver.name = "WeaponCaptureDriver"
	root.add_child(driver)
