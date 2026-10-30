extends SceneTree
## Captures de la carte plein écran zoomable (PR « carte zoom ») : vrai raid Dust Creek à seed
## fixe, quelques déplacements pour explorer, puis carte entière, recentrage zoomé sur le
## joueur, zoom max, déplacement vers une extraction.
##   godot --path . --resolution 1560x720 -s res://tools/map_zoom_capture/map_zoom_capture.gd -- --out=C:/dossier [--tag=1560x720]
## (1280x720 = PC, 1560x720 = téléphone 2000×923.) Isoler la sauvegarde : override.cfg (non commité),
## voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/map_zoom_capture/map_zoom_capture_driver.gd") as Script).new()
	driver.name = "MapZoomCaptureDriver"
	root.add_child(driver)
