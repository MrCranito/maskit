extends SceneTree
## Captures de l'occultation par les bâtiments (PR « fix/batiments-occlusion ») : lance un vrai
## raid à seed fixe sur une carte pré-rendue, place le joueur et un ennemi juste derrière (au
## nord) d'un grand bâtiment, et enregistre le viewport.
##   godot --path . --resolution 2000x923 -s res://tools/occlusion_capture/occlusion_capture.gd -- \
##       --out=C:/dossier/captures --map=dust|station|mall [--prefix=apres] [--no-fade]
## Isoler la sauvegarde : override.cfg (non commité) avec
##   [application] config/use_custom_user_dir=true / config/custom_user_dir_name="RaidersGo_batcap"
## Le scénario est dans occlusion_capture_driver.gd (chargé après les autoloads).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/occlusion_capture/occlusion_capture_driver.gd") as Script).new()
	driver.name = "OcclusionCaptureDriver"
	root.add_child(driver)
