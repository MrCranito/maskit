extends SceneTree
## Captures des zones d'extraction à durée de vie (PR « extractions multiples ») : vrai raid à
## seed fixe, joueur posé près des zones, horloge du raid avancée.
##   godot --path . --resolution 2000x923 -s res://tools/extraction_capture/zones_capture.gd -- --out=C:/dossier [--map=res://data/maps/perm_dust_creek.tres] [--before]
## --before : [extraction] timed_zones=false (comportement d'avant : zones toujours ouvertes).
## Isoler la sauvegarde : override.cfg (non commité), voir tools/fog_capture/fog_capture.gd.


func _init() -> void:
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	var driver: Node = (load("res://tools/extraction_capture/zones_capture_driver.gd") as Script).new()
	driver.name = "ZonesCaptureDriver"
	root.add_child(driver)
