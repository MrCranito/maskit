extends SceneTree
## Captures du HUD compact (PR « HUD moderne ») : vrai raid Dust Creek à seed fixe, sticks
## affichés, joueur avec 1, 2 puis 3 armes + équipement + soins en emplacements rapides,
## rechargement en cours, déplacement sans viser dans 4 directions (tenue de l'arme).
##   godot --path . --resolution 1560x720 -s res://tools/hud_capture/hud_capture.gd -- \
##       --out=C:/dossier/captures --tag=1560x720
## (1280x720 = PC, 1560x720 = téléphone 2000×923, 1600x720 = téléphone 2400×1080 : le viewport
## fait toujours 720 de haut.) Isoler la sauvegarde : override.cfg (non commité) avec
##   [application] config/use_custom_user_dir=true / config/custom_user_dir_name="RaidersGo_hudcap"


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/hud_capture/hud_capture_driver.gd") as Script).new()
	driver.name = "HudCaptureDriver"
	root.add_child(driver)
