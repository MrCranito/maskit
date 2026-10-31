extends SceneTree
## Captures de l'éclairage d'ambiance (PR « lumières de la station ») : raid à seed fixe,
## étages demandés, plus grandes salles (IA gelée).
##   godot --path . --resolution 1280x720 -s res://tools/light_capture/light_capture.gd -- \
##       --out=C:/dossier/captures [--prefix=apres] [--map=perm_station_kagami] [--floors=0,-1,1] [--rooms=2]
## Isoler la sauvegarde : override.cfg (non commité) avec un dossier utilisateur dédié.
## Le scénario est dans light_capture_driver.gd (chargé après les autoloads).


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/light_capture/light_capture_driver.gd") as Script).new()
	driver.name = "LightCaptureDriver"
	root.add_child(driver)
