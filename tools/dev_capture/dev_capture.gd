extends SceneTree
## Captures du mode développeur : fenêtre Options (section dev), panneau F3, choix des cartes,
## arsenal et pass de combat avec « Tout débloquer ».
##   godot --path . --resolution 1280x720 -s res://tools/dev_capture/dev_capture.gd -- --out=C:/dossier [--unlock=1] [--prefix=xxx]
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.



func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/dev_capture/dev_capture_driver.gd") as Script).new()
	driver.name = "DevCaptureDriver"
	root.add_child(driver)
