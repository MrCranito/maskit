extends SceneTree
## Captures de l'arène de test (mode dev) : vue de l'arène, mannequins touchés, panneau ouvert
## avec des ennemis apparus, et vignette dans le choix des cartes.
##   godot --path . --resolution 1280x720 -s res://tools/arena_capture/arena_capture.gd -- --out=C:/dossier
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/arena_capture/arena_capture_driver.gd") as Script).new()
	driver.name = "ArenaCaptureDriver"
	root.add_child(driver)