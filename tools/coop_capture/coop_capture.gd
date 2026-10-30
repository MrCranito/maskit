extends SceneTree
## Captures des écrans coop sans réseau (coéquipier simulé) :
##   godot --path . --resolution 1280x720 -s res://tools/coop_capture/coop_capture.gd -- --out=C:/dossier [--only=fin]
## Groupes : fin (écrans de fin coop), menu (menu principal seul / avec coéquipier), salon (salon coop).
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/coop_capture/coop_capture_driver.gd") as Script).new()
	driver.name = "CoopCaptureDriver"
	root.add_child(driver)
