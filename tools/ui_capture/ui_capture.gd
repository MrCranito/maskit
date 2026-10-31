extends SceneTree
## Captures d'écrans de menus (démarrage, menu principal, fin de raid) sans toucher au profil.
##   godot --path . --resolution 1280x720 -s res://tools/ui_capture/ui_capture.gd -- --out=C:/dossier
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/ui_capture/ui_capture_driver.gd") as Script).new()
	driver.name = "UiCaptureDriver"
	root.add_child(driver)
