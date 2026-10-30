extends SceneTree
## Captures de l'extraction (PR « animation d'extraction ») : vrai raid Dust Creek à seed fixe,
## joueur posé sur une zone d'extraction, captures pendant la canalisation et la sortie.
##   godot --path . --resolution 1280x720 -s res://tools/extraction_capture/extraction_capture.gd -- --out=C:/dossier
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/extraction_capture/extraction_capture_driver.gd") as Script).new()
	driver.name = "ExtractionCaptureDriver"
	root.add_child(driver)
