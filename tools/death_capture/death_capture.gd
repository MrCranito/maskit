extends SceneTree
## Captures de la séquence de mort (PR « mort lisible + jauge de vie ») : vrai raid Dust Creek
## à seed fixe, le joueur est abattu (« par Pistolero ») et la séquence est capturée.
##   godot --path . --resolution 1280x720 -s res://tools/death_capture/death_capture.gd -- --out=C:/dossier
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/death_capture/death_capture_driver.gd") as Script).new()
	driver.name = "DeathCaptureDriver"
	root.add_child(driver)
