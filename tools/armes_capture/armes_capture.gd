extends SceneTree
## Captures « armes visibles partout » : héros du menu (seul, avec coéquipier), salon coop,
## boutique, planche des armes tenues par des coéquipiers (arme + skin d'arme synchronisés) et raid
## coop simulé (joueur + coéquipier, caméra rapprochée).
##   godot --path . --resolution 1280x720 -s res://tools/armes_capture/armes_capture.gd -- \
##       --out=C:/dossier [--only=menu,salon,boutique,planche,raid] [--prefix=avant_]
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/armes_capture/armes_capture_driver.gd") as Script).new()
	driver.name = "ArmesCaptureDriver"
	root.add_child(driver)
